# Vulcain : ce qui est installé, étape par étape

Ce guide explique ce que fait le prompt [PROMPT.md](PROMPT.md) une fois donné à Claude Code sur un VPS. Il couvre ce qui est installé, où, et pourquoi.

## L'idée

- **Hermes Agent** (Nous Research) est un agent IA qui tourne en continu. On lui parle sur Discord, ou dans le terminal.
- **Vulcain** est un agent Hermes particulier : l'**administrateur**. Il a tous les droits sur le serveur (`sudo`). Il crée, configure, met à jour, redémarre et supprime les autres agents, et peut se modifier lui-même.
- **Les autres agents** sont enfermés : chacun ne voit que ses propres fichiers.
- **Toi**, tu gardes la main sur une chose : les **secrets** (tokens Discord, clés API). Tu les tapes toi-même, en saisie masquée, et aucun modèle ne les voit.

```
/usr/local/lib/hermes-agent          Hermes, installé une fois, figé sur une version, en lecture seule
/usr/local/bin/hermes, uv            les commandes, utilisables par tous les agents
/usr/local/sbin/agent-secret         TON outil pour saisir un secret en masqué
/usr/local/bin/vulcain               ouvre le chat avec Vulcain dans le terminal

/var/lib/agents/vulcain/             home de Vulcain (700) ; .hermes/ = sa config, son .env, son SOUL.md, son skill « agents »
/etc/sudoers.d/vulcain               Vulcain a sudo sans mot de passe
/etc/systemd/system/agent-vulcain.service       Vulcain sur Discord, sans prison

/var/lib/agents/<agent>/             home privé de chaque autre agent (700)
/etc/systemd/system/agent-<agent>.service       son bot Discord
/etc/systemd/system/agent-<agent>.service.d/isolate.conf   sa prison

/opt/honcho/                         (optionnel) la mémoire partagée, sur 127.0.0.1:8000 uniquement
```

## Les étapes du prompt

### Avant de commencer : 3 questions
Claude te demande trois choses, dont aucune n'est un secret :
- **ton identifiant Discord**, pour la liste blanche : les agents n'obéissent qu'à toi ;
- **le modèle de Vulcain** ;
- **ton prénom**, utilisé par la mémoire.

### 1. Prérequis
Claude vérifie le système (Debian 12 ou 13, ou Ubuntu 24.04) et installe quelques outils de base (`git`, `curl`…). Il crée aussi `/var/lib/agents`, le dossier qui contiendra tous les agents.

### 2. Hermes, une seule fois pour tout le monde
- **Version figée.** Hermes est installé à un commit précis, toujours le même, ce qui rend le comportement reproductible. Claude vérifie d'abord que le tag pointe toujours sur ce commit.
- **Installé une seule fois.** Lancé en root sans `--dir`, l'installeur met tout dans `/usr/local/lib/hermes-agent`. Hermes pèse environ 1,8 Go, donc une copie par agent serait du gaspillage.
- **`--skip-setup` est indispensable.** Sans lui, l'assistant de configuration d'Hermes s'ouvre et bloque l'installation.
- **Dépendances pré-installées.** Les bibliothèques Discord et mémoire sont installées d'avance. Hermes les installe normalement « à la demande », ce qui échouerait pour un agent non-root.
- **Lecture seule.** L'installation appartient à root : aucun agent ne peut la modifier.

### 3. Deux outils
- **`agent-secret <agent> [CLÉ]`** te demande un secret en saisie masquée et l'écrit dans le `.env` de l'agent (droits 600, propriétaire l'agent). Le secret n'apparaît ni à l'écran, ni dans l'historique, ni dans `ps`. Si tu colles autre chose qu'un token de bot Discord (par exemple le Client Secret), il refuse.
- **`vulcain`** ouvre le chat avec Vulcain dans le terminal.

### 4. Vulcain, l'administrateur
- **Son utilisateur Linux.** Vulcain a son propre utilisateur, `vulcain`, avec un home privé.
- **`sudo` sans mot de passe.** Avec cette règle, Vulcain peut tout faire sur le serveur. C'est voulu : il doit pouvoir créer des utilisateurs, des services et des agents.
- **Le garde-fou.** Hermes demande ton approbation pour les commandes jugées dangereuses (`/approve` sur Discord, ou une fenêtre de confirmation dans le terminal), et le `SOUL.md` de Vulcain l'oblige à te faire confirmer avant de créer, supprimer ou changer un agent.

### 5. L'identité de Vulcain
- **`SOUL.md`** définit sa personnalité, sa mission et ses règles : ne jamais demander ni lire un secret, faire confirmer avant d'agir, ne pas toucher à SSH ni au pare-feu.
- **Son skill `agents`** est sa procédure écrite. Il y trouve comment :
  - **créer un agent** : utilisateur, home, `SOUL.md`, modèle, bot Discord, service et prison ;
  - **modifier un agent** : personnalité, modèle, réglages, skills ;
  - **se modifier lui-même**, y compris se redémarrer sans couper sa propre réponse (`systemd-run --on-active=5`) ;
  - **supprimer un agent**, jamais lui-même ;
  - **brancher la mémoire.**

### 6. Le modèle de Vulcain
- **Avec un abonnement** (ChatGPT/Codex, Claude Max avec crédits, SuperGrok) : tu lances `hermes auth add …` en tant que Vulcain. La commande affiche une URL et un code, que tu ouvres sur ton ordinateur. Il n'y a pas besoin de navigateur sur le serveur.
- **Avec une clé API :** tu lances `sudo agent-secret vulcain <CLÉ>`.

### 7. Vulcain sur Discord
Tu crées son bot dans le portail Discord :
1. Clique sur New Application, puis va dans l'onglet Bot et clique sur **Reset Token** pour obtenir le token.
2. Active **Message Content** et **Server Members**.
3. Invite le bot sur ton serveur avec un lien qui contient l'Application ID.
4. Saisis le token avec `sudo agent-secret vulcain`.

Claude ajoute ensuite ta liste blanche et démarre le service. Vulcain tourne **sans prison**, puisqu'il doit administrer le serveur. Il ne répond que quand on le mentionne, et seulement à toi.

### 8. La mémoire Honcho, si tu la veux
Honcho mémorise les conversations de chaque agent dans son propre espace. Il a besoin d'une clé OpenRouter, qui sert à résumer et à indexer.
- **Installation :** Honcho tourne dans Docker (installé depuis le dépôt officiel), avec Postgres et Redis.
- **Exposition :** seule son API est publiée, et seulement sur `127.0.0.1`. Postgres a un vrai mot de passe aléatoire.
- **Secret :** son `.env` contient la clé, donc c'est toi qui le crées avec le bloc `read -rsp` que Claude te donne.

⚠️ **Limite :** Honcho tourne sans authentification sur `127.0.0.1`. Les fichiers des agents sont isolés, mais un agent pourrait interroger la mémoire d'un autre via l'API.

### 9. Vérifications
- Vulcain tourne et te répond sur Discord.
- `sudo vulcain` ouvre le chat.
- Rien de nouveau n'écoute vers l'extérieur.
- Les droits des fichiers sont les bons : 700 pour les homes, 600 pour les `.env`.

## La prison des autres agents

Chaque agent créé par Vulcain reçoit `agent-<nom>.service.d/isolate.conf` :

| Réglage | Effet |
|---|---|
| `ProtectSystem=strict` | tout le système en lecture seule |
| `ProtectHome=tmpfs` + `TemporaryFileSystem=/var/lib/agents:ro` | les autres agents sont invisibles |
| `BindPaths` / `ReadWritePaths` = son home | il ne voit et n'écrit que chez lui |
| `ReadOnlyPaths=/usr/local/lib/hermes-agent` | il ne peut pas modifier Hermes |
| `PrivateTmp`, `NoNewPrivileges`, `ProtectProc=invisible` | un `/tmp` à lui, aucun `sudo` possible, il ne voit pas les processus des autres utilisateurs |

En plus de la prison, chaque agent est un utilisateur Linux distinct : c'est le noyau lui-même qui l'empêche de lire les fichiers des autres.

## Au quotidien

| Je veux… | Je fais… |
|---|---|
| parler à Vulcain | `@Vulcain …` sur Discord, ou `sudo vulcain` dans le terminal |
| créer un agent | je le demande à Vulcain ; il me guide pour le bot et me donne la commande `agent-secret` |
| saisir un token ou une clé | `sudo agent-secret <agent> [CLÉ]`, puis `sudo systemctl restart agent-<agent>` |
| voir les logs | `sudo journalctl -u agent-<agent> -n 100 -o cat` |
| connecter un abonnement | `sudo runuser --pty -u <agent> -- env HOME=/var/lib/agents/<agent> HERMES_HOME=/var/lib/agents/<agent>/.hermes hermes auth add <provider>` |

## Problèmes connus

| Symptôme | Cause | Remède |
|---|---|---|
| L'écran « How would you like to set up Hermes? » s'affiche | il manque `--skip-setup` | relancer l'installeur avec `--skip-setup` |
| `Improper token has been passed` | le Client Secret a été collé à la place du token | onglet Bot, puis Reset Token, puis `agent-secret` |
| `HTTP 401: User not found` | clé OpenRouter invalide | nouvelle clé, puis `agent-secret <agent> OPENROUTER_API_KEY` |
| « Application inconnue » à l'invitation | Application ID absent ou erroné dans le lien | copier l'Application ID depuis General Information |
| Un agent ne répond à personne | `DISCORD_ALLOWED_USERS` vide | ajouter ton identifiant Discord |
| Un agent n'arrive pas à utiliser `sudo` | `NoNewPrivileges` (voulu) | seul Vulcain a `sudo` |
