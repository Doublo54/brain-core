/**
 * opencode-discord-pipe — Configuration
 *
 * Channel IDs and settings for routing OpenCode events to Discord.
 */

export const OPENCODE_URL = process.env.OPENCODE_URL || 'http://localhost:4096';

// Discord channel IDs — loaded from .env.local (see .env.local.example)
// No hardcoded fallbacks: if channels not configured, fail fast
function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    console.error(`[config] Missing required env var: ${name}`);
    console.error(`[config] Configure channels in .env.local (copy from .env.local.example)`);
    process.exit(1);
  }
  return value;
}

export const CHANNELS = {
  /** Agent text responses */
  agent: requireEnv('CHANNEL_AGENT'),
  /** Tool calls and results */
  tools: requireEnv('CHANNEL_TOOLS'),
  /** Code diffs */
  diffs: requireEnv('CHANNEL_DIFFS'),
  /** Reasoning / thinking */
  thinking: requireEnv('CHANNEL_THINKING'),
  /** Session lifecycle (start, idle, status) */
  status: requireEnv('CHANNEL_STATUS'),
} as const;

// Discord bot token for direct API posting (from environment)
export const DISCORD_BOT_TOKEN = process.env.DISCORD_BOT_TOKEN || '';

// Formatting limits
export const MAX_DISCORD_MSG = 2000;
export const MAX_CODE_BLOCK = 1800; // leave room for formatting
export const MAX_TOOL_OUTPUT = 1200;

// SSE reconnect settings
export const SSE_RECONNECT_DELAY_MS = 3000;
export const SSE_MAX_RECONNECT_DELAY_MS = 30000;

// Debounce: wait for streaming text to finish before posting
export const TEXT_DEBOUNCE_MS = 2000;

// Filter out noise events
export const IGNORED_EVENT_TYPES = new Set([
  'tui.toast.show',
  'server.heartbeat',
  'todo.updated',
  'file.edited',
  'file.watcher.updated',
  'lsp.updated',
  'lsp.client.diagnostics',
]);
