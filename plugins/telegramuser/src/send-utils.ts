/**
 * Pure utility functions for Telegram message sending.
 * Extracted from org-specific send.ts for reuse and testing.
 */

const TELEGRAM_TEXT_LIMIT = 4096;

export function chunkTelegramText(input: string): string[] {
  if (input.length <= TELEGRAM_TEXT_LIMIT) {
    return [input];
  }
  const chunks: string[] = [];
  let offset = 0;
  while (offset < input.length) {
    if (offset + TELEGRAM_TEXT_LIMIT >= input.length) {
      chunks.push(input.slice(offset));
      break;
    }

    const windowEnd = offset + TELEGRAM_TEXT_LIMIT;
    const window = input.slice(offset, windowEnd + 1);
    let cutRel = window.lastIndexOf("\n");
    let includeDelimiter = true;
    if (cutRel < Math.floor(TELEGRAM_TEXT_LIMIT * 0.6)) {
      cutRel = window.lastIndexOf(" ");
    }
    if (cutRel <= 0) {
      cutRel = TELEGRAM_TEXT_LIMIT;
      includeDelimiter = false;
    }

    chunks.push(input.slice(offset, offset + cutRel));
    offset += cutRel + (includeDelimiter ? 1 : 0);
  }
  return chunks.filter((c) => c.length > 0);
}

export function extractFloodWaitSeconds(err: unknown): number | null {
  const msg = String((err as { message?: string })?.message ?? err);
  const m = msg.match(/FLOOD_WAIT_(\d+)/i) ?? msg.match(/A wait of (\d+) seconds/i);
  if (!m?.[1]) {
    return null;
  }
  const seconds = Number(m[1]);
  if (!Number.isFinite(seconds)) {
    return null;
  }
  return Math.min(120, Math.max(1, seconds));
}

export function isTransientSendError(err: unknown): boolean {
  const msg = String((err as { message?: string })?.message ?? err).toLowerCase();
  return (
    msg.includes("timeout") ||
    msg.includes("temporar") ||
    msg.includes("network") ||
    msg.includes("connection") ||
    msg.includes("econnreset") ||
    msg.includes("eai_again")
  );
}
