# PRD: Getting into the app (signed in is a resolution: the app settles the
#      caregiver's identity and care teams, and that decides where they land)
Feature: Signing in
  When a caregiver signs in, the app learns who they are and which care teams
  they belong to. That answer decides where they land: Home if they belong to
  a care team, Join a care team if they do not.

  # PRD: Getting into the app → Join a care team (scope: the signed-in caregiver, when they belong to no care team)
  Scenario: A new caregiver signs in for the first time and belongs to no care team
    When "Sam" signs in
    Then the answer is 200
    And the answer lists no care teams
    And the answer shows "Sam"'s name and email address

  # PRD: Getting into the app (the sign-in resolution only runs once the app knows who you are)
  # Contract: GET /v1/me answers 401 to a caller who has not signed in
  Scenario: Asking for an account without signing in is refused
    When someone who has not signed in asks for their account
    Then the answer is 401

  # PRD: Definitions → Caregiver (closing an account takes away their way back in)
  Scenario: A caregiver whose account has been closed is refused
    Given "Sam" has closed their account
    When "Sam" signs in
    Then the answer is 401
