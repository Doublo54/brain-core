import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";

async function loadDraftsWithTempStore() {
  const previous = process.env.OPENCLAW_DISCORDUSER_DRAFTS;
  const dir = mkdtempSync(join(tmpdir(), "discorduser-drafts-test-"));
  const storePath = join(dir, "drafts.json");
  process.env.OPENCLAW_DISCORDUSER_DRAFTS = storePath;
  vi.resetModules();
  const base = new URL("./drafts.ts", import.meta.url).href;
  const mod = await import(`${base}?t=${Date.now()}`);
  const restoreEnv = () => {
    if (previous == null) {
      delete process.env.OPENCLAW_DISCORDUSER_DRAFTS;
    } else {
      process.env.OPENCLAW_DISCORDUSER_DRAFTS = previous;
    }
  };
  return { mod, storePath, restoreEnv };
}

const baseDraft = {
  accountId: "default",
  chatId: "123456",
  senderName: "TestUser",
  senderId: "u1",
  inboundText: "hello",
  draftText: "hi back",
};

describe("discorduser drafts store", () => {
  it("persists a created draft to disk", async () => {
    const { mod, storePath, restoreEnv } = await loadDraftsWithTempStore();
    try {
      const id = await mod.addDraft(baseDraft);
      expect(typeof id).toBe("string");
      const raw = readFileSync(storePath, "utf8");
      expect(raw).toContain(id);
    } finally {
      restoreEnv();
    }
  });

  it("retrieves a draft by id", async () => {
    const { mod, restoreEnv } = await loadDraftsWithTempStore();
    try {
      const id = await mod.addDraft(baseDraft);
      const draft = await mod.getDraft(id);
      expect(draft).not.toBeNull();
      expect(draft.draftText).toBe("hi back");
      expect(draft.accountId).toBe("default");
    } finally {
      restoreEnv();
    }
  });

  it("removes a draft", async () => {
    const { mod, restoreEnv } = await loadDraftsWithTempStore();
    try {
      const id = await mod.addDraft(baseDraft);
      const removed = await mod.removeDraft(id);
      expect(removed).toBe(true);
      const draft = await mod.getDraft(id);
      expect(draft).toBeNull();
    } finally {
      restoreEnv();
    }
  });

  it("returns false when removing non-existent draft", async () => {
    const { mod, restoreEnv } = await loadDraftsWithTempStore();
    try {
      const removed = await mod.removeDraft("non-existent-id");
      expect(removed).toBe(false);
    } finally {
      restoreEnv();
    }
  });

  it("lists active drafts and auto-prunes expired ones", async () => {
    const { mod, restoreEnv } = await loadDraftsWithTempStore();
    try {
      await mod.addDraft(baseDraft, 0);
      const activeId = await mod.addDraft({ ...baseDraft, draftText: "active" }, 3600);
      const rows = await mod.listDrafts();
      expect(rows.length).toBe(1);
      expect(rows[0].id).toBe(activeId);
    } finally {
      restoreEnv();
    }
  });

  it("lists drafts filtered by accountId", async () => {
    const { mod, restoreEnv } = await loadDraftsWithTempStore();
    try {
      await mod.addDraft({ ...baseDraft, accountId: "sales" });
      await mod.addDraft({ ...baseDraft, accountId: "support" });
      const salesDrafts = await mod.listDrafts("sales");
      expect(salesDrafts.length).toBe(1);
      expect(salesDrafts[0].accountId).toBe("sales");
    } finally {
      restoreEnv();
    }
  });

  it("pruneExpired removes only expired drafts", async () => {
    const { mod, restoreEnv } = await loadDraftsWithTempStore();
    try {
      await mod.addDraft(baseDraft, 0);
      await mod.addDraft({ ...baseDraft, draftText: "keep" }, 3600);
      const removed = await mod.pruneExpired();
      expect(removed).toBe(1);
      const remaining = await mod.listDrafts();
      expect(remaining.length).toBe(1);
      expect(remaining[0].draftText).toBe("keep");
    } finally {
      restoreEnv();
    }
  });
});
