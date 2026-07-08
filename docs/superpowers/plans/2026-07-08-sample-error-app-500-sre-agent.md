# Sample Error App (500-throwing shop + Azure SRE Agent) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an `azd`-deployable online-shop sample whose **Pay** button always returns HTTP 500, wired to Application Insights, an Azure Monitor 5xx alert, and an Azure SRE Agent that files a GitHub issue when the failure is detected.

**Architecture:** React SPA on Azure Static Web Apps calls a Spring Boot backend on Azure Container Apps. The backend's `POST /api/checkout` always throws → 500, captured by Application Insights. A scheduled-query Azure Monitor alert fires on 5xx; the SRE Agent (`Microsoft.App/agents`, watching the app's resource group) picks up the incident and opens a GitHub issue. Everything provisions with Bicep via `azd`; agent behavior config runs in an `azd` postprovision hook with a documented manual fallback for preview-API gaps.

**Tech Stack:** Java 21 + Spring Boot 3.3.5 (Maven), React 18 + Vite 5 + TypeScript + Vitest, Bicep, Azure Developer CLI (`azd`), Azure CLI (`az`), Application Insights Java agent.

**Design spec:** `docs/superpowers/specs/2026-07-08-sample-error-app-500-sre-agent-design.md`

**Environment notes for the implementer:**
- Docker is **not** installed on this box. Do **not** attempt local `docker build`. The backend image builds server-side via ACR remote build (`azd` `docker.remoteBuild: true`), or `az acr build` for standalone validation.
- Tools present: `java` 21, `mvn` 3.9.9, `node` 24 / `npm` 11, `az` 2.85 (logged into subscription `ME-MngEnvMCAP695898-jbergfeld-2`), `az bicep` 0.42.1, `azd` 1.25.4, `gh` 2.89.0.
- `Microsoft.App/agents` is a **preview** resource type; Task 12 verifies provider/feature registration before relying on it.
- Keep the GitHub PAT out of Bicep and Key Vault; it is passed to the hook via `azd env set GITHUB_PAT` only.

**Conventions:**
- Backend Java package root: `com.contoso.shop`.
- Commit after every task with the message shown in its final step. Include the trailer
  `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` on every commit.
- Run backend tests with `mvn -q -f src/backend/pom.xml ...`; frontend with `npm --prefix src/frontend ...`.

---

## File Structure

```
sample-error-app/
├─ azure.yaml                                  # Task 11
├─ .gitignore                                  # Task 1
├─ infra/
│  ├─ main.bicep                               # Task 10
│  ├─ main.parameters.json                     # Task 10
│  └─ modules/
│     ├─ monitoring.bicep                       # Task 6
│     ├─ registry.bicep                         # Task 7
│     ├─ staticwebapp.bicep                     # Task 7
│     ├─ containerapp.bicep                     # Task 8
│     ├─ alerts.bicep                           # Task 9
│     └─ sre-agent.bicep                        # Task 9
├─ src/
│  ├─ backend/                                  # Tasks 1-3
│  │  ├─ pom.xml
│  │  ├─ Dockerfile
│  │  ├─ .dockerignore
│  │  └─ src/main|test/java/com/contoso/shop/...
│  └─ frontend/                                 # Tasks 4-5
│     ├─ package.json, vite.config.ts, tsconfig*.json
│     ├─ public/staticwebapp.config.json
│     └─ src/...
├─ scripts/
│  └─ configure-sre-agent.sh                    # Task 12
└─ README.md                                    # Task 13
```

---

## Task 1: Backend project skeleton + products endpoint (TDD)

**Files:**
- Create: `.gitignore`
- Create: `src/backend/pom.xml`
- Create: `src/backend/src/main/java/com/contoso/shop/ShopApplication.java`
- Create: `src/backend/src/main/java/com/contoso/shop/model/Product.java`
- Create: `src/backend/src/main/java/com/contoso/shop/web/ProductController.java`
- Create: `src/backend/src/main/resources/application.properties`
- Test: `src/backend/src/test/java/com/contoso/shop/web/ProductControllerTest.java`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# Java / Maven
target/
*.class
# Node
node_modules/
dist/
# azd / Azure
.azure/
# Editors / OS
.idea/
.vscode/
.DS_Store
*.log
```

- [ ] **Step 2: Create `src/backend/pom.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.3.5</version>
        <relativePath/>
    </parent>
    <groupId>com.contoso</groupId>
    <artifactId>shop-backend</artifactId>
    <version>0.0.1</version>
    <name>shop-backend</name>
    <properties>
        <java.version>21</java.version>
    </properties>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>
    <build>
        <finalName>app</finalName>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
```

- [ ] **Step 3: Create the application entry point** `src/backend/src/main/java/com/contoso/shop/ShopApplication.java`

```java
package com.contoso.shop;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ShopApplication {
    public static void main(String[] args) {
        SpringApplication.run(ShopApplication.class, args);
    }
}
```

- [ ] **Step 4: Create `src/backend/src/main/resources/application.properties`**

```properties
server.port=${PORT:8080}
frontend.origin=${FRONTEND_ORIGIN:*}
spring.application.name=shop-backend
```

- [ ] **Step 5: Write the failing test** `src/backend/src/test/java/com/contoso/shop/web/ProductControllerTest.java`

```java
package com.contoso.shop.web;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(ProductController.class)
class ProductControllerTest {

    @Autowired
    MockMvc mockMvc;

    @Test
    void returnsProductCatalog() throws Exception {
        mockMvc.perform(get("/api/products"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isArray())
                .andExpect(jsonPath("$.length()").value(6))
                .andExpect(jsonPath("$[0].id").exists())
                .andExpect(jsonPath("$[0].name").exists())
                .andExpect(jsonPath("$[0].priceCents").isNumber());
    }
}
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `mvn -q -f src/backend/pom.xml -Dtest=ProductControllerTest test`
Expected: FAIL — compilation error (`ProductController` / `Product` do not exist).

- [ ] **Step 7: Create the model** `src/backend/src/main/java/com/contoso/shop/model/Product.java`

```java
package com.contoso.shop.model;

public record Product(String id, String name, String description, int priceCents, String emoji) {
}
```

- [ ] **Step 8: Implement the controller** `src/backend/src/main/java/com/contoso/shop/web/ProductController.java`

```java
package com.contoso.shop.web;

import com.contoso.shop.model.Product;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/products")
public class ProductController {

    private static final List<Product> CATALOG = List.of(
            new Product("coffee-mug", "Ceramic Coffee Mug", "A sturdy 350ml mug.", 1299, "☕"),
            new Product("notebook", "Dotted Notebook", "A5 dotted, 120gsm paper.", 1899, "📓"),
            new Product("pen-set", "Gel Pen Set", "Pack of 5 smooth gel pens.", 799, "🖊️"),
            new Product("desk-lamp", "LED Desk Lamp", "Dimmable, warm/cool light.", 3499, "💡"),
            new Product("headphones", "Wireless Headphones", "Over-ear, 30h battery.", 8999, "🎧"),
            new Product("water-bottle", "Insulated Bottle", "Keeps drinks cold 24h.", 2499, "🍶")
    );

    @GetMapping
    public List<Product> list() {
        return CATALOG;
    }
}
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `mvn -q -f src/backend/pom.xml -Dtest=ProductControllerTest test`
Expected: PASS (`BUILD SUCCESS`).

- [ ] **Step 10: Commit**

```bash
git add .gitignore src/backend
git commit -m "feat(backend): scaffold Spring Boot app with products endpoint

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 2: Checkout (always 500), health, and CORS (TDD)

**Files:**
- Create: `src/backend/src/main/java/com/contoso/shop/model/CheckoutRequest.java`
- Create: `src/backend/src/main/java/com/contoso/shop/web/CheckoutException.java`
- Create: `src/backend/src/main/java/com/contoso/shop/web/CheckoutController.java`
- Create: `src/backend/src/main/java/com/contoso/shop/web/GlobalExceptionHandler.java`
- Create: `src/backend/src/main/java/com/contoso/shop/web/HealthController.java`
- Create: `src/backend/src/main/java/com/contoso/shop/config/CorsConfig.java`
- Test: `src/backend/src/test/java/com/contoso/shop/web/CheckoutControllerTest.java`
- Test: `src/backend/src/test/java/com/contoso/shop/web/HealthControllerTest.java`

- [ ] **Step 1: Write the failing checkout test** `.../web/CheckoutControllerTest.java`

```java
package com.contoso.shop.web;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(CheckoutController.class)
@Import(GlobalExceptionHandler.class)
class CheckoutControllerTest {

    @Autowired
    MockMvc mockMvc;

    @Test
    void checkoutAlwaysReturns500() throws Exception {
        String body = "{\"items\":[{\"id\":\"coffee-mug\",\"quantity\":2}]}";
        mockMvc.perform(post("/api/checkout")
                        .contentType("application/json")
                        .content(body))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.error").exists());
    }
}
```

- [ ] **Step 2: Write the failing health test** `.../web/HealthControllerTest.java`

```java
package com.contoso.shop.web;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(HealthController.class)
class HealthControllerTest {

    @Autowired
    MockMvc mockMvc;

    @Test
    void healthReturnsUp() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
```

- [ ] **Step 3: Run both tests to verify they fail**

Run: `mvn -q -f src/backend/pom.xml -Dtest=CheckoutControllerTest,HealthControllerTest test`
Expected: FAIL — compilation error (referenced classes do not exist).

- [ ] **Step 4: Create the request model** `.../model/CheckoutRequest.java`

```java
package com.contoso.shop.model;

import java.util.List;

public record CheckoutRequest(List<Item> items) {
    public record Item(String id, int quantity) {
    }
}
```

- [ ] **Step 5: Create the exception** `.../web/CheckoutException.java`

```java
package com.contoso.shop.web;

public class CheckoutException extends RuntimeException {
    public CheckoutException(String message) {
        super(message);
    }
}
```

- [ ] **Step 6: Implement the checkout controller** `.../web/CheckoutController.java`

```java
package com.contoso.shop.web;

import com.contoso.shop.model.CheckoutRequest;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/checkout")
public class CheckoutController {

    @PostMapping
    public void pay(@RequestBody(required = false) CheckoutRequest request) {
        int itemCount = request == null || request.items() == null ? 0 : request.items().size();
        throw new CheckoutException("Payment processing failed for basket with " + itemCount + " item(s).");
    }
}
```

- [ ] **Step 7: Implement the exception handler (logs ERROR + returns 500)** `.../web/GlobalExceptionHandler.java`

```java
package com.contoso.shop.web;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(CheckoutException.class)
    public ResponseEntity<Map<String, String>> handleCheckout(CheckoutException ex) {
        // Logged at ERROR so the Application Insights Java agent records an exception,
        // and the 500 response is recorded as a failed request (resultCode >= 500).
        log.error("Checkout failed", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Payment failed. Please try again later."));
    }
}
```

- [ ] **Step 8: Implement the health controller** `.../web/HealthController.java`

```java
package com.contoso.shop.web;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/health")
public class HealthController {

    @GetMapping
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }
}
```

- [ ] **Step 9: Implement CORS config** `.../config/CorsConfig.java`

```java
package com.contoso.shop.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class CorsConfig implements WebMvcConfigurer {

    @Value("${frontend.origin:*}")
    private String frontendOrigin;

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOrigins(frontendOrigin)
                .allowedMethods("GET", "POST", "OPTIONS");
    }
}
```

- [ ] **Step 10: Run the full backend test suite to verify all pass**

Run: `mvn -q -f src/backend/pom.xml test`
Expected: PASS — all three test classes green (`BUILD SUCCESS`).

- [ ] **Step 11: Commit**

```bash
git add src/backend
git commit -m "feat(backend): add checkout (500), health, CORS, and error handler

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 3: Backend container image (Dockerfile + App Insights agent)

**Files:**
- Create: `src/backend/Dockerfile`
- Create: `src/backend/.dockerignore`

No local Docker on this box — validation is the Maven package (build correctness) plus a
Dockerfile lint by inspection. The image itself is built server-side by `azd`/ACR later.

- [ ] **Step 1: Create `src/backend/.dockerignore`**

```dockerignore
target/
*.md
.git/
```

- [ ] **Step 2: Create `src/backend/Dockerfile`** (multi-stage; attaches the App Insights Java agent)

```dockerfile
# --- Build stage ---
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml .
RUN mvn -q -e -B dependency:go-offline
COPY src ./src
RUN mvn -q -e -B clean package -DskipTests

# --- Runtime stage ---
FROM eclipse-temurin:21-jre AS runtime
WORKDIR /app
ARG AI_AGENT_VERSION=3.6.2
ADD https://github.com/microsoft/ApplicationInsights-Java/releases/download/${AI_AGENT_VERSION}/applicationinsights-agent-${AI_AGENT_VERSION}.jar /app/applicationinsights-agent.jar
COPY --from=build /workspace/target/app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/app/applicationinsights-agent.jar"
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

> Note: when `APPLICATIONINSIGHTS_CONNECTION_STRING` is unset (local runs), the AI agent logs a
> warning and the app still starts. The connection string is injected by the Container App.

- [ ] **Step 3: Verify the jar builds (proves the Dockerfile build stage will succeed)**

Run: `mvn -q -f src/backend/pom.xml clean package -DskipTests && ls -la src/backend/target/app.jar`
Expected: `BUILD SUCCESS` and `src/backend/target/app.jar` exists.

- [ ] **Step 4: Commit**

```bash
git add src/backend/Dockerfile src/backend/.dockerignore
git commit -m "feat(backend): containerize with App Insights Java agent

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 4: Frontend scaffold + product grid + basket (TDD)

**Files:**
- Create (scaffold): `src/frontend/` via Vite react-ts template
- Create: `src/frontend/src/types.ts`
- Create: `src/frontend/src/api.ts`
- Create: `src/frontend/src/useBasket.ts`
- Create: `src/frontend/vite.config.ts` (overwrite with Vitest config)
- Create: `src/frontend/src/setupTests.ts`
- Test: `src/frontend/src/useBasket.test.tsx`

- [ ] **Step 1: Scaffold the Vite app and add test deps**

Run:
```bash
cd src && npm create vite@latest frontend -- --template react-ts && cd frontend \
  && npm install \
  && npm install -D vitest jsdom @testing-library/react @testing-library/jest-dom @testing-library/user-event \
  && cd ../..
```
Expected: `src/frontend` created with `package.json`, `npm install` completes without errors.

- [ ] **Step 2: Overwrite `src/frontend/vite.config.ts`** (add Vitest jsdom config)

```ts
/// <reference types="vitest" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/setupTests.ts',
  },
});
```

- [ ] **Step 3: Create `src/frontend/src/setupTests.ts`**

```ts
import '@testing-library/jest-dom';
```

- [ ] **Step 4: Add the `test` script to `src/frontend/package.json`**

In the `"scripts"` object add:
```json
"test": "vitest run"
```

- [ ] **Step 5: Create `src/frontend/src/types.ts`**

```ts
export interface Product {
  id: string;
  name: string;
  description: string;
  priceCents: number;
  emoji: string;
}

export interface BasketLine {
  product: Product;
  quantity: number;
}
```

- [ ] **Step 6: Write the failing basket-hook test** `src/frontend/src/useBasket.test.tsx`

```tsx
import { renderHook, act } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { useBasket } from './useBasket';
import type { Product } from './types';

const mug: Product = { id: 'coffee-mug', name: 'Mug', description: '', priceCents: 1299, emoji: '☕' };

describe('useBasket', () => {
  it('adds items and accumulates quantity and total', () => {
    const { result } = renderHook(() => useBasket());

    act(() => result.current.add(mug));
    act(() => result.current.add(mug));

    expect(result.current.lines).toHaveLength(1);
    expect(result.current.lines[0].quantity).toBe(2);
    expect(result.current.totalCents).toBe(2598);
  });

  it('clears the basket', () => {
    const { result } = renderHook(() => useBasket());
    act(() => result.current.add(mug));
    act(() => result.current.clear());
    expect(result.current.lines).toHaveLength(0);
    expect(result.current.totalCents).toBe(0);
  });
});
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `npm --prefix src/frontend run test`
Expected: FAIL — `useBasket` module not found.

- [ ] **Step 8: Implement `src/frontend/src/useBasket.ts`**

```ts
import { useMemo, useState } from 'react';
import type { BasketLine, Product } from './types';

export function useBasket() {
  const [lines, setLines] = useState<BasketLine[]>([]);

  const add = (product: Product) => {
    setLines((current) => {
      const existing = current.find((l) => l.product.id === product.id);
      if (existing) {
        return current.map((l) =>
          l.product.id === product.id ? { ...l, quantity: l.quantity + 1 } : l,
        );
      }
      return [...current, { product, quantity: 1 }];
    });
  };

  const clear = () => setLines([]);

  const totalCents = useMemo(
    () => lines.reduce((sum, l) => sum + l.product.priceCents * l.quantity, 0),
    [lines],
  );

  return { lines, add, clear, totalCents };
}
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `npm --prefix src/frontend run test`
Expected: PASS — both `useBasket` tests green.

- [ ] **Step 10: Create the API client** `src/frontend/src/api.ts`

```ts
import type { Product } from './types';

const BASE_URL = (import.meta.env.VITE_API_BASE_URL ?? '').replace(/\/$/, '');

export async function getProducts(): Promise<Product[]> {
  const res = await fetch(`${BASE_URL}/api/products`);
  if (!res.ok) throw new Error(`Failed to load products (${res.status})`);
  return res.json();
}

export interface CheckoutItem {
  id: string;
  quantity: number;
}

export async function checkout(items: CheckoutItem[]): Promise<void> {
  const res = await fetch(`${BASE_URL}/api/checkout`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ items }),
  });
  if (!res.ok) {
    throw new Error(`Payment failed (${res.status})`);
  }
}
```

- [ ] **Step 11: Commit**

```bash
git add src/frontend
git commit -m "feat(frontend): scaffold Vite app with basket hook and API client

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 5: Frontend UI + Pay flow with 500 error state (TDD)

**Files:**
- Create: `src/frontend/src/App.tsx` (overwrite scaffold default)
- Create: `src/frontend/src/App.css` (overwrite scaffold default)
- Create: `src/frontend/staticwebapp.config.json`
- Test: `src/frontend/src/App.test.tsx`

- [ ] **Step 1: Write the failing App test** `src/frontend/src/App.test.tsx`

```tsx
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import App from './App';

const products = [
  { id: 'coffee-mug', name: 'Ceramic Coffee Mug', description: 'A mug', priceCents: 1299, emoji: '☕' },
];

beforeEach(() => {
  vi.restoreAllMocks();
});

describe('App', () => {
  it('lists products, adds to basket, and shows a 500 error on Pay', async () => {
    const fetchMock = vi.fn()
      // getProducts
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => products } as Response)
      // checkout -> 500
      .mockResolvedValueOnce({ ok: false, status: 500, json: async () => ({ error: 'x' }) } as Response);
    vi.stubGlobal('fetch', fetchMock);

    render(<App />);

    // product renders
    expect(await screen.findByText('Ceramic Coffee Mug')).toBeInTheDocument();

    // add to basket
    await userEvent.click(screen.getByRole('button', { name: /add to basket/i }));
    expect(screen.getByText(/basket \(1\)/i)).toBeInTheDocument();

    // pay -> error surfaces
    await userEvent.click(screen.getByRole('button', { name: /pay/i }));
    await waitFor(() =>
      expect(screen.getByText(/payment failed \(500\)/i)).toBeInTheDocument(),
    );
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm --prefix src/frontend run test`
Expected: FAIL — `App` still the scaffold default (no products/pay/basket text).

- [ ] **Step 3: Implement `src/frontend/src/App.tsx`**

```tsx
import { useEffect, useState } from 'react';
import type { Product } from './types';
import { getProducts, checkout } from './api';
import { useBasket } from './useBasket';
import './App.css';

type PayState = { status: 'idle' | 'paying' } | { status: 'error'; message: string };

export default function App() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [pay, setPay] = useState<PayState>({ status: 'idle' });
  const basket = useBasket();

  useEffect(() => {
    getProducts().then(setProducts).catch((e) => setLoadError(String(e.message ?? e)));
  }, []);

  const onPay = async () => {
    setPay({ status: 'paying' });
    try {
      await checkout(basket.lines.map((l) => ({ id: l.product.id, quantity: l.quantity })));
      setPay({ status: 'idle' });
    } catch (e) {
      setPay({ status: 'error', message: e instanceof Error ? e.message : String(e) });
    }
  };

  const formatPrice = (cents: number) => `$${(cents / 100).toFixed(2)}`;

  return (
    <div className="app">
      <header>
        <h1>🛒 Sample Shop</h1>
      </header>

      <main>
        <section className="catalog">
          {loadError && <p className="error">Could not load products: {loadError}</p>}
          <div className="grid">
            {products.map((p) => (
              <article key={p.id} className="card">
                <div className="emoji">{p.emoji}</div>
                <h3>{p.name}</h3>
                <p className="desc">{p.description}</p>
                <p className="price">{formatPrice(p.priceCents)}</p>
                <button onClick={() => basket.add(p)}>Add to basket</button>
              </article>
            ))}
          </div>
        </section>

        <aside className="basket">
          <h2>Basket ({basket.lines.reduce((n, l) => n + l.quantity, 0)})</h2>
          <ul>
            {basket.lines.map((l) => (
              <li key={l.product.id}>
                {l.product.name} × {l.quantity} — {formatPrice(l.product.priceCents * l.quantity)}
              </li>
            ))}
          </ul>
          <p className="total">Total: {formatPrice(basket.totalCents)}</p>
          <button className="pay" disabled={basket.lines.length === 0 || pay.status === 'paying'} onClick={onPay}>
            {pay.status === 'paying' ? 'Processing…' : 'Pay'}
          </button>
          {pay.status === 'error' && <p className="error">{pay.message} — something went wrong on the server.</p>}
        </aside>
      </main>
    </div>
  );
}
```

- [ ] **Step 4: Implement minimal styling** `src/frontend/src/App.css`

```css
* { box-sizing: border-box; }
body { margin: 0; font-family: system-ui, sans-serif; background: #f5f5f7; color: #1d1d1f; }
.app header { padding: 1rem 2rem; background: #1d1d1f; color: #fff; }
.app main { display: flex; gap: 2rem; padding: 2rem; align-items: flex-start; }
.catalog { flex: 3; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem; }
.card { background: #fff; border-radius: 12px; padding: 1rem; text-align: center; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
.card .emoji { font-size: 3rem; }
.card .price { font-weight: 700; }
.card button, .pay { cursor: pointer; border: 0; border-radius: 8px; padding: .6rem 1rem; background: #0071e3; color: #fff; }
.pay:disabled { background: #9bbfe6; cursor: not-allowed; }
.basket { flex: 1; background: #fff; border-radius: 12px; padding: 1rem; position: sticky; top: 2rem; }
.basket .total { font-weight: 700; }
.error { color: #b00020; font-weight: 600; }
```

- [ ] **Step 5: Create `src/frontend/public/staticwebapp.config.json`** (SPA fallback routing)

Vite copies files under `public/` to the `dist/` root, so the SWA config ships with the built
app (Static Web Apps reads `staticwebapp.config.json` from the deployed artifact root).

```json
{
  "navigationFallback": {
    "rewrite": "/index.html"
  }
}
```

- [ ] **Step 6: Run the full frontend test suite to verify all pass**

Run: `npm --prefix src/frontend run test`
Expected: PASS — `useBasket` and `App` tests green.

- [ ] **Step 7: Verify a production build succeeds**

Run: `npm --prefix src/frontend run build`
Expected: `dist/` produced, no TypeScript errors.

- [ ] **Step 8: Commit**

```bash
git add src/frontend
git commit -m "feat(frontend): shop UI with add-to-basket and 500 Pay error state

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 6: Infra — monitoring module (Log Analytics + Application Insights)

**Files:**
- Create: `infra/modules/monitoring.bicep`

- [ ] **Step 1: Create `infra/modules/monitoring.bicep`**

```bicep
@description('Azure region for all resources.')
param location string

@description('Resource token used to build unique resource names.')
param resourceToken string

@description('Tags applied to every resource.')
param tags object

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

output logAnalyticsId string = logAnalytics.id
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsAppId string = appInsights.properties.AppId
output appInsightsConnectionString string = appInsights.properties.ConnectionString
```

- [ ] **Step 2: Validate the module compiles**

Run: `az bicep build --file infra/modules/monitoring.bicep --stdout > /dev/null && echo OK`
Expected: `OK` (no build errors; warnings are acceptable).

- [ ] **Step 3: Commit**

```bash
git add infra/modules/monitoring.bicep
git commit -m "feat(infra): Log Analytics + Application Insights module

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 7: Infra — container registry + static web app modules

**Files:**
- Create: `infra/modules/registry.bicep`
- Create: `infra/modules/staticwebapp.bicep`

- [ ] **Step 1: Create `infra/modules/registry.bicep`**

```bicep
@description('Azure region for the registry.')
param location string

@description('Resource token used to build unique resource names.')
param resourceToken string

@description('Tags applied to every resource.')
param tags object

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'acr${resourceToken}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
  }
}

output loginServer string = registry.properties.loginServer
output name string = registry.name
output id string = registry.id
```

> `acr` name must be alphanumeric and globally unique; `resourceToken` (lowercase alphanumeric)
> keeps it valid. If the name collides at deploy time, change the `resourceToken` seed in `main.bicep`.

- [ ] **Step 2: Create `infra/modules/staticwebapp.bicep`**

```bicep
@description('Azure region for the Static Web App.')
param location string

@description('Resource token used to build unique resource names.')
param resourceToken string

@description('Tags applied to every resource (must include azd-service-name for the frontend).')
param tags object

resource staticSite 'Microsoft.Web/staticSites@2023-12-01' = {
  name: 'stapp-${resourceToken}'
  location: location
  tags: tags
  sku: { name: 'Free', tier: 'Free' }
  properties: {
    // App is deployed by azd (SWA CLI), not by a linked repo build.
    provider: 'Custom'
  }
}

output name string = staticSite.name
output defaultHostname string = staticSite.properties.defaultHostname
output uri string = 'https://${staticSite.properties.defaultHostname}'
```

> Static Web Apps is not offered in every region. `location` here must be a SWA-supported region
> (West Europe, East US 2, Central US, West US 2, East Asia). `main.bicep` passes
> `staticWebAppLocation` (default `westeurope`) — independent of the `swedencentral` region used
> for the SRE Agent and the rest of the stack.

- [ ] **Step 3: Validate both modules compile**

Run:
```bash
az bicep build --file infra/modules/registry.bicep --stdout > /dev/null \
  && az bicep build --file infra/modules/staticwebapp.bicep --stdout > /dev/null && echo OK
```
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add infra/modules/registry.bicep infra/modules/staticwebapp.bicep
git commit -m "feat(infra): container registry and static web app modules

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 8: Infra — Container Apps module (env + backend app + identity + ACR pull)

**Files:**
- Create: `infra/modules/containerapp.bicep`

- [ ] **Step 1: Create `infra/modules/containerapp.bicep`**

```bicep
@description('Azure region.')
param location string

@description('Resource token used to build unique resource names.')
param resourceToken string

@description('Tags for the environment. The container app also needs an azd-service-name tag.')
param tags object

@description('azd service name that maps this container app to the "backend" service.')
param serviceName string = 'backend'

@description('Log Analytics workspace customer id (GUID) for the environment.')
param logAnalyticsCustomerId string

@description('Log Analytics workspace resource id (for the shared key lookup).')
param logAnalyticsWorkspaceResourceId string

@description('Container registry login server, e.g. myacr.azurecr.io.')
param registryLoginServer string

@description('Container registry resource name (for role assignment scope).')
param registryName string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Allowed CORS origin for the frontend (https://<swa-hostname>).')
param frontendOrigin string

@description('Container image to run. Defaults to a placeholder; azd replaces it on deploy.')
param backendImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(logAnalyticsWorkspaceResourceId, '/'))
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-backend-${resourceToken}'
  location: location
  tags: tags
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, identity.id, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${resourceToken}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-backend-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': serviceName })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registryLoginServer
          identity: identity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'backend'
          image: backendImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'PORT', value: '8080' }
            { name: 'FRONTEND_ORIGIN', value: frontendOrigin }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
  dependsOn: [ acrPull ]
}

output name string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn
output uri string = 'https://${app.properties.configuration.ingress.fqdn}'
output identityPrincipalId string = identity.properties.principalId
```

> The placeholder image `mcr.microsoft.com/k8se/quickstart:latest` listens on 80, so the app is
> unhealthy on first provision but the Container App resource is created. `azd deploy` builds and
> pushes the real image (listening on 8080) and updates the revision. This is the standard azd
> flow and does not require local Docker (remote ACR build is configured in `azure.yaml`).

- [ ] **Step 2: Validate the module compiles**

Run: `az bicep build --file infra/modules/containerapp.bicep --stdout > /dev/null && echo OK`
Expected: `OK` (a warning about `listKeys` is acceptable).

- [ ] **Step 3: Commit**

```bash
git add infra/modules/containerapp.bicep
git commit -m "feat(infra): Container Apps env + backend app with ACR-pull identity

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 9: Infra — alert + SRE Agent modules

**Files:**
- Create: `infra/modules/alerts.bicep`
- Create: `infra/modules/sre-agent.bicep`

- [ ] **Step 1: Create `infra/modules/alerts.bicep`** (action group + scheduled-query 5xx alert)

```bicep
@description('Azure region for the alert resources (global for action groups).')
param location string

@description('Resource token used to build unique resource names.')
param resourceToken string

@description('Tags applied to every resource.')
param tags object

@description('Application Insights resource id the alert queries.')
param appInsightsId string

@description('Optional email address for the action group. Empty = no email receiver.')
param alertEmail string = ''

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'shop5xx'
    enabled: true
    emailReceivers: empty(alertEmail) ? [] : [
      {
        name: 'primary'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource alert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'alert-backend-5xx-${resourceToken}'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'Backend 5xx errors detected'
    description: 'Fires when the backend records HTTP 5xx responses in Application Insights.'
    severity: 2
    enabled: true
    scopes: [ appInsightsId ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      allOf: [
        {
          query: 'requests | where success == false and toint(resultCode) >= 500'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [ actionGroup.id ]
    }
  }
}

output actionGroupId string = actionGroup.id
output alertId string = alert.id
output alertName string = alert.name
```

- [ ] **Step 2: Create `infra/modules/sre-agent.bicep`** (agent + RBAC)

```bicep
@description('Azure region (must be an SRE-Agent-supported region, e.g. swedencentral).')
param location string

@description('Resource token used to build unique resource names.')
param resourceToken string

@description('Tags applied to every resource.')
param tags object

@description('Application Insights app id (GUID) for the agent log configuration.')
param appInsightsAppId string

@description('Application Insights connection string for the agent log configuration.')
@secure()
param appInsightsConnectionString string

@description('Resource id of the resource group content the agent should watch.')
param managedResourceId string

@description('Agent action mode for Azure mitigations.')
@allowed([ 'ReadOnly', 'Review', 'Autonomous' ])
param agentMode string = 'Review'

@description('Model provider (ARM value). MicrosoftFoundry maps to Azure OpenAI.')
param modelProvider string = 'MicrosoftFoundry'

@description('Model name, e.g. gpt-5.')
param modelName string = 'gpt-5'

var readerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
var monitoringReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')

resource agent 'Microsoft.App/agents@2026-01-01' = {
  name: 'sre-${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    actionConfiguration: {
      mode: agentMode
      accessLevel: 'Low'
    }
    defaultModel: {
      provider: modelProvider
      name: modelName
    }
    knowledgeGraphConfiguration: {
      managedResources: [ managedResourceId ]
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsightsAppId
        connectionString: appInsightsConnectionString
      }
    }
    upgradeChannel: 'Preview'
  }
}

resource readerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedResourceId, agent.id, readerRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: readerRoleId
    principalId: agent.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource monitoringReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedResourceId, agent.id, monitoringReaderRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: monitoringReaderRoleId
    principalId: agent.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output name string = agent.name
output principalId string = agent.identity.principalId
```

> Preview caveat: exact property names for `Microsoft.App/agents@2026-01-01` may shift. If
> `az bicep build` reports an unknown property, cross-check the live schema at
> https://learn.microsoft.com/azure/templates/microsoft.app/agents and adjust. Do NOT remove a
> required property to make it compile — if a value is genuinely unavailable, stop and raise it
> per the design's manual-fallback rule (§9 of the spec).

- [ ] **Step 3: Validate both modules compile**

Run:
```bash
az bicep build --file infra/modules/alerts.bicep --stdout > /dev/null \
  && az bicep build --file infra/modules/sre-agent.bicep --stdout > /dev/null && echo OK
```
Expected: `OK`. If the agent module reports an unknown-property error, resolve per the caveat above before proceeding.

- [ ] **Step 4: Commit**

```bash
git add infra/modules/alerts.bicep infra/modules/sre-agent.bicep
git commit -m "feat(infra): 5xx scheduled-query alert and SRE Agent modules

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 10: Infra — main.bicep composition + parameters

**Files:**
- Create: `infra/main.bicep`
- Create: `infra/main.parameters.json`

- [ ] **Step 1: Create `infra/main.bicep`** (subscription scope; creates RG; wires modules)

```bicep
targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the azd environment; used to name the resource group and tag resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources (SRE-Agent-supported, e.g. swedencentral).')
param location string

@description('Location for the Static Web App. SWA is NOT available in every region (e.g. not swedencentral); use a supported region such as westeurope.')
param staticWebAppLocation string = 'westeurope'

@description('Optional email for the 5xx action group.')
param alertEmail string = ''

@description('SRE Agent action mode.')
@allowed([ 'ReadOnly', 'Review', 'Autonomous' ])
param sreAgentMode string = 'Review'

@description('SRE Agent model provider (ARM value; MicrosoftFoundry = Azure OpenAI).')
param sreAgentModelProvider string = 'MicrosoftFoundry'

@description('SRE Agent model name.')
param sreAgentModelName string = 'gpt-5'

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

module staticwebapp 'modules/staticwebapp.bicep' = {
  name: 'staticwebapp'
  scope: rg
  params: {
    location: staticWebAppLocation
    resourceToken: resourceToken
    tags: union(tags, { 'azd-service-name': 'frontend' })
  }
}

module containerapp 'modules/containerapp.bicep' = {
  name: 'containerapp'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    logAnalyticsCustomerId: monitoring.outputs.logAnalyticsCustomerId
    logAnalyticsWorkspaceResourceId: monitoring.outputs.logAnalyticsId
    registryLoginServer: registry.outputs.loginServer
    registryName: registry.outputs.name
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    frontendOrigin: staticwebapp.outputs.uri
  }
}

module alerts 'modules/alerts.bicep' = {
  name: 'alerts'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    appInsightsId: monitoring.outputs.appInsightsId
    alertEmail: alertEmail
  }
}

module sreAgent 'modules/sre-agent.bicep' = {
  name: 'sre-agent'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    appInsightsAppId: monitoring.outputs.appInsightsAppId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    managedResourceId: rg.id
    agentMode: sreAgentMode
    modelProvider: sreAgentModelProvider
    modelName: sreAgentModelName
  }
}

// azd-consumed outputs
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.loginServer
output SERVICE_BACKEND_URI string = containerapp.outputs.uri
output SERVICE_FRONTEND_URI string = staticwebapp.outputs.uri
output VITE_API_BASE_URL string = containerapp.outputs.uri
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.appInsightsConnectionString
output SRE_AGENT_NAME string = sreAgent.outputs.name
```

> `VITE_API_BASE_URL` is emitted as an output so `azd` exposes it as an env var during the
> frontend build; Vite injects any `VITE_*` env var into the bundle.

- [ ] **Step 2: Create `infra/main.parameters.json`**

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": { "value": "${AZURE_ENV_NAME}" },
    "location": { "value": "${AZURE_LOCATION}" },
    "staticWebAppLocation": { "value": "${STATIC_WEB_APP_LOCATION=westeurope}" },
    "alertEmail": { "value": "${ALERT_EMAIL=}" },
    "sreAgentMode": { "value": "${SRE_AGENT_MODE=Review}" },
    "sreAgentModelProvider": { "value": "${SRE_AGENT_MODEL_PROVIDER=MicrosoftFoundry}" },
    "sreAgentModelName": { "value": "${SRE_AGENT_MODEL_NAME=gpt-5}" }
  }
}
```

- [ ] **Step 3: Validate the full template compiles**

Run: `az bicep build --file infra/main.bicep --stdout > /dev/null && echo OK`
Expected: `OK` (warnings acceptable).

- [ ] **Step 4: Commit**

```bash
git add infra/main.bicep infra/main.parameters.json
git commit -m "feat(infra): compose main.bicep and azd parameters

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 11: azd project file (`azure.yaml`)

**Files:**
- Create: `azure.yaml`

- [ ] **Step 1: Create `azure.yaml`**

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/Azure/azure-dev/main/schemas/v1.0/azure.yaml.json
name: sample-error-app
metadata:
  template: sample-error-app@0.0.1
services:
  backend:
    project: src/backend
    language: java
    host: containerapp
    docker:
      path: ./Dockerfile
      remoteBuild: true
  frontend:
    project: src/frontend
    language: js
    host: staticwebapp
    dist: dist
hooks:
  postprovision:
    posix:
      shell: sh
      run: scripts/configure-sre-agent.sh
      continueOnError: true
      interactive: false
```

> `docker.remoteBuild: true` makes azd build the backend image with ACR (no local Docker).
> `continueOnError: true` ensures a preview-API hiccup in the SRE-Agent hook never fails `azd up`;
> the hook prints any required manual steps instead.

- [ ] **Step 2: Validate azd can parse the project**

Run: `azd env list >/dev/null 2>&1; azd config show >/dev/null 2>&1; echo "azd present"`
Then: `python3 -c "import yaml,sys; yaml.safe_load(open('azure.yaml')); print('azure.yaml valid')"`
Expected: `azure.yaml valid` (YAML parses; full azd validation happens at `azd up` in Task 14).

- [ ] **Step 3: Commit**

```bash
git add azure.yaml
git commit -m "feat: add azd project wiring for backend and frontend

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 12: SRE Agent behavior hook (`scripts/configure-sre-agent.sh`)

**Goal:** After provisioning, connect the GitHub connector, connect Azure Monitor as the incident
platform, and create an incident response plan that files a GitHub issue on 5xx — **using the
preview data-plane API for whatever it supports**, and printing precise manual steps for anything
it cannot yet do. Nothing is faked: the script makes real calls and reports reality.

**Files:**
- Create: `scripts/configure-sre-agent.sh`

- [ ] **Step 1: Verify the preview provider/feature is registered (prerequisite check)**

Run:
```bash
az provider show -n Microsoft.App --query registrationState -o tsv
```
Expected: `Registered`. If not, run `az provider register -n Microsoft.App` and wait until it reports `Registered`. Record the result; the hook re-checks this at runtime.

- [ ] **Step 2: Discover the SRE Agent data-plane API surface (real, one-time discovery)**

This preview API is not fully documented. Determine the exact endpoints/payloads for (a) GitHub
connector, (b) Azure Monitor incident platform, (c) incident response plan by ONE of:
- Opening https://sre.azure.com, performing each action once in the portal Builder, and capturing
  the outbound request (browser DevTools → Network) — URL, method, JSON body, and the token
  `aud` (audience) claim; **or**
- Checking for ARM sub-resources under the agent: `az rest --method get --url "https://management.azure.com<AGENT_ID>?api-version=2026-01-01"` and probing documented child collections.

Write the discovered endpoint(s), audience, and payload shape into the script in Step 3 where the
`# DISCOVERED:` markers are. If a capability has no callable API yet, leave its call out and add a
matching entry to the manual-steps block (Step 3, `print_manual_steps`). **Do not invent an
endpoint** — an unimplemented capability becomes a printed manual step, per the approved fallback.

- [ ] **Step 3: Create `scripts/configure-sre-agent.sh`**

```bash
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
```

> This script is intentionally honest about the preview boundary: the `# DISCOVERED:` blocks are
> filled in during Step 2 with **real** captured endpoints. Any capability without a working API
> stays as a printed manual step (`unimplemented`), matching the approved fallback. Because
> `continueOnError: true` is set in `azure.yaml`, the hook never blocks `azd up`.

- [ ] **Step 4: Make the script executable and shell-check it**

Run:
```bash
chmod +x scripts/configure-sre-agent.sh
sh -n scripts/configure-sre-agent.sh && echo "syntax OK"
```
Expected: `syntax OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/configure-sre-agent.sh
git commit -m "feat: SRE Agent postprovision hook with manual-fallback

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 13: README with run/deploy instructions and manual fallback

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace `README.md` with the following**

````markdown
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
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README with local run, azd deploy, and SRE Agent fallback

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 14: End-to-end deployment validation

No new files — this task deploys and verifies the whole system. Requires `az login` to the target
subscription and permission to create the resources and role assignments.

- [ ] **Step 1: Preview the infra (what-if)**

Run:
```bash
azd env set AZURE_LOCATION swedencentral
azd provision --preview
```
Expected: a resource preview listing the RG, monitoring, registry, container app, static web app,
alert, action group, and the SRE agent. Resolve any template errors before continuing.

- [ ] **Step 2: Provision + deploy**

Run: `azd up`
Expected: provisioning succeeds; backend image builds on ACR; frontend deploys; the postprovision
hook runs (either configures the agent or prints MANUAL STEPS). Note the frontend URL.

- [ ] **Step 3: Verify the app and the 500**

Run (replace with the printed backend URL):
```bash
curl -si https://<backend-fqdn>/api/health   | head -n 1     # expect 200
curl -si https://<backend-fqdn>/api/products  | head -n 1     # expect 200 + JSON array
curl -si -X POST https://<backend-fqdn>/api/checkout \
  -H 'Content-Type: application/json' \
  -d '{"items":[{"id":"coffee-mug","quantity":1}]}' | head -n 1   # expect HTTP/1.1 500
```
Then open the frontend URL, add to basket, click **Pay**, and confirm the on-screen 500 error.

- [ ] **Step 4: Verify telemetry + alert**

- In the Azure portal, open Application Insights → **Failures**; confirm `POST /api/checkout`
  appears with result code 500.
- Open **Alerts**; confirm "Backend 5xx errors detected" fires within ~5–10 minutes (or run
  `az monitor scheduled-query list -g rg-<env> -o table` and check the rule exists/enabled).

- [ ] **Step 5: Verify the SRE Agent issue (or complete manual steps)**

- If the hook fully configured the agent: wait for the incident to be picked up, then confirm a
  new issue in `JoranBergfeld/sample-error-app` (`gh issue list -R JoranBergfeld/sample-error-app`).
- If MANUAL STEPS were printed: complete them at https://sre.azure.com, re-trigger a Pay 500, and
  confirm the issue is created.

- [ ] **Step 6: Record results**

Update the plan checkboxes and note any preview-API endpoints discovered (fold them back into
`scripts/configure-sre-agent.sh` if not already). Commit any script refinements:

```bash
git add scripts/configure-sre-agent.sh
git commit -m "chore: finalize SRE Agent hook with verified preview endpoints

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Done criteria

- `mvn -f src/backend/pom.xml test` and `npm --prefix src/frontend run test` pass.
- `az bicep build --file infra/main.bicep` succeeds.
- `azd up` provisions everything and deploys both apps; frontend reachable at a public URL.
- `POST /api/checkout` returns 500; Application Insights records the failed request.
- The "Backend 5xx errors detected" alert exists and fires on 5xx.
- The SRE Agent is deployed and watches the app's resource group; on incident it creates a GitHub
  issue (via the hook, or via the documented one-time manual steps for any preview-API gap).
