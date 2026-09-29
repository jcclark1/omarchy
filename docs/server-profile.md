# Omarchy Server — a headless amd64 profile

## Context

Omarchy's value splits in two: a **desktop layer** (Hyprland, Waybar/quickshell,
SDDM, GUI apps) and a **CLI/dev layer** (bash env + aliases, starship, tmux,
neovim, git/lazygit, docker, and the mise-backed AI/dev tool suite). We want the
CLI layer on servers so jumping between desktop and server feels identical, with
no desktop baggage.

**Decision — ISO, not bootstrap, and not from-scratch.** Omarchy 4.0 already ships
an archiso-based builder (`omacom/omarchy-iso`) that does exactly "base Arch →
continue into Omarchy setup": `bin/omarchy-iso-make` pacstraps
`omarchy-base.packages`, bundles an **offline mirror** in the ISO, then runs
`omarchy-provision-user --first-install` in the target chroot. It already has
**unattended install** (a `cidata`-labeled drive) and **Tailscale auto-join on
first boot** — both server features. So we add a **headless profile** to the
existing builder rather than hand-rolling archinstall or a bootstrap script.
(Bootstrap would only be needed for ARM/Pi/VPS, which the user scoped out.)

**Confirmed scope:** amd64 bare-metal/VM only · stock `linux` + btrfs/snapper ·
both unattended + interactive install · full mise "delayed packages" suite as-is.

Two repos are involved, developed as sibling checkouts (the builder supports
`omarchy-iso-make --local-source ../omarchy`):
- **`omarchy`** (the `/usr/share/omarchy` runtime): package manifests, `install/`
  setup scripts, `default/bash` shell, themes, `bin/omarchy-*`.
- **`omarchy-iso`** (the builder): archiso profile + the installer orchestrator
  ("phases"), `bin/omarchy-iso-make`, `test/`.

Both should be forked; the profile is structured cleanly enough to potentially
upstream.

## What "delayed packages + mise" is (keep it intact)

`install/user/mise.sh` lays down mise wrappers under `~/.local/bin` (via
`omarchy-mise-install`) for `codex, claude, crush, gemini, gh, copilot, opencode,
playwright, pi, omp, grok, cursor-agent, ghui, hunk`, plus `omarchy-install-hermes-cli
|| true` and the Meta `muse` launcher. Each wrapper `mise use -g` installs the tool
**on first invocation** — that lazy install is the "delayed package" system. It is
fully headless-compatible and stays as-is (full suite). `mise-bin` is already in the
base manifest, so the runtime is present.

## Implementation

### 1. Server package manifest (`omarchy` repo)

Add `install/omarchy-server.packages`, derived from `omarchy-base.packages` (150
pkgs) by the rule **keep CLI/dev + server infra, drop everything graphical/audio/
laptop**. The builder's offline-mirror logic already reads a packages file, so this
becomes the headless mirror source.

- **Must add (not in base):** `openssh` (sshd) — the single biggest gap; also
  `qemu-guest-agent` (VM integration). Keep `sudo`/`base`/`base-devel` from
  `omarchy-other.packages`.
- **Kernel/boot (from `omarchy-other.packages`):** swap `linux-omarchy` →
  `linux` + `linux-headers`; **keep** `btrfs-progs`, `snapper`, `limine`,
  `limine-mkinitcpio-hook`, `limine-snapper-sync` (snapper rollback on servers is
  a win and reuses the installer's existing boot/rollback phase). **Drop** all
  `nvidia*`, `broadcom-wl`, `tuxedo`, `apple/t2`, `intel-ipu7`, `asusctl`,
  `macbook12`, `sof-firmware`, `linux-firmware-marvell`, vulkan/media desktop
  drivers.
- **Keep (representative):** `bash-completion, bat, btop, clang, docker,
  docker-buildx, docker-compose, dua-cli, eza, expac, fastfetch, fd, fzf, git,
  gum, jq, lazydocker, lazygit, less, man-db, mise-bin, networkmanager,
  nss-mdns, avahi, nvim, omarchy-nvim, pacman-contrib, plocate, ripgrep,
  starship, tldr, tmux, tree-sitter-cli, unzip, usage, ufw, ufw-docker, whois,
  yay, zoxide, dosfstools, exfatprogs, inotify-tools, inxi` + language runtimes
  kept for dev-server parity (`ruby, lua51, luarocks, dotnet-runtime, llvm,
  mariadb-libs, postgresql-libs, python-gobject, python-poetry-core`).
- **Drop (representative):** the session stack `hyprland*, uwsm, sddm,
  quickshell, xdg-desktop-portal-hyprland, xdg-desktop-portal-gtk,
  xdg-terminal-exec, plymouth`; GUI apps `chromium, foot, obsidian, obs-studio,
  libreoffice-fresh, kdenlive, pinta, xournalpp, moonlight-qt, mpv*, nautilus*,
  gnome-disk-utility, evince, imv, localsend, aether, cliamp, herdr, omacut,
  omacalc, omawrite`; audio `wireplumber, pamixer, alsa-utils`; input/i18n
  `fcitx5*`; screenshot/clipboard `grim, slurp, hyprpicker, wl-clipboard, wtype,
  gpu-screen-recorder`; theming/fonts `yaru-icon-theme, gnome-themes-extra,
  ttf*/woff2*/noto-*` (keep none needed headless), printing `cups*,
  system-config-printer`, laptop `brightnessctl, ddcutil, power-profiles-daemon,
  bluez*, bolt, udiskie, udisksie`.

### 2. Headless login/session (`omarchy` repo)

- `install/login/all.sh` currently unconditionally sources `login/sddm.sh`. Make
  it profile-aware: on the server profile source a new **`install/login/headless.sh`**
  that: enables `sshd`, sets `systemctl set-default multi-user.target`, and
  configures **console autologin** (a `getty@tty1` drop-in) into a login shell so
  the physical console lands in the Omarchy bash env. No display manager, no
  Hyprland.
- The bash "feel" already seeds via **`/etc/skel`** (confirmed in
  `omarchy-provision-user` help text) plus `$OMARCHY_PATH/default/bash/rc`
  sourced from `~/.bashrc` — this is desktop-independent, so SSH sessions inherit
  aliases/functions/starship for free. Also seed `/root` for root SSH.

### 3. Profile-aware user provisioning (`omarchy` repo)

Gate the desktop-only steps in `install/user/all.sh` behind the profile marker
(e.g. `/etc/omarchy/profile` == `server`, or `OMARCHY_PROFILE`):
- **Keep:** `git.sh`, `mise-work.sh`, **`mise.sh`** (the delayed suite).
- **Guard/skip:** `chromium.sh`, `xcompose.sh`, `default-keyring.sh`, all
  `hardware/**` audio fixes, and reduce `theme.sh` to terminal-color output only
  (skip GTK/Hypr theming).
- `install/user/first-run/`: keep `setup-agent.hook`; skip `welcome.sh`,
  `wifi.sh`, `gnome-theme.sh`, `gtk-primary-paste.sh`, `audio-tuning.sh`,
  `install-voxtype.hook`, `setup-fingerprint.hook`, `enable-user-units.sh`
  (or trim to non-graphical units).
- `bin/omarchy-provision-user` / `bin/omarchy-provision-first-run`: read the
  profile marker and pass it into `install/user/all.sh`.

### 4. Builder: `--headless` flag (`omarchy-iso` repo)

Add `--headless` (alias `--server`) to `bin/omarchy-iso-make` that:
- Sources `omarchy-server.packages` for pacstrap **and** the bundled offline
  mirror (instead of base+other).
- Writes the profile marker into the target (`/etc/omarchy/profile=server`) so
  the chroot provisioning takes the headless paths.
- In the installer **orchestrator phases**: the kernel/bootloader phase installs
  stock `linux` and lets `limine-mkinitcpio-hook` generate entries for
  `vmlinuz-linux` (verify the phase doesn't hardcode `linux-omarchy` in
  pacstrap or a `limine.conf` template — this is the main porting risk); the
  session phase runs `login/headless.sh` instead of the SDDM/Hyprland setup.
- Leave the **cidata** autoinstall + **Tailscale** join paths intact (they're
  server features). Extend the cidata schema if not already present to preset:
  `hostname`, `username`, `authorized_keys` (SSH pubkeys → the biggest fleet
  need), `timezone`. Interactive wizard remains the default when no cidata drive.

### 5. Tests (`omarchy-iso` repo)

- Add a **unit** case under `test/unit/` (run by `./test/all`, VM-free) asserting
  the headless profile selects `multi-user.target` + `sshd`, includes `git/docker/
  mise-bin/openssh`, and excludes `hyprland/sddm/uwsm`.
- Add a **`test/integration.d/`** scenario (QEMU, guest SSH — harness already
  exists) named e.g. `headless-server.sh`.

## Critical files

`omarchy` repo:
- `install/omarchy-server.packages` *(new)* — derived from `install/omarchy-base.packages`
- `install/login/all.sh` *(profile switch)*, `install/login/headless.sh` *(new)*
- `install/user/all.sh` *(guard desktop steps)*; keep `install/user/mise.sh`,
  `install/user/mise-work.sh`, `install/user/git.sh`
- `install/user/first-run/*` *(guard)*
- `bin/omarchy-provision-user`, `bin/omarchy-provision-first-run` *(profile-aware)*

`omarchy-iso` repo:
- `bin/omarchy-iso-make` *(add `--headless`)*
- archiso profile (`profiledef.sh`, `packages.x86_64`, `airootfs/`) + the
  installer orchestrator phases *(kernel/bootloader + session branch)*
- `test/unit/*` and `test/integration.d/headless-server.sh` *(new coverage)*

## Verification (end to end)

1. **Setup (do this first, before any code):** create **public forks** of both
   upstream repos and clone them as siblings, keeping an `upstream` remote so the
   fast-moving `4.0.alpha` can be pulled in:
   ```
   gh repo fork omacom/omarchy      --clone --remote   # sets origin=fork, upstream=omacom
   gh repo fork omacom/omarchy-iso  --clone --remote
   ```
   Place them as siblings (`omarchy/` and `omarchy-iso/`) so `--local-source
   ../omarchy` resolves. Do all work on a `server-profile` branch in each, kept as
   a clean diff so it can be offered upstream later.
2. **Build:** `cd omarchy-iso && ./bin/omarchy-iso-make --headless --local-source ../omarchy`
   → `release/omarchy-server*.iso`.
3. **Fast tests:** `./test/all` (unit: profile selection, package in/exclusion).
4. **Boot test:** `./bin/omarchy-iso-boot release/omarchy-server.iso` (QEMU).
5. **Unattended:** build a `cidata` drive (`genisoimage -volid cidata`) with
   hostname + an SSH `authorized_keys` (+ optional `tailscale_authkey`), attach
   alongside the ISO, confirm hands-off install and auto-reboot.
6. **Integration:** `./test/integration release/omarchy-server.iso headless-server`
   asserting via guest SSH: `systemctl is-active sshd`,
   `systemctl get-default` == `multi-user.target`, `pacman -Q hyprland` **fails**,
   `pacman -Q git docker openssh linux` **succeeds**, `mise --version` works,
   and a wrapper (`gh --version`) lazily resolves (delayed-package path).
7. **Feel check:** SSH in, confirm Omarchy aliases/functions/starship are live
   from `/etc/skel`, and `snapper list` shows the post-install snapshot.
