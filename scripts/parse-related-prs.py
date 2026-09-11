#!/usr/bin/env python3
"""
parse-related-prs.py

Extract related pull requests from a PR description.

Paired changes across ROS 2 repositories (an rcl PR adding API and the rclcpp
PR consuming it) are declared by the author in the PR body, on a line of the
form

    Depends-On: ros2/rcl#1234
    Requires: https://github.com/ros2/rmw/pull/567, ros2/rcutils#89

Recognised keywords (case-insensitive, optional list marker in front):
Depends-On / Depends on / Depends, Requires, Needs, Blocked by, Companion.
Only keyword-labelled lines are considered; bare PR links elsewhere in the
body are ignored on purpose, since "closes", "similar to" and "supersedes"
links are not build dependencies. HTML comments (PR template boilerplate) are
stripped first. Same-repository references (#123) are ignored.

Inputs (environment):
  PR_BODY              The pull request description (may be empty).
  RELATED_PRS_INPUT    Extra references from a workflow input, whitespace or
                       comma separated, in either slug or URL form.

Output ($GITHUB_OUTPUT when set, always echoed):
  related-prs          Space-separated, de-duplicated "owner/repo#N" list.
"""
import os
import re
import sys

KEYWORD_LINE_RE = re.compile(
    r"^\s*(?:[-*+]\s*)?(?:depends(?:[- ]on)?|requires|needs|blocked[- ]by|companion(?:\s+prs?)?)\s*:\s*(.+)$",
    re.IGNORECASE,
)
REF_RE = re.compile(
    r"(?:https?://github\.com/)?([\w.-]+)/([\w.-]+?)(?:\.git)?(?:/pull/|#)(\d+)\b",
    re.IGNORECASE,
)
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)


def extract(text):
    """Normalised 'owner/repo#N' references in text, in order of appearance."""
    return [f"{owner.lower()}/{repo.lower()}#{int(number)}"
            for owner, repo, number in REF_RE.findall(text)]


def main():
    body = HTML_COMMENT_RE.sub("", os.environ.get("PR_BODY", "") or "")
    refs = []
    for line in body.splitlines():
        m = KEYWORD_LINE_RE.match(line)
        if m:
            refs.extend(extract(m.group(1)))
    refs.extend(extract(os.environ.get("RELATED_PRS_INPUT", "") or ""))
    found = list(dict.fromkeys(refs))  # de-duplicate, keep first occurrence

    value = " ".join(found)
    if found:
        print("Related pull requests: " + ", ".join(found))
    else:
        print("Related pull requests: none")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as f:
            f.write(f"related-prs={value}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
