#!/bin/bash
#
# setup_test_driver_alias.sh
#
# One-time setup: adds a `test_driver` shell function to your shell profile
# so you can run:
#   test_driver [options]
# from inside any driver's `src` directory (or its root) in any clone of
# this repo, without typing a path to tools/test_driver.sh.
#
# Usage:
#   tools/setup_test_driver_alias.sh
#
# Then start a new shell (or `source` your profile) to pick it up.

set -e

marker_start="# >>> SmartThingsEdgeDrivers test_driver alias >>>"
marker_end="# <<< SmartThingsEdgeDrivers test_driver alias <<<"

case "$(basename "${SHELL:-bash}")" in
    zsh)  profile="$HOME/.zshrc" ;;
    bash) profile="$HOME/.bashrc" ;;
    *)
        echo "setup_test_driver_alias.sh: unrecognized shell '${SHELL:-unset}'." >&2
        echo "Add the function shown below to your shell's profile manually." >&2
        profile=""
        ;;
esac

function_block=$(cat <<'EOF'
test_driver() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "test_driver: not inside a git repository" >&2
    return 1
  }
  "$repo_root/tools/test_driver.sh" "$@"
}
EOF
)

if [ -z "$profile" ]; then
    printf '\n%s\n%s\n%s\n' "$marker_start" "$function_block" "$marker_end"
    exit 1
fi

touch "$profile"

if grep -qF "$marker_start" "$profile"; then
    echo "test_driver alias already installed in $profile"
    exit 0
fi

{
    printf '\n%s\n' "$marker_start"
    printf '%s\n' "$function_block"
    printf '%s\n' "$marker_end"
} >> "$profile"

echo "Added test_driver() to $profile"
echo "Run 'source $profile' (or open a new terminal) to start using it."
