# Fluffy Inventory & Sales System

React + Vite single-page app for Fluffy Group's inventory and sales system, backed by Supabase. Deployed as a static site on **GitHub Pages** — the app talks to Supabase directly from the browser using the public anon key; there is no server component, by design.

## Live URL

`https://<github-username>.github.io/fluffyinv/` — deploys automatically from `main` via `.github/workflows/deploy-pages.yml`.

**One-time setup required** (repo owner, in GitHub UI — not something that can be scripted): go to **Settings → Pages → Build and deployment → Source**, select **GitHub Actions**. After that, every push to `main` deploys automatically.

## Architecture note: why no server

This app is 100% static HTML/JS/CSS. It calls Supabase's REST/Auth API directly from the browser using the **anon key only** — the same key that's safe to ship in a public bundle, because Supabase's Row Level Security policies (not key secrecy) are the actual access-control boundary. The `SUPABASE_SERVICE_ROLE_KEY` must **never** appear anywhere in this codebase: a static site ships all its JS to every visitor, so any secret placed here is not a secret. Anything that needs elevated/service-role privileges in the future (e.g. bulk imports) needs a separate mechanism — Supabase Edge Functions, not a key embedded here.

## Local setup

1. Install dependencies:
   ```
   npm install
   ```
2. `.env` already contains the public Supabase URL and anon key (safe to commit — see architecture note above). Only create `.env.local` if you want to override those locally.
3. Run the dev server:
   ```
   npm run dev
   ```
   App runs at http://localhost:5173/fluffyinv/.

## Run in GitHub Codespaces

Still useful for development (editing/testing before pushing), independent of how the app is hosted:

1. On the repo's GitHub page: **Code** → **Codespaces** → **Create codespace on main**
2. Once it opens, run `npm run dev`
3. Open the forwarded preview of port 5173

## Scripts

- `npm run dev` — start the Vite dev server
- `npm run build` — typecheck + production build to `dist/`
- `npm run preview` — preview the production build locally
- `npm run lint` — ESLint
- `npm run format` — Prettier write
- `npm run format:check` — Prettier check

## Project tracking

Epics and stories are tracked in Linear (team `FLU`, project `fluffyinv`).
