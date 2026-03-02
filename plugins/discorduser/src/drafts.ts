import { randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export type Draft = {
  id: string;
  accountId: string;
  chatId: string;
  senderName: string;
  senderId: string;
  inboundText: string;
  draftText: string;
  createdAt: string;
  expiresAt: string;
};

const DRAFTS_PATH =
  process.env.OPENCLAW_DISCORDUSER_DRAFTS ??
  join(homedir(), ".openclaw", "state", "discorduser-drafts.json");

const DEFAULT_TIMEOUT_SECONDS = 3600;

let mutexChain: Promise<unknown> = Promise.resolve();
function withMutex<T>(fn: () => Promise<T>): Promise<T> {
  const next = mutexChain.catch(() => undefined).then(fn);
  mutexChain = next;
  return next;
}

export async function loadDrafts(): Promise<Draft[]> {
  try {
    const raw = readFileSync(DRAFTS_PATH, "utf8");
    const rows = JSON.parse(raw) as Draft[];
    return Array.isArray(rows) ? rows : [];
  } catch (err) {
    if ((err as { code?: string })?.code !== "ENOENT") {
      console.error(`[discorduser] failed to load drafts from ${DRAFTS_PATH}: ${String(err)}`);
    }
    return [];
  }
}

export async function saveDrafts(drafts: Draft[]): Promise<void> {
  try {
    mkdirSync(dirname(DRAFTS_PATH), { recursive: true });
    const tempPath = `${DRAFTS_PATH}.tmp`;
    writeFileSync(tempPath, JSON.stringify(drafts, null, 2), "utf8");
    renameSync(tempPath, DRAFTS_PATH);
  } catch (err) {
    console.error(`[discorduser] failed to persist drafts to ${DRAFTS_PATH}: ${String(err)}`);
    throw err;
  }
}

export function addDraft(
  input: Omit<Draft, "id" | "createdAt" | "expiresAt">,
  timeoutSeconds = DEFAULT_TIMEOUT_SECONDS,
): Promise<string> {
  return withMutex(async () => {
    const drafts = await loadDrafts();
    let id = randomUUID();
    while (drafts.some((d) => d.id === id)) {
      id = randomUUID();
    }
    const now = new Date();
    const expiresAt = new Date(now.getTime() + timeoutSeconds * 1000);
    const draft: Draft = {
      ...input,
      id,
      createdAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
    };
    drafts.push(draft);
    await saveDrafts(drafts);
    return id;
  });
}

export function removeDraft(draftId: string): Promise<boolean> {
  return withMutex(async () => {
    const drafts = await loadDrafts();
    const initialLength = drafts.length;
    const filtered = drafts.filter((d) => d.id !== draftId);
    if (filtered.length === initialLength) {
      return false;
    }
    await saveDrafts(filtered);
    return true;
  });
}

export async function getDraft(draftId: string): Promise<Draft | null> {
  const drafts = await loadDrafts();
  return drafts.find((d) => d.id === draftId) ?? null;
}

export async function listDrafts(accountId?: string): Promise<Draft[]> {
  const drafts = await loadDrafts();
  const now = new Date();
  const active = drafts.filter((d) => new Date(d.expiresAt) > now);
  if (active.length !== drafts.length) {
    await saveDrafts(active).catch(() => {});
  }
  if (!accountId) {
    return active;
  }
  return active.filter((d) => d.accountId === accountId);
}

export function pruneExpired(): Promise<number> {
  return withMutex(async () => {
    const drafts = await loadDrafts();
    const now = new Date();
    const initialLength = drafts.length;
    const filtered = drafts.filter((d) => new Date(d.expiresAt) > now);
    const removed = initialLength - filtered.length;
    if (removed > 0) {
      await saveDrafts(filtered);
    }
    return removed;
  });
}
