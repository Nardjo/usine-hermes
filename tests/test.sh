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

# Lint: every shell file must pass shellcheck.
if command -v shellcheck >/dev/null; then
  expect "shellcheck clean" 0 "" -- shellcheck "$root/install.sh" "$root/bin/usine-hermes" "$root/tests/test.sh"
else
  ko "shellcheck not installed"
fi

if [[ $fails -gt 0 ]]; then echo "$fails failure(s)"; exit 1; fi
echo "all tests passed"
