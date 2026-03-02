/**
 * hindsight-retain v1.4.0 — Auto-recall + stale conversation batching.
 *
 * Two complementary features in one plugin:
 *
 * 1) AUTO-RECALL (v1.3.4): Before agent turns, recalls relevant memories
 *    from Hindsight and injects them as context via the before_agent_start hook.
 *    Configurable modes: off (default), first-turn-only, every-N-turns.
 *    Disabled by default due to context accumulation (no ephemeral injection yet).
 *
 * 2) AUTO-RETAIN (v1.0.0+): Accumulates conversation messages to per-session
 *    JSONL files on disk. A periodic staleness checker detects when a conversation
 *    goes quiet (no new messages for staleAfterMs) and batch-ingests the full
 *    conversation to Hindsight for fact extraction.
 *
 * v1.3.4 fixes (consolidated review — 3 reviewers):
 *   - C1: Turn counter only increments after successful recall (prevents burned first-turn)
 *   - C2: Resilient JSONL parsing — skip corrupt lines instead of failing entire buffer
 *   - C3: Fixed misleading config comment
 *   - M1: Validate recallMode — reject invalid values, fallback to 'off'
 *   - M2: Clamp recallEveryN to minimum 1 (prevents NaN modulo)
 *   - M3: Clean up dedup cache + turn counter on session TTL purge
 *   - M5: Filter recall results with missing id/text
 *   - M9: Fix stripInjectedContext empty string fallback (Copilot)
 *
 * v1.3.3 enhancements:
 *   - recallMode: 'off' (default), 'first' (session start only), 'every-n' (periodic)
 *   - recallEveryN: turns between recalls in 'every-n' mode (default: 5)
 *   - Auto-recall disabled by default until OpenClaw supports ephemeral context
 *
 * v1.3.2 enhancements:
 *   - Recall queries include username for person-relevant memory retrieval
 *   - Strip <hindsight-memories> from buffered messages to prevent feedback loops
 *
 * v1.3.1 enhancements:
 *   - Auto-recall: before_agent_start hook queries Hindsight and injects memories
 *   - Dedup: tracks last injected memory IDs per session, skips if identical
 *   - Configurable recall types, session types, skip patterns, timeout
 *
 * v1.2.0 enhancements:
 *   - Entity pre-tagging: extracts PERSON/AGENT entities from transcript labels
 *   - Tags for scoping: auto-generates provider/session-type tags for filtered recall
 *   - Metadata: passes channel, session type, agent ID, source to Hindsight
 *   - Derived context: session-type-aware context (e.g. "dm:discord") instead of generic
 *
 * flushTriggerPatterns detect compaction/flush turns and trigger an immediate
 * buffer flush — the trigger turn itself is NOT buffered.
 *
 * File layout (persistent, survives crashes):
 *   data/buffers/<sessionKey>.jsonl   — append-only message buffer per session
 *   data/state.json                   — per-session metadata & rolling tail
 *
 * Config (plugins.entries.hindsight-retain.config):
 *   --- Auto-Recall ---
 *   recallMode           'off' | 'first' | 'every-n' (default: off)
 *   recallEveryN         Turns between recalls in every-n mode (default: 5)
 *   autoRecall           Legacy toggle; prefer recallMode
 *   recallMaxTokens      Max tokens for recall results (default: 512)
 *   recallMinPromptLength Minimum prompt length to trigger recall (default: 10)
 *   recallTimeoutMs      Timeout for recall API call in ms (default: 5000)
 *   recallSkipPatterns   Patterns in prompt that skip recall (default: ["Read HEARTBEAT.md"])
 *   recallTypes          Fact types to recall; empty = all (default: [])
 *   recallSessionTypes   Session types to recall for; empty = all (default: [])
 *   recallDedup          Skip injection if same memories as last turn (default: true)
 *   --- Auto-Retain ---
 *   apiUrl               Hindsight API URL (default: http://hindsight:8888)
 *   bankId               Memory bank ID (default: default)
 *   context              Context tag for retained memories (default: conversation)
 *   staleAfterMs         Conversation idle time before flush (default: 3600000 = 1h)
 *   checkIntervalMs      How often to check for stale sessions (default: 60000 = 1m)
 *   rollingMessages      Overlap messages from previous batch for context (default: 5)
 *   minMessages          Minimum messages to flush (default: 2)
 *   assistantName        Name label for assistant messages in transcript (default: Assistant)
 *   skipRoles            Roles to exclude from transcript (default: [tool, toolResult])
 *   flushTriggerPatterns Patterns that trigger immediate buffer flush (turn not buffered)
 *   requireProviders     Only buffer from these providers (default: [discord, telegram])
 *   sessionTtlMs         Purge inactive session entries after this duration (default: 604800000 = 7d)
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync, appendFileSync, unlinkSync, realpathSync, renameSync, readdirSync, statSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

// Resolve plugin directory reliably across ESM and CJS (jiti transpiles to CJS)
let PLUGIN_DIR: string;
try {
  // ESM path — works in jiti when import.meta.url is patched to source path
  PLUGIN_DIR = dirname(fileURLToPath(import.meta.url));
} catch {
  // CJS fallback: __dirname may point to jiti cache (/tmp/jiti/), so prefer
  // workspace-relative path if available
  if (process.env.OPENCLAW_WORKSPACE) {
    PLUGIN_DIR = join(process.env.OPENCLAW_WORKSPACE, '.openclaw', 'extensions', 'hindsight-retain');
  } else if (typeof __dirname !== 'undefined') {
    PLUGIN_DIR = __dirname;
  } else {
    PLUGIN_DIR = dirname(realpathSync(process.argv[1] || '.'));
  }
}

// ─── Types ───────────────────────────────────────────────────────────────────

interface PluginConfig {
  // Auto-Recall
  autoRecall: boolean;
  recallMode: 'off' | 'first' | 'every-n';
  recallEveryN: number;
  recallMaxTokens: number;
  recallMinPromptLength: number;
  recallTimeoutMs: number;
  recallSkipPatterns: string[];
  recallTypes: string[];
  recallSessionTypes: string[];
  recallDedup: boolean;
  // Auto-Retain
  apiUrl: string;
  bankId: string;
  context: string;
  assistantName: string;
  staleAfterMs: number;
  checkIntervalMs: number;
  rollingMessages: number;
  minMessages: number;
  skipRoles: string[];
  flushTriggerPatterns: string[];
  requireProviders: string[];
  agentIds: string[];
  sessionTtlMs: number;
}

interface Message {
  role: string;
  content: string | Array<{ type: string; text?: string }>;
}

interface SessionState {
  lastActivity: number;
  lastIngested: number;
  lastSeenMessageCount: number;
  bufferedMessageCount: number;
  provider: string;
  agentId?: string;
  rollingTail: Message[];
}

interface State {
  sessions: Record<string, SessionState>;
}

// ─── Config ──────────────────────────────────────────────────────────────────

function getConfig(api: any): PluginConfig {
  const cfg = api.config?.plugins?.entries?.['hindsight-retain']?.config || {};

  // Resolve recallMode from config, with validation.
  // Priority: recallMode (explicit) > autoRecall (legacy) > default ('off')
  const validModes = ['off', 'first', 'every-n'] as const;
  let recallMode: 'off' | 'first' | 'every-n';
  if (cfg.recallMode && validModes.includes(cfg.recallMode)) {
    recallMode = cfg.recallMode;
  } else if (cfg.recallMode) {
    console.warn(`[hindsight-retain] Invalid recallMode "${cfg.recallMode}", falling back to 'off'`);
    recallMode = 'off';
  } else if (cfg.autoRecall === false) {
    recallMode = 'off';
  } else {
    recallMode = 'off'; // default: disabled until OpenClaw supports ephemeral context
  }

  return {
    // Auto-Recall
    autoRecall: recallMode !== 'off',
    recallMode,
    recallEveryN: Math.max(1, cfg.recallEveryN ?? 5),
    recallMaxTokens: cfg.recallMaxTokens ?? 512,
    recallMinPromptLength: cfg.recallMinPromptLength ?? 10,
    recallTimeoutMs: cfg.recallTimeoutMs ?? 5_000,
    recallSkipPatterns: cfg.recallSkipPatterns ?? ['Read HEARTBEAT.md'],
    recallTypes: cfg.recallTypes ?? [],       // empty = include all types
    recallSessionTypes: cfg.recallSessionTypes ?? [], // empty = all sessions
    recallDedup: cfg.recallDedup ?? true,
    // Auto-Retain
    apiUrl: cfg.apiUrl || process.env.HINDSIGHT_API_URL || 'http://hindsight:8888',
    bankId: cfg.bankId || 'default',
    context: cfg.context || 'conversation',
    assistantName: cfg.assistantName || 'Assistant',
    staleAfterMs: cfg.staleAfterMs ?? 3_600_000,
    checkIntervalMs: cfg.checkIntervalMs ?? 60_000,
    rollingMessages: cfg.rollingMessages ?? 5,
    minMessages: cfg.minMessages ?? 2,
    skipRoles: cfg.skipRoles ?? ['tool', 'toolResult'],
    flushTriggerPatterns: cfg.flushTriggerPatterns ?? [
      'Flush session context to durable memory before compaction',
    ],
    requireProviders: cfg.requireProviders ?? ['discord', 'telegram'],
    agentIds: cfg.agentIds ?? [],
    sessionTtlMs: cfg.sessionTtlMs ?? 7 * 24 * 60 * 60 * 1000, // 7 days
  };
}

// ─── File Paths ──────────────────────────────────────────────────────────────

function getDataDir(): string {
  return join(PLUGIN_DIR, 'data');
}

function getBufferDir(): string {
  return join(getDataDir(), 'buffers');
}

function getStatePath(): string {
  return join(getDataDir(), 'state.json');
}

function sanitizeSessionKey(key: string): string {
  return key.replace(/[^a-zA-Z0-9_:-]/g, '_');
}

function getBufferPath(sessionKey: string): string {
  return join(getBufferDir(), `${sanitizeSessionKey(sessionKey)}.jsonl`);
}

// ─── State Persistence ───────────────────────────────────────────────────────

function ensureDirs(): void {
  const bufferDir = getBufferDir();
  if (!existsSync(bufferDir)) {
    mkdirSync(bufferDir, { recursive: true });
  }
}

function loadState(): State {
  const path = getStatePath();
  try {
    if (existsSync(path)) {
      return JSON.parse(readFileSync(path, 'utf-8'));
    }
  } catch (err: any) {
    console.error(`[hindsight-retain] Failed to load state: ${err.message}`);
  }
  return { sessions: {} };
}

function saveState(state: State): void {
  try {
    const path = getStatePath();
    const tmpPath = path + '.tmp';
    writeFileSync(tmpPath, JSON.stringify(state, null, 2));
    renameSync(tmpPath, path); // atomic on Linux (ext4/xfs)
  } catch (err: any) {
    console.error(`[hindsight-retain] Failed to save state: ${err.message}`);
  }
}

// ─── Context Stripping ───────────────────────────────────────────────────────
// Strip injected <hindsight-memories> blocks from messages before buffering.
// Without this, recalled memories would get re-ingested on flush → feedback loop.

const HINDSIGHT_BLOCK_REGEX = /\s*<hindsight-memories>[\s\S]*?<\/hindsight-memories>\s*/g;

function stripInjectedContext(content: unknown): unknown {
  if (typeof content !== 'string') return content;
  if (!content.includes('<hindsight-memories>')) return content;
  return content.replace(HINDSIGHT_BLOCK_REGEX, '\n').trim();
}

function stripInjectedContextFromMessages(messages: Message[]): Message[] {
  return messages.map(msg => {
    if (msg.role !== 'user') return msg;

    if (typeof msg.content === 'string' && msg.content.includes('<hindsight-memories>')) {
      return { ...msg, content: stripInjectedContext(msg.content) as string };
    }

    // Handle array content (multi-part messages)
    if (Array.isArray(msg.content)) {
      const hasBlock = msg.content.some(
        (part: any) => typeof part?.text === 'string' && part.text.includes('<hindsight-memories>')
      );
      if (hasBlock) {
        return {
          ...msg,
          content: msg.content.map((part: any) => {
            if (typeof part?.text === 'string' && part.text.includes('<hindsight-memories>')) {
              return { ...part, text: stripInjectedContext(part.text) as string };
            }
            return part;
          }),
        };
      }
    }

    return msg;
  });
}

// ─── Recalled Content Sanitization ───────────────────────────────────────────
// Sanitize content recalled from Hindsight before injecting into agent context.
// Prevents credential leakage and prompt injection via poisoned memories (M-PLUGIN-1).

/** Credential-like patterns to redact from recalled content */
const CREDENTIAL_PATTERNS = [
  /sk-[a-zA-Z0-9]{20,}/g,           // OpenAI API keys
  /ghp_[a-zA-Z0-9]{36}/g,           // GitHub PATs
  /xoxb-[0-9]+-[a-zA-Z0-9]+/g,      // Slack bot tokens
  /AKIA[0-9A-Z]{16}/g,               // AWS access keys
  /Bearer\s+[a-zA-Z0-9._\-]{20,}/g, // Bearer tokens
  /sk-ant-[a-zA-Z0-9\-]{20,}/g,     // Anthropic API keys
  /Bot\s+[a-zA-Z0-9._\-]{50,}/g,    // Discord bot tokens
];

/** System prompt injection patterns to strip from recalled content */
const INJECTION_PATTERNS = [
  /<system>/gi,
  /<\/system>/gi,
  /\[INST\]/gi,
  /\[\/INST\]/gi,
  /<<SYS>>/gi,
  /<<\/SYS>>/gi,
];

/** Max character length for a single recalled memory text */
const MAX_RECALL_CONTENT_LENGTH = 50_000;

/**
 * Sanitize a single piece of recalled content.
 * Applied to each RecallResult.text before injection into agent context.
 *
 * 1. Redacts credential-like strings (API keys, tokens)
 * 2. Strips prompt injection patterns (<system>, [INST], <<SYS>>)
 * 3. Enforces per-result length limit
 */
function sanitizeRecalledContent(text: string): string {
  let sanitized = text;

  // Redact credential patterns
  for (const pattern of CREDENTIAL_PATTERNS) {
    sanitized = sanitized.replace(pattern, '[REDACTED]');
  }

  // Strip injection patterns
  for (const pattern of INJECTION_PATTERNS) {
    sanitized = sanitized.replace(pattern, '');
  }

  // Enforce length limit
  if (sanitized.length > MAX_RECALL_CONTENT_LENGTH) {
    sanitized = sanitized.slice(0, MAX_RECALL_CONTENT_LENGTH) + '… [truncated]';
  }

  return sanitized;
}

/**
 * Sanitize an array of recall results (mutates text fields in-place).
 * Returns the same array for chaining convenience.
 */
function sanitizeRecallResults(results: RecallResult[]): RecallResult[] {
  for (const result of results) {
    result.text = sanitizeRecalledContent(result.text);
  }
  return results;
}

// ─── Buffer I/O ──────────────────────────────────────────────────────────────

function appendToBuffer(sessionKey: string, messages: Message[]): void {
  const path = getBufferPath(sessionKey);
  const lines = messages.map(m => JSON.stringify(m)).join('\n') + '\n';
  appendFileSync(path, lines);
}

function readBuffer(sessionKey: string): Message[] {
  const path = getBufferPath(sessionKey);
  try {
    if (!existsSync(path)) return [];
    const content = readFileSync(path, 'utf-8').trim();
    if (!content) return [];
    // Parse line-by-line: skip corrupted lines instead of failing the entire buffer
    const messages: Message[] = [];
    const lines = content.split('\n');
    let corrupted = 0;
    for (let i = 0; i < lines.length; i++) {
      try {
        messages.push(JSON.parse(lines[i]));
      } catch {
        corrupted++;
      }
    }
    if (corrupted > 0) {
      console.warn(`[hindsight-retain] Skipped ${corrupted} corrupted line(s) in buffer for ${sessionKey}`);
    }
    return messages;
  } catch (err: any) {
    console.error(`[hindsight-retain] Failed to read buffer for ${sessionKey}: ${err.message}`);
    return [];
  }
}

function clearBuffer(sessionKey: string): void {
  const path = getBufferPath(sessionKey);
  try {
    if (existsSync(path)) unlinkSync(path);
  } catch (err: any) {
    console.error(`[hindsight-retain] Failed to clear buffer for ${sessionKey}: ${err.message}`);
  }
}

// ─── Message Helpers ─────────────────────────────────────────────────────────

function extractText(content: string | Array<{ type: string; text?: string }>): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .filter(b => b.type === 'text' && b.text)
      .map(b => b.text!)
      .join('\n');
  }
  return '';
}

function filterMessages(messages: Message[], skipRoles: string[]): Message[] {
  return messages.filter(m => {
    if (skipRoles.includes(m.role)) return false;
    const text = extractText(m.content);
    return text.trim().length > 0;
  });
}

function matchesFlushTrigger(messages: Message[], patterns: string[]): boolean {
  if (patterns.length === 0) return false;
  const firstUser = messages.find(m => m.role === 'user');
  if (!firstUser) return false;
  const text = extractText(firstUser.content);
  return patterns.some(p => text.includes(p));
}

// ─── Transcript Formatting ───────────────────────────────────────────────────

/**
 * Parse OpenClaw's user message metadata prefix.
 * Format: [Channel username user id:ID timestamp] message content
 * Examples:
 *   [Discord admin user id:123456789 +2m 2026-02-01 18:22 UTC] Hello
 *   [Telegram @admin user id:123456789 +1m 2026-02-01 10:00 UTC] Hello
 *
 * Returns structured metadata and the clean message content, or null if no match.
 */
interface UserMessageMeta {
  channel: string;
  username: string;
  userId: string;
  cleanContent: string;
}

const USER_META_REGEX = /^\[(\w+)\s+(@?\S+)\s+user\s+id:(\d+)\s+[^\]]*\]\s*([\s\S]*)$/;

function parseUserMessageMeta(text: string): UserMessageMeta | null {
  // Content may have system messages prepended (e.g. cron notifications).
  // Find the last metadata prefix in the text.
  const lines = text.split('\n');
  let metaLineIdx = -1;
  for (let i = lines.length - 1; i >= 0; i--) {
    if (USER_META_REGEX.test(lines.slice(i).join('\n'))) {
      metaLineIdx = i;
      break;
    }
  }

  if (metaLineIdx === -1) return null;

  const relevantText = lines.slice(metaLineIdx).join('\n');
  const match = relevantText.match(USER_META_REGEX);
  if (!match) return null;

  return {
    channel: match[1],
    username: match[2].replace(/^@/, ''), // strip leading @ from Telegram usernames
    userId: match[3],
    cleanContent: match[4].trim(),
  };
}

function buildTranscriptHeader(sessionKey: string, state: SessionState): string {
  const lines: string[] = ['[session metadata]'];
  lines.push(`session: ${sessionKey}`);
  if (state.provider) lines.push(`channel: ${state.provider}`);
  if (state.agentId) lines.push(`agent: ${state.agentId}`);

  const parts = sessionKey.split(':');
  if (parts.length >= 2) {
    lines.push(`type: ${parts[1]}`);
    if (parts.length >= 3) {
      if (parts[1] === 'dm') lines.push(`sender_id: ${parts.slice(2).join(':')}`);
      else if (parts[1] === 'group') lines.push(`channel_id: ${parts.slice(2).join(':')}`);
    }
  }

  lines.push('[session metadata:end]');
  return lines.join('\n');
}

function formatTranscript(messages: Message[], assistantName: string): string {
  const parts: string[] = [];
  for (const msg of messages) {
    const text = extractText(msg.content);
    if (!text.trim()) continue;

    if (msg.role === 'user') {
      const meta = parseUserMessageMeta(text);
      if (meta) {
        // Structured labels for user messages
        const labels = [
          `[role: user]`,
          `[channel: ${meta.channel}]`,
          `[username: ${meta.username}]`,
          `[id: ${meta.userId}]`,
        ];
        parts.push(`${labels.join('\n')}\n${meta.cleanContent}\n[user:end]`);
      } else {
        // Fallback: no metadata prefix found, keep as-is
        parts.push(`[role: user]\n${text}\n[user:end]`);
      }
    } else if (msg.role === 'assistant') {
      parts.push(`[role: assistant]\n[name: ${assistantName}]\n${text}\n[assistant:end]`);
    } else {
      parts.push(`[role: ${msg.role}]\n${text}\n[${msg.role}:end]`);
    }
  }
  return parts.join('\n\n');
}

// ─── Entity Extraction ───────────────────────────────────────────────────────

interface EntityTag {
  text: string;
  type: string;
}

/**
 * Extract entities from messages for pre-tagging in Hindsight.
 * Collects unique usernames from parsed user message metadata
 * and always includes the assistant identity.
 */
function extractEntities(messages: Message[], assistantName: string): EntityTag[] {
  const seen = new Set<string>();
  const entities: EntityTag[] = [];

  // Always include the assistant
  entities.push({ text: assistantName, type: 'AGENT' });
  seen.add(assistantName.toLowerCase());

  // Extract usernames from user messages
  for (const msg of messages) {
    if (msg.role !== 'user') continue;
    const text = extractText(msg.content);
    const meta = parseUserMessageMeta(text);
    if (meta && !seen.has(meta.username.toLowerCase())) {
      seen.add(meta.username.toLowerCase());
      entities.push({ text: meta.username, type: 'PERSON' });
    }
  }

  return entities;
}

// ─── Session Metadata Helpers ─────────────────────────────────────────────────

interface SessionMeta {
  sessionType: string;   // dm | group | unknown
  provider: string;      // discord | telegram | unknown
  agentId: string;       // main | sub-agent id
}

/**
 * Parse session metadata from sessionKey and state.
 * sessionKey format: "agent:<sessionType>:<channelId>"
 * Examples:
 *   "agent:main:main"           → sessionType "main"
 *   "agent:dm:812579232580501504" → sessionType "dm"
 *   "agent:group:123456789"     → sessionType "group"
 */
function parseSessionMeta(sessionKey: string, sessionState: SessionState): SessionMeta {
  const parts = sessionKey.split(':');
  return {
    sessionType: parts.length >= 2 ? parts[1] : 'unknown',
    provider: sessionState.provider || 'unknown',
    agentId: sessionState.agentId || 'unknown',
  };
}

/**
 * Derive context value from session metadata instead of generic "conversation".
 * Falls back to config.context if session type can't be determined.
 *
 * Examples: "dm:discord", "group:telegram", "conversation"
 */
function deriveContext(config: PluginConfig, meta: SessionMeta): string {
  if (meta.sessionType !== 'unknown' && meta.provider !== 'unknown') {
    return `${meta.sessionType}:${meta.provider}`;
  }
  if (meta.sessionType !== 'unknown') {
    return meta.sessionType;
  }
  return config.context;
}

/**
 * Generate tags for scoping retained documents.
 * Tags enable filtered recall via RecallRequest.tags + tags_match.
 *
 * Generated tags: provider:<name>, session:<type>, agent:<id>
 */
function buildTags(meta: SessionMeta): string[] {
  const tags: string[] = [];
  if (meta.provider !== 'unknown') tags.push(`provider:${meta.provider}`);
  if (meta.sessionType !== 'unknown') tags.push(`session:${meta.sessionType}`);
  if (meta.agentId !== 'unknown') tags.push(`agent:${meta.agentId}`);
  return tags;
}

/**
 * Build metadata object for the retain call.
 * Passed through to Hindsight as arbitrary key-value pairs on the memory item.
 */
function buildMetadata(meta: SessionMeta, sessionKey: string): Record<string, string> {
  const md: Record<string, string> = {
    source: 'hindsight-retain-plugin',
    session_key: sessionKey,
  };
  if (meta.provider !== 'unknown') md.channel = meta.provider;
  if (meta.sessionType !== 'unknown') md.session_type = meta.sessionType;
  if (meta.agentId !== 'unknown') md.agent_id = meta.agentId;
  return md;
}

// ─── Hindsight API ───────────────────────────────────────────────────────────

async function retainToHindsight(
  config: PluginConfig,
  transcript: string,
  documentId: string,
  entities: EntityTag[],
  tags: string[],
  metadata: Record<string, string>,
  context: string,
): Promise<void> {
  const url = `${config.apiUrl}/v1/default/banks/${config.bankId}/memories`;

  const body = JSON.stringify({
    items: [{
      content: transcript,
      context,
      document_id: documentId,
      timestamp: new Date().toISOString(),
      entities: entities.length > 0 ? entities : undefined,
      tags: tags.length > 0 ? tags : undefined,
      metadata,
    }],
    async: true,
  });

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
    body,
    signal: AbortSignal.timeout(10_000),
  });

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`Hindsight retain failed (${response.status}): ${text}`);
  }
}

// ─── Hindsight Recall API ────────────────────────────────────────────────────

interface RecallResult {
  id: string;
  text: string;
  type: string;
  context?: string;
  entities?: string[];
}

interface RecallResponse {
  results: RecallResult[];
}

async function recallFromHindsight(
  config: PluginConfig,
  query: string,
): Promise<RecallResult[]> {
  const url = `${config.apiUrl}/v1/default/banks/${config.bankId}/memories/recall`;

  const body: Record<string, unknown> = {
    query,
    max_tokens: config.recallMaxTokens,
  };

  // Only pass types if explicitly configured (empty = let Hindsight decide)
  if (config.recallTypes.length > 0) {
    body.types = config.recallTypes;
  }

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(config.recallTimeoutMs),
  });

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`Hindsight recall failed (${response.status}): ${text}`);
  }

  const data = await response.json() as RecallResponse;
  // Filter out malformed results to prevent "📌 undefined" injection
  return (data.results || []).filter(r => r.id && r.text);
}

/**
 * Format recall results into a context block for injection.
 * Uses XML-style tags so the agent can clearly identify injected memories.
 */
function formatRecallContext(results: RecallResult[]): string {
  if (results.length === 0) return '';

  const lines = results.map(r => {
    const prefix = r.type === 'observation' ? '💡' : r.type === 'experience' ? '📝' : '📌';
    return `${prefix} ${r.text}`;
  });

  return [
    '<hindsight-memories>',
    'Relevant context from long-term memory:',
    ...lines,
    '</hindsight-memories>',
  ].join('\n');
}

/**
 * Compute a dedup key from recall result IDs.
 * Sorted to ensure consistent comparison regardless of result order.
 */
function computeDedupKey(results: RecallResult[]): string {
  return results.map(r => r.id).sort().join(',');
}

// ─── Recall Query Enrichment ─────────────────────────────────────────────────

/**
 * Build an enriched recall query by combining recent conversation context
 * with the current user message. This anchors semantic search on the actual
 * topic being discussed, not just the bare (potentially vague) question.
 *
 * Example:
 *   Last assistant: "I've implemented auto-recall with dedup and skip logic..."
 *   User: "How did that go?"
 *   Enriched: "auto-recall implementation dedup skip logic | How did that go?"
 */
function buildEnrichedQuery(cleanQuery: string, messages: unknown[], maxContextChars: number = 200): string {
  if (!Array.isArray(messages) || messages.length === 0) return cleanQuery;

  // Walk backwards to find the last 1-2 assistant messages for topic context
  const contextParts: string[] = [];
  let contextLen = 0;

  for (let i = messages.length - 1; i >= 0 && contextLen < maxContextChars; i--) {
    const msg = messages[i] as Record<string, unknown> | null;
    if (!msg || typeof msg !== 'object') continue;
    if (msg.role !== 'assistant') continue;

    let text = '';
    if (typeof msg.content === 'string') {
      text = msg.content;
    } else if (Array.isArray(msg.content)) {
      text = (msg.content as Array<Record<string, unknown>>)
        .filter(b => b.type === 'text' && typeof b.text === 'string')
        .map(b => b.text as string)
        .join(' ');
    }

    if (!text) continue;

    // Strip markdown formatting, code blocks, URLs, and tool noise
    text = text
      .replace(/```[\s\S]*?```/g, '')           // code blocks
      .replace(/`[^`]+`/g, '')                   // inline code
      .replace(/https?:\/\/\S+/g, '')            // URLs
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')   // markdown links → text
      .replace(/[#*_~>|]/g, '')                  // markdown formatting
      .replace(/\n+/g, ' ')                      // newlines → spaces
      .replace(/\s+/g, ' ')                      // collapse whitespace
      .trim();

    if (text.length < 10) continue;

    // Truncate to fit within budget
    const available = maxContextChars - contextLen;
    const snippet = text.length > available ? text.slice(0, available) : text;
    contextParts.unshift(snippet);
    contextLen += snippet.length;

    // 1-2 assistant messages is enough
    if (contextParts.length >= 2) break;
  }

  if (contextParts.length === 0) return cleanQuery;

  const topicContext = contextParts.join(' ');
  return `${topicContext} | ${cleanQuery}`;
}

// ─── Recall State (in-memory, per session) ────────────────────────────────────

const recallDedupCache = new Map<string, string>(); // sessionKey → dedupKey
const recallTurnCounter = new Map<string, number>(); // sessionKey → turn count since last recall

// ─── Flush Logic ─────────────────────────────────────────────────────────────

// Per-session flush lock to prevent concurrent flushes racing on the same buffer
const flushingLocks = new Set<string>();

async function flushSession(
  sessionKey: string,
  config: PluginConfig,
  state: State,
): Promise<boolean> {
  // Acquire lock — skip if already flushing this session
  if (flushingLocks.has(sessionKey)) {
    console.log(`[hindsight-retain] Session ${sessionKey} already flushing, skipping`);
    return false;
  }
  flushingLocks.add(sessionKey);

  try {
    const sessionState = state.sessions[sessionKey];
    if (!sessionState) return false;

    // Read buffered messages
    const buffered = readBuffer(sessionKey);
    if (buffered.length === 0) return false;

    // Check minimum message count
    if (buffered.length < config.minMessages) {
      console.log(`[hindsight-retain] Session ${sessionKey}: only ${buffered.length} msg(s) (min: ${config.minMessages}), skipping flush`);
      clearBuffer(sessionKey);
      delete state.sessions[sessionKey];
      saveState(state);
      return false;
    }

    // Build transcript: rolling tail (context overlap) + new messages
    const rollingTail = sessionState.rollingTail || [];
    const allMessages = [...rollingTail, ...buffered];

    // Format transcript
    const header = buildTranscriptHeader(sessionKey, sessionState);
    const body = formatTranscript(allMessages, config.assistantName);

    if (!body || body.trim().length < 50) {
      console.log(`[hindsight-retain] Session ${sessionKey}: transcript too short after formatting, skipping`);
      clearBuffer(sessionKey);
      delete state.sessions[sessionKey];
      saveState(state);
      return false;
    }

    const fullTranscript = `${header}\n\n${body}`;

    // Extract entities from messages for pre-tagging
    const entities = extractEntities(allMessages, config.assistantName);

    // Derive session metadata for tags, metadata, and context
    const meta = parseSessionMeta(sessionKey, sessionState);
    const tags = buildTags(meta);
    const metadata = buildMetadata(meta, sessionKey);
    const context = deriveContext(config, meta);

    // Build document ID
    const safeKey = sanitizeSessionKey(sessionKey);
    const docId = `${safeKey}_${Date.now()}`;

    // Send to Hindsight
    try {
      await retainToHindsight(config, fullTranscript, docId, entities, tags, metadata, context);
      const entityNames = entities.map(e => e.text).join(', ');
      console.log(`[hindsight-retain] Flushed ${buffered.length} msgs (+${rollingTail.length} rolling) for ${sessionKey} → ${docId} (${fullTranscript.length} chars, context: ${context}, tags: [${tags.join(', ')}], entities: [${entityNames}])`);
    } catch (err: any) {
      console.error(`[hindsight-retain] Flush failed for ${sessionKey}: ${err.message}`);
      // Don't clear buffer on failure — retry next cycle
      return false;
    }

    // Save new rolling tail (last N messages from this batch for next overlap)
    const newTail = config.rollingMessages > 0
      ? buffered.slice(-config.rollingMessages)
      : [];

    // Update state
    sessionState.rollingTail = newTail;
    sessionState.lastIngested = Date.now();
    sessionState.bufferedMessageCount = 0;
    clearBuffer(sessionKey);
    saveState(state);

    return true;
  } finally {
    flushingLocks.delete(sessionKey);
  }
}

// ─── Plugin Entry ────────────────────────────────────────────────────────────

export default function (api: any) {
  console.log('[hindsight-retain] v1.4.0 loading...');

  const config = getConfig(api);
  ensureDirs();

  const state = loadState();

  console.log(`[hindsight-retain] Config: api=${config.apiUrl} bank=${config.bankId} stale=${config.staleAfterMs}ms check=${config.checkIntervalMs}ms rolling=${config.rollingMessages} providers=[${config.requireProviders.join(',')}]`);
  console.log(`[hindsight-retain] Auto-recall: ${config.autoRecall ? 'ON' : 'OFF'} (mode=${config.recallMode}, everyN=${config.recallEveryN}, maxTokens=${config.recallMaxTokens}, timeout=${config.recallTimeoutMs}ms, dedup=${config.recallDedup}, types=${config.recallTypes.length ? config.recallTypes.join(',') : 'all'}, sessions=${config.recallSessionTypes.length ? config.recallSessionTypes.join(',') : 'all'})`);
  console.log(`[hindsight-retain] Restored state: ${Object.keys(state.sessions).length} tracked session(s)`);

  // ── Hook: before_agent_start (Auto-Recall) ───────────────────────────────
  // Queries Hindsight for relevant memories and injects them as context
  // before the agent processes the user's message.

  if (config.autoRecall) {
    api.on('before_agent_start', async (event: any, ctx: any) => {
      try {
        const prompt = event?.prompt;
        if (!prompt || typeof prompt !== 'string') return;

        const sessionKey = ctx?.sessionKey || 'unknown';

        // Per-agent gate: skip if agentIds is configured and this agent isn't listed
        if (config.agentIds.length > 0) {
          const agentId = ctx?.agentId;
          if (!agentId || !config.agentIds.includes(agentId)) return;
        }

        // ── Session type filter ──
        if (config.recallSessionTypes.length > 0) {
          const parts = sessionKey.split(':');
          const sessionType = parts.length >= 2 ? parts[1] : 'unknown';
          if (!config.recallSessionTypes.includes(sessionType)) {
            return;
          }
        }

        // ── Skip patterns (heartbeats, compaction triggers, etc.) ──
        const allSkipPatterns = [
          ...config.recallSkipPatterns,
          ...config.flushTriggerPatterns,
        ];
        if (allSkipPatterns.some(p => prompt.includes(p))) {
          return;
        }

        // ── Recall mode gating ──
        // Turn counter only increments after successful recall to prevent
        // permanently burning the first-turn opportunity on transient failures.
        const turnCount = recallTurnCounter.get(sessionKey) ?? 0;

        if (config.recallMode === 'first') {
          if (turnCount > 0) {
            return; // already recalled for this session — skip silently
          }
        } else if (config.recallMode === 'every-n') {
          if (turnCount > 0 && turnCount % config.recallEveryN !== 0) {
            recallTurnCounter.set(sessionKey, turnCount + 1);
            return;
          }
        }

        // ── Extract clean query from user prompt ──
        // Strip OpenClaw metadata prefix but keep username for person-relevant recall.
        // "admin: What's the PTO policy?" biases recall toward admin-tagged memories.
        const meta = parseUserMessageMeta(prompt);
        const cleanQuery = meta
          ? `${meta.username}: ${meta.cleanContent}`
          : prompt;

        // ── Min length check ──
        if (cleanQuery.length < config.recallMinPromptLength) {
          return;
        }

        // ── Enrich query with conversation context ──
        // Anchors semantic search on the actual topic, not just the bare question
        const enrichedQuery = buildEnrichedQuery(cleanQuery, event.messages || []);

        // ── Call Hindsight recall API ──
        const results = await recallFromHindsight(config, enrichedQuery);

        if (results.length === 0) {
          return;
        }

        // Sanitize recalled content before injection: redact credentials, strip injection patterns, enforce length
        sanitizeRecallResults(results);

        // ── Dedup: skip if same memories as last injection for this session ──
        if (config.recallDedup) {
          const newKey = computeDedupKey(results);
          const lastKey = recallDedupCache.get(sessionKey);

          if (lastKey === newKey) {
            console.log(`[hindsight-retain] Recall dedup hit for ${sessionKey} (${results.length} results identical to last turn)`);
            return;
          }

          recallDedupCache.set(sessionKey, newKey);
        }

        // ── Format and inject ──
        const contextBlock = formatRecallContext(results);
        const queryInfo = enrichedQuery !== cleanQuery
          ? `query="${cleanQuery.slice(0, 60)}..." (enriched: ${enrichedQuery.length} chars)`
          : `query="${cleanQuery.slice(0, 80)}..."`;
        console.log(`[hindsight-retain] Auto-recall: injecting ${results.length} memories for ${sessionKey} — ${queryInfo} (${contextBlock.length} chars)`);

        // Increment turn counter AFTER successful recall — prevents burning
        // the first-turn opportunity on transient failures (C1 fix)
        recallTurnCounter.set(sessionKey, turnCount + 1);

        return {
          prependContext: contextBlock,
        };

      } catch (err: any) {
        // Graceful degradation — if recall fails, agent proceeds without memories
        // Turn counter NOT incremented — retry on next turn
        console.warn(`[hindsight-retain] Auto-recall failed: ${err.message}`);
        return;
      }
    });
  }

  // ── Orphan buffer recovery ─────────────────────────────────────────────
  // If the process crashed between appendToBuffer and saveState, buffer
  // files exist on disk with no matching state entry. Scan and seed minimal
  // entries so the staleness checker can flush them.
  try {
    const bufferDir = getBufferDir();
    const files = readdirSync(bufferDir).filter((f: string) => f.endsWith('.jsonl'));
    let orphans = 0;
    for (const file of files) {
      const sessionKey = file.replace(/\.jsonl$/, '');
      if (!state.sessions[sessionKey]) {
        const filePath = join(bufferDir, file);
        const fileStat = statSync(filePath);
        const mtime = fileStat.mtimeMs;
        // Count lines to set bufferedMessageCount — staleness checker
        // requires > 0 to trigger a flush
        let lineCount = 0;
        try {
          const content = readFileSync(filePath, 'utf-8').trim();
          lineCount = content ? content.split('\n').length : 0;
        } catch { /* will be read again by flushSession */ }
        state.sessions[sessionKey] = {
          lastActivity: mtime,
          lastIngested: 0,
          lastSeenMessageCount: 0,
          bufferedMessageCount: lineCount,
          provider: 'unknown',
          rollingTail: [],
        };
        orphans++;
      }
    }
    if (orphans > 0) {
      console.log(`[hindsight-retain] Recovered ${orphans} orphaned buffer(s)`);
      saveState(state);
    }
  } catch (err: any) {
    console.error(`[hindsight-retain] Orphan recovery failed: ${err.message}`);
  }

  // ── Hook: agent_end ──────────────────────────────────────────────────────
  // Message delta extraction uses lastSeenMessageCount stored per-session
  // in state.json. No before_agent_start hook needed — avoids the
  // multi-session race condition of a shared key.

  api.on('agent_end', async (event: any, ctx: any) => {
    try {
      if (!event.success || !Array.isArray(event.messages) || event.messages.length === 0) {
        return;
      }

       const sessionKey = ctx?.sessionKey || 'unknown';
       const messageProvider = ctx?.messageProvider;
       const agentId = ctx?.agentId;

       // Per-agent gate: skip if agentIds is configured and this agent isn't listed
       if (config.agentIds.length > 0) {
         if (!agentId || !config.agentIds.includes(agentId)) return;
       }

       // ── Guard: skip if session is being flushed ──
      // Prevents appending to a buffer that flushSession is about to delete.
      // Don't update lastSeenMessageCount either — next turn will re-capture
      // these messages as "new".
      if (flushingLocks.has(sessionKey)) {
        return;
      }

      // ── Filter: requireProviders ──
      if (config.requireProviders.length > 0) {
        if (!messageProvider || !config.requireProviders.includes(messageProvider)) {
          return;
        }
      }

      // Extract NEW messages using per-session lastSeenMessageCount
      const sessionState = state.sessions[sessionKey];
      const prevCount = sessionState?.lastSeenMessageCount || 0;
      const totalMessages = event.messages.length;

      // Detect compaction: message count shrank (session history was replaced
      // with a compact summary). Reset counter and skip this turn — the
      // compacted summary is system noise, not conversation content.
      if (prevCount > 0 && prevCount >= totalMessages) {
        console.log(`[hindsight-retain] Compaction detected for ${sessionKey} (prev=${prevCount}, now=${totalMessages}) — resetting counter`);
        if (state.sessions[sessionKey]) {
          state.sessions[sessionKey].lastSeenMessageCount = totalMessages;
        }
        saveState(state);
        return;
      }

      const newMessages = prevCount > 0
        ? event.messages.slice(prevCount)
        : event.messages;

      // Update the count for next turn (always, even if we skip buffering)
      if (!state.sessions[sessionKey]) {
        state.sessions[sessionKey] = {
          lastActivity: Date.now(),
          lastIngested: 0,
          lastSeenMessageCount: totalMessages,
          bufferedMessageCount: 0,
          provider: messageProvider || 'unknown',
          agentId: agentId || undefined,
          rollingTail: [],
        };
      } else {
        state.sessions[sessionKey].lastSeenMessageCount = totalMessages;
      }

      if (newMessages.length === 0) {
        saveState(state);
        return;
      }

      // Filter out excluded roles
      const filtered = filterMessages(newMessages, config.skipRoles);
      if (filtered.length === 0) {
        saveState(state);
        return;
      }

      // ── flushTriggerPatterns: detect compaction/flush turns ──
      // These turns signal that the session is about to be wiped.
      // Flush the accumulated buffer immediately. The trigger turn
      // itself is NOT buffered (it's system noise, not conversation).
      if (matchesFlushTrigger(filtered, config.flushTriggerPatterns)) {
        console.log(`[hindsight-retain] Flush trigger detected for ${sessionKey} — flushing buffer now`);
        saveState(state);
        flushSession(sessionKey, config, state).catch(err => {
          console.error(`[hindsight-retain] Triggered flush failed: ${err.message}`);
        });
        return;
      }

      // ── Buffer the messages ──
      state.sessions[sessionKey].lastActivity = Date.now();
      state.sessions[sessionKey].provider = messageProvider || state.sessions[sessionKey].provider;
      state.sessions[sessionKey].agentId = agentId || state.sessions[sessionKey].agentId;
      state.sessions[sessionKey].bufferedMessageCount = (state.sessions[sessionKey].bufferedMessageCount || 0) + filtered.length;

      // Strip injected <hindsight-memories> blocks to prevent feedback loops
      const cleanedMessages = stripInjectedContextFromMessages(filtered);

      // Append to JSONL buffer (sub-ms for small payloads)
      appendToBuffer(sessionKey, cleanedMessages);
      saveState(state);

      console.log(`[hindsight-retain] Buffered ${filtered.length} msg(s) for ${sessionKey} (total: ${state.sessions[sessionKey].bufferedMessageCount})`);

    } catch (err: any) {
      console.error(`[hindsight-retain] Error in agent_end: ${err.message}`);
    }
  });

  // ── Hook: before_compaction (defensive) ──────────────────────────────────
  // Not wired in OpenClaw v2026.1.30 but registered defensively so it
  // auto-activates if a future version connects it. Flushes ALL tracked
  // sessions, not just the one being compacted.

  api.on('before_compaction', async (_event: any, _ctx: any) => {
    console.log('[hindsight-retain] before_compaction fired — flushing all sessions');
    const sessionKeys = Object.keys(state.sessions);
    for (const sessionKey of sessionKeys) {
      try {
        await flushSession(sessionKey, config, state);
      } catch (err: any) {
        console.error(`[hindsight-retain] Compaction flush failed for ${sessionKey}: ${err.message}`);
      }
    }
  });

  // ── Staleness Checker ────────────────────────────────────────────────────

  const interval: any = setInterval(() => {
    const now = Date.now();
    const sessionKeys = Object.keys(state.sessions);

    for (const sessionKey of sessionKeys) {
      const session = state.sessions[sessionKey];

      // Purge ancient session entries (no activity for sessionTtlMs)
      const ageMs = now - session.lastActivity;
      if (ageMs >= config.sessionTtlMs) {
        console.log(`[hindsight-retain] Purging stale session entry ${sessionKey} (inactive ${Math.round(ageMs / 86_400_000)}d)`);
        clearBuffer(sessionKey);
        delete state.sessions[sessionKey];
        recallDedupCache.delete(sessionKey);
        recallTurnCounter.delete(sessionKey);
        saveState(state);
        continue;
      }

      // Flush conversations that have gone quiet
      const idleMs = now - session.lastActivity;
      if (idleMs >= config.staleAfterMs && (session.bufferedMessageCount || 0) > 0) {
        console.log(`[hindsight-retain] Session ${sessionKey} stale (idle ${Math.round(idleMs / 60_000)}m) — flushing`);
        flushSession(sessionKey, config, state).catch(err => {
          console.error(`[hindsight-retain] Stale flush failed for ${sessionKey}: ${err.message}`);
        });
      }
    }
  }, config.checkIntervalMs);

  // Don't let the interval keep the process alive
  if (interval.unref) interval.unref();

  console.log(`[hindsight-retain] v1.4.0 loaded — recall=${config.autoRecall ? 'ON' : 'OFF'}, staleness checker every ${config.checkIntervalMs / 1000}s, flush after ${config.staleAfterMs / 60_000}m idle`);
}
