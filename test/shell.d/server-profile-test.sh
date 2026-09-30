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

# Model limine-entry-tool: drop-ins load in name order, and each addition is
# placed before the ones loaded earlier (so /etc/default/limine's root= leads
# the real cmdline). Reversing the additions in load order gives the cmdline.
cp "$ROOT/etc/limine-entry-tool.d/omarchy-defaults.conf" "$boot_root/etc/limine-entry-tool.d/"
cmdline=$(for conf in "$boot_root"/etc/limine-entry-tool.d/*.conf; do cat "$conf"; done |
  sed -n 's/^KERNEL_CMDLINE\[default\]+="\(.*\)"$/\1/p' | tac | tr '\n' ' ')
last() { grep -o "$1=[^ ]*" <<<"$cmdline" | tail -1; }
[[ $(last loglevel) == "loglevel=4" ]] || fail "server cmdline ends on a visible loglevel" "cmdline: $cmdline"
[[ $(last systemd.show_status) == "systemd.show_status=auto" ]] || fail "server cmdline re-enables systemd status"
[[ $(last plymouth.enable) == "plymouth.enable=0" ]] || fail "server cmdline disables plymouth"
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

# --- system config leaves ---

config_steps() {
  OMARCHY_PROFILE="$1" bash -c \
    'run_logged(){ printf "%s\n" "$1"; }; OMARCHY_INSTALL="'"$INSTALL"'"; source "$OMARCHY_INSTALL/config/all.sh"'
}

steps=$(config_steps server)
grep -q "config/increase-lockout-limit.sh" <<<"$steps" || fail "server keeps the faillock limit"
for desktop_leaf in theme-system.sh browser-policy.sh lockscreen-pam.sh; do
  if grep -q "config/$desktop_leaf" <<<"$steps"; then fail "server skips desktop config leaf $desktop_leaf"; fi
done
pass "server config keeps faillock and skips desktop leaves"

steps=$(config_steps desktop)
for desktop_leaf in theme-system.sh browser-policy.sh lockscreen-pam.sh; do
  grep -q "config/$desktop_leaf" <<<"$steps" || fail "desktop still runs $desktop_leaf"
done
pass "desktop config runs the desktop leaves"

# A server has no sddm, so /etc/pam.d/sddm-autologin must not be touched.
lockout_targets() {
  OMARCHY_PROFILE="$1" bash -c \
    'sed(){ printf "%s\n" "${@: -1}"; }; source "'"$INSTALL"'/config/increase-lockout-limit.sh"'
}
if grep -q "sddm-autologin" <<<"$(lockout_targets server)"; then
  fail "server faillock leaves sddm-autologin alone"
fi
grep -q "system-auth" <<<"$(lockout_targets server)" || fail "server faillock still edits system-auth"
grep -q "sddm-autologin" <<<"$(lockout_targets desktop)" || fail "desktop faillock still edits sddm-autologin"
pass "faillock edits sddm-autologin on desktop only"

# --- hardware leaves ---

hardware_steps() {
  OMARCHY_PROFILE="$1" bash -c \
    'run_logged(){ printf "%s\n" "$1"; }; OMARCHY_INSTALL="'"$INSTALL"'"; source "$OMARCHY_INSTALL/hardware/all.sh"'
}

steps=$(hardware_steps server)
for leaf in nvidia.sh bluetooth.sh vulkan.sh intel/video-acceleration.sh; do
  grep -q "hardware/$leaf" <<<"$steps" || fail "server runs hardware-detected leaf $leaf"
done
if grep -q "hardware/speaker-tuning.sh" <<<"$steps"; then fail "server skips speaker tuning (no audio stack)"; fi
pass "server runs the hardware-detected driver leaves and skips speaker tuning"

steps=$(hardware_steps desktop)
for desktop_leaf in bluetooth.sh vulkan.sh intel/video-acceleration.sh speaker-tuning.sh; do
  grep -q "hardware/$desktop_leaf" <<<"$steps" || fail "desktop still runs $desktop_leaf"
done
pass "desktop hardware runs the full leaf set"

grep -Fq 'source "$OMARCHY_INSTALL/helpers/profile.sh"' "$ROOT/bin/omarchy-apply-hardware" ||
  fail "omarchy-apply-hardware resolves the profile when run on its own"
pass "omarchy-apply-hardware resolves the profile"

# Print the packages nvidia.sh would add for a profile and GSP support.
nvidia_packages() {
  local etc_root
  etc_root=$(mktemp -d)
  sed "s#/etc/#$etc_root/etc/#g" "$INSTALL/hardware/nvidia.sh" |
    OMARCHY_PROFILE="$1" GSP="$2" bash -c '
      lspci(){ echo "01:00.0 VGA compatible controller: NVIDIA Corporation TU102"; }
      omarchy-hw-nvidia-gsp(){ [[ $GSP == 1 ]]; }
      omarchy-hw-nvidia-without-gsp(){ [[ $GSP == 0 ]]; }
      omarchy-pkg-add(){ printf "%s\n" "$@"; }
      source /dev/stdin'
  rm -rf "$etc_root"
}

for gsp in 1 0; do
  got=$(nvidia_packages server $gsp)
  [[ -n $got ]] || fail "server nvidia installs a driver (gsp=$gsp)"
  if grep -qE "^lib32-|^libva-" <<<"$got"; then fail "server nvidia skips lib32/libva (gsp=$gsp)" "got: $got"; fi
done
grep -qx "lib32-nvidia-utils" <<<"$(nvidia_packages desktop 1)" || fail "desktop nvidia keeps lib32"
pass "server nvidia installs only compute packages"

# Bluetooth on a server follows the hardware: bluez only with an adapter.
bluetooth_actions() {
  local class_dir
  class_dir=$(mktemp -d)
  [[ $2 == "adapter" ]] && mkdir "$class_dir/hci0"
  OMARCHY_PROFILE="$1" OMARCHY_BLUETOOTH_CLASS_PATH="$class_dir" bash -c '
    omarchy-pkg-add(){ printf "pkg-add %s\n" "$*"; }
    systemctl(){ printf "systemctl %s\n" "$*"; }
    source "'"$INSTALL"'/hardware/bluetooth.sh"'
  rm -rf "$class_dir"
}

got=$(bluetooth_actions server adapter)
grep -q "pkg-add bluez bluez-utils" <<<"$got" || fail "server with an adapter installs bluez" "got: $got"
grep -q "systemctl enable bluetooth.service" <<<"$got" || fail "server with an adapter enables bluetooth"
[[ -z $(bluetooth_actions server none) ]] || fail "server without an adapter leaves bluetooth alone"
got=$(bluetooth_actions desktop none)
grep -q "systemctl enable bluetooth.service" <<<"$got" || fail "desktop always enables bluetooth"
if grep -q "pkg-add" <<<"$got"; then fail "desktop does not install bluez here"; fi
pass "server installs Bluetooth only when an adapter is present"

grep -qxF wireless-regdb <<<"$pkgs" || fail "server manifest includes wireless-regdb for Wi-Fi"
pass "server manifest includes the Wi-Fi regulatory database"

grep -qxF tailscale <<<"$pkgs" || fail "server manifest includes tailscale"
pass "server manifest includes tailscale"

# The Tailscale service commands skip the desktop-only steps (Taildrop
# receiver, bar plugin, Admin Console web app) on a server.
tailscale_service_calls() {
  local stubs
  stubs=$(mktemp -d)
  for cmd in sudo systemctl tailscale omarchy-cmd-present omarchy-pkg-add omarchy-pkg-drop omarchy-plugin-enable \
    omarchy-plugin-disable omarchy-webapp-install omarchy-webapp-remove; do
    printf '#!/bin/bash\necho "%s $*"\n' "$cmd" >"$stubs/$cmd"
    chmod +x "$stubs/$cmd"
  done
  PATH="$stubs:$PATH" OMARCHY_PATH="$ROOT" OMARCHY_PROFILE="$1" bash "$ROOT/bin/$2" 2>&1
  rm -rf "$stubs"
}

got=$(tailscale_service_calls server omarchy-install-service-tailscale)
grep -q "sudo systemctl enable --now tailscaled.service" <<<"$got" || fail "server tailscale install starts tailscaled" "got: $got"
grep -q "sudo tailscale up" <<<"$got" || fail "server tailscale install brings the node up"
grep -q "sudo ufw allow in on tailscale0" <<<"$got" || fail "server tailscale install allows the tailnet through ufw"
if grep -qE "omarchy-plugin-enable|omarchy-webapp-install|systemctl --user" <<<"$got"; then
  fail "server tailscale install skips the desktop steps" "got: $got"
fi
got=$(tailscale_service_calls desktop omarchy-install-service-tailscale)
grep -q "omarchy-plugin-enable omarchy.tailscale" <<<"$got" || fail "desktop tailscale install adds the bar plugin"
grep -q "omarchy-webapp-install Tailscale" <<<"$got" || fail "desktop tailscale install adds the web app"
if grep -q "ufw" <<<"$got"; then fail "desktop tailscale install leaves ufw alone"; fi
pass "tailscale install skips the bar, web app and Taildrop on server"

got=$(tailscale_service_calls server omarchy-remove-service-tailscale)
grep -q "omarchy-pkg-drop tailscale" <<<"$got" || fail "server tailscale removal drops the package"
if grep -qE "omarchy-plugin-disable|omarchy-webapp-remove" <<<"$got"; then
  fail "server tailscale removal skips the desktop steps" "got: $got"
fi
grep -q "omarchy-plugin-disable omarchy.tailscale" <<<"$(tailscale_service_calls desktop omarchy-remove-service-tailscale)" ||
  fail "desktop tailscale removal disables the bar plugin"
pass "tailscale removal skips the bar and web app on server"
