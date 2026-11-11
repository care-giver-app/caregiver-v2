# PRD: Home → Quick log (what to record: the occurrences the receiver has waiting — everything
#      scheduled for today and everything still unrecorded from the forty-eight hours behind it,
#      unrecorded first; each occurrence with its time and the schedule it came from)
Feature: What Quick log's picker leads with
  Above the trackers, Quick log's picker lists the occurrences the care
  receiver has waiting: the care left unrecorded in the last forty-eight
  hours, then what is still scheduled for today, each with its time and the
  schedule it came from.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Home (the picker leads with what the day already expects: everything scheduled for today,
  #      and everything still unrecorded from the forty-eight hours behind it, unrecorded first)
  # PRD: Home (each occurrence carries its time and the schedule it came from)
  Scenario: Unrecorded care from the last two days comes first, then the rest of today
    Given "Grandma" has a tracker "Medication"
    And "Medication" has a schedule labelled "Morning" every day at 08:00
    And "Medication" has a schedule labelled "Evening" every day at 20:00
    And "Medication" has these entries from its "Evening" schedule:
      | state      | when         |
      | unrecorded | 30 hours ago |
    And "Medication" has these entries from its "Morning" schedule:
      | state      | when        |
      | unrecorded | 3 hours ago |
    And "Grandma" has a tracker "Walk"
    And "Walk" is scheduled for later today
    When "Sam" opens Quick log for "Grandma"
    Then the answer is 200
    And the occurrences waiting are, unrecorded first:
      | tracker    | state      | when         | schedule |
      | Medication | unrecorded | 30 hours ago | Evening  |
      | Medication | unrecorded | 3 hours ago  | Morning  |
      | Walk       | scheduled  | later today  |          |

  # PRD: Home (needs attention is what still wants doing; skipping settles an occurrence)
  # PRD: Home → Quick log (everything still unrecorded from the forty-eight hours behind today;
  #      everything scheduled for today)
  Scenario: Settled care, care older than two days, and care after today are not waiting
    Given "Grandma" has a tracker "Medication"
    And "Medication" has a schedule labelled "Morning" every day at 08:00
    And "Medication" has these entries from its "Morning" schedule:
      | state      | when         | by  |
      | unrecorded | 49 hours ago |     |
      | skipped    | 25 hours ago | Sam |
      | logged     | 1 hour ago   | Sam |
      | unrecorded | 2 hours ago  |     |
    And "Grandma" has a tracker "Appointment"
    And "Appointment" is scheduled for 2 days from now
    When "Sam" opens Quick log for "Grandma"
    Then the answer is 200
    And the occurrences waiting are, unrecorded first:
      | tracker    | state      | when        | schedule |
      | Medication | unrecorded | 2 hours ago | Morning  |

  # PRD: Definitions → Tracker (pausing: it leaves both Home and the logging picker)
  Scenario: A paused tracker's unrecorded care is not waiting
    Given "Grandma" has a tracker "Zinc"
    And "Zinc" was due 3 hours ago and nobody has logged it
    And "Zinc" was paused 1 hour ago
    And "Grandma" has a tracker "Walk"
    And "Walk" was due 2 hours ago and nobody has logged it
    When "Sam" opens Quick log for "Grandma"
    Then the answer is 200
    And the occurrences waiting are, unrecorded first:
      | tracker | state      | when        | schedule |
      | Walk    | unrecorded | 2 hours ago |          |
