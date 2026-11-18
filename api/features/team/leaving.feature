# PRD: Team (Leaving takes away the access, not the record)
# PRD: Team → Leave this care team? (what you lose — the access, and nothing else; what stays — every
#      entry and journal note you wrote, where it is, under your name)
Feature: Leaving a care team
  A caregiver may leave at any time. They lose the access and nothing else:
  every entry and journal note they wrote stays where it is, under their name.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" has joined "Riverside" as a caregiver
    And "Riverside" looks after "Grandma"

  # PRD: Definitions → Care team (A caregiver … may leave at any time)
  # PRD: Team → Leave this care team? (Leave → Team)
  Scenario: A caregiver leaves and can no longer reach the team
    When "Sam" leaves "Riverside"
    Then the answer is 204
    And "Sam" does not belong to "Riverside"
    When "Sam" opens the care team "Riverside"
    Then the answer is 403
    When "Alex" opens the care team "Riverside"
    Then the care team's caregivers are:
      | name | role  |
      | Alex | admin |

  # PRD: Team (every entry and journal note they wrote stays where it is, under their name)
  # PRD: Definitions → Care team (leaving takes away the access and not the record, so every entry
  #      and journal note they wrote stays exactly where it was, under their name)
  Scenario: What a caregiver recorded stays under their name after they leave
    Given "Grandma" has a tracker "Medication"
    And "Sam" logged "Medication" 3 hours ago
    And "Sam" wrote a journal note about "Grandma" at 15:00 1 day ago: "Slept well after lunch"
    When "Sam" leaves "Riverside"
    Then the answer is 204
    When "Alex" opens that entry
    Then the answer is 200
    And it is the "Medication" entry logged by "Sam" 3 hours ago
    When "Alex" opens that note
    Then the answer is 200
    And the note reads "Slept well after lunch", written by "Sam" about 15:00 1 day ago

  # PRD: Team → Care team (A caregiver acting on their own row is offered leaving and nothing else)
  # PRD: Definitions → Admin (Admins invite and remove caregivers)
  Scenario: A caregiver cannot remove anyone else
    Given "Jordan" has joined "Riverside" as a caregiver
    When "Sam" removes "Jordan" from "Riverside"
    Then the answer is 403
    And "Jordan" belongs to "Riverside" as a caregiver
