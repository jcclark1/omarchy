# Resolve the install profile once and export it, so sourced setup files and
# run_logged leaves (each a fresh `bash -eE`) inherit it from the environment.
#
# The ISO writes /etc/omarchy/profile ("server" for the --headless build); an
# absent or unrecognized value means the default "desktop" profile. A preset
# OMARCHY_PROFILE env var wins, which is how the builder and tests select it.

if [[ -z ${OMARCHY_PROFILE:-} && -r ${OMARCHY_PROFILE_FILE:-/etc/omarchy/profile} ]]; then
  read -r OMARCHY_PROFILE <"${OMARCHY_PROFILE_FILE:-/etc/omarchy/profile}"
fi

case "${OMARCHY_PROFILE:-}" in
  server) OMARCHY_PROFILE="server" ;;
  *) OMARCHY_PROFILE="desktop" ;;
esac

export OMARCHY_PROFILE
