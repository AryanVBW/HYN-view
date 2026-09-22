# D1 Migration Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement and review each task.

**Goal:** Keep Supabase Auth and account records; move operational data to a Cloudflare D1 Worker, with five-minute cloud monitoring for 20 servers.

**Architecture:** Preserve the portal and agent endpoint contracts. Route operational PostgREST calls through a private Worker, validating Supabase identity and applying explicit permission checks. D1 uses SQLite tables, migrations and bounded cleanup. Keep the original provider active until all required operations and migrated records are verified.

**Tech Stack:** Bash, Next.js, TypeScript, Cloudflare Workers/D1, Supabase Auth.

**Spec:** User-approved design in this session: 300-second heartbeats, five-minute uploads, 48-hour cloud retention, one-minute local collection, offline after 15 minutes, 20 servers.

## Global Constraints

- Existing IDs and node credentials survive migration; no secret values in logs.
- Supabase remains responsible for Auth, profiles and account administration.
- D1 stores operational records; user-scoped requests enforce current permissions.
- Preserve unrelated original-checkout changes. Work in `.worktrees/d1-migration`.
- No production cutover while any required operational RPC is missing.
- Verify D1 rows read/written and storage; the 17,280 baseline is not total usage.

### Task 1: Five-minute monitoring

**Files:** `lib/{core,agent,cloud,local-store,setup}.sh`, CLI tests, `web-portal/lib/{heartbeat,monitoring-state,node-config}.ts`, watchdog and UI consumers, Supabase additive cadence migration and schema, documentation.

- [ ] Set default heartbeat to 300 seconds, cloud upload/check-in to five minutes. Keep local sampling at one minute, including resident-loop scheduling.
- [ ] Permit the hosted cadence through configuration validation and ensure old managed nodes receive it; preserve explicit privacy mode. Use an additive migration for the hosted settings.
- [ ] Mark connectivity delayed at 600 seconds and quiet/offline at 900 seconds. Audit watchdog, SQL reporting and UI thresholds together.
- [ ] Test default and installed-config behavior, one-minute local collection, 300-second heartbeat scheduling, and state boundaries at 599/600/899/900 seconds.
- [ ] Run CLI suites and relevant portal tests; record any baseline failures separately.

### Task 2: D1 schema and migration tooling

**Files:** `web-portal/cloudflare/`, migration/export scripts and tests.

- [ ] Inventory the final PostgreSQL tables/columns and RPCs used by the app. Retain account tables in Supabase.
- [ ] Build the equivalent SQLite schema with explicit constraints, indexes and JSON conversion. Preserve UUIDs and secret hashes.
- [ ] Export operational records using a server credential into a private file, import to an empty target in bounded batches, and compare per-table counts and stable row checksums.
- [ ] Require explicit readiness evidence before provider activation; do not fall back to Supabase after an operational write fails.
- [ ] Test schema application, invalid data rollback, duplicate imports, export redaction and coverage checking.

### Task 3: Authenticated D1 application backend

**Files:** `web-portal/cloudflare/src/`, `web-portal/lib/database/`, client factories and service clients, `/api/database` route.

- [ ] Implement a Worker with D1 binding, authenticated portal transport, prepared SQL, strict query/table allowlists and bounded request bodies.
- [ ] Load verified user/profile identity from Supabase; separately authenticate agent tokens; do not trust user-supplied role or owner fields.
- [ ] Port required operational RPCs, including server access, relayers, commands, delivery and monitoring, with their existing authorization and concurrency rules.
- [ ] Route server, browser and service operational requests to the selected provider while leaving Auth and account records on Supabase.
- [ ] Test cross-user isolation, revoked nodes, paused accounts, exactly-once claims, ingestion deduplication, retention and provider errors.

### Task 4: Review, deployment and acceptance

**Files:** D1 deployment documentation, readiness script, Worker configuration and environment examples.

- [ ] Verify Cloudflare login/account; create database/Worker when access is available. Use bindings and secret storage.
- [ ] Run all relevant local tests, type checking and build. Review the migration diff and fix findings.
- [ ] Verify import parity and required RPC coverage before any production switch. Preserve source data for rollback.
- [ ] Verify live portal and a real installed server independently from source/build success. If account access is unavailable, report exact connection steps and leave activation blocked.
