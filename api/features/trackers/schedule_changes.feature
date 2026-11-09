# PRD: Trackers → A schedule (one recurring rule on a tracker, and the values it pre-fills; admins only)
# PRD: Trackers → Remove this schedule?
# PRD: Definitions → Tracker schedule
Feature: Adding, changing and removing a tracker's schedules
  A schedule is written the moment its own sheet is saved, and its occurrences
  start existing as soon as it does. Removing one takes the plan rather than
  the care. Admins write schedules; every caregiver reads them.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"
    And "Grandma" has a tracker "Medication"

  # PRD: Trackers (A schedule is written the moment its own sheet is saved)
  # PRD: Trackers → Tracker detail (how many schedules it has, opening Schedules)
  # PRD: Trackers → Schedules (each schedule by its name … its time)
  Scenario: A schedule an admin adds shows on the tracker and on its Schedules screen
    When "Alex" adds a schedule labelled "Morning dose" to "Medication" every day at 08:00
    Then the answer is 201
    When "Sam" opens "Medication"
    Then it has 1 schedule
    When "Sam" reads the schedules of "Medication"
    Then the schedules listed are "Morning dose"
    And the "Morning dose" schedule is at 08:00

  # PRD: Definitions → Tracker schedule (left blank, it defaults to one derived from the schedule itself)
  # PRD: Trackers (left unlabelled it takes a name derived from itself, so three schedules on one
  #      tracker read as a regimen rather than as three copies of the tracker's name)
  Scenario: A schedule added without a label is named for its days and time
    When "Alex" adds an unlabelled schedule to "Medication" on Mon, Wed and Fri at 20:00
    Then the answer is 201
    When "Sam" reads the schedules of "Medication"
    Then the one schedule listed is named for its days and time rather than "Medication"

  # PRD: Trackers (A new schedule's first occurrence is the first one at or after the moment it is
  #      saved, because care nobody had yet been asked for cannot have gone unrecorded)
  # PRD: Trackers (occurrences that start existing as soon as it does)
  Scenario: A schedule saved after today's time leaves nothing unrecorded today
    When "Alex" adds a schedule labelled "Morning dose" to "Medication" every day at a time already past today
    Then the answer is 201
    And something is waiting ahead of "Medication"
    When "Sam" reads the entries of "Medication"
    Then no entries are listed
    When "Sam" opens "Medication"
    Then nothing about it needs attention

  # PRD: Definitions → Threshold (a tracker has schedules or a gap, never both; an admin changing
  #      either is told what they are about to lose)
  # PRD: Trackers → A schedule (what a gap costs: the first schedule on a tracker watched by one says so)
  # Contract: POST /v1/trackers/{trackerId}/schedules answers 409 SchedulesOrGap over a gap unless replace_gap
  Scenario: The first schedule on a tracker watched by a gap waits for the admin to give the gap up
    Given "Grandma" has a tracker "Shower"
    And "Shower" is watched by a gap of 72 hours
    When "Alex" adds a schedule labelled "Evening" to "Shower" every day at 19:00
    Then the answer is 409
    When "Alex" opens "Shower"
    Then it is watched by a gap of 72 hours
    And it has 0 schedules
    When "Alex" adds a schedule labelled "Evening" to "Shower" every day at 19:00, confirming it turns the gap off
    Then the answer is 201
    When "Alex" opens "Shower"
    Then it is not watched by a gap
    And it has 1 schedule

  # PRD: Trackers → A schedule (Save → Edit tracker)
  # Contract: PUT /v1/schedules/{scheduleId}
  Scenario: An admin changes a schedule's time
    Given "Alex" adds a schedule labelled "Morning dose" to "Medication" every day at 08:00
    When "Alex" changes the "Morning dose" schedule of "Medication" to every day at 09:00
    Then the answer is 200
    When "Sam" reads the schedules of "Medication"
    Then the "Morning dose" schedule is at 09:00

  # PRD: Definitions → Tracker schedule (removing one takes the plan rather than the care: every
  #      occurrence still waiting goes with the rule, while every entry already logged, skipped, or
  #      unrecorded stays exactly where it was)
  # PRD: Trackers → Remove this schedule? (what stays — every entry already logged, skipped or
  #      unrecorded, exactly where it is)
  Scenario: Removing a schedule keeps every entry it already made
    Given "Alex" adds a schedule labelled "Morning dose" to "Medication" every day at 08:00
    And "Medication" has these entries from its "Morning dose" schedule:
      | state      | when       | by  |
      | unrecorded | 1 day ago  |     |
      | skipped    | 2 days ago | Sam |
      | logged     | 3 days ago | Sam |
    When "Alex" removes the "Morning dose" schedule of "Medication"
    Then the answer is 204
    And nothing is still waiting ahead of "Medication"
    When "Sam" opens "Medication"
    Then it has 0 schedules
    When "Sam" reads the entries of "Medication"
    Then the entries are, newest first:
      | state      | when       | by  |
      | unrecorded | 1 day ago  |     |
      | skipped    | 2 days ago | Sam |
      | logged     | 3 days ago | Sam |
    And the entries name the "Morning dose" schedule

  # PRD: Trackers → A schedule (admins only)
  # PRD: Trackers → Schedules (read by anyone on the team. Nothing here edits)
  Scenario: A caregiver cannot add, change or remove a schedule
    Given "Medication" has a schedule labelled "Morning dose" every day at 08:00
    When "Sam" adds a schedule labelled "Evening dose" to "Medication" every day at 20:00
    Then the answer is 403
    When "Sam" changes the "Morning dose" schedule of "Medication" to every day at 09:00
    Then the answer is 403
    When "Sam" removes the "Morning dose" schedule of "Medication"
    Then the answer is 403
    When "Sam" reads the schedules of "Medication"
    Then the schedules listed are "Morning dose"
    And the "Morning dose" schedule is at 08:00
