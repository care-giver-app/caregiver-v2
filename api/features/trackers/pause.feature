# PRD: Trackers → Pause this tracker?
# PRD: Definitions → Tracker (pausing stops the future without touching the past)
Feature: Pausing and resuming a tracker
  Pausing a tracker stops what was still to come and keeps everything already
  recorded. Resuming puts it back the way it was. Admins pause and resume.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"
    And "Grandma" has a tracker "Medication"
    And "Medication" has these entries:
      | state      | when             | by  |
      | scheduled  | 1 day from now   |     |
      | scheduled  | 3 hours from now |     |
      | unrecorded | 2 hours ago      |     |
      | skipped    | 1 day ago        | Sam |
      | logged     | 2 days ago       | Sam |

  # PRD: Trackers → Pause this tracker? (what is kept — every entry ever logged against it;
  #      the occurrences already waiting ahead of it go)
  Scenario: Pausing keeps every past entry and removes what was still waiting ahead
    When "Alex" pauses "Medication"
    Then the answer is 200
    And it reads as paused
    And nothing about it needs attention
    And nothing is still waiting ahead of "Medication"
    When "Sam" reads the entries of "Medication"
    Then the entries are, newest first:
      | state      | when        | by  |
      | unrecorded | 2 hours ago |     |
      | skipped    | 1 day ago   | Sam |
      | logged     | 2 days ago  | Sam |
    When "Sam" opens the trackers of "Grandma"
    Then the row for "Medication" does not say it needs attention

  # PRD: Definitions → Tracker (a resumed tracker returns with its history intact)
  # PRD: Trackers → Tracker detail (exit: Resume → Tracker detail, active again)
  Scenario: Resuming returns the tracker active, with its history
    Given "Alex" pauses "Medication"
    When "Alex" resumes "Medication"
    Then the answer is 200
    And it reads as active
    When "Sam" reads the entries of "Medication"
    Then the entries are, newest first:
      | state      | when        | by  |
      | unrecorded | 2 hours ago |     |
      | skipped    | 1 day ago   | Sam |
      | logged     | 2 days ago  | Sam |

  # PRD: Definitions → Tracker (admins pause and resume trackers)
  Scenario: A caregiver cannot pause a tracker
    When "Sam" pauses "Medication"
    Then the answer is 403
    When "Sam" opens "Medication"
    Then it reads as active
    And it needs attention for the care due 2 hours ago that went unrecorded
