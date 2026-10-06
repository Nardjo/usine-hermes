---
name: usine-hermes
description: Add a Hermes Discord bot (profile) on a VPS running usine-hermes, with the human typing every secret. Use when the user says "add an agent", "new bot", "create a Hermes profile", "usine-hermes create", or wants another Discord bot on their usine-hermes VPS.
---

# usine-hermes: add a profile

You drive `usine-hermes` on the VPS; the human types every secret. See the repo `README.md` for details.

## Hard rule: secrets

Never ask for, read, print, grep, cat or relay a secret (Discord token, API keys, `.env`, `auth.json`, `/opt/usine-hermes/honcho/.env`). Never run `secret`, `create` without `</dev/null`, or a subscription login yourself: those are prompts for the human. If the human pastes a secret in chat, tell them to reset it (Discord **Reset Token**, or rotate the key) and set the new one with `secret`.

## Steps

1. Check the setup: `sudo usine-hermes list` works (else the human runs `sudo ./install.sh` first). `sudo usine-hermes config default_provider` gives the default.
2. Ask the human for: **name** (`^[a-z][a-z0-9-]{1,30}$`, not an existing Linux user), **personality**, **mission**, **provider** (one of: `openrouter anthropic claude-subscription-directsdk-experimental openai-api openai-codex xai xai-oauth gemini deepseek`; README "Providers" lists auth and limits).
3. Create it without prompts (all three flags, stdin not a terminal):
   ```sh
   sudo usine-hermes create <name> --personality "<text>" --mission "<text>" --provider <provider> </dev/null
   ```
   Keep the "Next steps" it prints: they are the exact `secret` commands, and for a subscription provider the login command.
4. Discord: walk the human through README "Discord setup" steps 1 to 5 (new application, bot token, **Message Content** + **Server Members** intents, invite URL with their Application ID, their user id in `discord_allowed_users`). You may build the invite URL from the Application ID they give you (it is not secret).
5. Hand the human the commands from step 3 to run in their own terminal, for example:
   ```sh
   sudo usine-hermes secret <name> DISCORD_BOT_TOKEN
   sudo usine-hermes secret <name> <PROVIDER_KEY_VAR>
   ```
   Subscription providers: give them the printed login command instead of a key. Wait until they say done.
6. Start and check:
   ```sh
   sudo usine-hermes start <name>
   sudo usine-hermes doctor <name>
   ```
   On a `token` FAIL or "DISCORD_BOT_TOKEN is empty", go back to step 5. Read failures with `sudo usine-hermes logs <name>` (redacted).
7. Ask the human to mention the bot in a channel and confirm it answers. No answer: check intents, the invite, and that their user id is in `discord_allowed_users`.
