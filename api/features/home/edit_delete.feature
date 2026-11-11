# PRD: Definitions → Entry (any caregiver can edit or delete any entry, whoever logged it; deleting
#      an entry that fulfilled a scheduled one does not delete the plan behind it)
# PRD: Home → Delete this entry? (an entry logged ad hoc is simply gone, while one that fulfilled a
#      scheduled entry leaves that occurrence waiting again)
Feature: Editing and deleting an entry
  Any caregiver can correct or delete any entry. Entry detail then says who
  changed it last. Deleting care logged ad hoc removes it; deleting the log
  or the skip of an occurrence leaves the occurrence waiting again, with
  what it was planned to hold.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Definitions → Entry (the caregiver who notices a systolic reading is a digit short is rarely
  #      the one who typed it. An entry records who logged it and, if it has since been changed, who
  #      changed it last and when)
  # PRD: Home → Entry detail (who logged or skipped it; who changed it last and when)
  Scenario: A caregiver corrects another caregiver's reading, and the entry says who changed it
    Given "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Sam" logs "Blood pressure" as of 1 hour ago with "Systolic" at 13
    When "Alex" edits that entry, changing "Systolic" to 132
    Then the answer is 200
    When "Sam" opens that entry
    Then it is the "Blood pressure" entry logged by "Sam", at 1 hour ago
    And its "Systolic" reads 132
    And the entry was last changed by "Alex"

  # PRD: Definitions → Entry (an entry logged ad hoc fulfilled nothing, and deleting it simply
  #      removes it)
  # PRD: Home → Delete this entry? (Delete, when the entry was logged ad hoc: there is nothing left
  #      to show)
  Scenario: Deleting another caregiver's ad hoc entry removes it
    Given "Grandma" has a tracker "Walk"
    And "Sam" logs "Walk" as of 2 hours ago
    When "Alex" deletes that entry
    Then the answer is 204
    When "Sam" opens that entry
    Then the answer is 404
    When "Sam" opens the timeline of "Grandma" for the day of 2 hours ago
    Then the timeline is empty

  # PRD: Definitions → Entry (the occurrence goes back to scheduled, or to unrecorded if its time has
  #      passed — a caregiver who logged the evening dose against the wrong receiver should be left
  #      with an evening dose still waiting)
  # PRD: Definitions → Tracker schedule (a recurring rule, together with the field values it
  #      pre-fills)
  # PRD: Home → Delete this entry? (Delete, when the entry fulfilled a scheduled entry: Entry detail,
  #      now scheduled again, or unrecorded if its time has passed)
  Scenario: Deleting a logged occurrence leaves it unrecorded again, with what it was planned to hold
    Given "Grandma" has a tracker "Medication"
    And "Medication" has a number field "Dose"
    And "Medication" has a schedule labelled "Morning" every day at 08:00
    And "Medication" has these entries from its "Morning" schedule:
      | state      | when        | values |
      | unrecorded | 3 hours ago | Dose 5 |
    And "Sam" logs that entry as of 2 hours ago with "Dose" at 10
    When "Alex" deletes that entry
    Then the answer is 200
    When "Sam" opens that entry
    Then it is the "Medication" entry still unrecorded, due 3 hours ago
    And it came from the "Morning" schedule
    And its "Dose" reads 5
    When "Sam" looks at what needs attention for "Grandma"
    Then needs attention lists, in this order:
      | tracker    | kind       | when        |
      | Medication | unrecorded | 3 hours ago |

  # PRD: Definitions → Entry (the same holds for a skip: deleting one returns the occurrence to
  #      waiting rather than erasing it)
  # PRD: Home → Entry detail (deleting the skip leaves the occurrence waiting again for whoever marked
  #      the wrong dose)
  Scenario: Deleting a skip leaves care still to come waiting again
    Given "Grandma" has a tracker "Medication"
    And "Medication" has a number field "Dose"
    And "Medication" has a schedule labelled "Evening" every day at 20:00
    And "Medication" has these entries from its "Evening" schedule:
      | state     | when             | values |
      | scheduled | 5 hours from now | Dose 5 |
    And "Sam" skips that entry
    When "Sam" deletes that entry
    Then the answer is 200
    When "Alex" opens that entry
    Then it is the "Medication" entry still scheduled, due 5 hours from now
    And its "Dose" reads 5
    When "Alex" opens Coming up for "Grandma"
    Then coming up holds, soonest first:
      | tracker    | when             | schedule |
      | Medication | 5 hours from now | Evening  |

  # PRD: Definitions → Entry (deleting a skip says only that it should not have been skipped)
  Scenario: Deleting a skip of past care leaves it unrecorded again
    Given "Grandma" has a tracker "Medication"
    And "Medication" has a schedule labelled "Morning" every day at 08:00
    And "Medication" has these entries from its "Morning" schedule:
      | state   | when        | by  |
      | skipped | 3 hours ago | Sam |
    When "Alex" deletes that entry
    Then the answer is 200
    When "Sam" opens that entry
    Then it is the "Medication" entry still unrecorded, due 3 hours ago
    When "Sam" opens Quick log for "Grandma"
    Then the occurrences waiting are, unrecorded first:
      | tracker    | state      | when        | schedule |
      | Medication | unrecorded | 3 hours ago | Morning  |

  # PRD: Definitions → Tracker (pausing stops the future without touching the past: its schedules
  #      stop generating, and no new entries can be logged against it)
  # PRD: Definitions → Entry (deleting an entry that fulfilled a scheduled one undoes the log and no
  #      more — and a plan paused since no longer holds care still to come)
  Scenario: Deleting a log of care still to come on a paused tracker leaves nothing waiting
    Given "Grandma" has a tracker "Medication"
    And "Medication" has a number field "Dose"
    And "Medication" has a schedule labelled "Evening" every day at 20:00
    And "Medication" has these entries from its "Evening" schedule:
      | state     | when             | values |
      | scheduled | 5 hours from now | Dose 5 |
    And "Sam" logs that entry as of 1 hour ago with "Dose" at 5
    And "Alex" pauses "Medication"
    When "Sam" deletes that entry
    Then the answer is 204
    When "Alex" opens that entry
    Then the answer is 404
    When "Alex" opens Coming up for "Grandma"
    Then nothing is coming up
