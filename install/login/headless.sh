# Headless server login: no display manager. SSH (enabled in
# install/config/enable-services.sh) is the primary access path; the physical
# console gets passwordless autologin into a normal login shell, so it lands in
# the Omarchy bash environment seeded by /etc/skel.

# Boot to the console, not graphical.target.
systemctl set-default multi-user.target

# Autologin the install user on tty1. Physical-console only; SSH is unaffected.
# The empty ExecStart= resets the unit's default before setting the override.
# The username is the only value expanded into the root-owned drop-in, so
# refuse anything outside the portable username shape: a newline there would
# inject its own directives into the unit.
if [[ -n ${OMARCHY_INSTALL_USER:-} && ! $OMARCHY_INSTALL_USER =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Refusing tty1 autologin for invalid username: $OMARCHY_INSTALL_USER" >&2
  exit 1
elif [[ -n ${OMARCHY_INSTALL_USER:-} ]]; then
  install -d /etc/systemd/system/getty@tty1.service.d
  # omarchy:heredoc-expands paths=none -- $OMARCHY_INSTALL_USER is a username
  # validated above, written as the agetty --autologin argument; no path expands.
  cat >/etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin ${OMARCHY_INSTALL_USER} --noclear %I \$TERM
EOF
fi
