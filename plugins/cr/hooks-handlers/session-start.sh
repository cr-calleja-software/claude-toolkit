#!/bin/bash
# Shared session setup for every repo using the cr plugin.
#
# Unlike bootstrap/session-start.sh — which each consuming repo must copy in,
# because it is what makes this plugin reachable in the first place — this hook
# ships with the plugin and runs everywhere it is installed. Shared, repo-
# agnostic session setup belongs here, not in the per-repo bootstrap.
#
# Today it does one thing: every cr command starts by reading
# `.claude/project.md`, so say so at session start rather than letting a command
# fail halfway through.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

if [ ! -f "${PROJECT_DIR}/.claude/project.md" ]; then
  echo "cr plugin: ${PROJECT_DIR}/.claude/project.md is missing — /cr: commands read it for the repo's owner, reviewers, board and checklists, and will not work without it. See the claude-toolkit README for the contract." >&2
fi

exit 0
