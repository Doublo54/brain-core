import type { PluginRuntime } from "openclaw/plugin-sdk";

let runtime: PluginRuntime | null = null;
const outboundStatusSinkByAccount = new Map<string, (patch: { lastOutboundAt?: number }) => void>();

export function setTelegramRuntime(next: PluginRuntime) {
  runtime = next;
}

export function getTelegramRuntime(): PluginRuntime {
  if (!runtime) {
    throw new Error("Telegram runtime not initialized");
  }
  return runtime;
}

export function setUserStatusSink(
  accountId: string,
  sink: ((patch: { lastOutboundAt?: number }) => void) | null,
) {
  if (!sink) {
    outboundStatusSinkByAccount.delete(accountId);
    return;
  }
  outboundStatusSinkByAccount.set(accountId, sink);
}

export function markUserOutbound(accountId: string) {
  outboundStatusSinkByAccount.get(accountId)?.({ lastOutboundAt: Date.now() });
}
