# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BookStack is a Rails 7.1 application for managing reading goals and tracking progress. Users set reading goals with target dates, view them on an interactive pipeline visualization, and track reading sessions to analyze reading speed.

## Development Environment

This project uses Nix flakes for development environment management. Enter the dev shell with:
```bash
nix develop
```

The Nix shell provides all dependencies (Ruby, Node, PostgreSQL, etc.) via direnv.
- PostgreSQL data is stored in `.postgres/`
- Ruby gems are stored in `.gems/`
- Run `bin/setup` once after cloning to initialize the database
- Run `bin/dev` to start PostgreSQL, Rails, and Tailwind together

## Common Commands

```bash
# Start development server (runs Rails server + Tailwind CSS watcher)
bin/dev

# Run all tests
bundle exec rspec

# Run a single test file
bundle exec rspec spec/models/book_spec.rb

# Run a specific test by line number
bundle exec rspec spec/models/book_spec.rb:42

# Database commands (MUST use bin/safe_db for destructive operations)
bin/safe_db migrate           # auto-backs-up, then runs db:migrate
bin/safe_db rollback          # auto-backs-up, then runs db:rollback
bin/safe_db schema:load       # auto-backs-up, requires confirmation, then runs db:schema:load
bin/rails db:migrate:status   # safe — no wrapper needed
bin/rails db:seed             # safe — no wrapper needed

# Generate resources
bin/rails generate model ModelName
bin/rails generate controller ControllerName

# Build Tailwind CSS once
bin/rails tailwindcss:build

# Rails console
bin/rails console
```

## Architecture

### Domain Models

- **User** - Devise authentication, stores reading speed preferences
- **Book** - Core entity with page ranges, difficulty ratings, and reading status (unread/reading/completed/abandoned)
- **ReadingGoal** - Target completion date for a book with weekend inclusion option; drives the pipeline view
- **DailyQuota** - Auto-generated per-day page targets for a reading goal
- **ReadingSession** - Tracks time spent reading with start/end pages for WPM calculation
- **UserReadingStats** - Aggregated reading statistics (average WPM, totals)

### Service Objects (app/services/)

- **QuotaCalculator** - Generates daily quotas for a reading goal
- **QuotaRedistributor** - Redistributes remaining pages when quotas are missed
- **ReadingTimeEstimator** - Estimates time to complete books
- **ReadingStatsCalculator** - Updates user reading statistics
- **DifficultyAnalyzer** - Analyzes actual vs. expected reading speed

### Scheduler Design (ReadingListScheduler)

The scheduler uses a **fixed logical tier system** to place books into calendar-aligned buckets. **Do NOT replace this with computed durations, target-share-based end dates, or any approach that removes the tier concept.** The tiers are:

`[:week, :two_weeks, :month, :two_months, :quarter, :half_year, :year]`

Each tier snaps to a natural calendar boundary (Mondays for week/two_weeks, 1st of month for longer tiers). Books are tried shortest-tier-first and placed in the first tier where they fit under the daily budget ceiling. Stacking (multiple concurrent books) is a natural outcome of the ceiling math, not a goal in itself.

### Key Patterns

- Books use `first_page` and `last_page` instead of raw page count (accommodates different editions)
- Difficulty enum affects reading speed estimates via modifiers (easy=1.3x, dense=0.7x)
- Reading goals drive an interactive D3 pipeline chart (Breakout-style stacked blocks; X=days, Y=minutes/day)
- Pipeline API at `/api/v1/pipeline` serves goal data for the chart
- Book reading time uses actual WPM from sessions when available, falling back to estimated WPM * difficulty modifier
- All authenticated routes are nested under `authenticate :user`

### Testing

Uses RSpec with FactoryBot. Factories are in `spec/factories/`. Run specific model specs with:
```bash
bundle exec rspec spec/models/
```

## Database Safety

**CRITICAL: The dev database has been wiped TWICE by running db commands without backups. Mechanical safeguards are now enforced.**

### Enforced by `bin/rails` guard

`bin/rails` **blocks** these commands outright: `db:migrate`, `db:schema:load`, `db:reset`, `db:drop`, `db:rollback`, `db:migrate:down`, `db:migrate:redo`. You MUST use `bin/safe_db` instead, which auto-backs-up before running.

```bash
# CORRECT — always use bin/safe_db for destructive db operations
bin/safe_db migrate
bin/safe_db rollback
bin/safe_db schema:load    # also requires interactive confirmation

# WRONG — these will be blocked with an error
bin/rails db:migrate       # BLOCKED
bin/rails db:schema:load   # BLOCKED
bundle exec rails db:migrate  # bypasses guard — NEVER DO THIS
```

**NEVER bypass the guard** by calling `bundle exec rails` directly, running raw SQL that drops/truncates, or setting `BOOKSTACK_DB_BACKUP_DONE=1` manually.

### Additional rules

- **NEVER run `RAILS_ENV=test bin/rails db:schema:load`** — it has wiped the dev database before
- Any raw SQL with `DELETE`, `TRUNCATE`, or `DROP` requires `bin/db_backup` first AND user confirmation
- `destroy_all`, `delete_all` on models requires user confirmation
- Any migration that drops tables or columns requires user confirmation

### Backup and restore

```bash
bin/db_backup                                    # Create a backup
bin/db_restore                                   # List available backups
bin/db_restore bookstack_20260206_120000.sql     # Restore from a backup
```

Backups are stored in `.postgres/backups/` (last 10 kept automatically).

## Git Workflow

**CRITICAL: NEVER commit directly to `main`. NEVER run `git checkout` to switch branches.**

**Always assume other agents are running in parallel.** Even if you don't see evidence of them, the user may spin up another agent at any time. This is why worktrees are mandatory, not optional — they guarantee your work is isolated regardless of what other agents do.

### Before you do ANYTHING else

Run this check first:
```bash
git worktree list
pwd
git branch --show-current
```

- **If you are in a worktree** (your pwd is NOT `~/dev/bookstack`): You're set. Work on whatever branch is checked out. Do NOT switch branches.
- **If you are in the main repo** (`~/dev/bookstack`) and on `main`: You MUST create a worktree before making any changes. No exceptions.
- **If you are in the main repo and on a non-main branch**: Create a worktree for that branch and move your work there, OR ask the user for guidance.

### Creating a worktree

Run from the main repo (`~/dev/bookstack`):
```bash
git worktree add ../bookstack-<short-description> -b claude/<short-description>
```
This creates `~/dev/bookstack-<short-description>/` checked out to `claude/<short-description>`. **All subsequent work must happen in that directory.**

### Working in a worktree

- Do all work inside your worktree directory — it is a full working copy
- Commit early and often on your branch
- Run tests from within the worktree: `bundle exec rspec`
- Do NOT run `git checkout` — ever. You are on the right branch already.

### Merging and cleanup (run from the main repo)

```bash
cd ~/dev/bookstack
git merge claude/<short-description>
git worktree remove ../bookstack-<short-description>
git branch -d claude/<short-description>
```

### Commit discipline

- **Commit early and often** - Create a commit as soon as a feature or fix is working. Don't accumulate large uncommitted changes.
- **Group by feature** - When multiple features are pending, create separate commits for each logical change.
- **Descriptive messages** - Summarize what the change does, not how.

## Parallel Development

**Multiple Claude Code agents run simultaneously.** Always assume this is the case — never assume you are the only agent. The user may launch additional agents at any point during your task. Worktrees ensure your work is fully isolated and cannot interfere with (or be interfered by) other agents. However:

**Shared resources — don't touch if already running:**
- Do NOT start/stop `bin/dev`, PostgreSQL, or other services if they're already running (check with `lsof -i :3000` and `pg_isready`)
- Do NOT run `db:migrate` without asking the user — another agent may depend on the current schema

**Worktree awareness:**
- Run `git worktree list` to see what other agents are working on
- Avoid modifying files that another worktree's branch is actively changing
- If you encounter a merge conflict when merging to `main`, stop and ask the user for help — do not resolve conflicts autonomously

**Useful commands:**
```bash
# List all worktrees and their branches
git worktree list

# Prune stale worktree references
git worktree prune
```
