# PRD: Settings (Closing an account — the account goes, and the care stays)
# PRD: Settings → Close your account, Close this account?
# PRD: Definitions → Caregiver (a closed account's name becomes "a former caregiver")
Feature: Closing an account
  With the password, the account goes and everything it recorded stays,
  attributed to a former caregiver. Each care team is left the way leaving
  leaves it. An account cannot be closed while it is a team's only admin.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" has joined "Riverside" as a caregiver
    And "Jordan" has joined "Riverside" as a caregiver
    And "Riverside" looks after "Grandma"

  # PRD: Settings → Close this account? (Close account → Landing)
  # PRD: Settings (Every entry and journal note the caregiver wrote remains where it is, attributed to
  #      a former caregiver)
  Scenario: The account goes and what it recorded stays, attributed to a former caregiver
    Given "Grandma" has a tracker "Medication"
    And "Sam" logged "Medication" 3 hours ago
    And "Sam" wrote a journal note about "Grandma" at 15:00 1 day ago: "Slept well after lunch"
    When "Sam" closes their account with their password
    Then the answer is 204
    And "Sam" can no longer sign in
    When "Alex" opens that entry
    Then it is the "Medication" entry logged by "a former caregiver" 3 hours ago
    When "Alex" opens that note
    Then the note reads "Slept well after lunch", written by "a former caregiver" about 15:00 1 day ago
    When "Alex" opens the care team "Riverside"
    Then the care team's caregivers are:
      | name   | role      |
      | Alex   | admin     |
      | Jordan | caregiver |

  # PRD: Settings (Closing an account leaves every care team the way leaving does. The assignments
  #      still ahead of the caregiver go, and a coverage schedule naming them ends that day)
  Scenario: Closing leaves the roster the way leaving does
    Given "Alex" schedules "Sam" to cover "Grandma" every day from 08:00 to 16:00
    And "Alex" assigns "Sam" to "Grandma" in 3 days from 18:00 to 20:00
    When "Sam" closes their account with their password
    Then the answer is 204
    When "Jordan" opens the assignments ahead of "Grandma"
    Then "Sam" is not assigned tomorrow
    And "Sam" is not assigned in 3 days
    When "Jordan" opens the coverage schedules of "Grandma"
    Then "Sam"'s coverage schedule ends today

  # PRD: Settings → Close your account (Close my account, with a password that is not right → saying
  #      the password is not right)
  Scenario: A wrong password closes nothing
    When "Sam" closes their account with a wrong password
    Then the answer is 403 saying "the password is not right"
    And "Sam" belongs to "Riverside" as a caregiver

  # PRD: Settings (An account cannot be closed while it is a care team's only admin. The screen names
  #      the team and asks for someone else to be promoted first)
  # PRD: Settings → Close your account (when you are a care team's only admin → refused with the team
  #      named, asking to promote someone first, or to close the team first when you are alone on it)
  # PRD: Settings (A caregiver who is alone on a team has nobody to promote, so for that team the
  #      screen asks them to close it first instead)
  Scenario: The only admin is refused, with every such team named
    Given "Alex" has created the care team "Hillside"
    When "Alex" closes their account with their password
    Then the answer is 409, naming "Hillside" and "Riverside" as the care teams to promote someone on first
    And it asks to promote someone first on "Riverside"
    And it asks to close "Hillside" first, since nobody else is on it
    And "Alex" belongs to "Riverside" as an admin
    And "Alex" belongs to "Hillside" as an admin

  # PRD: Settings (An account cannot be closed while it is a care team's only admin)
  # PRD: Definitions → Care team (the last admin cannot … leave the team … until someone else has been
  #      promoted)
  Scenario: Once someone else is an admin, an admin may close their account
    Given "Alex" makes "Jordan" an admin on "Riverside"
    When "Alex" closes their account with their password
    Then the answer is 204
    And "Alex" can no longer sign in
    And "Jordan" belongs to "Riverside" as an admin
