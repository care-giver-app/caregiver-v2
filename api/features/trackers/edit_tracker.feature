# PRD: Trackers → Edit tracker (one tracker; admins only)
# PRD: Trackers → A field
Feature: Editing a tracker
  Once a tracker exists its fields are never deleted, only paused, and a
  field's type is fixed; a choice field's options are retired, never deleted.
  A tracker has schedules or a gap, never both.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"
    And "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Blood pressure" has a number field "Pulse"

  # PRD: Definitions → Field (a field is never deleted, because deleting one would take real readings with it)
  # PRD: Trackers → Edit tracker (a switch that pauses or resumes it — never deletes it)
  # Contract: PUT /v1/trackers/{trackerId} answers 400 when fields leaves out an existing field
  Scenario: A field cannot be deleted once the tracker exists
    When "Alex" saves "Blood pressure" without its "Pulse" field
    Then the answer is 400 saying "left out"
    When "Alex" opens "Blood pressure"
    Then it collects "Systolic" and "Pulse"

  # PRD: Definitions → Field (a choice field's options can be added, renamed, and retired, but never deleted)
  # Contract: PUT /v1/trackers/{trackerId} answers 400 when an existing choice option is dropped
  Scenario: A choice field's option cannot be deleted
    Given "Grandma" has a tracker "Mood"
    And "Mood" has a choice field "Mood" offering "great", "ok", "low" and "bad"
    When "Alex" saves "Mood" without the "bad" option of its "Mood" field
    Then the answer is 400 saying "left out"
    When "Alex" opens "Mood"
    Then its "Mood" field still offers "bad"

  # PRD: Trackers → A field (on a tracker that exists, a field's type is shown but cannot be changed)
  # Contract: PUT /v1/trackers/{trackerId} answers 400 when an existing field's type changes
  Scenario: A field's type cannot change once the tracker exists
    When "Alex" saves "Blood pressure" with its "Systolic" field turned into a text field
    Then the answer is 400 saying "type cannot change"
    When "Alex" opens "Blood pressure"
    Then its "Systolic" field is still a number

  # PRD: Definitions → Field (a field can be paused, which stops it being collected; a paused field
  #      resumes where it left off)
  Scenario: A field is paused and resumed
    When "Alex" pauses the "Pulse" field of "Blood pressure"
    Then the answer is 200
    And its "Pulse" field is paused
    And its "Systolic" field is active
    When "Alex" resumes the "Pulse" field of "Blood pressure"
    Then the answer is 200
    And its "Pulse" field is active

  # PRD: Definitions → Threshold (a tracker has schedules or a gap, never both; an admin changing
  #      either is told what they are about to lose)
  # Contract: PUT /v1/trackers/{trackerId} answers 409 SchedulesOrGap when a gap is turned on over schedules
  Scenario: Turning on a gap over a tracker's schedules is refused
    Given "Grandma" has a tracker "Medication"
    And "Medication" has a schedule labelled "Morning dose" every day at 08:00
    When "Alex" turns on a gap of 72 hours for "Medication"
    Then the answer is 409
    When "Alex" opens "Medication"
    Then it is not watched by a gap
    And it has 1 schedule

  # PRD: Trackers → Tracker detail (only admins see Edit, since admins manage the team's trackers)
  Scenario: A caregiver cannot edit a tracker
    When "Sam" pauses the "Pulse" field of "Blood pressure"
    Then the answer is 403
    When "Alex" opens "Blood pressure"
    Then its "Pulse" field is active
