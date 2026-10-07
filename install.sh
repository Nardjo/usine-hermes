#!/usr/bin/env bash
# Install the usine-hermes CLI and its templates. Safe to re-run.
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
bin_dir=/usr/local/bin
share_dir=/usr/local/share/usine-hermes
os_release=${USINE_OS_RELEASE:-/etc/os-release}

die() {
  printf 'install.sh: %s\n' "$1" >&2
  exit 1
}

# shellcheck source=/dev/null
os=$( [[ -r $os_release ]] && . "$os_release" && echo "${ID:-} ${VERSION_ID:-}" ) || os=unknown
case $os in
  "ubuntu 24.04" | "debian 12" | "debian 13") ;;
  *) die "unsupported OS ($os): only Ubuntu 24.04, Debian 12 and Debian 13 are supported" ;;
esac

[[ $EUID -eq 0 ]] || die "must run as root (try: sudo ./install.sh)"

# Piped install (curl ... | sudo bash [-s -- --ref REF]): no repo next to us,
# so fetch the repo at REF and re-run its install.sh with the terminal as stdin.
if [[ ! -f $src/bin/usine-hermes ]]; then
  ref=main
  [[ ${1:-} == --ref && -n ${2:-} ]] && ref=$2
  [[ $ref =~ ^[A-Za-z0-9._/-]+$ ]] || die "invalid ref: $ref"
  # ponytail: the extracted copy stays in /tmp until reboot; harmless, no secrets.
  tmp=$(mktemp -d /tmp/usine-hermes.XXXXXX)
  curl -fsSL "https://codeload.github.com/Nardjo/usine-hermes/tar.gz/$ref" |
    tar -xz -C "$tmp" --strip-components=1 || die "cannot download usine-hermes at '$ref'"
  if [[ -r /dev/tty ]]; then exec bash "$tmp/install.sh" </dev/tty; fi
  exec bash "$tmp/install.sh"
fi

install -d -m 755 "$bin_dir" "$share_dir/templates"
install -m 755 "$src/bin/usine-hermes" "$bin_dir/usine-hermes"
shopt -s nullglob
for f in "$src"/templates/*; do
  install -m 644 "$f" "$share_dir/templates/"
done
install -D -m 644 "$src/skills/usine-hermes/SKILL.md" "$share_dir/skills/usine-hermes/SKILL.md"
[[ -f $src/usine.example.yaml ]] && install -m 644 "$src/usine.example.yaml" "$share_dir/"

echo "Installed $bin_dir/usine-hermes and $share_dir."

# First setup, re-runnable: init and Vulcain ask only what is not known yet.
cli=$bin_dir/usine-hermes
"$cli" init
"$cli" bootstrap
if [[ ! -f /etc/usine-hermes/profiles/vulcain ]]; then
  read -r -p "Installer Vulcain, l'agent qui crée les autres agents depuis Discord ? [O/n] " yn || yn=n
  [[ $yn == [nN]* ]] || "$cli" create vulcain --preset vulcain
fi
"$cli" doctor || true
