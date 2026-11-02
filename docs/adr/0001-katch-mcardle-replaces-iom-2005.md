# Katch-McArdle replaces IOM 2005, with exercise credited only through logging

This fork computes BMR with Katch-McArdle (`370 + 21.6 × Lean Body Mass`) and sets TDEE to BMR × 1.2, with no activity setting; all exercise reaches the calorie goal through Logged Activities (net of resting burn) and Daily Steps. Upstream's IOM 2005 equation and its four-category activity setting are removed rather than kept as an option, because the fork is for a user who has a Body Fat Reading and found IOM's estimate off for them, and a single model avoids double-counting exercise between an activity multiplier and logged workouts.

## Considered Options

- **Katch-McArdle as a selectable alternative to IOM 2005.** Rejected: two models meant two activity scales and a setting whose meaning changed with the formula, for a single-user fork that would only ever use one.
- **Five-level activity multiplier (1.2–1.9).** Rejected: those levels are defined by exercise frequency, so they double-count any workout that is also logged.

## Consequences

- A Body Fat Reading is required; without one the app shows no calorie goal rather than guessing.
- Age no longer affects the calorie goal, and gender only affects it indirectly (water goal, nutrient references, workout-compensation suggestion).
- Non-exercise activity (an active job, walking) counts only through Daily Steps, Logged Activities or the kcal offset.
- `tdee_calc.dart`, onboarding, Profile and the calorie breakdown screen diverge from upstream; expect merge conflicts there.
- The stored activity category stays in the database, unused, so existing data and backups still load.
