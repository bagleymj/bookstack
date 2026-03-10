# Scheduling System Design — Heijunka for Books

This document defines the principles and invariants that govern BookStack's
reading pipeline scheduler. All future changes to scheduling logic **must**
honor these constraints.

## Core Principle

The scheduler implements **heijunka** (production leveling) for reading. The
goal is to deliver a precise number of books per year with a consistent,
sustainable daily reading load — no spikes, no valleys, no hoping it works
out.

The user should be able to open the app every day and see exactly what to
read — assignments that honor the pace target, reflect reality through
yesterday, and just work. No manual redistribution. No catch-up decisions.
The system adapts continuously and autonomously.

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

### The Reading List as Order Backlog

The reading list is a queue of **orders** — books the user has committed to
reading, in priority sequence. Queue position determines **sequence** (which
book enters the pipeline next) but NOT **speed**. A book that's first in
line doesn't get rushed through a 1-week tier if that would spike the daily
load. It gets the tier that keeps the belt level.

Individual lead times vary by design. A 600-page book at position #1 may
take 6 weeks while a 150-page book at position #5 enters concurrently and
finishes in 1 week. That's not queue-jumping — that's the system working
correctly. The small package flows through faster because it's smaller, not
because it's more important.

The system's promise is about **throughput rate**, not individual lead times:
regardless of which specific book ships when, the rate of completions is
steady and matches the pace target.

### Glossary

| Term | Definition |
|------|-----------|
| **Pace target** | The user's desired throughput: e.g. 50 books/year |
| **Takt time** | Completion interval required to hit pace: `365 / pace` days (e.g. 7.3 days) |
| **Daily budget** | Total reading minutes per day across all concurrent books |
| **Tier** | A fixed calendar duration for a book (1w, 2w, 3w, 4w, 6w, 12w, 26w, 52w) |
| **Daily share** | A single book's contribution to the daily budget (book_minutes / reading_days) |
| **WIP** | Work in progress — number of books being read concurrently |
| **Derived budget** | The daily reading minutes computed by the scheduler from pace + book mix (an output, not an input) |
| **Deficit/surplus** | Gap between expected and actual completions at any point in time |
| **Tier promotion** | Moving a book to a longer tier when it can't complete in its current tier without spiking |
| **Work cell** | The current week's committed books — fixed from Monday to Sunday, no mid-week changes |
| **Ad-hoc session** | Reading logged against a book not currently on the pipeline; counts toward future scheduling |

## The Five Invariants

Every scheduler run **must** satisfy all five:

### Invariant 1: Pace is the constraint

The pace target (e.g. 50 books/year) is the primary input. The daily
reading budget is **derived** from the pace target and the book mix — it is
an output of the scheduler, not an input. The scheduler adjusts the daily
budget up or down to hit the pace target, never the reverse.

```
pace_target → required throughput → daily budget → tier assignments
                                                  (not the other way around)
```

**Pace types are throughput-based only.** Valid pace types:
- `books_per_year` (e.g. 50)
- `books_per_month` (e.g. 4)
- `books_per_week` (e.g. 1)

The `minutes_per_day` pace type is **deprecated** — it inverts the
causality (budget → pace instead of pace → budget). Existing users with
`minutes_per_day` should be migrated or prompted to set a throughput
target. The system must not allow new pace targets in minutes_per_day.

### Invariant 2: Daily load is leveled

The sum of daily shares across all concurrent books should be approximately
equal on every reading day — and should track the derived budget. Peaks
and valleys both violate heijunka. The scheduler uses **Monday-by-Monday
bin filling**: each Monday is filled to just above budget before
advancing to the next. This front-loads the timeline — books fill to
100% of budget for as long as possible, with natural taper only when
books run out. Overshoot beyond a 15-minute tolerance is always the
worst violation.

### Invariant 3: Throughput is verified

After placing all books, the scheduler **must** count projected completions
over the next 365 days (or whatever the pace window is). If the count does
not equal the pace target (within a tolerance band), the schedule is
invalid and must be adjusted.

### Invariant 4: No spikes — ever

The system will never ask the user to read significantly more on one day
than any other to recover from a deficit or meet a deadline. If a plan
requires spiking, the plan must change — the pace stays level. This applies
to both macro recovery (weeks of missed reading) and micro recovery
(individual books falling behind within their tier).

### Invariant 5: The system reflects reality through yesterday

Every scheduler run incorporates all actual reading data through the
previous day. Quotas, tier assignments, and the daily budget always reflect
what really happened — not what was planned. The user never needs to
manually redistribute, catch up, or acknowledge discrepancies. The system
adapts automatically and continuously.

## Hard Constraints

These are non-negotiable rules that the scheduler must always obey:

### Monday starts (strategic) / Weekly commitment (tactical)

The Monday rule operates at two levels:

**Strategic (planning):** When the scheduler places a book from the queue
into the pipeline, it always starts on a Monday. Tier durations are
measured in whole weeks from that Monday. The pipeline chart shows clean,
week-aligned blocks. This exists for psychological consistency and does not
affect the leveling algorithm — it simply restricts the set of valid
planned start dates.

**Tactical (execution):** The books assigned for the current week are a
**committed work cell**. The user has those books physically on hand. The
system does not swap books mid-week, add new books mid-week, or change
which books are active before the next Monday. Within the week:

- **Over-reading** is banked: pages read ahead reduce future quotas for
  that book. If the user finishes a book early, the completion is recorded
  but no new book enters until the next Monday. The remaining days of the
  week simply have less total reading (the belt runs lighter).
- **Under-reading** redistributes within the week: remaining pages spread
  across remaining days for that book. If redistribution would create a
  spike (daily load exceeds the derived budget), tier promotion kicks in
  immediately — the book's end date extends by one week and quotas
  regenerate across the longer range.
- **New books only enter on Mondays**, after the system has absorbed the
  previous week's actuals and re-leveled the pipeline.

This means the pipeline re-levels weekly at the Monday boundary, not
mid-week. The daily reflow (Invariant 5) adjusts quotas within the current
week's committed books, but does not change which books are active.

### Book commitment

Once a book has reading sessions, the system **never** removes it from the
pipeline. The user committed to reading it, and the system honors that
commitment. The scheduler treats committed books as fixed load on the belt
and plans everything else around them.

The system may **adjust** a committed book (promote it to a longer tier,
adjust its daily share) but will never abandon it or swap it out without
explicit user action.

### Concurrency limit

The user sets a **hard cap** on how many books can be active (on the
pipeline) at once. The scheduler never exceeds this cap.

- The cap is user-controlled and can be set to any value, including
  "no limit" (effectively unlimited concurrency).
- **Fewer concurrent books is generally better.** The system should prefer
  placing books sequentially rather than stacking many in parallel. High
  concurrency dilutes focus and creates absurd schedules ("read 1 page
  from each of 20 books").
- **Surface conflicts, don't silently fail.** If the pace target requires
  more concurrency than the cap allows, tell the user: "Your pace of 50
  books/year requires at least 3 concurrent books, but your limit is 2.
  Either increase the limit or reduce your pace target."
- The cap applies to scheduled pipeline books only. Ad-hoc reading
  sessions against unscheduled books do not count toward the cap.

### Empty work cell (mid-week completion)

When all books in the current week's work cell finish before Sunday, the
system **suggests ad-hoc reading** rather than formally scheduling a new
book mid-week (which would violate the weekly commitment rule).

The suggestion surfaces in the UI: "You're ahead of schedule! Consider
starting [next book in queue] early." If the user reads it, those pages
are recorded as ad-hoc sessions — they count toward the book's progress
and reduce its tier when it officially enters the pipeline on Monday.

**The system does not:**
- Auto-schedule the next book into the current week
- Show an empty/blank state with nothing to do
- Force the user to wait until Monday with no guidance

This keeps the weekly commitment rule intact while giving the user
something productive to do with their momentum.

### Automatic reflow (the daily heartbeat)

The daily reflow is the system's **single scheduling loop**. It runs once
per day (lazy — triggered on first app access when quotas are stale) and
performs the full scheduling cycle:

1. **Mark missed quotas** from yesterday
2. **Check tier promotions** — extend books that can't complete without
   spiking
3. **Run the full scheduler** (`ReadingListScheduler.schedule!`) — measures
   actuals, computes budget, places queued books, verifies throughput,
   generates quotas for all schedulable goals
4. **Redistribute pages** for locked goals only (active books with reading
   sessions, which the scheduler treats as fixed load)
5. **Update timestamp** so reflow doesn't re-run until tomorrow

Because all tier placements snap to Monday boundaries, new books still
only enter the pipeline on Mondays — but the scheduler *evaluates* daily.
Running it on a Wednesday doesn't place a book starting Wednesday; it
places the book starting the following Monday. The daily cadence means
the system absorbs completions, promotions, and queue changes quickly
without requiring a separate "weekly reflow" concept.

The user never needs to intervene. The system continuously reflects
reality.

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

The daily budget is derived from the pace target and what remains:

```
books_remaining_for_pace = pace_target - actual_completed
avg_book_minutes         = rolling window average (next N books in queue,
                           backfilled with recent completions)
total_remaining_minutes  = books_remaining_for_pace × avg_book_minutes
baseline_daily           = total_remaining_minutes / days_remaining
```

The deficit is inherently captured: if the user is behind,
`books_remaining_for_pace` is larger (more books to read) while
`days_remaining` is smaller (less time) → budget goes up naturally. If
ahead, fewer books remain → budget eases off. This is **rate-based
recovery** — correction proportional to error, spread over remaining time.

There is no ceiling on the derived budget. The budget is what the pace
and book mix require. If the user wants a lower daily commitment, they
adjust their pace target or choose shorter books. The controls are the
inputs (pace, book selection), not the output (budget).

### Phase 3: Monday-by-Monday bin filling

Instead of placing books and then scoring the result, the scheduler
**fills time slots**. It walks Mondays in order and fills each one to
just above the daily budget before advancing. This naturally produces
level schedules because the fill-forward approach guarantees every
Monday carries at least budget-level load.

**Algorithm**:

1. Pre-compute a **share index**: for each schedulable book, cache its
   `book_minutes` (reading time estimate). Daily shares are computed
   lazily per (book, monday, tier) combination.
2. Walk Mondays from earliest to latest across a 104-week horizon.
3. For each Monday:
   - **Skip** if spillover from prior multi-week placements already
     puts this Monday at or above budget.
   - **Fill loop**: Take the next unscheduled book (queue order). Try
     tiers shortest to longest — use the first tier whose daily share
     fits under remaining headroom (keeps Monday below budget). If
     placement keeps Monday under budget, continue filling.
   - **Backfill**: When no book fits under budget, find the (book, tier)
     across all remaining books that overshoots budget by the least
     amount. Place it — Monday is filled — advance to the next Monday.
4. Any books still unscheduled after the horizon get a fallback
   52-week placement.

```
for each monday (earliest first):
  skip if load already >= budget (from spillover)
  break if no unscheduled books remain

  loop:
    try next unscheduled book in shortest-fitting tier
    if fits under budget → place it, continue filling
    if at/above budget → Monday done, advance
    if nothing fits → backfill with min-overshoot → advance
```

**Key properties**:

- **Every Monday filled above budget**: The algorithm guarantees
  `load >= budget` before advancing. No Monday is left under-filled.
- **Queue order preserved**: Books are placed in the user's reading
  list order (position), not sorted by size.
- **Shortest-fitting tier preferred**: For each book, try tiers from
  shortest to longest; use the first one whose daily share fits under
  remaining headroom. This naturally selects longer tiers when headroom
  is tight (a short tier's high share would overshoot).
- **Backfill = minimal overshoot**: When no book fits under budget,
  pick the (book, tier) that overshoots by the least — this is the
  "just above target" behavior.
- **Self-leveling**: Multi-week tiers placed on early Mondays spill
  load into later Mondays, reducing headroom. Later Mondays may
  already be above budget from spillover alone — they're simply skipped.
- **No refinement pass needed**: Because the algorithm fills forward
  with full knowledge of current load, it doesn't need post-hoc
  correction. The fill-forward approach is inherently self-leveling.

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
  - Some books could move to shorter tiers (increases daily budget)

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

## Continuous Reflow

The scheduler operates as a **single daily loop**. The daily reflow runs
the full scheduler every day, but new books only enter on Monday
boundaries (tier placements snap to Mondays).

### Daily reflow (the full cycle)

Each day, the system runs the complete scheduling pipeline:

1. **Marks missed quotas**: Yesterday's unfinished quotas become "missed"
2. **Promotes spiking goals**: Extends books that can't complete without
   exceeding the daily budget (tier promotion)
3. **Runs the scheduler**: Measures actuals → computes budget → places
   queued books (starting on next Monday) → verifies throughput →
   generates quotas for all schedulable goals
4. **Redistributes locked goals**: For active books with reading sessions
   (which the scheduler treats as fixed load), redistributes remaining
   pages across remaining days

The scheduler is idempotent — running it daily simply absorbs whatever
changed since yesterday (completions, promotions, queue changes, ad-hoc
sessions). On non-Monday days, the scheduler evaluates but typically
finds no new Monday slots to fill. On Mondays, new books enter the
pipeline through the same code path.

This replaces the earlier "daily reflow + weekly reflow" two-cadence
model. There is no separate weekly trigger — the daily reflow IS the
scheduler.

### Tier promotion (line rebalancing)

When an active book falls behind within its tier, the system checks: can
the remaining pages be completed in the remaining days without exceeding
the leveled daily budget?

If **yes**: redistribute remaining pages across remaining days. The daily
share for this book increases slightly, absorbed by the leveled budget.

If **no**: the book has fallen too far behind to complete in its current
tier without spiking. The system **promotes** the book to the next longer
tier:

```
Example:
- Book A is in a 1-week tier (Mon–Sun)
- By Wednesday, no pages have been read
- Remaining: 200 pages in 4 days = 50 pages/day → would spike
- System promotes to 2-week tier: 200 pages in 11 days = ~18 pages/day
- The freed-up daily capacity can absorb a short backfill book
```

**Tier promotion rules:**

1. Promotion extends the end date by **one week at a time**. Multiple
   extensions may occur in a single reflow if the load remains above
   budget (capped at 5 extensions per cycle for safety)
2. Promotion preserves any pages already read — only remaining work is
   redistributed
3. The end date always extends by full weeks (7 days)
4. Promotion is automatic — no user intervention needed
5. Promotion fires **daily** during reflow, not only at Monday boundaries.
   The no-spike invariant is more fundamental than the weekly boundary
6. At the weekly Monday boundary, the full scheduler also checks tier
   viability and may re-level the entire pipeline

### Backfill on promotion

When a tier promotion frees up daily capacity (the promoted book's share
drops), the scheduler may pull the next queued book into the pipeline to
fill the valley:

```
Before promotion:
  Mon  Tue  Wed  Thu  Fri  Sat  Sun
  [Book A: 30 min/day              ]   ← 1-week tier, not started
  [Book B: 15 min/day                          ]   ← 4-week tier
  Total: 45 min/day

After promotion (Book A → 2-week tier):
  Mon  Tue  Wed  Thu  Fri  Sat  Sun  Mon ...
  [Book A: 15 min/day                         ]   ← now 2-week tier
  [Book B: 15 min/day                          ]
  [Book C: 15 min/day   ]                         ← backfill, 1-week tier
  Total: 45 min/day (leveled)
```

Backfill only happens at the **Monday boundary** (weekly reflow), because:
- The current week's books are a committed work cell — no mid-week changes
- The user needs to have the book physically on hand
- Backfill requires a full re-level to maintain load consistency

Backfill conditions:
- There are queued books available
- Adding the book doesn't cause a spike elsewhere in the timeline
- The leveling math supports it

### What does NOT trigger tier promotion

- A single missed day does not trigger promotion. The redistribution
  within the tier absorbs it.
- Being slightly behind (can still catch up within the tier at the
  leveled budget) does not trigger promotion.
- Promotion only fires when the math proves the book **cannot** complete
  in its tier without exceeding the daily budget.

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
- Individual books that fell too far behind get tier-promoted

### Binge reading (long flight, rainy weekend)

The user gets ahead — surplus grows. On the next scheduler run:
- Some books may have been completed early
- `books_remaining_for_pace` decreases → budget eases
- The pipeline relaxes: books may shift to slightly longer tiers
- The user feels rewarded: tomorrow's reading assignment is lighter

### Heavy books entering the queue

When several large books are added:
- Average book minutes in the rolling window increases
- The daily budget adjusts upward accordingly
- The system surfaces the new budget so the user can see the impact:
  "Adding these books increases your daily reading to 75 min/day.
  Lower your pace or remove books to reduce it."

### Queue running low

If there aren't enough books queued to sustain pace:
- The throughput verification (Phase 4) catches this
- Surface to user: "You have N books scheduled. At your current pace,
  you'll run out of scheduled books in X weeks. Add more to stay on pace."

### A book goes untouched for its first week

This is the tier promotion case described above. The system doesn't panic.
It promotes the book to a 2-week tier, redistributes its pages at a
comfortable daily rate, and may backfill a short book into the freed
capacity. The daily budget stays level. The pace target stays on track.

### Spontaneous reading (ad-hoc sessions)

The user picks up a book that's further down the queue — not currently
scheduled — and reads 50 pages on a Sunday afternoon. This is real
progress and the system should honor it.

**How it works**: The user logs an ad-hoc reading session against any book
in their collection, regardless of whether it's currently on the pipeline.
The pages are recorded. When the scheduler next runs (Monday reflow):

- The book now has fewer remaining pages
- When it eventually enters the pipeline, it gets a shorter tier or lower
  daily share than it would have otherwise
- If enough pages were read ad-hoc, the book might skip straight to a
  1-week tier or even be mostly done before it's "officially" scheduled

**What it does NOT do**:
- Does not pull the book into the current week (weekly commitment stands)
- Does not change the queue order (the book stays at its position)
- Does not count as a "completion" until the book is actually finished
- Does not affect the current week's quotas for other books

Ad-hoc sessions are the system's way of absorbing spontaneous reading
without disrupting the leveled plan. The work counts, the schedule adjusts,
but the weekly commitment remains stable.

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

**Monday bin filling**: For each book, the scheduler tries tiers from
shortest to longest and uses the first tier whose daily share fits
under remaining headroom on the current Monday. When no tier fits
under budget, the (book, tier) combination that overshoots budget by
the least is chosen. This naturally selects longer tiers for larger
books (their short-tier shares are too high) and shorter tiers for
small books (they fit under headroom easily).

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

- **Does not schedule books the user hasn't queued.** It can *recommend*
  adding books, but never auto-adds.

- **Does not require user intervention to adapt.** No manual redistribute
  buttons, no catch-up actions, no discrepancy acknowledgements. The system
  observes reality and adjusts autonomously.

- **Does not abandon books.** Once a book has reading sessions, it stays
  on the pipeline. The system may promote its tier but will never remove it
  without explicit user action.

- **Does not change the work cell mid-week.** The books committed for the
  current week are fixed. No new books enter, no books are swapped out.
  Adjustments to quotas happen within the committed set. Pipeline changes
  happen at the Monday boundary.

## Triggers

### Daily reflow (the scheduling heartbeat)

The daily reflow runs once per day on first app access (lazy evaluation).
It executes the full algorithm: mark missed quotas → promote spiking goals
→ run scheduler (measure actuals → compute budget → place books → verify
throughput → generate quotas) → redistribute locked goals.

New books enter the pipeline on the next Monday boundary. The daily
cadence ensures the system absorbs changes quickly — a book completed on
Tuesday is accounted for on Wednesday's reflow, and the freed slot is
filled starting the following Monday.

**Book completion and abandonment do NOT trigger an immediate reschedule.**
The daily reflow picks them up the next morning.

### Immediate triggers (deliberate queue changes)

These actions call `schedule!` immediately because the user expects to
see the pipeline update in response to their action:

- Book added to reading list
- Reading list reordered
- Goal deleted
- User changes pace target or reading preferences
- Goal manually rescheduled (drag on pipeline)
- Ad-hoc reading session against a **queued** book (updates remaining
  pages so future placement reflects reality)

## Key Metrics to Surface

These metrics should be available in the UI (pipeline view, dashboard):

1. **Pace status**: "On pace" / "2 books behind" / "1 book ahead"
2. **Current daily budget**: "42 min/day" (derived, not set)
3. **Projected completions**: "47 of 50 books by Dec 31" (if queue is short)
4. **Queue depth warning**: "Add 3+ books to maintain pace through August"
5. **Budget impact**: "Your pace requires 45 min/day with your current book mix"

## Relationship to Existing Code

| Component | Role in heijunka system |
|-----------|------------------------|
| `ReadingListScheduler` | The core engine — must implement all phases |
| `ProfileAwareQuotaCalculator` | Phase 5 — distributes pages within a placed tier (unchanged) |
| `QuotaRedistributor` | Subsumed by continuous reflow — may be simplified or removed |
| `User#reading_pace_*` | Source of pace target |
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

5. **Respect committed books.** Any book with reading sessions stays on
   the pipeline. The system may promote its tier but never removes it.

6. **Surface impacts, don't hide them.** Always show the derived daily
   budget so the user understands the cost of their pace + book mix.

7. **No manual intervention required.** The system must adapt to reality
   automatically. If a feature requires the user to manually trigger
   redistribution or acknowledge discrepancies, it violates this constraint.

8. **Promote, don't spike.** When a book can't complete in its tier at
   the leveled daily budget, promote it to the next tier. Never increase
   its daily share beyond what the budget allows.

9. **Respect the weekly work cell.** Never change which books are active
   mid-week. Daily reflow adjusts quotas within the committed set and
   may extend end dates to prevent spikes (same books, longer duration).
   Adding new books and backfills happen at Monday boundaries only.

10. **Honor ad-hoc reading.** Pages read against any book count toward
    that book's progress and affect future scheduling. But ad-hoc sessions
    never disrupt the current week's committed work cell.

11. **Respect concurrency limits.** Never schedule more concurrent books
    than the user's hard cap. If the pace target is unachievable within
    the concurrency limit, surface the conflict.

12. **Suggest, don't force, when ahead.** When the work cell empties
    mid-week, suggest ad-hoc reading of the next queued book. Never
    auto-schedule or show a blank state.

## Implementation Gaps

Status of all identified gaps:

### ~~Gap 1: `max_daily_reading_minutes` column~~ — ELIMINATED

No max ceiling needed. The budget is derived from pace + book mix. The
user controls it by adjusting pace or choosing different books. Adding
a ceiling would re-introduce the budget-first thinking we're eliminating.

### Gap 2: `concurrency_limit` column

The concurrency hard cap does not exist in the schema. Needs a
`concurrency_limit` integer column on `users` (nullable = no limit).

### ~~Gap 3: Phase 3 objective function~~ — RESOLVED

**Decision: Monday-by-Monday bin filling.** Phase 3 walks Mondays in
order, filling each to just above the daily budget before advancing.
For each Monday, books are tried in queue order with the shortest-
fitting tier; when no book fits under budget, the (book, tier) with
minimal overshoot is placed. Multi-week tiers spill load into future
Mondays, making the approach self-leveling with no separate refinement
pass needed.

### ~~Gap 4: Phase 4 feedback loop~~ — RESOLVED

**Algorithm:**

1. After Phase 3 places all books, count projected completions within
   the pace window.
2. **Tolerance band**: ±2 books (or ±5%, whichever is larger).
3. **If under-loaded** (too few completions):
   a. Try shortening the longest-tier unstarted book by one tier step.
   b. Re-check. Repeat up to 5 iterations.
   c. If still under: surface "Add N more books to maintain pace."
4. **If over-loaded** (too many completions):
   a. Try lengthening the shortest-tier unstarted book by one tier step.
   b. Re-check. Repeat up to 5 iterations.
   c. If still over: accept (being ahead of pace is fine).
5. **Termination**: Stop when within tolerance or after 5 iterations.
6. Never adjust committed books (those with reading sessions). Only
   modify unstarted/queued placements.

### ~~Gap 5: Daily reflow execution mechanism~~ — RESOLVED

**Decision: Lazy reflow.** The first time a user accesses the app each
day, the system checks whether quotas are stale (last generated before
today). If so, it reflows the current week's quotas based on all activity
through the previous day, then serves fresh assignments.

No background jobs, no cron. Simple timestamp check on access. Stale
data between visits is a non-issue — the user only sees quotas when
they open the app, which is exactly when reflow fires.

### ~~Gap 6: `minutes_per_day` deprecation~~ — RESOLVED

**Decision: Heijunka-first.** Remove `minutes_per_day` as a pace option.
Only throughput-based pace types are supported: `books_per_year`,
`books_per_month`, `books_per_week`. The old `daily_reading_minutes`
field on users is no longer used by the scheduler (budget is derived).
It can remain in the schema for now as a legacy field but the scheduler
ignores it.
