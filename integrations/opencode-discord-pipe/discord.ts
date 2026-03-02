/**
 * opencode-discord-pipe — Discord sender
 *
 * Posts messages to Discord channels via bot token HTTP API.
 * Supports thread creation and thread-scoped messaging.
 */

import { DISCORD_BOT_TOKEN, MAX_DISCORD_MSG } from './config.ts';

const DISCORD_API = 'https://discord.com/api/v10';

/** Queue to serialize sends per channel and avoid rate limits */
export const channelQueues = new Map<string, Promise<void>>();

/** Track created threads: Map<channelId:sessionId, threadId> */
const threadCache = new Map<string, string>();

/** In-flight thread creation promises to prevent duplicate threads (TOCTOU race) */
const threadCreationLocks = new Map<string, Promise<string | null>>();

interface SendOptions {
  channelId: string;
  content: string;
  threadId?: string;
}

interface ThreadOptions {
  channelId: string;
  name: string;
  firstMessage: string;
  autoArchiveMin?: number;
}

const MAX_RETRIES = 5;

async function apiCall(method: string, path: string, body?: any, retryCount = 0): Promise<any> {
  if (!DISCORD_BOT_TOKEN) {
    console.log(`[discord] DRY-RUN ${method} ${path}`, body ? JSON.stringify(body).slice(0, 200) : '');
    return null;
  }

  const url = `${DISCORD_API}${path}`;
  const res = await fetch(url, {
    method,
    headers: {
      'Authorization': `Bot ${DISCORD_BOT_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (res.status === 429) {
    if (retryCount >= MAX_RETRIES) {
      console.error(`[discord] Rate limit exceeded after ${MAX_RETRIES} retries, dropping message`);
      return null;
    }
    const data = await res.json() as { retry_after?: number };
    const wait = (data.retry_after || 1) * 1000;
    console.warn(`[discord] Rate limited (attempt ${retryCount + 1}/${MAX_RETRIES}), waiting ${wait}ms`);
    await new Promise(r => setTimeout(r, wait));
    return apiCall(method, path, body, retryCount + 1);
  }

  if (!res.ok) {
    const text = await res.text();
    console.error(`[discord] ${method} ${path} failed: ${res.status} ${text}`);
    return null;
  }

  // Return JSON if there's content
  const contentType = res.headers.get('content-type');
  if (contentType?.includes('application/json')) {
    return res.json();
  }
  return null;
}

function truncate(content: string): string {
  if (content.length <= MAX_DISCORD_MSG) return content;
  return content.slice(0, MAX_DISCORD_MSG - 20) + '\n… *(truncated)*';
}

/**
 * Create a thread from a message in a channel.
 */
export async function createThread(opts: ThreadOptions): Promise<string | null> {
  const { channelId, name, firstMessage, autoArchiveMin = 1440 } = opts;

  // Truncate thread name to Discord's 100 char limit
  const threadName = name.length > 100 ? name.slice(0, 97) + '...' : name;

  // First, send the "anchor" message that the thread will be created from
  const msg = await apiCall('POST', `/channels/${channelId}/messages`, {
    content: truncate(firstMessage),
    allowed_mentions: { parse: [] },
  });

  if (!msg?.id) {
    console.error(`[discord] Failed to create anchor message for thread in ${channelId}`);
    // Fallback: just send without thread
    return null;
  }

  // Create thread from the message
  const thread = await apiCall('POST', `/channels/${channelId}/messages/${msg.id}/threads`, {
    name: threadName,
    auto_archive_duration: autoArchiveMin,
  });

  if (!thread?.id) {
    console.error(`[discord] Failed to create thread from message ${msg.id}`);
    return null;
  }

  console.log(`[discord] Created thread "${threadName}" (${thread.id}) in channel ${channelId}`);
  return thread.id;
}

/**
 * Send a message to a channel or thread.
 */
async function sendRaw(opts: SendOptions): Promise<void> {
  const { channelId, content, threadId } = opts;
  const targetId = threadId || channelId;

  await apiCall('POST', `/channels/${targetId}/messages`, {
    content: truncate(content),
    allowed_mentions: { parse: [] },
  });
}

/**
 * Send a message, serialized per-channel.
 */
export async function send(channelId: string, content: string, threadId?: string): Promise<void> {
  const queueKey = threadId || channelId;
  const prev = channelQueues.get(queueKey) || Promise.resolve();
  const next = prev.then(() => sendRaw({ channelId, content, threadId })).catch(err => {
    console.error(`[discord] Send error: ${err.message}`);
  });
  channelQueues.set(queueKey, next);
  return next;
}

/**
 * Send multiple chunks if content exceeds Discord's limit.
 */
export async function sendChunked(channelId: string, content: string, threadId?: string): Promise<void> {
  if (content.length <= MAX_DISCORD_MSG) {
    return send(channelId, content, threadId);
  }

  const chunks: string[] = [];
  let current = '';

  for (const line of content.split('\n')) {
    if ((current + '\n' + line).length > MAX_DISCORD_MSG - 50) {
      if (current) chunks.push(current);
      current = line;
    } else {
      current = current ? current + '\n' + line : line;
    }
  }
  if (current) chunks.push(current);

  for (let i = 0; i < chunks.length; i++) {
    const prefix = chunks.length > 1 ? `*(${i + 1}/${chunks.length})*\n` : '';
    await send(channelId, prefix + chunks[i], threadId);
  }
}

// ─── Thread Management ───────────────────────────────────────────────────────

/**
 * Get or create a thread for a session in a given channel.
 * Returns the thread ID, or null if thread creation failed (falls back to channel).
 */
export async function getOrCreateSessionThread(
  channelId: string,
  sessionId: string,
  sessionSlug: string,
  sessionTitle: string,
  firstMessage: string,
): Promise<string | null> {
  const cacheKey = `${channelId}:${sessionId}`;

  // Check cache — thread already created
  const cached = threadCache.get(cacheKey);
  if (cached) return cached;

  // Check if another call is already creating this thread (prevent TOCTOU race)
  const inflight = threadCreationLocks.get(cacheKey);
  if (inflight) return inflight;

  // Create thread — store the promise so concurrent calls await the same creation
  const threadName = `${sessionSlug} — ${sessionTitle || 'session'}`;
  const createPromise = createThread({
    channelId,
    name: threadName,
    firstMessage,
    autoArchiveMin: 1440, // 24h auto-archive
  }).then(threadId => {
    if (threadId) {
      threadCache.set(cacheKey, threadId);
    }
    threadCreationLocks.delete(cacheKey);
    return threadId;
  }).catch(err => {
    threadCreationLocks.delete(cacheKey);
    console.error(`[discord] Thread creation failed: ${err.message}`);
    return null;
  });

  threadCreationLocks.set(cacheKey, createPromise);
  return createPromise;
}

/**
 * Clear thread cache for a session.
 * NOTE: Intentionally keeps thread references even after session completes,
 * because late-arriving events (e.g., final step-finish after session.idle)
 * still need the thread ID. The thread cache is lightweight (string→string)
 * and entries are effectively bounded by total sessions seen.
 */
export function clearSessionThreads(_sessionId: string): void {
  // No-op by design. See comment above.
}

/**
 * Get cached thread ID if it exists.
 */
export function getCachedThread(channelId: string, sessionId: string): string | undefined {
  return threadCache.get(`${channelId}:${sessionId}`);
}
