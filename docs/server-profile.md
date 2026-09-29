# Omarchy Server — headless amd64 profile

A `--headless` install profile for Omarchy: the full CLI/dev environment and
"feel" (shell, aliases, starship, tmux, neovim, mise tool suite) with no desktop
session, so servers and the desktop share one config. Built as a profile of
Omarchy's existing archiso builder, not a separate distro or a bootstrap script.

## Where the work lives

Two forks, cloned as siblings under `~/Projects`, both on branch `server-profile`
(`origin` = `jcclark1/*`, `upstream` = `omacom/*`):

- `~/Projects/omarchy` — the runtime (`/usr/share/omarchy` payload)
- `~/Projects/omarchy-iso` — the archiso builder + Python install orchestrator
- `~/Projects/omarchy-pkgs` — custom package PKGBUILDs (needed by `--local-source`)

Resume by reading this file, then `git -C ~/Projects/omarchy log --oneline` and
the same in `omarchy-iso`. Base is `4.0.0.alpha` on the `quattro` branch.

## How the profile works

One marker file, `/etc/omarchy/profile`, is the single source of truth. The ISO
bakes it (for a `--headless` build) and the installer writes it into the target;
every runtime code path reads it via `install/helpers/profile.sh`, which resolves
and exports `OMARCHY_PROFILE` (`server` or `desktop`, default `desktop`).

Install-time flow (server):
1. `omarchy-iso-make --headless` → `OMARCHY_PROFILE=server` into the build container.
2. `builder/build-iso.sh` builds the offline mirror from `omarchy-server.packages`
   **alone** (never base+other, which carry nvidia/T2/broadcom hardware packages a
   server neither installs nor wants), ships that manifest into the airootfs, and
   bakes `/usr/share/omarchy-iso/profile` = `server`.
3. The Python orchestrator (`orchestrator/`) resolves the profile, defaults the
   kernel to stock `linux` (and coerces a config's `linux-omarchy` → `linux`,
   since the server mirror carries only stock), pacstraps `omarchy-server.packages`,
   writes `/etc/omarchy/profile` into the target, then runs
   `omarchy-apply-system --first-install` in the chroot.
4. `omarchy-apply-system` sources the profile and takes the server branch:
   `login/headless.sh` (multi-user.target + tty1 console autologin), sshd enabled
   and sddm/cups/avahi/power-profiles skipped, user provisioning that keeps
   `git` + `mise.sh` and skips the desktop leaves.
5. `configure_login` (orchestrator) is a no-op on server, so it does not clobber
   the console autologin or try to enable sddm.

## Delayed packages / mise

`install/user/mise.sh` writes mise wrappers (claude, codex, gemini, gh, copilot,
opencode, crush, playwright, pi, grok, …) that install on first use — the
"delayed packages." Kept in full on the server profile; `mise-bin` is in the
server manifest.

## File map (server-profile changes)

`omarchy`:
- `install/omarchy-server.packages` — the server manifest (source of truth)
- `install/helpers/profile.sh` — resolves+exports `OMARCHY_PROFILE`
- `install/login/headless.sh` — multi-user.target + tty1 autologin
- `install/login/all.sh`, `install/config/enable-services.sh` — profile branches
- `install/config/firewall.sh` — server opens SSH (not LocalSend) through ufw
- `install/user/all.sh` — keeps git+mise, guards desktop leaves
- `bin/omarchy-apply-system` — sources the profile helper
- `bin/omarchy-provision-user` — guards graphical finalization
- `test/shell.d/server-profile-test.sh` — 14 tests

`omarchy-iso`:
- `bin/omarchy-iso-make` — `--headless` flag → `OMARCHY_PROFILE`
- `builder/build-iso.sh` — server-only mirror, ships manifest, bakes marker,
  headless dashboard count
- `orchestrator/context.py` — profile resolution, stock-kernel default + coercion
- `orchestrator/phases_impl.py` — server manifest selection, target marker,
  `configure_login` server no-op
- `test/unit/test_server_profile.py` — profile/kernel/login/manifest tests
- `test/integration.d/headless-server-test.sh` — end-to-end QEMU scenario;
  `base-test.sh` records each base's profile so scenarios skip bases they
  don't apply to (`factory-reset` skips on a server base)

## Build

`gh` must be logged in. Docker is required; the user is not in the `docker` group,
so `omarchy-iso-make` escalates the single `docker run` via sudo (needs a real
terminal for the password — the Claude `!` runner has no TTY, so run it in an
actual terminal):

```
cd ~/Projects/omarchy-iso
./bin/omarchy-iso-make --headless --no-boot-offer --local-source ../omarchy ../omarchy-pkgs
```

Output: `~/Projects/omarchy-iso/release/omarchy-*-local.iso`. The local build
compiles only three small config packages (omarchy, omarchy-settings,
omarchy-nvim); the rest, including stock `linux`, download into the mirror. Add
`--no-cache` if a half-finished run left stale cache.

## Test

Unit tests (no Docker/VM; run from each repo):
- `omarchy`: `./test/shell` (or just `bash test/shell.d/server-profile-test.sh`)
- `omarchy-iso`: `python3 -m unittest discover -t . -s test/unit` (84 pass;
  stdlib unittest, no pytest). Pre-existing unrelated failure in `omarchy`'s
  `test/cli`: "vscode generated theme references current theme file".

Verify a built ISO (before booting): loopback-mount it and check
`usr/share/omarchy-iso/profile` = `server`, that `omarchy-server.packages` is
present, and that the offline mirror under `var/cache/omarchy/mirror/offline`
contains `openssh` and a `linux-*` package but no `hyprland`/`sddm`.

QEMU boot test (`/dev/kvm` is available, world-accessible — no sudo):
- Build a `cidata` drive with a hostname + an `authorized_keys` (default SSH key
  `~/.ssh/id_ed25519.pub`) so the install runs unattended and headless, per the
  cidata section of `omarchy-iso/README.md` (it already supports
  `--authorized-keys-file` and `--tailscale-authkey-file`).
- Boot with `./bin/omarchy-iso-boot release/<iso>` (or `omarchy-vm`), let it
  install and reboot, then SSH in and assert: `systemctl is-active sshd`,
  `systemctl get-default` = `multi-user.target`, `pacman -Q hyprland` fails,
  `pacman -Q git docker openssh linux` succeeds, `mise --version` works, and a
  wrapper (`gh --version`) lazily resolves.

## Remaining

- Build the ISO (see Build; needs sudo in a real terminal) and get a green run
  of the integration scenario, which does the whole QEMU install + assertions:
  `cd ~/Projects/omarchy-iso && ./test/integration release/<iso> headless-server`
  (`--reuse-base` on reruns). Not yet run — no ISO has been built.
- Optionally open PRs to `omacom/omarchy` and `omacom/omarchy-iso`.
- Not in scope (deliberately): ARM/Raspberry-Pi, cloud-VPS images, a bootstrap
  script for existing machines.
