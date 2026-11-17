# PRD: Definitions → Admin (Admins invite and remove caregivers, promote other caregivers to admin and
#      demote them again, and manage the team's care receivers, trackers, care instructions, and
#      coverage … admins additionally manage the team's setup)
# PRD: Team → Care receiver (Every caregiver reads all of it; only admins change any of it)
Feature: What only an admin may change
  Every caregiver reads the team and its care receivers. Only admins change
  who is on the team, the receivers, and their care instructions.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" has joined "Riverside" as a caregiver
    And "Jordan" has joined "Riverside" as a caregiver
    And "Riverside" looks after "Grandma"

  # PRD: Team → A caregiver (one caregiver's membership of one care team; admins only)
  # PRD: Team → Care team (A caregiver acting on their own row is offered leaving and nothing else)
  Scenario: A caregiver cannot change anyone's role, their own included
    When "Sam" makes "Jordan" an admin on "Riverside"
    Then the answer is 403
    When "Sam" makes "Sam" an admin on "Riverside"
    Then the answer is 403
    When "Sam" makes "Alex" a caregiver on "Riverside"
    Then the answer is 403
    When "Jordan" opens the care team "Riverside"
    Then the care team's caregivers are:
      | name   | role      |
      | Alex   | admin     |
      | Sam    | caregiver |
      | Jordan | caregiver |

  # PRD: Team → Add care receiver (one care team; admins only)
  # PRD: Team → Edit care receiver (one care receiver; admins only)
  # PRD: Team → Archive this care receiver? (one care receiver; admins only)
  Scenario: A caregiver cannot add, change or archive a care receiver
    When "Sam" adds the care receiver "Grandpa" to "Riverside", keeping time in "America/Chicago"
    Then the answer is 403
    When "Sam" renames the care receiver "Grandma" to "Nana"
    Then the answer is 403
    When "Sam" archives the care receiver "Grandma"
    Then the answer is 403
    When "Sam" opens the care receivers of "Riverside"
    Then the care receivers listed are "Grandma"

  # PRD: Team → Care receiver (Restore — admin, when the receiver is archived)
  Scenario: A caregiver cannot restore an archived care receiver
    Given "Alex" archives the care receiver "Grandma"
    When "Sam" restores the care receiver "Grandma"
    Then the answer is 403
    When "Sam" opens the care receiver "Grandma"
    Then the care receiver reads as archived

  # PRD: Team → Edit care instructions (one care receiver's instructions; admins only)
  # PRD: Team → Emergency contacts (one care receiver's contacts; admins only)
  Scenario: A caregiver cannot write the care instructions or the emergency contacts
    When "Sam" writes the care instructions for "Grandma": "Pills with breakfast."
    Then the answer is 403
    When "Sam" sets the emergency contacts of "Grandma" to:
      | name  | relationship | phone        |
      | Robin | Daughter     | 312-555-0100 |
    Then the answer is 403
    When "Sam" opens the care receiver "Grandma"
    Then the care receiver has no care instructions yet
    And the care receiver has no emergency contacts yet
