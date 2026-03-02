import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { emptyPluginConfigSchema } from "openclaw/plugin-sdk";
import { clearDrafts, getDraft, listDrafts, rejectDraft, resolveDraftText } from "./src/drafts.js";
import { sendUserMessage, telegramUserDock, telegramUserPlugin } from "./src/channel.js";
import { markUserOutbound, setTelegramRuntime } from "./src/runtime.js";

const plugin = {
  id: "telegramuser",
  name: "Telegram User",
  description: "Telegram personal account plugin via GramJS (MTProto)",
  configSchema: emptyPluginConfigSchema(),
  register(api: OpenClawPluginApi) {
    console.log("[telegramuser] register() called");
    setTelegramRuntime(api.runtime);
    try {
      console.log("[telegramuser] registering channel plugin telegramuser");
      api.registerChannel({ plugin: telegramUserPlugin, dock: telegramUserDock });
      console.log("[telegramuser] registerChannel(telegramuser) ok");
    } catch (err) {
      console.error(`[telegramuser] registerChannel failed: ${String(err)}`);
      throw err;
    }

    api.registerCommand({
      name: "tgu_list",
      description: "List pending TelegramUser drafts",
      handler: async () => {
        const rows = listDrafts();
        if (!rows.length) return { text: "No pending drafts." };
        return {
          text: rows
            .slice(0, 20)
            .map(
              (d) =>
                `[${d.id}] ${d.senderLabel} (${Math.round((Date.now() - d.createdAt) / 1000)}s)\n  in: ${d.inboundText.slice(0, 80)}\n  draft: ${d.draftText.slice(0, 120)}`,
            )
            .join("\n\n"),
        };
      },
    });

    api.registerCommand({
      name: "tgu_approve",
      description: "Approve pending draft: /tgu_approve <id>",
      acceptsArgs: true,
      handler: async (ctx) => {
        const id = ctx.args?.trim();
        if (!id) return { text: "Usage: /tgu_approve <id>" };
        const draft = resolveDraftText(id);
        if (!draft) return { text: `Draft ${id} not found.` };
        await sendUserMessage(draft.chatId, draft.draftText, { accountId: draft.accountId });
        markUserOutbound(draft.accountId);
        return { text: `Sent draft ${id} to ${draft.senderLabel}.` };
      },
    });

    api.registerCommand({
      name: "tgu_edit",
      description: "Edit+approve draft: /tgu_edit <id> <new text>",
      acceptsArgs: true,
      handler: async (ctx) => {
        const raw = ctx.args?.trim() ?? "";
        const space = raw.indexOf(" ");
        if (space < 1) return { text: "Usage: /tgu_edit <id> <new text>" };
        const id = raw.slice(0, space).trim();
        const edited = raw.slice(space + 1).trim();
        if (!edited) return { text: "Usage: /tgu_edit <id> <new text>" };
        const draft = resolveDraftText(id, edited);
        if (!draft) return { text: `Draft ${id} not found.` };
        await sendUserMessage(draft.chatId, draft.draftText, { accountId: draft.accountId });
        markUserOutbound(draft.accountId);
        return { text: `Sent edited draft ${id} to ${draft.senderLabel}.` };
      },
    });

    api.registerCommand({
      name: "tgu_reject",
      description: "Reject pending draft: /tgu_reject <id>",
      acceptsArgs: true,
      handler: async (ctx) => {
        const id = ctx.args?.trim();
        if (!id) return { text: "Usage: /tgu_reject <id>" };
        const ok = rejectDraft(id);
        return { text: ok ? `Rejected draft ${id}.` : `Draft ${id} not found.` };
      },
    });

    api.registerCommand({
      name: "tgu_view",
      description: "View draft details: /tgu_view <id>",
      acceptsArgs: true,
      handler: async (ctx) => {
        const id = ctx.args?.trim();
        if (!id) return { text: "Usage: /tgu_view <id>" };
        const d = getDraft(id);
        if (!d) return { text: `Draft ${id} not found.` };
        return {
          text: [
            `Draft [${d.id}] from ${d.senderLabel}`,
            `Inbound: ${d.inboundText}`,
            "",
            `Draft: ${d.draftText}`,
          ].join("\n"),
        };
      },
    });

    api.registerCommand({
      name: "tgu_clear",
      description: "Clear drafts: /tgu_clear [accountId|all]",
      acceptsArgs: true,
      handler: async (ctx) => {
        const arg = ctx.args?.trim();
        if (!arg || arg === "all") {
          const count = clearDrafts();
          return { text: `Cleared ${count} draft(s).` };
        }
        const count = clearDrafts(arg);
        return { text: `Cleared ${count} draft(s) for account ${arg}.` };
      },
    });
  },
};

export default plugin;
