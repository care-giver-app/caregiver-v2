# PRD: Trackers → Tracker detail (its entries, newest first, holding logged, unrecorded and
#      skipped together)
Feature: A tracker's entries
  Tracker detail lists everything logged against one tracker, newest first,
  with the unrecorded and skipped occurrences among them. Entries still to
  come are not listed. The list can be narrowed to a stretch of dates, and
  loads a page at a time.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Trackers → Tracker detail (logged, unrecorded and skipped together; entries still to come
  #      are not here; each entry shows when, its state, its values, and who logged or skipped it)
  Scenario: Logged, skipped and unrecorded entries together, newest first, nothing still to come
    Given "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Blood pressure" has these entries:
      | state      | when             | by   | values       |
      | scheduled  | 5 hours from now |      |              |
      | unrecorded | 2 hours ago      |      |              |
      | skipped    | 1 day ago        | Sam  |              |
      | logged     | 2 days ago       | Alex | Systolic 128 |
      | logged     | 3 days ago       | Sam  | Systolic 131 |
    When "Sam" reads the entries of "Blood pressure"
    Then the entries are, newest first:
      | state      | when        | by   | values       |
      | unrecorded | 2 hours ago |      |              |
      | skipped    | 1 day ago   | Sam  |              |
      | logged     | 2 days ago  | Alex | Systolic 128 |
      | logged     | 3 days ago  | Sam  | Systolic 131 |

  # PRD: Trackers → Tracker detail (a way to narrow the entries to a stretch of time)
  # Contract: from and to are dates in the receiver's time zone, inclusive
  Scenario: Narrowing the entries to a stretch of days
    Given "Grandma" has a tracker "Walk"
    And "Sam" logged "Walk" at noon on each of the last 5 days
    When "Sam" narrows the entries of "Walk" to the days from 4 days ago to 2 days ago
    Then the entries are, newest first:
      | state  | when             | by  |
      | logged | noon 2 days ago  | Sam |
      | logged | noon 3 days ago  | Sam |
      | logged | noon 4 days ago  | Sam |

  # PRD: Trackers → Tracker detail (the most recent stretch first, loading more as a caregiver scrolls)
  Scenario: The entries load a page at a time until the end
    Given "Grandma" has a tracker "Walk"
    And "Sam" logged "Walk" at noon on each of the last 5 days
    When "Sam" reads the entries of "Walk" 2 at a time
    Then they came in 3 pages
    And the entries are, newest first:
      | state  | when            | by  |
      | logged | noon 1 day ago  | Sam |
      | logged | noon 2 days ago | Sam |
      | logged | noon 3 days ago | Sam |
      | logged | noon 4 days ago | Sam |
      | logged | noon 5 days ago | Sam |

  # PRD: Definitions → Care team (every care receiver, tracker, and entry belongs to exactly one care team)
  # Contract: GET /v1/trackers/{trackerId}/entries answers 403 to a caller not on the team
  Scenario: Someone not on the care team cannot read the entries
    Given "Grandma" has a tracker "Walk"
    And "Sam" logged "Walk" 1 day ago
    When "Riley" reads the entries of "Walk"
    Then the answer is 403
