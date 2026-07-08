# Sample Error App — 500-throwing shop with Azure SRE Agent

- **Date:** 2026-07-08
- **Status:** Approved (design)
- **Repository:** `JoranBergfeld/sample-error-app`

## 1. Purpose and success criteria

Build a small, fully `azd`-deployable sample that deliberately fails, so it can showcase
Azure Monitor alerting and the **Azure SRE Agent** incident-response loop.

The system is a trivial online shop. Browsing and adding items to a basket works. Clicking
**Pay** always returns an HTTP 500 from the backend. That failure is captured in Application
Insights, an Azure Monitor alert fires on the 5xx errors, and the Azure SRE Agent picks up
the incident, investigates, and **creates a GitHub issue** in this repository.

**Success criteria**

1. `azd up` provisions all infrastructure and deploys both apps from a clean subscription.
2. The frontend is reachable at a public Static Web Apps URL and can list products and add to basket.
3. Clicking **Pay** reliably produces an HTTP 500 that surfaces to the user and to Application Insights.
4. An Azure Monitor alert fires when 5xx errors are detected in the backend.
5. The Azure SRE Agent is deployed, watches the app's resources, and — driven by the alert —
   creates a GitHub issue describing the incident. Any agent configuration the preview API
   cannot perform is captured as a clearly documented one-time manual step.

## 2. Architecture overview

```
Browser ──► Static Web App (React SPA, public URL)
                │  POST /api/checkout  (CORS)
                ▼
        Container App (Spring Boot backend, public FQDN)
                │  request + exception telemetry
                ▼
        Application Insights  ◄── Log Analytics workspace
                │
                ▼
   Azure Monitor scheduled-query alert (5xx)  ──► Action group
                │  (incident)
                ▼
        Azure SRE Agent  ──► GitHub issue in JoranBergfeld/sample-error-app
        (Microsoft.App/agents, watches the app resource group)
```

All resources live in a single resource group provisioned by `azd`/Bicep.

## 3. Repository layout

```
sample-error-app/
├─ azure.yaml                     # azd project: backend + frontend services
├─ infra/
│  ├─ main.bicep                  # subscription-scoped entry (creates RG + module calls)
│  ├─ main.parameters.json        # azd-driven parameter mapping
│  └─ modules/
│     ├─ monitoring.bicep         # Log Analytics + Application Insights
│     ├─ registry.bicep           # Azure Container Registry
│     ├─ containerapp.bicep       # ACA environment + backend app + identity/role
│     ├─ staticwebapp.bicep       # Static Web App (frontend)
│     ├─ alerts.bicep             # action group + scheduled-query 5xx alert
│     └─ sre-agent.bicep          # Microsoft.App/agents + RBAC
├─ src/
│  ├─ backend/                    # Java 21 Spring Boot (Maven), Dockerfile
│  └─ frontend/                   # React + Vite + TypeScript SPA
├─ scripts/
│  └─ configure-sre-agent.sh      # azd postprovision hook (agent behavior config)
├─ docs/superpowers/specs/        # this design doc
└─ README.md
```

## 4. Backend (Java Spring Boot)

- **Stack:** Java 21, Spring Boot 3.x (Spring Web), built with Maven, packaged as a container.
- **Endpoints:**
  - `GET /api/products` — returns a hardcoded list of shop items:
    `{ id, name, description, priceCents, emoji }`. No database.
  - `GET /api/health` — returns `200 OK` for Container Apps liveness/readiness probes.
  - `POST /api/checkout` — accepts the basket in the request body, then **always throws an
    unhandled exception** that resolves to **HTTP 500**. The exception is logged at `ERROR`
    so Application Insights records both a failed request (`resultCode = 500`) and an exception.
- **CORS:** allow the Static Web App origin (passed via environment variable
  `FRONTEND_ORIGIN`) for `GET`/`POST`.
- **Telemetry:** the Application Insights Java agent (`applicationinsights-agent-*.jar`) is
  attached at container start; the connection string is injected via
  `APPLICATIONINSIGHTS_CONNECTION_STRING`. This guarantees the 500s are visible to both the
  alert and the SRE Agent.
- **Container:** multi-stage `Dockerfile` (Maven build stage → slim JRE 21 runtime stage).
  Listens on the port ACA provides (`PORT`, default 8080).

### Backend configuration (environment variables)

| Variable | Source | Purpose |
| --- | --- | --- |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | App Insights output | Telemetry export |
| `FRONTEND_ORIGIN` | Static Web App hostname output | CORS allow-list |
| `PORT` | Container Apps | Listen port |

## 5. Frontend (React SPA on Static Web Apps)

- **Stack:** React + Vite + TypeScript. Basket state is client-side (React state/context);
  no persistence.
- **UI:** product grid with **Add to basket**; a basket panel showing line items and total;
  a **Pay** button.
- **Pay flow:** `POST {VITE_API_BASE_URL}/api/checkout` with the basket. The backend returns
  500; the UI displays a clear error message (e.g. "Payment failed (500) — something went
  wrong on the server."). This is the intended, visible failure.
- **Backend URL wiring:** `VITE_API_BASE_URL` is set at build time by `azd` from the Container
  App's public FQDN output. Direct call + CORS is used instead of an SWA linked backend to keep
  the failure path transparent and the infra simple.
- **Hosting:** Azure Static Web Apps (public URL). Build output (`dist/`) deployed by `azd`'s
  `staticwebapp` host.

## 6. Infrastructure (Bicep + azd)

Single resource group, subscription-scoped `main.bicep` (azd `provider: bicep`).

| Resource | Type | Notes |
| --- | --- | --- |
| Log Analytics workspace | `Microsoft.OperationalInsights/workspaces` | Backing store for App Insights + ACA logs |
| Application Insights | `Microsoft.Insights/components` (workspace-based) | Request/exception telemetry |
| Container Registry | `Microsoft.ContainerRegistry/registries` | Backend image; ACA pulls via managed identity |
| Container Apps env | `Microsoft.App/managedEnvironments` | Wired to Log Analytics |
| Container App (backend) | `Microsoft.App/containerApps` | External ingress, public FQDN, `minReplicas: 1` |
| User-assigned identity | `Microsoft.ManagedIdentity/userAssignedIdentities` | `AcrPull` for the backend app |
| Static Web App (frontend) | `Microsoft.Web/staticSites` | Public URL |
| Action group | `Microsoft.Insights/actionGroups` | Optional email via `alertEmail` param |
| 5xx alert | `Microsoft.Insights/scheduledQueryRules` | Log alert (see §7) |
| SRE Agent | `Microsoft.App/agents@2026-01-01` | See §8 |
| Role assignments | `Microsoft.Authorization/roleAssignments` | AcrPull (backend), Reader + Monitoring Reader (agent) |

**Key parameters** (`main.parameters.json`, azd-mapped):

| Parameter | Default | Purpose |
| --- | --- | --- |
| `environmentName` | (azd) | Resource naming / `azd-env-name` tag |
| `location` | `swedencentral` | Region (SRE-Agent-supported, EU) |
| `sreAgentModelProvider` | `MicrosoftFoundry` | Agent model provider (Azure OpenAI); ARM schema value is `MicrosoftFoundry` |
| `sreAgentModelName` | e.g. `gpt-5.4` | Agent model |
| `sreAgentMode` | `Review` | `actionConfiguration.mode` for Azure mitigations |
| `alertEmail` | `''` (optional) | Action group email; empty = no email receiver |
| `githubOwner` / `githubRepo` | `JoranBergfeld` / `sample-error-app` | Issue target |
| `githubPat` | (secure, optional) | Fine-grained PAT for the GitHub connector |

**Outputs** used by `azd` and the postprovision hook: backend FQDN, frontend hostname, App
Insights connection string + app id, resource group name, SRE Agent name.

## 7. 500 detection and alerting (Azure Monitor)

- **Mechanism:** a **scheduled query (log) alert** — `Microsoft.Insights/scheduledQueryRules`
  — scoped to the Application Insights resource.
- **Query (KQL):**
  ```kusto
  requests
  | where success == false and toint(resultCode) >= 500
  ```
- **Evaluation:** `evaluationFrequency: PT5M`, `windowSize: PT5M`, threshold `GreaterThan 0`,
  severity `2`. Fires whenever any backend 5xx occurs in the window.
- **Action group:** always created (stable ID for the incident plan); adds an email receiver
  only when `alertEmail` is provided.
- **Why log alert over ACA ingress metric:** App Insights gives richer 5xx + exception detail
  and is the same telemetry the SRE Agent reads during investigation, keeping detection and
  diagnosis on one data source.

## 8. Azure SRE Agent

Deployed as `Microsoft.App/agents@2026-01-01` (preview) in the same resource group.

- **Identity:** system-assigned managed identity for reading the app's Azure resources.
- **`logConfiguration.applicationInsightsConfiguration`:** app id + connection string of the
  App Insights resource above (connection string passed as a secure value).
- **`knowledgeGraphConfiguration.managedResources`:** the app's resources (the resource group /
  backend / App Insights) so the agent scopes its monitoring to this app.
- **`actionConfiguration.mode`:** `Review` by default — the agent proposes Azure-resource
  mitigations but requires approval, while its incident response plan is allowed to file a
  GitHub issue automatically (the primary demo output). Configurable via `sreAgentMode`.
- **`defaultModel`:** `{ provider: MicrosoftFoundry, name: <sreAgentModelName> }` — the ARM
  schema provider value `MicrosoftFoundry` maps to Azure OpenAI (Sweden Central default).
  Anthropic is available in other regions but needs a direct agreement.
- **`upgradeChannel`:** `Preview`.
- **RBAC:** agent identity granted **Reader** + **Monitoring Reader** on the resource group.

> Preview caveat: `Microsoft.App/agents` is a preview resource type. Provider registration
> (`Microsoft.App`) and feature availability in the target subscription/region are verified
> during implementation. If a required property (e.g. model provider setup) cannot be
> satisfied purely in Bicep, it is handled as a documented step per §9 rather than stubbed.

## 9. Automating agent behavior (azd `postprovision` hook)

The GitHub connector, Azure Monitor incident-platform connection, and incident response plan
live in the agent **Builder** (data-plane API at `*.azuresre.ai`), not in the Bicep resource.
`scripts/configure-sre-agent.sh` runs as an `azd` `postprovision` hook and, **as far as the
preview data-plane API allows**:

1. **Connect the GitHub connector** using a fine-grained **PAT** (`contents:read`,
   `issues:read/write`) supplied via the `githubPat` secure parameter / azd env
   (`AZURE_GITHUB_PAT`). Non-interactive, so it is scriptable.
2. **Connect Azure Monitor** as the agent's incident platform.
3. **Create an incident response plan** that picks up the 5xx alert and instructs the agent to
   investigate and **create a GitHub issue** in `githubOwner/githubRepo` summarizing the root
   cause. Issue creation is configured to happen automatically (not gated on approval) so the
   demo completes end-to-end.

**Manual fallback:** whatever the preview API genuinely cannot do yet is written up as an
explicit, ordered one-time checklist in `README.md` (portal Builder steps). No behavior is
faked or stubbed to paper over an API gap.

**Auth for the hook:** the script authenticates with the same Azure identity `azd`/`az` is
already logged in as (Contributor on the subscription), and obtains a token for the SRE Agent
data-plane audience.

## 10. azd project (`azure.yaml`)

Two services:

- `backend` — host `containerapp`, language `java` (Docker), image pushed to the provisioned ACR.
- `frontend` — host `staticwebapp`, project `src/frontend`, build output `dist`, with
  `VITE_API_BASE_URL` injected from the backend FQDN output.

Hooks: `postprovision` → `scripts/configure-sre-agent.sh`.

## 11. Security considerations

- The GitHub **PAT** is a secret: stored as an `azd` secure/`secret` parameter and never
  committed. If a persisted secret store is required, it is placed in Key Vault; otherwise it
  is passed transiently to the hook.
- CORS is restricted to the Static Web App origin.
- Backend pulls its image via a user-assigned identity with `AcrPull` (no registry admin creds).
- The SRE Agent uses least-privilege reader roles for observation; Azure-resource mitigations
  stay in `Review` (approval-gated).

## 12. Testing and validation strategy

- **Backend:** a unit/`@WebMvcTest` test asserting `POST /api/checkout` returns 500 and
  `GET /api/products` returns the item list.
- **Frontend:** `npm run build` succeeds; a component test (or manual check) that Pay renders
  the error state on a 500 response.
- **Infra:** `az bicep build` + `az deployment sub what-if` (or `azd provision --preview`) to
  validate templates before applying.
- **End-to-end:** `azd up`, then browse the SWA URL, click Pay, confirm the 500, confirm the
  App Insights failed request, confirm the alert fires, and confirm the SRE Agent creates a
  GitHub issue.

## 13. Out of scope (YAGNI)

- Real payment processing, authentication, persistence/database, or a product catalog service.
- Multi-environment pipelines / CI beyond what `azd` needs (a CI workflow may be added later).
- Fixing the 500 — the failure is the point of the sample.

## 14. Open items / preview caveats

- Exact SRE Agent data-plane API surface for connectors and response plans is preview and may
  require iteration; unreachable steps become documented manual actions (§9).
- Whether `defaultModel`/`AzureOpenAI` requires any additional resource in the target
  subscription is confirmed during implementation.
- `Microsoft.App/agents` availability may require provider/feature registration in the target
  subscription and region.
