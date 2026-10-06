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

install -d -m 755 "$bin_dir" "$share_dir/templates"
install -m 755 "$src/bin/usine-hermes" "$bin_dir/usine-hermes"
shopt -s nullglob
for f in "$src"/templates/*; do
  install -m 644 "$f" "$share_dir/templates/"
done
install -D -m 644 "$src/skills/usine-hermes/SKILL.md" "$share_dir/skills/usine-hermes/SKILL.md"
[[ -f $src/usine.example.yaml ]] && install -m 644 "$src/usine.example.yaml" "$share_dir/"

echo "Installed $bin_dir/usine-hermes and $share_dir."

# Offer to chain into the first setup; Enter means yes.
for step in init bootstrap; do
  read -r -p "Run 'usine-hermes $step' now? [Y/n] " yn || yn=n
  if [[ $yn == [nN]* ]]; then
    echo "Next: sudo usine-hermes init && sudo usine-hermes bootstrap"
    exit 0
  fi
  "$bin_dir/usine-hermes" "$step"
done
