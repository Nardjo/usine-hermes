# Faire monter la ferme par Claude Code, sur le VPS

Le guide complet de référence est [setup-manuel.md](setup-manuel.md). Ce fichier contient trois choses : comment installer Claude Code sur le VPS, quelles autorisations lui donner, et le prompt à lui coller.

## 1. Installer Claude Code sur le VPS

```bash
ssh ovh
curl -fsSL https://claude.ai/install.sh | bash      # installé pour l'utilisateur debian, dans ~/.local/bin
exec bash -l                                          # recharge le PATH
mkdir -p ~/ferme && cd ~/ferme
curl -fsSLO https://raw.githubusercontent.com/Nardjo/usine-hermes/main/docs/setup-manuel.md
claude                                                # 1re fois : choisir la connexion par abonnement, ouvrir l'URL affichée sur ton Mac, coller le code
```

## 2. Les autorisations

Claude tourne sous `debian`, qui a `sudo` sans mot de passe. C'est nécessaire, car tout le setup se fait en root.

En contrepartie, on lui interdit de **lire les secrets**, et on garde une confirmation de ta part pour les commandes destructrices. Crée `~/ferme/.claude/settings.json` :

```bash
mkdir -p ~/ferme/.claude && cat > ~/ferme/.claude/settings.json <<'EOF'
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash(sudo apt-get:*)", "Bash(sudo install:*)", "Bash(sudo useradd:*)", "Bash(sudo runuser:*)",
      "Bash(sudo -u:*)", "Bash(sudo tee:*)", "Bash(sudo chmod:*)", "Bash(sudo chown:*)",
      "Bash(sudo systemctl:*)", "Bash(sudo journalctl:*)", "Bash(sudo docker:*)", "Bash(sudo bash /tmp/hermes-install.sh:*)",
      "Bash(sudo env UV_PROJECT_ENVIRONMENT=:*)", "Bash(sudo ss:*)", "Bash(sudo curl:*)",
      "Bash(curl:*)", "Bash(git:*)", "Bash(stat:*)", "Bash(ls:*)", "Bash(cat:*)", "Bash(od:*)"
    ],
    "ask": [
      "Bash(sudo rm:*)", "Bash(sudo userdel:*)", "Bash(sudo docker compose down:*)", "Bash(sudo apt-get purge:*)"
    ],
    "deny": [
      "Read(/var/lib/usine-hermes/**/.env)", "Read(/var/lib/usine-hermes/**/auth.json)",
      "Read(/opt/usine-hermes/honcho/.env)", "Read(/root/**)",
      "Bash(sudo cat:*)", "Bash(sudo less:*)", "Bash(sudo grep:*)", "Bash(sudo head:*)", "Bash(sudo tail:*)"
    ]
  }
}
EOF
```

Tu peux ajuster cette liste : tout ce qui n'est pas autorisé te sera demandé.

**La règle `deny` est un garde-fou, pas une garantie.** Un `sudo bash -c` pourrait la contourner. La vraie protection reste la consigne du prompt : les secrets, c'est **toi** qui les tapes, dans **ton** terminal SSH, avec les commandes `read -rsp` du guide.

## 3. Le prompt à coller dans `claude`

```text
Tu es sur un VPS Debian 13 (utilisateur debian, sudo sans mot de passe). Ta mission : monter une ferme
d'agents Hermes (Nous Research) en suivant EXACTEMENT ~/ferme/setup-manuel.md, section par section.
Lis d'abord ce fichier en entier.

Ce que je veux à la fin :
1. Hermes installé une fois, figé sur le commit f97608f178d1ffeca59860195ab7da295f7c8e5f (section 3),
   avec --skip-setup, dépendances pré-installées, uv dans /usr/local/bin.
2. Un premier agent "vulcain" (section 4), mission : « m'aider à gérer cette ferme d'agents »,
   modèle : abonnement ChatGPT (openai-codex, gpt-6-sol). Lance `hermes auth add openai-codex` en tant
   qu'agent et laisse-moi saisir le code de connexion moi-même.
3. Son service systemd et sa prison (section 4.5), démarré seulement une fois le .env en place.
4. Ensuite seulement, si je te le demande : la mémoire Honcho (section 6) et d'autres agents.

Règles strictes :
- Les SECRETS (token Discord, clés API, clé OpenRouter de Honcho) : tu ne me les demandes JAMAIS dans
  la conversation et tu ne les lis jamais. Quand une étape en a besoin, tu t'arrêtes, tu me donnes le
  bloc `read -rsp ...` exact du guide à taper moi-même dans un autre terminal SSH, et tu attends que je
  te dise « fait ». Ne fais jamais cat/grep/head sur un .env, auth.json ou /opt/usine-hermes/honcho/.env.
- Avant chaque section : dis-moi en 2 lignes ce que tu vas faire. Après : vérifie (commandes de
  vérification du guide) et montre le résultat.
- Ne passe jamais --dir à l'installeur Hermes. Toujours --skip-setup.
- Ne donne jamais sudo à un agent. N'ouvre aucun port (Honcho seulement sur 127.0.0.1).
- Ne touche pas à beszel-agent ni au groupe docker existant.
- Toute suppression (rm, userdel, docker down, purge) : demande-moi avant.
- Si quelque chose échoue : lis les logs (`sudo journalctl -u usine-<nom> -n 80`), explique la cause,
  propose le correctif, ne contourne pas.
- Réponds en français.

Commence par lire le guide, puis dis-moi ton plan en 5 lignes et attends mon « go ».
```

## 4. Ce que tu feras toi-même pendant la session

- **Le code de connexion ChatGPT :** Claude lance `hermes auth add openai-codex` et te montre l'URL et le code. Tu les saisis sur ton Mac.
- **Le bot Discord :** tu le crées dans le portail (guide, section 5).
- **Les secrets :** dans un second terminal (`ssh ovh`), tu colles le bloc `read -rsp …` que Claude te donne, puis tu lui réponds « fait ».
- **À la fin, sur Discord :** tu écris `@Vulcain bonjour`.
