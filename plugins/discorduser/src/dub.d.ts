declare module "discord-user-bots" {
  export type DiscordReadyPayload = {
    id?: string;
    username?: string;
    user?: {
      id?: string;
      username?: string;
      [key: string]: unknown;
    };
    [key: string]: unknown;
  };

  export type DiscordAuthor = {
    id: string;
    username: string;
    discriminator?: string;
    global_name?: string;
    avatar?: string;
    [key: string]: unknown;
  };

  export type DiscordAttachment = {
    id?: string;
    filename?: string;
    url?: string;
    proxy_url?: string;
    content_type?: string | null;
    size?: number;
    [key: string]: unknown;
  };

  export type DiscordMention = {
    id: string;
    username: string;
    discriminator?: string;
    global_name?: string;
    avatar?: string;
    [key: string]: unknown;
  };

  export interface DiscordMessage {
    id: string;
    channel_id: string;
    guild_id?: string;
    author: DiscordAuthor;
    content: string;
    attachments: DiscordAttachment[];
    mentions: DiscordMention[];
    referenced_message?: DiscordMessage | null;
    type: number;
    timestamp: string;
    [key: string]: unknown;
  }

  export interface SendOptions {
    content?: string;
    reply?: string | { message_id?: string; [key: string]: unknown };
    tts?: boolean;
    embeds?: unknown[];
    attachments?: Array<string | { path: string; name?: string; [key: string]: unknown }>;
    components?: unknown[];
    stickers?: string[];
    allowed_mentions?: {
      parse?: string[];
      users?: string[];
      roles?: string[];
      replied_user?: boolean;
      [key: string]: unknown;
    };
    [key: string]: unknown;
  }

  export interface ClientConfig {
    autoReconnect?: boolean;
    proxy?: string;
    intents?: number | number[];
    [key: string]: unknown;
  }

  export interface DmChannel {
    id: string;
    type: number;
    [key: string]: unknown;
  }

  export interface FetchRequestOptions {
    method?: string;
    body?: unknown;
    headers?: Record<string, string>;
    [key: string]: unknown;
  }

  export interface DiscordAPIErrorData {
    status?: number;
    body?:
      | {
          retry_after?: number | string;
          [key: string]: unknown;
        }
      | string;
    internalError?: boolean;
    [key: string]: unknown;
  }

  export interface DiscordAPIError extends Error {
    name: "DiscordAPIError" | string;
    status?: number;
    body?: DiscordAPIErrorData["body"];
    response?: {
      status?: number;
      body?: DiscordAPIErrorData["body"];
      [key: string]: unknown;
    };
    raw?: string;
  }

  export class Client {
    constructor(config?: ClientConfig);
    login(token: string): Promise<void>;
    close(): void;
    terminate(): void;
    on(event: "message", listener: (payload: DiscordMessage) => void): this;
    on(event: "ready", listener: (payload?: DiscordReadyPayload) => void): this;
    on(event: "discord_disconnect", listener: (payload: unknown) => void): this;
    on(event: "discord_reconnect", listener: (payload: unknown) => void): this;
    on(event: "message_reaction_add", listener: (payload: unknown) => void): this;
    on(event: "message_reaction_remove", listener: (payload: unknown) => void): this;
    on(event: "thread_create", listener: (payload: unknown) => void): this;
    on(event: "typing_start", listener: (payload: unknown) => void): this;
    send(channelId: string, options: SendOptions): Promise<DiscordMessage>;
    group(userIds: string[]): Promise<DmChannel>;
    add_reaction(messageId: string, channelId: string, emoji: string): Promise<unknown>;
    remove_reaction(messageId: string, channelId: string, emoji: string): Promise<unknown>;
    create_thread(channelId: string, options: Record<string, unknown>): Promise<unknown>;
    create_thread_from_message(
      channelId: string,
      messageId: string,
      options: Record<string, unknown>,
    ): Promise<unknown>;
    edit(channelId: string, messageId: string, options: SendOptions): Promise<DiscordMessage>;
    delete_message(channelId: string, messageId: string): Promise<unknown>;
    fetch_messages(limit: number, channelId: string): Promise<DiscordMessage[]>;
    fetch_request(path: string, options?: FetchRequestOptions): Promise<unknown>;
    info: DiscordReadyPayload | null;
    isReady: boolean;
  }

  const Discord: {
    Client: typeof Client;
  };

  export default Discord;
}
