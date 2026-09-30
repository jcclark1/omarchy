# Headless server boot: show kernel and systemd output on the console instead
# of the desktop's Plymouth splash, so a server that fails to boot can be
# diagnosed from a physical, IPMI, or VM console. Plymouth itself stays
# installed (omarchy-settings depends on it); it is just never started.

# Drop the plymouth hook from the initramfs. Sorts after omarchy_hooks.conf,
# which sets HOOKS.
install -d /etc/mkinitcpio.conf.d
cat >/etc/mkinitcpio.conf.d/omarchy_server_boot.conf <<'EOF'
_omarchy_hooks=()
for _omarchy_hook in "${HOOKS[@]}"; do
  [[ $_omarchy_hook == "plymouth" ]] || _omarchy_hooks+=("$_omarchy_hook")
done
HOOKS=("${_omarchy_hooks[@]}")
unset _omarchy_hooks _omarchy_hook
EOF

# limine-entry-tool drop-ins can only append to the cmdline, so override the
# quiet flags from omarchy-defaults.conf with later values (the kernel and
# systemd honour the last occurrence). plymouth.enable=0 also keeps the
# rootfs plymouth-start.service from showing the splash.
install -d /etc/limine-entry-tool.d
cat >/etc/limine-entry-tool.d/omarchy-server-boot.conf <<'EOF'
KERNEL_CMDLINE[default]+=" plymouth.enable=0 loglevel=4 systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=1"
EOF
