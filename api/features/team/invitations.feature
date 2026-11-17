# PRD: Definitions → Invitation (An admin creates an invitation for a particular email address …
#      every invitation also carries an invite code the admin copies and sends)
# PRD: Team → Invite a caregiver
Feature: Inviting a caregiver
  An admin invites an address and lands back on the team, where the invitation
  is a row in the pending list with its code beside it to copy.

  Background:
    Given "Alex" has created the care team "Riverside"

  # PRD: Team (Creating an invitation ends on the team … the invitation is now a row in the pending
  #      list with its code beside it)
  # PRD: Team → Care team (pending invitations, each with its invite code to copy — admins only)
  Scenario: An invitation an admin creates is pending with its code
    When "Alex" invites "Sam" to "Riverside"
    Then the answer is 201
    When "Alex" opens the pending invitations of "Riverside"
    Then the answer is 200
    And the invitations pending are for "Sam", each with the invite code it was created with

  # PRD: Definitions → Invitation (A caregiver who signs up with the address they were invited at
  #      finds the invitation waiting in the app and accepts it)
  # PRD: Definitions → Invitation (Every invitation joins a team as a caregiver)
  # PRD: Definitions → Invitation (An admin can copy it again … for as long as it goes unused)
  Scenario: The invitee finds the invitation waiting and joins as a caregiver
    Given "Alex" invites "Sam" to "Riverside"
    Then "Sam" has a pending invitation to "Riverside" from "Alex"
    When "Sam" accepts their invitation to "Riverside"
    Then the answer is 200
    And "Sam" belongs to "Riverside" as a caregiver
    When "Alex" opens the pending invitations of "Riverside"
    Then no invitations are pending

  # PRD: Definitions → Invitation (every invitation also carries an invite code the admin copies and
  #      sends, and the invitee pastes into the app)
  Scenario: The invite code an admin copies joins whoever pastes it
    Given "Alex" invites "Sam" to "Riverside"
    When "Casey" pastes the invite code for "Riverside"
    Then the answer is 200
    And "Casey" belongs to "Riverside" as a caregiver

  # PRD: Definitions → Invitation (An admin cannot create one for somebody already on the team)
  # PRD: Team → Invite a caregiver (Create invitation, when the address already belongs to someone on
  #      this care team → refused because they are already a member)
  Scenario: Inviting someone already on the team is refused
    Given "Sam" has joined "Riverside" as a caregiver
    When "Alex" invites "Sam" to "Riverside"
    Then the answer is 409
    When "Alex" opens the pending invitations of "Riverside"
    Then no invitations are pending

  # PRD: Team → Care team (pending invitations … — admins only)
  # PRD: Team → Invite a caregiver (one care team; admins only)
  Scenario: A caregiver can neither invite nor see the pending invitations
    Given "Sam" has joined "Riverside" as a caregiver
    When "Sam" invites "Casey" to "Riverside"
    Then the answer is 403
    When "Sam" opens the pending invitations of "Riverside"
    Then the answer is 403
