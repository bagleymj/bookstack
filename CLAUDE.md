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
