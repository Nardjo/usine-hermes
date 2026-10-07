#!/usr/bin/env bash
# Install the usine-hermes CLI and its templates. Safe to re-run.
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
bin_dir=/usr/local/bin
share_dir=/usr/local/share/usine-hermes
os_release=${USINE_OS_RELEASE:-/etc/os-release}

# Operator language before init: USINE_LANG, then an existing config, default en.
lang=${USINE_LANG:-$(awk -F': *' '$1 == "lang" { print $2 }' /etc/usine-hermes/usine.yaml 2>/dev/null || true)}

# t <english> <french>: print the one in the operator's language.
t() { if [[ $lang == fr ]]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }

die() {
  printf 'install.sh: %s\n' "$1" >&2
  exit 1
}

# shellcheck source=/dev/null
os=$( [[ -r $os_release ]] && . "$os_release" && echo "${ID:-} ${VERSION_ID:-}" ) || os=unknown
case $os in
  "ubuntu 24.04" | "debian 12" | "debian 13") ;;
  *) die "$(t "unsupported OS ($os): only Ubuntu 24.04, Debian 12 and Debian 13 are supported" \
    "OS non pris en charge ($os) : seuls Ubuntu 24.04, Debian 12 et Debian 13 le sont")" ;;
esac

[[ $EUID -eq 0 ]] || die "$(t "must run as root (try: sudo ./install.sh)" "doit être lancé en root (essaie : sudo ./install.sh)")"

# Piped install (curl ... | sudo bash [-s -- --ref REF]): no repo next to us,
# so fetch the repo at REF and re-run its install.sh with the terminal as stdin.
if [[ ! -f $src/bin/usine-hermes ]]; then
  ref=main
  [[ ${1:-} == --ref && -n ${2:-} ]] && ref=$2
  [[ $ref =~ ^[A-Za-z0-9._/-]+$ ]] || die "$(t "invalid ref: $ref" "ref invalide : $ref")"
  # ponytail: the extracted copy stays in /tmp until reboot; harmless, no secrets.
  tmp=$(mktemp -d /tmp/usine-hermes.XXXXXX)
  curl -fsSL "https://codeload.github.com/Nardjo/usine-hermes/tar.gz/$ref" |
    tar -xz -C "$tmp" --strip-components=1 ||
    die "$(t "cannot download usine-hermes at '$ref'" "impossible de télécharger usine-hermes à '$ref'")"
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

t "Installed $bin_dir/usine-hermes and $share_dir." "Installé : $bin_dir/usine-hermes et $share_dir."

# First setup, re-runnable: init and Vulcain ask only what is not known yet.
cli=$bin_dir/usine-hermes
"$cli" init
# init may just have asked the language.
lang=${USINE_LANG:-$("$cli" config lang)}
"$cli" bootstrap
if [[ ! -f /etc/usine-hermes/profiles/vulcain ]]; then
  read -r -p "$(t "Install Vulcain, the agent that creates the other agents from Discord? [Y/n]" \
    "Installer Vulcain, l'agent qui crée les autres agents depuis Discord ? [O/n]") " yn || yn=n
  [[ $yn == [nN]* ]] || "$cli" create vulcain --preset vulcain
fi
# One clear next step instead of a full doctor report (run `usine-hermes doctor` for that).
# (create already said whether Vulcain is connected or how to start it.)
if [[ -f /etc/usine-hermes/profiles/vulcain ]]; then
  t "✓ Installed." "✓ Installé."
else
  t "✓ Installed. Create your first agent: sudo usine-hermes create <name>" "✓ Installé. Crée ton premier agent : sudo usine-hermes create <nom>"
fi
