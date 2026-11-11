# PRD: Definitions → Entry (a caregiver can log an unrecorded entry at any point afterward and set
#      the time the care actually occurred; an unrecorded entry can equally be skipped, and skipping
#      settles it)
# PRD: Home → Quick log (a picked occurrence's step offers Log it or Skip, with a note either way)
Feature: Settling an occurrence
  Logging or skipping a waiting occurrence settles it: it stops needing
  attention and stops waiting in Quick log. A log records the run's time,
  not the occurrence's; a skip records who decided and why, and keeps the
  occurrence in its day.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"
    And "Grandma" has a tracker "Medication"
    And "Medication" has a schedule labelled "Morning" every day at 08:00

  # PRD: Home (the same list that says the evening dose has no record is the list a caregiver taps to
  #      give it one)
  # PRD: Home (the run's one time is what the entry records, because what is being logged is when
  #      the care happened)
  # PRD: Home (it names the schedule an entry came from when it came from one)
  Scenario: Logging an unrecorded occurrence settles it at the time the care happened
    Given "Medication" has these entries from its "Morning" schedule:
      | state      | when        |
      | unrecorded | 3 hours ago |
    When "Sam" looks at what needs attention for "Grandma"
    Then needs attention lists, in this order:
      | tracker    | kind       | when        |
      | Medication | unrecorded | 3 hours ago |
    When "Sam" logs that entry as of 1 hour ago
    Then the answer is 200
    When "Alex" looks at what needs attention for "Grandma"
    Then nothing needs attention on Home
    When "Alex" opens Quick log for "Grandma"
    Then nothing is waiting in Quick log
    When "Alex" opens that entry
    Then it is the "Medication" entry logged by "Sam", at 1 hour ago
    And it came from the "Morning" schedule

  # PRD: Definitions → Entry (Skipped — the entry carries who skipped it and when, and a note if they
  #      leave one, usually saying why. A skip is a decision, not a care failure, so it never counts
  #      as unrecorded)
  # PRD: Home (the timeline holds the occurrences the day expected — the one somebody skipped)
  Scenario: Skipping settles an occurrence with who skipped it and why, and it stays in its day
    Given "Medication" has these entries from its "Morning" schedule:
      | state      | when        |
      | unrecorded | 3 hours ago |
    When "Sam" skips that entry, saying "The hospital gave it before discharge"
    Then the answer is 200
    When "Alex" looks at what needs attention for "Grandma"
    Then nothing needs attention on Home
    When "Alex" opens Quick log for "Grandma"
    Then nothing is waiting in Quick log
    When "Alex" opens that entry
    Then it is the "Medication" entry skipped by "Sam", at 3 hours ago
    And its note says "The hospital gave it before discharge"
    And it came from the "Morning" schedule
    When "Alex" opens the timeline of "Grandma" for the day of 3 hours ago
    Then the timeline holds, in time order:
      | when        | item                | by  |
      | 3 hours ago | Medication, skipped | Sam |

  # PRD: Definitions → Entry (Skipped — whether or not its time has already passed)
  Scenario: Care still to come can be skipped ahead of time
    Given "Medication" has these entries from its "Morning" schedule:
      | state     | when             |
      | scheduled | 5 hours from now |
    When "Sam" skips that entry
    Then the answer is 200
    When "Sam" opens Coming up for "Grandma"
    Then nothing is coming up

  # PRD: Definitions → Entry (a caregiver who skipped the evening dose and then learns it was given
  #      after all can edit the entry and log it, moving it from skipped to logged)
  # PRD: Home → Entry detail (Edit, when the entry is skipped, and editing it logs the care after all)
  Scenario: A skipped occurrence edited is logged after all
    Given "Medication" has these entries from its "Morning" schedule:
      | state   | when        | by  |
      | skipped | 5 hours ago | Sam |
    When "Alex" edits that entry, saying it happened 4 hours ago
    Then the answer is 200
    When "Sam" opens that entry
    Then it is the "Medication" entry logged by "Alex", at 4 hours ago
    And it came from the "Morning" schedule
    And the entry was last changed by "Alex"

  # PRD: Definitions → Tracker (pausing: no new entries can be logged against it, and it leaves the
  #      logging picker)
  Scenario: An occurrence of a paused tracker cannot be logged
    Given "Grandma" has a tracker "Zinc"
    And "Zinc" was due 3 hours ago and nobody has logged it
    And "Zinc" was paused 1 hour ago
    When "Sam" logs that entry as of 1 hour ago
    Then the answer is 409 "the tracker is paused"
