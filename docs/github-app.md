# Engineering Standards GitHub App

This document describes the optional **GitHub App** shipped in `app/` (and `charts/`). It complements the Nix flake module: consumers still configure standards in `flake.nix` and regenerate files locally or in CI; the app adds **org-wide automation** where you install it.

## What it does

- **Webhooks** — `POST {BASE_URL}/api/webhooks` receives GitHub events (HMAC-verified). The app acts as an installation on selected orgs or repositories.
- **Dashboard** — Staff sign in with **OIDC** (e.g. corporate IdP). The UI surfaces org/repo state that the app tracks in **PostgreSQL**.
- **Feature modules** (webhook-driven):
  - **Flake** — When **engineering-standards** pushes to `main`, the app can **`repository_dispatch`** consumer repos that opted into the update workflow (see [adopting.md](adopting.md#staying-up-to-date)). On consumer repos it tracks `flake.lock` / standards compliance and can open bump PRs. On **installation** or **added repositories**, it can seed state from the default branch.
  - **Pin** — On push to `main`/`master`, if workflow YAML or Docker-related files changed, it can help **pin** Actions references and container images for supply-chain hygiene.
  - **Review** — On pull request **opened** / **synchronize**, and on **issue_comment** when triggered, it can run **Anthropic Claude**-based AI review (requires `ANTHROPIC_API_KEY`).

You only need the app if you want this automation; adopting the flake module alone does not require it.

## Setup

1. **PostgreSQL** — The app expects a reachable database (see `DATABASE_URL` in `app/.env.example`). For local work, from the repo root:
   ```sh
   docker compose -f app/docker-compose.yml up -d
   ```
2. **Environment** — Copy `app/.env.example` to `app/.env` (or export the same variables). Fill at least: `GITHUB_*`, `DATABASE_URL`, OIDC fields, `BASE_URL`, `STANDARDS_REPO_OWNER`, `STANDARDS_REPO_NAME`. For AI review, set `ANTHROPIC_API_KEY`.
3. **Run the server** — From `app/`:
   ```sh
   cargo run
   ```
   Migrations run on startup. Default listen address is `0.0.0.0:3000` (`LISTEN_ADDR`).
4. **OIDC client** — In your IdP, register a confidential client. Set the redirect URI to `{BASE_URL}/auth/callback` (e.g. `http://localhost:3000/auth/callback` for local dev if the IdP allows it).
5. **GitHub App** — Create and configure the app as in [Register the GitHub App](#register-the-github-app). For local webhook testing, use **[Smee](#local-development)** so GitHub can reach your laptop.

**Production** — Deploy the same binary (container or Rust artifact) with secrets from your platform; use the Helm chart under `charts/engineering-standards-app/` if you deploy to Kubernetes. Set `BASE_URL` to the public origin users and the IdP see.

## Local development

GitHub sends webhooks to a **public HTTPS** URL. It cannot call `http://localhost:3000` on your machine. For local dev, use **[Smee](https://smee.io/)** as a free webhook relay: GitHub → Smee → your app.

1. Open [smee.io](https://smee.io/), click **Start a new channel**, and copy the channel URL (e.g. `https://smee.io/abc123`).
2. In your **GitHub App** settings, set **Webhook URL** to that Smee URL (no path — Smee receives the POST as delivered).
3. Keep **Webhook secret** in sync with `GITHUB_WEBHOOK_SECRET` in your `.env`.
4. With `cargo run` already listening (default port `3000`), start the Smee client in another terminal so deliveries are forwarded to the webhook route:
   ```sh
   npx smee-client --url https://smee.io/<your-channel> --target http://127.0.0.1:3000/api/webhooks
   ```
   Change the URL if your `LISTEN_ADDR` uses another host or port.
5. Use a **separate** GitHub App (or personal test app) for dev so you do not change production webhooks.

**Dashboard / OIDC** — Unrelated to Smee: keep `BASE_URL` as `http://localhost:3000` (or whatever your browser uses) so login redirects match your IdP’s registered callback.

**Check** — In the GitHub App settings, use **Redeliver** on a recent webhook (or trigger a real event) and confirm your server logs show the request.

## Register the GitHub App

1. Create an app under [GitHub → Developer settings → GitHub Apps](https://github.com/settings/apps) (or your org’s equivalent).
2. Set **Webhook URL** to `https://<your-host>/api/webhooks` in production. For local dev with Smee, use your **`https://smee.io/…` channel URL** (see [Local development](#local-development)) and run `smee-client` with `--target` pointing at `/api/webhooks`. Use the same **secret** as `GITHUB_WEBHOOK_SECRET`.
3. Subscribe to events the modules use (at minimum: **Push**, **Pull request**, **Installation** / **Installation repositories**; add **Issue comment** if you use review triggers from comments).
4. Grant repository permissions sufficient for the features you enable (contents and pull requests for PR workflows; **Actions** / workflow scope if you rely on pinning or dispatch; follow least privilege for your rollout).
5. Install the app on the **organization or repositories** where standards automation should run.

## Configuration reference

All settings are environment variables; see **`app/.env.example`** for names and comments. Important fields:

- **GitHub** — `GITHUB_APP_ID`, `GITHUB_PRIVATE_KEY` or `GITHUB_PRIVATE_KEY_PATH`, `GITHUB_WEBHOOK_SECRET`
- **HTTP** — `LISTEN_ADDR`, `BASE_URL` (public origin for OIDC redirects and CORS)
- **Data** — `DATABASE_URL`
- **Auth** — `OIDC_ISSUER_URL`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `OIDC_REDIRECT_URL`, optional role-claim variables
- **Standards repo** — `STANDARDS_REPO_OWNER`, `STANDARDS_REPO_NAME`
- **Optional** — `ANTHROPIC_API_KEY`, `OIDC_EXTRA_SCOPES`, `RUST_LOG`

## Health checks

- **`GET /healthz`** — Liveness-style endpoint returning `ok`.

## See also

- [adopting.md](adopting.md) — Nix adoption, `updateWorkflow`, and `repository_dispatch`.
- [README.md](../README.md) — Repository layout (`app/`, `charts/`).
