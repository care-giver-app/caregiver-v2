# PRD: Getting into the app → Create your first care team
Feature: Creating a care team
  A caregiver who belongs to no care team can create one instead of waiting
  for an invitation. The caregiver who creates a care team is its first admin.

  # PRD: Definitions → Admin (the caregiver who creates a care team is its first admin)
  # PRD: Getting into the app → Create your first care team (exit: Team, with the new team on the list)
  Scenario: Creating a care team makes the caregiver its admin
    When "Alex" creates a care team named "  Riverside  "
    Then the answer is 201
    And the new care team is called "Riverside"
    And "Alex" belongs to "Riverside" as an admin

  # PRD: Getting into the app → Create your first care team (care team name)
  # Contract: CreateTeamRequest.name is 1 to 100 characters
  Scenario Outline: A care team name that is <problem> is refused
    When "Alex" creates a care team <how>
    Then the answer is 400
    And "Alex" belongs to no care team

    Examples:
      | problem  | how                                    |
      | blank    | named "   "                            |
      | too long | whose name is 101 characters long      |
