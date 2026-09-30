if [[ $OMARCHY_PROFILE == "server" ]]; then
  # A server gets Bluetooth only when it has an adapter; bluez is not in its
  # package set otherwise.
  if compgen -G "${OMARCHY_BLUETOOTH_CLASS_PATH:-/sys/class/bluetooth}/hci*" >/dev/null; then
    omarchy-pkg-add bluez bluez-utils
    systemctl enable bluetooth.service
  fi
else
  systemctl enable bluetooth.service
fi

# AutoEnable stays at its stock default on purpose. It was set to false here to
# persist the power state, which it never did: BlueZ has no such behaviour, so
# all it bought was Bluetooth coming up off on every boot. omarchy-bluetooth-power
# holds the state in the rfkill soft block instead, and leaving AutoEnable alone
# is what lets bluetoothd bring the adapter back up when that block is lifted.
