# PRD: Team → Team notification settings (which kinds of reminder and alert this team should send
#      you — chosen by kind for the whole team, not tracker by tracker)
# PRD: Definitions → Notification (What they want to be told about … belongs to each care team
#      separately)
Feature: What a care team tells a caregiver about
  Each caregiver chooses, team by team and kind by kind, which reminders and
  alerts a care team sends them. The choice is theirs alone.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" has joined "Riverside" as a caregiver

  # PRD: Team → Team notification settings (one care team, for the signed-in caregiver)
  Scenario: Turning reminders off changes only that caregiver's choice
    Given "Alex" has turned on reminders for "Riverside"
    And "Sam" has turned on reminders for "Riverside"
    When "Sam" turns off reminders for "Riverside"
    Then the answer is 200
    And "Sam" does not get reminders from "Riverside"
    And "Alex" gets reminders from "Riverside"

  # PRD: Team → Team notification settings (chosen by kind)
  Scenario: Turning one kind off leaves the other kinds as they were
    Given "Sam" has turned on gap alerts for "Riverside"
    And "Sam" has turned on unrecorded-care alerts for "Riverside"
    When "Sam" turns off out-of-range alerts for "Riverside"
    Then the answer is 200
    And "Sam" does not get out-of-range alerts from "Riverside"
    And "Sam" gets gap alerts from "Riverside"
    And "Sam" gets unrecorded-care alerts from "Riverside"

  # PRD: Team (this holds the subject matter, team by team, because … how involved they are does
  #      [change from one family to the next])
  Scenario: A choice for one care team leaves the caregiver's other teams as they were
    Given "Jordan" has created the care team "Lakeside"
    And "Sam" has joined "Lakeside" as a caregiver
    And "Sam" has turned on reminders for "Lakeside"
    When "Sam" turns off reminders for "Riverside"
    Then the answer is 200
    And "Sam" does not get reminders from "Riverside"
    And "Sam" gets reminders from "Lakeside"
