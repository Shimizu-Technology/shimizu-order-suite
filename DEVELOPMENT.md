# Development Guide — Hafaloha Legacy API

> **Project:** shimizu-order-suite (Concert ordering system)
> **Stack:** Ruby 3.2.3 · Rails 7.2 · PostgreSQL · Redis · Sidekiq
> **Auth:** Custom JWT (not Clerk)
> **Plane Board:** HL1 (Hafaloha Legacy V1)
> **Deadline:** March 2026 concert — will be archived after

---

## Quick Start

```bash
git clone git@github.com:Shimizu-Technology/shimizu-order-suite.git
cd shimizu-order-suite
bundle install
# DB: restore from production backup (DO NOT use rails db:seed)
rails s -p 3000
```

> ⚠️ **Redis is required** for auth to work. Make sure Redis is running locally.

---

## Gate Script

**Every PR must pass the gate before submission.**

```bash
./scripts/gate.sh
```

This runs:
1. **RSpec tests** — 171 tests
2. **RuboCop lint** — style/correctness checks

❌ If the gate fails, fix the issues before creating a PR. No exceptions.

---

## Development Commands

| Task | Command |
|------|---------|
| Install deps | `bundle install` |
| Start server | `rails s -p 3000` |
| Run tests | `bundle exec rspec` |
| Run linter | `bundle exec rubocop` |
| Run gate | `./scripts/gate.sh` |
| Rails console | `rails c` |

---

## Database Setup

**Do NOT run `rails db:seed`.** The README explicitly warns against this.

Restore from a production backup instead:
```bash
pg_restore --no-owner --no-privileges -d shimizu_order_suite_development /path/to/backup.dump
```

---

## Closed-Loop Development Workflow

We use a "close the loop" approach where agents verify their own work before human review:

### Three Gates

1. **Sub-Agent Gate (automated)** — `./scripts/gate.sh` must pass (RSpec + RuboCop)
2. **Jerry Visual QA (real browser)** — Navigate pages, take screenshots, verify flows work
3. **Leon Final Review (human)** — Review PR + screenshots, approve/reject

Leon shifts from "test everything" to "approve verified work." The gate script is the first line of defense — no PR without a green gate.

### Branch Strategy

- All feature work branches from `staging`
- All PRs target `staging` (never `main` directly)
- `main` only gets updated when Leon approves merging staging
- Feature branches: `feature/<TICKET-ID>-description`

```bash
git checkout staging && git pull
git checkout -b feature/HL1-42-fix-order-totals
```

### PR Process

- **Title:** `HL1-42: Fix order total calculations`
- **Body includes:** what changed, gate results, screenshots
- After creating PR:
  1. Move Plane ticket (HL1 board) to **QA / Testing**
  2. Add PR link to the ticket

### Ticket Tracking

All work is tracked on the **HL1** board in [Plane](https://plane.shimizu-technology.com).

---

## Architecture Notes

- **Auth:** Custom JWT implementation (not Clerk like V2)
- **Background jobs:** Sidekiq (requires Redis)
- **This project has a finite lifespan** — it serves the March 2026 concert and will be archived after
