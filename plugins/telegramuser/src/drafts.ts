import { randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export type PendingDraft = {
  id: string;
  accountId: string;
  chatId: string;
  senderId: string;
  senderLabel: string;
  inboundText: string;
  draftText: string;
  createdAt: number;
  expiresAt?: number;
};

const drafts = new Map<string, PendingDraft>();
const DRAFTS_PATH =
  process.env.OPENCLAW_TELEGRAMUSER_DRAFTS ??
  join(homedir(), ".openclaw", "state", "telegramuser-drafts.json");

function persistDrafts() {
  try {
    mkdirSync(dirname(DRAFTS_PATH), { recursive: true });
    const tempPath = `${DRAFTS_PATH}.tmp`;
    writeFileSync(tempPath, JSON.stringify(Array.from(drafts.values())), "utf8");
    renameSync(tempPath, DRAFTS_PATH);
  } catch (err) {
    console.error(`[telegramuser] failed to persist drafts to ${DRAFTS_PATH}: ${String(err)}`);
  }
}

(function loadDrafts() {
  try {
    const raw = readFileSync(DRAFTS_PATH, "utf8");
    const rows = JSON.parse(raw) as PendingDraft[];
    for (const row of rows) {
      if (row?.id) drafts.set(row.id, row);
    }
  } catch (err) {
    if ((err as { code?: string })?.code !== "ENOENT") {
      console.error(`[telegramuser] failed to load drafts from ${DRAFTS_PATH}: ${String(err)}`);
    }
  }
})();

export function createDraft(input: Omit<PendingDraft, "id" | "createdAt">): PendingDraft {
  let id = randomUUID();
  while (drafts.has(id)) {
    id = randomUUID();
  }
  const draft: PendingDraft = {
    ...input,
    id,
    createdAt: Date.now(),
  };
  drafts.set(id, draft);
  persistDrafts();
  return draft;
}

export function tryCreateDraft(
  input: Omit<PendingDraft, "id" | "createdAt">,
  maxPending: number,
  accountId?: string,
): PendingDraft | null {
  const existing = listDrafts(accountId);
  if (existing.length >= maxPending) return null;
  return createDraft(input);
}

export function getDraft(id: string): PendingDraft | undefined {
  return drafts.get(id);
}

export function resolveDraftText(id: string, edited?: string): PendingDraft | undefined {
  const draft = drafts.get(id);
  if (!draft) return undefined;
  drafts.delete(id);
  persistDrafts();
  return {
    ...draft,
    draftText: edited?.trim() ? edited.trim() : draft.draftText,
  };
}

export function rejectDraft(id: string): boolean {
  const ok = drafts.delete(id);
  if (ok) persistDrafts();
  return ok;
}

export function clearDrafts(accountId?: string): number {
  if (!accountId) {
    const count = drafts.size;
    drafts.clear();
    persistDrafts();
    return count;
  }
  let count = 0;
  for (const draft of drafts.values()) {
    if (draft.accountId === accountId) {
      drafts.delete(draft.id);
      count += 1;
    }
  }
  if (count) persistDrafts();
  return count;
}

export function listDrafts(accountId?: string): PendingDraft[] {
  const now = Date.now();
  let pruned = false;
  const rows = Array.from(drafts.values()).filter((d) => {
    if (d.expiresAt && d.expiresAt <= now) {
      drafts.delete(d.id);
      pruned = true;
      return false;
    }
    if (accountId && d.accountId !== accountId) return false;
    return true;
  });
  if (pruned) persistDrafts();
  rows.sort((a, b) => b.createdAt - a.createdAt);
  return rows;
}
