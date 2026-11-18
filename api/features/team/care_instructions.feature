# PRD: Definitions → Care instructions (a single free-form document … records who last changed it
#      and when … Beside the document is a list of emergency contacts … in the order the admin sets,
#      or none)
# PRD: Team → Care receiver (the care instructions … with who last changed them and when; emergency
#      contacts … in the order the admin set)
Feature: Care instructions and emergency contacts
  A care receiver's instructions are one document that says who last changed
  it. Beside it sit the emergency contacts, in the order an admin set. Admins
  write both; every caregiver reads them.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" has joined "Riverside" as a caregiver
    And "Riverside" looks after "Grandma"

  # PRD: Team → Care receiver (empty: no care instructions have been written — one line saying so;
  #      no emergency contacts — one line saying so)
  Scenario: A new care receiver has no instructions and no contacts yet
    When "Sam" opens the care receiver "Grandma"
    Then the answer is 200
    And the care receiver has no care instructions yet
    And the care receiver has no emergency contacts yet

  # PRD: Team → Edit care instructions (Save → Care receiver, recording who changed it and when)
  # PRD: Definitions → Care instructions (kept by the team's admins and readable by every caregiver)
  Scenario: Instructions an admin writes say who changed them and when
    When "Alex" writes the care instructions for "Grandma": "Morning pills go down with food."
    Then the answer is 200
    When "Sam" opens the care receiver "Grandma"
    Then the care instructions read "Morning pills go down with food.", last changed by "Alex" just now

  # PRD: Definitions → Care instructions (The document records who last changed it and when)
  Scenario: Another admin's change to the instructions is the one recorded
    Given "Jordan" has joined "Riverside" as an admin
    And "Alex" writes the care instructions for "Grandma": "Morning pills go down with food."
    When "Jordan" writes the care instructions for "Grandma": "Morning pills with food; walker past the kitchen."
    Then the answer is 200
    When "Sam" opens the care receiver "Grandma"
    Then the care instructions read "Morning pills with food; walker past the kitchen.", last changed by "Jordan" just now

  # PRD: Definitions → Care instructions (The document records who last changed it — the document,
  #      beside which the emergency contacts are a list of their own)
  Scenario: Changing the emergency contacts does not change who last changed the instructions
    Given "Jordan" has joined "Riverside" as an admin
    And "Alex" writes the care instructions for "Grandma": "Morning pills go down with food."
    When "Jordan" sets the emergency contacts of "Grandma" to:
      | name  | relationship | phone        |
      | Robin | Daughter     | 312-555-0100 |
    Then the answer is 200
    When "Sam" opens the care receiver "Grandma"
    Then the care instructions read "Morning pills go down with food.", last changed by "Alex" just now

  # PRD: Definitions → Care instructions (each a name, a relationship, and a phone number … in the
  #      order the admin sets)
  # PRD: Team → Emergency contacts (each contact's name, relationship, and phone number; the order
  #      they appear in; add a contact, and remove one)
  Scenario: Emergency contacts keep the order the admin sets
    When "Alex" sets the emergency contacts of "Grandma" to:
      | name   | relationship | phone        |
      | Robin  | Daughter     | 312-555-0100 |
      | Dr Lee | Physician    | 312-555-0199 |
    Then the answer is 200
    When "Sam" opens the care receiver "Grandma"
    Then the emergency contacts are, in order:
      | name   | relationship | phone        |
      | Robin  | Daughter     | 312-555-0100 |
      | Dr Lee | Physician    | 312-555-0199 |
    When "Alex" sets the emergency contacts of "Grandma" to:
      | name   | relationship | phone        |
      | Dr Lee | Physician    | 312-555-0199 |
      | Casey  | Neighbor     | 312-555-0142 |
      | Robin  | Daughter     | 312-555-0100 |
    Then the answer is 200
    When "Sam" opens the care receiver "Grandma"
    Then the emergency contacts are, in order:
      | name   | relationship | phone        |
      | Dr Lee | Physician    | 312-555-0199 |
      | Casey  | Neighbor     | 312-555-0142 |
      | Robin  | Daughter     | 312-555-0100 |

  # PRD: Team → Care receiver (empty: no care instructions have been written — one line saying so)
  Scenario: Clearing the instructions leaves none written
    Given "Alex" writes the care instructions for "Grandma": "Morning pills go down with food."
    When "Alex" clears the care instructions for "Grandma"
    Then the answer is 200
    When "Sam" opens the care receiver "Grandma"
    Then the care receiver has no care instructions yet
