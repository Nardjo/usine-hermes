---
name: usine-secret
description: "Vulcain: take one secret (Discord bot token, API key, OpenRouter key) from the human without seeing it. View this skill right before a take-secret or memory bridge action."
version: 1.0.0
author: usine-hermes
license: MIT
platforms: [linux]
required_environment_variables:
  - name: USINE_PENDING_SECRET
    prompt: "Paste the secret Vulcain just asked for (hidden)"
    help: "Discord token: Developer Portal > Bot > Reset Token. API key: your provider's dashboard."
metadata:
  hermes:
    tags: [usine-hermes, secrets]
---

# usine-secret: hand over a secret without seeing it

Viewing this skill makes the terminal ask the human for `USINE_PENDING_SECRET`, hidden, and store it in your `.env`. You only see "Secret stored". This works in the terminal chat only (not on Discord).

1. Tell the human, before viewing the skill: which secret, where to find it, and that the next prompt is hidden.
2. View this skill. Never ask for the value in the chat, never read or print your `.env`.
3. Right away, run one bridge action that consumes it:
   - a token or key for a profile: `sudo -n /usr/local/bin/usine-hermes bridge take-secret <name> <KEY>` (`DISCORD_BOT_TOKEN`, or the profile's own provider key such as `OPENROUTER_API_KEY`);
   - the OpenRouter key for memory: `sudo -n /usr/local/bin/usine-hermes bridge memory`.
   The bridge moves the value out of your `.env`, so the next view asks again.
4. If the bridge says "no pending secret", or the prompt did not appear: tell the human to run `sudo usine-hermes secret <name> [KEY]` in another terminal on the VPS (it asks the value hidden itself). Not as `!` in this chat: that would run as you, and you may not use sudo for it.
