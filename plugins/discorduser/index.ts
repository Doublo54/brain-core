/// <reference path="./src/typecheck-shims.d.ts" />
/// <reference lib="es2020" />

import { emptyPluginConfigSchema, type OpenClawPluginApi } from "openclaw/plugin-sdk";
import { discordUserDock, discordUserPlugin, sendDiscordUserApprovalText } from "./src/channel.js";
import {
  getDraft,
  listDrafts,
  loadDrafts,
  pruneExpired,
  removeDraft,
  saveDrafts,
} from "./src/drafts.js";
import { setDiscordUserRuntime } from "./src/userbot-runtime.js";

async function clearDrafts(accountId?: string): Promise<number> {
  const drafts = await loadDrafts();
  if (!accountId || accountId === "all") {
    const count = drafts.length;
    await saveDrafts([]);
    return count;
  }

  const remaining = drafts.filter((draft) => draft.accountId !== accountId);
  const removed = drafts.length - remaining.length;
  if (removed > 0) {
    await saveDrafts(remaining);
  }
  return removed;
}

function draftAgeSeconds(createdAtIso: string): number {
  const createdAt = Date.parse(createdAtIso);
  if (!Number.isFinite(createdAt)) return 0;
  return Math.max(0, Math.round((Date.now() - createdAt) / 1000));
}

const plugin = {
  id: "discorduser",
  name: "Discord (User)",
  description: "Discord personal account plugin via discord-user-bots",
  configSchema: emptyPluginConfigSchema(),
  register(api: OpenClawPluginApi) {
    setDiscordUserRuntime(api.runtime);
    api.registerChannel({ plugin: discordUserPlugin, dock: discordUserDock });

    api.registerCommand({
      name: "du-list",
      description: "List pending DiscordUser drafts",
      handler: async () => {
        await pruneExpired();
        const rows = await listDrafts();
        if (!rows.length) return { text: "📭 No pending drafts." };
        return {
          text: rows
            .slice(0, 20)
            .map(
              (draft) =>
                `• [${draft.id}] ${draft.senderName} (${draftAgeSeconds(draft.createdAt)}s)\n  ${draft.inboundText.slice(0, 80)}\n  ${draft.draftText.slice(0, 120)}`,
            )
            .join("\n\n"),
        };
      },
    });

    api.registerCommand({
      name: "du-approve",
      description: "Approve pending draft: /du-approve <id>",
      acceptsArgs: true,
      handler: async (ctx) => {
        const id = ctx.args?.trim();
        if (!id) return { text: "Usage: /du-approve <id>" };
        const draft = await getDraft(id);
        if (!draft) return { text: `Draft ${id} not found.` };
        try {
          await sendDiscordUserApprovalText({
            accountId: draft.accountId,
            chatId: draft.chatId,
            text: draft.draftText,
          });
          await removeDraft(id);
          return { text: `✅ Sent draft ${id} to ${draft.senderName}.` };
        } catch (err) {
          return { text: `Failed to send draft ${id}: ${String(err)}` };
        }
      },
    });

    api.registerCommand({
      name: "du-reject",
      description: "Reject pending draft: /du-reject <id>",
      acceptsArgs: true,
      handler: async (ctx) => {
        const id = ctx.args?.trim();
        if (!id) return { text: "Usage: /du-reject <id>" };
        const ok = await removeDraft(id);
        return { text: ok ? `🗑 Rejected draft ${id}.` : `Draft ${id} not found.` };
      },
    });

    api.registerCommand({
      name: "du-edit",
      description: "Edit+approve draft: /du-edit <id> <new text>",
      acceptsArgs: true,
      handler: async (ctx) => {
        const raw = ctx.args?.trim() ?? "";
        const space = raw.indexOf(" ");
        if (space < 1) return { text: "Usage: /du-edit <id> <new text>" };
        const id = raw.slice(0, space).trim();
        const edited = raw.slice(space + 1).trim();
        if (!edited) return { text: "Usage: /du-edit <id> <new text>" };

        const draft = await getDraft(id);
        if (!draft) return { text: `Draft ${id} not found.` };

        try {
          await sendDiscordUserApprovalText({
            accountId: draft.accountId,
            chatId: draft.chatId,
            text: edited,
          });
          await removeDraft(id);
          return { text: `✏️ Sent edited draft ${id} to ${draft.senderName}.` };
        } catch (err) {
          return { text: `Failed to send edited draft ${id}: ${String(err)}` };
        }
      },
    });

    api.registerCommand({
      name: "du-view",
      description: "View draft details: /du-view <id>",
      acceptsArgs: true,
      handler: async (ctx) => {
        const id = ctx.args?.trim();
        if (!id) return { text: "Usage: /du-view <id>" };
        const draft = await getDraft(id);
        if (!draft) return { text: `Draft ${id} not found.` };
        return {
          text: [
            `Draft [${draft.id}] from ${draft.senderName}`,
            `Inbound: ${draft.inboundText}`,
            "",
            `Draft: ${draft.draftText}`,
          ].join("\n"),
        };
      },
    });

    api.registerCommand({
      name: "du-clear",
      description: "Clear drafts: /du-clear [accountId|all]",
      acceptsArgs: true,
      handler: async (ctx) => {
        await pruneExpired();
        const arg = ctx.args?.trim();
        if (!arg || arg === "all") {
          const count = await clearDrafts();
          return { text: `🧹 Cleared ${count} draft(s).` };
        }
        const count = await clearDrafts(arg);
        return { text: `🧹 Cleared ${count} draft(s) for account ${arg}.` };
      },
    });
  },
};

export default plugin;
