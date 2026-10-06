#!/usr/bin/env bash
# Dependency-free tests for the usine-hermes CLI (external behaviour only).
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cli="$root/bin/usine-hermes"
fails=0

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
expect "existing config kept on 'n'" 0 "kept" -- uc init <<<"n"
expect "kept config unchanged" 0 "^openrouter$" -- uc config default_provider
expect "overwrite on 'y' with answers" 0 "wrote" -- uc init <<<$'y\n/srv/usine\n\nanthropic\n123, 456\nfalse\njordan'
expect "answer home_root written" 0 "^/srv/usine$" -- uc config home_root
expect "empty answer keeps default" 0 "^v2026\.9\.24$" -- uc config hermes_version
expect "answer provider written" 0 "^anthropic$" -- uc config default_provider
expect "allowlist normalised" 0 "^123,456$" -- uc config discord_allowed_users
expect "answer honcho written" 0 "^false$" -- uc config honcho
expect "answer peer_name written" 0 "^jordan$" -- uc config peer_name
rm -f "$cfgf"
expect "init rejects unknown provider" 2 "provider" -- uc init <<<$'\n\nnope'
expect "init rejects bad allowlist" 2 "allowlist" -- uc init <<<$'\n\n\nabc'
expect "init rejects bad honcho" 2 "honcho" -- uc init <<<$'\n\n\n\nmaybe'
expect "rejected init writes nothing" 1 "usine-hermes init" -- uc config home_root

# Lint: every shell file must pass shellcheck.
if command -v shellcheck >/dev/null; then
  expect "shellcheck clean" 0 "" -- shellcheck "$root/install.sh" "$root/bin/usine-hermes" "$root/tests/test.sh"
else
  ko "shellcheck not installed"
fi

if [[ $fails -gt 0 ]]; then echo "$fails failure(s)"; exit 1; fi
echo "all tests passed"
