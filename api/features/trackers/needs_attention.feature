# PRD: Trackers → Tracker detail (what is wrong right now, only when something is)
# PRD: Home (what needs attention: care gone unrecorded, a reading outside its range,
#      a tracker past its gap)
Feature: What needs attention on a tracker
  Tracker detail says what is wrong with a tracker right now, and only when
  something is: care that went unrecorded in the last forty-eight hours, a
  latest reading outside its range, or a gap run past.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Definitions → Entry (unrecorded: its scheduled time has passed and nobody has logged it)
  # PRD: Home (an unrecorded occurrence leaves needs attention forty-eight hours after its scheduled time)
  Scenario: Care that went unrecorded needs attention
    Given "Grandma" has a tracker "Medication"
    And "Medication" was due 3 hours ago and nobody has logged it
    When "Sam" opens "Medication"
    Then the answer is 200
    And it needs attention for the care due 3 hours ago that went unrecorded

  # PRD: Home (an unrecorded occurrence leaves needs attention forty-eight hours after its scheduled
  #      time; it is still unrecorded, and still in its tracker's list)
  # PRD: Definitions → Alert (an occurrence raises an alert for forty-eight hours, then goes quiet)
  Scenario: Unrecorded care stops needing attention once forty-eight hours have passed
    Given "Grandma" has a tracker "Medication"
    And "Medication" was due 49 hours ago and nobody has logged it
    When "Sam" opens "Medication"
    Then the answer is 200
    And nothing about it needs attention
    When "Sam" reads the entries of "Medication"
    Then the entries are, newest first:
      | state      | when         | by |
      | unrecorded | 49 hours ago |    |

  # PRD: Definitions → Threshold (a range on a numeric field raises an alert when a logged value falls outside it)
  Scenario: A latest reading outside its range needs attention
    Given "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Sam" logged "Blood pressure" 3 hours ago with "Systolic" at 165
    When "Sam" opens "Blood pressure"
    Then the answer is 200
    And it needs attention because "Systolic" read 165, outside 90 to 140

  # PRD: Home (a range alert stands until a later reading comes back in range)
  Scenario: A later reading back in range clears it
    Given "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Sam" logged "Blood pressure" 3 hours ago with "Systolic" at 165
    And "Sam" logged "Blood pressure" 1 hour ago with "Systolic" at 128
    When "Sam" opens "Blood pressure"
    Then the answer is 200
    And nothing about it needs attention

  # PRD: Definitions → Field (a paused field's range stops raising alerts)
  Scenario: A paused field's range raises nothing
    Given "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Blood pressure" has a number field "Pulse" expected between 50 and 100
    And the "Pulse" field of "Blood pressure" has been paused
    And "Sam" logged "Blood pressure" 3 hours ago with "Pulse" at 130
    When "Sam" opens "Blood pressure"
    Then the answer is 200
    And nothing about it needs attention

  # PRD: Definitions → Threshold (a tracker that has never been logged counts from the day it was created)
  # PRD: Trackers → Tracker detail (for a gap alert, how long it has gone unlogged against how
  #      long the team said was acceptable)
  Scenario: A gap on a tracker never logged counts from when it was created
    Given "Grandma" has a tracker "Shower"
    And "Shower" is watched by a gap of 72 hours
    And "Shower" was created 4 days ago
    When "Sam" opens "Shower"
    Then the answer is 200
    And it has never been logged
    And it needs attention because nothing has been logged since it was created 4 days ago, past its gap of 72 hours

  # PRD: Definitions → Threshold (a gap raises an alert when that long passes with no entry at all)
  Scenario: A gap counts from the last entry
    Given "Grandma" has a tracker "Shower"
    And "Shower" is watched by a gap of 72 hours
    And "Shower" was created 10 days ago
    And "Sam" logged "Shower" 4 days ago
    When "Sam" opens "Shower"
    Then the answer is 200
    And it needs attention because nothing has been logged since 4 days ago, past its gap of 72 hours

  # PRD: Home (a gap stands until someone logs the tracker)
  Scenario: A tracker logged within its gap needs nothing
    Given "Grandma" has a tracker "Shower"
    And "Shower" is watched by a gap of 72 hours
    And "Shower" was created 10 days ago
    And "Sam" logged "Shower" 1 day ago
    When "Sam" opens "Shower"
    Then the answer is 200
    And nothing about it needs attention

  # PRD: Definitions → Threshold (a resumed tracker counts from the day it was resumed)
  Scenario: A resumed tracker's gap counts from when it was resumed
    Given "Grandma" has a tracker "Shower"
    And "Shower" is watched by a gap of 72 hours
    And "Shower" was created 20 days ago
    And "Sam" logged "Shower" 14 days ago
    And "Shower" was paused 13 days ago
    When "Alex" resumes "Shower"
    And "Sam" opens "Shower"
    Then the answer is 200
    And nothing about it needs attention

  # PRD: Definitions → Tracker (pausing: its thresholds stop raising alerts)
  Scenario: A paused tracker needs no attention
    Given "Grandma" has a tracker "Shower"
    And "Shower" is watched by a gap of 72 hours
    And "Shower" was created 10 days ago
    And "Shower" was paused 1 day ago
    When "Sam" opens "Shower"
    Then the answer is 200
    And it reads as paused
    And nothing about it needs attention
