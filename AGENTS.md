# Repository Guidelines

## Project Structure & Module Organization

`subnet-calculator/` hosts the flagship IPv4/IPv6 stacks: FastAPI backends in `api-fastapi-azure-function/` and `api-fastapi-container-app/`, plus Flask, static HTML, and Vite frontends (shared UI logic in `shared-frontend/`). Terraform work lives in `terraform/claranet-tfwrapper/`, `terraform/terragrunt/`, and `terraform/modules/`, each with a scoped Makefile and README. Personal-subscription resources must live in UK South unless explicitly justified—Terragrunt stacks default to `PERSONAL_SUB_REGION=uksouth` and expect CAF-style naming (`rg-<workload>-<env>`, e.g., `rg-subnet-calc-webapp`). Keep `scripts/`, `cloud-networking/`, and `blog/` self-contained and document changes in `README.md`.

## Build, Test, and Development Commands

Launch all subnet-calculator services with `cd subnet-calculator && podman-compose up -d`; target the SPA stack via `podman-compose up api-fastapi-container-app frontend-typescript-vite` or `make start-stack4` (SWA CLI). Use the root `Makefile` for hygiene: `make precommit` bundles Ruff, Biome, Terraform fmt/validate, markdownlint, ShellCheck, and gitleaks, while `make test` fans out to `uv run pytest -v`, `npm run type-check`, and `npm run test` across detected projects. Terraform contributors should `source terraform/claranet-tfwrapper/setup-env.sh` before issuing helpers like `make platform plan dev uks` so credentials and backend config load correctly.

## Coding Style & Naming Conventions

Python code uses `uv` + Ruff; keep four-space indentation, snake_case modules, and typed public functions. Frontend projects rely on Biome (`npm run lint:fix`) plus `npm run type-check`; follow PascalCase components, kebab-case filenames, and colocated tests. Terraform/Terragrunt files must pass `terraform fmt`, `tflint`, and `terraform_validate`, with variables declared in `variables.tf`; Markdown and shell scripts must satisfy `markdownlint-cli2` and `shellcheck` as wired in `.pre-commit-config.yaml`.

## Testing Guidelines

`make test` is required before pushing. Keep pytest modules named `test_*.py` beside the code they cover and lean on `uv run pytest -k subnet` for targeted runs. The Vite frontend uses Playwright (`npm run test`, `npm run test:integration`, `npm run test:swa:stack4`); set `BASE_URL` to the active stack (3000/3001/4280) and, for infrastructure edits, run `terraform validate` or the tfwrapper `make ... plan` to maintain the current 188+ checks.

## Commit & Pull Request Guidelines

Commits follow Conventional Commits (`feat:`, `refactor:`, `docs:`) with scopes similar to `feat: Add shared-frontend package`. PRs should list touched stacks, commands executed (`podman-compose up api-fastapi-container-app frontend-python-flask`, `make test`, etc.), linked issues/ADRs, and screenshots or curl output for UI/API tweaks. Call out new env vars, ports, or secrets, confirm `make precommit` passed, and split unrelated experiments into separate PRs.

## Security & Configuration Tips

Secrets stay in local `.env`, tfvars, or tfwrapper `.run/` directories (gitignored); never commit Azure tokens or SWA auth config. Run `make security-setup` once on macOS, re-run `gitleaks` when introducing new providers, and note that `.git-hooks/check-emojis.sh` blocks emoji in Markdown.
