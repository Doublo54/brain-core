import { ToolPolicySchema } from "openclaw/plugin-sdk";
import { z } from "zod";

const channelConfigSchema = z.object({
  allow: z.boolean().optional(),
  requireMention: z.boolean().optional(),
  users: z.array(z.string()).optional(),
  tools: ToolPolicySchema.optional(),
});

const guildConfigSchema = z.object({
  channels: z.object({}).catchall(channelConfigSchema).optional(),
});

const approvalSchema = z.object({
  mode: z.enum(["manual", "auto", "auto-allowlist"]).optional(),
  timeoutSeconds: z.number().int().nonnegative().optional(),
  notifySavedMessages: z.boolean().optional(),
});

const rateLimitSchema = z.object({
  minIntervalSeconds: z.number().int().positive().optional(),
  maxPendingDrafts: z.number().int().positive().optional(),
});

export const DiscordUserAccountSchema = z.object({
  name: z.string().optional(),
  enabled: z.boolean().optional(),
  token: z.string().optional(),
  dmPolicy: z.enum(["pairing", "allowlist", "open", "disabled"]).optional(),
  allowFrom: z.array(z.union([z.string(), z.number()])).optional(),
  guilds: z.object({}).catchall(guildConfigSchema).optional(),
  mediaMaxMb: z.number().positive().optional(),
  historyLimit: z.number().int().positive().optional(),
  replyToMode: z.enum(["off", "thread", "reply"]).optional(),
  approval: approvalSchema.optional(),
  rateLimit: rateLimitSchema.optional(),
});

export const DiscordUserConfigSchema = DiscordUserAccountSchema.extend({
  accounts: z.object({}).catchall(DiscordUserAccountSchema).optional(),
  defaultAccount: z.string().optional(),
});
