# Scheduling System Design — Heijunka for Books

This document defines the principles and invariants that govern BookStack's
reading pipeline scheduler. All future changes to scheduling logic **must**
honor these constraints.

## What This System Is

You want to read 50 books this year. You have a list of books, in order.
You open the app and it tells you what to read today — the same total time
every day, predictable, sustainable. You pack books for a trip on Friday
and they're the same books Monday morning.

The schedule only changes when something real changes: you finish a book,
you add a book, your reading speed data updates, or a reading day passes.
Not because the calendar rolled from Sunday to Monday. Not because you
didn't read yesterday. Not because of anything invisible.

The system's job is to turn a pace target into daily assignments. The user
controls the inputs (pace, book list, concurrency limit). The system
controls the output (which books, which tiers, how many pages today).

## The Five Invariants

Every scheduler run **must** satisfy all five. These are not guidelines.

### Invariant 1: Pace is the constraint

The pace target (e.g. 50 books/year) is the primary input. The daily
reading target is **derived** from the pace target and the book mix — it is
an output, never an input. The scheduler adjusts the daily target up or
down to hit pace, never the reverse.

```
pace_target → books remaining × avg book time / reading days remaining → daily target
```

Valid pace types: `books_per_year`, `books_per_month`, `books_per_week`.
The `minutes_per_day` type is deprecated — it inverts the causality.

### Invariant 2: Daily load is leveled

The sum of daily shares across all concurrent books should be approximately
equal on every reading day. The scheduler fills each Monday to **just above
the daily target** before advancing to the next. This produces a flat load
profile across the timeline.

"Just above" means: among all valid combinations of books and tiers, pick
the one whose total daily load exceeds the target by the smallest amount.
Overshoot is expected and acceptable — it's how the math works with
discrete tier sizes. The leveling emerges from choosing the closest-above
combination at each slot.

### Invariant 3: Throughput is verified

After placing all books, the scheduler counts projected completions over
the pace window (365 days). If the count doesn't match the pace target
(within tolerance), the schedule is adjusted — tiers shortened or
lengthened until throughput aligns.

### Invariant 4: No spikes — ever

The system never asks the user to read significantly more on one day than
any other. Recovery from deficit is always rate-based: spread evenly over
remaining reading days, never crammed into a catch-up period.

### Invariant 5: The system reflects reality through yesterday

Every scheduler run incorporates all actual reading data through the
previous day. The user never needs to manually redistribute, catch up, or
acknowledge discrepancies. The system adapts automatically.

## Hard Constraints

### Reading days, not calendar days

If the user skips weekends, Saturday and Sunday **do not exist** for
scheduling purposes. They are not counted in days elapsed, days remaining,
or the daily target calculation. The daily target is identical on Friday
evening and Monday morning — the only thing that changes it is a reading
day passing.

This means:
- `days_remaining` = count of reading days from today to epoch end
- `days_elapsed` = count of reading days from epoch start to yesterday
- `daily_target` = minutes per **reading day** (no 7/5 scaling needed)
- Weekend quotas are 0 (skip mode) or equal to weekday quotas (same mode)

### Monday starts

New books enter the pipeline on **Mondays only**. Tier durations are
measured in whole weeks from that Monday. End dates always land on Sundays.
This provides predictable weekly rhythms.

The one exception: mid-week ramp-in. If the scheduler runs for the first
time mid-week (e.g. user sets up their pace on a Wednesday), the first
placement starts today and ends on the current week's Sunday. All
subsequent placements start on Mondays.

### Book commitment (started_on <= today)

Once a book's `started_on` date has arrived, it is **committed**. The
scheduler will not re-place it, change its start date, or remove it from
the pipeline.

The scheduler **may** adjust a committed book's end date:
- **Graduation** (extension): if the committed book's load exceeds the
  daily target, stretch it to a longer tier to reduce its daily share
- **Contraction** (shortening): if the committed book's load is well below
  target, shorten it to increase its daily share

Books with `started_on` in the future are **uncommitted** and freely
re-placeable. The scheduler may change their start date, tier, or position
as it re-evaluates on each run.

This means:
- No session-based locking. You don't need to have read a book to lock it.
- No week boundary resets. A book committed on Friday is still committed
  Monday.
- The schedule you see on Friday is the schedule you see on Monday (if no
  reading day passed and nothing else changed).
- **Postponement** (future): explicit user action to uncommit a book they
  started but don't want to continue right now. The book returns to the
  queue and gets rescheduled.

### Concurrency limit

The user sets a hard cap on concurrent books. The scheduler never exceeds
it. If the pace target requires more concurrency than the cap allows, the
system surfaces the conflict — it doesn't silently under-schedule.

### Queue order

The first unscheduled book in queue order is always the **anchor** — it
gets placed at the first available Monday. The scheduler never skips ahead
to place a later book before the anchor has been placed. Companions (books
placed alongside the anchor to fill to target) may come from anywhere in
the remaining queue.

## Algorithm

### Phase 1: Measure actuals

Count where the user stands relative to their pace target.

```
epoch_start           = user.reading_pace_set_on (advanced by 365-day epochs)
reading_days_elapsed  = count of reading days from epoch_start to yesterday
reading_days_remaining = count of reading days from today to epoch_end
total_reading_days    = count of reading days in the full epoch
actual_completed      = books completed since epoch_start
epoch_target          = annual_pace + carried_deficit_from_prior_epochs
deficit               = (epoch_target × reading_days_elapsed / total_reading_days) - actual_completed
```

The deficit tells us whether the user is ahead or behind pace. It feeds
directly into the daily target calculation.

### Phase 2: Derive the daily target

```
books_remaining = epoch_target - actual_completed
avg_minutes     = average reading time across books in current epoch
daily_target    = (books_remaining × avg_minutes) / reading_days_remaining
```

This is minutes per **reading day**. If the user is behind, fewer remaining
days with the same books → target goes up. If ahead, fewer remaining books
→ target eases. Rate-based recovery, no spikes.

Weekend modes:
- **Skip**: `weekday_target = daily_target`, `weekend_target = 0`
- **Same**: `weekday_target = weekend_target = daily_target`

No scaling needed — `reading_days_remaining` already excludes weekends
when the user skips them.

### Phase 3: Combinatorial Monday bin filling

The scheduler walks Mondays in order, filling each to just above the daily
target before advancing.

For each Monday:
1. **Skip** if spillover from prior multi-week placements already puts
   this Monday at or above target.
2. **Anchor** = first unscheduled book in queue order.
3. **Combination search**: evaluate all valid combinations of
   anchor × tier, optionally with companion books × their tiers (up to
   concurrency limit). Each combination is scored.
4. **Place** the winning combination. Their load spills into future Mondays.
5. Advance to the next Monday.

After all books are placed:
6. **Relax the last book**: if the last book placed pushed its slot above
   target, stretch it to the shortest tier that brings load at or below
   target. This prevents a spike at the end of the schedule when there are
   no future books to balance it. With a full queue at the pace target,
   this rarely fires — the math works out.

**Scoring** — closest above target:

```
projected = current_load + combo_shares

if projected >= target:
  score = [0, projected]     → above target: smallest overshoot wins
else:
  score = [1, -projected]    → below target: closest to target wins
```

Always prefer combinations that reach or exceed the target. Among those,
pick the smallest overshoot. If nothing reaches target, pick the closest
approach from below.

That's it. No tier-length penalties, no combo-size penalties, no tolerance
bands. The leveling emerges from always choosing closest-above — longer
tiers naturally win when they produce less overshoot, shorter tiers win
when they're needed to reach target.

**Key properties**:
- **Queue order preserved**: the anchor is always the first unscheduled
  book. It must be placed before any companions are considered.
- **Companions are flexible**: any future book can be a companion if it
  helps the mix hit target.
- **Self-leveling**: multi-week tiers spill load into future Mondays,
  reducing headroom. Later Mondays may already be above target from
  spillover alone — they're simply skipped.

### Phase 4: Verify throughput

After placement, count projected completions within the pace window. If
the count doesn't match the pace target (within tolerance), adjust tiers:

- **Under-loaded** (too few completions): shorten the longest-tier book
  by one step. Re-check. Repeat up to 5 times. If still under: surface
  "Add N more books to maintain pace."
- **Over-loaded** (too many completions): lengthen the shortest-tier book
  by one step. Re-check. Repeat up to 5 times.

Adjustments respect leveling — won't shorten a tier if it would spike load,
won't lengthen if it would create a valley below target.

### Phase 5: Generate quotas

Distribute pages across reading days within each book's tier span using
`ProfileAwareQuotaCalculator`. This step is mechanical — it takes the tier
placements from Phase 3-4 and produces daily page assignments.

## Daily Reflow

The scheduler runs once per day, lazily triggered on first app access when
quotas are stale (`quotas_generated_on < today`).

The daily reflow:
1. **Marks missed quotas** from yesterday
2. **Runs the full scheduler** — measures actuals, derives target, fills
   Mondays, verifies throughput, generates quotas
3. **Redistributes committed goals** — for committed books the scheduler
   didn't touch, spreads remaining pages across remaining days
4. **Updates timestamp** so reflow doesn't re-run until tomorrow

Because tier placements snap to Mondays, running on a Wednesday doesn't
place a book starting Wednesday — it places starting the following Monday.
The daily cadence means the system absorbs changes quickly without
requiring a separate weekly trigger.

## Committed Book Adjustments

### Graduation (tier extension)

When committed books' combined load exceeds the daily target in the near
term, the heaviest contributor gets promoted to the next longer tier. This
reduces its daily share and frees capacity.

### Contraction (tier shortening)

When committed books' combined load falls below target, the lightest
contributor gets shortened to a shorter tier. This increases its daily
share to fill the gap. Only shortens if the result stays at or below
target (closest-above).

### What does NOT trigger graduation

- A single missed day (redistribution absorbs it)
- Being slightly behind (can catch up within the tier at target rate)
- Graduation only fires when load exceeds target — it's automatic and
  daily, not only at Monday boundaries

## Handling Real-World Variance

### Missed reading days

Deficit grows. On next reflow: fewer reading days remaining with the same
books → target increases slightly, spread evenly. A week off in June means
a few extra minutes per day for the rest of the year.

### Binge reading

Surplus grows. Books completed early → fewer books remaining → target
eases. Tomorrow's assignment is lighter.

### Weekend handling

If the user skips weekends, the scheduler literally does not know weekends
exist. The target doesn't change on Saturday. It doesn't change on Sunday.
It doesn't change on Monday morning. It only changes when a reading day
(weekday) passes. This is enforced by counting reading days everywhere —
elapsed, remaining, shares, quotas.

### Queue running low

Phase 4 catches this. Surface: "Add N more books to maintain pace."

### A book goes untouched for weeks

It's committed (started_on is in the past). Graduation extends it to a
longer tier, reducing its daily share. The freed capacity absorbs other
books. The daily target stays level.

### Spontaneous reading (ad-hoc sessions)

The user reads a book that's not yet scheduled. Pages are recorded. When
the book eventually enters the pipeline, it has fewer remaining pages and
gets a shorter tier. Ad-hoc sessions never disrupt the current week's
committed books.

## Immediate Reschedule Triggers

These actions call `schedule!` immediately (not waiting for daily reflow):

- Book added to reading list
- Reading list reordered
- Goal deleted
- Pace target or reading preferences changed
- Goal manually rescheduled (pipeline drag)
- Ad-hoc session against a queued book

Book completion and abandonment do **not** trigger immediate reschedule —
the daily reflow picks them up the next morning.

## Tier System

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

Tiers exist for psychological reasons: predictable rhythms ("I start and
finish books on Mondays"), parallel variety (long book at low dose
alongside short book at high dose), and mental framing ("this is a 4-week
book").

Tiers are a **core design element** — do not replace them with
arbitrary-duration placements.

## Design Constraints for Future Changes

1. **Never derive pace from target.** Target flows from pace, not the
   reverse.

2. **Never place a book without verifying throughput.** Phase 4 is
   mandatory.

3. **Never create a spike to recover from a deficit.** Spread recovery
   evenly across remaining reading days.

4. **Preserve tier boundaries.** Tiers snap to Mondays, span fixed week
   counts, end on Sundays.

5. **Respect committed books.** `started_on <= today` means committed.
   May adjust end date, never remove without user action.

6. **Surface impacts, don't hide them.** Always show the derived daily
   target.

7. **No manual intervention required.** The system adapts to reality
   automatically.

8. **Respect the concurrency limit.** Surface conflicts rather than
   silently under-scheduling.

9. **Never change committed books mid-week.** Daily reflow adjusts quotas
   within the committed set. New books enter on Monday boundaries only.

10. **Honor ad-hoc reading.** Pages count, schedule adjusts, but the
    current week's committed books don't change.

11. **Suggest, don't force, when ahead.** When all committed books finish
    mid-week, suggest the next queued book. Never auto-schedule.

## Implementation Status

### Implemented
- Phase 1: Measure actuals (reading-day-aware)
- Phase 2: Derive daily target (reading-day-aware, no 7/5 scaling)
- Phase 3: Combinatorial Monday bin filling (closest-above-target scoring)
- Phase 4: Verify throughput
- Phase 5: Generate quotas
- Daily reflow (lazy, once per day)
- Graduation and contraction of committed goals
- Weekend skip/same modes
- Concurrency limit
- relax_last_placement (last-book safety valve)

### Not yet implemented
- **started_on-based commitment**: code still uses session-based locking
  with Monday week boundary reset. Needs to be changed to
  `started_on <= Date.current`.
- **Postponement**: user action to uncommit a book and return it to queue.
