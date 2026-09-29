# Headless server login: no display manager. SSH (enabled in
# install/config/enable-services.sh) is the primary access path; the physical
# console gets passwordless autologin into a normal login shell, so it lands in
# the Omarchy bash environment seeded by /etc/skel.

# Boot to the console, not graphical.target.
systemctl set-default multi-user.target

# Autologin the install user on tty1. Physical-console only; SSH is unaffected.
# The empty ExecStart= resets the unit's default before setting the override.
if [[ -n ${OMARCHY_INSTALL_USER:-} ]]; then
  install -d /etc/systemd/system/getty@tty1.service.d
  cat >/etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin ${OMARCHY_INSTALL_USER} --noclear %I \$TERM
EOF
fi
