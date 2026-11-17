# PRD: Team → Add care receiver (one care team; admins only: name, time zone)
# PRD: Team → Edit care receiver
# PRD: Definitions → Care receiver (archiving stops the future without touching the past)
Feature: Adding, changing, archiving and restoring a care receiver
  An admin adds a care receiver with a name and a time zone, and can change
  either. A receiver the team stops caring for is archived: still readable
  from Team, no longer changed, and restorable.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" has joined "Riverside" as a caregiver

  # PRD: Team → Add care receiver (name, time zone; Add receiver → Home, with the new receiver active)
  # PRD: Team → Team (each team's care receivers, archived ones aside)
  Scenario: A care receiver an admin adds is one of the team's receivers
    When "Alex" adds the care receiver "Grandma" to "Riverside", keeping time in "America/Chicago"
    Then the answer is 201
    When "Sam" opens the care receivers of "Riverside"
    Then the care receivers listed are "Grandma"
    And every care receiver listed keeps time in "America/Chicago"
    When "Sam" opens the care receiver "Grandma"
    Then the answer is 200
    And the care receiver is "Grandma" of "Riverside", keeping time in "America/Chicago"

  # PRD: Team → Edit care receiver (name; Save → Care receiver)
  Scenario: An admin renames a care receiver
    Given "Riverside" looks after "Grandma"
    When "Alex" renames the care receiver "Grandma" to "Nana"
    Then the answer is 200
    When "Sam" opens the care receivers of "Riverside"
    Then the care receivers listed are "Nana"

  # PRD: Definitions → Care receiver (A care receiver can be archived … the receiver leaves Home, the
  #      receiver switcher and Quick log … readable by the team from Team)
  # PRD: Team → Care team (the team's archived care receivers, in a group of their own)
  Scenario: An archived care receiver moves to the team's archived receivers
    Given "Riverside" looks after "Grandma"
    And "Riverside" looks after "Grandpa"
    When "Alex" archives the care receiver "Grandpa"
    Then the answer is 204
    When "Sam" opens the care receivers of "Riverside"
    Then the care receivers listed are "Grandma"
    When "Sam" opens the archived care receivers of "Riverside"
    Then the answer is 200
    And the care receivers listed are "Grandpa"

  # PRD: Definitions → Care receiver (Everything recorded about them stays, readable by the team from
  #      Team but no longer changed)
  # PRD: Team → Care receiver (when archived, all of it unchanged but read-only)
  Scenario: An archived care receiver can be read but not changed
    Given "Riverside" looks after "Grandma"
    And "Alex" writes the care instructions for "Grandma": "Morning pills go down with food."
    And "Alex" archives the care receiver "Grandma"
    When "Sam" opens the care receiver "Grandma"
    Then the answer is 200
    And the care receiver reads as archived
    And the care instructions read "Morning pills go down with food.", last changed by "Alex" just now
    When "Alex" renames the care receiver "Grandma" to "Nana"
    Then the answer is 409
    When "Alex" writes the care instructions for "Grandma": "Pills with breakfast."
    Then the answer is 409
    When "Alex" sets the emergency contacts of "Grandma" to:
      | name  | relationship | phone        |
      | Robin | Daughter     | 312-555-0100 |
    Then the answer is 409
    When "Alex" opens the care receiver "Grandma"
    Then the care instructions read "Morning pills go down with food.", last changed by "Alex" just now
    And the care receiver has no emergency contacts yet

  # PRD: Definitions → Care receiver (an admin can restore them, returning everything as it was)
  # PRD: Team → Care receiver (Restore → Care receiver, no longer archived)
  Scenario: A restored care receiver is back among the team's receivers
    Given "Riverside" looks after "Grandma"
    And "Alex" archives the care receiver "Grandma"
    When "Alex" restores the care receiver "Grandma"
    Then the answer is 204
    When "Sam" opens the care receiver "Grandma"
    Then the care receiver reads as active
    When "Sam" opens the care receivers of "Riverside"
    Then the care receivers listed are "Grandma"
    When "Sam" opens the archived care receivers of "Riverside"
    Then no care receivers are listed

  # PRD: Definitions → Care receiver (archiving … their schedules stop generating)
  # PRD: Team → Archive this care receiver? (what stops — … their schedules stop)
  # PRD: Definitions → Care receiver (an admin can restore them, returning everything as it was)
  Scenario: Archiving stops a receiver's schedules, and restoring starts them again
    Given "Riverside" looks after "Grandma"
    And "Grandma" has a tracker "Medication"
    And "Alex" adds a schedule labelled "Morning dose" to "Medication" every day at 08:00
    And something is waiting ahead of "Medication"
    When "Alex" archives the care receiver "Grandma"
    Then the answer is 204
    And nothing is still waiting ahead of "Medication"
    When "Alex" restores the care receiver "Grandma"
    Then the answer is 204
    And something is waiting ahead of "Medication"

  # PRD: Definitions → Care receiver (If a receiver's time zone changes … their routines keep their
  #      wall-clock times and shift with them)
  # PRD: Team → Edit care receiver (time zone — changing it keeps the receiver's routines at their
  #      wall-clock times and shifts them along)
  Scenario: Moving a care receiver keeps their routines at the same wall-clock time
    Given "Riverside" looks after "Grandma"
    And "Grandma" has a tracker "Medication"
    And "Alex" adds a schedule labelled "Morning dose" to "Medication" every day at 08:00
    When "Sam" opens Coming up for "Grandma"
    Then the next "Medication" coming up is due at 08:00 in "America/Chicago"
    When "Alex" moves the care receiver "Grandma" to the time zone "Europe/London"
    Then the answer is 200
    When "Sam" opens the care receiver "Grandma"
    Then the care receiver is "Grandma" of "Riverside", keeping time in "Europe/London"
    When "Sam" opens Coming up for "Grandma"
    Then the next "Medication" coming up is due at 08:00 in "Europe/London"
