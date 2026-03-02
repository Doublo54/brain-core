import type { PluginRuntime } from "openclaw/plugin-sdk";

let runtime: PluginRuntime | null = null;

export function setDiscordUserRuntime(next: PluginRuntime) {
  runtime = next;
}

export function getDiscordUserRuntime(): PluginRuntime {
  if (!runtime) {
    throw new Error("Discord user runtime not initialized");
  }
  return runtime;
}
