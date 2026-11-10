# PRD: Home → Coming up (each tracker's next scheduled entry, soonest first, with its time and the
#      schedule it came from)
Feature: What is coming up
  Coming up holds each tracker's next scheduled entry, soonest first. Home
  shows the first three of it; See all opens the whole list.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Home (Coming up holds one entry per tracker, that tracker's next scheduled entry, soonest
  #      first — a medication given twice a day would otherwise fill the space with its own doses)
  Scenario: One entry per tracker, soonest first, naming its schedule
    Given "Grandma" has a tracker "Medication"
    And "Medication" has a schedule labelled "Evening" every day at 20:00
    And "Medication" has these entries from its "Evening" schedule:
      | state     | when              |
      | scheduled | 2 hours from now  |
      | scheduled | 26 hours from now |
    And "Grandma" has a tracker "Appointment"
    And "Appointment" is scheduled for 3 days from now
    And "Grandma" has a tracker "Walk"
    And "Walk" is scheduled for 5 hours from now
    When "Sam" opens Coming up for "Grandma"
    Then the answer is 200
    And coming up holds, soonest first:
      | tracker     | when             | schedule |
      | Medication  | 2 hours from now | Evening  |
      | Walk        | 5 hours from now |          |
      | Appointment | 3 days from now  |          |

  # PRD: Home (Home shows the first three … See all opens Coming up, which holds the same list in full)
  Scenario: Home shows the first three and Coming up shows them all
    Given "Grandma" has a tracker "Medication"
    And "Medication" is scheduled for 1 hour from now
    And "Grandma" has a tracker "Walk"
    And "Walk" is scheduled for 2 hours from now
    And "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" is scheduled for 3 hours from now
    And "Grandma" has a tracker "Appointment"
    And "Appointment" is scheduled for 2 days from now
    When "Sam" looks at what is coming up for "Grandma" on Home
    Then the answer is 200
    And coming up holds, soonest first:
      | tracker        | when              |
      | Medication     | 1 hour from now   |
      | Walk           | 2 hours from now  |
      | Blood pressure | 3 hours from now  |
    When "Sam" opens Coming up for "Grandma"
    Then the answer is 200
    And coming up holds, soonest first:
      | tracker        | when              |
      | Medication     | 1 hour from now   |
      | Walk           | 2 hours from now  |
      | Blood pressure | 3 hours from now  |
      | Appointment    | 2 days from now   |

  # PRD: Home (the section is there only when something is coming; a team that logs everything ad
  #      hoc has nothing ahead of them)
  # PRD: Home → Home (coming up: present only when something is scheduled ahead)
  Scenario: Nothing scheduled ahead leaves coming up empty
    Given "Grandma" has a tracker "Medication"
    And "Medication" has these entries:
      | state      | when        | by  |
      | unrecorded | 2 hours ago |     |
      | skipped    | 1 day ago   | Sam |
      | logged     | 2 days ago  | Sam |
    When "Sam" looks at what is coming up for "Grandma" on Home
    Then the answer is 200
    And nothing is coming up
