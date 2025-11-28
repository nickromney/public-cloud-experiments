# Repository Guidelines

## Project Structure & Module Organization

- `subnet-calculator/` hosts the flagship IPv4/IPv6 stacks with FastAPI backends in `api-fastapi-azure-function/` and `api-fastapi-container-app/`, plus Flask, static HTML, and Vite frontends (shared UI logic in `shared-frontend/`).
- Terraform work lives in `terraform/claranet-tfwrapper/`, `terraform/terragrunt/`, and `terraform/modules/`, each with a scoped Makefile and README.
- Personal-subscription resources must live in UK South unless explicitly justified. Terragrunt stacks default to `PERSONAL_SUB_REGION=uksouth` and expect CAF-style naming (`rg-<workload>-<env>`, e.g., `rg-subnet-calc-webapp`).
- Keep `scripts/`, `cloud-networking/`, and `blog/` self-contained and document changes in `README.md`.

## Build, Test, and Development Commands

Launch all subnet-calculator services with `cd subnet-calculator && podman-compose up -d`; target the SPA stack via `podman-compose up api-fastapi-container-app frontend-typescript-vite` or `make start-stack4` (SWA CLI). Use the root `Makefile` for hygiene: `make precommit` bundles Ruff, Biome, Terraform fmt/validate, markdownlint, ShellCheck, and gitleaks, while `make test` fans out to `uv run pytest -v`, `npm run type-check`, and `npm run test` across detected projects. Terraform contributors should `source terraform/claranet-tfwrapper/setup-env.sh` before issuing helpers like `make platform plan dev uks` so credentials and backend config load correctly.
    - Local kind+Cilium+ArgoCD stack is fully driven via the Terragrunt Makefile: from repo root run `make local kind create` (uses `kind-config.yaml` with Podman) and then apply the staged tfvars in order with `make local kind 100 apply` (bootstrap), `make local kind 200 apply` (Cilium), `make local kind 300 apply` (Hubble), `make local kind 400 apply` (namespaces+ArgoCD), `make local kind 500 apply` (Gitea), and optionally `make local kind 600 apply` (policies). Stage 100 writes kubeconfig to `~/.kube/config` and opens all NodePorts (including azure auth simulation) up-front to avoid cluster recreation later; flip `enable_azure_auth_ports=false` in tfvars only if you do not want those mappings. Use `AUTO_APPROVE=1` to skip prompts when iterating locally.
- If you deleted the cluster, any stage ≥200 **apply** will auto-bootstrap stage 100 (kind create); plans will fail fast and ask you to run stage 100 apply first.
- The Gitea-seeded Argo CD app-of-apps includes an “azure auth simulation” workload (formerly “stack 12”) under `apps/azure-auth-sim` (Application name `azure-auth-sim`). It deploys Keycloak, OAuth2 Proxy, APIM simulator, the FastAPI backend, and the protected React frontend for the “frontend-to-backend with Azure auth simulation” scenario.
- Stages `500`/`600` auto-run `make local kind prereqs` (unless `SKIP_AZURE_AUTH_PREREQS=1`) to build and `kind load` the azure auth simulation images (`api-fastapi-keycloak`, `apim-simulator`, `frontend-react-protected`) so workloads start cleanly. You can run the helper manually or skip it if pointing manifests at an external registry.

## Coding Style & Naming Conventions

Python code uses `uv` + Ruff; keep four-space indentation, snake_case modules, and typed public functions. Frontend projects rely on Biome (`npm run lint:fix`) plus `npm run type-check`; follow PascalCase components, kebab-case filenames, and colocated tests. Terraform/Terragrunt files must pass `terraform fmt`, `tflint`, and `terraform_validate`, with variables declared in `variables.tf`; Markdown and shell scripts must satisfy `markdownlint-cli2` and `shellcheck` as wired in `.pre-commit-config.yaml`.

## Testing Guidelines

`make test` is required before pushing. Keep pytest modules named `test_*.py` beside the code they cover and lean on `uv run pytest -k subnet` for targeted runs. The Vite frontend uses Playwright (`npm run test`, `npm run test:integration`, `npm run test:swa:stack4`); set `BASE_URL` to the active stack (3000/3001/4280) and, for infrastructure edits, run `terraform validate` or the tfwrapper `make ... plan` to maintain the current 188+ checks.

## Commit & Pull Request Guidelines

Commits follow Conventional Commits (`feat:`, `refactor:`, `docs:`) with scopes similar to `feat: Add shared-frontend package`. PRs should list touched stacks, commands executed (`podman-compose up api-fastapi-container-app frontend-python-flask`, `make test`, etc.), linked issues/ADRs, and screenshots or curl output for UI/API tweaks. Call out new env vars, ports, or secrets, confirm `make precommit` passed, and split unrelated experiments into separate PRs.

## Security & Configuration Tips

Secrets stay in local `.env`, tfvars, or tfwrapper `.run/` directories (gitignored); never commit Azure tokens or SWA auth config. Run `make security-setup` once on macOS, re-run `gitleaks` when introducing new providers, and note that `.git-hooks/check-emojis.sh` blocks emoji in Markdown.
