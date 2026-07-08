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

Prerequisites: `az login`, an SRE-Agent-supported region (default `swedencentral`), and a
fine-grained GitHub PAT (`contents:read`, `issues:read/write`).

```bash
azd auth login
azd env new sample-error-app
azd env set AZURE_LOCATION swedencentral
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

## SRE Agent manual configuration (preview fallback)

Some SRE Agent Builder settings are preview and may not be fully automatable by the hook. If the
`azd up` output prints **MANUAL STEPS**, complete them once at https://sre.azure.com:

1. **Code Access** → connect `JoranBergfeld/sample-error-app`.
2. **Connectors → GitHub** → auth = PAT (`contents:read`, `issues:read/write`).
3. **Incident platform** → **Azure Monitor** → Save.
4. **Incident response plans → New** → filter on the 5xx alert; instruct the agent to investigate
   and create a GitHub issue titled "Backend 500 detected"; allow automatic issue creation.

## Clean up

```bash
azd down --purge
```
