# PRD: Trackers → Add tracker (a new tracker for the active care receiver; admins only)
# PRD: Definitions → Tracker template
Feature: Adding a tracker
  An admin adds a tracker by starting from a template and changing anything it
  brought before the tracker is created. Creating it lands on the new tracker.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Definitions → Tracker template (the catalogue: weight, a walk, mood, urination, a bowel
  #      movement, a shower, medication, a doctor's appointment)
  # Contract: GET /v1/tracker-templates is ordered as Add tracker shows them
  Scenario: The template catalogue
    When "Sam" looks at the tracker templates
    Then the templates are "Mood", "Shower", "Urination", "Bowel Movement", "Medication", "Walk", "Weight" and "Doctor Appointment", in that order
    And the templates watched by a gap are "Shower" and "Bowel Movement"
    And the "Shower" template collects nothing
    And the "Medication" template collects nothing

  # PRD: Trackers → Add tracker (exit: Create → Tracker detail, on the tracker just made)
  # PRD: Definitions → Tracker template (Weight arrives already knowing it is a number in pounds
  #      with a range around it)
  Scenario: An admin creates a tracker from a template and lands on it
    When "Alex" adds a tracker to "Grandma" from the "Weight" template
    Then the answer is 201
    And it is called "Weight"
    And it reads as active
    And it collects "Weight" as a number in "lb" expected between 80 and 400
    And it has never been logged
    And it has 0 schedules
    When "Sam" opens the trackers of "Grandma"
    Then the trackers listed are "Weight"

  # PRD: Trackers (a field the template brought can be dropped before the tracker is created)
  # PRD: Definitions → Tracker template (everything it brought can be changed before the tracker is created)
  Scenario: A field the template brought is dropped before creating
    When "Alex" adds a tracker to "Grandma" from the "Doctor Appointment" template without its "Specialty" field
    Then the answer is 201
    And it collects "Doctor", "Location", "Reason", "Outcome" and "Follow-up"

  # PRD: Definitions → Tracker template (a shower arrives with no fields at all and a gap of a few days)
  # PRD: Definitions → Threshold (a gap starts watching immediately rather than waiting for a first entry)
  Scenario: A tracker made from a gap template is watched from the moment it exists
    When "Alex" adds a tracker to "Grandma" from the "Shower" template
    Then the answer is 201
    And it is watched by a gap of 72 hours
    And it collects nothing
    And nothing about it needs attention

  # PRD: Definitions → Admin (admins manage the team's trackers)
  # PRD: Trackers → Trackers (Add new, in the header — admins only)
  Scenario: A caregiver cannot add a tracker
    When "Sam" adds a tracker to "Grandma" from the "Weight" template
    Then the answer is 403
    When "Sam" opens the trackers of "Grandma"
    Then the answer is 200
    And the list holds no trackers
