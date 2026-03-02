import type { OpenClawConfig } from "openclaw/plugin-sdk";
import { DEFAULT_ACCOUNT_ID } from "openclaw/plugin-sdk";

export type DiscordUserAccountConfig = {
  name?: string;
  enabled?: boolean;
  token?: string;
  dmPolicy?: "pairing" | "allowlist" | "open" | "disabled";
  allowFrom?: (string | number)[];
  guilds?: Record<
    string,
    {
      channels?: Record<
        string,
        {
          allow?: boolean;
          requireMention?: boolean;
          users?: string[];
          tools?: unknown;
        }
      >;
    }
  >;
  mediaMaxMb?: number;
  historyLimit?: number;
  replyToMode?: "off" | "thread" | "reply";
  approval?: {
    mode?: "manual" | "auto" | "auto-allowlist";
    timeoutSeconds?: number;
    notifySavedMessages?: boolean;
  };
  rateLimit?: {
    minIntervalSeconds?: number;
    maxPendingDrafts?: number;
  };
};

type TokenSource = "env" | "config" | "none";

export type ResolvedDiscordUserAccount = {
  accountId: string;
  name?: string;
  enabled: boolean;
  token: string;
  tokenSource: TokenSource;
  config: DiscordUserAccountConfig;
};

export function listDiscordUserAccountIds(cfg: OpenClawConfig): string[] {
  const base = cfg.channels?.discorduser;
  const ids = new Set<string>();
  if (base) {
    ids.add(DEFAULT_ACCOUNT_ID);
  }
  const accountIds = Object.keys(base?.accounts ?? {});
  for (const id of accountIds) ids.add(id);
  return Array.from(ids);
}

export function defaultAccountId(cfg: OpenClawConfig): string {
  return cfg.channels?.discorduser?.defaultAccount ?? DEFAULT_ACCOUNT_ID;
}

export function resolveDiscordUserAccount(params: {
  cfg: OpenClawConfig;
  accountId?: string | null;
}): ResolvedDiscordUserAccount {
  const accountId = params.accountId?.trim() || defaultAccountId(params.cfg);
  const base = params.cfg.channels?.discorduser ?? {};
  const scoped =
    accountId === DEFAULT_ACCOUNT_ID
      ? base
      : { ...base, ...(base.accounts?.[accountId] ?? {}) };

  const resolveToken = (): { token: string; source: TokenSource } => {
    if (accountId === DEFAULT_ACCOUNT_ID) {
      const envToken = process.env.DISCORD_USER_TOKEN?.trim();
      if (envToken) return { token: envToken, source: "env" };
    }

    const configToken = scoped.token?.trim();
    if (configToken) {
      return { token: configToken, source: "config" };
    }

    return { token: "", source: "none" };
  };

  const { token, source: tokenSource } = resolveToken();

  return {
    accountId,
    name: scoped.name,
    enabled: scoped.enabled !== false,
    token,
    tokenSource,
    config: scoped,
  };
}

export function describeAccount(account: ResolvedDiscordUserAccount): string {
  const parts: string[] = [];
  
  if (account.name) {
    parts.push(`name="${account.name}"`);
  }
  
  parts.push(`accountId="${account.accountId}"`);
  parts.push(`enabled=${account.enabled}`);
  parts.push(`tokenSource=${account.tokenSource}`);
  
  if (account.token) {
    const masked = account.token.slice(0, 8) + "..." + account.token.slice(-4);
    parts.push(`token=${masked}`);
  } else {
    parts.push("token=<none>");
  }

  return `DiscordUserAccount(${parts.join(", ")})`;
}

export function isConfigured(account: ResolvedDiscordUserAccount): boolean {
  return account.token.length > 0;
}

export function setAccountEnabled(params: {
  cfg: OpenClawConfig;
  accountId: string;
  enabled: boolean;
}): void {
  const base = (params.cfg as any).channels?.discorduser;
  if (!base) return;
  if (params.accountId === DEFAULT_ACCOUNT_ID) {
    base.enabled = params.enabled;
  } else if (base.accounts?.[params.accountId]) {
    base.accounts[params.accountId].enabled = params.enabled;
  }
}

export function deleteAccount(params: {
  cfg: OpenClawConfig;
  accountId: string;
}): void {
  const base = (params.cfg as any).channels?.discorduser;
  if (!base?.accounts) return;
  delete base.accounts[params.accountId];
}
