# PRD: Home → Entry detail (one entry, in whatever state it is in: its tracker, its state and its
#      time; who logged or skipped it; who changed it last; any value outside its range with the
#      range; the schedule it came from)
Feature: Entry detail
  Entry detail is the one screen any entry is read on, whatever state it is
  in. It names the schedule an entry came from, who logged or skipped it and
  who changed it last, and marks any value that fell outside its range.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Home (it names the schedule an entry came from when it came from one, so a caregiver can
  #      tell this evening's dose from a reading somebody took because they felt like it)
  Scenario: An entry names the schedule it came from and who logged it
    Given "Grandma" has a tracker "Medication"
    And "Medication" has a schedule labelled "Evening" every day at 20:00
    And "Medication" has these entries from its "Evening" schedule:
      | state  | when        | by  |
      | logged | 2 hours ago | Sam |
    When "Alex" opens that entry
    Then the answer is 200
    And it is the "Medication" entry logged by "Sam" 2 hours ago
    And it came from the "Evening" schedule

  # PRD: Home → Entry detail (the schedule it came from, when it came from one)
  Scenario: An entry logged ad hoc names no schedule
    Given "Grandma" has a tracker "Walk"
    And "Sam" logged "Walk" 3 hours ago
    When "Sam" opens that entry
    Then the answer is 200
    And it is the "Walk" entry logged by "Sam" 3 hours ago
    And it came from no schedule

  # PRD: Home → Entry detail (who logged or skipped it, and when)
  Scenario: A skipped entry says who skipped it
    Given "Grandma" has a tracker "Medication"
    And "Medication" has a schedule labelled "Morning" every day at 08:00
    And "Medication" has these entries from its "Morning" schedule:
      | state   | when        | by   |
      | skipped | 5 hours ago | Alex |
    When "Sam" opens that entry
    Then the answer is 200
    And it is the "Medication" entry skipped by "Alex" 5 hours ago
    And it came from the "Morning" schedule

  # PRD: Home (Entry detail is the one screen any entry is read on, whatever state it is in)
  Scenario: Unrecorded care is read on the same screen, waiting for nobody in particular
    Given "Grandma" has a tracker "Medication"
    And "Medication" was due 3 hours ago and nobody has logged it
    When "Sam" opens that entry
    Then the answer is 200
    And it is the "Medication" entry still unrecorded, due 3 hours ago

  # PRD: Home (it marks any value that fell outside its range, because an alert now leads here)
  # PRD: Home → Entry detail (any value that fell outside its range, named alongside the range it
  #      was expected to hold to)
  Scenario: A value outside its range is marked with the range, and only that value
    Given "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Blood pressure" has a number field "Pulse" expected between 50 and 100
    And "Blood pressure" has these entries:
      | state  | when        | by  | values                 |
      | logged | 1 hour ago  | Sam | Systolic 165, Pulse 72 |
    When "Sam" opens that entry
    Then the answer is 200
    And it marks only "Systolic" at 165 as outside 90 to 140

  # PRD: Home → Entry detail (any value that fell outside its range)
  Scenario: A reading inside its range is marked as nothing
    Given "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Sam" logged "Blood pressure" 1 hour ago with "Systolic" at 128
    When "Sam" opens that entry
    Then the answer is 200
    And it marks nothing as out of range

  # PRD: Definitions → Entry (an entry records who logged it and, if it has since been changed, who
  #      changed it last and when)
  Scenario: A changed entry says who changed it last
    Given "Grandma" has a tracker "Walk"
    And "Sam" logged "Walk" 1 day ago
    And "Alex" changed that entry 2 hours ago
    When "Sam" opens that entry
    Then the answer is 200
    And it is the "Walk" entry logged by "Sam" 1 day ago
    And the entry was last changed by "Alex" 2 hours ago

  # PRD: Definitions → Care team (every care receiver, tracker, and entry belongs to exactly one care team)
  # Contract: GET /v1/entries/{entryId} answers 403 to a caller not on the team
  Scenario: Someone not on the care team cannot read an entry
    Given "Grandma" has a tracker "Walk"
    And "Sam" logged "Walk" 1 day ago
    When "Riley" opens that entry
    Then the answer is 403
