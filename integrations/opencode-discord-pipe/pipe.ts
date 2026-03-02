#!/usr/bin/env npx tsx
/**
 * opencode-discord-pipe v2.2 — Main SSE listener & router
 *
 * Connects to OpenCode's SSE event stream and routes events to Discord channels.
 * Groups events per session into Discord threads.
 *
 * Usage:
 *   npx tsx pipe.ts
 *   DISCORD_BOT_TOKEN=xxx npx tsx pipe.ts
 *
 * Changelog v2.2:
 *   - Sanitize tool inputs (bash commands, URLs, generic values)
 *   - Sanitize diff content (before/after file contents)
 *   - Wire LONG_TOKEN_PATTERN into sanitization (40+ char hex/base64 strings)
 *   - Neutralize @everyone/@here mentions in all output
 *   - Remove dead formatSessionBusy export
 *   - Fix session cleanup: track _lastSeen locally as fallback
 *   - Fix shutdown drain: remove misleading while/break structure
 *   - Rename formatUnifiedDiff → formatNaiveDiff (honest about limitations)
 *
 * Changelog v2.1:
 *   - Fixed sendToSession dropping first message after thread creation
 *   - Fixed connectSSE recursive stack growth (now uses while loop)
 *   - Fixed memory leaks in postedParts/pendingTools cleanup
 *   - Added graceful shutdown with signal handlers
 *   - Added tool output sanitization
 */

import {
  OPENCODE_URL,
  CHANNELS,
  IGNORED_EVENT_TYPES,
  SSE_RECONNECT_DELAY_MS,
  SSE_MAX_RECONNECT_DELAY_MS,
  TEXT_DEBOUNCE_MS,
  DISCORD_BOT_TOKEN,
} from './config.ts';

import {
  sendChunked,
  getOrCreateSessionThread,
  getCachedThread,
  channelQueues,
} from './discord.ts';

import {
  formatSessionCreated,
  formatSessionIdle,
  formatUserMessage,
  formatAgentText,
  formatReasoning,
  formatToolCall,
  formatDiffs,
  formatStepFinish,
  sanitizeOutput,
} from './formatter.ts';

// ─── State ───────────────────────────────────────────────────────────────────

/** Tracked session info, keyed by session ID */
const sessions = new Map<string, any>();

/** Pending text debounce timers */
const textTimers = new Map<string, ReturnType<typeof setTimeout>>();

/** Track which parts we've already posted, with timestamps for cleanup */
const postedParts = new Map<string, number>(); // partKey → timestamp

/** Track pending tool parts, with session ID for scoped cleanup */
const pendingTools = new Map<string, { part: any; sessionId: string; addedAt: number }>();

/** Flag for graceful shutdown */
let shuttingDown = false;

/** Current SSE AbortController for shutdown */
let sseController: AbortController | null = null;

// ─── Thread Helpers ──────────────────────────────────────────────────────────

/**
 * Get thread ID for a session in a channel. Creates thread on first use.
 * Returns { threadId, justCreated } so callers can avoid double-posting.
 */
async function getThread(
  channelId: string,
  sessionId: string,
  firstMessage: string,
): Promise<{ threadId: string | undefined; justCreated: boolean }> {
  const session = sessions.get(sessionId);
  if (!session) return { threadId: undefined, justCreated: false };

  // Check if thread already exists
  const cached = getCachedThread(channelId, sessionId);
  if (cached) return { threadId: cached, justCreated: false };

  // Create thread — firstMessage becomes the anchor
  const slug = session.slug || sessionId.slice(0, 12);
  const title = session.title || 'Session';
  const threadId = await getOrCreateSessionThread(
    channelId,
    sessionId,
    slug,
    title,
    firstMessage,
  );

  return { threadId: threadId || undefined, justCreated: !!threadId };
}

/**
 * Send to a channel thread (subsequent messages after thread creation).
 * If no thread exists yet, creates one with this content as the anchor.
 */
async function sendToSessionThread(
  channelId: string,
  sessionId: string,
  content: string,
): Promise<void> {
  const threadId = getCachedThread(channelId, sessionId);
  if (threadId) {
    await sendChunked(channelId, content, threadId);
  } else {
    // No thread yet — create one with this as the first message
    // Content becomes the anchor, no need to send again
    await getThread(channelId, sessionId, content);
  }
}

// ─── SSE Connection ──────────────────────────────────────────────────────────

let reconnectDelay = SSE_RECONNECT_DELAY_MS;

/**
 * Main SSE connection loop. Uses while(true) instead of recursion
 * to avoid stack growth over long uptimes.
 */
async function connectSSE(): Promise<void> {
  while (!shuttingDown) {
    const url = `${OPENCODE_URL}/event`;
    console.log(`[pipe] Connecting to SSE: ${url}`);
    console.log(`[pipe] Discord mode: ${DISCORD_BOT_TOKEN ? 'LIVE (bot token)' : 'DRY-RUN (stdout only)'}`);

    try {
      sseController = new AbortController();
      const response = await fetch(url, {
        headers: { 'Accept': 'text/event-stream' },
        signal: sseController.signal,
      });

      if (!response.ok) {
        throw new Error(`SSE connection failed: ${response.status} ${response.statusText}`);
      }

      if (!response.body) {
        throw new Error('SSE response has no body');
      }

      console.log('[pipe] SSE connected');
      reconnectDelay = SSE_RECONNECT_DELAY_MS;

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (!shuttingDown) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });

        const messages = buffer.split('\n\n');
        buffer = messages.pop() || '';

        for (const msg of messages) {
          if (!msg.trim()) continue;

          const dataLines = msg.split('\n')
            .filter(l => l.startsWith('data: '))
            .map(l => l.slice(6));

          for (const dataStr of dataLines) {
            try {
              const event = JSON.parse(dataStr);
              await handleEvent(event);
            } catch (err: any) {
              if (dataStr && !dataStr.startsWith('{')) {
                console.error(`[pipe] Failed to parse SSE data: ${err.message}`);
              } else {
                console.error(`[pipe] Event handler error: ${err.message}`);
              }
            }
          }
        }
      }

      console.log('[pipe] SSE stream ended');
    } catch (err: any) {
      if (err.name === 'AbortError') {
        if (shuttingDown) {
          console.log('[pipe] SSE aborted for shutdown');
          break;
        }
      } else {
        console.error(`[pipe] SSE error: ${err.message}`);
      }
    }

    if (shuttingDown) break;

    console.log(`[pipe] Reconnecting in ${reconnectDelay}ms...`);
    await new Promise(r => setTimeout(r, reconnectDelay));
    reconnectDelay = Math.min(reconnectDelay * 1.5, SSE_MAX_RECONNECT_DELAY_MS);
  }
}

// ─── Event Router ────────────────────────────────────────────────────────────

async function handleEvent(event: any): Promise<void> {
  const type = event.type as string;
  if (!type || IGNORED_EVENT_TYPES.has(type)) return;

  const props = event.properties || {};

  switch (type) {
    case 'server.connected':
      console.log('[pipe] Server connected event received');
      break;
    case 'session.created':
      await handleSessionCreated(props);
      break;
    case 'session.updated':
      handleSessionUpdated(props);
      break;
    case 'session.status':
      handleSessionStatus(props);
      break;
    case 'session.idle':
      await handleSessionIdle(props);
      break;
    case 'session.diff':
      await handleSessionDiff(props);
      break;
    case 'message.updated':
      handleMessageUpdated(props);
      break;
    case 'message.part.updated':
      await handleMessagePartUpdated(props);
      break;
    case 'question.asked':
      await handleQuestionAsked(props);
      break;
    // Known noise events — ignore silently
    case 'file.edited':
    case 'file.watcher.updated':
    case 'lsp.updated':
    case 'lsp.client.diagnostics':
    case 'server.heartbeat':
    case 'todo.updated':
      break;
    default:
      console.log(`[pipe] Unknown event: ${type}`);
      break;
  }
}

// ─── Event Handlers ──────────────────────────────────────────────────────────

async function handleSessionCreated(props: any): Promise<void> {
  const info = props.info;
  if (!info?.id) return;

  sessions.set(info.id, { ...info, messages: {}, _lastSeen: Date.now() });

  // Post session creation to status channel — this creates the thread
  const msg = formatSessionCreated(info);
  await getThread(CHANNELS.status, info.id, msg);
}

function handleSessionUpdated(props: any): void {
  const info = props.info;
  if (!info?.id) return;

  const existing = sessions.get(info.id) || { messages: {} };
  sessions.set(info.id, {
    ...existing,
    ...info,
    messages: existing.messages,
    _lastSeen: Date.now(),
  });
}

function handleSessionStatus(props: any): void {
  const sessionId = props.sessionID;
  const status = props.status?.type;
  if (!sessionId || !status) return;

  const session = sessions.get(sessionId);
  if (session) {
    session._lastStatus = status;
    session._lastSeen = Date.now();
  }
}

async function handleSessionIdle(props: any): Promise<void> {
  const sessionId = props.sessionID;
  if (!sessionId) return;

  const msg = formatSessionIdle(sessionId, sessions);
  await sendToSessionThread(CHANNELS.status, sessionId, msg);
}

async function handleSessionDiff(props: any): Promise<void> {
  const sessionId = props.sessionID;
  const diffs = props.diff;
  if (!sessionId || !Array.isArray(diffs) || diffs.length === 0) return;

  const msg = formatDiffs(sessionId, diffs, sessions);
  if (msg) await sendToSessionThread(CHANNELS.diffs, sessionId, msg);
}

async function handleQuestionAsked(props: any): Promise<void> {
  const sessionId = props.sessionID;
  const questionSetId = props.id;

  // Normalize questions to array with defensive type check
  const rawQuestions = props.questions || (props.question ? [props.question] : []);
  const questions = Array.isArray(rawQuestions) ? rawQuestions.filter(Boolean) : [];
  
  if (!sessionId || questions.length === 0) {
    // Log only metadata, not full props
    console.log(`[pipe] question.asked missing sessionId or questions — sessionId=${sessionId}, hasQuestions=${questions.length > 0}`);
    return;
  }

  const session = sessions.get(sessionId);
  // Sanitize metadata fields — slug/title can be user-controlled
  const slug = sanitizeOutput(session?.slug || sessionId.slice(0, 12)).slice(0, 50);
  const title = sanitizeOutput(session?.title || 'Session').slice(0, 100);

  // Format all questions for Discord (with full sanitization)
  const questionBlocks = questions.map((q: any, idx: number) => {
    if (q == null) return '';
    const rawText = typeof q === 'string' ? q : (q.question || q.text || q.message || '');
    const questionText = typeof rawText === 'string' 
      ? sanitizeOutput(rawText).slice(0, 500)
      : '[REDACTED_NON_STRING]';
    // Sanitize header — could contain secrets or @mentions
    const header = sanitizeOutput(
      typeof q === 'string' ? `Question ${idx + 1}` : (q.header || `Question ${idx + 1}`)
    ).slice(0, 100);
    const options = (q != null && typeof q === 'object' && Array.isArray(q.options)) ? q.options : [];
    const optionsText = options.length > 0 
      ? options.filter(Boolean).map((o: any, i: number) => {
          const optText = typeof o === 'string' 
            ? sanitizeOutput(o).slice(0, 100)
            : sanitizeOutput(String(o?.label || o?.value || '[REDACTED]')).slice(0, 100);
          return `    ${i + 1}. ${optText}`;
        }).join('\n')
      : '';
    
    return [
      `### ${header}`,
      `> ${questionText}`,
      optionsText ? `**Options:**\n${optionsText}` : '',
    ].filter(Boolean).join('\n');
  }).filter(Boolean).join('\n\n');
  
  const msg = [
    `## ❓ Questions from ${slug}`,
    `**Session:** ${title}`,
    `**Question Set ID:** \`${sanitizeOutput(String(questionSetId || 'N/A')).slice(0, 50)}\``,
    '',
    questionBlocks,
    '',
    `💡 **To answer:** Reply in Discord or use the OpenCode API`,
  ].filter(Boolean).join('\n');

  // Post to agent channel (visible in Discord)
  await sendToSessionThread(CHANNELS.agent, sessionId, msg);
  
  // Log only metadata, not question text (prevents secret leakage)
  console.log(`[pipe] QUESTION ESCALATION — Session: ${sessionId}, Questions: ${questions.length}`);
  questions.forEach((q: any, i: number) => {
    const textLength = typeof q === 'string' ? q.length : (q?.question || q?.text || q?.message || '').length || 0;
    console.log(`[ESCALATE:QUESTION] session=${sessionId} qid=${questionSetId} idx=${i} text_length=${textLength}`);
  });
}

function handleMessageUpdated(props: any): void {
  const info = props.info;
  if (!info?.id || !info?.sessionID) return;

  const session = sessions.get(info.sessionID);
  if (!session) return;

  if (!session.messages) session.messages = {};
  session.messages[info.id] = { ...session.messages[info.id], ...info };
}

async function handleMessagePartUpdated(props: any): Promise<void> {
  const part = props.part;
  const delta = props.delta;
  if (!part?.id || !part?.type) return;

  const partKey = part.id;
  const sessionId = part.sessionID;

  switch (part.type) {
    case 'text': {
      const session = sessions.get(sessionId);
      const msg = session?.messages?.[part.messageID];
      if (!msg) return;

      // User messages (prompts) — post on first sight (no streaming, no end timestamp)
      if (msg.role === 'user') {
        if (!postedParts.has(partKey) && part.text?.trim()) {
          postedParts.set(partKey, Date.now());
          const formatted = formatUserMessage(part, sessions);
          if (formatted) await sendToSessionThread(CHANNELS.agent, sessionId, formatted);
        }
        return;
      }

      if (msg.role !== 'assistant') return;

      if (part.time?.end) {
        // Text complete
        clearTimeout(textTimers.get(partKey));
        textTimers.delete(partKey);

        if (!postedParts.has(partKey)) {
          postedParts.set(partKey, Date.now());
          const formatted = formatAgentText(part, sessions);
          if (formatted) await sendToSessionThread(CHANNELS.agent, sessionId, formatted);
        }
      } else if (delta !== undefined) {
        // Streaming — debounce
        clearTimeout(textTimers.get(partKey));
        const timer = setTimeout(async () => {
          textTimers.delete(partKey);
          if (!postedParts.has(partKey)) {
            postedParts.set(partKey, Date.now());
            const formatted = formatAgentText(part, sessions);
            if (formatted) await sendToSessionThread(CHANNELS.agent, sessionId, formatted);
          }
        }, TEXT_DEBOUNCE_MS);
        textTimers.set(partKey, timer);
      }
      break;
    }

    case 'reasoning': {
      if (part.time?.end && !postedParts.has(partKey)) {
        postedParts.set(partKey, Date.now());
        const formatted = formatReasoning(part, sessions);
        if (formatted) await sendToSessionThread(CHANNELS.thinking, sessionId, formatted);
      }
      break;
    }

    case 'tool': {
      const status = part.state?.status;
      if (status === 'running') {
        pendingTools.set(partKey, { part, sessionId, addedAt: Date.now() });
      } else if (status === 'completed' || status === 'error') {
        pendingTools.delete(partKey);
        if (!postedParts.has(partKey)) {
          postedParts.set(partKey, Date.now());
          const formatted = formatToolCall(part, sessions);
          if (formatted) await sendToSessionThread(CHANNELS.tools, sessionId, formatted);
        }
      }
      break;
    }

    case 'step-start':
      break;

    case 'step-finish': {
      if (!postedParts.has(partKey)) {
        postedParts.set(partKey, Date.now());
        const formatted = formatStepFinish(part, sessions);
        if (formatted) await sendToSessionThread(CHANNELS.status, sessionId, formatted);
      }
      break;
    }

    default:
      break;
  }
}

// ─── Cleanup ─────────────────────────────────────────────────────────────────

const CLEANUP_INTERVAL_MS = 300_000; // 5 minutes
const SESSION_TTL_MS = 3600_000; // 1 hour
const PART_TTL_MS = 3600_000; // 1 hour — match session TTL
const PENDING_TOOL_TTL_MS = 1800_000; // 30 min — stale tools from crashed sessions

const cleanupTimer = setInterval(() => {
  const now = Date.now();

  // Clean postedParts by timestamp instead of blunt size cap
  let partsRemoved = 0;
  for (const [key, ts] of postedParts) {
    if (now - ts > PART_TTL_MS) {
      postedParts.delete(key);
      partsRemoved++;
    }
  }

  // Clean stale pendingTools (crashed sessions that never completed)
  let toolsRemoved = 0;
  for (const [key, entry] of pendingTools) {
    if (now - entry.addedAt > PENDING_TOOL_TTL_MS) {
      pendingTools.delete(key);
      toolsRemoved++;
    }
  }

  // Clean expired sessions (use local _lastSeen if API doesn't provide time.updated)
  let sessionsRemoved = 0;
  for (const [id, session] of sessions) {
    const lastActivity = session.time?.updated || session._lastSeen || 0;
    if (lastActivity > 0 && now - lastActivity > SESSION_TTL_MS) {
      sessions.delete(id);
      sessionsRemoved++;
    }
  }

  if (partsRemoved + toolsRemoved + sessionsRemoved > 0) {
    console.log(`[pipe] Cleanup: ${partsRemoved} parts, ${toolsRemoved} tools, ${sessionsRemoved} sessions removed`);
  }
}, CLEANUP_INTERVAL_MS);

// ─── Graceful Shutdown ───────────────────────────────────────────────────────

async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`[pipe] Received ${signal}, shutting down gracefully...`);

  // Abort SSE connection first (stops new events)
  if (sseController) {
    sseController.abort();
    sseController = null;
  }

  // Clear all debounce timers (don't fire pending text posts)
  for (const [, timer] of textTimers) {
    clearTimeout(timer);
  }
  textTimers.clear();

  // Clear cleanup interval
  clearInterval(cleanupTimer);

  // Await all pending channel queue tasks so no messages are lost
  const queuePromises = Array.from(channelQueues.values());
  if (queuePromises.length > 0) {
    console.log(`[pipe] Draining ${queuePromises.length} pending channel queue(s)...`);
    await Promise.race([
      Promise.allSettled(queuePromises),
      new Promise(r => setTimeout(r, 30000)), // 30s max drain timeout (handles 30+ queued messages)
    ]);
  }

  // Clear state maps to free memory
  const stats = {
    sessions: sessions.size,
    posted: postedParts.size,
    pendingTools: pendingTools.size,
    queues: channelQueues.size,
  };
  sessions.clear();
  postedParts.clear();
  pendingTools.clear();
  channelQueues.clear();

  console.log(`[pipe] Shutdown complete (freed: ${stats.sessions} sessions, ${stats.posted} parts, ${stats.pendingTools} tools, ${stats.queues} queues)`);
  process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// ─── Startup ─────────────────────────────────────────────────────────────────

async function main() {
  console.log('[pipe] opencode-discord-pipe v2.2 starting...');
  console.log(`[pipe] OpenCode URL: ${OPENCODE_URL}`);
  console.log(`[pipe] Threading: enabled (per-session threads in each channel)`);

  // Load existing sessions
  try {
    const res = await fetch(`${OPENCODE_URL}/session`);
    if (res.ok) {
      const data = await res.json();
      // Handle both array and {sessions: [...]} response shapes
      const sessionList = Array.isArray(data) ? data : (data?.sessions || []);
      for (const s of sessionList) {
        sessions.set(s.id, { ...s, messages: {} });
      }
      console.log(`[pipe] Loaded ${sessionList.length} existing session(s)`);
    }
  } catch (err: any) {
    console.warn(`[pipe] Failed to load existing sessions: ${err.message}`);
  }

  await connectSSE();
}

main().catch(err => {
  console.error(`[pipe] Fatal error: ${err.message}`);
  process.exit(1);
});
