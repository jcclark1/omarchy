# Portable dev-user setup, both profiles. mise.sh lays down the mise-backed
# tool wrappers (claude, codex, gh, opencode, playwright, ...) that install on
# first use -- the "delayed packages" -- and stays last, as before.
run_logged "$OMARCHY_INSTALL/user/git.sh"
run_logged "$OMARCHY_INSTALL/user/mise-work.sh"

if [[ $OMARCHY_PROFILE != "server" ]]; then
  run_logged "$OMARCHY_INSTALL/user/theme.sh"
  run_logged "$OMARCHY_INSTALL/user/chromium.sh"
  run_logged "$OMARCHY_INSTALL/user/xcompose.sh"

  run_logged "$OMARCHY_INSTALL/user/hardware/asus/fix-audio-mixer.sh"
  run_logged "$OMARCHY_INSTALL/user/hardware/asus/fix-mic.sh"
  run_logged "$OMARCHY_INSTALL/user/hardware/framework/fix-f13-amd-audio-input.sh"
  run_logged "$OMARCHY_INSTALL/user/hardware/dell/xps13-text-scaling.sh"
  run_logged "$OMARCHY_INSTALL/user/hardware/fix-nouveau-cursor.sh"
  run_logged "$OMARCHY_INSTALL/user/hardware/vm-no-animations.sh"

  run_logged "$OMARCHY_INSTALL/user/default-keyring.sh"
fi

run_logged "$OMARCHY_INSTALL/user/mise.sh"
