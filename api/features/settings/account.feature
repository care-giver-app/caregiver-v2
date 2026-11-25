# PRD: Settings (Your account and this device — a caregiver's name is theirs to change, because it
#      is what every entry and note they write is signed with)
# PRD: Settings → Change name, Notifications (email, on or off)
Feature: A caregiver's own name and email channel
  A caregiver changes their own name, which signs everything they write on
  screens the whole team reads, and turns email on or off once for the
  account.

  # PRD: Settings → Change name (Save → Settings)
  Scenario: A caregiver changes their name and the team sees it
    Given "Alex" has created the care team "Riverside"
    And "Sam" has joined "Riverside" as a caregiver
    When "Sam" changes their name to "Sam Lee"
    Then the answer is 200
    And "Sam"'s account shows the name "Sam Lee" with email notifications on
    When "Alex" opens the care team "Riverside"
    Then the care team's caregivers are:
      | name    | role      |
      | Alex    | admin     |
      | Sam Lee | caregiver |

  # PRD: Settings → Notifications (email, on or off; turn email on or off → Notifications)
  Scenario: A caregiver turns email off and on again
    Given "Sam" signs in
    When "Sam" turns email notifications off
    Then the answer is 200
    And "Sam"'s account shows the name "Sam" with email notifications off
    When "Sam" turns email notifications on
    Then "Sam"'s account shows the name "Sam" with email notifications on

  # PRD: Settings → Change name (your name)
  Scenario: A name must be there to be saved
    Given "Sam" signs in
    When "Sam" changes their name to "   "
    Then the answer is 400
    And "Sam"'s account shows the name "Sam" with email notifications on

  # Contract: ChangeMyAccountRequest has at least one field
  Scenario: Saving nothing is refused
    Given "Sam" signs in
    When "Sam" saves their account with nothing changed
    Then the answer is 400
