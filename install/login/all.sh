if [[ $OMARCHY_PROFILE == "server" ]]; then
  run_logged "$OMARCHY_INSTALL/login/headless.sh"
else
  run_logged "$OMARCHY_INSTALL/login/sddm.sh"
fi
