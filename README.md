# Fluffy Inventory & Sales System

Next.js 15 (App Router, TypeScript, Tailwind CSS) app for Fluffy Group's inventory and sales system, backed by Supabase.

## Run in GitHub Codespaces (primary access method)

This is the intended way to run and access the app — entirely on GitHub's infrastructure, no local machine or third-party host involved.

1. On the repo's GitHub page: **Code** → **Codespaces** → **Create codespace on main**
2. Once it opens (dependencies install automatically), copy `.env.example` to `.env.local` and fill in the Supabase values
3. Run `npm run dev` in the terminal
4. Codespaces will prompt to open a forwarded preview of port 3000 — that's your URL (`https://<something>-3000.app.github.dev`)

**Port visibility is set to `public`** (see `.devcontainer/devcontainer.json`), so that URL works for anyone with the link, no GitHub login required. There's nothing sensitive behind it yet — no auth, no write actions — but this should be revisited once FLU-7 (auth) and real data-entry screens ship, since "public" means unauthenticated.

A Codespace is not permanent: it sleeps after inactivity and the URL changes each time you create a new one. For an always-on stable URL, see the Vercel option noted in Linear (deferred, not the current direction).

## Local setup

1. Install dependencies:
   ```
   npm install
   ```
2. Copy `.env.example` to `.env.local` and fill in the Supabase project values:
   ```
   cp .env.example .env.local
   ```
3. Run the dev server:
   ```
   npm run dev
   ```
   App runs at http://localhost:3000.

## Scripts

- `npm run dev` — start the dev server
- `npm run build` — production build
- `npm run start` — run the production build
- `npm run lint` — ESLint
- `npm run format` — Prettier write
- `npm run format:check` — Prettier check

## Project tracking

Epics and stories are tracked in Linear (team `FLU`, project `fluffyinv`).
