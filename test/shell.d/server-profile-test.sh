#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

INSTALL="$ROOT/install"

# --- profile helper resolution ---

resolve() {
  # Run the helper in a clean shell and print the profile it settles on.
  env "$@" OMARCHY_PROFILE_FILE=/nonexistent bash -c \
    'source "'"$INSTALL"'/helpers/profile.sh"; printf "%s" "$OMARCHY_PROFILE"'
}

[[ $(resolve OMARCHY_PROFILE=server) == "server" ]] ||
  fail "profile helper keeps an explicit server profile"
pass "profile helper keeps an explicit server profile"

[[ $(resolve -u OMARCHY_PROFILE) == "desktop" ]] ||
  fail "profile helper defaults to desktop when unset"
pass "profile helper defaults to desktop when unset"

[[ $(resolve OMARCHY_PROFILE=bogus) == "desktop" ]] ||
  fail "profile helper treats an unknown value as desktop"
pass "profile helper treats an unknown value as desktop"

profile_file=$(mktemp)
trap 'rm -f "$profile_file"' EXIT
echo server >"$profile_file"
got=$(env -u OMARCHY_PROFILE OMARCHY_PROFILE_FILE="$profile_file" bash -c \
  'source "'"$INSTALL"'/helpers/profile.sh"; printf "%s" "$OMARCHY_PROFILE"')
[[ $got == "server" ]] || fail "profile helper reads the profile marker file" "got: $got"
pass "profile helper reads the profile marker file"

# --- login branching ---

login_pick() {
  OMARCHY_PROFILE="$1" bash -c \
    'run_logged(){ printf "%s\n" "$1"; }; OMARCHY_INSTALL="'"$INSTALL"'"; source "$OMARCHY_INSTALL/login/all.sh"'
}

picked=$(login_pick server)
grep -q "login/headless.sh" <<<"$picked" || fail "server login runs the headless leaf"
if grep -q "login/sddm.sh" <<<"$picked"; then fail "server login does not run sddm"; fi
pass "server login runs the headless leaf, not sddm"

picked=$(login_pick desktop)
grep -q "login/sddm.sh" <<<"$picked" || fail "desktop login still runs sddm"
pass "desktop login still runs sddm"

grep -q "login/verbose-boot.sh" <<<"$(login_pick server)" || fail "server login runs the verbose-boot leaf"
if grep -q "login/verbose-boot.sh" <<<"$(login_pick desktop)"; then fail "desktop keeps the boot splash"; fi
pass "only the server swaps the boot splash for verbose boot"

# Run verbose-boot.sh against a scratch root and check the drop-ins it writes
# actually strip plymouth from HOOKS and end the cmdline on the verbose values.
boot_root=$(mktemp -d)
trap 'rm -f "$profile_file"; rm -rf "$boot_root"' EXIT
sed "s#/etc/#$boot_root/etc/#g" "$INSTALL/login/verbose-boot.sh" | bash ||
  fail "verbose-boot leaf runs"
hooks=$(bash -c 'source "$1"; source "$2"; printf "%s " "${HOOKS[@]}"' _ \
  "$ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf" \
  "$boot_root/etc/mkinitcpio.conf.d/omarchy_server_boot.conf")
if [[ " $hooks " == *" plymouth "* ]]; then fail "server initramfs drops the plymouth hook" "hooks: $hooks"; fi
[[ " $hooks " == *" encrypt "* && " $hooks " == *" btrfs-overlayfs "* ]] ||
  fail "server initramfs keeps the other hooks" "hooks: $hooks"
[[ omarchy_hooks.conf < omarchy_server_boot.conf ]] ||
  fail "server hooks drop-in sorts after omarchy_hooks.conf"
pass "server initramfs drops only the plymouth hook"

cmdline=$(cat "$ROOT/etc/limine-entry-tool.d/omarchy-defaults.conf" \
  "$boot_root/etc/limine-entry-tool.d/omarchy-server-boot.conf" |
  sed -n 's/^KERNEL_CMDLINE\[default\]+="\(.*\)"$/\1/p' | tr '\n' ' ')
last() { grep -o "$1=[^ ]*" <<<"$cmdline" | tail -1; }
[[ $(last loglevel) == "loglevel=4" ]] || fail "server cmdline ends on a visible loglevel" "cmdline: $cmdline"
[[ $(last systemd.show_status) == "systemd.show_status=auto" ]] || fail "server cmdline re-enables systemd status"
[[ $(last plymouth.enable) == "plymouth.enable=0" ]] || fail "server cmdline disables plymouth"
[[ omarchy-defaults.conf < omarchy-server-boot.conf ]] ||
  fail "server cmdline drop-in sorts after omarchy-defaults.conf"
pass "server cmdline overrides the quiet splash flags"

grep -Fq "systemctl set-default multi-user.target" "$INSTALL/login/headless.sh" ||
  fail "headless login boots to multi-user.target"
pass "headless login boots to multi-user.target"

# A newline in the username would inject directives into the getty drop-in.
if OMARCHY_INSTALL_USER=$'bob\nExecStartPre=/tmp/x' bash -c \
  'systemctl(){ :; }; install(){ echo "install $*"; }; source "'"$INSTALL"'/login/headless.sh"' >/dev/null 2>&1; then
  fail "headless login refuses an invalid autologin username"
fi
pass "headless login refuses an invalid autologin username"

# --- service enablement branching ---

services() {
  OMARCHY_PROFILE="$1" bash -c \
    'systemctl(){ printf "systemctl %s\n" "$*"; }; source "'"$INSTALL"'/config/enable-services.sh"'
}

srv=$(services server)
grep -q "systemctl enable sshd.service" <<<"$srv" || fail "server enables sshd"
if grep -q "sddm.service" <<<"$srv"; then fail "server does not enable sddm"; fi
grep -q "systemctl enable avahi-daemon.service" <<<"$srv" || fail "server enables avahi for .local names"
if grep -qE "cups|power-profiles" <<<"$srv"; then fail "server does not enable cups or power-profiles"; fi
pass "server enables sshd and avahi, not sddm/cups/power-profiles"

dsk=$(services desktop)
grep -q "systemctl enable sddm.service" <<<"$dsk" || fail "desktop still enables sddm"
if grep -q "sshd.service" <<<"$dsk"; then fail "desktop does not enable sshd here"; fi
pass "desktop enables sddm and not sshd"

# --- user setup branching (delayed packages kept on both) ---

user_steps() {
  OMARCHY_PROFILE="$1" bash -c \
    'run_logged(){ printf "%s\n" "$1"; }; OMARCHY_INSTALL="'"$INSTALL"'"; source "$OMARCHY_INSTALL/user/all.sh"'
}

steps=$(user_steps server)
grep -q "user/mise.sh" <<<"$steps" || fail "server runs the mise delayed-package setup"
grep -q "user/git.sh" <<<"$steps" || fail "server runs git setup"
for desktop_leaf in theme.sh chromium.sh xcompose.sh default-keyring.sh; do
  if grep -q "user/$desktop_leaf" <<<"$steps"; then fail "server skips desktop leaf $desktop_leaf"; fi
done
pass "server user setup keeps mise/git and skips desktop leaves"

steps=$(user_steps desktop)
grep -q "user/theme.sh" <<<"$steps" || fail "desktop still runs theme setup"
grep -q "user/mise.sh" <<<"$steps" || fail "desktop still runs mise setup"
pass "desktop user setup runs the full leaf set"

# --- server package manifest ---

manifest="$INSTALL/omarchy-server.packages"
pkgs=$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$manifest")
for want in openssh mise-bin git docker linux starship btrfs-progs \
  avahi nss-mdns rsync smartmontools lm_sensors herdr qemu-user-static-binfmt; do
  grep -qxF "$want" <<<"$pkgs" || fail "server manifest includes $want"
done
for unwanted in hyprland sddm chromium linux-omarchy nvidia-dkms libsecret; do
  if grep -qxF "$unwanted" <<<"$pkgs"; then fail "server manifest excludes $unwanted"; fi
done
pass "server manifest keeps the CLI/server core and drops the desktop stack"

# --- firewall branching ---

firewall() {
  # Record ufw calls; stub the ufw-docker installer (readonly, so the script's
  # own definition cannot replace it) and the live ufw.conf edit.
  OMARCHY_PROFILE="$1" bash -c '
    ufw(){ printf "ufw %s\n" "$*"; }
    systemctl(){ :; }
    sed(){ :; }
    install_ufw_docker_rules(){ :; }
    readonly -f install_ufw_docker_rules
    source "'"$INSTALL"'/config/firewall.sh"' 2>/dev/null
}

fw=$(firewall server)
grep -qx "ufw allow ssh" <<<"$fw" || fail "server firewall allows ssh"
if grep -q "53317" <<<"$fw"; then fail "server firewall does not open LocalSend"; fi
pass "server firewall allows ssh and skips LocalSend"

fw=$(firewall desktop)
grep -q "ufw allow 53317/tcp" <<<"$fw" || fail "desktop firewall still opens LocalSend"
if grep -qx "ufw allow ssh" <<<"$fw"; then fail "desktop firewall does not open ssh"; fi
pass "desktop firewall opens LocalSend and not ssh"
