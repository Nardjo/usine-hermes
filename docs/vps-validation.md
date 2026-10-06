# Manual validation on a throwaway VPS

`tests/test.sh` cannot exercise systemd, Docker, Discord or provider logins. Run this procedure before calling a release good. Use a fresh Ubuntu 24.04 VPS (2 GB+ RAM), then repeat on Debian 12 and Debian 13 if possible. Destroy the VPS afterwards.

You need: an OpenRouter key (Honcho + profiles), two Discord applications with bots (see the README Discord guide), a test Discord server, your Discord user id, and a second Discord account that is not allowlisted.

## Procedure

1. **Install**
   ```sh
   git clone https://github.com/Nardjo/usine-hermes && cd usine-hermes && sudo ./install.sh
   ```
   Answer `init` with your user id as allowlist, keep `honcho: true`. Let `bootstrap` run; paste the OpenRouter key when asked. Expect `Honcho healthy` and `bootstrap done`.
2. **Idempotency**: `sudo usine-hermes bootstrap` again. Expect `Hermes ... already installed, skipping installer`, `Docker with compose already installed`, no key prompt, `bootstrap done`. Re-run `sudo ./install.sh` and answer `n`: no error.
3. **Two profiles**
   ```sh
   sudo usine-hermes create alice --provider openrouter   # paste key + bot A token
   sudo usine-hermes create bob --provider openrouter     # paste key + bot B token
   sudo usine-hermes start alice && sudo usine-hermes start bob
   sudo usine-hermes list                                 # both active, token=set
   ```
   Also check refusals: `create root` (non-managed user), `start` with a token copied from the other profile.
4. **Discord**: invite both bots. Mention each from your account: both answer. Message without a mention: silence. Mention from the non-allowlisted account: silence.
5. **Memory**: tell alice a fact, start a new conversation (or wait a few minutes for the deriver), ask about it: alice recalls it.
6. **Doctor**: `sudo usine-hermes doctor` and `sudo usine-hermes doctor alice`: every line `ok`, including `alice cannot-read-bob` and `bob cannot-read-alice`.
7. **Logs**: `sudo usine-hermes logs alice -n 200` and `status alice`: no token or key visible.
8. **Reboot**: `sudo reboot`, then `list` (both active), `doctor` green, both bots answer.
9. **Exposure**: `sudo ss -tlnp`: Honcho only on `127.0.0.1:8000`; no Postgres (5432) or Redis (6379) listener on any interface.
10. **Destroy**: `sudo usine-hermes destroy bob` (type `bob`). Then `id bob` and `getent group bob` fail, `/var/lib/usine-hermes/bob`, `/etc/usine-hermes/profiles/bob` and `/etc/systemd/system/usine-bob.service*` are gone, `list` and `doctor` show only alice.
11. **Vulcain**
    ```sh
    sudo usine-hermes create vulcain --preset vulcain --provider openrouter
    sudo usine-hermes secret vulcain DISCORD_BOT_TOKEN && sudo usine-hermes secret vulcain OPENROUTER_API_KEY
    sudo usine-hermes start vulcain
    ```
    On Discord ask it to create `carol` (openrouter). Expect: it repeats the values and waits for your yes, then gives you the Discord steps and the `secret` + `start` commands, and never asks for a token. `list` shows `carol inactive token=empty`. Run the `secret` commands yourself, then ask Vulcain to start `carol`: it answers on Discord. Ask Vulcain to destroy or stop `carol`, to set a secret, and to restart itself: each refused. `sudo usine-hermes doctor`: all `ok`, including `vulcain cannot-read-carol` and `carol cannot-read-vulcain`.
12. Optional: a third profile with a subscription provider (`claude-subscription-directsdk-experimental`, `openai-codex` or `xai-oauth`), login at `create`, start, answer on Discord.

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
- [ ] Honcho is back after reboot; a `bootstrap` re-run keeps the DB password and does not re-ask the key
- [ ] Workspace `POST /v3/workspaces` is idempotent
- [ ] OpenRouter accepts `openai/gpt-5.4-mini` and the embeddings model `openai/text-embedding-3-small`
- [ ] The agent recalls facts across conversations

### Subscriptions
- [ ] `hermes plugins install` runs non-interactively
- [ ] Claude CLI installs under `runuser` with the profile HOME; `claude auth login` paste-code works without a browser
- [ ] `hermes auth add` device-code flows work in a TTY under `runuser`
- [ ] The gateway sandbox finds the profile's `claude` (`~/.local/bin` on PATH)
- [ ] A subscription profile answers on Discord

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
- [ ] Vulcain's skill shows up in Hermes (ask Vulcain which skills it has)
- [ ] `hermes config set command_allowlist '[...]'` stores a list in Vulcain's `config.yaml`
- [ ] `systemd-run --wait --pipe` returns the inner exit code and output (a refused `start` of an empty token shows its error on Discord)
- [ ] `journalctl -t usine-hermes-bridge` shows one `caller=vulcain action=... target=...` line per call
- [ ] `max_profiles` reached: the bridge refuses `create`; the human's `create` still works
- [ ] `sudo -u vulcain sudo -n /bin/true` is refused (the rule allows the bridge only); `destroy vulcain` removes `/etc/sudoers.d/usine-hermes-vulcain`
