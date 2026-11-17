# PRD: Definitions → Care team (A care team ends when its last caregiver closes it … the team is
#      archived, nobody can reach it any longer, and everything recorded in it is kept)
# PRD: Team → Close this care team?
Feature: Closing a care team
  The last caregiver on a team is offered Close this care team in place of
  Leave. Anyone else on the team leaves instead.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" has joined "Riverside" as a caregiver

  # PRD: Team → Care team (Close this care team, when you are the last caregiver on it)
  Scenario: A care team cannot be closed while someone else is on it
    When "Alex" closes "Riverside"
    Then the answer is 409
    And "Alex" belongs to "Riverside" as an admin
    When "Sam" closes "Riverside"
    Then the answer is 409
    And "Sam" belongs to "Riverside" as a caregiver

  # PRD: Definitions → Care team (the last caregiver is offered Close this care team in place of
  #      Leave: the team is archived, nobody can reach it any longer)
  # PRD: Team → Close this care team? (Close team → Team)
  Scenario: The last caregiver closes the team and it is gone from their teams
    Given "Sam" leaves "Riverside"
    When "Alex" closes "Riverside"
    Then the answer is 204
    And "Alex" belongs to no care team
    When "Alex" opens the care team "Riverside"
    Then the answer is 404
