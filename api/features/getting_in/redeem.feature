# PRD: Getting into the app → Join a care team (accept an invitation, or paste an invite code)
Feature: Joining a care team with an invitation
  A caregiver joins a care team by accepting an invitation waiting for their
  email, or by pasting the invite code the admin sent them. Every invitation
  joins as a caregiver, never as an admin.

  Background:
    Given "Alex" has created the care team "Riverside"

  # PRD: Getting into the app → Join a care team (exit: Accept an invitation → Home)
  # PRD: Definitions → Invitation (every invitation joins a team as a caregiver; it is single-use)
  Scenario: Accepting an invitation joins the care team as a caregiver
    Given "Alex" has invited "Sam" to "Riverside"
    When "Sam" accepts their invitation to "Riverside"
    Then the answer is 200
    And "Sam" belongs to "Riverside" as a caregiver
    And "Sam" has no pending invitations

  # PRD: Getting into the app → Signed in with no care team (a code the app will not take
  #      is answered the same way whatever is wrong with it)
  # Contract: POST /v1/invitations/redeem answers 410 InvitationNotValid (unknown, expired, used, or revoked)
  Scenario Outline: An invite code that <problem> is refused with the same answer
    Given "Alex" has invited "Sam" to "Riverside"
    But the invite code for "Riverside" <problem>
    When "Sam" pastes the invite code for "Riverside"
    Then the answer is 410 "invitation not valid" and nothing more
    And "Sam" does not belong to "Riverside"

    Examples:
      | problem               |
      | was never issued      |
      | has expired           |
      | has already been used |
      | has been revoked      |

  # PRD: Definitions → Invitation (for Hide My Email, or a different address than the admin had on hand)
  Scenario: An invite code sent to a different email address still works
    Given "Alex" has invited a different email address than "Sam"'s to "Riverside"
    Then "Sam" has no pending invitations
    When "Sam" pastes the invite code for "Riverside"
    Then the answer is 200
    And "Sam" belongs to "Riverside" as a caregiver
