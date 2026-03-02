/**
 * discord-roles v1.0.1 — Discord role management tools
 * 
 * Provides agent tools for creating, editing, and assigning Discord roles.
 * Uses Discord REST API directly since OpenClaw's message tool doesn't expose role management.
 */

const DISCORD_API = 'https://discord.com/api/v10';

const DISCORD_ID_REGEX = /^\d{17,20}$/;

function validateDiscordId(id: string, fieldName: string): void {
  if (!DISCORD_ID_REGEX.test(id)) {
    throw new Error(`Invalid Discord ID for ${fieldName}: must be 17-20 digits`);
  }
}

interface DiscordConfig {
  token: string;
  accountId?: string;
}

function getDiscordToken(api: any): string | null {
  // Try to find Discord token from config
  // Preferred structure: channels.discord.accounts.{accountId}.token
  const discord = api.config?.channels?.discord;
  if (!discord) return null;

  const accounts = discord.accounts;

  // Current config shape: object map by account id (e.g. default, agent-name)
  if (accounts && typeof accounts === 'object' && !Array.isArray(accounts)) {
    for (const account of Object.values(accounts) as any[]) {
      if (account?.token) return account.token;
    }
  }

  // Backward compatibility: array of accounts
  if (Array.isArray(accounts) && accounts.length > 0) {
    for (const account of accounts) {
      if (account?.token) return account.token;
    }
  }

  // Legacy: direct token on channel config
  if (discord.token) return discord.token;

  return null;
}

async function discordRequest(
  token: string,
  method: string,
  endpoint: string,
  body?: any,
  attempt = 0
): Promise<any> {
  const url = `${DISCORD_API}${endpoint}`;
  const headers: Record<string, string> = {
    'Authorization': `Bot ${token}`,
    'Content-Type': 'application/json',
    'User-Agent': 'OpenClaw-discord-roles/1.0.1',
  };

  const options: RequestInit = {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  };

  const response = await fetch(url, options);

  // Handle Discord rate limits with bounded retries
  if (response.status === 429 && attempt < 3) {
    let waitMs = 1000;
    try {
      const data = await response.json();
      if (typeof data?.retry_after === 'number') {
        waitMs = data.retry_after > 10 ? data.retry_after : Math.ceil(data.retry_after * 1000);
      }
    } catch {
      const retryAfterHeader = response.headers.get('retry-after');
      if (retryAfterHeader) {
        const parsed = Number(retryAfterHeader);
        if (!Number.isNaN(parsed)) {
          waitMs = parsed > 10 ? parsed : Math.ceil(parsed * 1000);
        }
      }
    }

    await new Promise((resolve) => setTimeout(resolve, Math.max(waitMs, 250)));
    return discordRequest(token, method, endpoint, body, attempt + 1);
  }

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`Discord API error (${response.status}): ${text}`);
  }

  // 204 No Content
  if (response.status === 204) return null;

  return response.json();
}

export default function (api: any) {
  console.log('[discord-roles] v1.0.1 loading...');
  
  const token = getDiscordToken(api);
  if (!token) {
    console.warn('[discord-roles] No Discord token found in config — tools will fail at runtime');
  } else {
    console.log('[discord-roles] Discord token found, tools ready');
  }

  // ─── Tool: discord_role_create ─────────────────────────────────────────────
  api.registerTool({
    name: 'discord_role_create',
    description: 'Create a new role in a Discord server (guild)',
    parameters: {
      type: 'object',
      properties: {
        guildId: { type: 'string', description: 'Discord server/guild ID' },
        name: { type: 'string', description: 'Role name' },
        color: { type: 'number', description: 'Role color as decimal integer (optional)' },
        hoist: { type: 'boolean', description: 'Display role members separately in sidebar (optional)' },
        mentionable: { type: 'boolean', description: 'Allow anyone to @mention this role (optional)' },
        permissions: { type: 'string', description: 'Permission bitfield as string (optional, default: 0)' },
      },
      required: ['guildId', 'name'],
    },
    async execute(_id: string, params: any) {
      const currentToken = getDiscordToken(api);
      if (!currentToken) {
        return { content: [{ type: 'text', text: 'Error: No Discord token configured' }] };
      }
      
      try {
        validateDiscordId(params.guildId, 'guildId');

        const body: any = { name: params.name };
        if (params.color !== undefined) body.color = params.color;
        if (params.hoist !== undefined) body.hoist = params.hoist;
        if (params.mentionable !== undefined) body.mentionable = params.mentionable;
        if (params.permissions !== undefined) body.permissions = params.permissions;
        
        const role = await discordRequest(
          currentToken,
          'POST',
          `/guilds/${params.guildId}/roles`,
          body
        );
        
        return {
          content: [{
            type: 'text',
            text: JSON.stringify({ ok: true, role }, null, 2)
          }]
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }] };
      }
    },
  });

  // ─── Tool: discord_role_edit ───────────────────────────────────────────────
  api.registerTool({
    name: 'discord_role_edit',
    description: 'Edit an existing Discord role',
    parameters: {
      type: 'object',
      properties: {
        guildId: { type: 'string', description: 'Discord server/guild ID' },
        roleId: { type: 'string', description: 'Role ID to edit' },
        name: { type: 'string', description: 'New role name (optional)' },
        color: { type: 'number', description: 'New role color as decimal integer (optional)' },
        hoist: { type: 'boolean', description: 'Display role members separately (optional)' },
        mentionable: { type: 'boolean', description: 'Allow @mentions (optional)' },
        permissions: { type: 'string', description: 'New permission bitfield as string (optional)' },
      },
      required: ['guildId', 'roleId'],
    },
    async execute(_id: string, params: any) {
      const currentToken = getDiscordToken(api);
      if (!currentToken) {
        return { content: [{ type: 'text', text: 'Error: No Discord token configured' }] };
      }
      
      try {
        validateDiscordId(params.guildId, 'guildId');
        validateDiscordId(params.roleId, 'roleId');

        const body: any = {};
        if (params.name !== undefined) body.name = params.name;
        if (params.color !== undefined) body.color = params.color;
        if (params.hoist !== undefined) body.hoist = params.hoist;
        if (params.mentionable !== undefined) body.mentionable = params.mentionable;
        if (params.permissions !== undefined) body.permissions = params.permissions;
        
        const role = await discordRequest(
          currentToken,
          'PATCH',
          `/guilds/${params.guildId}/roles/${params.roleId}`,
          body
        );
        
        return {
          content: [{
            type: 'text',
            text: JSON.stringify({ ok: true, role }, null, 2)
          }]
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }] };
      }
    },
  });

  // ─── Tool: discord_role_delete ─────────────────────────────────────────────
  api.registerTool({
    name: 'discord_role_delete',
    description: 'Delete a Discord role',
    parameters: {
      type: 'object',
      properties: {
        guildId: { type: 'string', description: 'Discord server/guild ID' },
        roleId: { type: 'string', description: 'Role ID to delete' },
      },
      required: ['guildId', 'roleId'],
    },
    async execute(_id: string, params: any) {
      const currentToken = getDiscordToken(api);
      if (!currentToken) {
        return { content: [{ type: 'text', text: 'Error: No Discord token configured' }] };
      }
      
      try {
        validateDiscordId(params.guildId, 'guildId');
        validateDiscordId(params.roleId, 'roleId');

        await discordRequest(
          currentToken,
          'DELETE',
          `/guilds/${params.guildId}/roles/${params.roleId}`
        );
        
        return {
          content: [{
            type: 'text',
            text: JSON.stringify({ ok: true, deleted: params.roleId })
          }]
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }] };
      }
    },
  });

  // ─── Tool: discord_role_assign ─────────────────────────────────────────────
  api.registerTool({
    name: 'discord_role_assign',
    description: 'Assign a role to a user in a Discord server',
    parameters: {
      type: 'object',
      properties: {
        guildId: { type: 'string', description: 'Discord server/guild ID' },
        userId: { type: 'string', description: 'User ID to assign role to' },
        roleId: { type: 'string', description: 'Role ID to assign' },
      },
      required: ['guildId', 'userId', 'roleId'],
    },
    async execute(_id: string, params: any) {
      const currentToken = getDiscordToken(api);
      if (!currentToken) {
        return { content: [{ type: 'text', text: 'Error: No Discord token configured' }] };
      }
      
      try {
        validateDiscordId(params.guildId, 'guildId');
        validateDiscordId(params.userId, 'userId');
        validateDiscordId(params.roleId, 'roleId');

        await discordRequest(
          currentToken,
          'PUT',
          `/guilds/${params.guildId}/members/${params.userId}/roles/${params.roleId}`
        );
        
        return {
          content: [{
            type: 'text',
            text: JSON.stringify({ ok: true, assigned: { userId: params.userId, roleId: params.roleId } })
          }]
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }] };
      }
    },
  });

  // ─── Tool: discord_role_unassign ───────────────────────────────────────────
  api.registerTool({
    name: 'discord_role_unassign',
    description: 'Remove a role from a user in a Discord server',
    parameters: {
      type: 'object',
      properties: {
        guildId: { type: 'string', description: 'Discord server/guild ID' },
        userId: { type: 'string', description: 'User ID to remove role from' },
        roleId: { type: 'string', description: 'Role ID to remove' },
      },
      required: ['guildId', 'userId', 'roleId'],
    },
    async execute(_id: string, params: any) {
      const currentToken = getDiscordToken(api);
      if (!currentToken) {
        return { content: [{ type: 'text', text: 'Error: No Discord token configured' }] };
      }
      
      try {
        validateDiscordId(params.guildId, 'guildId');
        validateDiscordId(params.userId, 'userId');
        validateDiscordId(params.roleId, 'roleId');

        await discordRequest(
          currentToken,
          'DELETE',
          `/guilds/${params.guildId}/members/${params.userId}/roles/${params.roleId}`
        );
        
        return {
          content: [{
            type: 'text',
            text: JSON.stringify({ ok: true, unassigned: { userId: params.userId, roleId: params.roleId } })
          }]
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }] };
      }
    },
  });

  // ─── Tool: discord_channel_permissions ─────────────────────────────────────
  api.registerTool({
    name: 'discord_channel_permissions',
    description: 'Set permission overwrites for a role or user on a Discord channel',
    parameters: {
      type: 'object',
      properties: {
        channelId: { type: 'string', description: 'Channel ID to set permissions on' },
        targetId: { type: 'string', description: 'Role ID or User ID to set permissions for' },
        targetType: { type: 'number', description: '0 = role, 1 = user' },
        allow: { type: 'string', description: 'Permission bitfield to allow (as string)' },
        deny: { type: 'string', description: 'Permission bitfield to deny (as string)' },
      },
      required: ['channelId', 'targetId', 'targetType'],
    },
    async execute(_id: string, params: any) {
      const currentToken = getDiscordToken(api);
      if (!currentToken) {
        return { content: [{ type: 'text', text: 'Error: No Discord token configured' }] };
      }
      
      try {
        validateDiscordId(params.channelId, 'channelId');
        validateDiscordId(params.targetId, 'targetId');

        const body: any = {
          type: params.targetType,
        };
        if (params.allow !== undefined) body.allow = params.allow;
        if (params.deny !== undefined) body.deny = params.deny;
        
        await discordRequest(
          currentToken,
          'PUT',
          `/channels/${params.channelId}/permissions/${params.targetId}`,
          body
        );
        
        return {
          content: [{
            type: 'text',
            text: JSON.stringify({ ok: true, channelId: params.channelId, targetId: params.targetId })
          }]
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }] };
      }
    },
  });

  // ─── Tool: discord_role_list ───────────────────────────────────────────────
  api.registerTool({
    name: 'discord_role_list',
    description: 'List all roles in a Discord server',
    parameters: {
      type: 'object',
      properties: {
        guildId: { type: 'string', description: 'Discord server/guild ID' },
      },
      required: ['guildId'],
    },
    async execute(_id: string, params: any) {
      const currentToken = getDiscordToken(api);
      if (!currentToken) {
        return { content: [{ type: 'text', text: 'Error: No Discord token configured' }] };
      }
      
      try {
        validateDiscordId(params.guildId, 'guildId');

        const roles = await discordRequest(
          currentToken,
          'GET',
          `/guilds/${params.guildId}/roles`
        );
        
        return {
          content: [{
            type: 'text',
            text: JSON.stringify({ ok: true, roles }, null, 2)
          }]
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }] };
      }
    },
  });

  console.log('[discord-roles] v1.0.1 loaded — 7 tools registered');
}
