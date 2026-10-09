#!/usr/bin/env bash
# Dependency-free tests for the usine-hermes CLI (external behaviour only).
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cli="$root/bin/usine-hermes"
fails=0
exec </dev/null # no test may wait on a terminal

ok() { printf 'ok   %s\n' "$1"; }
ko() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# expect <desc> <expected-exit> <regex|""> -- cmd...
expect() {
  local desc=$1 code=$2 pat=$3 out rc
  shift 4
  out=$("$@" 2>&1); rc=$?
  if [[ $rc -ne $code ]]; then ko "$desc (exit $rc, want $code): $out"; return; fi
  if [[ -n $pat ]] && ! grep -qE -- "$pat" <<<"$out"; then ko "$desc (no /$pat/): $out"; return; fi
  ok "$desc"
}

expect "help exits 0 and lists commands" 0 "create" -- "$cli" help
expect "unknown command exits 2" 2 "unknown command" -- "$cli" frobnicate

# Profile names: ^[a-z][a-z0-9-]{1,30}$ (2..31 chars).
for name in ab argus my-agent-2 "a$(printf '%030d' 0)"; do
  out=$("$cli" create "$name" --dry-run 2>&1)
  if grep -qE "invalid name|unknown command" <<<"$out"; then ko "valid name accepted: $name"; else ok "valid name accepted: $name"; fi
done
for name in "" a 2bot -agent Agent my_agent "a.b" "a b" "a$(printf '%031d' 0)" "../x"; do
  expect "invalid name rejected: '$name'" 2 "invalid name" -- "$cli" create "$name" --dry-run
done
expect "create without name rejected" 2 "invalid name" -- "$cli" create --dry-run
expect "name checked by start too" 2 "invalid name" -- "$cli" start Bad

# install.sh refuses unsupported OSes, then non-root runs.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Example config with Honcho memory on (init leaves it off until enabled).
mkdir -p "$tmp/ex"; ex="$tmp/ex/usine.yaml"
sed 's/^honcho:.*/honcho: true/' "$root/usine.example.yaml" >"$ex"
osr() { printf 'ID=%s\nVERSION_ID="%s"\n' "$1" "$2" >"$tmp/$1-$2"; echo "$tmp/$1-$2"; }
expect "install: missing os-release refused" 1 "unsupported OS" -- \
  env USINE_OS_RELEASE="$tmp/nope" "$BASH" "$root/install.sh"
for v in "fedora 40" "ubuntu 22.04" "debian 11"; do
  read -r id ver <<<"$v"
  expect "install: $v refused" 1 "unsupported OS" -- \
    env USINE_OS_RELEASE="$(osr "$id" "$ver")" "$BASH" "$root/install.sh"
done
expect "install: USINE_LANG=fr refuses in French" 1 "OS non pris en charge" -- \
  env USINE_LANG=fr USINE_OS_RELEASE="$tmp/nope" "$BASH" "$root/install.sh"
if [[ $EUID -ne 0 ]]; then
  expect "install: USINE_LANG=fr root refusal in French" 1 "doit être lancé en root" -- \
    env USINE_LANG=fr USINE_OS_RELEASE="$(osr ubuntu 24.04)" "$BASH" "$root/install.sh"
  for v in "ubuntu 24.04" "debian 12" "debian 13"; do
    read -r id ver <<<"$v"
    expect "install: $v accepted, non-root refused" 1 "must run as root" -- \
      env USINE_OS_RELEASE="$(osr "$id" "$ver")" "$BASH" "$root/install.sh"
  done
fi

# init: asks only the language; USINE_CONFIG points at a non-root path.
cfgf="$tmp/etc/usine.yaml"; keyf="$tmp/etc/openrouter.key"
uc() { env USINE_LANG=fr USINE_CONFIG="$cfgf" "$cli" "$@"; }
expect "config without file points to init" 1 "usine-hermes init" -- uc config home_root
expect "init: USINE_LANG stored, not asked" 0 "^\| lang: fr$" -- uc init --dry-run
if [[ -n $(uc init --dry-run 2>&1 >/dev/null) ]]; then ko "init: USINE_LANG set, asks nothing"; else ok "init: USINE_LANG set, asks nothing"; fi
# Without USINE_LANG: the language is the only question.
li() { env -u USINE_LANG USINE_CONFIG="$tmp/l/usine.yaml" "$cli" "$@"; }
asked=$(li init --dry-run 2>&1 >/dev/null <<<'')
if [[ $asked == "Language / Langue : [1] English  [2] Français  (Enter = 1) " ]]; then ok "init asks the language only"; else ko "init asks the language only: $asked"; fi
expect "init: Enter = English" 0 "^\| lang: en$" -- li init --dry-run <<<''
expect "init: 2 stores lang fr" 0 "^\| lang: fr$" -- li init --dry-run <<<2
li init <<<2 >/dev/null 2>&1
expect "init: lang stored in config" 0 "^fr$" -- li config lang
if li init <<<x 2>&1 | grep -c >/dev/null "Langue"; then ko "init re-run: language not asked again"; else ok "init re-run: language not asked again"; fi
expect "config lang drives the CLI (no USINE_LANG)" 1 "pas un profil géré" -- li status nobody
expect "init --dry-run prints the config" 0 "write $cfgf" -- uc init --dry-run
if [[ -e $cfgf ]]; then ko "init --dry-run writes nothing"; else ok "init --dry-run writes nothing"; fi
expect "init writes the config" 0 "" -- uc init
if [[ -e $keyf ]]; then ko "init stores no key"; else ok "init stores no key"; fi
if uc init <<<x 2>&1 | grep -c >/dev/null "Langue"; then ko "init re-run asks nothing"; else ok "init re-run asks nothing"; fi
expect "init: no Discord id yet" 0 "^$" -- uc config discord_allowed_users
expect "init: memory off until enabled" 0 "^false$" -- uc config honcho
expect "config reads home_root default" 0 "^/var/lib/usine-hermes$" -- uc config home_root
expect "config reads pinned hermes_version" 0 "^v2026\.9\.24$" -- uc config hermes_version
expect "config reads per-provider model" 0 "^z-ai/glm-5\.2$" -- uc config model_openrouter
expect "config reads dashed provider model" 0 "^gpt-5\.6-terra$" -- uc config model_openai_codex
expect "config reads peer_name default" 0 "^owner$" -- uc config peer_name
expect "config reads honcho_url" 0 "^http://127\.0\.0\.1:8000$" -- uc config honcho_url
expect "config unknown key fails" 1 "clé de config inconnue" -- uc config nope
if grep -qiE "key|token|secret|password" <(grep -v '^#' "$cfgf" | cut -d: -f1); then ko "config holds no secret keys"; else ok "config holds no secret keys"; fi
keys() { grep -E '^[a-z_]+:' "$1" | cut -d: -f1 | sort; }
if [[ "$(keys "$cfgf")" == "$(keys "$root/usine.example.yaml")" ]]; then ok "example has same keys as init"; else ko "example has same keys as init"; fi
expect "config reads example via USINE_CONFIG" 0 "^gpt-6-sol$" -- \
  env USINE_CONFIG="$root/usine.example.yaml" "$cli" config model_openai_api
# Loaded config is validated too (it feeds sed, honcho.json and rm -rf paths).
badc() { sed "s#^$1:.*#$1: $2#" "$root/usine.example.yaml" >"$tmp/bad.yaml"; env USINE_CONFIG="$tmp/bad.yaml" "$cli" "${@:3}"; }
expect "load rejects bad home_root" 2 "invalid home_root" -- badc home_root "/srv/a b" config peer_name
expect "load rejects relative home_root" 2 "invalid home_root" -- badc home_root "var/lib" config peer_name
expect "load rejects / as home_root" 2 "invalid home_root" -- badc home_root "/" config peer_name
expect "load rejects .. in home_root" 2 "home_root" -- badc home_root "/var/../etc" config peer_name
expect "load rejects bad honcho_url" 2 "invalid honcho_url" -- badc honcho_url 'http://x/"' create ab --dry-run
expect "load accepts https honcho_url" 0 "" -- badc honcho_url "https://honcho.example:8443" config honcho_url
expect "load rejects bad allowlist" 2 "invalid discord_allowed_users" -- badc discord_allowed_users "1;2" config honcho
expect "load rejects bad hermes_version" 2 "invalid hermes_version" -- badc hermes_version "v1|x" bootstrap --dry-run
expect "load rejects bad peer_name" 2 "invalid peer_name" -- badc peer_name '"x' config honcho

# bootstrap --dry-run: planned Hermes install, no root, no network.
bs() { env USINE_CONFIG="$ex" "$cli" bootstrap --dry-run; }
expect "bootstrap: apt prereqs" 0 "apt-get install -y .*git.*curl" -- bs
expect "bootstrap: tag resolved via ls-remote" 0 \
  "git ls-remote https://github.com/NousResearch/hermes-agent .*refs/tags/v2026\.9\.24" -- bs
expect "bootstrap: installer fetched at the resolved sha" 0 \
  "raw\.githubusercontent\.com/NousResearch/hermes-agent/\\\\?<sha-of-v2026\.9\.24\\\\?>/scripts/install\.sh" -- bs
if bs 2>&1 | grep -c >/dev/null "hermes-agent/v2026"; then ko "bootstrap: installer not fetched by tag"; else ok "bootstrap: installer not fetched by tag"; fi
expect "bootstrap: installer pinned and non-interactive" 0 \
  "--commit \\\\?<sha-of-v2026\.9\.24\\\\?> --non-interactive --skip-setup --skip-browser --skip-computer-use" -- bs
expect "bootstrap: root HERMES_HOME via installer flag" 0 "install.* --hermes-home /root/\.hermes" -- bs
if bs 2>&1 | grep -c >/dev/null "HERMES_HOME="; then ko "bootstrap: no HERMES_HOME env"; else ok "bootstrap: no HERMES_HOME env"; fi
if bs 2>&1 | grep -c >/dev/null -- "--dir"; then ko "bootstrap: no --dir"; else ok "bootstrap: no --dir"; fi
expect "bootstrap: skip when at pinned sha" 0 \
  "skip.*/usr/local/lib/hermes-agent.*at <sha-of-v2026\.9\.24>" -- bs
expect "bootstrap: pre-bakes Discord + Honcho deps" 0 \
  "uv sync --extra all --extra messaging --extra honcho --locked" -- bs
expect "bootstrap: shared install root-owned" 0 "chown -R root:root /usr/local/lib/hermes-agent" -- bs
expect "bootstrap: shared install not writable by others" 0 "chmod -R go-w /usr/local/lib/hermes-agent" -- bs
if [[ $EUID -ne 0 ]]; then
  expect "bootstrap: non-root refused" 1 "must run as root" -- \
    env USINE_CONFIG="$root/usine.example.yaml" "$cli" bootstrap
fi

# create --dry-run: full plan, no root. With every flag but no token on a
# non-TTY stdin it never prompts and does not start.
cr() { env USINE_CONFIG="$ex" "$cli" create "$@" --dry-run; }
crf() { cr ab --personality "dry wit" --mission "watch the logs" --provider anthropic; }
expect "create: system nologin user + own group" 0 \
  "useradd --system --user-group --home-dir /var/lib/usine-hermes/ab --no-create-home --shell /usr/sbin/nologin ab" -- crf
expect "create: private home 700 owned by profile" 0 "install -d -m 700 -o ab -g ab /var/lib/usine-hermes/ab" -- crf
# Root-owned registry next to the config (here the repo root), right after useradd.
expect "create: ownership marker in root registry" 0 "write $tmp/ex/profiles/ab \(mode 644, owner root:root\)" -- crf
expect "create: marker records the provider" 0 "^\| provider=anthropic$" -- crf
if crf 2>&1 | grep -A2 "useradd" | grep -c >/dev/null "profiles/ab "; then ok "create: marker right after useradd"; else ko "create: marker right after useradd"; fi
if crf 2>&1 | grep -c >/dev/null "lib/usine-hermes/ab/\.usine-hermes"; then ko "create: no marker in profile home"; else ok "create: no marker in profile home"; fi
expect "create: SOUL.md with personality" 0 "^\| .*dry wit" -- crf
expect "create: SOUL.md with mission" 0 "^\| .*watch the logs" -- crf
expect "create: .env 600 owned by profile" 0 \
  "write /var/lib/usine-hermes/ab/\.hermes/\.env \(mode 600, owner ab:ab\)" -- crf
expect "create: provider set as profile user" 0 \
  "runuser -u ab -- .*hermes config set model\.provider anthropic" -- crf
expect "create: default model from config" 0 "hermes config set model\.default claude-sonnet-4-6" -- crf
expect "create: unit installed" 0 "write /etc/systemd/system/usine-ab\.service" -- crf
expect "create: unit runs gateway as profile" 0 "^\| User=ab$" -- crf
expect "create: unit uses external supervisor" 0 "hermes gateway run --external-supervisor" -- crf
expect "create: unit sets HERMES_HOME" 0 "HERMES_HOME=/var/lib/usine-hermes/ab/\.hermes" -- crf
expect "create: unit sets lazy-install target" 0 "HERMES_LAZY_INSTALL_TARGET=/var/lib/usine-hermes/ab/lazy-packages" -- crf
expect "create: isolation drop-in installed" 0 "write /etc/systemd/system/usine-ab\.service\.d/isolate\.conf" -- crf
expect "create: drop-in strict + home bound" 0 "^\| BindPaths=/var/lib/usine-hermes/ab$" -- crf
expect "create: drop-in hides other processes" 0 "^\| ProtectProc=invisible$" -- crf
expect "create: daemon-reload" 0 "systemctl daemon-reload" -- crf
expect "create: no token: one secret command" 0 "^  sudo usine-hermes secret ab$" -- crf
if crf 2>&1 | grep -cE >/dev/null "systemctl (enable|start)"; then ko "create: no token, not started"; else ok "create: no token, not started"; fi
if crf 2>&1 | grep -cE >/dev/null "^\| .*(DISCORD_BOT_TOKEN|API_KEY)"; then ko "create: .env content not printed"; else ok "create: .env content not printed"; fi
expect "create: experimental Claude plugin gone" 2 "unknown provider" -- cr ab --provider claude-subscription-directsdk-experimental
expect "create: unknown provider rejected" 2 "unknown provider" -- cr ab --provider nope
# Its own channel: answers there without a mention, inline; mention elsewhere.
expect "create: --channel: free-response channel in .env" 0 "^# \.env keys: DISCORD_FREE_RESPONSE_CHANNELS$" -- cr ab --mission m --channel 123456789012345678
expect "create: --channel digits only" 2 "invalid channel" -- cr ab --mission m --channel general
if cr ab --mission m 2>&1 | grep -c >/dev/null FREE_RESPONSE; then ko "create: no channel, no free-response line"; else ok "create: no channel, no free-response line"; fi
# OpenRouter create: two questions, shared key, starts when a token is given.
mkdir -p "$tmp/shared"; scfg="$tmp/shared/usine.yaml"
cp "$root/usine.example.yaml" "$scfg"; echo sk-or-shared-secret >"$tmp/shared/openrouter.key"
cs() { env USINE_LANG=fr USINE_CONFIG="$scfg" "$cli" create "$1" --provider openrouter "${@:2}" --dry-run; }
cse() { env USINE_LANG=en USINE_CONFIG="$scfg" "$cli" create "$1" --provider openrouter "${@:2}" --dry-run; }
asked=$(cse alice 2>&1 >/dev/null <<<$'watch prices\n')
if [[ $asked == "What should alice do? (one sentence): Discord bot token for alice (Enter = later): " ]]; then ok "create: English questions"; else ko "create: English questions: $asked"; fi
expect "create: English start line" 0 "✓ alice created and started\. Mention @alice on Discord\." -- cse alice <<<$'w\ntok.alice.1234567890'
expect "create: English later line" 0 "✓ alice created\. Once you have the bot token, it starts with:" -- cse alice <<<$'w\n'
expect "create: English key prompt" 0 "ANTHROPIC_API_KEY for ab \(hidden\):" -- cse ab --provider anthropic <<<$'w\n'
expect "create: English subscription warning" 0 "undocumented" -- cse ab --provider openai-codex <<<$'w\n'
expect "create: French subscription warning" 0 "pas documenté" -- cs ab --provider openai-codex <<<$'w\n'
expect "create: French error" 2 "fournisseur inconnu" -- cs ab --provider nope
expect "create: asks what it does" 0 "Que doit faire alice \? \(une phrase\) :" -- cs alice <<<$'watch prices\n'
expect "create: asks the bot token (d')" 0 "Token du bot Discord d'alice \(Entrée = plus tard\) :" -- cs alice <<<$'watch prices\n'
expect "create: asks the bot token (de)" 0 "Token du bot Discord de bob \(Entrée = plus tard\) :" -- cs bob <<<$'watch prices\n'
# Prompts go to stderr: exactly these two, nothing else.
asked=$(cs alice 2>&1 >/dev/null <<<$'watch prices\n')
if [[ $asked == "Que doit faire alice ? (une phrase) : Token du bot Discord d'alice (Entrée = plus tard) : " ]]; then ok "create: only two questions"; else ko "create: only two questions: $asked"; fi
# Default create: the ChatGPT subscription with terra, login offered as the profile.
cd0() { env USINE_LANG=en USINE_CONFIG="$scfg" "$cli" create alice --dry-run; }
expect "create: default provider ChatGPT" 0 "hermes config set model\.provider openai-codex$" -- cd0 <<<$'w\nn\n'
expect "create: default model terra" 0 "hermes config set model\.default gpt-5\.6-terra$" -- cd0 <<<$'w\nn\n'
asked=$(cd0 2>&1 >/dev/null <<<$'w\nn\n' | grep -oE "What should alice do\?|Log in now\? \[y/N\]|Discord bot token for alice" | paste -sd'|' -)
if [[ $asked == "What should alice do?|Log in now? [y/N]|Discord bot token for alice" ]]; then ok "create: default asks mission, login, token"; else ko "create: default asks mission, login, token: $asked"; fi
expect "create: default login as the profile on y" 0 "^\+ runuser -u alice -- .*hermes auth add openai-codex$" -- cd0 <<<$'w\ny\n'
expect "create: tool calls hidden as the profile" 0 "runuser -u alice -- .*hermes config set --force display\.tool_progress off$" -- cd0 <<<$'w\nn\n'
expect "create: reasoning medium as the profile" 0 "runuser -u alice -- .*hermes config set --force agent\.reasoning_effort medium$" -- cd0 <<<$'w\nn\n'
expect "create: mission in SOUL.md" 0 "^\| watch prices$" -- cs alice <<<$'watch prices\n'
expect "create: default personality in SOUL.md" 0 "^\| helpful, concise and friendly$" -- cs alice <<<$'watch prices\n'
expect "create: token given: starts" 0 "systemctl enable --now usine-alice\.service" -- cs alice <<<$'watch prices\ntok.alice.1234567890'
expect "create: token given: says it runs" 0 "✓ alice créée et démarrée\. Mentionne @alice sur Discord\." -- cs alice <<<$'watch prices\ntok.alice.1234567890'
if cs alice <<<$'w\ntok.alice.1234567890' 2>&1 | grep -cE >/dev/null "tok\.alice|sk-or-shared"; then ko "create: secrets never printed"; else ok "create: secrets never printed"; fi
if cs alice <<<$'w\n' 2>&1 | grep -cE >/dev/null "systemctl (enable|start)"; then ko "create: no token: not started"; else ok "create: no token: not started"; fi
expect "create: no token: one secret command (interactive)" 0 "^  sudo usine-hermes secret alice$" -- cs alice <<<$'w\n'
# A pasted Client Secret (no dots) is refused and the token asked again.
expect "create: non-token refused, re-asked" 0 "Ce n'est pas un token de bot" -- cs alice <<<$'w\nabcdefghijklmnopqrstuvwxyz0123456789\ntok.alice.1234567890'
expect "create: valid token after retry starts" 0 "systemctl enable --now usine-alice\.service" -- cs alice <<<$'w\nabcdefghijklmnopqrstuvwxyz0123456789\ntok.alice.1234567890'
if cs alice <<<$'w\n' 2>&1 | grep -c >/dev/null "secret alice OPENROUTER"; then ko "create: shared key, no key step"; else ok "create: shared key, no key step"; fi
expect "create: no shared key: asks the OpenRouter key" 0 "OPENROUTER_API_KEY for ab \(hidden\):" -- cr ab --provider openrouter <<<$'w\n'
expect "create: --provider asks that key" 0 "ANTHROPIC_API_KEY pour ab \(saisie masquée\) :" -- cs ab --provider anthropic <<<$'w\n'
expect "create: --personality written" 0 "^\| dry wit$" -- cs ab --personality "dry wit" <<<$'w\n'
# Subscription providers: warning, y/N login as the profile user, or a follow-up command.
sub() { cr ab --personality p --mission m --provider "$@"; }
# Missing --mission keeps it interactive: Enter for the mission, then the login answer.
subi() { cr ab --personality p --provider "$@"; }
expect "sub: codex warns quota" 0 "quota" -- sub openai-codex
expect "sub: supergrok warns 403" 0 "403" -- sub xai-oauth
expect "sub: codex login as profile on y" 0 "^\+ runuser -u ab -- .*hermes auth add openai-codex" -- subi openai-codex <<<$'\ny'
expect "sub: supergrok login as profile on y" 0 "^\+ runuser -u ab -- .*hermes auth add xai-oauth" -- subi xai-oauth <<<$'\ny'
expect "sub: skip prints follow-up command" 0 "later" -- sub openai-codex
expect "sub: follow-up is the model command" 0 "^ *sudo usine-hermes model ab$" -- sub openai-codex
if sub openai-codex 2>&1 | grep -c >/dev/null "^+ .*auth add"; then ko "sub: skip runs no login"; else ok "sub: skip runs no login"; fi
# All flags + stdin not a TTY (tests run on /dev/null): no prompt at all.
prompts="Que doit|What should|Token du bot|bot token for|saisie masquée|\(hidden\)|\[o/N\]|\[y/N\]"
if crf 2>&1 | grep -cE >/dev/null "$prompts"; then ko "create: flags, no TTY: no prompt"; else ok "create: flags, no TTY: no prompt"; fi
if sub openai-codex 2>&1 | grep -cE >/dev/null "Se connecter|Log in now"; then ko "create: no TTY: no login prompt"; else ok "create: no TTY: no login prompt"; fi
expect "create: next step sets the API key" 0 "sudo usine-hermes secret ab ANTHROPIC_API_KEY" -- crf
if sub openai-codex 2>&1 | grep -c >/dev/null "secret ab .*_API_KEY"; then ko "create: no key step for subscriptions"; else ok "create: no key step for subscriptions"; fi
expect "create: unknown flag rejected" 2 "unknown flag" -- cr ab --nope x
expect "create: existing non-managed user refused" 1 "non-managed" -- cr root --provider anthropic
# Vulcain preset: an operator profile that creates profiles through the bridge.
vc() { cr vul --preset vulcain; }
hh=/var/lib/usine-hermes/vul/.hermes
expect "preset: unknown preset rejected" 2 "unknown preset" -- cr vul --preset nope --provider openrouter
expect "preset: Vulcain SOUL installed" 0 "write $hh/SOUL\.md \(mode 644, owner vul:vul\)" -- vc
expect "preset: SOUL never handles secrets" 0 "^\| .*[Nn]ever ask.*secret" -- vc
expect "preset: skill dir owned by profile" 0 "install -d -m 700 -o vul -g vul $hh/skills $hh/skills/usine-hermes $hh/skills/usine-secret$" -- vc
expect "preset: secret capture skill installed" 0 \
  "install -m 644 -o vul -g vul $root/skills/usine-secret/SKILL\.md $hh/skills/usine-secret/SKILL\.md" -- vc
expect "secret skill: hidden capture declared" 0 "name: USINE_PENDING_SECRET" -- cat "$root/skills/usine-secret/SKILL.md"
expect "preset: Vulcain skill installed in its profile" 0 \
  "install -m 644 -o vul -g vul $root/skills/usine-hermes/SKILL\.md $hh/skills/usine-hermes/SKILL\.md" -- vc
expect "preset: only the bridge is pre-approved" 0 \
  "runuser -u vul -- .*hermes config set command_allowlist .*sudo.{1,2}-n.{1,2}/usr/local/bin/usine-hermes.{1,2}bridge.{1,3}\\*" -- vc
expect "preset: sudoers staged under an ignored name" 0 "write /etc/sudoers\.d/usine-hermes-vul\.new \(mode 440, owner root:root\)" -- vc
expect "preset: sudoers allows the bridge only" 0 \
  "^\| vul ALL=\(root\) NOPASSWD: /usr/local/bin/usine-hermes bridge \*$" -- vc
expect "preset: sudoers checked before use" 0 \
  "visudo -cf /etc/sudoers\.d/usine-hermes-vul\.new"$'\n'"\+ mv /etc/sudoers\.d/usine-hermes-vul\.new /etc/sudoers\.d/usine-hermes-vul$" -- vc
expect "preset: drop-in relaxes NoNewPrivileges only" 0 \
  "write /etc/systemd/system/usine-vul\.service\.d/vulcain\.conf"$'\n'"\| \[Service\]"$'\n'"\| NoNewPrivileges=no$" -- vc
expect "preset: still sandboxed by isolate.conf" 0 "write /etc/systemd/system/usine-vul\.service\.d/isolate\.conf" -- vc
if vc 2>&1 | grep -cE >/dev/null "$prompts|systemctl (enable|start)"; then ko "preset: no prompt, not started"; else ok "preset: no prompt, not started"; fi
if vc 2>&1 | grep -cE >/dev/null "model\.provider|_API_KEY"; then ko "preset: no provider yet (chosen in the chat)"; else ok "preset: no provider yet (chosen in the chat)"; fi
expect "preset: registry has no provider" 0 "^\| provider=$" -- vc
expect "preset: SOUL knows the operator language" 0 "^\| .*language: en" -- vc
expect "preset: next step is the chat" 0 "sudo usine-hermes$" -- vc
if crf 2>&1 | grep -cE >/dev/null "sudoers|command_allowlist|vulcain"; then ko "create: no operator bits without preset"; else ok "create: no operator bits without preset"; fi
if [[ $EUID -ne 0 ]]; then
  expect "create: non-root refused" 1 "must run as root" -- \
    env USINE_CONFIG="$root/usine.example.yaml" "$cli" create ab --provider anthropic </dev/null
fi

# Lifecycle against a fake home_root; systemctl/journalctl stubbed on PATH.
hr="$tmp/homes"; lcfg="$tmp/life.yaml"
sed "s|^home_root:.*|home_root: $hr|" "$ex" >"$lcfg"
mkprof() { mkdir -p "$hr/$1/.hermes" "$tmp/profiles"; echo "provider=${4:-openrouter}" >"$tmp/profiles/$1"; printf 'DISCORD_BOT_TOKEN=%s\nOPENROUTER_API_KEY=%s\n' "$2" "$3" >"$hr/$1/.hermes/.env"; }
mkprof alpha "" ""
mkprof beta "tok.beta.1234567890" "sk-or-beta-secret"
mkprof gamma "tok.beta.1234567890" ""
mkprof delta "tok.delta.0987654321" "sk-or-delta-secret"
mkdir -p "$hr/stranger" "$hr/imposter/.hermes" "$tmp/stub"
# A marker inside a home is profile-writable, so it never counts.
: >"$hr/imposter/.usine-hermes"
cat >"$tmp/stub/systemctl" <<'EOF'
#!/bin/sh
case "$1 $*" in
  is-active*) if [ -n "${STUB_INACTIVE:-}" ]; then echo inactive; exit 3; fi; echo active ;;
  *LoadState*) echo loaded ;;
  *DropInPaths*) echo "/etc/systemd/system/$2.d/isolate.conf" ;;
  *) echo "systemctl $*"; echo active ;;
esac
EOF
cat >"$tmp/stub/journalctl" <<'EOF'
#!/bin/sh
echo "login ok token tok.delta.0987654321 key=sk-or-delta-secret"
echo "Authorization: Bearer abcdefghijklmnopqrstuvwxyz"
EOF
chmod +x "$tmp/stub/"*
lc() { env USINE_CONFIG="$lcfg" PATH="$tmp/stub:$PATH" "$cli" "$@"; }
expect "start: empty token refused" 1 "empty" -- lc start alpha --dry-run
expect "start: duplicate token refused" 1 "already used by beta" -- lc start gamma --dry-run
expect "start: unmanaged profile refused" 1 "not a managed profile" -- lc start stranger --dry-run
expect "start: marker in home not trusted" 1 "not a managed profile" -- lc start imposter --dry-run
expect "create: managed profile points to destroy" 1 "already managed.*destroy delta" -- lc create delta --provider anthropic --dry-run
expect "create: reused token refused before any change" 1 "already used by beta" -- lc create newp --dry-run <<<$'m\nsk-or-x\ntok.beta.1234567890'
if lc create newp --dry-run <<<$'m\nsk-or-x\ntok.beta.1234567890' 2>&1 | grep -c >/dev/null useradd; then ko "create: reused token creates nothing"; else ok "create: reused token creates nothing"; fi
expect "start: enables and starts" 0 "systemctl enable --now usine-delta\.service" -- lc start delta --dry-run
expect "stop: stops unit" 0 "systemctl stop usine-delta\.service" -- lc stop delta --dry-run
expect "restart: restarts unit" 0 "systemctl restart usine-delta\.service" -- lc restart delta --dry-run
expect "list: managed profiles only" 0 "^delta +active +token=set" -- lc list
if lc list 2>&1 | grep -cE >/dev/null "stranger|imposter"; then ko "list: hides non-managed dirs"; else ok "list: hides non-managed dirs"; fi
expect "list: empty token shown" 0 "^alpha +active +token=empty" -- lc list
expect "status: unit state + token" 0 "token=set" -- lc status delta
expect "logs: journal of the unit" 0 "login ok" -- lc logs delta
if lc logs delta 2>&1 | grep -cE >/dev/null "tok\.delta|sk-or-delta|abcdefghijklmnop"; then ko "logs: secrets redacted"; else ok "logs: secrets redacted"; fi
if [[ $EUID -ne 0 ]]; then
  expect "start: non-root refused" 1 "must run as root" -- lc start delta
fi
# destroy: typed-name confirmation, managed profiles only.
expect "destroy: unmanaged profile refused" 1 "not a managed profile" -- lc destroy stranger --dry-run <<<stranger
expect "destroy: wrong typed name aborts" 1 "aborted" -- lc destroy delta --dry-run <<<beta
expect "destroy: no typed name aborts" 1 "aborted" -- lc destroy delta --dry-run </dev/null
expect "destroy: asks to type the name" 0 "Type delta" -- lc destroy delta --dry-run <<<delta
expect "destroy: stops and disables unit" 0 "systemctl disable --now usine-delta\.service" -- lc destroy delta --dry-run <<<delta
expect "destroy: removes unit" 0 "rm -f /etc/systemd/system/usine-delta\.service$" -- lc destroy delta --dry-run <<<delta
expect "destroy: removes drop-in dir" 0 "rm -rf /etc/systemd/system/usine-delta\.service\.d" -- lc destroy delta --dry-run <<<delta
expect "destroy: removes any operator sudoers rule" 0 "rm -f /etc/sudoers\.d/usine-hermes-delta$" -- lc destroy delta --dry-run <<<delta
expect "destroy: daemon-reload" 0 "systemctl daemon-reload" -- lc destroy delta --dry-run <<<delta
expect "destroy: removes user" 0 "userdel delta" -- lc destroy delta --dry-run <<<delta
expect "destroy: removes home" 0 "rm -rf $hr/delta$" -- lc destroy delta --dry-run <<<delta
expect "destroy: removes marker last" 0 "rm -f $tmp/profiles/delta"$'\n'"destroyed" -- lc destroy delta --dry-run <<<delta
if [[ -f $tmp/profiles/delta ]]; then ok "destroy: dry-run keeps files"; else ko "destroy: dry-run keeps files"; fi
if [[ $EUID -ne 0 ]]; then
  expect "destroy: non-root refused" 1 "must run as root" -- lc destroy delta <<<delta
fi

# secret: hidden prompt, one allowed key per call, managed profiles only.
expect "secret: unknown key refused" 2 "unknown key" -- lc secret delta PATH --dry-run <<<x
expect "secret: unmanaged profile refused" 1 "not a managed profile" -- lc secret stranger DISCORD_BOT_TOKEN --dry-run <<<x
expect "secret: name checked" 2 "invalid name" -- lc secret Bad DISCORD_BOT_TOKEN --dry-run <<<x
sec() { lc secret "$1" "$2" --dry-run <<<"$3"; }
expect "secret: hidden prompt names key and profile" 0 "OPENROUTER_API_KEY for delta \(hidden\):" -- sec delta OPENROUTER_API_KEY sk-or-new-secret
expect "secret: .env rewritten 600 owned by profile" 0 \
  "write $hr/delta/\.hermes/\.env \(mode 600, owner delta:delta\)" -- sec delta DISCORD_BOT_TOKEN new.token.123456
expect "secret: replaces an existing key" 0 "^# \.env keys: OPENROUTER_API_KEY DISCORD_BOT_TOKEN$" -- sec delta DISCORD_BOT_TOKEN new.token.123456
mkprof epsilon "" "" xai
expect "secret: appends a missing key" 0 "^# \.env keys: DISCORD_BOT_TOKEN OPENROUTER_API_KEY XAI_API_KEY$" -- sec epsilon XAI_API_KEY xai-new-secret
expect "secret: other provider's key refused" 2 "unknown key.*allowed: DISCORD_BOT_TOKEN OPENROUTER_API_KEY\)$" -- sec delta XAI_API_KEY x
mkprof zeta "" "" openai-codex
expect "secret: subscription profile takes only the token" 2 "allowed: DISCORD_BOT_TOKEN\)$" -- sec zeta OPENAI_API_KEY x
if sec delta OPENROUTER_API_KEY sk-or-new-secret 2>&1 | grep -cE >/dev/null "sk-or-|tok\.delta"; then ko "secret: values never printed"; else ok "secret: values never printed"; fi
expect "secret: empty value refused" 1 "empty" -- sec delta DISCORD_BOT_TOKEN ""
expect "secret: restart hint when active" 0 "usine-hermes restart delta" -- sec delta DISCORD_BOT_TOKEN new.token.123456
# secret <name>: the Discord token, then the profile starts if it is stopped.
expect "secret: French prompt" 0 "OPENROUTER_API_KEY pour delta \(saisie masquée\) :" -- env USINE_LANG=fr USINE_CONFIG="$lcfg" PATH="$tmp/stub:$PATH" "$cli" secret delta OPENROUTER_API_KEY --dry-run <<<sk-or-new-secret
tk() { env USINE_LANG="${TL:-fr}" STUB_INACTIVE="${STOPPED-1}" USINE_CONFIG="$lcfg" PATH="$tmp/stub:$PATH" "$cli" secret "$1" --dry-run <<<"$2"; }
expect "secret <name>: asks the bot token" 0 "Token du bot Discord d'alpha :" -- tk alpha new.alpha.123456
expect "secret <name>: sets DISCORD_BOT_TOKEN" 0 "^# \.env keys: OPENROUTER_API_KEY DISCORD_BOT_TOKEN$" -- tk alpha new.alpha.123456
expect "secret <name>: starts a stopped profile" 0 "systemctl enable --now usine-alpha\.service" -- tk alpha new.alpha.123456
expect "secret <name>: says it runs" 0 "✓ alpha démarrée\. Mentionne @alpha sur Discord\." -- tk alpha new.alpha.123456
tke() { TL=en tk "$@"; }
expect "secret <name>: English prompt" 0 "Discord bot token for alpha:" -- tke alpha new.alpha.123456
expect "secret <name>: English start line" 0 "✓ alpha started\. Mention @alpha on Discord\." -- tke alpha new.alpha.123456
if STOPPED='' tk delta new.token.123456 2>&1 | grep -c >/dev/null "enable --now"; then ko "secret <name>: running profile not re-enabled"; else ok "secret <name>: running profile not re-enabled"; fi
expect "secret <name>: reused token refused" 1 "déjà utilisé par beta" -- tk alpha tok.beta.1234567890
if tk alpha new.alpha.123456 2>&1 | grep -c >/dev/null "new\.alpha"; then ko "secret <name>: token never printed"; else ok "secret <name>: token never printed"; fi
if grep -q "^DISCORD_BOT_TOKEN=tok.delta" "$hr/delta/.hermes/.env"; then ok "secret: dry-run writes nothing"; else ko "secret: dry-run writes nothing"; fi
if [[ $EUID -ne 0 ]]; then
  expect "secret: non-root refused" 1 "must run as root" -- lc secret delta DISCORD_BOT_TOKEN <<<x
fi

# model <name>: provider menu, login or hidden key, registry updated.
md() { env USINE_LANG="${TL:-en}" STUB_INACTIVE="${STOPPED-}" USINE_CONFIG="$lcfg" PATH="$tmp/stub:$PATH" "$cli" model "$1" --dry-run <<<"$2"; }
expect "model: menu asks for the model" 0 "Which model for delta\?" -- md delta ''
mdf() { TL=fr md "$@"; }
expect "model: French menu" 0 "1\) ChatGPT \(abonnement Codex\)" -- mdf delta ''
expect "model: Enter = ChatGPT login as profile" 0 "^\+ runuser -u delta -- .*hermes auth add openai-codex$" -- md delta ''
expect "model: provider set as profile" 0 "hermes config set model\.provider openai-codex" -- md delta ''
expect "model: default model from config" 0 "hermes config set model\.default gpt-5\.6-terra" -- md delta ''
expect "model: registry updated" 0 "write $tmp/profiles/delta \(mode 644, owner root:root\)"$'\n'"\| provider=openai-codex$" -- md delta ''
expect "model: restarts a running profile" 0 "systemctl restart usine-delta\.service" -- md delta ''
if STOPPED=1 md delta '' 2>&1 | grep -c >/dev/null "systemctl restart"; then ko "model: stopped profile not restarted"; else ok "model: stopped profile not restarted"; fi
expect "model: Claude subscription is a native login" 0 "hermes auth add anthropic$" -- md delta 2
expect "model: Claude subscription warns Max + credits" 0 "Max plan" -- md delta 2
i=0
for p in openai-codex anthropic openrouter anthropic openai-api xai xai-oauth gemini deepseek; do
  i=$((i + 1))
  expect "model: choice $i is $p" 0 "^\| provider=$p$" -- md delta "$i"$'\nsk-model-secret'
done
expect "model: API key asked hidden" 0 "ANTHROPIC_API_KEY for delta \(hidden\):" -- md delta $'4\nsk-model-secret'
expect "model: API key written to the profile .env" 0 "^# \.env keys: .*ANTHROPIC_API_KEY$" -- md delta $'4\nsk-model-secret'
if md delta $'4\nsk-model-secret' 2>&1 | grep -cE >/dev/null "sk-model|auth add"; then ko "model: key never printed, no login"; else ok "model: key never printed, no login"; fi
expect "model: empty key changes nothing" 1 "empty" -- md delta $'4\n'
if md delta $'4\n' 2>&1 | grep -c >/dev/null "provider="; then ko "model: empty key, registry kept"; else ok "model: empty key, registry kept"; fi
expect "model: bad choice refused" 2 "invalid choice" -- md delta 12
expect "model: unmanaged profile refused" 1 "not a managed profile" -- md stranger ''
if [[ $EUID -ne 0 ]]; then
  expect "model: non-root refused" 1 "must run as root" -- env USINE_CONFIG="$lcfg" "$cli" model delta
fi

# bridge: the only root command of the Vulcain preset (via sudo). Validated
# here without root; --dry-run prints the journal line and the systemd-run.
mkprof vul "tok.vul.1234567890" "sk-or-vul-secret"
br() { env SUDO_USER="${CALLER-vul}" USINE_CONFIG="$lcfg" PATH="$tmp/stub:$PATH" "$cli" bridge "$@" --dry-run; }
long() { printf "%${1}s" "" | tr ' ' x; }
for a in destroy secret init bootstrap stop config bridge help frobnicate ""; do
  expect "bridge: '$a' denied" 2 "not allowed" -- br "$a" delta
done
expect "bridge: needs a sudo caller" 1 "through sudo" -- env SUDO_USER= USINE_CONFIG="$lcfg" "$cli" bridge list --dry-run
expect "bridge: caller must be managed" 1 "not a managed profile" -- env SUDO_USER=stranger USINE_CONFIG="$lcfg" "$cli" bridge list --dry-run
expect "bridge: bad target name" 2 "invalid name" -- br restart Bad
expect "bridge: missing target" 2 "invalid name" -- br start
expect "bridge: extra arguments refused" 2 "usage" -- br restart delta now
expect "bridge: list takes nothing" 2 "usage" -- br list delta
expect "bridge: no restart of itself" 2 "own profile" -- br restart vul
expect "bridge: no start of itself" 2 "own profile" -- br start vul
expect "bridge: no doctor of itself" 2 "own profile" -- br doctor vul
expect "bridge: status of itself allowed" 0 "systemd-run .* /usr/local/bin/usine-hermes status vul$" -- br status vul
expect "bridge: logs of itself allowed" 0 "usine-hermes logs vul -n 50$" -- br logs vul -n 50
expect "bridge: logs -n must be a small number" 2 "usage" -- br logs delta -n 99999
expect "bridge: logs -n no leading zero" 2 "usage" -- br logs delta -n 0999
expect "bridge: logs bad flag" 2 "usage" -- br logs delta --since x
expect "bridge: doctor of all" 0 "usine-hermes doctor$" -- br doctor
expect "bridge: restart another profile" 0 "usine-hermes restart delta$" -- br restart delta
expect "bridge: logged to the journal" 0 "logger -t usine-hermes-bridge caller=vul\\\\? action=restart\\\\? target=delta" -- br restart delta
expect "bridge: runs as root outside the sandbox" 0 "systemd-run --wait --pipe --quiet --collect /usr/local/bin/usine-hermes list$" -- br list
bc() { br create newbie "$@"; }
expect "bridge: create passes flags through" 0 \
  "usine-hermes create newbie --personality calm --mission watch --provider xai$" -- bc --personality calm --mission watch --provider xai
expect "bridge: create needs --mission" 2 "usage" -- bc --personality calm --provider xai
expect "bridge: create with --mission only" 0 "usine-hermes create newbie --mission watch$" -- bc --mission watch
expect "bridge: create flag twice refused" 2 "usage" -- bc --personality a --personality b --mission m --provider xai
expect "bridge: create no preset" 2 "usage" -- bc --personality a --mission m --provider xai --preset vulcain
expect "bridge: create unknown provider" 2 "unknown provider" -- bc --personality a --mission m --provider evil
expect "bridge: personality too long" 2 "too long" -- bc --personality "$(long 201)" --mission m --provider xai
expect "bridge: mission too long" 2 "too long" -- bc --personality a --mission "$(long 501)" --provider xai
expect "bridge: max-length text accepted" 0 "systemd-run" -- bc --personality "$(long 200)" --mission "$(long 500)" --provider xai
expect "bridge: control chars refused" 2 "control" -- bc --personality $'a\nb' --mission m --provider xai
expect "bridge: create of itself refused" 2 "own profile" -- br create vul --personality a --mission m --provider xai
sed 's/^max_profiles:.*/max_profiles: 7/' "$lcfg" >"$tmp/full.yaml"
expect "bridge: max_profiles enforced" 1 "max_profiles" -- env USINE_CONFIG="$tmp/full.yaml" SUDO_USER=vul PATH="$tmp/stub:$PATH" \
  "$cli" bridge create newbie --personality a --mission m --provider xai --dry-run
if [[ $EUID -ne 0 ]]; then
  expect "bridge: non-root refused" 1 "must run as root" -- env SUDO_USER=vul USINE_CONFIG="$lcfg" "$cli" bridge list
fi
# take-secret / allow / memory: validated by the bridge, run as root.
expect "bridge: take-secret runs with the caller" 0 \
  "systemd-run .* /usr/local/bin/usine-hermes take-secret vul delta OPENROUTER_API_KEY$" -- br take-secret delta OPENROUTER_API_KEY
expect "bridge: take-secret for itself (its Discord bot)" 0 "usine-hermes take-secret vul vul DISCORD_BOT_TOKEN$" -- br take-secret vul DISCORD_BOT_TOKEN
expect "bridge: take-secret only allowed keys" 2 "unknown key" -- br take-secret delta PATH
expect "bridge: take-secret other provider key refused" 2 "unknown key" -- br take-secret delta XAI_API_KEY
expect "bridge: take-secret needs a key" 2 "usage" -- br take-secret delta
expect "bridge: take-secret extra args refused" 2 "usage" -- br take-secret delta DISCORD_BOT_TOKEN x
expect "bridge: take-secret bad name" 2 "invalid name" -- br take-secret Bad DISCORD_BOT_TOKEN
expect "bridge: take-secret unmanaged target" 1 "not a managed profile" -- br take-secret stranger DISCORD_BOT_TOKEN
expect "bridge: channel of another profile" 0 "usine-hermes channel delta 123456789012345678$" -- br channel delta 123456789012345678
expect "bridge: channel of itself allowed" 0 "usine-hermes channel vul 123456789012345678$" -- br channel vul 123456789012345678
expect "bridge: channel digits only" 2 "invalid channel" -- br channel delta general
expect "bridge: channel needs an id" 2 "usage" -- br channel delta
expect "bridge: create --channel passed through" 0 "usine-hermes create newbie --mission m --channel 123456789012345678$" -- bc --mission m --channel 123456789012345678
expect "bridge: create --channel digits only" 2 "invalid channel" -- bc --mission m --channel '1;2'
# channel: the profile's own Discord channel, applied by a restart.
expect "channel: written to the profile .env" 0 "^# \.env keys: DISCORD_BOT_TOKEN OPENROUTER_API_KEY DISCORD_FREE_RESPONSE_CHANNELS$" -- lc channel delta 123456789012345678 --dry-run
expect "channel: restarts it if running" 0 "systemctl try-restart usine-delta\.service" -- lc channel delta 123456789012345678 --dry-run
expect "channel: digits only" 2 "invalid channel" -- lc channel delta general --dry-run
expect "channel: unmanaged profile refused" 1 "not a managed profile" -- lc channel stranger 123456789012345678 --dry-run
expect "bridge: allow ids" 0 "usine-hermes allow 123\\\\?,456$" -- br allow 123,456
expect "bridge: allow rejects non-digits" 2 "invalid discord_allowed_users" -- br allow "1;2"
expect "bridge: allow needs ids" 2 "usage" -- br allow
expect "bridge: allow one argument" 2 "usage" -- br allow 1 2
expect "bridge: memory runs with the caller" 0 "usine-hermes memory vul$" -- br memory
expect "bridge: memory takes nothing" 2 "usage" -- br memory delta
# take-secret: the value captured hidden by Vulcain's usine-secret skill.
echo "USINE_PENDING_SECRET=sk-pending-secret" >>"$hr/vul/.hermes/.env"
tss() { STOPPED=1 ts "$@"; }
mkprof vtok "" ""; echo "USINE_PENDING_SECRET=MTIzNDU2Nzg5MDEyMzQ1Njc4.vtok.123456" >>"$hr/vtok/.hermes/.env"
ts() { env USINE_LANG=en STUB_INACTIVE="${STOPPED-}" USINE_CONFIG="$lcfg" PATH="$tmp/stub:$PATH" "$cli" take-secret "$@" --dry-run; }
expect "take-secret: written to the target .env" 0 \
  "^# \.env keys: DISCORD_BOT_TOKEN OPENROUTER_API_KEY"$'\n'"\+ write $hr/delta/\.hermes/\.env \(mode 600, owner delta:delta\)" -- ts vul delta OPENROUTER_API_KEY
expect "take-secret: removed from the caller .env" 0 \
  "^# \.env keys: DISCORD_BOT_TOKEN OPENROUTER_API_KEY"$'\n'"\+ write $hr/vul/\.hermes/\.env " -- ts vul delta OPENROUTER_API_KEY
if ts vul delta OPENROUTER_API_KEY 2>&1 | grep -c >/dev/null "sk-pending"; then ko "take-secret: value never printed"; else ok "take-secret: value never printed"; fi
expect "take-secret: a Discord token starts a stopped profile" 0 "systemctl enable --now usine-alpha\.service" -- tss vtok alpha DISCORD_BOT_TOKEN
if ts vtok alpha DISCORD_BOT_TOKEN 2>&1 | grep -cE >/dev/null "MTIzNDU2|vtok\.1"; then ko "take-secret: token never printed"; else ok "take-secret: token never printed"; fi
expect "take-secret: invite link from the token's application id" 0 \
  "https://discord\.com/oauth2/authorize\?client_id=123456789012345678&scope=bot\+applications\.commands&permissions=309237763136" -- ts vtok alpha DISCORD_BOT_TOKEN
expect "take-secret: not a bot token refused" 1 "not a bot token" -- ts vul alpha DISCORD_BOT_TOKEN
expect "take-secret: nothing captured" 1 "no pending secret" -- ts delta alpha DISCORD_BOT_TOKEN
expect "take-secret: key checked" 2 "unknown key" -- ts vul delta PATH
# allow: config + every profile's .env.
expect "allow: config updated" 0 "^\| discord_allowed_users: 123,456$" -- lc allow 123,456 --dry-run
expect "allow: every profile .env" 0 "write $hr/delta/\.hermes/\.env \(mode 600" -- lc allow 123,456 --dry-run
expect "allow: running profiles restarted" 0 "systemctl try-restart usine-delta\.service" -- lc allow 123,456 --dry-run
expect "allow: bad ids refused" 2 "invalid discord_allowed_users" -- lc allow "1 2" --dry-run
# memory: Honcho on with the captured OpenRouter key.
mem() { lc memory "$1" --dry-run; }
expect "memory: key stored root 600" 0 "write $tmp/openrouter\.key \(mode 600, owner root:root\)" -- mem vul
expect "memory: config honcho true" 0 "^\| honcho: true$" -- mem vul
expect "memory: Docker + Honcho up" 0 "docker compose -f /opt/usine-hermes/honcho/docker-compose\.yml up -d" -- mem vul
expect "memory: every profile wired" 0 "write $hr/delta/\.hermes/honcho\.json" -- mem vul
expect "memory: running profiles restarted" 0 "systemctl try-restart usine-delta\.service" -- mem vul
if mem vul 2>&1 | grep -c >/dev/null "sk-pending"; then ko "memory: key never printed"; else ok "memory: key never printed"; fi
expect "memory: needs a captured key" 1 "OpenRouter key" -- mem delta
# treg: the team token (captured by Vulcain, or asked hidden), MCP in every profile.
tr() { lc treg "$@" --dry-run; }
expect "bridge: treg runs with the caller" 0 "usine-hermes treg vul$" -- br treg
expect "bridge: treg takes nothing" 2 "usage" -- br treg delta
expect "treg: token stored root 600" 0 "write $tmp/treg\.token \(mode 600, owner root:root\)" -- tr vul
expect "treg: token in every .env" 0 "^# \.env keys: DISCORD_BOT_TOKEN OPENROUTER_API_KEY MCP_TREG_API_KEY$" -- tr vul
expect "treg: MCP url as the profile" 0 "runuser -u delta -- .*hermes config set --force mcp_servers\.treg\.url https://treg\.to/mcp/$" -- tr vul
expect "treg: bearer header from the .env" 0 'mcp_servers\.treg\.headers\.Authorization Bearer\\? \\?\$\\?\{MCP_TREG_API_KEY\\?\}$' -- tr vul
expect "treg: running profiles restarted" 0 "systemctl try-restart usine-delta\.service" -- tr vul
if tr vul 2>&1 | grep -c >/dev/null "sk-pending"; then ko "treg: token never printed"; else ok "treg: token never printed"; fi
expect "treg: needs a captured token" 1 "no pending secret" -- tr delta
expect "treg: asks it hidden from a shell" 0 "treg team token \(hidden\):" -- env USINE_LANG=en USINE_CONFIG="$lcfg" PATH="$tmp/stub:$PATH" "$cli" treg --dry-run <<<treg-secret-token
expect "treg: empty token refused" 1 "empty" -- lc treg --dry-run </dev/null
if cr ab --mission m 2>&1 | grep -c >/dev/null mcp_servers; then ko "create: no treg token, no MCP"; else ok "create: no treg token, no MCP"; fi
echo treg-secret-token >"$tmp/ex/treg.token"
expect "create: treg wired when the token exists" 0 "runuser -u ab -- .*mcp_servers\.treg\.url https://treg\.to/mcp/$" -- cr ab --mission m
if cr ab --mission m 2>&1 | grep -c >/dev/null "treg-secret"; then ko "create: treg token never printed"; else ok "create: treg token never printed"; fi
rm -f "$tmp/ex/treg.token"
if "$cli" help | grep -c >/dev/null bridge; then ko "bridge: hidden from help"; else ok "bridge: hidden from help"; fi
expect "config reads max_profiles" 0 "^10$" -- env USINE_CONFIG="$root/usine.example.yaml" "$cli" config max_profiles

# usine-hermes with no argument: the terminal chat with Vulcain.
ch() { env USINE_CONFIG="$lcfg" PATH="$tmp/stub:$PATH" "$cli" "$@"; }
expect "chat: no Vulcain yet" 1 "not a managed profile" -- ch --dry-run
mkprof vulcain "" "" openai-codex
expect "chat: Hermes REPL as vulcain on a pty" 0 \
  "^\+ runuser --pty -u vulcain -- env HOME=$hr/vulcain HERMES_HOME=$hr/vulcain/\.hermes .*hermes --cli$" -- ch --dry-run
if ch --dry-run 2>&1 | grep -c >/dev/null "Which model"; then ko "chat: known provider, no menu"; else ok "chat: known provider, no menu"; fi
echo "provider=" >"$tmp/profiles/vulcain"
expect "chat: no provider yet: menu first" 0 "Which model for vulcain\?" -- ch --dry-run <<<''
expect "chat: then the chat" 0 "hermes auth add openai-codex"$'\n'".*"$'\n'".*"$'\n'"\+ runuser --pty -u vulcain" -- ch --dry-run <<<''
expect "chat: needs a terminal" 1 "ssh -t" -- ch
expect "help mentions the chat" 0 "Vulcain" -- "$cli" help
rm -f "$tmp/profiles/vulcain"

# doctor: runuser/stat/git/curl stubbed; STUB_* vars inject failures.
cat >"$tmp/stub/runuser" <<'EOF'
#!/bin/sh
# runuser -u A -- test -r PATH: A reads its own home, or a home in STUB_LEAK.
u=$2; f=$6
case "$f" in "$STUB_HR/$u/"*) exit 0 ;; esac
[ -n "${STUB_LEAK:-}" ] && case "$f" in "$STUB_HR/$STUB_LEAK/"*) exit 0 ;; esac
exit 1
EOF
cat >"$tmp/stub/stat" <<'EOF'
#!/bin/sh
f=$3; u=${f#"$STUB_HR/"}; u=${u%%/*}
case "$f" in
  */.env) echo "$u:$u ${STUB_ENV_MODE:-600}" ;;
  *) echo "$u:$u 700" ;;
esac
EOF
cat >"$tmp/stub/git" <<'EOF'
#!/bin/sh
case "$*" in
  *rev-parse*) echo "${STUB_HEAD:-f97608f000000000000000000000000000000000}" ;;
  ls-remote*) printf 'f97608f000000000000000000000000000000000\trefs/tags/v2026.9.24^{}\n' ;;
esac
EOF
cat >"$tmp/stub/curl" <<'EOF'
#!/bin/sh
[ -z "${STUB_HONCHO_DOWN:-}" ]
EOF
chmod +x "$tmp/stub/"*
# dr [VAR=value...] [name]: doctor against the fake homes and stubs.
dr() { local e=(); while [[ ${1:-} == *=* ]]; do e+=("$1"); shift; done; env STUB_HR="$hr" USINE_CONFIG="$lcfg" PATH="$tmp/stub:$PATH" "${e[@]}" "$cli" doctor --dry-run "$@"; }
expect "doctor: whole setup fails on empty token" 1 "^alpha +token +FAIL" -- dr
expect "doctor: hermes at pinned sha" 0 "^hermes +ok" -- dr delta
expect "doctor: honcho healthy" 0 "^honcho +ok" -- dr delta
expect "doctor: unit loaded and active" 0 "^delta +unit +ok" -- dr delta
expect "doctor: drop-in present" 0 "^delta +drop-in +ok" -- dr delta
expect "doctor: token set" 0 "^delta +token +ok" -- dr delta
expect "doctor: home owner and mode" 0 "^delta +home +ok" -- dr delta
expect "doctor: .env owner and mode" 0 "^delta +env +ok" -- dr delta
expect "doctor: cannot read other profile" 0 "^delta +cannot-read-beta +ok" -- dr delta
expect "doctor: other profile cannot read it" 0 "^beta +cannot-read-delta +ok" -- dr delta
if dr delta 2>&1 | grep -cE >/dev/null "^(alpha|beta|gamma) +(unit|token|home|reads-own-env)"; then ko "doctor <name>: one profile only"; else ok "doctor <name>: one profile only"; fi
if dr 2>&1 | grep -cE >/dev/null "tok\.|sk-or"; then ko "doctor: secrets never printed"; else ok "doctor: secrets never printed"; fi
expect "doctor: readable .env of another profile fails" 1 "^alpha +cannot-read-delta +FAIL" -- dr STUB_LEAK=delta delta
expect "doctor: hermes off pin fails" 1 "^hermes +FAIL" -- dr STUB_HEAD=deadbeef delta
expect "doctor: honcho down fails" 1 "^honcho +FAIL" -- dr STUB_HONCHO_DOWN=1 delta
expect "doctor: loose .env mode fails" 1 "^delta +env +FAIL" -- dr STUB_ENV_MODE=644 delta
sed 's/^honcho:.*/honcho: false/' "$lcfg" >"$tmp/life-nohoncho.yaml"
expect "doctor: honcho skipped when disabled" 0 "" -- dr STUB_HONCHO_DOWN=1 USINE_CONFIG="$tmp/life-nohoncho.yaml" delta
expect "doctor: unmanaged profile refused" 1 "not a managed profile" -- dr stranger
if [[ $EUID -ne 0 ]]; then
  expect "doctor: non-root refused" 1 "must run as root" -- env USINE_CONFIG="$lcfg" "$cli" doctor
fi

# Honcho (on in the example config): Docker from the official repo + compose stack.
nocfg="$root/usine.example.yaml"
bsn() { env USINE_CONFIG="$nocfg" "$cli" bootstrap --dry-run; }
expect "bootstrap: Docker apt repo key" 0 "download\.docker\.com/linux/.*/gpg" -- bs
expect "bootstrap: Docker official repo listed" 0 "write /etc/apt/sources\.list\.d/docker\.list" -- bs
expect "bootstrap: Docker packages" 0 "apt-get install -y docker-ce docker-ce-cli containerd\.io docker-compose-plugin" -- bs
expect "bootstrap: Docker enabled at boot" 0 "systemctl enable --now docker" -- bs
expect "bootstrap: Honcho compose installed" 0 "/opt/usine-hermes/honcho/docker-compose\.yml" -- bs
expect "bootstrap: Honcho .env root 600" 0 \
  "write /opt/usine-hermes/honcho/\.env \(mode 600, owner root:root\)" -- bs
if [[ -z $(bs 2>&1 >/dev/null) ]]; then ok "bootstrap: asks nothing (shared key)"; else ko "bootstrap: asks nothing (shared key)"; fi
expect "bootstrap: Honcho key from the shared key file" 0 "# Honcho key: $tmp/ex/openrouter\.key" -- bs
expect "bootstrap: Honcho up -d" 0 "docker compose -f /opt/usine-hermes/honcho/docker-compose\.yml up -d" -- bs
expect "bootstrap: waits for Honcho health" 0 "http://127\.0\.0\.1:8000/health" -- bs
if bs 2>&1 | grep -cE >/dev/null "LLM_OPENAI_API_KEY=|POSTGRES_PASSWORD="; then ko "bootstrap: Honcho secrets not printed"; else ok "bootstrap: Honcho secrets not printed"; fi
if bsn 2>&1 | grep -cE >/dev/null "docker|/opt/usine-hermes"; then ko "bootstrap: honcho false skips Docker/Honcho"; else ok "bootstrap: honcho false skips Docker/Honcho"; fi
expect "bootstrap: honcho false still installs Hermes" 0 "hermes-agent" -- bsn
c="$root/templates/honcho-compose.yml"
expect "compose: pinned Honcho image" 0 "image: ghcr\.io/plastic-labs/honcho:v3\.2\.2" -- cat "$c"
expect "compose: api only on loopback" 0 "127\.0\.0\.1:8000:8000" -- cat "$c"
if grep -E '^ *- "?[0-9.:]*[0-9]+:[0-9]+"?$' "$c" | grep -v '127\.0\.0\.1:8000:8000' | grep -c >/dev/null .; then ko "compose: no other published port"; else ok "compose: no other published port"; fi
if grep -qE "mcp|HOST_AUTH_METHOD|postgres:postgres@" "$c"; then ko "compose: no mcp, trust or default password"; else ok "compose: no mcp, trust or default password"; fi
expect "compose: generated db password wired" 0 "postgres:\\$\{POSTGRES_PASSWORD" -- cat "$c"
expect "compose: restarts after reboot" 0 "restart: unless-stopped" -- cat "$c"

# create wires Honcho memory only when enabled.
crn() { env USINE_CONFIG="$nocfg" "$cli" create ab --provider anthropic --dry-run; }
expect "create: Honcho workspace created" 0 "curl .*-X POST.*127\.0\.0\.1:8000/v3/workspaces" -- crf
expect "create: workspace id is the profile" 0 'id\\?":\\?"ab' -- crf
expect "create: honcho.json owned by profile" 0 \
  "write /var/lib/usine-hermes/ab/\.hermes/honcho\.json \(mode 600, owner ab:ab\)" -- crf
expect "create: honcho.json points at workspace" 0 '"workspace": *"ab"' -- crf
expect "create: honcho.json peer name" 0 '"peerName": *"owner"' -- crf
expect "create: memory provider set as profile" 0 \
  "runuser -u ab -- .*hermes config set memory\.provider honcho" -- crf
if crn 2>&1 | grep -ciE >/dev/null "honcho|workspaces"; then ko "create: honcho false skips memory"; else ok "create: honcho false skips memory"; fi
expect "bootstrap: uv reachable by profiles" 0 "install -m 755 /root/\.hermes/bin/uv /usr/local/bin/uv" -- bs

# Lint: every shell file must pass shellcheck.
if command -v shellcheck >/dev/null; then
  expect "shellcheck clean" 0 "" -- shellcheck "$root/install.sh" "$root/bin/usine-hermes" "$root/tests/test.sh"
else
  ko "shellcheck not installed"
fi

if [[ $fails -gt 0 ]]; then echo "$fails failure(s)"; exit 1; fi
echo "all tests passed"
