# PRD: Team → Care team (its caregivers and the role each of them holds, readable by every
#      caregiver rather than admins alone)
# PRD: Definitions → Admin (every caregiver can see who else is on the team and what role they hold)
Feature: Who is on a care team
  Reading the roster is not an admin privilege: every caregiver sees who else
  is on their team and what role each of them holds.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" has joined "Riverside" as a caregiver
    And "Jordan" has joined "Riverside" as a caregiver

  # PRD: Team (Every caregiver sees who else is on their team and what role each of them holds)
  Scenario Outline: <who> sees everyone on the team and their role
    When "<person>" opens the care team "Riverside"
    Then the answer is 200
    And the care team's caregivers are:
      | name   | role      |
      | Alex   | admin     |
      | Sam    | caregiver |
      | Jordan | caregiver |

    Examples:
      | who         | person |
      | An admin    | Alex   |
      | A caregiver | Sam    |

  # PRD: Definitions → Care team (a shared space containing one or more care receivers and the
  #      caregivers who look after them)
  # Contract: GET /v1/teams/{teamId} answers 403 to a caller not on the team
  Scenario: Someone not on the care team cannot see who is on it
    When "Riley" opens the care team "Riverside"
    Then the answer is 403

  # PRD: Definitions → Admin (Admins … promote other caregivers to admin and demote them again)
  # PRD: Team → A caregiver (make admin, make caregiver → Care team)
  Scenario: An admin promotes a caregiver and demotes them again
    When "Alex" makes "Sam" an admin on "Riverside"
    Then the answer is 200
    When "Jordan" opens the care team "Riverside"
    Then the care team's caregivers are:
      | name   | role      |
      | Alex   | admin     |
      | Sam    | admin     |
      | Jordan | caregiver |
    When "Alex" makes "Sam" a caregiver on "Riverside"
    Then the answer is 200
    And "Sam" belongs to "Riverside" as a caregiver

  # PRD: Definitions → Admin (Admins invite and remove caregivers)
  # PRD: Team → A caregiver (remove from this care team → Care team)
  Scenario: An admin removes a caregiver
    When "Alex" removes "Jordan" from "Riverside"
    Then the answer is 204
    And "Jordan" does not belong to "Riverside"
    When "Sam" opens the care team "Riverside"
    Then the care team's caregivers are:
      | name | role      |
      | Alex | admin     |
      | Sam  | caregiver |
