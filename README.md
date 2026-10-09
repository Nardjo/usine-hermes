# usine-hermes

Turn a fresh VPS into a factory of isolated [Hermes Agent](https://github.com/NousResearch/hermes-agent) bots on Discord. One installer, one bash CLI, run directly on the VPS as root. The install ends in a terminal chat with Vulcain, the operator agent, which sets up the rest (Discord, memory, your agents) from the conversation.

## What gets installed

```
/usr/local/bin/usine-hermes          the CLI (+ templates and skill in /usr/local/share/usine-hermes)
/etc/usine-hermes/usine.yaml         machine config (no secrets)
/etc/usine-hermes/openrouter.key     OpenRouter key (root, 600), once memory is on: Honcho + default profile key
/etc/usine-hermes/treg.token         treg team token (root, 600), once `treg` ran: copied into each profile's .env
/etc/usine-hermes/profiles/<name>    root-owned ownership marker of each managed profile (holds its provider)
/usr/local/lib/hermes-agent          Hermes, pinned, shared, root-owned, read-only for profiles
/opt/usine-hermes/honcho             Honcho memory (docker compose, once enabled), API on 127.0.0.1:8000 only

per profile <name>:
  Linux user <name> (nologin, own group)
  <home_root>/<name>/                mode 700, HERMES_HOME=<home>/.hermes (.env 600, SOUL.md, honcho.json)
  usine-<name>.service               Hermes gateway, plus isolate.conf sandbox drop-in
  Honcho workspace <name>

Vulcain (created at install, see below):
  /etc/sudoers.d/usine-hermes-<name> one rule: the bridge, nothing else
  usine-<name>.service.d/vulcain.conf NoNewPrivileges=no
  <home>/.hermes/skills/{usine-hermes,usine-secret}/SKILL.md
```

Each profile is the default profile of its own Hermes home, so there is no profile multiplexing. The sandbox drop-in hides every other home (`ProtectHome=tmpfs`, `TemporaryFileSystem=<home_root>:ro`, only its own home bound in), mounts the system read-only (`ProtectSystem=strict`), hides foreign processes (`ProtectProc=invisible`) and sets `PrivateTmp` and `NoNewPrivileges`.

## Requirements

- Ubuntu 24.04, Debian 12 or Debian 13 (anything else is refused).
- Root (or sudo).
- Disk: about 2 GB for the shared Hermes install, plus a few GB for the Honcho images and database.
- RAM: Honcho runs Postgres, Redis, an API and a deriver; plan for at least 2 GB total, more with many agents.
- A model for Vulcain: a ChatGPT or Claude Max subscription, or an API key (OpenRouter, Anthropic, OpenAI, xAI, Gemini, DeepSeek). Later, optional: an OpenRouter key for memory, and per agent a Discord bot.

## Install

One command, two questions (answer `2` to the first one for French), then you talk to Vulcain:

```
curl -fsSL https://raw.githubusercontent.com/Nardjo/usine-hermes/main/install.sh | sudo bash
Language / Langue : [1] English  [2] Français  (Enter = 1)
… installs the CLI and the pinned shared Hermes, creates Vulcain (no Discord yet, not started)
Which model for vulcain?
  1) ChatGPT (Codex subscription)
  2) Claude (Max subscription + credits)
  3) OpenRouter (API key)
  4) Anthropic (API key)
  5) OpenAI (API key)
  6) xAI (API key)   7) SuperGrok (subscription)   8) Gemini (API key)   9) DeepSeek (API key)
Choice (Enter = 1):
… device-code login as user vulcain, or the key asked hidden
… the Hermes chat with Vulcain opens
```

Over SSH, keep a terminal: `ssh -t <vps> 'curl -fsSL … | sudo bash'` (or log in first). Or from a clone: `git clone https://github.com/Nardjo/usine-hermes && cd usine-hermes && sudo ./install.sh`.

Piped, `install.sh` downloads the repo (branch `main`, or `bash -s -- --ref <branch|tag>`) and runs itself from it with the terminal as input. It copies the CLI, templates and skills, then chains `init` (the language), `bootstrap` (Hermes; no Docker, memory is off), `create vulcain --preset vulcain`, and opens the chat (`usine-hermes` with no command), which first asks Vulcain's model. Re-running it asks nothing already known: the config and Vulcain are kept, `bootstrap` skips the Hermes installer when the pinned commit is already there, and a Vulcain with a model goes straight to the chat.

Back later: `sudo usine-hermes` (over SSH: `ssh -t <vps> sudo usine-hermes`).

## Quickstart

In the chat, Vulcain offers, one at a time: its own Discord bot (it walks you through the Developer Portal, asks your Discord user id, takes the token hidden and starts), memory (an OpenRouter key, hidden), then your first agent. Secrets never go through the chat: Vulcain's `usine-secret` skill makes the terminal ask them hidden (see below).

Everything also works by hand:

```
sudo usine-hermes create alice
Que doit faire alice ? (une phrase) :
Token du bot Discord d'alice (Entrée = plus tard) :
✓ alice créée et démarrée. Mentionne @alice sur Discord.
```

No token yet? `sudo usine-hermes secret alice` asks it and starts the bot. Then `sudo usine-hermes logs alice` (redacted journal) and `sudo usine-hermes doctor` (everything, including isolation).

## Vulcain: the operator agent

Created at install (`sudo usine-hermes create vulcain --preset vulcain` by hand), without a model or Discord: the chat asks its model first (`sudo usine-hermes model vulcain` changes it).

On top of a normal profile it gets a Vulcain `SOUL.md` (in the config's language), two Hermes skills ([skills/usine-hermes](skills/usine-hermes/SKILL.md), [skills/usine-secret](skills/usine-secret/SKILL.md), installed in `<home>/.hermes/skills/`), one sudoers rule (`/etc/sudoers.d/usine-hermes-<name>`), and a drop-in `vulcain.conf`. The terminal chat runs Hermes' classic REPL as the Linux user `vulcain` (`runuser --pty`); once it has its Discord token, the same profile also answers on Discord.

Secrets without the model seeing them: `usine-secret` declares `required_environment_variables: [USINE_PENDING_SECRET]`. When Vulcain views it, the Hermes CLI asks the value hidden and stores it in Vulcain's `.env`; the model only sees "Secret stored". Vulcain then runs `bridge take-secret <name> <KEY>` (or `bridge memory`): root moves the value into the target profile's `.env` (allowed keys only, `600`) and deletes it from Vulcain's. A Discord token starts the profile and prints its invite link (from the token's public application id). This only works in the terminal chat; on Discord, or if it fails, run `sudo usine-hermes secret <name> [KEY]` in another terminal.

What it can run, through `sudo -n /usr/local/bin/usine-hermes bridge <action>` only:

- allowed: `list`, `status`, `logs` (redacted, at most 1000 lines), `doctor`, `restart`, `start` (still refuses an empty token), `create` (flags only, never prompts, no secrets, no preset), `take-secret <name> <KEY>` (the secret it captured, allowed keys only, its own Discord token included), `allow <ids>` (digits and commas: `discord_allowed_users` in the config and every `.env`, running profiles restarted), `memory` (Docker + Honcho with the OpenRouter key it captured, moved to `/etc/usine-hermes/openrouter.key`; every profile wired and restarted);
- denied: `destroy`, `secret`, `model`, `stop`, `init`, `bootstrap`, `config`, and anything on its own profile except `status`, `logs` and `take-secret`;
- quota: `create` is refused once `max_profiles` managed profiles exist (operator included). Your own `create` is not capped.

How it works: the bridge is a hidden subcommand of the root-owned CLI. It re-validates every argument (action allowlist, name regex, provider allowlist, personality at most 200 characters and mission at most 500, no control characters), logs `caller=<sudo user> action=<action> target=<name>` to the journal (`journalctl -t usine-hermes-bridge`), then hands the command to systemd (`systemd-run --wait --pipe`), so it runs as root outside Vulcain's sandbox. In Hermes, that one command line is pre-approved in Vulcain's `command_allowlist` (`sudo -n /usr/local/bin/usine-hermes bridge *`): no YOLO mode, every other risky command still asks for approval (in the terminal or on Discord), and Hermes refuses the allowlist shortcut for compound commands (`;`, `&&`, `|`, `$(...)`).

## Commands

`--dry-run` is accepted anywhere: commands are printed instead of run, no root needed. Prompts are the same; secret values are never printed.

| Command | What it does |
|---|---|
| (none) | Opens the terminal chat with Vulcain: `runuser --pty -u vulcain -- … hermes --cli`. Asks Vulcain's model first if it has none. Needs a terminal (`ssh -t`). |
| `init` | Asks the language (`[1] English  [2] Français`, skipped when `USINE_LANG` is set) and writes `/etc/usine-hermes/usine.yaml` (no Discord id yet, `honcho: false`). Does nothing if the config exists. `USINE_CONFIG` overrides the path; the OpenRouter key and the profile registry (`profiles/`) live next to it. |
| `config <key>` | Prints one config value. |
| `bootstrap` | Installs prerequisites, Hermes at the pinned tag, pre-installs the Discord and Honcho deps into the shared venv, then (if `honcho: true`, set by the bridge `memory` action) Docker from Docker's apt repo and the Honcho stack, using the stored OpenRouter key. Waits up to 180 s for Honcho health. Asks nothing. |
| `create <name> [--mission T] [--personality T] [--provider P] [--preset vulcain]` | Asks what the agent does (unless `--mission`) and its Discord bot token (hidden; Enter = later). Creates the Linux user, home, `SOUL.md` (default personality unless `--personality`), model config, Honcho workspace and `honcho.json`, `.env`, unit and drop-in, then starts it if a token was given; otherwise prints the one `secret` command. Provider `openai-codex` by default (ChatGPT subscription, model `gpt-5.6-terra`, login offered as the profile user, or later with `model <name>`); with `--provider openrouter` the stored key (memory on) is copied into the profile's `.env` (`600`), else asked; any other `--provider P` asks that provider's key or offers its subscription login. A reused token is refused before anything is created. Name must match `^[a-z][a-z0-9-]{1,30}$` and must not be an existing non-managed user; an already managed name (including a half-created profile) is refused with a pointer to `destroy`. With `--mission` and stdin not a terminal (a script, a coding agent, Vulcain), it never prompts: the token stays empty, subscription login is skipped, and it prints the commands to run next. `--preset vulcain` makes the operator profile (section above): no question, no model, no token. |
| (Lightpanda) | Not a command: `bootstrap` installs the [Lightpanda](https://github.com/lightpanda-io/browser) headless browser (pinned release, sha256-checked) as `/usr/local/bin/lightpanda`, and `create` gives every profile its stdio MCP server (`mcp_servers.lightpanda`, `lightpanda mcp`, telemetry off): browsing tools, about 17 MB idle per running profile. No screenshots (no graphical renderer). |
| `treg` | Asks the treg team token (hidden; <https://treg.to>, a tool catalog for agents over MCP, billed per call to the team balance), stores it in `/etc/usine-hermes/treg.token` (`600`), and gives every profile the `treg` MCP server (`mcp_servers.treg` at `https://treg.to/mcp/`, `Authorization: Bearer ${MCP_TREG_API_KEY}` from its `.env`), restarting running ones. Later profiles get it at `create`. Vulcain runs it through the bridge with the token you typed in the chat. Every agent shares the team balance. |
| `channel <name> <id>` | Sets the profile's own Discord channel (`DISCORD_FREE_RESPONSE_CHANNELS` in its `.env`): there it answers every message, inline (Hermes does not auto-thread free-response channels); everywhere else only when mentioned (`DISCORD_REQUIRE_MENTION=true`), in a thread. Restarts the profile if it runs. `create --channel <id>` sets it at creation; Vulcain asks for it. |
| `model <name>` | The provider menu above: sets `model.provider` and `model.default` (from the config), runs the login as the profile user (`hermes auth add openai-codex|anthropic|xai-oauth`) or asks the key hidden into its `.env`, records the provider in the registry, restarts the profile if it runs. |
| `secret <name> [KEY]` | Without `KEY`: asks (hidden) the Discord bot token (refuses anything not shaped like one, or used by another profile), prints the invite link, then starts the profile if it is stopped. With `KEY`: asks one value and writes or replaces it. Values go to the profile's `.env` (mode `600`, owned by the profile) and are never printed. `KEY` is `DISCORD_BOT_TOKEN` or the key variable of the profile's own provider (table below; none for subscriptions); managed profiles only; an empty value changes nothing. Says to `restart` if the profile is running. |
| `start <name>` | `systemctl enable --now`. Refuses if `DISCORD_BOT_TOKEN` is empty or used by another profile. |
| `stop <name>` / `restart <name>` | systemctl stop / restart. |
| `status <name>` | Redacted `systemctl status` plus `token=set|empty|unknown`. |
| `logs <name> [-n N]` | Last N journal lines (default 100), secrets redacted. |
| `list` | Every managed profile with unit state and token state. |
| `destroy <name>` | Asks you to type the name, then removes unit, drop-in, Linux user and home. Only touches profiles listed in the root-owned registry `/etc/usine-hermes/profiles/`. |
| `doctor [name]` | Checks Hermes pin, Honcho health, and per profile: unit loaded and active, drop-in applied, token set, home `700`, `.env` `600`, and that each profile reads its own `.env` but no other profile's. Exits non-zero on any `FAIL`. Run it as root. |

## Discord setup (one bot per profile)

1. Open the [Discord Developer Portal](https://discord.com/developers/applications), click **New Application**, name it after the profile.
2. **Bot** tab: click **Reset Token**, copy the token. Keep it secret.
3. Same tab, **Privileged Gateway Intents**: enable **Message Content Intent** and **Server Members Intent** (Presence is optional). Save.
4. Note the **Application ID** (General Information), then open this URL to invite the bot to your server:
   `https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot+applications.commands&permissions=309237763136`
   (scopes `bot applications.commands`, permissions `309237763136`).
5. Your own user id: Discord **Settings > Advanced > Developer Mode** on, then right-click your name > **Copy User ID**. Give it to Vulcain (bridge `allow`): it lands in `discord_allowed_users` and every profile's `.env`.
6. Give the token through Vulcain (hidden capture), paste it when `create` asks for it, or run `sudo usine-hermes secret <name>`: the bot starts by itself.
7. Mention the bot in a channel; it only answers allowlisted users and only when mentioned (`DISCORD_REQUIRE_MENTION=true`).

Never reuse a token across profiles: two gateways on one bot fight each other (`create`, `secret` and `start` refuse it).

## Providers

`usine-hermes model <name>` offers all of them (menu above); `create` uses `openai-codex` (ChatGPT subscription, `gpt-5.6-terra`) unless `--provider <id>`. Every profile, Vulcain included, is created with `agent.reasoning_effort: medium` (what `/reasoning medium --global` saves) and `display.tool_progress: off` (no tool-call lines in the terminal chat or on Discord; `hermes config set display.tool_progress all` as the profile brings them back):

| Id | Auth | Default model | Limits |
|---|---|---|---|
| `openrouter` | `OPENROUTER_API_KEY` | `z-ai/glm-5.2` | |
| `anthropic` | `ANTHROPIC_API_KEY`, or Claude subscription: `hermes auth add anthropic` (paste code, `model` only) | `claude-sonnet-4-6` | Subscription: a Max plan with purchased extra-usage credits only, not Pro. |
| `openai-api` | `OPENAI_API_KEY` | `gpt-6-sol` | |
| `openai-codex` | ChatGPT subscription, `hermes auth add openai-codex` (device code) | `gpt-5.6-terra` | Plan quota for agent use is undocumented. |
| `xai` | `XAI_API_KEY` | `grok-4.6` | |
| `xai-oauth` | SuperGrok subscription, `hermes auth add xai-oauth` (device code) | `grok-4.6` | Some SuperGrok tiers answer 403. |
| `gemini` | `GEMINI_API_KEY` | `gemini-3.8-flash` | |
| `deepseek` | `DEEPSEEK_API_KEY` | `deepseek-flash` | |

API keys are prompted hidden and written to the profile's `.env`. Subscription logins run as the profile's Linux user, so tokens stay in that profile (`$HERMES_HOME/auth.json`). Skip the login at `create` and it prints `sudo usine-hermes model <name>` to run later. `model.provider` is always set explicitly.

## Config reference

`/etc/usine-hermes/usine.yaml`, flat `key: value`, no secrets, written once by `init` with defaults (edit it by hand to change one). See [usine.example.yaml](usine.example.yaml). Every command validates `home_root` (absolute, not `/`, no `..`, only `A-Za-z0-9/._-`), `hermes_version` (`vX.Y.Z`), `peer_name`, `honcho_url` and `discord_allowed_users`, and refuses to run on a bad value.

| Key | Default | Meaning |
|---|---|---|
| `lang` | `en` (asked first at install) | Language of every prompt and message: `en` or `fr`. The `USINE_LANG` env var overrides it. Vulcain answers in the language you write to it. |
| `home_root` | `/var/lib/usine-hermes` | Parent of every profile home. |
| `hermes_version` | `v2026.9.24` | Hermes tag, resolved to its commit and installed once. |
| `model_<provider>` | see table above | Default model per provider (`-` in the id becomes `_`). |
| `discord_allowed_users` | empty | Comma-separated Discord user ids. Empty: nobody is allowed. Set by the bridge `allow` (config and every `.env`); copied into each profile's `.env` at `create`. |
| `honcho` | `false` | `true` once the bridge `memory` action ran; `false` skips Docker, Honcho and memory config. |
| `peer_name` | `owner` | Your name as a peer in Honcho. |
| `honcho_url` | `http://127.0.0.1:8000` | Honcho API used by bootstrap and profiles. |
| `max_profiles` | `10` | Most managed profiles (operator included) a Vulcain operator may reach with `create`. Read only by the bridge. |

## Security model and known limits

- File isolation: each profile is its own Linux user with a `700` home and a `600` `.env`; the systemd sandbox hides other homes and processes. `doctor` proves cross-profile reads fail.
- Secrets are prompted hidden, written with umask 077, never passed on a visible command line, and redacted in `logs`/`status`. The config file holds none.
- Once memory is on, one shared OpenRouter key: root-only in `/etc/usine-hermes/openrouter.key`, used by Honcho and copied into each later default profile's `.env`. A profile can therefore spend on the shared account; give one its own key with `secret <name> OPENROUTER_API_KEY`. Rotating the shared key means updating that file, Honcho's `.env` and each profile.
- Honcho has no auth: it listens on 127.0.0.1 only, but any local process, including any profile, can query any workspace. File isolation holds; **memory isolation between profiles does not**.
- Pre-installing the Discord and Honcho deps into the shared venv is inferred from upstream's Docker image, not documented for script installs. Each profile also gets its own lazy-install directory as a fallback.
- No upgrades in V1: changing `hermes_version` and re-running `bootstrap` is untested; do not run `hermes update` (it leaves the pin). No backups.
- A `create` that fails midway leaves the user and home behind; its marker is written right after the user, so `destroy` always cleans it up.
- The terminal chat runs as the `vulcain` user but outside its systemd sandbox (no `isolate.conf`): other homes stay unreadable (`700`), yet Vulcain sees the rest of the system as any unprivileged user would.
- Hidden capture relies on Hermes' skill secret prompt (CLI only, 120 s timeout). If Hermes keeps a captured value in its process environment after the bridge removed it from `.env`, a second capture in the same chat session may not prompt; restart the chat or use `secret`.
- Vulcain trades one sandbox setting for its power. Its unit sets `NoNewPrivileges=no`, otherwise `sudo` (setuid) cannot run; every other sandbox setting stays, and the only thing sudo lets it run is the bridge. The bridge validates its arguments and runs the real command in a fresh systemd unit as root, outside the sandbox. Consequence: whoever controls Vulcain (you on Discord, or a prompt injection that reaches it) can create profiles up to `max_profiles`, start and restart them, read redacted logs, change who may talk to the bots (`allow`) and turn memory on, but never sees a secret (it only moves the one you typed hidden), never stops or destroys anything, and cannot change its own profile beyond its Discord token. Created profiles stay stopped until they get their Discord token. Every bridge call is in `journalctl -t usine-hermes-bridge`. To revoke it: `sudo rm /etc/sudoers.d/usine-hermes-<name>` (or `destroy` it).
- Discord only.

## Tests

```sh
bash tests/test.sh
```

Dependency-free, no root, no VPS: covers name validation, the questions `init`, `create`, `model` and `secret` ask (and do not ask) in English and French, `install.sh` OS/root refusal, `--dry-run` of `bootstrap`, `create`, `model` and the chat, `secret`, `take-secret`, `allow`, `memory`, the profile lifecycle, `doctor` and the Vulcain bridge against stubbed system commands, and `shellcheck` on every shell file. On macOS use a bash 5 (`/opt/homebrew/bin/bash tests/test.sh`). What needs a real VPS is in [docs/vps-validation.md](docs/vps-validation.md).

## License

MIT, see [LICENSE](LICENSE).
