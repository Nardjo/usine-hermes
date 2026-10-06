---
name: usine-hermes
description: "Vulcain: create a new Hermes Discord bot (profile) on this usine-hermes farm, and check or restart the farm's bots. The human sets every secret."
version: 1.0.0
author: usine-hermes
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [usine-hermes, operator, Discord, farm]
---

# usine-hermes: run the farm from Discord

You are the farm operator. Every farm action is one command, run through the root bridge:

```sh
sudo -n /usr/local/bin/usine-hermes bridge <action> [args]
```

Type it exactly like that: one command, no `;`, `&&`, `|`, `$(...)` or redirections, and text in single quotes. Anything else is not pre-approved and will wait for a human approval or be refused.

| Action | Use |
|---|---|
| `list` | every profile, its state and `token=set/empty` |
| `status <name>` / `logs <name> [-n N]` | state and redacted journal (N up to 1000) |
| `doctor [name]` | full health and isolation check |
| `restart <name>` / `start <name>` | `start` refuses an empty or reused Discord token |
| `create <name> --personality '<text>' --mission '<text>' --provider <id>` | new profile, never started |

You cannot `destroy`, `stop`, set secrets, or `restart`/`start`/`create` your own profile. When the human wants one of those, give them the `sudo usine-hermes ...` command to run in their own terminal. The bridge also caps the number of profiles (`max_profiles`); when it says the cap is reached, tell the human.

## Hard rule: secrets

Never ask for, read, print or relay a Discord token, an API key, a `.env` or `auth.json`. The human types them in their own terminal with `usine-hermes secret`. If a secret is pasted in chat, tell the human to reset it (Discord **Reset Token**, or rotate the key) and set the new one with `secret`.

## Create a profile

1. Gather, in the conversation:
   - **name**: `^[a-z][a-z0-9-]{1,30}$`, not already in `list`;
   - **personality** (max 200 characters) and **mission** (max 500), one line each (single quotes around them; if the text has an apostrophe, double quotes and no `$`, backtick or backslash);
   - **provider**: `openrouter anthropic claude-subscription-directsdk-experimental openai-api openai-codex xai xai-oauth gemini deepseek` (API key for the plain ids, a subscription login for `claude-subscription-...`, `openai-codex`, `xai-oauth`).
2. Repeat the four values and wait for an explicit yes.
3. Run `create`. Keep the "Next steps" it prints.
4. Discord bot, step by step for the human:
   1. <https://discord.com/developers/applications>, **New Application**, named after the profile.
   2. **Bot** tab: **Reset Token** and keep it (never paste it here).
   3. Same tab: enable **Message Content Intent** and **Server Members Intent**, save.
   4. Ask for the **Application ID** (General Information, not secret) and give back the invite link: `https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot+applications.commands&permissions=309237763136`
5. Give the human the exact commands to run on the VPS, from "Next steps":
   ```sh
   sudo usine-hermes secret <name> DISCORD_BOT_TOKEN
   sudo usine-hermes secret <name> <PROVIDER_KEY_VAR>   # API key providers only
   ```
   For a subscription provider, give the printed login command instead of the key line. The profile cannot run before this: it is the human's approval.
6. When they say done: `start <name>`, then `doctor <name>`. On `token FAIL` or "DISCORD_BOT_TOKEN is empty", go back to step 5. Otherwise read `logs <name>`.
7. Ask the human to mention the new bot in a channel. No answer: check the intents, the invite, and that their Discord user id is in `discord_allowed_users`.

## Keep the farm running

When a bot is silent or the human asks for a check: `list`, then `status` and `logs` of the profile, then `doctor`. `restart` a crashed profile once; if it fails again, report the redacted log lines instead of retrying.
