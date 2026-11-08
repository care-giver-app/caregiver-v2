# PRD: Trackers → Schedules (one tracker's schedules, read by anyone on the team)
# PRD: Definitions → Tracker schedule
Feature: A tracker's schedules
  Every caregiver on the team can read a tracker's schedules. A schedule left
  unlabelled takes a name derived from itself, so several schedules on one
  tracker read as a regimen rather than as copies of the tracker's name.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"
    And "Grandma" has a tracker "Medication"
    And "Medication" has a schedule labelled "Morning dose" every day at 08:00
    And "Medication" has an unlabelled schedule on Mon, Wed and Fri at 20:00

  # PRD: Trackers → Tracker detail (how many schedules it has, opening Schedules)
  Scenario: Tracker detail says how many schedules it has
    When "Sam" opens "Medication"
    Then the answer is 200
    And it has 2 schedules

  # PRD: Trackers (left unlabelled it takes a name derived from itself, so three schedules on one
  #      tracker read as a regimen rather than as three copies of the tracker's name)
  # PRD: Trackers → Schedules (read by anyone on the team)
  Scenario: A caregiver reads the schedules, an unlabelled one by a name of its own
    When "Sam" reads the schedules of "Medication"
    Then the answer is 200
    And the schedules are named "Morning dose" and one named for its days and time rather than "Medication"

  # PRD: Definitions → Care team (every care receiver, tracker, and entry belongs to exactly one care team)
  # Contract: GET /v1/trackers/{trackerId}/schedules answers 403 to a caller not on the team
  Scenario: Someone not on the care team cannot read the schedules
    When "Riley" reads the schedules of "Medication"
    Then the answer is 403
