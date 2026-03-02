import { Api, TelegramClient } from "telegram";
import { NewMessage } from "telegram/events/index.js";
import type { NewMessageEvent } from "telegram/events/NewMessage.js";
import { StringSession } from "telegram/sessions/index.js";

export type UserTransportConfig = {
  apiId: number;
  apiHash: string;
  stringSession: string;
};

export type UserInboundEvent = {
  chatId: string;
  senderId: string;
  text: string;
  messageId?: string;
  timestampMs: number;
  isGroup: boolean;
  mentioned: boolean;
  senderLabel?: string;
};

export type SendFileOptions = {
  file: string | Buffer;
  caption?: string;
  forceDocument?: boolean;
};

export type DialogEntry = {
  id: string;
  name: string;
  isGroup: boolean;
};

export type UserAdapter = {
  connect: () => Promise<void>;
  disconnect: () => Promise<void>;
  sendText: (chatId: string, text: string) => Promise<{ messageId: string }>;
  sendFile: (chatId: string, opts: SendFileOptions) => Promise<{ messageId: string }>;
  setTyping: (chatId: string) => Promise<void>;
  onInbound: (handler: (event: UserInboundEvent) => Promise<void>) => void;
  removeInbound: () => void;
  self: () => Promise<{ id: string; username?: string }>;
  getDialogs: () => Promise<DialogEntry[]>;
  isParticipant: (groupId: string) => Promise<boolean>;
};

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  return value as Record<string, unknown>;
}

function valueToString(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }
  if (typeof value === "number" || typeof value === "bigint") {
    return String(value);
  }
  const record = asRecord(value);
  if (record && (typeof record.value === "string" || typeof record.value === "number" || typeof record.value === "bigint")) {
    return String(record.value);
  }
  if (value != null && typeof (value as { toString?: unknown }).toString === "function") {
    const str = String(value);
    if (str && str !== "[object Object]") return str;
  }
  return "";
}

export function createTelegramUserAdapter(cfg: UserTransportConfig): UserAdapter {
  const client = new TelegramClient(new StringSession(cfg.stringSession), cfg.apiId, cfg.apiHash, {
    connectionRetries: 5,
    useWSS: true,
  });
  const inboundEvent = new NewMessage({});

  let inboundHandler: ((event: NewMessageEvent) => Promise<void>) | null = null;

  return {
    connect: async () => {
      await client.connect();
      // Ensure the client is started to receive updates
      // start() handles authorization check and starts the update loop
      try {
        await client.start({
          phoneNumber: async () => "",
          phoneCode: async () => "",
          onError: (err) => console.error(`[telegramuser:adapter] start error: ${String(err)}`),
        });
        console.log(`[telegramuser:adapter] client started, updates enabled`);
      } catch (startErr) {
        // If already authorized, start() may throw - that's okay
        console.log(`[telegramuser:adapter] start result: ${String(startErr)}`);
      }
    },
    disconnect: async () => {
      if (inboundHandler) {
        client.removeEventHandler(inboundHandler, inboundEvent);
        inboundHandler = null;
      }
      await client.disconnect();
    },
    sendText: async (chatId: string, text: string) => {
      const result = await client.sendMessage(chatId, { message: text });
      const record = asRecord(result);
      return { messageId: valueToString(record?.id) };
    },
    sendFile: async (chatId: string, opts: SendFileOptions) => {
      const result = await client.sendFile(chatId, {
        file: opts.file,
        caption: opts.caption,
        forceDocument: opts.forceDocument ?? false,
      });
      const record = asRecord(result);
      return { messageId: valueToString(record?.id) };
    },
    setTyping: async (chatId: string) => {
      try {
        const entity = await client.getInputEntity(chatId);
        await client.invoke(
          new Api.messages.SetTyping({
            peer: entity,
            action: new Api.SendMessageTypingAction(),
          }),
        );
      } catch {
        // Best-effort — typing indicators are non-critical
      }
    },
    onInbound: (handler) => {
      if (inboundHandler) {
        client.removeEventHandler(inboundHandler, inboundEvent);
      }

      inboundHandler = async (event: NewMessageEvent) => {
        const eventRecord = asRecord(event);
        const msg = asRecord(eventRecord?.message);
        try {
          const peerRecord = asRecord(msg?.peerId);
          const rawPeer = peerRecord?.channelId ?? peerRecord?.chatId ?? peerRecord?.userId ?? null;
          console.log(`[telegramuser:adapter] raw-update out=${String(Boolean(msg?.out))} hasMsg=${String(Boolean(msg))} peer=${String(rawPeer)} textLen=${String(String(msg?.message ?? "").length)}`);
        } catch (e) {
          console.error(`[telegramuser:adapter] raw-update log error: ${String(e)}`);
        }
        if (!msg) {
          console.log(`[telegramuser:adapter] filtered: no msg`);
          return;
        }
        if (Boolean(msg.out)) {
          console.log(`[telegramuser:adapter] filtered: outgoing message`);
          return;
        }

        const peerRecord = asRecord(msg.peerId);
        const channelId = peerRecord?.channelId;
        const chatIdValue = peerRecord?.chatId;
        const userId = peerRecord?.userId;
        const peerValue = channelId ?? chatIdValue ?? userId;
        const chatId = valueToString(peerValue);
        console.log(`[telegramuser:adapter] peer extracted: chatId=${chatId}`);
        if (!chatId) {
          console.log(`[telegramuser:adapter] filtered: no chatId`);
          return;
        }

        const senderRaw = msg.senderId;
        const senderRecord = asRecord(senderRaw);
        const senderValue = senderRecord?.value ?? senderRaw ?? peerValue;
        const senderId = valueToString(senderValue);
        console.log(`[telegramuser:adapter] sender extracted: senderId=${senderId}`);
        if (!senderId) {
          console.log(`[telegramuser:adapter] filtered: no senderId`);
          return;
        }

        const text = String(msg.message ?? "").trim();
        if (!text) {
          console.log(`[telegramuser:adapter] filtered: empty text`);
          return;
        }

        console.log(`[telegramuser:adapter] processing message from ${senderId}: ${text}`);

        let senderLabel: string | undefined;
        const getSender = msg.getSender;
        if (typeof getSender === "function") {
          try {
            const sender = await Promise.resolve(getSender.call(msg));
            const senderData = asRecord(sender);
            const first = String(senderData?.firstName ?? "").trim();
            const last = String(senderData?.lastName ?? "").trim();
            const username = String(senderData?.username ?? "").trim();
            const full = [first, last].filter(Boolean).join(" ");
            senderLabel = full || (username ? `@${username}` : undefined);
          } catch {
            senderLabel = undefined;
          }
        }

        await handler({
          chatId,
          senderId,
          text,
          messageId: valueToString(msg.id) || undefined,
          timestampMs:
            typeof msg.date === "number" && Number.isFinite(msg.date)
              ? msg.date * 1000
              : Date.now(),
          isGroup: Boolean(msg.isGroup || msg.isChannel),
          mentioned: Boolean(msg.mentioned),
          senderLabel,
        });
      };

      client.addEventHandler(inboundHandler, inboundEvent);
    },
    removeInbound: () => {
      if (!inboundHandler) {
        return;
      }
      client.removeEventHandler(inboundHandler, inboundEvent);
      inboundHandler = null;
    },
    self: async () => {
      const me = asRecord(await client.getMe());
      return {
        id: valueToString(me?.id),
        username: typeof me?.username === "string" ? me.username : undefined,
      };
    },
    getDialogs: async () => {
      const dialogs = await client.getDialogs({});
      const entries: DialogEntry[] = [];
      for (const dialog of dialogs) {
        const d = asRecord(dialog);
        if (!d) continue;
        const entity = asRecord(d.entity);
        if (!entity) continue;
        const id = valueToString(entity.id);
        if (!id) continue;
        const title = String(entity.title ?? "").trim();
        const firstName = String(entity.firstName ?? "").trim();
        const lastName = String(entity.lastName ?? "").trim();
        const username = String(entity.username ?? "").trim();
        const name =
          title ||
          [firstName, lastName].filter(Boolean).join(" ") ||
          (username ? `@${username}` : id);
        const isGroup = Boolean(entity.megagroup || entity.gigagroup || d.isGroup);
        entries.push({ id, name, isGroup });
      }
      return entries;
    },
    isParticipant: async (groupId: string) => {
      try {
        const entity = await client.getEntity(groupId);
        if (!entity) return false;
        const me = await client.getMe();
        if (!me) return false;
        const meId = valueToString(asRecord(me)?.id);
        if (!meId) return false;

        try {
          await client.invoke(
            new Api.channels.GetParticipant({
              channel: entity,
              participant: me,
            }),
          );
          return true;
        } catch (channelErr) {
          const errMsg = String((channelErr as { errorMessage?: string })?.errorMessage ?? channelErr);
          if (errMsg.includes("USER_NOT_PARTICIPANT")) return false;
          if (errMsg.includes("CHAT_ADMIN_REQUIRED")) return false;

          const participants = await client.getParticipants(entity, { limit: 200 });
          if (!participants) return false;
          return participants.some((p) => valueToString(asRecord(p)?.id) === meId);
        }
      } catch {
        return false;
      }
    },
  };
}
