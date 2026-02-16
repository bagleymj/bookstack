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

# Database commands
bin/rails db:migrate
bin/rails db:migrate:status
bin/rails db:seed

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

**CRITICAL: Never run destructive database commands without explicit user confirmation AND a backup.**

Destructive commands that require confirmation:
- `db:reset`, `db:drop`, `db:schema:load`
- Any raw SQL with `DELETE`, `TRUNCATE`, or `DROP`
- `destroy_all`, `delete_all` on models
- Any migration that drops tables or columns

Before running ANY of the above:
1. Run `bin/db_backup` to create a backup
2. Explicitly ask the user for confirmation
3. Only proceed after receiving explicit "yes"

Backup and restore commands:
```bash
# Create a backup
bin/db_backup

# List available backups
bin/db_restore

# Restore from a backup
bin/db_restore bookstack_20260206_120000.sql
```

Backups are stored in `.postgres/backups/` (last 10 kept automatically).

## Git Workflow

**CRITICAL: Always use a feature branch. NEVER commit directly to `main`.**

### Worktree-based workflow (preferred — required when launched in a worktree)

Each agent should work in its own **git worktree** so that branch checkouts are fully isolated. The main repo at `~/dev/bookstack` stays on `main`; agent worktrees live as siblings.

**Creating a worktree (run from the main repo):**
```bash
git worktree add ../bookstack-<short-description> -b claude/<short-description>
```
This creates `~/dev/bookstack-<short-description>/` checked out to `claude/<short-description>`.

**Working in a worktree:**
- Do all work inside your worktree directory — it is a full working copy
- Commit early and often on your branch
- Run tests from within the worktree: `bundle exec rspec`

**Merging and cleanup (run from the main repo):**
```bash
cd ~/dev/bookstack
git merge claude/<short-description>
git worktree remove ../bookstack-<short-description>
git branch -d claude/<short-description>
```

**If you are already inside a worktree**, just work on the branch that's checked out. Do NOT run `git checkout` to switch branches — that defeats the purpose of worktrees.

### Fallback: branch-only workflow (single-agent use)

If you are the only agent and are working directly in the main repo:
- Create a feature branch: `git checkout -b claude/<short-description>`
- Do all work on your branch, committing early and often
- When done, merge to `main`: `git checkout main && git merge claude/<short-description>`
- Delete the branch after merging: `git branch -d claude/<short-description>`

### Commit discipline

- **Commit early and often** - Create a commit as soon as a feature or fix is working. Don't accumulate large uncommitted changes.
- **Group by feature** - When multiple features are pending, create separate commits for each logical change.
- **Descriptive messages** - Summarize what the change does, not how.

## Parallel Development

Multiple Claude Code agents may run simultaneously in separate worktrees. Worktrees eliminate most git conflicts since each agent has its own working directory and branch. However:

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
