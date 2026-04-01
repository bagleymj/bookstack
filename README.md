# BookStack

BookStack is a reading management app that turns a pace target — like "50 books this year" — into a predictable daily reading plan. It uses **heijunka** (production leveling) to keep your daily reading time consistent: no spikes, no valleys, just a steady pipeline of books.

## How It Works

You tell BookStack how many books you want to read and how many minutes per day you're willing to spend. The scheduler takes your reading list and assigns each book to a **tier** — a fixed-duration slot (1 week to 52 weeks) — snapping start and end dates to Monday boundaries so your week is always predictable. Multiple books run concurrently, stacked to fill your daily target evenly.

Each day, you get a page quota. Read it, and the schedule holds. Miss it, and the system redistributes the deficit evenly across remaining days — no cramming, no guilt spikes.

### The Pipeline

The centerpiece is an interactive D3 visualization: a stacked bar chart where the X-axis is your calendar and the Y-axis is minutes per day. Each book is a colored block riding the conveyor belt. Hover to isolate a book, click to see details. A vertical line marks today.

### Reading Sessions

Start a timer or log pages after the fact. BookStack tracks your words-per-minute, learns your actual reading speed per book, and uses that data to improve future schedule estimates. Books have a density rating (light to dense) that adjusts WPM estimates until real data is available.

## Features

- **Pace-driven scheduling** — set a target (books/year, month, or week) and the app derives everything else
- **Heijunka pipeline** — books placed in fixed-duration tiers to level daily reading load
- **Daily quotas** — auto-generated page targets with redistribution on missed days
- **Reading session tracking** — timer-based or manual entry, with WPM calculation
- **Adaptive speed estimates** — density modifiers (0.7x to 1.3x) refined by actual reading data
- **Interactive pipeline chart** — D3-powered stacked visualization of your reading timeline
- **Weekend modes** — skip weekends entirely or read the same amount
- **Manual overrides** — pin a book to a specific date and tier, postpone, or unlock
- **Concurrency control** — set how many books you read in parallel
- **Goodreads import/export** — bring in your shelves, export your history
- **Mobile API** — JWT-authenticated REST endpoints for mobile clients

## Tech Stack

- **Ruby 3.3** / **Rails 7.1**
- **PostgreSQL**
- **Tailwind CSS** / **Hotwire** (Turbo + Stimulus)
- **D3.js** for pipeline visualization
- **Devise** (web auth) + **JWT** (API auth)
- **Nix flakes** for reproducible dev environment

## Getting Started

### Prerequisites

This project uses [Nix](https://nixos.org/) with flakes for development environment management. Install Nix, then:

```bash
git clone https://github.com/mbagley/bookstack.git
cd bookstack
nix develop     # or use direnv for automatic shell entry
```

The Nix shell provides Ruby, Node, PostgreSQL, and all other dependencies.

### Setup

```bash
bin/setup       # initializes the database
```

### Running

```bash
bin/dev         # starts PostgreSQL, Rails server, and Tailwind CSS watcher
```

The app will be available at `http://localhost:3000`.

### Testing

```bash
bin/rspec                           # run all tests
bin/rspec spec/models/book_spec.rb  # run a specific file
```

## Architecture

### Domain Models

| Model | Purpose |
|-------|---------|
| **Book** | Title, author, page range (`first_page`..`last_page`), density rating, reading status |
| **ReadingGoal** | Links a book to a schedule — tier, start date, target completion, quota generation |
| **DailyQuota** | Per-day page target for a goal (pending/completed/missed/adjusted) |
| **ReadingSession** | A reading event with timestamps, pages, and calculated WPM |
| **UserReadingStats** | Aggregated stats — average WPM, total pages, total time |

### Services

| Service | Role |
|---------|------|
| **ReadingListScheduler** | The heijunka engine — places books into tiers, levels daily load |
| **DailyReflow** | Runs once per day — marks missed quotas, triggers rescheduling |
| **QuotaCalculator** | Generates daily page quotas for a goal |
| **QuotaRedistributor** | Spreads remaining pages when quotas are missed |
| **ReadingTimeEstimator** | Estimates completion time using WPM and density |
| **ReadingStatsCalculator** | Recalculates user-level reading statistics |
| **DifficultyAnalyzer** | Compares estimated vs. actual reading speed |

### Scheduling Design

The scheduler is documented in detail in [`SCHEDULING.md`](SCHEDULING.md). The five invariants:

1. **Pace is the constraint** — the daily target is derived from the pace target, never the reverse
2. **Daily load is leveled** — minimize variance in reading time across the timeline
3. **Throughput is verified** — projected completions must match the pace target
4. **Recovery is rate-based** — deficits spread evenly, never crammed
5. **The daily target is a floor** — conflicts are surfaced, not hidden

## License

This project is not currently licensed for redistribution.
