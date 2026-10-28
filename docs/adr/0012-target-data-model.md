# 0012 — Target Data Model

- **Status:** Accepted
- **Date:** 2026-10-28
- **Deciders:** Trevor Williams

## Context and Problem Statement

`docs/PRD.md` now catalogues every screen, and the data built in B1/B3a no longer fits it. The PRD
renames the core nouns (_entry_, _care team_), drops tracker kinds, gives entries four states, and
introduces things that have no storage at all: tracker schedules, journal notes, care instructions,
coverage, notification preferences. It also adds rules that only hold if the data is shaped for
them: receivers and teams are archived and never deleted, fields are paused and never deleted, choice
options are retired and renamed without disturbing old entries, and a closed account leaves its care
behind as "a former caregiver".

This record fixes the target entities — what exists, what each holds, what owns what — and what
moving live production data onto them costs. It gates every endpoint change that follows. It is a
dated decision, not a living spec: once approved, the Go domain types and the OpenAPI contract are
the source of truth, and this record is not updated to follow them.

Three PRD open questions are deliberately left open, and the model leaves room for each: **1**
(where the grace period is set), **3** (whether alerts are stored or derived), and **4** (whether an
entry can be detached from its occurrence).

## Considered Options

**How scheduled care exists in the data.**

- **Materialize occurrences ahead** — a scheduled job writes real `scheduled` entries over a rolling
  window; logging or skipping updates that row in place.
- **Derive occurrences on read** — schedules are rules only; every reader expands them, and only
  logged or skipped occurrences are stored.

**Vocabulary in storage.**

- **Rename everything** — new tables and attributes (`entry`, `team`, `team_id`), populated by a
  one-time copy-and-convert.
- **Rename in code only** — keep `event` / `care_group_id` in DynamoDB, translate at the store layer
  forever.

**When live data moves.**

- **One cutover** — prod stays on the old model while every area is built against the new one in
  dev; migration, API, and app ship together on one day.
- **Per area, both live** — migrate first, ship each area as it lands, and keep the old endpoints
  working for the installed app until everyone updates.

## Decision

**Materialize occurrences ahead.** The PRD already treats an occurrence as a thing — it is skipped,
edited, still waiting, pointed at by an alert — and a thing with a stable id from the moment it is
planned is something every reader can agree about. Deriving on read would have Home, Coming up,
reminders, and alerts each expand rules and agree to the minute, and would orphan a stored log
whenever a schedule's time moved. The price is one scheduled job.

**Rename everything.** The data is being rewritten anyway (field and option ids, below), so the
rename costs almost nothing extra, and one vocabulary from PRD to storage removes a translation
layer that would otherwise live forever.

**One cutover.** The family is a handful of people on one TestFlight build; supporting two API
generations on live data to ship areas a few weeks sooner is not worth it. Prod stays exactly as it
is until the new app is ready, then moves in one planned step.

### Conventions that apply to every entity

- Tables are `caregiver-{stage}-{entity}`, one per entity, as today.
- Every record carries `team_id`, denormalized onto children, so authorization stays a single read.
- Every record traces to one receiver or one team, so support's cascading delete can find it.
- Anything archived or paused is a **status** (`active|archived`, `active|paused`) with
  `{status}_by` / `{status}_at`, never a boolean and never a delete.
- Anything any caregiver may edit records `updated_by` / `updated_at` — the last change only. The
  PRD asks for no history beyond that.
- Wall-clock rules about a receiver are stored in **local time** and resolved against the receiver's
  `time_zone`. Materialized rows carry both the local time and the resolved instant.
- Recurrence is a **rule**, never a preset: `{freq: daily|weekly|monthly, interval, by_day[]}`, an
  RRULE subset that can widen without migrating data. The UI's choices are presets that write into
  it.

### Entities

**User** (`user`, PK `user_id` = Cognito `sub`; GSI `email-index`) — `email`, `name`,
`email_notifications` (bool; push is the phone's, not stored), `status` (`active|closed`),
`closed_at`, `created_at`. Closing an account removes `email` and `name` and sets `closed`; the row
stays so every entry pointing at it resolves to "a former caregiver". Dropping `email` also drops the
row from `email-index`.

**Device** (`device`, PK `user_id`, SK `device_id`) — `push_token`, `platform`, `updated_at`. Where
push is delivered; one row per installed app. New.

**Team** (`team`, PK `team_id`) — `name`, `status` (`active|archived`), `archived_by`/`archived_at`,
`created_by`, `created_at`. Replaces `care-group`. "Close this care team" archives it.

**Membership** (`membership`, PK `user_id`, SK `team_id`; GSI `team-index`) — `role`
(`admin|caregiver`), `joined_at`, and the team's notification kinds for this caregiver:
`notify_reminders`, `notify_range_alerts`, `notify_gap_alerts`, `notify_unrecorded_alerts` (all
default on). Leaving or being removed deletes the row; the record stays because it points at the
user, not the membership. "At least one admin" is enforced by the API in a transaction.

**Invitation** (`invitation`, PK `code`; GSIs `team-index`, `email-index`; TTL `expires_at`) —
`email`, `status` (`pending|accepted|revoked`), `invited_by`, `created_at`, `expires_at` (14 days).
**`role` is removed**: every invitation joins as a caregiver.

**Receiver** (`receiver`, PK `receiver_id`; GSI `team-index` on `created_at`) — `name`,
`time_zone` (IANA, required), `status` (`active|archived`), `archived_by`/`archived_at`,
`created_by`, `created_at`. Changing `time_zone` makes the generator re-resolve every future
occurrence and assignment, which keeps their wall-clock times.

**Care instructions** (`care-instructions`, PK `receiver_id`) — `team_id`, `body` (free text),
`contacts` (ordered list of `{contact_id, name, relationship, phone}`), `updated_by`, `updated_at`.
One per receiver. New.

**Tracker** (`tracker`, PK `tracker_id`; GSI `receiver-index`) — `receiver_id`, `team_id`, `name`,
`icon`, `color`, `fields`, `gap_hours` (optional), `status` (`active|paused`),
`paused_by`/`paused_at`, `created_by`, `created_at`. **`kind` is removed.** A gap and any live
schedule are mutually exclusive, enforced by the API.

**Field** (embedded in the tracker) — `field_id` (stable, never reused), `label`, `type`
(`number|text|boolean|choice|datetime`), `unit`, `required`, `status` (`active|paused`),
`paused_at`, and by type: `range {low, high}` for numbers; `multiple` (bool) and `options` for
choices. Fields are never removed from the list.

**Choice option** (embedded in the field) — `option_id` (stable), `label`, `status`
(`active|retired`). Entries store option ids, so a rename reads everywhere and a retirement leaves
old entries intact.

**Tracker schedule** (`schedule`, PK `schedule_id`; GSI `tracker-index`) — `tracker_id`,
`receiver_id`, `team_id`, `label` (optional; blank means derived), `rule`, `time` (local `HH:MM`),
`starts_on`, `ends_on` (local dates, optional end), `planned_values` (pre-filled, keyed by
`field_id`), `unrecorded_alert` (bool), `grace_minutes` (optional; unset means the default — room for
open question 1), `removed_at`, `generated_through`, `created_by`, `created_at`. Removing a schedule
sets `removed_at` and deletes its still-waiting occurrences; the row stays so past entries can still
name the regimen they belonged to. A morning and an evening dose are two schedules.

**Entry** (`entry`, PK `entry_id`) — one record for all four states. Replaces both `event` and
`scheduled-item`.

- Identity: `tracker_id`, `receiver_id`, `team_id`.
- Plan (present when the entry was planned): `schedule_id` (absent for one made by hand),
  `occurrence_local`, `occurrence_at`, `planned_values`, `unrecorded_alert`, `grace_minutes`.
- State: `state` (`scheduled|logged|skipped`). **Unrecorded is not stored** — it is `scheduled` with
  `occurrence_at` in the past.
- Care: `values` (keyed by `field_id`; a choice is a list of `option_id`s), `note`, `occurred_at`,
  `logged_by`, `logged_at`, `skipped_by`, `skipped_at`.
- Edit trail: `created_by`, `created_at`, `updated_by`, `updated_at`.
- `timeline_at`: `occurred_at` if logged, otherwise `occurrence_at` — the one time indexes sort on.

Deleting a logged or skipped entry that has a plan returns it to `scheduled` and restores
`planned_values`; deleting one without a plan removes the row. Indexes:

| Index            | Key                               | Serves                                  |
| ---------------- | --------------------------------- | --------------------------------------- |
| `tracker-time`   | `tracker_id`, `timeline_at`       | Tracker detail, insights                |
| `receiver-time`  | `receiver_id`, `timeline_at`      | Home's daily timeline                   |
| `open-index`     | `receiver_id`, `open_at` (sparse) | Coming up, unrecorded alerts, reminders |
| `schedule-index` | `schedule_id`, `occurrence_at`    | Generator, removing a schedule          |

`open_at` is set only while `state = scheduled`, so the open index holds nothing but care still
waiting.

Room left for open questions: alerts can be derived from these rows, or stored beside them, without
changing an entry (**3**). Because an entry _is_ its occurrence, detaching one would mean writing a
new plan-less entry and resetting the occurrence — possible later without a schema change (**4**).

**Journal note** (`journal-note`, PK `note_id`; GSI `receiver-time` on `at`) — `receiver_id`,
`team_id`, `at` (the time it is about), `body`, `author`, `created_at`, `updated_by`, `updated_at`.
New.

**Coverage schedule** (`coverage-schedule`, PK `coverage_schedule_id`; GSI `receiver-index`) —
`receiver_id`, `team_id`, `user_id` (who covers), `rule`, `start_time`/`end_time` (local),
`starts_on`, `ends_on`, `removed_at`, `generated_through`, `created_by`, `created_at`. New. Removing
one deletes its future assignments and keeps past ones.

**Assignment** (`assignment`, PK `assignment_id`; GSIs `receiver-time` on `starts_at`,
`coverage-schedule-index`) — `receiver_id`, `team_id`, `user_id`, `starts_local`/`ends_local`,
`starts_at`/`ends_at`, `coverage_schedule_id` (absent if made by hand), `created_by`,
`updated_by`, `updated_at`. Handing one Tuesday to someone else changes `user_id` on that row only.
New, materialized ahead like entries.

**Tracker template** — stays a catalogue in code (`templates.json`), not a table. A tracker keeps no
tie to it.

**Not stored:** alerts (pending open question 3), the last-viewed receiver (per device), feedback.

### The generator

A scheduled job in `services/` materializes occurrences and assignments: for each live schedule it
writes everything up to a rolling horizon **and at least the next occurrence**, because Coming up
shows each tracker's _next_ scheduled entry and a schedule that repeats every two months would fall
outside any short window. It advances `generated_through`, re-resolves future rows when a receiver's
time zone changes, and skips paused trackers and archived receivers. Editing a schedule's rule
deletes its future `scheduled` rows and regenerates them; logged, skipped, and past rows are never
touched.

### Migrating production

Prod is migrated once, at cutover, by a copy-and-convert script that reads the old tables and
writes the new ones. Old tables are left in place, read-only, until Trevor deletes them by hand.
Every new id is deterministic (`uuid5` of the old key), as in the v1→v2 migration, so the script can
be re-run safely.

Counts read from prod on 2026-10-28; entries grow daily until cutover.

| Old              | New             | Conversion                                                                          | Rows |
| ---------------- | --------------- | ----------------------------------------------------------------------------------- | ---- |
| `user`           | `user`          | add `status: active`, `email_notifications: true`                                   | 3    |
| `care-group`     | `team`          | rename; `status: active`                                                            | 1    |
| `membership`     | `membership`    | `care_group_id` → `team_id`; notification kinds default on                          | 3    |
| `invitation`     | `invitation`    | pending only, `role` dropped; `token` → `code`                                      | 0    |
| `receiver`       | `receiver`      | `time_zone: America/Chicago`; `archived` → `status`; drop `date_of_birth`           | 2    |
| `tracker`        | `tracker`       | drop `kind`; `archived` → `paused`; `enum` → `choice`; key → `field_id`; option ids | 13   |
| `event`          | `entry`         | `state: logged`; choice text → option ids; `logged_at` = `created_at`               | 1795 |
| `scheduled-item` | `entry`         | `state: scheduled`, no schedule, `planned_values` = `values`                        | 5    |
| —                | everything else | starts empty                                                                        | 0    |

Field `key`s become `field_id`s unchanged — they are already stable and unique within a tracker — so
entry values are re-keyed only where a choice's text becomes an option id. Per-field `min`/`max`
become `range {low, high}`. What prod holds makes the rest cheap:

- **Choices convert cleanly.** Four trackers have a single-answer choice field (two colors,
  an amount, mood), and all 107 recorded answers match one of their options, so every answer has an
  option id to become. All convert with `multiple: false`.
- **No receiver has a date of birth**, and the PRD does not describe one, so the attribute is
  dropped at no cost.
- **The appointments tracker** (`kind: scheduled`, six fields) holds the five scheduled items. They
  become one-off scheduled entries; any whose time has passed reads as unrecorded, with no
  unrecorded-care alert, since none was ever asked for.
- **No tracker is archived** and no invitation is pending, so neither conversion has data to act on.

- **Both receivers are in Chicago**, so each gets `time_zone: America/Chicago`.
- **The v1 stragglers stay as they are.** Two people's eleven v1 events remain attributed to Trevor;
  the v1→v2 re-run that would move them is abandoned, since after cutover it would write tables
  nothing reads.

## Consequences

### Positive

- One vocabulary from PRD to storage.
- Every occurrence and assignment has a stable id; readers list rows rather than expand rules.
- Renames, retirements, pauses, and closed accounts never rewrite or lose recorded care.
- Prod is untouched until a single, re-runnable cutover.

### Negative / Trade-offs

- A new scheduled job, and logic to regenerate the future when a rule or time zone changes.
- Thirteen tables instead of eight; old tables linger until deleted by hand.
- Nothing built against the new model reaches the family until every area is done.
- Old and new iOS builds cannot share a backend; the cutover forces an app update.

## Related

- PRD: `docs/PRD.md` — _Definitions_ and open questions 1, 3, 4
- Historical: `docs/archive/2026-06-11-b1-data-model-identity-design.md`,
  `docs/archive/2026-06-12-b3a-core-care-domain-design.md`
- ADRs: 0011 (table prefixing)
