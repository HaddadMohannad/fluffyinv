# Fluffy Inventory & Sales System

Next.js 15 (App Router, TypeScript, Tailwind CSS) app for Fluffy Group's inventory and sales system, backed by Supabase.

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
