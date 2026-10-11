#!/usr/bin/env bash
# Pre-commit guard (overcommit): docs must not reference the teams Vue files at
# their OLD addon path. These were migrated to the host app (app/javascript/...)
# — see ADR-0034 rev 2026-10-10. A doc referencing the addon path has drifted.
set -uo pipefail

pattern='addons/eln_ui/app/javascript/(packs/vue_teams_table|vue/teams|vue/team_)'

matches=$(grep -rnE "$pattern" docs 2>/dev/null || true)
if [ -n "$matches" ]; then
  echo "ERROR: docs reference teams Vue files at the old addon path:"
  echo "$matches"
  echo "They now live under app/javascript/... (host). Update the doc. (ADR-0034 rev 2026-10-10)"
  exit 1
fi
