# usine-hermes

Turn a fresh VPS into a factory of isolated [Hermes Agent](https://github.com/NousResearch/hermes-agent) bots on Discord. One installer, one bash CLI, run directly on the VPS as root. Adding an agent is one command.

## What gets installed

```
/usr/local/bin/usine-hermes          the CLI (+ templates in /usr/local/share/usine-hermes)
/etc/usine-hermes/usine.yaml         machine config (no secrets)
/usr/local/lib/hermes-agent          Hermes, pinned, shared, root-owned, read-only for profiles
/opt/usine-hermes/honcho             Honcho memory (docker compose), API on 127.0.0.1:8000 only

per profile <name>:
  Linux user <name> (nologin, own group)
  <home_root>/<name>/                mode 700, HERMES_HOME=<home>/.hermes (.env 600, SOUL.md, honcho.json)
  usine-<name>.service               Hermes gateway, plus isolate.conf sandbox drop-in
  Honcho workspace <name>
```

Each profile is the default profile of its own Hermes home, so there is no profile multiplexing. The sandbox drop-in hides every other home (`ProtectHome=tmpfs`, `TemporaryFileSystem=<home_root>:ro`, only its own home bound in), mounts the system read-only (`ProtectSystem=strict`), hides foreign processes (`ProtectProc=invisible`) and sets `PrivateTmp` and `NoNewPrivileges`.

## Requirements

- Ubuntu 24.04 or Debian 12 (anything else is refused).
- Root (or sudo).
- Disk: about 2 GB for the shared Hermes install, plus a few GB for the Honcho images and database.
- RAM: Honcho runs Postgres, Redis, an API and a deriver; plan for at least 2 GB total, more with many agents.
- An OpenRouter API key for Honcho (unless `honcho: false`), and per profile a Discord bot token plus a model credential.

## Install

```sh
git clone https://github.com/Nardjo/usine-hermes && cd usine-hermes && sudo ./install.sh
```

`install.sh` copies the CLI and templates, then offers to run `init` (writes the config) and `bootstrap` (installs Hermes, Docker and Honcho). Enter means yes. Both can be re-run safely; `bootstrap` skips the Hermes installer when the pinned commit is already there, and keeps the Honcho database password and OpenRouter key.

## Quickstart

```sh
sudo usine-hermes create alice      # asks provider, personality, mission, key, Discord token
sudo usine-hermes start alice       # enable + start (refuses an empty or reused token)
sudo usine-hermes logs alice        # redacted journal
sudo usine-hermes doctor            # checks everything, including isolation
```

## Commands

`--dry-run` is accepted anywhere: commands are printed instead of run, no root needed, no secret prompts.

| Command | What it does |
|---|---|
| `init` | Asks a few questions, writes `/etc/usine-hermes/usine.yaml` (asks before overwriting). `USINE_CONFIG` overrides the path. |
| `config <key>` | Prints one config value. |
| `bootstrap` | Installs prerequisites, Hermes at the pinned tag, pre-installs the Discord and Honcho deps into the shared venv, then (if `honcho: true`) Docker from Docker's apt repo and the Honcho stack. Waits up to 180 s for Honcho health. Asks once (hidden) for the OpenRouter key. |
| `create <name> [--personality T] [--mission T] [--provider P]` | Creates the Linux user, home, `SOUL.md`, model config, Honcho workspace and `honcho.json`, `.env`, unit and drop-in. Does not start. Name must match `^[a-z][a-z0-9-]{1,30}$` and must not be an existing non-managed user. Secrets prompts are hidden; Enter leaves them empty. |
| `start <name>` | `systemctl enable --now`. Refuses if `DISCORD_BOT_TOKEN` is empty or used by another profile. |
| `stop <name>` / `restart <name>` | systemctl stop / restart. |
| `status <name>` | Redacted `systemctl status` plus `token=set|empty|unknown`. |
| `logs <name> [-n N]` | Last N journal lines (default 100), secrets redacted. |
| `list` | Every managed profile with unit state and token state. |
| `destroy <name>` | Asks you to type the name, then removes unit, drop-in, Linux user and home. Only touches profiles carrying the `.usine-hermes` marker. |
| `doctor [name]` | Checks Hermes pin, Honcho health, and per profile: unit loaded and active, drop-in applied, token set, home `700`, `.env` `600`, and that each profile reads its own `.env` but no other profile's. Exits non-zero on any `FAIL`. Run it as root. |

## Discord setup (one bot per profile)

1. Open the [Discord Developer Portal](https://discord.com/developers/applications), click **New Application**, name it after the profile.
2. **Bot** tab: click **Reset Token**, copy the token. Keep it secret.
3. Same tab, **Privileged Gateway Intents**: enable **Message Content Intent** and **Server Members Intent** (Presence is optional). Save.
4. Note the **Application ID** (General Information), then open this URL to invite the bot to your server:
   `https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot+applications.commands&permissions=309237763136`
   (scopes `bot applications.commands`, permissions `309237763136`).
5. Get your own user id for the allowlist: Discord **Settings > Advanced > Developer Mode** on, then right-click your name > **Copy User ID**. Put it in `discord_allowed_users` (at `init`, or edit the config; affects profiles created afterwards).
6. Paste the token when `create` asks for `DISCORD_BOT_TOKEN`, or later edit `<home_root>/<name>/.hermes/.env` (`DISCORD_BOT_TOKEN=...`).
7. `sudo usine-hermes start <name>`. Mention the bot in a channel; it only answers allowlisted users and only when mentioned (`DISCORD_REQUIRE_MENTION=true`).

Never reuse a token across profiles: two gateways on one bot fight each other (`start` refuses it).

## Providers

| Menu id | Auth | Default model | Limits |
|---|---|---|---|
| `openrouter` | `OPENROUTER_API_KEY` | `z-ai/glm-5.2` | |
| `anthropic` | `ANTHROPIC_API_KEY` | `claude-sonnet-4-6` | |
| `claude-subscription-directsdk-experimental` | Claude subscription: Claude CLI + Hermes plugin, `claude auth login` (paste code) | `sonnet` | Experimental plugin, may break on upgrades; bills ~1.7x the Agent SDK allowance; needs Max plus extra-usage credits; refuses `ANTHROPIC_*` in `.env`. |
| `openai-api` | `OPENAI_API_KEY` | `gpt-6-sol` | |
| `openai-codex` | ChatGPT subscription, `hermes auth add openai-codex` (device code) | `gpt-6-sol` | Plan quota for agent use is undocumented. |
| `xai` | `XAI_API_KEY` | `grok-4.6` | |
| `xai-oauth` | SuperGrok subscription, `hermes auth add xai-oauth` (device code) | `grok-4.6` | Some SuperGrok tiers answer 403. |
| `gemini` | `GEMINI_API_KEY` | `gemini-3.8-flash` | |
| `deepseek` | `DEEPSEEK_API_KEY` | `deepseek-flash` | |

API keys are prompted hidden and written to the profile's `.env`. Subscription logins run as the profile's Linux user, so tokens stay in that profile (`$HERMES_HOME/auth.json`). Skip the login at `create` and it prints the exact command to run later. `model.provider` is always set explicitly.

## Config reference

`/etc/usine-hermes/usine.yaml`, flat `key: value`, no secrets. See [usine.example.yaml](usine.example.yaml).

| Key | Default | Meaning |
|---|---|---|
| `home_root` | `/var/lib/usine-hermes` | Parent of every profile home. |
| `hermes_version` | `v2026.9.24` | Hermes tag, resolved to its commit and installed once. |
| `default_provider` | `openrouter` | Preselected in the `create` menu. |
| `model_<provider>` | see table above | Default model per provider (`-` in the id becomes `_`). |
| `discord_allowed_users` | empty | Comma-separated Discord user ids. Empty: nobody is allowed. Copied into each profile's `.env` at `create`. |
| `honcho` | `true` | `false` skips Docker, Honcho and memory config. |
| `peer_name` | `owner` | Your name as a peer in Honcho. |
| `honcho_url` | `http://127.0.0.1:8000` | Honcho API used by bootstrap and profiles. |

## Security model and known limits

- File isolation: each profile is its own Linux user with a `700` home and a `600` `.env`; the systemd sandbox hides other homes and processes. `doctor` proves cross-profile reads fail.
- Secrets are prompted hidden, written with umask 077, never passed on a visible command line, and redacted in `logs`/`status`. The config file holds none.
- Honcho has no auth: it listens on 127.0.0.1 only, but any local process, including any profile, can query any workspace. File isolation holds; **memory isolation between profiles does not**.
- Pre-installing the Discord and Honcho deps into the shared venv is inferred from upstream's Docker image, not documented for script installs. Each profile also gets its own lazy-install directory as a fallback.
- No upgrades in V1: changing `hermes_version` and re-running `bootstrap` is untested; do not run `hermes update` (it leaves the pin). No backups.
- A `create` that fails midway leaves the user and home behind; clean up with `destroy`.
- Discord only.

## Tests

```sh
bash tests/test.sh
```

Dependency-free, no root, no VPS: covers name validation, `init`, `install.sh` OS/root refusal, `--dry-run` of `bootstrap` and `create`, the profile lifecycle and `doctor` against stubbed system commands, and `shellcheck` on every shell file. On macOS use a bash 5 (`/opt/homebrew/bin/bash tests/test.sh`). What needs a real VPS is in [docs/vps-validation.md](docs/vps-validation.md).

## License

MIT, see [LICENSE](LICENSE).
