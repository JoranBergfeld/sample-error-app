#!/usr/bin/env sh
set -eu

# Configures Azure SRE Agent behavior after `azd provision`.
# Reads azd-provided environment variables (infra outputs) and GITHUB_* secrets.
# Real calls only: whatever the preview data-plane API can't do is printed as manual steps.

RG="${AZURE_RESOURCE_GROUP:-}"
SUB="${AZURE_SUBSCRIPTION_ID:-}"
AGENT_NAME="${SRE_AGENT_NAME:-}"
GH_OWNER="${GITHUB_OWNER:-JoranBergfeld}"
GH_REPO="${GITHUB_REPO:-sample-error-app}"
GH_PAT="${GITHUB_PAT:-}"

log()  { printf '\033[36m[sre-agent]\033[0m %s\n' "$1"; }
warn() { printf '\033[33m[sre-agent]\033[0m %s\n' "$1"; }

print_manual_steps() {
  cat <<EOF

============================================================
 MANUAL STEPS (SRE Agent Builder — https://sre.azure.com)
============================================================
Open your agent "${AGENT_NAME}" (resource group ${RG}) and:

 1. Builder > Code Access: connect this repo (${GH_OWNER}/${GH_REPO}).
 2. Builder > Connectors > Add connector > GitHub:
      auth = PAT, token = <your fine-grained PAT: contents:read, issues:read/write>.
 3. Builder > Incident platform: choose "Azure Monitor" and Save.
 4. Builder > Incident response plans > New:
      - Filter: all severities (or Sev2), title contains "5xx".
      - Instruction: "Investigate the backend 5xx incident using Application Insights,
        then create a GitHub issue in ${GH_OWNER}/${GH_REPO} titled
        'Backend 500 detected' summarizing root cause and evidence."
      - Allow the agent to create the GitHub issue automatically.
============================================================
EOF
}

if [ -z "$AGENT_NAME" ] || [ -z "$RG" ]; then
  warn "SRE_AGENT_NAME/AZURE_RESOURCE_GROUP not set; skipping automated config."
  print_manual_steps
  exit 0
fi

# Ensure the resource provider is registered (preview).
STATE="$(az provider show -n Microsoft.App --query registrationState -o tsv 2>/dev/null || echo Unknown)"
if [ "$STATE" != "Registered" ]; then
  warn "Microsoft.App provider not Registered (state=$STATE); attempting registration."
  az provider register -n Microsoft.App >/dev/null 2>&1 || true
fi

AGENT_ID="/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.App/agents/${AGENT_NAME}"

# --- GitHub connector ---
if [ -z "$GH_PAT" ]; then
  warn "GITHUB_PAT not set (run: azd env set GITHUB_PAT <fine-grained-pat>). Skipping GitHub connector automation."
else
  log "Configuring GitHub connector via preview API..."
  # DISCOVERED: replace the URL/payload/api-version below with the values captured in Step 2.
  # Example shape (VERIFY before use):
  #   az rest --method put \
  #     --url "https://management.azure.com${AGENT_ID}/connectors/github?api-version=2026-01-01" \
  #     --headers "Content-Type=application/json" \
  #     --body "{\"properties\":{\"type\":\"GitHub\",\"auth\":{\"kind\":\"PAT\",\"token\":\"${GH_PAT}\"},\"repository\":\"${GH_OWNER}/${GH_REPO}\"}}" \
  #     && log "GitHub connector configured." \
  #     || { warn "GitHub connector API call failed; see manual steps."; GH_FAILED=1; }
  GH_FAILED="${GH_FAILED:-unimplemented}"
fi

# --- Azure Monitor incident platform + response plan ---
log "Configuring Azure Monitor incident platform + response plan via preview API..."
# DISCOVERED: replace with captured endpoints from Step 2 (incident platform + response plan create).
INCIDENT_FAILED="${INCIDENT_FAILED:-unimplemented}"

# If any capability was not implementable via the API, surface manual steps and still succeed.
if [ "${GH_FAILED:-}" = "1" ] || [ "${GH_FAILED:-}" = "unimplemented" ] \
   || [ "${INCIDENT_FAILED:-}" = "1" ] || [ "${INCIDENT_FAILED:-}" = "unimplemented" ]; then
  warn "One or more agent settings could not be applied via the preview API."
  print_manual_steps
fi

log "Done."
exit 0
