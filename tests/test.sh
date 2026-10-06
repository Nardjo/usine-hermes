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
expect "no args shows help" 0 "Usage" -- "$cli"
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
osr() { printf 'ID=%s\nVERSION_ID="%s"\n' "$1" "$2" >"$tmp/$1-$2"; echo "$tmp/$1-$2"; }
expect "install: missing os-release refused" 1 "unsupported OS" -- \
  env USINE_OS_RELEASE="$tmp/nope" "$BASH" "$root/install.sh"
for v in "fedora 40" "ubuntu 22.04" "debian 11"; do
  read -r id ver <<<"$v"
  expect "install: $v refused" 1 "unsupported OS" -- \
    env USINE_OS_RELEASE="$(osr "$id" "$ver")" "$BASH" "$root/install.sh"
done
if [[ $EUID -ne 0 ]]; then
  for v in "ubuntu 24.04" "debian 12"; do
    read -r id ver <<<"$v"
    expect "install: $v accepted, non-root refused" 1 "must run as root" -- \
      env USINE_OS_RELEASE="$(osr "$id" "$ver")" "$BASH" "$root/install.sh"
  done
fi

# init + config: USINE_CONFIG points at a non-root path.
cfgf="$tmp/etc/usine.yaml"
uc() { env USINE_CONFIG="$cfgf" "$cli" "$@"; }
expect "config without file points to init" 1 "usine-hermes init" -- uc config home_root
expect "init --dry-run prints the config" 0 "write $cfgf" -- uc init --dry-run </dev/null
if [[ -e $cfgf ]]; then ko "init --dry-run writes nothing"; else ok "init --dry-run writes nothing"; fi
expect "init with defaults (empty input)" 0 "wrote" -- uc init </dev/null
expect "config reads home_root default" 0 "^/var/lib/usine-hermes$" -- uc config home_root
expect "config reads pinned hermes_version" 0 "^v2026\.9\.24$" -- uc config hermes_version
expect "config reads default_provider" 0 "^openrouter$" -- uc config default_provider
expect "config reads per-provider model" 0 "^z-ai/glm-5\.2$" -- uc config model_openrouter
expect "config reads dashed provider model" 0 "^sonnet$" -- uc config model_claude_subscription_directsdk_experimental
expect "config reads honcho default" 0 "^true$" -- uc config honcho
expect "config reads honcho_url" 0 "^http://127\.0\.0\.1:8000$" -- uc config honcho_url
expect "config unknown key fails" 1 "unknown config key" -- uc config nope
if grep -qiE "key|token|secret|password" <(grep -v '^#' "$cfgf" | cut -d: -f1); then ko "config holds no secret keys"; else ok "config holds no secret keys"; fi
keys() { grep -E '^[a-z_]+:' "$1" | cut -d: -f1 | sort; }
if [[ "$(keys "$cfgf")" == "$(keys "$root/usine.example.yaml")" ]]; then ok "example has same keys as init"; else ko "example has same keys as init"; fi
expect "config reads example via USINE_CONFIG" 0 "^gpt-6-sol$" -- \
  env USINE_CONFIG="$root/usine.example.yaml" "$cli" config model_openai_api
# Loaded config is validated too (it feeds sed, honcho.json and rm -rf paths).
badc() { sed "s#^$1:.*#$1: $2#" "$root/usine.example.yaml" >"$tmp/bad.yaml"; env USINE_CONFIG="$tmp/bad.yaml" "$cli" "${@:3}"; }
expect "load rejects bad home_root" 2 "invalid home_root" -- badc home_root "/srv/a b" config peer_name
expect "load rejects bad honcho_url" 2 "invalid honcho_url" -- badc honcho_url 'http://x/"' create ab --dry-run
expect "load accepts https honcho_url" 0 "" -- badc honcho_url "https://honcho.example:8443" config honcho_url
expect "load rejects bad allowlist" 2 "invalid discord_allowed_users" -- badc discord_allowed_users "1;2" config honcho
expect "load rejects bad hermes_version" 2 "invalid hermes_version" -- badc hermes_version "v1|x" bootstrap --dry-run
expect "load rejects bad peer_name" 2 "invalid peer_name" -- badc peer_name '"x' config honcho
expect "existing config kept on 'n'" 0 "kept" -- uc init <<<"n"
expect "kept config unchanged" 0 "^openrouter$" -- uc config default_provider
expect "overwrite on 'y' with answers" 0 "wrote" -- uc init <<<$'y\n/srv/usine\n\nanthropic\n123, 456\nfalse\njordan'
expect "answer home_root written" 0 "^/srv/usine$" -- uc config home_root
expect "empty answer keeps default" 0 "^v2026\.9\.24$" -- uc config hermes_version
expect "answer provider written" 0 "^anthropic$" -- uc config default_provider
expect "allowlist normalised" 0 "^123,456$" -- uc config discord_allowed_users
expect "answer honcho written" 0 "^false$" -- uc config honcho
expect "answer peer_name written" 0 "^jordan$" -- uc config peer_name
# A rewrite replaces the file: never writes through a link to another file.
echo keep >"$tmp/other"; ln -f "$tmp/other" "$cfgf"
uc init <<<"y" >/dev/null 2>&1
if [[ $(cat "$tmp/other") == keep ]]; then ok "init never writes through a link"; else ko "init never writes through a link"; fi
rm -f "$cfgf"
expect "init rejects unknown provider" 2 "provider" -- uc init <<<$'\n\nnope'
expect "init rejects bad allowlist" 2 "allowlist" -- uc init <<<$'\n\n\nabc'
expect "init rejects bad honcho" 2 "honcho" -- uc init <<<$'\n\n\n\nmaybe'
expect "init rejects relative home_root" 2 "home_root" -- uc init <<<$'var/lib'
expect "init rejects / as home_root" 2 "home_root" -- uc init <<<$'/'
expect "init rejects .. in home_root" 2 "home_root" -- uc init <<<$'/var/../etc'
expect "init rejects odd chars in home_root" 2 "home_root" -- uc init <<<$'/var/lib|x'
expect "init rejects bad hermes_version" 2 "hermes_version" -- uc init <<<$'\nmain;rm'
expect "init rejects bad peer_name" 2 "peer_name" -- uc init <<<$'\n\n\n\n\na"b'
expect "rejected init writes nothing" 1 "usine-hermes init" -- uc config home_root

# bootstrap --dry-run: planned Hermes install, no root, no network.
bs() { env USINE_CONFIG="$root/usine.example.yaml" "$cli" bootstrap --dry-run; }
expect "bootstrap: apt prereqs" 0 "apt-get install -y .*git.*curl" -- bs
expect "bootstrap: tag resolved via ls-remote" 0 \
  "git ls-remote https://github.com/NousResearch/hermes-agent .*refs/tags/v2026\.9\.24" -- bs
expect "bootstrap: installer fetched at the resolved sha" 0 \
  "raw\.githubusercontent\.com/NousResearch/hermes-agent/\\\\?<sha-of-v2026\.9\.24\\\\?>/scripts/install\.sh" -- bs
if bs 2>&1 | grep -c >/dev/null "hermes-agent/v2026"; then ko "bootstrap: installer not fetched by tag"; else ok "bootstrap: installer not fetched by tag"; fi
expect "bootstrap: installer pinned and non-interactive" 0 \
  "--commit \\\\?<sha-of-v2026\.9\.24\\\\?> --non-interactive --skip-browser --skip-computer-use" -- bs
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

# create --dry-run: full plan, no root, no secret prompt, nothing started.
cr() { env USINE_CONFIG="$root/usine.example.yaml" "$cli" create "$@" --dry-run; }
crf() { cr ab --personality "dry wit" --mission "watch the logs" --provider anthropic; }
expect "create: system nologin user + own group" 0 \
  "useradd --system --user-group --home-dir /var/lib/usine-hermes/ab --no-create-home --shell /usr/sbin/nologin ab" -- crf
expect "create: private home 700 owned by profile" 0 "install -d -m 700 -o ab -g ab /var/lib/usine-hermes/ab" -- crf
# Root-owned registry next to the config (here the repo root), right after useradd.
expect "create: ownership marker in root registry" 0 "install -m 644 -o root -g root /dev/null $root/profiles/ab$" -- crf
if crf 2>&1 | grep -A2 "useradd" | grep -c >/dev/null "profiles/ab$"; then ok "create: marker right after useradd"; else ko "create: marker right after useradd"; fi
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
expect "create: says not started" 0 "not started" -- crf
if crf 2>&1 | grep -cE >/dev/null "systemctl (enable|start)"; then ko "create: never enables/starts"; else ok "create: never enables/starts"; fi
if crf 2>&1 | grep -cE >/dev/null "^\| .*(DISCORD_BOT_TOKEN|API_KEY)"; then ko "create: .env content not printed"; else ok "create: .env content not printed"; fi
expect "create: prompts menu with defaults (no flags)" 0 "model\.provider openrouter" -- cr ab
expect "create: menu accepts a number" 0 "model\.provider xai" -- cr ab <<<"6"
expect "create: unknown provider rejected" 2 "unknown provider" -- cr ab --provider nope
# Subscription providers: warning, y/N login as the profile user, or a follow-up command.
sub() { cr ab --personality p --mission m --provider "$@"; }
claude="claude-subscription-directsdk-experimental"
# Missing --mission keeps it interactive: Enter for the mission, then the login answer.
subi() { cr ab --personality p --provider "$@"; }
expect "sub: claude warns experimental" 0 "1\.7x" -- sub $claude
expect "sub: codex warns quota" 0 "quota" -- sub openai-codex
expect "sub: supergrok warns 403" 0 "403" -- sub xai-oauth
expect "sub: claude provider set" 0 "hermes config set model\.provider $claude" -- sub $claude
expect "sub: claude model from config" 0 "hermes config set model\.default sonnet" -- sub $claude
expect "sub: claude CLI installed as profile" 0 "runuser -u ab -- .*claude\.ai/install\.sh" -- sub $claude
expect "sub: plugin installed as profile" 0 \
  "runuser -u ab -- .*hermes plugins install claude-subscription-directsdk" -- sub $claude
expect "sub: claude login as profile on y" 0 "^\+ runuser -u ab -- .*HOME=/var/lib/usine-hermes/ab .*claude auth login" -- subi $claude <<<$'\ny'
expect "sub: codex login as profile on y" 0 "^\+ runuser -u ab -- .*hermes auth add openai-codex" -- subi openai-codex <<<$'\ny'
expect "sub: supergrok login as profile on y" 0 "^\+ runuser -u ab -- .*hermes auth add xai-oauth" -- subi xai-oauth <<<$'\ny'
expect "sub: skip prints follow-up command" 0 "later.*" -- sub openai-codex
expect "sub: follow-up is the login as profile" 0 "^ *sudo runuser -u ab -- .*hermes auth add openai-codex" -- sub openai-codex
if sub openai-codex 2>&1 | grep -c >/dev/null "^+ .*auth add"; then ko "sub: skip runs no login"; else ok "sub: skip runs no login"; fi
if sub $claude 2>&1 | grep -cE >/dev/null "_API_KEY"; then ko "sub: no API key asked or written"; else ok "sub: no API key asked or written"; fi
expect "sub: menu offers subscriptions" 0 "openai-codex" -- cr ab --personality p --mission m <<<"5"
expect "sub: unit PATH finds the profile's claude CLI" 0 "^\| Environment=PATH=/var/lib/usine-hermes/ab/\.local/bin:" -- sub $claude
# All flags + stdin not a TTY (tests run on /dev/null): no prompt at all.
if crf 2>&1 | grep -cE >/dev/null "would ask|\[.*\]: "; then ko "create: all flags, no TTY: no prompt"; else ok "create: all flags, no TTY: no prompt"; fi
if sub openai-codex 2>&1 | grep -c >/dev/null "Log in now"; then ko "create: no TTY: no login prompt"; else ok "create: no TTY: no login prompt"; fi
expect "create: next step sets the API key" 0 "sudo usine-hermes secret ab ANTHROPIC_API_KEY" -- crf
expect "create: next step sets the Discord token" 0 "sudo usine-hermes secret ab DISCORD_BOT_TOKEN" -- crf
if sub openai-codex 2>&1 | grep -c >/dev/null "secret ab .*_API_KEY"; then ko "create: no key step for subscriptions"; else ok "create: no key step for subscriptions"; fi
expect "create: missing flag still asks secrets" 0 "would ask \(hidden\)" -- cr ab --provider anthropic
expect "create: unknown flag rejected" 2 "unknown flag" -- cr ab --nope x
expect "create: existing non-managed user refused" 1 "non-managed" -- cr root --provider anthropic
if [[ $EUID -ne 0 ]]; then
  expect "create: non-root refused" 1 "must run as root" -- \
    env USINE_CONFIG="$root/usine.example.yaml" "$cli" create ab --provider anthropic </dev/null
fi

# Lifecycle against a fake home_root; systemctl/journalctl stubbed on PATH.
hr="$tmp/homes"; lcfg="$tmp/life.yaml"
sed "s|^home_root:.*|home_root: $hr|" "$root/usine.example.yaml" >"$lcfg"
mkprof() { mkdir -p "$hr/$1/.hermes" "$tmp/profiles"; : >"$tmp/profiles/$1"; printf 'DISCORD_BOT_TOKEN=%s\nOPENROUTER_API_KEY=%s\n' "$2" "$3" >"$hr/$1/.hermes/.env"; }
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
  is-active*) echo active ;;
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
expect "secret: hidden prompt names key and profile" 0 "DISCORD_BOT_TOKEN for delta \(hidden" -- sec delta DISCORD_BOT_TOKEN new.token.123456
expect "secret: .env rewritten 600 owned by profile" 0 \
  "write $hr/delta/\.hermes/\.env \(mode 600, owner delta:delta\)" -- sec delta DISCORD_BOT_TOKEN new.token.123456
expect "secret: replaces an existing key" 0 "^# \.env keys: OPENROUTER_API_KEY DISCORD_BOT_TOKEN$" -- sec delta DISCORD_BOT_TOKEN new.token.123456
expect "secret: appends a missing key" 0 "^# \.env keys: DISCORD_BOT_TOKEN OPENROUTER_API_KEY XAI_API_KEY$" -- sec alpha XAI_API_KEY xai-new-secret
if sec delta OPENROUTER_API_KEY sk-or-new-secret 2>&1 | grep -cE >/dev/null "sk-or-|tok\.delta"; then ko "secret: values never printed"; else ok "secret: values never printed"; fi
expect "secret: empty value refused" 1 "empty" -- sec delta DISCORD_BOT_TOKEN ""
expect "secret: restart hint when active" 0 "usine-hermes restart delta" -- sec delta DISCORD_BOT_TOKEN new.token.123456
if grep -q "^DISCORD_BOT_TOKEN=tok.delta" "$hr/delta/.hermes/.env"; then ok "secret: dry-run writes nothing"; else ko "secret: dry-run writes nothing"; fi
if [[ $EUID -ne 0 ]]; then
  expect "secret: non-root refused" 1 "must run as root" -- lc secret delta DISCORD_BOT_TOKEN <<<x
fi

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
nocfg="$tmp/nohoncho.yaml"
sed "s|^honcho:.*|honcho: false|" "$root/usine.example.yaml" >"$nocfg"
bsn() { env USINE_CONFIG="$nocfg" "$cli" bootstrap --dry-run; }
expect "bootstrap: Docker apt repo key" 0 "download\.docker\.com/linux/.*/gpg" -- bs
expect "bootstrap: Docker official repo listed" 0 "write /etc/apt/sources\.list\.d/docker\.list" -- bs
expect "bootstrap: Docker packages" 0 "apt-get install -y docker-ce docker-ce-cli containerd\.io docker-compose-plugin" -- bs
expect "bootstrap: Docker enabled at boot" 0 "systemctl enable --now docker" -- bs
expect "bootstrap: Honcho compose installed" 0 "/opt/usine-hermes/honcho/docker-compose\.yml" -- bs
expect "bootstrap: Honcho .env root 600" 0 \
  "write /opt/usine-hermes/honcho/\.env \(mode 600, owner root:root\)" -- bs
expect "bootstrap: Honcho key asked hidden, not in dry-run" 0 "would ask \(hidden\).*OpenRouter" -- bs
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
