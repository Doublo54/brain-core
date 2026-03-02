/**
 * opencode-discord-pipe — Message formatters
 *
 * Converts OpenCode SSE event data into Discord-formatted messages.
 */

import { MAX_CODE_BLOCK, MAX_TOOL_OUTPUT } from './config.ts';

// ─── Output Sanitization ─────────────────────────────────────────────────────

/**
 * Redact potential secrets from tool output before posting to Discord.
 * Matches common patterns: KEY=value, Bearer tokens, connection strings, etc.
 *
 * Strategy: multi-layer — catch env vars, inline secrets, connection URIs,
 * and bearer/authorization headers. Intentionally aggressive (false positives
 * are better than leaked secrets in a public Discord channel).
 */
/**
 * Matches sensitive key names in compound identifiers (e.g. MONGO_URL, JWT_SECRET, API_KEY).
 * Uses looser boundaries — checks if sensitive word appears anywhere in the key name,
 * not just as a standalone word (underscore-separated names like JWT_SECRET need this).
 */
const SECRET_KEY_PATTERN = /(?:^|[^a-z])(pass(?:word)?|secret|token|api[_-]?key|private[_-]?key|auth|credential|mongo|database[_-]?url|connection[_-]?string|jwt|session[_-]?secret|encryption[_-]?key|access[_-]?key|client[_-]?secret|signing[_-]?key)(?:$|[^a-z])/i;

/** Connection string URIs (mongodb://, postgres://, redis://, mysql://, amqp://) */
const CONNECTION_URI_PATTERN = /\b(mongodb(\+srv)?|postgres(ql)?|mysql|redis|amqp|mssql):\/\/[^\s"']+/gi;

/** Bearer and Authorization header values (captures full "Authorization: Bearer <token>" pattern) */
const BEARER_PATTERN = /\bBearer\s+\S+|\bAuthorization[:\s]+\S+(?:\s+\S+)?/gi;

/** Long hex/base64 strings that look like tokens (40+ chars). Uses negative lookbehind
 *  instead of \b to correctly match strings starting with +/ (non-word chars). */
const LONG_TOKEN_PATTERN = /(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{40,}=*(?![A-Za-z0-9+/=])/g;

/** Discord mention patterns that could ping everyone */
const MENTION_PATTERN = /@(everyone|here)/g;

export function sanitizeOutput(output: string): string {
  // First pass: redact connection URIs globally
  let sanitized = output.replace(CONNECTION_URI_PATTERN, (match) => {
    const proto = match.split('://')[0];
    return `${proto}://[REDACTED]`;
  });

  // Second pass: redact bearer/auth headers
  sanitized = sanitized.replace(BEARER_PATTERN, (match) => {
    const prefix = match.split(/[:\s]/)[0];
    return `${prefix} [REDACTED]`;
  });

  // Third pass: redact long standalone tokens (hex/base64 strings 40+ chars)
  sanitized = sanitized.replace(LONG_TOKEN_PATTERN, '[REDACTED_TOKEN]');

  // Fourth pass: neutralize @everyone/@here mentions
  sanitized = sanitized.replace(MENTION_PATTERN, '@\u200b$1');

  // Fifth pass: per-line checks using SECRET_KEY_PATTERN
  return sanitized.split('\n').map(line => {
    // Redact KEY=VALUE or KEY: VALUE patterns where key looks sensitive
    // Extract the variable name and test against SECRET_KEY_PATTERN
    const kvMatch = line.match(/^(\s*(?:export\s+)?([\w.-]+)\s*[=:]\s*).+/);
    if (kvMatch && SECRET_KEY_PATTERN.test(kvMatch[2])) {
      return kvMatch[1] + '[REDACTED]';
    }
    return line;
  }).join('\n');
}

// ─── Session Formatters ──────────────────────────────────────────────────────

export function formatSessionCreated(info: any): string {
  const title = info.title || 'Untitled';
  const slug = info.slug || info.id;
  const dir = info.directory || '?';
  return `🆕 **New Session** — \`${slug}\`\n> ${title}\n📁 \`${dir}\``;
}

export function formatSessionIdle(sessionId: string, sessions: Map<string, any>): string {
  const session = sessions.get(sessionId);
  if (!session) return `✅ **Session Idle** — \`${sessionId}\``;

  const slug = session.slug || sessionId;
  const title = session.title || '';
  const summary = session.summary;
  const parts: string[] = [`✅ **Session Complete** — \`${slug}\``];

  if (title) parts.push(`> ${title}`);

  if (summary) {
    const stats: string[] = [];
    if (summary.additions) stats.push(`+${summary.additions}`);
    if (summary.deletions) stats.push(`-${summary.deletions}`);
    if (summary.files) stats.push(`${summary.files} file(s)`);
    if (stats.length > 0) parts.push(`📊 ${stats.join(' | ')}`);
  }

  // Aggregate cost/tokens from tracked messages
  const msgs = session.messages || {};
  let totalCost = 0;
  let totalInput = 0;
  let totalOutput = 0;
  let totalReasoning = 0;

  for (const msg of Object.values(msgs) as any[]) {
    if (msg.role === 'assistant' && msg.tokens) {
      totalCost += msg.cost || 0;
      totalInput += msg.tokens.input || 0;
      totalOutput += msg.tokens.output || 0;
      totalReasoning += msg.tokens.reasoning || 0;
    }
  }

  if (totalInput + totalOutput > 0) {
    const tokenParts = [`in: ${totalInput.toLocaleString()}`];
    tokenParts.push(`out: ${totalOutput.toLocaleString()}`);
    if (totalReasoning > 0) tokenParts.push(`reasoning: ${totalReasoning.toLocaleString()}`);
    parts.push(`🔢 ${tokenParts.join(' | ')}`);
  }

  if (totalCost > 0) {
    parts.push(`💰 $${totalCost.toFixed(4)}`);
  }

  return parts.join('\n');
}

// ─── Message Part Formatters ─────────────────────────────────────────────────

export function formatUserMessage(part: any, sessions: Map<string, any>): string | null {
  const text = part.text?.trim();
  if (!text) return null;

  const session = sessions.get(part.sessionID);
  const slug = session?.slug || part.sessionID?.slice(0, 12);

  // Truncate long prompts (keep first 1500 chars for Discord limit)
  const display = text.length > 1500
    ? text.slice(0, 1500) + `\n\n*… truncated (${text.length} chars total)*`
    : text;

  return `📋 **Prompt** · \`${slug}\`\n${sanitizeOutput(display)}`;
}

export function formatAgentText(part: any, sessions: Map<string, any>): string | null {
  const text = part.text?.trim();
  if (!text) return null;

  const session = sessions.get(part.sessionID);
  const slug = session?.slug || part.sessionID?.slice(0, 12);

  // Find agent name from the parent message
  const agent = session?.messages?.[part.messageID]?.agent || session?.messages?.[part.messageID]?.mode || '?';

  return `💬 **${agent}** · \`${slug}\`\n${sanitizeOutput(text)}`;
}

export function formatReasoning(part: any, sessions: Map<string, any>): string | null {
  const text = part.text?.trim();
  if (!text) return null;

  const session = sessions.get(part.sessionID);
  const slug = session?.slug || part.sessionID?.slice(0, 12);
  const agent = session?.messages?.[part.messageID]?.agent || '?';

  // Sanitize + truncate, then wrap in spoiler tags (collapsible-ish in Discord)
  const sanitized = sanitizeOutput(text);
  const truncated = sanitized.length > MAX_CODE_BLOCK
    ? sanitized.slice(0, MAX_CODE_BLOCK) + '\n… *(truncated)*'
    : sanitized;

  return `🧠 **${agent}** · \`${slug}\`\n||${truncated}||`;
}

export function formatToolCall(part: any, sessions: Map<string, any>): string | null {
  if (!part.tool) return null;

  const session = sessions.get(part.sessionID);
  const slug = session?.slug || part.sessionID?.slice(0, 12);
  const agent = session?.messages?.[part.messageID]?.agent || '?';

  const toolName = part.tool;
  const status = part.state?.status || 'unknown';
  const statusEmoji = status === 'completed' ? '✅' : status === 'error' ? '❌' : status === 'running' ? '⏳' : '🔧';

  const lines: string[] = [`${statusEmoji} **${toolName}** · ${agent} · \`${slug}\``];

  // Format input
  const input = part.state?.input;
  if (input) {
    const title = part.state?.title || '';
    if (title) lines.push(`📄 \`${title}\``);

    // Show key input fields
    if (typeof input === 'object') {
      const inputStr = formatToolInput(toolName, input);
      if (inputStr) lines.push(inputStr);
    }
  }

  // Format output (only on completion) — sanitize to prevent secret leaks
  if (status === 'completed' && part.state?.output) {
    const rawOutput = String(part.state.output);
    const output = sanitizeOutput(rawOutput);
    if (output.length > MAX_TOOL_OUTPUT) {
      lines.push(`\`\`\`\n${output.slice(0, MAX_TOOL_OUTPUT)}\n… (truncated)\n\`\`\``);
    } else if (output.trim()) {
      lines.push(`\`\`\`\n${output}\n\`\`\``);
    }
  }

  // Error output — sanitize to prevent secret leaks in error messages
  if (status === 'error' && part.state?.error) {
    const sanitizedError = sanitizeOutput(String(part.state.error).slice(0, 500));
    lines.push(`❌ \`${sanitizedError}\``);
  }

  return lines.join('\n');
}

function formatToolInput(tool: string, input: any): string {
  switch (tool) {
    case 'write':
    case 'create':
      return `> Writing to \`${input.filePath || input.file_path || '?'}\``;
    case 'read':
      return `> Reading \`${input.filePath || input.file_path || input.path || '?'}\``;
    case 'edit':
    case 'patch':
      return `> Editing \`${input.filePath || input.file_path || '?'}\``;
    case 'bash':
    case 'shell':
    case 'exec': {
      const cmd = input.command || input.cmd || '';
      // Sanitize commands — they may contain inline secrets, env vars, or API keys
      return `> \`$ ${sanitizeOutput(cmd).slice(0, 200)}\``;
    }
    case 'glob':
    case 'search':
      return `> Pattern: \`${input.pattern || input.query || input.glob || '?'}\``;
    case 'fetch':
      // Sanitize URLs — may contain API keys in query parameters
      return `> URL: \`${sanitizeOutput(input.url || '?')}\``;
    default:
      // Generic: show first string value, sanitized
      for (const [k, v] of Object.entries(input)) {
        if (typeof v === 'string' && v.length > 0 && v.length < 200) {
          return `> ${k}: \`${sanitizeOutput(v)}\``;
        }
      }
      return '';
  }
}

// ─── Diff Formatter ──────────────────────────────────────────────────────────

export function formatDiffs(sessionId: string, diffs: any[], sessions: Map<string, any>): string | null {
  if (!diffs || diffs.length === 0) return null;

  const session = sessions.get(sessionId);
  const slug = session?.slug || sessionId?.slice(0, 12);

  const parts: string[] = [`📝 **Diffs** · \`${slug}\``];

  for (const diff of diffs) {
    const file = diff.file || diff.path || '?';
    const adds = diff.additions ?? 0;
    const dels = diff.deletions ?? 0;
    parts.push(`\n**\`${file}\`** (+${adds}/-${dels})`);

    // Show the actual diff if available — sanitize to prevent secret leaks from config files
    if (diff.before !== undefined && diff.after !== undefined) {
      const diffContent = sanitizeOutput(formatNaiveDiff(diff.before, diff.after));
      if (diffContent.length < MAX_CODE_BLOCK) {
        parts.push(`\`\`\`diff\n${diffContent}\n\`\`\``);
      } else {
        parts.push(`\`\`\`diff\n${diffContent.slice(0, MAX_CODE_BLOCK)}\n… (truncated)\n\`\`\``);
      }
    }
  }

  return parts.join('\n');
}

/**
 * Naive line-by-line diff. Compares lines at the same index — NOT a real
 * unified diff (insertions shift all subsequent lines). Good enough for
 * quick Discord previews of small changes.
 */
function formatNaiveDiff(before: string, after: string): string {
  const beforeLines = before.split('\n');
  const afterLines = after.split('\n');
  const lines: string[] = [];

  const maxLines = Math.max(beforeLines.length, afterLines.length);
  for (let i = 0; i < maxLines && lines.length < 50; i++) {
    const bLine = beforeLines[i];
    const aLine = afterLines[i];

    if (bLine === aLine) {
      if (bLine !== undefined) lines.push(` ${bLine}`);
    } else {
      if (bLine !== undefined) lines.push(`-${bLine}`);
      if (aLine !== undefined) lines.push(`+${aLine}`);
    }
  }

  if (maxLines > 50) lines.push(`... (${maxLines - 50} more lines)`);
  return lines.join('\n');
}

// ─── Step Formatters ─────────────────────────────────────────────────────────

export function formatStepFinish(part: any, sessions: Map<string, any>): string | null {
  const tokens = part.tokens;
  if (!tokens) return null;

  const session = sessions.get(part.sessionID);
  const slug = session?.slug || part.sessionID?.slice(0, 12);
  const agent = session?.messages?.[part.messageID]?.agent || '?';

  const reason = part.reason || 'unknown';
  const reasonEmoji = reason === 'stop' ? '✅' : reason === 'tool-calls' ? '🔧' : '⚠️';

  const tokenParts: string[] = [];
  if (tokens.input) tokenParts.push(`in: ${tokens.input.toLocaleString()}`);
  if (tokens.output) tokenParts.push(`out: ${tokens.output.toLocaleString()}`);
  if (tokens.reasoning) tokenParts.push(`think: ${tokens.reasoning.toLocaleString()}`);
  if (tokens.cache?.read) tokenParts.push(`cache↓: ${tokens.cache.read.toLocaleString()}`);
  if (tokens.cache?.write) tokenParts.push(`cache↑: ${tokens.cache.write.toLocaleString()}`);

  const cost = part.cost ? ` · $${part.cost.toFixed(4)}` : '';

  return `${reasonEmoji} **Step done** · ${agent} · \`${slug}\`${cost}\n🔢 ${tokenParts.join(' | ')}`;
}
