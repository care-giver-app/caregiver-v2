# PRD: Definitions → Journal note (every caregiver writes journal notes, and any caregiver can edit
#      or delete any of them; a note carries the time it is about rather than the time it was typed)
Feature: Writing, editing and deleting a journal note
  A journal note is about a time that has already come, and sits in that
  day's timeline. Any caregiver can rewrite or delete any note; the note
  keeps its author and says who changed it last.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Definitions → Journal note (they sit in the daily timeline in time order among the entries
  #      logged that day; a caregiver writing up Tuesday on Wednesday morning puts it where it belongs)
  Scenario: A note sits in the day it is about
    When "Sam" writes a journal note about "Grandma" as of 15:00 1 day ago: "Granddaughter visited, mood lifted"
    Then the answer is 201
    When "Alex" opens the timeline of "Grandma" for 1 day ago
    Then the timeline holds, in time order:
      | when             | item                                         | by  |
      | 15:00 1 day ago  | a note: "Granddaughter visited, mood lifted" | Sam |

  # PRD: Home (Journal notes cannot be planned … there is nothing yet to say about a day that has not
  #      happened)
  Scenario: A note cannot be about a time still to come
    When "Sam" writes a journal note about "Grandma" as of 2 hours from now: "Will be tired after the trip"
    Then the answer is 400

  # PRD: Definitions → Journal note (a note records who wrote it and, if it has since been changed,
  #      who changed it last and when)
  # PRD: Home → Journal note (who wrote it, and the time it is about; who changed it last and when)
  Scenario: Another caregiver rewrites a note, which keeps its author and says who changed it
    Given "Alex" writes a journal note about "Grandma" as of 15:00 1 day ago: "Evenings seem foggy"
    When "Sam" edits that note to read "Evenings seem foggy since the new pills"
    Then the answer is 200
    When "Alex" opens that note
    Then the note reads "Evenings seem foggy since the new pills", written by "Alex" about 15:00 1 day ago
    And the note was last changed by "Sam"

  # PRD: Home → Delete this note? (that the note will be gone)
  Scenario: Another caregiver deletes a note, and it is gone from its day
    Given "Alex" writes a journal note about "Grandma" as of 15:00 1 day ago: "Rough night"
    When "Sam" deletes that note
    Then the answer is 204
    When "Alex" opens that note
    Then the answer is 404
    When "Alex" opens the timeline of "Grandma" for 1 day ago
    Then the timeline is empty
