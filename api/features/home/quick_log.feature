# PRD: Home → Quick log (what to record; when, asked once for the whole run: now, an earlier time
#      today, or a future time. A run given a future time is planning rather than logging, and
#      creates scheduled entries; a step for each thing picked, pre-filling rather than recording
#      when the run is planning)
Feature: Logging and planning from Quick log
  A run with a time now or earlier logs care: it lands in that day's
  timeline with who logged it. A run with a future time plans it instead:
  the entry is scheduled, sits under Coming up rather than in the day, and
  may leave a reading blank for whoever takes it.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Home → Quick log (Done, after a logging run: Home, with the new entries in the day behind it)
  # PRD: Definitions → Entry (Logged — a caregiver logged it, so it carries the time it occurred and
  #      who logged it)
  Scenario: Care logged ad hoc lands in its day with who logged it
    Given "Grandma" has a tracker "Walk"
    When "Sam" logs "Walk" as of earlier today
    Then the answer is 201
    When "Alex" opens the timeline of "Grandma" for today
    Then the answer is 200
    And the timeline holds, in time order:
      | when          | item         | by  |
      | earlier today | Walk, logged | Sam |
    When "Alex" opens that entry
    Then it is the "Walk" entry logged by "Sam", at earlier today
    And it came from no schedule

  # PRD: Home (a run given a future time is not logging at all: it creates scheduled entries,
  #      planned rather than recorded)
  # PRD: Home → Quick log (Done, after a planning run: Home, with the new entries under what is
  #      coming up)
  # PRD: Home (a dose planned for this evening is not yet part of the day's account but what is
  #      coming up)
  Scenario: A future time plans the entry, under Coming up and not in the day
    Given "Grandma" has a tracker "Walk"
    When "Sam" plans "Walk" for later today
    Then the answer is 201
    When "Sam" opens that entry
    Then it is the "Walk" entry still scheduled, due later today
    When "Sam" opens Coming up for "Grandma"
    Then coming up holds, soonest first:
      | tracker | when        | schedule |
      | Walk    | later today |          |
    When "Sam" opens the timeline of "Grandma" for today
    Then the timeline is empty

  # PRD: Home (a planned run pre-fills rather than records: a reading nobody has taken yet is left
  #      blank for whoever takes it)
  # PRD: Definitions → Field (a field is either required or optional)
  Scenario: A required reading is required when logging but may be left blank when planning
    Given "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    When "Sam" logs "Blood pressure" as of 1 hour ago, leaving "Systolic" blank
    Then the answer is 400 saying "is required"
    When "Sam" plans "Blood pressure" for 2 days from now, leaving "Systolic" blank
    Then the answer is 201
    When "Sam" opens Coming up for "Grandma"
    Then coming up holds, soonest first:
      | tracker        | when            | schedule |
      | Blood pressure | 2 days from now |          |

  # PRD: Definitions → Tracker (pausing: no new entries can be logged against it)
  Scenario: A paused tracker cannot be logged
    Given "Grandma" has a tracker "Walk"
    And "Walk" was paused 1 day ago
    When "Sam" logs "Walk" as of 1 hour ago
    Then the answer is 409 "the tracker is paused"
    When "Sam" opens the timeline of "Grandma" for the day of 1 hour ago
    Then the timeline is empty
