#!/usr/bin/env bash
#
# Unit tests for scripts/resolve-distro.sh and scripts/resolve-policy.sh.
# shellcheck source=test/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT"

DISTRO=scripts/resolve-distro.sh
POLICY=scripts/resolve-policy.sh

begin "distro=auto derives from base ref"
out="$TEST_TMP/auto.out"
expect_success env INPUT_DISTRO=auto GITHUB_BASE_REF=jazzy GITHUB_OUTPUT="$out" bash "$DISTRO"
assert_contains "$OUT" "Resolved distro: jazzy"
assert_eq "$(output_value "$out" distro)" "jazzy"
assert_eq "$(output_value "$out" build-mode)" "binary"
assert_eq "$(output_value "$out" source-strategy)" "incremental"
assert_eq "$(output_value "$out" image)" "ghcr.io/fujitatomoya/ros-abi:jazzy"
ok

begin "refs/heads/ prefix and upper case are normalised"
expect_success env INPUT_DISTRO=auto GITHUB_BASE_REF=refs/heads/Humble bash "$DISTRO"
assert_contains "$OUT" "Resolved distro: humble"
ok

begin "explicit distro wins"
expect_success env INPUT_DISTRO=humble GITHUB_BASE_REF=rolling bash "$DISTRO"
assert_contains "$OUT" "Resolved distro: humble"
ok

begin "distro=auto without a base ref fails"
expect_failure env INPUT_DISTRO=auto GITHUB_BASE_REF= bash "$DISTRO"
ok

begin "unsupported distro fails"
expect_failure env INPUT_DISTRO=bogus bash "$DISTRO"
ok

begin "build-mode defaults to binary -> plain distro tag"
expect_success env INPUT_DISTRO=jazzy bash "$DISTRO"
assert_contains "$OUT" "Resolved mode:   binary"
assert_match "$OUT" "Resolved image:  ghcr.io/fujitatomoya/ros-abi:jazzy$"
ok

begin "build-mode=source -> <distro>-source tag"
expect_success env INPUT_DISTRO=rolling BUILD_MODE=source bash "$DISTRO"
assert_contains "$OUT" "Resolved mode:   source"
assert_match "$OUT" "Resolved image:  ghcr.io/fujitatomoya/ros-abi:rolling-source$"
ok

begin "image-prefix is honoured"
expect_success env INPUT_DISTRO=kilted IMAGE_PREFIX=example.org/team/ros bash "$DISTRO"
assert_match "$OUT" "Resolved image:  example.org/team/ros:kilted$"
ok

begin "unsupported build-mode fails"
expect_failure env INPUT_DISTRO=humble BUILD_MODE=bogus bash "$DISTRO"
ok

begin "source + scratch -> still the source image, strategy reported"
expect_success env INPUT_DISTRO=rolling BUILD_MODE=source SOURCE_STRATEGY=scratch bash "$DISTRO"
assert_contains "$OUT" "Resolved strategy: scratch"
assert_match "$OUT" "Resolved image:  ghcr.io/fujitatomoya/ros-abi:rolling-source$"
ok

begin "unsupported source-strategy fails"
expect_failure env INPUT_DISTRO=rolling BUILD_MODE=source SOURCE_STRATEGY=bogus bash "$DISTRO"
ok

begin "rolling -> advisory -> fail-on none"
out="$TEST_TMP/policy.out"
expect_success env INPUT_POLICY=auto DISTRO=rolling GITHUB_OUTPUT="$out" bash "$POLICY"
assert_contains "$OUT" "Resolved policy:  advisory"
assert_contains "$OUT" "Resolved fail-on: none"
assert_eq "$(output_value "$out" policy)" "advisory"
assert_eq "$(output_value "$out" fail-on)" "none"
ok

for d in humble lyrical; do
  begin "$d (released) -> strict -> fail-on incompatible"
  expect_success env INPUT_POLICY=auto DISTRO="$d" bash "$POLICY"
  assert_contains "$OUT" "Resolved policy:  strict"
  assert_contains "$OUT" "Resolved fail-on: incompatible"
  ok
done

begin "explicit policy overrides the distro default"
expect_success env INPUT_POLICY=advisory DISTRO=humble bash "$POLICY"
assert_contains "$OUT" "Resolved policy:  advisory"
expect_success env INPUT_POLICY=strict DISTRO=rolling bash "$POLICY"
assert_contains "$OUT" "Resolved policy:  strict"
ok

begin "policy=auto without a distro fails"
expect_failure env INPUT_POLICY=auto DISTRO= bash "$POLICY"
ok

begin "invalid policy fails"
expect_failure env INPUT_POLICY=bogus DISTRO=humble bash "$POLICY"
ok
