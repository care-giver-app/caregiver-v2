# PRD: Home → Journal note (the note; who wrote it, and the time it is about; who changed it last
#      and when, if it has been changed)
Feature: Reading a journal note
  A journal note is read on its own screen: what it says, who wrote it, the
  time it is about, and who changed it last if anyone has.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Definitions → Journal note (free-form prose with a time and an author; a note carries the
  #      time it is about rather than the time it was typed)
  Scenario: A note says who wrote it and the time it is about
    Given "Alex" wrote a journal note about "Grandma" at 15:00 1 day ago: "Granddaughter visited, mood lifted"
    When "Sam" opens that note
    Then the answer is 200
    And the note reads "Granddaughter visited, mood lifted", written by "Alex" about 15:00 1 day ago

  # PRD: Home → Journal note (who changed it last and when, if it has been changed)
  Scenario: A changed note says who changed it last
    Given "Alex" wrote a journal note about "Grandma" at 15:00 1 day ago: "Evenings seem foggy"
    And "Sam" changed that note 3 hours ago
    When "Alex" opens that note
    Then the answer is 200
    And the note reads "Evenings seem foggy", written by "Alex" about 15:00 1 day ago
    And the note was last changed by "Sam" 3 hours ago

  # PRD: Definitions → Care team (a shared space containing one or more care receivers and the
  #      caregivers who look after them)
  # Contract: GET /v1/journal-notes/{noteId} answers 403 to a caller not on the team
  Scenario: Someone not on the care team cannot read a note
    Given "Alex" wrote a journal note about "Grandma" at 15:00 1 day ago: "Rough night"
    When "Riley" opens that note
    Then the answer is 403
