# PRD: Team (A care team always has an admin. Nothing anyone does may leave one without: the last
#      admin cannot demote themselves, cannot leave … and each attempt is refused with the same
#      answer — promote someone first)
# PRD: Definitions → Care team (A team always has at least one admin)
Feature: A care team always has an admin
  The last admin cannot demote themselves or leave, and is told to promote
  someone first. With a second admin, either of them may step down or go.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" has joined "Riverside" as a caregiver

  # PRD: Team → A caregiver (demote or remove the team's only admin → refused with the reason)
  Scenario: The only admin cannot make themselves a caregiver
    When "Alex" makes "Alex" a caregiver on "Riverside"
    Then the answer is 409 saying "promote someone first"
    And "Alex" belongs to "Riverside" as an admin

  # PRD: Team → Care team (Leave this care team, when you are the team's only admin → refused with
  #      the reason rather than a greyed-out row)
  Scenario: The only admin cannot leave
    When "Alex" leaves "Riverside"
    Then the answer is 409 saying "promote someone first"
    And "Alex" belongs to "Riverside" as an admin

  # PRD: Definitions → Care team (the last admin cannot demote themselves … until someone else has
  #      been promoted)
  Scenario: Once someone else is an admin, an admin may become a caregiver
    Given "Alex" makes "Sam" an admin on "Riverside"
    When "Alex" makes "Alex" a caregiver on "Riverside"
    Then the answer is 200
    And "Alex" belongs to "Riverside" as a caregiver
    And "Sam" belongs to "Riverside" as an admin
    When "Sam" makes "Sam" a caregiver on "Riverside"
    Then the answer is 409 saying "promote someone first"

  # PRD: Definitions → Care team (the last admin cannot … leave the team … until someone else has
  #      been promoted)
  Scenario: Once someone else is an admin, an admin may leave
    Given "Alex" makes "Sam" an admin on "Riverside"
    When "Alex" leaves "Riverside"
    Then the answer is 204
    And "Alex" does not belong to "Riverside"
    When "Sam" leaves "Riverside"
    Then the answer is 409 saying "promote someone first"
    And "Sam" belongs to "Riverside" as an admin
