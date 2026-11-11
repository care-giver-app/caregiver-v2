# PRD: Home → Home (the daily timeline for one day — entries and journal notes together in time
#      order, holding the day's unrecorded and skipped occurrences alongside what was logged.
#      Occurrences still to come are not in it; coming up holds them)
Feature: The daily timeline
  The timeline is one day of one care receiver: what was logged, skipped and
  left unrecorded that day, and the journal notes written about it, in time
  order. What has not yet come due belongs to Coming up, not to the day.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Home (the entries logged that day and the journal notes written about it, in time order,
  #      and among them the occurrences the day expected — the dose nobody wrote down, the one
  #      somebody skipped)
  # PRD: Definitions → Journal note (they sit in the daily timeline in time order among the entries)
  Scenario: A day holds what was logged, skipped and unrecorded, and its notes, in time order
    Given "Grandma" has a tracker "Medication"
    And "Medication" has these entries:
      | state      | when             | by  |
      | logged     | 08:00 2 days ago | Sam |
      | unrecorded | 20:00 2 days ago |     |
      | logged     | 08:00 1 day ago  | Sam |
    And "Grandma" has a tracker "Walk"
    And "Walk" has these entries:
      | state   | when             | by   |
      | skipped | 14:00 2 days ago | Alex |
    And "Alex" wrote a journal note about "Grandma" at 11:30 2 days ago: "Rough morning, half a breakfast"
    And "Sam" wrote a journal note about "Grandma" at 09:00 1 day ago: "Slept well"
    When "Sam" opens the timeline of "Grandma" for 2 days ago
    Then the answer is 200
    And the timeline holds, in time order:
      | when             | item                                      | by   |
      | 08:00 2 days ago | Medication, logged                        | Sam  |
      | 11:30 2 days ago | a note: "Rough morning, half a breakfast" | Alex |
      | 14:00 2 days ago | Walk, skipped                             | Alex |
      | 20:00 2 days ago | Medication, unrecorded                    |      |

  # PRD: Home (what the day expected means what has already come due: a dose planned for this
  #      evening is not yet part of the day's account but what is coming up)
  Scenario: Nothing still to come appears in today
    Given "Grandma" has a tracker "Medication"
    And "Medication" has these entries:
      | state      | when          | by  |
      | logged     | early today   | Sam |
      | unrecorded | earlier today |     |
      | scheduled  | later today   |     |
    When "Sam" opens the timeline of "Grandma" for today
    Then the answer is 200
    And the timeline holds, in time order:
      | when          | item                   | by  |
      | early today   | Medication, logged     | Sam |
      | earlier today | Medication, unrecorded |     |

  # PRD: Home (a day is empty only when nothing was logged and nothing came due, however much is
  #      planned for later in it)
  # PRD: Home → Home (empty: nothing logged on the day shown and nothing came due either)
  Scenario: A day with only something planned later in it is empty
    Given "Grandma" has a tracker "Medication"
    And "Medication" is scheduled for later today
    When "Sam" opens the timeline of "Grandma" for today
    Then the answer is 200
    And the timeline is empty

  # PRD: Home (the day stepper walks a day at a time and stops at today, so the timeline looks back
  #      but never forward)
  Scenario: A day after today cannot be opened
    Given "Grandma" has a tracker "Medication"
    And "Medication" is scheduled for 2 days from now
    When "Sam" opens the timeline of "Grandma" for tomorrow
    Then the answer is 400

  # PRD: Definitions → Tracker (pausing: everything already logged stays exactly where it was, in the
  #      timelines it appeared in)
  # PRD: Home (the day's timeline stays, because paused trackers' entries still belong to the days
  #      they happened on)
  Scenario: A paused tracker's entries stay in their day
    Given "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has these entries:
      | state  | when             | by  |
      | logged | 09:00 3 days ago | Sam |
    And "Blood pressure" was paused 1 day ago
    When "Sam" opens the timeline of "Grandma" for 3 days ago
    Then the answer is 200
    And the timeline holds, in time order:
      | when             | item                   | by  |
      | 09:00 3 days ago | Blood pressure, logged | Sam |
