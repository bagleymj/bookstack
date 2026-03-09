# Scheduling System Design — Heijunka for Books

This document defines the principles and invariants that govern BookStack's
reading pipeline scheduler. All future changes to scheduling logic **must**
honor these constraints.

## Core Principle

The scheduler implements **heijunka** (production leveling) for reading. The
goal is to deliver a precise number of books per year with a consistent,
sustainable daily reading load — no spikes, no valleys, no hoping it works
out.

## System Model

The pipeline is a conveyor belt. Books enter as "packages" of varying size
(reading time). Each package is placed in a **tier** — a fixed-duration box
(1 week, 2 weeks, etc.) that determines how long it rides the belt. Multiple
packages ride the belt concurrently. The belt moves at a constant speed (the
daily reading budget), and the scheduler's job is to keep the belt
uniformly loaded.

```
     ┌─────────────────────────────────────────────────────────┐
     │  Pipeline (conveyor belt)                               │
     │                                                         │
     │  ┌──┐ ┌────────┐ ┌──────────────────┐ ┌────┐           │
     │  │1w│ │  4w    │ │     12w          │ │ 2w │           │  → completions
     │  └──┘ └────────┘ └──────────────────┘ └────┘           │
     │                                                         │
     │  Daily load ≈ constant across the entire belt           │
     └─────────────────────────────────────────────────────────┘
```

### Glossary

| Term | Definition |
|------|-----------|
| **Pace target** | The user's desired throughput: e.g. 50 books/year |
| **Takt time** | Completion interval required to hit pace: `365 / pace` days (e.g. 7.3 days) |
| **Daily budget** | Total reading minutes per day across all concurrent books |
| **Tier** | A fixed calendar duration for a book (1w, 2w, 3w, 4w, 6w, 12w, 26w, 52w) |
| **Daily share** | A single book's contribution to the daily budget (book_minutes / reading_days) |
| **WIP** | Work in progress — number of books being read concurrently |
| **Max budget** | User-set ceiling on daily reading time (the system will never schedule above this) |
| **Deficit/surplus** | Gap between expected and actual completions at any point in time |

## The Three Invariants

Every scheduler run **must** satisfy all three:

### Invariant 1: Pace is the constraint

The pace target (e.g. 50 books/year) is the primary input. The daily
reading budget is **derived** from the pace target and the book mix — it is
an output of the scheduler, not an input. The scheduler adjusts the daily
budget up or down to hit the pace target, never the reverse.

```
pace_target → required throughput → daily budget → tier assignments
                                                  (not the other way around)
```

### Invariant 2: Daily load is leveled

The sum of daily shares across all concurrent books should be approximately
equal on every reading day. Peaks and valleys violate heijunka. The
scheduler selects tiers to **minimize variance** in daily load across the
timeline, not to find the shortest tier that fits under a ceiling.

### Invariant 3: Throughput is verified

After placing all books, the scheduler **must** count projected completions
over the next 365 days (or whatever the pace window is). If the count does
not equal the pace target (within a tolerance band), the schedule is
invalid and must be adjusted.

## Algorithm

### Phase 1: Measure actuals (closed-loop feedback)

Before planning forward, the scheduler measures where the user actually
stands relative to their pace target. This is the **control loop** that
turns the scheduler from an open-loop planner into a closed-loop control
system.

```
pace_start       = user.reading_pace_set_on (or beginning of year)
days_elapsed     = today - pace_start
days_remaining   = 365 - days_elapsed
expected_by_now  = pace_target × (days_elapsed / 365)
actual_completed = books completed since pace_start
deficit          = expected_by_now - actual_completed  (positive = behind)
```

The deficit tells us whether the user is ahead of or behind pace. A
positive deficit means they're behind and need to read slightly more per
day to catch up. A negative deficit (surplus) means they can ease off.

### Phase 2: Compute the adjusted daily budget

The daily budget has two components:

1. **Baseline budget**: the daily reading time required to maintain pace,
   assuming the remaining books are of average length.

2. **Recovery adjustment**: a small increment (or decrement) spread evenly
   across the remaining days to absorb the deficit or surplus.

```
books_remaining_for_pace = pace_target - actual_completed
avg_book_minutes         = rolling window average (next N books in queue,
                           backfilled with recent completions)
total_remaining_minutes  = books_remaining_for_pace × avg_book_minutes
baseline_daily           = total_remaining_minutes / days_remaining
```

The adjustment is proportional to the deficit and spread over the remaining
time — this is **rate-based recovery**, never spike-based:

```
adjusted_daily = baseline_daily
               = total_remaining_minutes / days_remaining
```

Note: the deficit is inherently captured because `books_remaining_for_pace`
accounts for how many books have (or haven't) been completed. If the user
is behind, more books remain to be read in fewer days → the budget goes up
naturally. If ahead, fewer books remain → budget eases off.

**Ceiling guard**: The adjusted daily budget is capped at `user.max_daily_reading_minutes`.
If the required budget exceeds the ceiling, the system should surface this
to the user: "At your current pace, you'd need X min/day to hit your target.
Your max is Y. Consider adjusting your pace target or adding reading time."

### Phase 3: Level-load tier assignment

For each book in the queue, select the tier that produces the most
uniform daily load across the timeline. This replaces the current
"shortest tier under ceiling" heuristic.

**Selection criterion**: For each candidate tier, compute what the daily
load profile would look like if the book were placed there. Choose the
tier that minimizes the variance (or max deviation) of daily load across
all reading days in the book's span.

```
for each book in queue order:
  for each tier (shortest first):
    candidate_share = book_minutes / reading_days_in_tier
    projected_load  = existing_daily_loads + candidate_share (for each day in span)
    variance        = measure deviation from target daily budget
    track best (tier, start_date) that minimizes variance

  place book in best tier
  update daily load profile
```

**Monday snapping**: All tiers still snap to Monday boundaries. This is
preserved for psychological consistency.

**Tie-breaking**: When multiple tiers produce similar variance, prefer
the shorter tier (higher throughput per slot).

### Phase 4: Verify throughput

After all books are placed, count projected completions:

```
projected_completions = count of books with target_completion_date
                        within (today..today + 365)
```

If `projected_completions < pace_target`:
- The pipeline is under-loaded. Either:
  - The queue doesn't have enough books (surface to user: "Add N more books
    to maintain your pace")
  - The daily budget needs to increase (check against max ceiling)
  - Some books could move to shorter tiers

If `projected_completions > pace_target + tolerance`:
- The pipeline is over-loaded. Ease off — move some books to longer tiers
  or reduce the daily budget.

**This verification step is mandatory.** A schedule that doesn't hit the
pace target is wrong, regardless of how neatly the tiers pack.

### Phase 5: Generate quotas

Once tier placements are finalized, generate daily page quotas using the
existing `ProfileAwareQuotaCalculator`. This step is unchanged — it
distributes pages proportionally across reading days within each book's
tier span.

## The Cumulative Production Curve

At any point in time, two values define the user's position:

```
Expected completions = pace_target × (days_elapsed / 365)
Actual completions   = books.completed.where("completed_at >= ?", pace_start).count
```

Plotting these over time produces two lines:
- **Expected**: a straight diagonal line from (0, 0) to (365, 50)
- **Actual**: a staircase that steps up by 1 with each completion

The vertical gap = deficit (below the line) or surplus (above the line).

This curve is the primary diagnostic for the system. It answers "am I on
pace?" at a glance, and the scheduler uses it as input on every run.

## Handling Real-World Variance

### Missed reading days (vacation, illness)

The user falls behind — deficit grows. On the next scheduler run:
- `books_remaining_for_pace` stays the same but `days_remaining` shrinks
- The daily budget increases slightly to spread recovery over remaining days
- No spike: a week off in June might mean 3-4 extra minutes per day for
  the rest of the year

### Binge reading (long flight, rainy weekend)

The user gets ahead — surplus grows. On the next scheduler run:
- Some books may have been completed early
- `books_remaining_for_pace` decreases → budget eases
- The pipeline relaxes: books may shift to slightly longer tiers

### Heavy books entering the queue

When several large books are added:
- Average book minutes in the rolling window increases
- The daily budget adjusts upward accordingly
- But the **max budget ceiling** prevents unsustainable spikes
- If the math doesn't work within the ceiling, the user is notified

### Queue running low

If there aren't enough books queued to sustain pace:
- The throughput verification (Phase 4) catches this
- Surface to user: "You have N books scheduled. At your current pace,
  you'll run out of scheduled books in X weeks. Add more to stay on pace."

## Tier System

Tiers are preserved for psychological reasons (see CLAUDE.md). They provide:
- **Predictable rhythms**: "I start and finish books on Mondays"
- **Parallel variety**: Long books at low daily doses alongside short books
  at higher doses
- **Mental framing**: "This is a 4-week book" feels different from "this
  is a 28-day book"

### Available tiers

| Tier | Duration | Typical use |
|------|----------|-------------|
| 1 week | 7 days | Short books, novellas |
| 2 weeks | 14 days | Average-length books |
| 3 weeks | 21 days | Slightly longer books |
| 4 weeks | 28 days | Standard novels |
| 6 weeks | 42 days | Longer novels |
| 12 weeks | 84 days | Non-fiction, dense reads |
| 26 weeks | 182 days | Major works, read slowly |
| 52 weeks | 364 days | Year-long projects |

### Tier selection criterion (restated)

**Old**: "Shortest tier where daily_share ≤ budget + tolerance"
**New**: "Tier that minimizes daily load variance across the timeline"

Both prefer shorter tiers when possible (higher throughput), but the new
criterion explicitly optimizes for load consistency rather than just
fitting under a ceiling.

## Weekend Handling

Three modes (unchanged from current):

- **Skip**: No reading on weekends. Daily budget applies to weekdays only.
  Tiers still span calendar weeks but quotas only fall on weekdays.
- **Same**: Equal reading every day. Budget divided by 7.
- **Capped**: Weekends have a separate (usually lower) reading budget.
  Weekday budget absorbs the remainder.

## What the Scheduler Does NOT Do

- **Does not override user agency.** If the user drags a book on the
  pipeline chart, the scheduler respects that placement and works around it.
  Locked goals (those with reading sessions) are never moved.

- **Does not create spikes to recover.** Recovery from deficit is always
  spread evenly across remaining time. The system will never schedule a
  "catch-up week."

- **Does not exceed the max budget ceiling.** If the math requires more
  daily reading than the user allows, the system surfaces the conflict
  rather than silently over-scheduling.

- **Does not schedule books the user hasn't queued.** It can *recommend*
  adding books, but never auto-adds.

## Triggers

The scheduler runs on any of these events:
- Book added to reading list
- Reading list reordered
- Book completed or abandoned
- Goal manually rescheduled (drag on pipeline)
- Goal deleted
- User changes pace target or reading preferences

Every run executes the full algorithm: measure actuals → compute budget →
level-load → verify throughput → generate quotas.

## Key Metrics to Surface

These metrics should be available in the UI (pipeline view, dashboard):

1. **Pace status**: "On pace" / "2 books behind" / "1 book ahead"
2. **Current daily budget**: "42 min/day" (derived, not set)
3. **Projected completions**: "47 of 50 books by Dec 31" (if queue is short)
4. **Queue depth warning**: "Add 3+ books to maintain pace through August"
5. **Budget vs. ceiling**: "Your pace requires 45 min/day (max: 60)"

## Relationship to Existing Code

| Component | Role in heijunka system |
|-----------|------------------------|
| `ReadingListScheduler` | The core engine — must implement all 5 phases |
| `ProfileAwareQuotaCalculator` | Phase 5 — distributes pages within a placed tier (unchanged) |
| `QuotaRedistributor` | Book-level mid-course correction (unchanged) |
| `User#reading_pace_*` | Source of pace target and max budget |
| `User#derive_daily_minutes_from_pace` | Replaced by Phase 2 budget computation |
| `ReadingGoal` | Carries placement result (started_on, target_completion_date) |
| Pipeline chart (D3) | Visualizes the leveled load + cumulative curve |

## Design Constraints for Future Changes

1. **Never derive pace from budget.** Budget flows from pace, not the
   reverse. If you find yourself computing pace from daily minutes, the
   causality is backwards.

2. **Never place a book without verifying throughput.** Phase 4 is not
   optional. A schedule that doesn't project to the pace target is a bug.

3. **Never create a spike to recover from a deficit.** Spread recovery
   evenly. The max daily increase from recovery should be bounded.

4. **Preserve tier boundaries.** Tiers snap to Mondays and span fixed
   week counts. Do not introduce arbitrary-duration placements.

5. **Respect locked goals.** Any goal with reading sessions is immovable.
   The scheduler works around it.

6. **Surface conflicts, don't hide them.** If pace is unachievable within
   the max budget, tell the user. Don't silently under-deliver.
