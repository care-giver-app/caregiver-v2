# PRD: Trackers → Trackers (every tracker belonging to the active care receiver)
Feature: The Trackers list
  Trackers lists every tracker a care receiver has, active and paused,
  alphabetically. Each row says how long it has been since anything was
  logged, or that nothing ever has been; a paused row says when it was paused
  instead; and a row that needs attention says only that.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Trackers → Trackers (the trackers in the chosen view, alphabetical and staying there;
  #      all three filters — active, needs attention, paused — drawn from every tracker)
  # Contract: GET /v1/receivers/{receiverId}/trackers lists active and paused trackers, sorted by name
  Scenario: Every tracker is listed alphabetically, paused ones included
    Given "Grandma" has a tracker "Zinc"
    And "Grandma" has a tracker "Blood pressure"
    And "Grandma" has a tracker "medication"
    And "Grandma" has a tracker "Shower"
    And "Zinc" was paused 2 days ago
    When "Sam" opens the trackers of "Grandma"
    Then the answer is 200
    And the trackers listed are "Blood pressure", "medication", "Shower" and "Zinc"

  # PRD: Trackers → Trackers (each row: how long it has been since anything was logged
  #      against it, or that nothing ever has been)
  Scenario: A row says when the tracker was last logged, or that it never has been
    Given "Grandma" has a tracker "Shower"
    And "Grandma" has a tracker "Walk"
    And "Sam" logged "Walk" 2 days ago
    And "Sam" logged "Walk" 3 hours ago
    When "Sam" opens the trackers of "Grandma"
    Then the answer is 200
    And the row for "Walk" says it was last logged 3 hours ago
    And the row for "Shower" says it has never been logged

  # PRD: Trackers → Trackers (a paused tracker's row says when it was paused instead)
  Scenario: A paused tracker's row says when it was paused
    Given "Grandma" has a tracker "Zinc"
    And "Zinc" was paused 2 days ago
    When "Sam" opens the trackers of "Grandma"
    Then the answer is 200
    And the row for "Zinc" says it was paused 2 days ago

  # PRD: Trackers → Trackers (a row that needs attention says only that)
  # PRD: Trackers (a paused tracker is never among those in trouble, because its thresholds have stopped)
  Scenario: A row needing attention says so, and a paused tracker never does
    Given "Grandma" has a tracker "Medication"
    And "Medication" was due 2 hours ago and nobody has logged it
    And "Grandma" has a tracker "Shower"
    And "Shower" is watched by a gap of 72 hours
    And "Sam" logged "Shower" 1 day ago
    And "Grandma" has a tracker "Zinc"
    And "Zinc" is watched by a gap of 24 hours
    And "Zinc" was paused 2 days ago
    When "Sam" opens the trackers of "Grandma"
    Then the answer is 200
    And the row for "Medication" says it needs attention
    And the row for "Shower" does not say it needs attention
    And the row for "Zinc" does not say it needs attention

  # PRD: Trackers (admins add trackers; every caregiver reads the list)
  # PRD: Definitions → Care team (every care receiver, tracker, and entry belongs to exactly one care team)
  # Contract: GET /v1/receivers/{receiverId}/trackers answers 403 to a caller not on the team
  Scenario Outline: <who> reading the list
    Given "Grandma" has a tracker "Shower"
    When "<person>" opens the trackers of "Grandma"
    Then the answer is <status>

    Examples:
      | who                         | person | status |
      | An admin                    | Alex   | 200    |
      | A caregiver                 | Sam    | 200    |
      | Someone not on the care team | Riley  | 403    |
