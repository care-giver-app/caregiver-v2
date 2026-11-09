# PRD: Definitions → Care receiver (each care receiver has a time zone, and every wall-clock rule
#      about them is expressed in it)
Feature: A care team's care receivers
  The app picks the active care receiver from the care team's receivers. Each
  is listed with the time zone their care is read in. A receiver the team has
  archived has stopped being cared for and is not offered.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"
    And "Riverside" looks after "Grandpa"

  # PRD: Definitions → Care receiver (each care receiver has a time zone)
  # Contract: GET /v1/teams/{teamId}/receivers lists the team's receivers, oldest first
  Scenario: Every care receiver is listed, oldest first, with their time zone
    When "Sam" opens the care receivers of "Riverside"
    Then the answer is 200
    And the care receivers listed are "Grandma" and "Grandpa"
    And every care receiver listed keeps time in "America/Chicago"

  # PRD: Definitions → Care receiver (archiving: the receiver leaves Home, the receiver switcher
  #      and Quick log)
  Scenario: An archived care receiver is not offered
    Given the care receiver "Grandpa" has been archived
    When "Sam" opens the care receivers of "Riverside"
    Then the answer is 200
    And the care receivers listed are "Grandma"

  # PRD: Definitions → Care team (every care receiver, tracker, and entry belongs to exactly one care team)
  # Contract: GET /v1/teams/{teamId}/receivers answers 403 to a caller not on the team
  Scenario Outline: <who> listing the care receivers
    When "<person>" opens the care receivers of "Riverside"
    Then the answer is <status>

    Examples:
      | who                          | person | status |
      | An admin                     | Alex   | 200    |
      | A caregiver                  | Sam    | 200    |
      | Someone not on the care team | Riley  | 403    |
