# Setup manuel d'une ferme Hermes (sans la CLI usine-hermes)

Ce document décrit, étape par étape, tout ce que `usine-hermes` met en place sur le VPS, pour le refaire à la main ou le faire faire par Claude Code sur le serveur (voir [prompt-claude-vps.md](prompt-claude-vps.md)).

Testé sur : Debian 13 (OVH VPS-1). Valable aussi sur Debian 12 et Ubuntu 24.04.

## 0. Ce qu'on obtient

```
/usr/local/lib/hermes-agent        Hermes, installé UNE fois, figé sur un commit, propriété de root, lecture seule
/usr/local/bin/hermes              le lanceur Hermes, utilisé par tous les profils
/usr/local/bin/uv                  uv (gestionnaire Python), pour les installs à la demande des profils

/var/lib/usine-hermes/<nom>/       le home privé d'un agent (mode 700, propriétaire <nom>)
  .hermes/                         son HERMES_HOME : config.yaml, .env (secrets, 600), SOUL.md, auth.json, mémoire locale…
  lazy-packages/                   ses dépendances installées à la demande

/etc/systemd/system/usine-<nom>.service          la gateway Discord de l'agent
/etc/systemd/system/usine-<nom>.service.d/isolate.conf   sa prison (il ne voit que son home)

/opt/usine-hermes/honcho/          (optionnel) la mémoire Honcho en docker compose, sur 127.0.0.1:8000 uniquement
```

Principes :
- **Un agent = un utilisateur Linux.** C'est le noyau qui empêche un agent de lire les fichiers d'un autre, et la prison systemd s'ajoute par-dessus.
- **Une seule installation de Hermes** (environ 1,8 Go), partagée en lecture seule. Les profils n'écrivent jamais dedans.
- **Chaque agent a son propre bot Discord** et ses propres identifiants de modèle (clé API ou connexion à un abonnement).
- **Les secrets** (tokens, clés) sont tapés par l'humain en saisie masquée et écrits en `600`. Ils ne passent jamais en argument de commande, ne s'affichent jamais et ne vont jamais dans une conversation avec un modèle.

Versions figées (vérifiées le 2026-10-06) :
- Hermes `v2026.9.24` = commit `f97608f178d1ffeca59860195ab7da295f7c8e5f` (0.21.5)
- Honcho `v3.2.2` (image `ghcr.io/plastic-labs/honcho:v3.2.2`)

## 1. Accès et autorisations

- Connexion : `ssh ovh` (utilisateur `debian`, clé `id_ed25519_2026`).
- `debian` a `sudo` **sans mot de passe** (règle cloud-init OVH). Toutes les commandes ci-dessous se lancent avec `sudo`.
- Pour Claude Code sur le VPS (installation, connexion, permissions), voir [prompt-claude-vps.md](prompt-claude-vps.md).

## 2. Prérequis système

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl tar coreutils ca-certificates
```

## 3. Hermes, installé une fois pour tous

```bash
SHA=f97608f178d1ffeca59860195ab7da295f7c8e5f
# Le script d'install est téléchargé par COMMIT, pas par tag (un tag peut bouger).
curl -fsSL -o /tmp/hermes-install.sh \
  "https://raw.githubusercontent.com/NousResearch/hermes-agent/$SHA/scripts/install.sh"
sudo bash /tmp/hermes-install.sh --commit "$SHA" \
  --non-interactive --skip-setup --skip-browser --skip-computer-use \
  --hermes-home /root/.hermes
rm -f /tmp/hermes-install.sh
```

Pourquoi ces options :
- **Pas de `--dir`.** Lancé en root sans `--dir`, l'installeur range le code dans `/usr/local/lib/hermes-agent` et le lanceur dans `/usr/local/bin/hermes`, utilisables par tous. Avec `--dir`, le lanceur atterrit dans `/root/.local/bin`, invisible pour les profils.
- **`--skip-setup` est indispensable.** `--non-interactive` ne suffit pas : sans `--skip-setup`, l'assistant « How would you like to set up Hermes? » s'ouvre dès qu'il y a un terminal et crée un profil root inutile.

Pré-installer les dépendances Discord et Honcho dans l'environnement Python partagé. Upstream les installe « à la demande », dans le venv, ce qui échouerait pour un profil non-root :

```bash
UV=$(sudo sh -c 'ls /root/.hermes/bin/uv /root/.local/bin/uv 2>/dev/null' | head -1)   # emplacement de uv après l'install
sudo env UV_PROJECT_ENVIRONMENT=/usr/local/lib/hermes-agent/venv \
  UV_PYTHON=/usr/local/lib/hermes-agent/venv/bin/python \
  "$UV" sync --extra all --extra messaging --extra honcho --locked \
  --project /usr/local/lib/hermes-agent
sudo chown -R root:root /usr/local/lib/hermes-agent
sudo chmod -R go-w /usr/local/lib/hermes-agent
sudo install -m 755 "$UV" /usr/local/bin/uv          # les profils n'ont pas accès à /root
```

Vérification :
```bash
git -C /usr/local/lib/hermes-agent rev-parse HEAD     # doit afficher f97608f…
sudo -u nobody /usr/local/bin/hermes --version         # utilisable par un non-root
```

## 4. Créer un agent

Variables utilisées dans toute la section (exemple : un agent `alice`) :
```bash
N=alice
H=/var/lib/usine-hermes/$N
```
Le nom doit être en minuscules et respecter `^[a-z][a-z0-9-]{1,30}$`. Il ne doit pas correspondre à un utilisateur Linux existant.

### 4.1 Utilisateur et home privé
```bash
sudo install -d -m 755 /var/lib/usine-hermes
sudo useradd --system --user-group --home-dir "$H" --no-create-home --shell /usr/sbin/nologin "$N"
sudo install -d -m 700 -o "$N" -g "$N" "$H" "$H/.hermes" "$H/lazy-packages"
```

Raccourci pour lancer Hermes en tant qu'agent (à redéfinir dans chaque nouveau shell) :
```bash
as_n() { sudo runuser -u "$N" -- env HOME="$H" HERMES_HOME="$H/.hermes" \
  HERMES_LAZY_INSTALL_TARGET="$H/lazy-packages" PATH="$H/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"; }
```

### 4.2 Personnalité et mission (`SOUL.md`)
```bash
sudo -u "$N" tee "$H/.hermes/SOUL.md" >/dev/null <<'EOF'
# alice

## Personality
helpful, concise and friendly

## Mission
Gérer mon agenda et mes mails.
EOF
sudo chmod 644 "$H/.hermes/SOUL.md"
```

### 4.3 Le modèle, au choix
**Abonnement ChatGPT (Codex)**, sans clé API :
```bash
as_n hermes auth add openai-codex        # affiche une URL et un code : ouvre l'URL sur ton Mac et saisis le code (15 min)
as_n hermes config set model.provider openai-codex
as_n hermes config set model.default gpt-6-sol
```
**Abonnement Claude** (seulement Max avec crédits d'usage supplémentaires ; Pro ne marche pas) :
```bash
as_n hermes auth add anthropic           # lien à ouvrir, puis coller le code "code#state"
as_n hermes config set model.provider anthropic
as_n hermes config set model.default claude-sonnet-4-6
```
**SuperGrok** : `auth add xai-oauth`, provider `xai-oauth`, modèle `grok-4.6`.

**Clé API** (OpenRouter, Anthropic, OpenAI, xAI, Gemini, DeepSeek) : la clé va dans le `.env` (étape 4.4), puis :
```bash
as_n hermes config set model.provider openrouter     # ou anthropic, openai-api, xai, gemini, deepseek
as_n hermes config set model.default z-ai/glm-5.2    # ou claude-sonnet-4-6, gpt-6-sol, grok-4.6, gemini-3.8-flash, deepseek-flash
```
Il faut toujours régler `model.provider` explicitement : une `OPENAI_API_KEY` seule est interprétée comme OpenRouter.

### 4.4 Le `.env` (secrets) — à taper par l'humain, jamais par Claude
Le bot Discord se crée à l'étape 5. Ensuite, **toi** (pas Claude) tu tapes les secrets en saisie masquée :
```bash
N=alice; H=/var/lib/usine-hermes/$N
read -rsp "Token du bot Discord : " T; echo
read -rp  "Ton ID Discord (allowlist, plusieurs = virgules) : " IDS
printf 'DISCORD_BOT_TOKEN=%s\nDISCORD_ALLOWED_USERS=%s\nDISCORD_REQUIRE_MENTION=true\n' "$T" "$IDS" \
  | sudo install -m 600 -o "$N" -g "$N" /dev/stdin "$H/.hermes/.env"
unset T
```
Avec une clé API, ajoute-la au même fichier :
```bash
read -rsp "Clé OPENROUTER_API_KEY : " K; echo
printf 'OPENROUTER_API_KEY=%s\n' "$K" | sudo tee -a "$H/.hermes/.env" >/dev/null; unset K
```
Explications :
- **`printf` est intégré au shell** : le secret n'apparaît jamais dans `ps` ni dans l'historique.
- **`DISCORD_ALLOWED_USERS`** : sans lui, l'agent n'obéit à personne. Avec lui, il n'obéit qu'à toi.
- **Un vrai token de bot fait environ 70 caractères, en 3 parties séparées par des points.** Si tu colles 32 à 36 caractères sans point, c'est le Client Secret : Discord répondra `Improper token has been passed`.

### 4.5 Le service systemd et sa prison
```bash
sudo tee /etc/systemd/system/usine-$N.service >/dev/null <<EOF
[Unit]
Description=Hermes Agent gateway for profile $N
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$N
Group=$N
Environment=HOME=$H
Environment=HERMES_HOME=$H/.hermes
Environment=HERMES_LAZY_INSTALL_TARGET=$H/lazy-packages
Environment=HERMES_ACCEPT_HOOKS=1
Environment=PATH=$H/.local/bin:/usr/local/bin:/usr/bin:/bin
WorkingDirectory=$H
ExecStart=/usr/local/bin/hermes gateway run --external-supervisor
ExecReload=/bin/kill -USR1 \$MAINPID
Restart=always
RestartSec=5
RestartForceExitStatus=75
RestartPreventExitStatus=78
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

sudo install -d -m 755 /etc/systemd/system/usine-$N.service.d
sudo tee /etc/systemd/system/usine-$N.service.d/isolate.conf >/dev/null <<EOF
[Service]
ProtectSystem=strict
ProtectHome=tmpfs
TemporaryFileSystem=/var/lib/usine-hermes:ro
BindPaths=$H
ReadWritePaths=$H
ReadOnlyPaths=/usr/local/lib/hermes-agent
PrivateTmp=yes
NoNewPrivileges=yes
ProtectProc=invisible
EOF
sudo systemctl daemon-reload
```
Ce que fait la prison :
- **Système en lecture seule.** `ProtectSystem=strict` rend tout le système non modifiable, sauf le home de l'agent.
- **Les autres agents sont invisibles.** `TemporaryFileSystem=/var/lib/usine-hermes:ro` masque tout le dossier des agents, puis `BindPaths` ne remet que celui de l'agent. `ProtectHome` seul ne suffirait pas, puisque les homes sont sous `/var/lib`.
- **Pas de gain de droits ni de fuite.** `NoNewPrivileges` empêche toute élévation de droits (`sudo` impossible), et `ProtectProc=invisible` cache les processus des autres utilisateurs.
- **Codes de sortie d'upstream :** 75 signifie « redémarre-moi », 78 signifie « config refusée, ne boucle pas ».

### 4.6 Démarrer et vérifier
```bash
sudo systemctl enable --now usine-$N
sudo journalctl -u usine-$N -f        # attendre : ✓ discord connected
```
Sur Discord : `@alice bonjour`. Elle répond à toi seul, et seulement quand on la mentionne.

## 5. Créer le bot Discord d'un agent

1. Sur <https://discord.com/developers/applications>, clique sur **New Application** et donne-lui le nom de l'agent.
2. Dans l'onglet **Bot** :
   - **Reset Token**, puis **Copy** : c'est le token pour l'étape 4.4 ;
   - **Privileged Gateway Intents** : active **Message Content** et **Server Members**, puis **Save** ;
   - **Requires OAuth2 Code Grant** doit rester **désactivé**.
3. Dans l'onglet **General Information**, copie l'**Application ID**.
4. Invite le bot en ouvrant
   `https://discord.com/oauth2/authorize?client_id=<APPLICATION_ID>&scope=bot+applications.commands&permissions=309237763136`
   puis choisis ton serveur et **Autoriser**.
5. Un bot = un agent. Ne réutilise jamais un token : deux gateways sur le même token se bloquent.

Ton ID Discord : `597080805101273128`. Pour le retrouver : Paramètres, Avancés, Mode développeur, puis clic droit sur ton pseudo dans un message et **Copier l'identifiant**.

## 6. Mémoire Honcho (optionnel)

Il faut une clé OpenRouter (<https://openrouter.ai/keys>) : Honcho s'en sert pour résumer et indexer les conversations.

### 6.1 Docker (dépôt officiel)
```bash
. /etc/os-release
sudo install -m 755 -d /etc/apt/keyrings
sudo curl -fsSL -o /etc/apt/keyrings/docker.asc "https://download.docker.com/linux/$ID/gpg"
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
```

### 6.2 Le stack Honcho
```bash
sudo install -d -m 700 /opt/usine-hermes/honcho
sudo curl -fsSL -o /opt/usine-hermes/honcho/docker-compose.yml \
  https://raw.githubusercontent.com/Nardjo/usine-hermes/main/templates/honcho-compose.yml
echo 'CREATE EXTENSION IF NOT EXISTS vector;' | sudo tee /opt/usine-hermes/honcho/init.sql >/dev/null
```
Le `.env` de Honcho est à taper **par toi** (il contient la clé) :
```bash
read -rsp "Clé OpenRouter pour Honcho : " K; echo
PW=$(od -An -tx1 -N24 /dev/urandom | tr -d ' \n'); M=openai/gpt-5.4-mini
{ printf 'POSTGRES_PASSWORD=%s\nAUTH_USE_AUTH=false\n' "$PW"
  printf 'LLM_OPENAI_API_KEY=%s\nLLM_OPENAI_BASE_URL=https://openrouter.ai/api/v1\n' "$K"
  for v in DERIVER SUMMARY DREAM_DEDUCTION DREAM_INDUCTION; do printf '%s_MODEL_CONFIG__MODEL=%s\n' $v "$M"; done
  for l in minimal low medium high max; do printf 'DIALECTIC_LEVELS__%s__MODEL_CONFIG__MODEL=%s\n' $l "$M"; done
  printf 'EMBEDDING_MODEL_CONFIG__MODEL=openai/text-embedding-3-small\nEMBEDDING_MODEL_CONFIG__TRANSPORT=openai\n'
  printf 'EMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL=https://openrouter.ai/api/v1\n'
} | sudo install -m 600 -o root -g root /dev/stdin /opt/usine-hermes/honcho/.env
unset K PW
sudo docker compose -f /opt/usine-hermes/honcho/docker-compose.yml up -d
curl -fsS http://127.0.0.1:8000/health      # {"status":"ok"} après environ 30 s
```
Le compose est le modèle upstream, avec trois changements :
- l'image publiée et figée remplace le build ;
- le service MCP est retiré ;
- **seule l'API est publiée, et seulement sur 127.0.0.1**, avec un vrai mot de passe Postgres.

### 6.3 Brancher un agent sur la mémoire
```bash
N=alice; H=/var/lib/usine-hermes/$N
curl -fsS -X POST -H 'Content-Type: application/json' -d "{\"id\":\"$N\"}" http://127.0.0.1:8000/v3/workspaces
sudo -u "$N" tee "$H/.hermes/honcho.json" >/dev/null <<EOF
{ "baseUrl": "http://127.0.0.1:8000",
  "hosts": { "hermes": { "enabled": true, "workspace": "$N", "aiPeer": "$N", "peerName": "jordan" } } }
EOF
sudo chmod 600 "$H/.hermes/honcho.json"
as_n hermes config set memory.provider honcho     # as_n : défini en 4.1
sudo systemctl restart usine-$N
```
Chaque agent a son workspace, et la création d'un workspace peut être relancée sans risque.

⚠️ **Limite :** Honcho tourne sans authentification sur 127.0.0.1. Les fichiers des agents sont isolés, mais n'importe quel agent peut interroger la mémoire d'un autre via l'API.

## 7. Vulcain (l'agent opérateur)

Dans la CLI, Vulcain est un agent normal, avec un droit en plus : une règle sudo vers un « pont » root qui revalide chaque commande (créer, lister, relancer des agents). Ce pont fait partie de la CLI `usine-hermes`.

**Dans le setup manuel, on n'en a pas besoin : Claude Code sur le VPS joue ce rôle.** Si tu veux quand même un Vulcain sur Discord, crée-le comme n'importe quel agent (section 4) avec la mission « m'aider à gérer la ferme », **sans lui donner sudo**.

## 8. Opérations courantes

```bash
sudo systemctl status usine-alice            # état
sudo journalctl -u usine-alice -n 100        # logs (attention : peuvent contenir des données sensibles)
sudo systemctl restart usine-alice           # après un changement de .env ou de config
sudo systemctl disable --now usine-alice     # arrêter
```
Supprimer un agent :
```bash
N=alice
sudo systemctl disable --now usine-$N
sudo rm -rf /etc/systemd/system/usine-$N.service /etc/systemd/system/usine-$N.service.d
sudo systemctl daemon-reload
sudo userdel "$N"; sudo rm -rf /var/lib/usine-hermes/$N
```

## 9. Vérifier l'isolation

Avec deux agents `alice` et `bob` :
```bash
sudo -u alice test -r /var/lib/usine-hermes/alice/.hermes/.env && echo "alice lit son .env : OK"
sudo -u alice test -r /var/lib/usine-hermes/bob/.hermes/.env   && echo "PROBLÈME" || echo "alice ne lit pas bob : OK"
sudo ss -tlnp            # Honcho : seulement 127.0.0.1:8000 ; pas de 5432 ni 6379
stat -c '%U %a %n' /var/lib/usine-hermes/*/ /var/lib/usine-hermes/*/.hermes/.env   # 700 et 600
```

## 10. Pièges rencontrés pendant la mise au point

| Symptôme | Cause | Remède |
|---|---|---|
| L'écran « How would you like to set up Hermes? » s'affiche | il manque `--skip-setup` à l'installeur | ajouter `--skip-setup` (§3) |
| `Improper token has been passed` | le Client Secret a été collé à la place du token | onglet Bot, puis Reset Token (§5) |
| `HTTP 401: User not found` (OpenRouter) | clé invalide ou révoquée | nouvelle clé sur openrouter.ai, à remettre dans le `.env` |
| « Application inconnue » à l'invitation | `APP_ID` laissé tel quel dans l'URL | mettre l'Application ID |
| Un profil ne trouve pas `hermes` ou `uv` | installé sous `/root` | pas de `--dir` ; `uv` copié dans `/usr/local/bin` (§3) |
| `sudo` refusé dans un agent | `NoNewPrivileges=yes` (voulu) | ne pas donner sudo aux agents |
| Un agent ne répond à personne | `DISCORD_ALLOWED_USERS` vide | mettre ton ID (§4.4) |
