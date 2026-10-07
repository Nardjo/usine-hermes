# Manual validation on a throwaway VPS

`tests/test.sh` cannot exercise systemd, Docker, Discord or provider logins. Run this procedure before calling a release good. Use a fresh Ubuntu 24.04 VPS (2 GB+ RAM), then repeat on Debian 12 and Debian 13 if possible. Destroy the VPS afterwards.

You need: a ChatGPT (Codex) subscription or an API key for Vulcain, an OpenRouter key (memory + profiles), three Discord applications with bots (see the README Discord guide), a test Discord server, your Discord user id, and a second Discord account that is not allowlisted.

## Procedure

1. **Install** (over `ssh -t`, so the chat gets a terminal)
   ```sh
   curl -fsSL https://raw.githubusercontent.com/Nardjo/usine-hermes/main/install.sh | sudo bash
   ```
   Expect one question (language), `bootstrap done` without Docker, `✓ Vulcain créé…`, then the model menu. Press Enter (ChatGPT): a device code and URL, log in from your laptop; then the Hermes chat opens as `vulcain`. No Discord id, OpenRouter key or `[O/n]` question. `config honcho` is `false`; `docker` is not installed.
2. **Chat with Vulcain**: say hello. It greets in the chosen language and offers its Discord bot. Follow it: give your Discord user id in the chat (it runs `bridge allow`), then it views `usine-secret`: the terminal asks the token hidden, Vulcain only sees "Secret stored", runs `bridge take-secret vulcain DISCORD_BOT_TOKEN` and gives the invite link. `grep -c USINE_PENDING /var/lib/usine-hermes/vulcain/.hermes/.env` is `0`; `sudo usine-hermes list` shows `vulcain active token=set`; Vulcain answers your mention on Discord.
   Then accept memory: the OpenRouter key is asked hidden the same way, `bridge memory` installs Docker and Honcho (`Honcho healthy`), `/etc/usine-hermes/openrouter.key` is `root:root 600`, `config honcho` is `true`.
3. **Idempotency**: leave the chat, re-run the install one-liner. Expect no question at all: `config gardée`, `Hermes ... already installed, skipping installer`, then straight into the chat. `sudo usine-hermes` alone also opens it; `ssh <vps> sudo usine-hermes` (no `-t`) prints the `ssh -t` hint.
   Two more profiles by hand:
   ```sh
   sudo usine-hermes create alice     # one sentence + bot A token: "alice créée et démarrée"
   sudo usine-hermes create bob       # one sentence + Enter: prints "sudo usine-hermes secret bob"
   sudo usine-hermes secret bob       # bot B token: bob starts by itself
   sudo usine-hermes list             # all active, token=set
   ```
   `create` asks exactly two questions and never the key; `alice`'s `.env` holds the shared key (`alice:alice 600`). Also check refusals: `create root` (non-managed user), `secret bob` with alice's token.
4. **Discord**: invite both bots. Mention each from your account: both answer. Message without a mention: silence. Mention from the non-allowlisted account: silence.
5. **Memory**: tell alice a fact, start a new conversation (or wait a few minutes for the deriver), ask about it: alice recalls it.
6. **Doctor**: `sudo usine-hermes doctor` and `sudo usine-hermes doctor alice`: every line `ok`, including `alice cannot-read-bob` and `bob cannot-read-alice`.
7. **Logs**: `sudo usine-hermes logs alice -n 200` and `status alice`: no token or key visible.
8. **Reboot**: `sudo reboot`, then `list` (both active), `doctor` green, both bots answer.
9. **Exposure**: `sudo ss -tlnp`: Honcho only on `127.0.0.1:8000`; no Postgres (5432) or Redis (6379) listener on any interface.
10. **Destroy**: `sudo usine-hermes destroy bob` (type `bob`). Then `id bob` and `getent group bob` fail, `/var/lib/usine-hermes/bob`, `/etc/usine-hermes/profiles/bob` and `/etc/systemd/system/usine-bob.service*` are gone, `list` and `doctor` show only alice.
11. **Vulcain creates an agent**: in the chat ask it to create `carol`. Expect: it asks only the name and what carol does, repeats them and waits for your yes, takes carol's Discord token through the hidden capture (`take-secret carol DISCORD_BOT_TOKEN`), and carol starts and answers on Discord. Ask Vulcain to destroy or stop `carol`, and to restart itself: each refused. `sudo usine-hermes doctor`: all `ok`, including `vulcain cannot-read-carol` and `carol cannot-read-vulcain`.
12. **model**: `sudo usine-hermes model alice`, choose `2` (Claude): the Max + credits warning, then `hermes auth add anthropic` paste-code as `alice`; alice restarts and answers. Optional: `7` (SuperGrok).

## Checklist of unverified assumptions

Tick each one on the VPS; open an issue for any failure.

### Bootstrap: Hermes
- [ ] `hermes --version` works as a non-root user and shows 0.21.5
- [ ] `git -C /usr/local/lib/hermes-agent rev-parse HEAD` is `f97608f...`; a second `bootstrap` skips the installer
- [ ] `discord`, `aiohttp`, `brotlicffi`, `honcho` importable from the venv as non-root (`/usr/local/lib/hermes-agent/venv/bin/python -c 'import discord, aiohttp, brotlicffi, honcho'`)
- [ ] `uv sync --locked` (with `UV_PROJECT_ENVIRONMENT`, uv found by `bootstrap`, normally `/root/.hermes/bin/uv`) reuses the venv without failing
- [ ] `/usr/local/share/uv/python` is not group/other-writable

### First bot
- [ ] `useradd`/`runuser` and `hermes config set` work as the profile user
- [ ] The drop-in lets the gateway start (`TemporaryFileSystem=<home_root>:ro` + `BindPaths` + `ProtectHome=tmpfs` + `ProtectProc=invisible`)
- [ ] Lazy installs as the profile find `/usr/local/bin/uv`
- [ ] `.env` is mode 600 owned by the profile
- [ ] `start` enables the unit and it survives a reboot
- [ ] The bot answers an allowlisted user on mention and ignores others
- [ ] Restart codes behave: exit 75 restarts, 78 does not loop
- [ ] Real journal lines are redacted in `logs`
- [ ] Known: a `create` failing midway leaves user + home; `destroy` cleans it

### Honcho
- [ ] Docker from the official repo installs on Ubuntu 24.04, Debian 12 and Debian 13; `docker compose version` >= v2.24
- [ ] The ghcr image entrypoint works without a build; `/health` answers within 180 s
- [ ] `ss -tlnp`: only `127.0.0.1:8000` from Honcho
- [ ] Honcho is back after reboot; a `bootstrap` re-run keeps the DB password and asks nothing
- [ ] Workspace `POST /v3/workspaces` is idempotent
- [ ] OpenRouter accepts `openai/gpt-5.4-mini` and the embeddings model `openai/text-embedding-3-small`
- [ ] The agent recalls facts across conversations

### Subscriptions
- [ ] `hermes auth add openai-codex`, `anthropic` and `xai-oauth` work in a TTY under `runuser` (device code / paste code, no browser)
- [ ] After `model`, `hermes` skips its setup wizard (provider configured)
- [ ] A subscription profile answers on Discord

### Terminal chat and hidden secrets
- [ ] `runuser --pty -u vulcain -- env … hermes --cli` gives a working classic REPL (line editing, Ctrl-C, exit)
- [ ] `usine-secret`'s `required_environment_variables` prompts hidden in the CLI and writes `USINE_PENDING_SECRET` to Vulcain's `.env` (mode `600`, owner `vulcain`)
- [ ] The model's tool output only says the secret was stored (check the session log for the value: absent)
- [ ] After `take-secret` removed it, a second capture in the same chat session prompts again (Hermes reads `.env`, not a stale process env)
- [ ] `bridge take-secret`, `allow`, `memory` run from the chat with no approval prompt (`command_allowlist`), and `memory` finishes within Hermes' terminal-tool timeout (Docker + image pulls)
- [ ] The invite link printed by `take-secret` matches the Developer Portal's Application ID

### Destroy and doctor
- [ ] With two real profiles, cross-read checks fail as expected and own-`.env` reads pass
- [ ] `systemctl show -p DropInPaths` lists `isolate.conf`
- [ ] `stat -c` owners/modes are as expected (home `700`, `.env` `600`, owned by the profile)
- [ ] `userdel` removes the profile group
- [ ] `destroy` cleans a half-created profile (no unit yet)

### Vulcain preset
- [ ] `sudo -n /usr/local/bin/usine-hermes bridge list` works inside Vulcain's sandbox (`NoNewPrivileges=no`, `ProtectSystem=strict`): sudo runs with a read-only `/run`, and `systemd-run` reaches PID 1 over its socket
- [ ] The bridge command runs from Discord with no approval prompt (pre-approved by `command_allowlist`), while another risky command (for example `rm -rf ~/x`) still asks for approval on Discord
- [ ] Hermes does not ask for a sudo password (no sudo prompt in the gateway; `sudo -n` fails fast otherwise)
- [ ] Vulcain's two skills show up in Hermes (ask Vulcain which skills it has)
- [ ] `hermes config set command_allowlist '[...]'` stores a list in Vulcain's `config.yaml`
- [ ] `systemd-run --wait --pipe` returns the inner exit code and output (a refused `start` of an empty token shows its error on Discord)
- [ ] `journalctl -t usine-hermes-bridge` shows one `caller=vulcain action=... target=...` line per call
- [ ] `max_profiles` reached: the bridge refuses `create`; the human's `create` still works
- [ ] `sudo -u vulcain sudo -n /bin/true` is refused (the rule allows the bridge only); `destroy vulcain` removes `/etc/sudoers.d/usine-hermes-vulcain`
