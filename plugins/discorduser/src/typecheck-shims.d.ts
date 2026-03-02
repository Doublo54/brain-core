declare module "openclaw/plugin-sdk" {
  export type ChannelDock = {
    id: string;
    capabilities?: {
      chatTypes?: string[];
      media?: boolean;
      blockStreaming?: boolean;
      [key: string]: any;
    };
    outbound?: {
      textChunkLimit?: number;
      [key: string]: any;
    };
    config?: {
      resolveAllowFrom?: (params: { cfg: OpenClawConfig; accountId?: string | null }) => string[];
      formatAllowFrom?: (params: { allowFrom: unknown[] }) => string[];
      [key: string]: any;
    };
    [key: string]: any;
  };

  export type ChannelPlugin<T = unknown> = {
    id: string;
    meta?: any;
    capabilities?: any;
    reload?: any;
    configSchema?: any;
    config?: Record<string, (...args: any[]) => any> & {
      resolveAccount?: (cfg: OpenClawConfig, accountId?: string | null) => T;
    };
    security?: Record<string, (...args: any[]) => any>;
    groups?: Record<string, (...args: any[]) => any>;
    threading?: Record<string, (...args: any[]) => any>;
    messaging?: Record<string, any>;
    mentions?: Record<string, (...args: any[]) => any>;
    directory?: Record<string, (...args: any[]) => any>;
    resolver?: Record<string, (...args: any[]) => any>;
    actions?: any;
    setup?: Record<string, (...args: any[]) => any>;
    outbound?: Record<string, any>;
    status?: Record<string, any>;
    gateway?: Record<string, (...args: any[]) => any>;
    pairing?: Record<string, any>;
    auditAccount?: (...args: any[]) => any;
    streaming?: any;
  };

  export type OpenClawConfig = {
    channels?: any;
    [key: string]: any;
  };

  export type RuntimeEnv = {
    error: (message: string) => void;
    [key: string]: any;
  };

  export type PluginRuntime = {
    channel: any;
    [key: string]: any;
  };

  export type OpenClawPluginApi = {
    runtime: PluginRuntime;
    registerChannel: (params: { plugin: ChannelPlugin<any>; dock?: ChannelDock }) => void;
    registerCommand: (params: {
      name: string;
      description: string;
      acceptsArgs?: boolean;
      handler: (ctx: { args?: string | null }) => Promise<{ text: string }> | { text: string };
    }) => void;
    registerCli: (register: (ctx: { program: unknown }) => void) => void;
  };

  export const DEFAULT_ACCOUNT_ID: string;

  export const ToolPolicySchema: any;

  export function emptyPluginConfigSchema(): any;

  export function buildChannelConfigSchema(schema: unknown): unknown;

  export function normalizeAccountId(accountId?: string | null): string;

  export function applyAccountNameToChannelSection(params: {
    cfg: OpenClawConfig;
    channelKey: string;
    accountId: string;
    name?: string;
  }): OpenClawConfig;

  export function setAccountEnabledInConfigSection(params: {
    cfg: OpenClawConfig;
    sectionKey: string;
    accountId: string;
    enabled: boolean;
    allowTopLevel?: boolean;
  }): OpenClawConfig;

  export function deleteAccountFromConfigSection(params: {
    cfg: OpenClawConfig;
    sectionKey: string;
    accountId: string;
    clearBaseFields?: string[];
  }): OpenClawConfig;

  export function formatPairingApproveHint(channelId: string): string;

  export function createReplyPrefixOptions(params: {
    cfg: OpenClawConfig;
    agentId?: string;
    channel: string;
    accountId?: string;
  }): any;
}

declare module "node:crypto" {
  export function randomUUID(): string;
}

declare module "node:fs" {
  export function mkdirSync(path: string, options?: unknown): void;
  export function readFileSync(path: string, encoding: string): string;
  export function renameSync(oldPath: string, newPath: string): void;
  export function writeFileSync(path: string, data: unknown, encoding?: string): void;
  export function mkdtempSync(prefix: string): string;
  export function unlinkSync(path: string): void;
}

declare module "node:os" {
  export function homedir(): string;
  export function tmpdir(): string;
}

declare module "node:path" {
  export function dirname(path: string): string;
  export function join(...parts: string[]): string;
}

declare module "zod" {
  export const z: any;
}

declare const process: {
  env: Record<string, string | undefined>;
};

declare const Buffer: {
  from(data: ArrayBuffer): Uint8Array;
};
