import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";

async function loadDraftsWithTempStore() {
  const previous = process.env.OPENCLAW_TELEGRAMUSER_DRAFTS;
  const dir = mkdtempSync(join(tmpdir(), "telegramuser-drafts-"));
  const storePath = join(dir, "drafts.json");
  process.env.OPENCLAW_TELEGRAMUSER_DRAFTS = storePath;
  vi.resetModules();
  const base = new URL("./drafts.ts", import.meta.url).href;
  const mod = await import(`${base}?t=${Date.now()}`);
  const restoreEnv = () => {
    if (previous == null) {
      delete process.env.OPENCLAW_TELEGRAMUSER_DRAFTS;
    } else {
      process.env.OPENCLAW_TELEGRAMUSER_DRAFTS = previous;
    }
  };
  return { mod, storePath, restoreEnv };
}

describe("telegramuser drafts store", () => {
  it("persists created drafts", async () => {
    const { mod, storePath, restoreEnv } = await loadDraftsWithTempStore();
    try {
      mod.clearDrafts();
      const created = mod.createDraft({
        accountId: "sales",
        chatId: "123",
        senderId: "u1",
        senderLabel: "User 1",
        inboundText: "hello",
        draftText: "hi",
      });
      const raw = readFileSync(storePath, "utf8");
      expect(raw).toContain(created.id);
    } finally {
      restoreEnv();
    }
  });

  it("resolves draft with edited text", async () => {
    const { mod, restoreEnv } = await loadDraftsWithTempStore();
    try {
      mod.clearDrafts();
      const created = mod.createDraft({
        accountId: "sales",
        chatId: "123",
        senderId: "u1",
        senderLabel: "User 1",
        inboundText: "hello",
        draftText: "hi",
      });
      const resolved = mod.resolveDraftText(created.id, "updated");
      expect(resolved?.draftText).toBe("updated");
      expect(mod.getDraft(created.id)).toBeUndefined();
    } finally {
      restoreEnv();
    }
  });

  it("prunes expired drafts on list", async () => {
    const { mod, restoreEnv } = await loadDraftsWithTempStore();
    try {
      mod.clearDrafts();
      mod.createDraft({
        accountId: "sales",
        chatId: "123",
        senderId: "u1",
        senderLabel: "User 1",
        inboundText: "hello",
        draftText: "hi",
        expiresAt: Date.now() - 1,
      });
      const rows = mod.listDrafts();
      expect(rows.length).toBe(0);
    } finally {
      restoreEnv();
    }
  });
});
