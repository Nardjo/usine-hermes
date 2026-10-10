<!-- À coller tel quel dans Claude Code, lancé sur le VPS par un utilisateur qui a sudo. Tout ce qui suit la ligne ===== est le prompt. -->

=====

Tu es sur un VPS Linux (Debian 12/13 ou Ubuntu 24.04), connecté avec un utilisateur qui a `sudo`.
Ta mission : installer **Hermes Agent** (Nous Research) et créer **Vulcain**, un agent Hermes administrateur qui peut créer, modifier et supprimer d'autres agents Hermes, et se modifier lui-même. Chaque autre agent est isolé (son propre utilisateur Linux et une prison systemd), avec son propre bot Discord et ses propres identifiants de modèle.

Suis les étapes dans l'ordre. Avant chaque étape, annonce-la en une ligne. Après chaque étape, lance la vérification indiquée et montre le résultat. Réponds en français.

## Règles absolues
1. **Secrets** (token Discord, clé API) : ne m'en demande JAMAIS un dans la conversation, ne lis jamais un `.env`, `auth.json` ou fichier de clé (pas de cat/grep/head/tail/less dessus, même avec sudo). Quand un secret est nécessaire, donne-moi la commande `sudo agent-secret <agent> <CLÉ>` (étape 3) à lancer moi-même dans un autre terminal SSH, et attends que je réponde « fait ».
2. Ne passe jamais `--dir` à l'installeur Hermes ; passe toujours `--skip-setup`.
3. N'ouvre aucun port vers l'extérieur. Ne modifie pas le pare-feu, SSH, ni les services existants qui ne sont pas à toi.
4. Toute suppression (`rm`, `userdel`, `docker compose down`, `apt purge`) : demande-moi avant.
5. En cas d'échec : lis les logs, explique la cause, propose un correctif. Ne contourne pas une sécurité.

## Ce que tu me demandes au début (pas des secrets)
- Mon (mes) identifiant(s) utilisateur Discord, pour l'allowlist (Discord → Paramètres → Avancés → Mode développeur, puis clic droit sur mon pseudo → Copier l'identifiant).
- Le modèle de Vulcain : abonnement ChatGPT (`openai-codex`, par défaut), abonnement Claude Max avec crédits (`anthropic`), SuperGrok (`xai-oauth`), ou une clé API (OpenRouter, Anthropic, OpenAI, xAI, Gemini, DeepSeek).
- Un nom d'interlocuteur pour la mémoire (mon prénom, en minuscules).

## Étape 1 : prérequis
```bash
. /etc/os-release; echo "$ID $VERSION_ID"     # doit être debian 12, debian 13 ou ubuntu 24.04, sinon arrête-toi et dis-le-moi
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl tar coreutils ca-certificates
sudo install -d -m 755 /var/lib/agents
```

## Étape 2 : Hermes, une seule installation partagée, figée
Version figée : tag `v2026.9.24` = commit `f97608f178d1ffeca59860195ab7da295f7c8e5f`. Vérifie d'abord que le tag pointe toujours sur ce commit (`git ls-remote https://github.com/NousResearch/hermes-agent 'refs/tags/v2026.9.24^{}'`) ; si ce n'est pas le cas, arrête-toi et demande-moi.
```bash
SHA=f97608f178d1ffeca59860195ab7da295f7c8e5f
curl -fsSL -o /tmp/hermes-install.sh "https://raw.githubusercontent.com/NousResearch/hermes-agent/$SHA/scripts/install.sh"
sudo bash /tmp/hermes-install.sh --commit "$SHA" --non-interactive --skip-setup --skip-browser --skip-computer-use --hermes-home /root/.hermes
rm -f /tmp/hermes-install.sh
UV=$(sudo sh -c 'ls /root/.hermes/bin/uv /root/.local/bin/uv /usr/local/bin/uv 2>/dev/null' | head -1); echo "uv: $UV"
sudo env UV_PROJECT_ENVIRONMENT=/usr/local/lib/hermes-agent/venv UV_PYTHON=/usr/local/lib/hermes-agent/venv/bin/python \
  "$UV" sync --extra all --extra messaging --extra honcho --locked --project /usr/local/lib/hermes-agent
sudo chown -R root:root /usr/local/lib/hermes-agent && sudo chmod -R go-w /usr/local/lib/hermes-agent
[ "$UV" = /usr/local/bin/uv ] || sudo install -m 755 "$UV" /usr/local/bin/uv
```
Vérification : `git -C /usr/local/lib/hermes-agent rev-parse HEAD` = le SHA ; `sudo -u nobody /usr/local/bin/hermes --version` fonctionne ; `sudo -u nobody /usr/local/lib/hermes-agent/venv/bin/python -c 'import discord, honcho'` ne renvoie pas d'erreur.

## Étape 3 : deux petits outils d'administration
`/usr/local/sbin/agent-secret` (c'est MOI qui le lance pour saisir un secret en masqué) :
```bash
sudo tee /usr/local/sbin/agent-secret >/dev/null <<'EOF'
#!/usr/bin/env bash
# agent-secret <agent> [KEY]: ask a secret hidden, store it in the agent's .env (600, owned by the agent).
set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
a=${1:-}; k=${2:-DISCORD_BOT_TOKEN}
[[ $a =~ ^[a-z][a-z0-9-]{1,30}$ && $k =~ ^[A-Z][A-Z0-9_]*$ ]] || { echo "usage: agent-secret <agent> [KEY]" >&2; exit 2; }
d=/var/lib/agents/$a/.hermes
[[ -d $d ]] || { echo "unknown agent: $a" >&2; exit 1; }
read -rsp "$k for $a (hidden): " v; echo
[[ -n $v ]] || { echo "empty, nothing changed" >&2; exit 1; }
if [[ $k == DISCORD_BOT_TOKEN && ! $v =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
  echo "not a bot token: Developer Portal > your app > Bot > Reset Token (not the Client Secret)" >&2; exit 1
fi
umask 077; tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
{ grep -v "^$k=" "$d/.env" 2>/dev/null || true; printf '%s=%s\n' "$k" "$v"; } >"$tmp"
install -m 600 -o "$a" -g "$(id -gn "$a")" "$tmp" "$d/.env"
echo "$k saved for $a. Apply: sudo systemctl restart agent-$a"
EOF
sudo chmod 755 /usr/local/sbin/agent-secret
```
`/usr/local/bin/vulcain` (ouvre le chat avec Vulcain dans le terminal) :
```bash
sudo tee /usr/local/bin/vulcain >/dev/null <<'EOF'
#!/usr/bin/env bash
# vulcain: chat with Vulcain in this terminal (Hermes classic REPL).
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
h=/var/lib/agents/vulcain
exec runuser --pty -u vulcain -- env HOME="$h" HERMES_HOME="$h/.hermes" HERMES_LAZY_INSTALL_TARGET="$h/lazy-packages" \
  PATH="$h/.local/bin:/usr/local/bin:/usr/bin:/bin" hermes --cli "$@"
EOF
sudo chmod 755 /usr/local/bin/vulcain
```

## Étape 4 : l'utilisateur Vulcain, avec tous les droits
```bash
H=/var/lib/agents/vulcain
sudo useradd --system --user-group --home-dir "$H" --no-create-home --shell /bin/bash vulcain
sudo install -d -m 700 -o vulcain -g vulcain "$H" "$H/.hermes" "$H/lazy-packages" "$H/.hermes/skills" "$H/.hermes/skills/agents"
echo 'vulcain ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/vulcain.new >/dev/null
sudo chmod 440 /etc/sudoers.d/vulcain.new && sudo visudo -cf /etc/sudoers.d/vulcain.new && sudo mv /etc/sudoers.d/vulcain.new /etc/sudoers.d/vulcain
```
Fonction utilitaire pour la suite (à redéfinir si tu ouvres un nouveau shell) :
```bash
as_agent() { local n=$1; shift; local h=/var/lib/agents/$n
  sudo runuser -u "$n" -- env HOME="$h" HERMES_HOME="$h/.hermes" HERMES_LAZY_INSTALL_TARGET="$h/lazy-packages" \
    PATH="$h/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"; }
```
Vérification : `sudo -u vulcain sudo -n true && echo ok`.

## Étape 5 : l'identité de Vulcain
`SOUL.md` :
```bash
sudo -u vulcain tee /var/lib/agents/vulcain/.hermes/SOUL.md >/dev/null <<'EOF'
# Vulcain

## Personality
Calm, precise, dry. Short answers, facts first.

## Mission
Run this server's Hermes agents: create, configure, update, restart and remove them, and improve yourself, on the operator's request. Follow the `agents` skill for every agent operation.

## Rules
- You have full root through `sudo`. Use it only for agent operations; never touch SSH, the firewall, or services that are not agents, unless the operator explicitly asks.
- Never ask for a secret in chat, never read or print any `.env`, `auth.json` or key file. Secrets are typed by the operator with `sudo agent-secret <agent> <KEY>` in their own terminal.
- Before creating, deleting, or changing an agent's model or permissions, restate the change and wait for an explicit yes.
- Speak the operator's language.
- Report failures as they are; read the logs before guessing.
EOF
sudo chmod 644 /var/lib/agents/vulcain/.hermes/SOUL.md
```
Son skill `agents` : écris `/var/lib/agents/vulcain/.hermes/skills/agents/SKILL.md` (propriétaire vulcain, 644) avec exactement ce contenu :
````markdown
---
name: agents
description: Create, configure, update, restart and remove the Hermes agents of this server, including yourself (Vulcain). Use for any request about agents, their Discord bots, models, personalities or memory.
---

# Managing Hermes agents

Layout: each agent `<n>` is Linux user `<n>`, home `/var/lib/agents/<n>` (700), `HERMES_HOME=/var/lib/agents/<n>/.hermes`, systemd unit `agent-<n>.service` + sandbox `agent-<n>.service.d/isolate.conf`. Hermes is shared read-only in `/usr/local/lib/hermes-agent`. You are `vulcain` (same layout, no sandbox, full sudo).

Run Hermes as an agent:
`sudo runuser -u <n> -- env HOME=/var/lib/agents/<n> HERMES_HOME=/var/lib/agents/<n>/.hermes HERMES_LAZY_INSTALL_TARGET=/var/lib/agents/<n>/lazy-packages PATH=/var/lib/agents/<n>/.local/bin:/usr/local/bin:/usr/bin:/bin hermes <args>`
(below: `AS <n> hermes <args>`).

## Create agent <n>
Name must match `^[a-z][a-z0-9-]{1,30}$` and not be an existing Linux user. Confirm name + one-sentence mission + model with the operator first.
1. `sudo useradd --system --user-group --home-dir /var/lib/agents/<n> --no-create-home --shell /usr/sbin/nologin <n>`
2. `sudo install -d -m 700 -o <n> -g <n> /var/lib/agents/<n> /var/lib/agents/<n>/.hermes /var/lib/agents/<n>/lazy-packages`
3. Write `/var/lib/agents/<n>/.hermes/SOUL.md` (owner `<n>`, 644): `# <n>`, `## Personality`, `## Mission`, `## Rules`.
4. Model: `AS <n> hermes config set model.provider <p>` and `model.default <m>`. Providers/models: openai-codex/gpt-6-sol, anthropic/claude-sonnet-4-6, xai-oauth/grok-4.6, openrouter/z-ai/glm-5.2, openai-api/gpt-6-sol, xai/grok-4.6, gemini/gemini-3.8-flash, deepseek/deepseek-flash. Subscriptions (openai-codex, anthropic, xai-oauth): tell the operator to run `sudo runuser --pty -u <n> -- env HOME=/var/lib/agents/<n> HERMES_HOME=/var/lib/agents/<n>/.hermes hermes auth add <p>` in their terminal (URL + code, no browser on the server; anthropic = Claude Max + extra-usage credits only). API keys: the operator runs `sudo agent-secret <n> <KEY>` (OPENROUTER_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY, XAI_API_KEY, GEMINI_API_KEY, DEEPSEEK_API_KEY).
5. Discord: walk the operator through the Developer Portal (New Application → Bot → Reset Token; enable Message Content + Server Members intents; keep "Requires OAuth2 Code Grant" off; invite with `https://discord.com/oauth2/authorize?client_id=<APPLICATION_ID>&scope=bot+applications.commands&permissions=309237763136`). Then the operator runs `sudo agent-secret <n>` (token). Then add the non-secret lines yourself, as root, appending: `DISCORD_ALLOWED_USERS=<same ids as yours>` and `DISCORD_REQUIRE_MENTION=true` (use `printf ... | sudo tee -a`, never read the file). One bot per agent; never reuse a token.
6. Unit: copy `/etc/systemd/system/agent-vulcain.service` to `agent-<n>.service` replacing every `vulcain` by `<n>`; create `agent-<n>.service.d/isolate.conf`:
   ```
   [Service]
   ProtectSystem=strict
   ProtectHome=tmpfs
   TemporaryFileSystem=/var/lib/agents:ro
   BindPaths=/var/lib/agents/<n>
   ReadWritePaths=/var/lib/agents/<n>
   ReadOnlyPaths=/usr/local/lib/hermes-agent
   PrivateTmp=yes
   NoNewPrivileges=yes
   ProtectProc=invisible
   ```
   `sudo systemctl daemon-reload && sudo systemctl enable --now agent-<n>`; wait for `✓ discord connected` in `sudo journalctl -u agent-<n> -n 50 -o cat`.
7. Memory (only if `/opt/honcho` exists): `curl -fsS -X POST -H 'Content-Type: application/json' -d '{"id":"<n>"}' http://127.0.0.1:8000/v3/workspaces`; write `.hermes/honcho.json` (owner `<n>`, 600) `{"baseUrl":"http://127.0.0.1:8000","hosts":{"hermes":{"enabled":true,"workspace":"<n>","aiPeer":"<n>","peerName":"<operator name>"}}}`; `AS <n> hermes config set memory.provider honcho`; restart.

## Modify agent <n>
- Personality/mission: edit its `SOUL.md`, then restart.
- Model: `config set` as above (+ login or `agent-secret`), then restart.
- Any Hermes setting: `AS <n> hermes config set <key> <value>`; read `/var/lib/agents/<n>/.hermes/config.yaml` with sudo (never print `.env` or `auth.json`).
- Skills: put `SKILL.md` folders in `/var/lib/agents/<n>/.hermes/skills/<skill>/` owned by `<n>`.
- Apply: `sudo systemctl restart agent-<n>`.

## Modify yourself (vulcain)
Same as above on `vulcain`. To restart yourself without cutting your own reply: `sudo systemd-run --on-active=5 systemctl restart agent-vulcain`. Never remove your own sudo rule or unit.

## Inspect
`systemctl list-units 'agent-*'`, `sudo systemctl status agent-<n>`, `sudo journalctl -u agent-<n> -n 80 -o cat` (do not echo token-looking strings back).

## Remove agent <n> (never vulcain; confirm first)
`sudo systemctl disable --now agent-<n>; sudo rm -rf /etc/systemd/system/agent-<n>.service /etc/systemd/system/agent-<n>.service.d; sudo systemctl daemon-reload; sudo userdel <n>; sudo rm -rf /var/lib/agents/<n>`
````

## Étape 6 : le modèle de Vulcain
Selon mon choix :
- Abonnement (`openai-codex`, `anthropic`, `xai-oauth`) : donne-moi la commande `sudo runuser --pty -u vulcain -- env HOME=/var/lib/agents/vulcain HERMES_HOME=/var/lib/agents/vulcain/.hermes hermes auth add <provider>` à lancer moi-même ; attends « fait ».
- Clé API : donne-moi `sudo agent-secret vulcain <CLÉ>` ; attends « fait ».
Puis : `as_agent vulcain hermes config set model.provider <provider>` et `as_agent vulcain hermes config set model.default <modèle>` (modèles par défaut : voir le skill).

Vérification : `sudo vulcain -q "Réponds juste: ok" --oneshot` (ou `-Q`) affiche une réponse.

## Étape 7 : Vulcain sur Discord
1. Guide-moi pour créer son bot (étape 5 du skill : portail, intents, invitation). Je te donne l'Application ID (ce n'est pas un secret) : construis le lien d'invitation.
2. Je lance `sudo agent-secret vulcain` (token).
3. Ajoute toi-même au `.env` de Vulcain, sans le lire : `printf 'DISCORD_ALLOWED_USERS=%s\nDISCORD_REQUIRE_MENTION=true\n' '<mes ids>' | sudo tee -a /var/lib/agents/vulcain/.hermes/.env >/dev/null`.
4. Son service (pas de prison : il doit pouvoir administrer) :
```bash
sudo tee /etc/systemd/system/agent-vulcain.service >/dev/null <<'EOF'
[Unit]
Description=Hermes agent vulcain
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=vulcain
Group=vulcain
Environment=HOME=/var/lib/agents/vulcain
Environment=HERMES_HOME=/var/lib/agents/vulcain/.hermes
Environment=HERMES_LAZY_INSTALL_TARGET=/var/lib/agents/vulcain/lazy-packages
Environment=HERMES_ACCEPT_HOOKS=1
Environment=PATH=/var/lib/agents/vulcain/.local/bin:/usr/local/bin:/usr/bin:/bin
WorkingDirectory=/var/lib/agents/vulcain
ExecStart=/usr/local/bin/hermes gateway run --external-supervisor
ExecReload=/bin/kill -USR1 $MAINPID
Restart=always
RestartSec=5
RestartForceExitStatus=75
RestartPreventExitStatus=78
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now agent-vulcain
```
Vérification : `sudo journalctl -u agent-vulcain -n 50 -o cat | grep -E 'discord connected|Improper token|error'` montre `✓ discord connected`. Si `Improper token` : je dois relancer `sudo agent-secret vulcain` avec le token de l'onglet Bot.

## Étape 8 (seulement si je le demande) : mémoire Honcho
Il faut une clé OpenRouter. Docker depuis le dépôt officiel :
```bash
. /etc/os-release
sudo install -m 755 -d /etc/apt/keyrings
sudo curl -fsSL -o /etc/apt/keyrings/docker.asc "https://download.docker.com/linux/$ID/gpg" && sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo install -d -m 700 /opt/honcho
echo 'CREATE EXTENSION IF NOT EXISTS vector;' | sudo tee /opt/honcho/init.sql >/dev/null
```
`/opt/honcho/docker-compose.yml` : services `api` (image `ghcr.io/plastic-labs/honcho:v3.2.2`, entrypoint `["sh","docker/entrypoint.sh"]`, ports `127.0.0.1:8000:8000` UNIQUEMENT, env `DB_CONNECTION_URI=postgresql+psycopg://postgres:${POSTGRES_PASSWORD:?}@database:5432/postgres`, `CACHE_URL=redis://redis:6379/0?suppress=true`, `CACHE_ENABLED=true`, `env_file: .env`, healthcheck `/app/.venv/bin/python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=2).read()"`), `deriver` (même image, entrypoint `["/app/.venv/bin/python","-m","src.deriver"]`, même environment et env_file, dépend de api healthy), `database` (`pgvector/pgvector:pg15`, `command: ["postgres","-c","max_connections=200"]`, `POSTGRES_PASSWORD=${POSTGRES_PASSWORD:?}`, `PGDATA=/var/lib/postgresql/data/pgdata`, volumes `./init.sql:/docker-entrypoint-initdb.d/init.sql:ro` et `pgdata`, healthcheck `pg_isready -U postgres -d postgres`), `redis` (`redis:8.2`, volume `redis-data`, healthcheck `redis-cli ping`). `restart: unless-stopped` partout, AUCUN port publié pour database et redis.
Le `.env` (600, root) contient la clé : je le crée moi-même. Donne-moi ce bloc à lancer :
```bash
read -rsp "Clé OpenRouter : " K; echo; PW=$(od -An -tx1 -N24 /dev/urandom | tr -d ' \n'); M=openai/gpt-5.4-mini
{ printf 'POSTGRES_PASSWORD=%s\nAUTH_USE_AUTH=false\nLLM_OPENAI_API_KEY=%s\nLLM_OPENAI_BASE_URL=https://openrouter.ai/api/v1\n' "$PW" "$K"
  for v in DERIVER SUMMARY DREAM_DEDUCTION DREAM_INDUCTION; do printf '%s_MODEL_CONFIG__MODEL=%s\n' $v "$M"; done
  for l in minimal low medium high max; do printf 'DIALECTIC_LEVELS__%s__MODEL_CONFIG__MODEL=%s\n' $l "$M"; done
  printf 'EMBEDDING_MODEL_CONFIG__MODEL=openai/text-embedding-3-small\nEMBEDDING_MODEL_CONFIG__TRANSPORT=openai\nEMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL=https://openrouter.ai/api/v1\n'
} | sudo install -m 600 -o root -g root /dev/stdin /opt/honcho/.env; unset K PW
```
Puis `sudo docker compose -f /opt/honcho/docker-compose.yml up -d`, attends `curl -fsS http://127.0.0.1:8000/health` = `{"status":"ok"}`, et branche chaque agent existant (étape 7 du skill), Vulcain compris.

## Étape 9 : vérifications finales
- `systemctl is-active agent-vulcain` = active ; sur Discord, `@Vulcain ping` répond.
- `sudo vulcain` ouvre le chat dans le terminal.
- `sudo ss -tlnp` : rien de nouveau n'écoute hors 127.0.0.1.
- `stat -c '%U %a %n' /var/lib/agents/*/ /var/lib/agents/*/.hermes/.env` : 700 et 600, bons propriétaires.
- Fais-moi un récapitulatif : ce qui est installé, où, et les commandes utiles (`sudo vulcain`, `sudo agent-secret <agent> [CLÉ]`, `sudo journalctl -u agent-<n>`).

Commence par me poser les 3 questions du début, puis annonce ton plan en 5 lignes et attends mon « go ».
