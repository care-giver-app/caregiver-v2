# Sample data — canonical fixtures

- **Module:** ios
- **Status:** Canonical (adopted from the 2026-07-01 design-coherence review)
- **Last updated:** 2026-07-16
- **Contract:** shapes only — see `shared/openapi/openapi.yaml`. This spec invents no fields.
- **Related specs:** every ios screen spec references this ([[home]], [[trackers]], [[logging]], [[insights]], [[team]], [[settings]], [[receivers]], [[add-tracker]], [[activity-timeline]], [[event-detail]], [[schedule]])

> **Read this before authoring any Figma frame or SwiftUI preview.** The 2026-07-01 review found the
> same active receiver named _Eleanor_ on Home but _Margaret_ on Insights, and the same active care
> group named _Mom's Care Team_ on Home but _The Riverside Group_ on Settings. Every frame had its own
> fixtures. This spec is the **one** persona/roster/tracker set — bind all mockups and previews to it so
> a caregiver navigating Home → Insights → Team → Settings sees one coherent product.

## Why this exists

Sample data is not decoration: on a multi-tenant care app, the receiver name and care-group name are
the two primary navigation anchors (who am I caring for, which group is active). When they drift
between tabs the deck reads as several different products. Fixtures therefore live in **one** spec, not
per-frame.

## The people

| Slot              | Value                                  | Notes                                                                     |
| ----------------- | -------------------------------------- | ------------------------------------------------------------------------- |
| Caregiver (you)   | **Trevor** · `twilliams0095@gmail.com` | Admin. Cyan avatar ring + "You" tag.                                      |
| Active care group | **The Riverside Group**                | Shown as Home header subtitle **and** the Settings ✓ active row.          |
| Second care group | Johnson Family                         | Settings only (proves `memberships[]` > 1).                               |
| Active receiver   | **Eleanor**, 72                        | Cyan monogram. Shown on Home / Insights / Trackers / Logging / Receivers. |
| Other receivers   | Harold 78 (teal) · Rosa 69 (violet)    | Receivers switch sheet.                                                   |

**Team roster (The Riverside Group):** Trevor (You · Admin) · Dana (Caregiver) · Marcus (Caregiver).
One pending invite: `jordan@email.com` (Caregiver · expires 7d).

- **Home caregiver face-pile = T · D · M** (three avatars, **no** "+N" overflow, **no** "S" — it must
  mirror the Team roster exactly). The review found Home showing `D · S · +2` against a 3-person roster.
- The active receiver is **Eleanor everywhere** (the review's "Margaret" on Insights is retired).
- The active care group is **The Riverside Group everywhere** (the review's "Mom's Care Team" on Home /
  Receivers is retired). _Chosen over "Mom's Care Team" because the roster context is already "Riverside";
  swap the string if product prefers the warmer name — but pick one._

## The trackers

One canonical roster for Eleanor. **A tracker keeps ONE hue on every screen** (the review found
Medication drawn violet on Add-Tracker but teal on Insights, and Weight teal↔violet — a direct hit to
the "per-entity hue aids recognition" signature). Hues are from the tracker-hue palette (cyan `17:7` /
teal `17:8` / violet `17:9` / info-blue `10:30`); reuse is fine, drift is not.

| Tracker        | Contract `kind` | Presentation label | Hue       | Sample latest            |
| -------------- | --------------- | ------------------ | --------- | ------------------------ |
| Blood pressure | `measurement`   | Numeric            | cyan      | 128/82 mmHg              |
| Medication     | `scheduled`     | Checklist          | violet    | Lisinopril 10 mg · taken |
| Weight         | `measurement`   | Numeric            | teal      | 154.2 lb                 |
| Pain level     | `measurement`   | Numeric            | info-blue | 2 / 10 · mild            |
| Mood           | `event`         | Scale              | violet    | Good — calm, alert       |
| Hydration      | `event`         | Count              | teal      | Glass of water           |
| Sleep          | `event`         | Duration           | cyan      | 7 h 20 m                 |
| Meals          | `event`         | Quick log          | cyan      | (no value) · **Due**     |
| Walk           | `event`         | Count              | teal      | —                        |

- **Count = 9 named; "12 active" is fine** — three more exist off-screen. But every screen must draw
  its visible subset from **this list**: the review found Insights showing Weight/Walk while Home/Trackers
  showed Meals/Hydration/Mood/Sleep, so the two views shared almost no trackers and read as two receivers.
- **Home snapshot** (6 tiles) and **Insights overview** (5 cards) should overlap by at least their
  headline trackers (Blood pressure, Medication, Pain level appear in both).
- **"Medication"** singular everywhere (the review found "Medications" on Insights only).
- **`Meals` "Due"** and any amber/red is the _status_ layer (recency-as-luminance: amber = overdue, red =
  breach), **not** a base hue — don't offer amber/red as selectable tracker hues (see [[add-tracker]]).

### Presentation label ↔ contract kind

The Trackers list uses friendly labels (Quick log / Count / Checklist / Scale / Numeric / Duration);
Add-Tracker shows the raw contract `kind` badge (Event / Measurement / Scheduled). These are **the same
axis shown two ways** — the label is derived from `kind` + the field schema:

| Label     | Derives from                                         |
| --------- | ---------------------------------------------------- |
| Numeric   | `measurement` with one `number` field                |
| Duration  | `measurement`/`event` with a time-valued `number`    |
| Scale     | `event`/`measurement` with a bounded `number`/`enum` |
| Count     | `event`, aggregated occurrences per timeframe        |
| Checklist | `scheduled`                                          |
| Quick log | `event` with no value fields                         |

The label is a client-side affordance; only `kind` (`event | measurement | scheduled`) is in the
contract. Reconciling which of the two vocabularies each screen shows is tracked as a decision in
[[trackers]] — this table is the mapping the build must use.

## Upcoming scheduled items (look-ahead)

Fixtures for the [[home]] "Coming up" banner and the [[schedule]] look-ahead. In the contract a
**scheduled item** attaches to a `scheduled`-kind tracker (`ScheduledItem.tracker_id` +
`scheduled_for`), so these appointment-style entries are `scheduled` trackers on Eleanor. The list is
**soonest-first, future-only**; the banner shows the single soonest item; the relative label is the
whole-day delta ("Today" / "Tomorrow" / "in N days").

| Scheduled tracker     | Hue    | `scheduled_for` (from now) | Relative label | Note (subtitle)            | Bucket    |
| --------------------- | ------ | -------------------------- | -------------- | -------------------------- | --------- |
| Physical therapy      | teal   | +1 day, 2:00 PM            | Tomorrow       | Riverside Clinic · 2:00 PM | This week |
| Blood pressure review | cyan   | +3 days                    | in 3 days      | Dr. Chen                   | This week |
| Cardiology check-up   | cyan   | +9 days                    | in 9 days      | Riverside Clinic           | Later     |
| Dental cleaning       | violet | +16 days                   | in 16 days     | Dr. Alvarez                | Later     |
| Flu shot              | teal   | +24 days                   | in 24 days     | Pharmacy                   | Later     |

- **Banner shows the soonest** — with this set that's **Physical therapy · Tomorrow**. _Drift note:_ the
  standalone Figma banner frame `64:2` still reads "Cardiology check-up · in 9 days" (it predates this
  set); fold the banner text to the soonest item on the next Figma pass.
- These are distinct from the roster's `Medication` (`scheduled`, a recurring checklist) — appointments
  are their own `scheduled` trackers. Reuse the canonical hues (cyan/teal/violet); no amber (amber is the
  banner's fixed attention accent, not a tracker hue).
- Figma frames: look-ahead list `219:986`, empty state `223:1051` (see [[schedule]]).
