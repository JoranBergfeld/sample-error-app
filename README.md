# sample-error-app

A deliberately failing sample shop used to demo Azure Monitor alerting and the **Azure SRE Agent**.
Browsing and adding to the basket works; clicking **Pay** always returns HTTP 500. The 500s are
captured in Application Insights, an Azure Monitor alert fires, and the SRE Agent opens a GitHub
issue describing the incident.

## Architecture

- **Frontend:** React + Vite on Azure Static Web Apps (public URL).
- **Backend:** Java 21 + Spring Boot on Azure Container Apps (`POST /api/checkout` → 500).
- **Observability:** Log Analytics + Application Insights; scheduled-query alert on backend 5xx.
- **SRE Agent:** `Microsoft.App/agents` watching the app's resource group; files a GitHub issue.

## Run locally

Backend:
```bash
mvn -f src/backend/pom.xml spring-boot:run   # http://localhost:8080
```
Frontend (in another terminal):
```bash
echo "VITE_API_BASE_URL=http://localhost:8080" > src/frontend/.env.local
npm --prefix src/frontend install
npm --prefix src/frontend run dev            # http://localhost:5173
```

## Test

```bash
mvn -f src/backend/pom.xml test
npm --prefix src/frontend run test
```

## Deploy with azd

Prerequisites: **azd ≥ 1.26.0** (older azd, e.g. 1.25.x, deploys Static Web Apps to the `default`
environment, which the SWA content server now rejects with `BadRequest`), `az login`, an
SRE-Agent-supported region, and a GitHub PAT (`contents:read`, `issues:read/write`).

SRE-Agent-supported regions include `swedencentral`, `francecentral`, `uksouth`, `eastus2`,
`australiaeast`, `canadacentral`, `koreacentral`, `southeastasia`, `southafricanorth` (all offer
the default `gpt-5.4` model). If a region reports Container Apps / AKS capacity errors, pick
another supported region.

```bash
azd auth login
azd env new sample-error-app
azd env set AZURE_LOCATION francecentral
azd env set GITHUB_OWNER JoranBergfeld
azd env set GITHUB_REPO sample-error-app
azd env set GITHUB_PAT <your-fine-grained-pat>   # not stored in Bicep/Key Vault
# optional:
azd env set ALERT_EMAIL you@example.com
azd up
```

`azd up` provisions all infrastructure, builds the backend image on ACR (no local Docker needed),
deploys the frontend to Static Web Apps, and runs the SRE-Agent postprovision hook.

## Trigger the demo

1. Open the frontend URL printed by `azd up`.
2. Add items to the basket and click **Pay** — you get a 500 error.
3. Within ~5 minutes the "Backend 5xx errors detected" alert fires.
4. The SRE Agent investigates and opens an issue in `JoranBergfeld/sample-error-app`.

## SRE Agent GitHub wiring

The postprovision hook configures the agent's GitHub PAT via the control plane
(`Microsoft.App/agents` → `properties.gitHubConfiguration.patTokenOverride`), so the agent can
authenticate to GitHub. Choosing **which** repo to file issues in and the **incident → issue**
behavior is done once in the agent workspace (preview, not yet IaC-automatable). If `azd up`
prints **MANUAL STEPS**, complete them at https://sre.azure.com for the `sre-*` agent:

1. **Code Access** → connect `JoranBergfeld/sample-error-app`.
2. **Incident platform** → **Azure Monitor** → Save.
3. **Incident response plans → New** → trigger on the Sev2 `alert-backend-5xx-*` alert; instruct the
   agent to investigate via Application Insights and create a GitHub issue titled
   "Backend 500 detected"; allow automatic issue creation.

> The PAT passed via `azd env set GITHUB_PAT` is stored on the agent resource (encrypted at rest),
> not in Bicep or Key Vault. Prefer a fine-grained PAT limited to this repository.

## Clean up

```bash
azd down --purge
```
