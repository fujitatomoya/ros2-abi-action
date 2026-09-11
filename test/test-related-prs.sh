#!/usr/bin/env bash
#
# Unit tests for scripts/parse-related-prs.py: only keyword-labelled lines
# count, HTML comments are stripped, same-repo refs are ignored, output is
# de-duplicated and merged with the workflow input.
# shellcheck source=test/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT"

PARSE=scripts/parse-related-prs.py

begin "a representative PR body"
body='## Description
<!-- Template text: Depends-On: ros2/template#1 must be ignored -->
Closes ros2/rclcpp#2555 and is similar to https://github.com/ros2/rclcpp/pull/3000.

- Depends-On: https://github.com/ros2/rcl/pull/1234
Requires: ros2/rmw#567, ROS2/rcutils#89 and ros2/rmw#567 again
blocked by #12
'
out="$TEST_TMP/body.out"
expect_success env PR_BODY="$body" GITHUB_OUTPUT="$out" \
  RELATED_PRS_INPUT='ros2/rcl#1234 https://github.com/ros2/rosidl/pull/9' \
  python3 "$PARSE"
assert_eq "$(output_value "$out" related-prs)" \
  "ros2/rcl#1234 ros2/rmw#567 ros2/rcutils#89 ros2/rosidl#9"
assert_contains "$OUT" "Related pull requests: ros2/rcl#1234, ros2/rmw#567, ros2/rcutils#89, ros2/rosidl#9"
ok

begin "empty body yields empty output"
out="$TEST_TMP/empty.out"
expect_success env PR_BODY= GITHUB_OUTPUT="$out" python3 "$PARSE"
assert_eq "$(output_value "$out" related-prs)" ""
assert_contains "$OUT" "Related pull requests: none"
ok

begin "input alone, comma separated, .git suffix tolerated"
out="$TEST_TMP/input.out"
expect_success env GITHUB_OUTPUT="$out" \
  RELATED_PRS_INPUT='ros2/rcl.git#5,https://github.com/ros2/rmw/pull/6' python3 "$PARSE"
assert_eq "$(output_value "$out" related-prs)" "ros2/rcl#5 ros2/rmw#6"
ok
