# PRD: Home → Home (what needs attention: at most three, ordered unrecorded care first, then
#      readings outside their range, then trackers past their gap, and never more than one for a
#      tracker — the one that matters most, then the most recent)
Feature: What needs attention on Home
  Home shows a care receiver's trackers only when something is wrong with
  them: care gone unrecorded, a reading outside its range, or a tracker past
  its gap. Unrecorded care leads, then readings, then gaps; at most three
  show, and never more than one for a tracker.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" is already a caregiver on "Riverside"
    And "Riverside" looks after "Grandma"

  # PRD: Home (ordered by how much it matters: unrecorded care first, then readings outside their
  #      range, then trackers past their gap)
  Scenario: Unrecorded care comes first, then a reading out of range, then a gap
    Given "Grandma" has a tracker "Shower"
    And "Shower" is watched by a gap of 72 hours
    And "Shower" was created 4 days ago
    And "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Sam" logged "Blood pressure" 2 hours ago with "Systolic" at 165
    And "Grandma" has a tracker "Medication"
    And "Medication" was due 5 hours ago and nobody has logged it
    When "Sam" looks at what needs attention for "Grandma"
    Then the answer is 200
    And needs attention lists, in this order:
      | tracker        | kind         | when         |
      | Medication     | unrecorded   | 5 hours ago  |
      | Blood pressure | out of range |              |
      | Shower         | gap          | 4 days ago   |
    And needs attention says "Systolic" on "Blood pressure" read 165, outside 90 to 140

  # PRD: Home (Home shows at most three at a time … the rest are not lost)
  Scenario: At most three show, and what matters least is the one left out
    Given "Grandma" has a tracker "Medication"
    And "Medication" was due 3 hours ago and nobody has logged it
    And "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Sam" logged "Blood pressure" 2 hours ago with "Systolic" at 165
    And "Grandma" has a tracker "Weight"
    And "Weight" has a number field "Pounds" expected between 100 and 160
    And "Sam" logged "Weight" 1 day ago with "Pounds" at 171
    And "Grandma" has a tracker "Shower"
    And "Shower" is watched by a gap of 72 hours
    And "Shower" was created 4 days ago
    When "Sam" looks at what needs attention for "Grandma"
    Then the answer is 200
    And needs attention names "Medication", "Blood pressure" and "Weight" and not "Shower"

  # PRD: Home (never more than one for a tracker … the evening dose nobody recorded rather than the
  #      morning one before it)
  Scenario: A dose missed twice in a day shows once, for the later dose
    Given "Grandma" has a tracker "Medication"
    And "Medication" was due 11 hours ago and nobody has logged it
    And "Medication" was due 1 hour ago and nobody has logged it
    When "Sam" looks at what needs attention for "Grandma"
    Then the answer is 200
    And needs attention lists, in this order:
      | tracker    | kind       | when       |
      | Medication | unrecorded | 1 hour ago |

  # PRD: Home (a tracker with more than one thing wrong shows the one that matters most by that
  #      same order)
  Scenario: A tracker with unrecorded care and a high reading shows the unrecorded care
    Given "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Sam" logged "Blood pressure" 1 hour ago with "Systolic" at 165
    And "Blood pressure" was due 4 hours ago and nobody has logged it
    When "Sam" looks at what needs attention for "Grandma"
    Then the answer is 200
    And needs attention lists, in this order:
      | tracker        | kind       | when        |
      | Blood pressure | unrecorded | 4 hours ago |

  # PRD: Home (an unrecorded occurrence leaves needs attention forty-eight hours after its scheduled
  #      time … still unrecorded, still in its day's timeline)
  Scenario: Unrecorded care leaves needs attention after forty-eight hours but stays in its day
    Given "Grandma" has a tracker "Medication"
    And "Medication" was due 49 hours ago and nobody has logged it
    When "Sam" looks at what needs attention for "Grandma"
    Then the answer is 200
    And nothing needs attention on Home
    When "Sam" opens the timeline of "Grandma" for the day of 49 hours ago
    Then the timeline holds, in time order:
      | when         | item                   | by |
      | 49 hours ago | Medication, unrecorded |    |

  # PRD: Definitions → Tracker (pausing: its thresholds stop raising alerts, and it leaves Home)
  Scenario: A paused tracker contributes nothing
    Given "Grandma" has a tracker "Shower"
    And "Shower" is watched by a gap of 72 hours
    And "Shower" was created 10 days ago
    And "Shower" was paused 1 day ago
    And "Grandma" has a tracker "Medication"
    And "Medication" was due 3 hours ago and nobody has logged it
    And "Medication" was paused 1 hour ago
    When "Sam" looks at what needs attention for "Grandma"
    Then the answer is 200
    And nothing needs attention on Home

  # PRD: Home (when nothing needs attention, Home says so plainly; a skipped entry never returns to it)
  # PRD: Home → Home (empty: nothing needs attention)
  Scenario: Nothing wrong leaves needs attention empty
    Given "Grandma" has a tracker "Blood pressure"
    And "Blood pressure" has a number field "Systolic" expected between 90 and 140
    And "Sam" logged "Blood pressure" 2 hours ago with "Systolic" at 128
    And "Grandma" has a tracker "Medication"
    And "Medication" has these entries:
      | state     | when             | by  |
      | skipped   | 3 hours ago      | Sam |
      | logged    | 1 day ago        | Sam |
      | scheduled | 5 hours from now |     |
    When "Sam" looks at what needs attention for "Grandma"
    Then the answer is 200
    And nothing needs attention on Home
