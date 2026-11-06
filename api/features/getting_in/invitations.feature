# PRD: Getting into the app → Join a care team (invitations waiting for your email,
#      each with its care team and who invited you)
Feature: Invitations waiting for a caregiver
  A caregiver who signs up with the address they were invited at finds the
  invitation waiting in the app, showing the care team and who invited them.

  Background:
    Given "Alex" has created the care team "Riverside"

  # PRD: Getting into the app → Join a care team (each with its care team and who invited you)
  Scenario: A pending invitation shows the care team and who sent it
    Given "Alex" has invited "Sam" to "Riverside"
    Then "Sam" has a pending invitation to "Riverside" from "Alex"

  # PRD: Definitions → Caregiver (a closed account's name becomes "a former caregiver")
  Scenario: An invitation from someone whose account has since closed
    Given "Alex" has invited "Sam" to "Riverside"
    And "Alex" has closed their account
    Then "Sam" has a pending invitation to "Riverside" from "a former caregiver"

  # PRD: Definitions → Invitation (an invitation redeemed by an existing member is refused as it is redeemed)
  # Contract: GET /v1/me/invitations includes invitations to teams the caller already belongs to
  Scenario: An invitation to a care team the caregiver already belongs to
    Given "Sam" is already a caregiver on "Riverside"
    And "Alex" has invited "Sam" to "Riverside"
    Then "Sam" has a pending invitation to "Riverside" from "Alex"
    When "Sam" accepts their invitation to "Riverside"
    Then the answer is 409 "already a member of this care team"
    And "Sam" has a pending invitation to "Riverside" from "Alex"

  # PRD: Definitions → Care team (a closed team is archived and nobody can reach it any longer)
  Scenario: An invitation to a care team that has been closed
    Given "Alex" has invited "Sam" to "Riverside"
    And "Riverside" has been closed
    Then "Sam" has no pending invitations
    When "Sam" pastes the invite code for "Riverside"
    Then the answer is 410 "invitation not valid"
    And "Sam" does not belong to "Riverside"
