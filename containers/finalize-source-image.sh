#!/usr/bin/env bash
#
# finalize-source-image.sh
#
# Post-build step of the containers/<distro>-source.Dockerfile images, run
# right after `colcon build` in the workspace root:
#
#   1. verify that colcon produced the prefix-level install/setup.bash the
#      action sources at PR time (scripts/colcon-build.sh via ROS_ABI_UNDERLAY);
#   2. record which manifest packages the build did NOT produce in
#      missing.txt (colcon runs with --continue-on-error, so a broken upstream
#      package must not sink the nightly image; colcon-build.sh rebuilds any
#      package the underlay lacks);
#   3. drop the sources, build tree and logs to keep the image small.
#
# Every failure prints what went wrong and a snapshot of install/ and the
# colcon log, so a red nightly build is diagnosable from the job log alone.
# The same script is exercised by the "source-toolchain" job in ci.yml on
# every base image with a one-package workspace.
#
# Usage: finalize-source-image.sh [workspace-root]   (default: /opt/ros2_ws)
set -euo pipefail

ws="${1:-/opt/ros2_ws}"
cd "$ws"

# Byte-wise, locale-independent ordering for sort and comm.
export LC_ALL=C

diagnostics() {
  echo "--- $ws/install (top level):" >&2
  ls -la install 2>&1 | head -40 >&2 || true
  echo "--- colcon log (tail):" >&2
  if [[ -f log/latest_build/logger_all.log ]]; then
    tail -n 60 log/latest_build/logger_all.log >&2
  else
    echo "(no colcon log found)" >&2
  fi
}
trap 'echo "ERROR: finalize-source-image.sh failed at line $LINENO: $BASH_COMMAND" >&2; diagnostics' ERR

if [[ ! -f install/setup.bash ]]; then
  echo "ERROR: colcon did not generate install/setup.bash; the underlay cannot be sourced." >&2
  diagnostics
  exit 1
fi

colcon list --base-paths src --names-only | sort > packages.txt
ls install | sort > built.txt
# comm exits non-zero on unsorted input; both inputs come from sort under
# LC_ALL=C, but --nocheck-order keeps a locale surprise from failing the image.
comm -23 --nocheck-order packages.txt built.txt > missing.txt
echo "Packages not built: $(wc -l < missing.txt)"
if [[ -s missing.txt ]]; then
  sed 's/^/  missing: /' missing.txt
fi

rm -rf build log src packages.txt built.txt
echo "Source underlay finalized in $ws"
