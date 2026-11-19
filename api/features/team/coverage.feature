# PRD: Definitions → Assignment
# PRD: Definitions → Coverage schedule
# PRD: Team → Care receiver (who is on duty; the assignments ahead; the coverage schedules behind
#      them, in a separate labelled group), An assignment, A coverage schedule,
#      Remove this coverage schedule?
Feature: Who covers a care receiver, and when
  Assignments say who is responsible for a care receiver and when, so two
  caregivers don't both drive over. A coverage schedule is the rule behind a
  rotation; a single assignment it made can be handed off without touching
  the rule. Coverage is optional, and admins manage it.

  Background:
    Given "Alex" has created the care team "Riverside"
    And "Sam" has joined "Riverside" as a caregiver
    And "Jordan" has joined "Riverside" as a caregiver
    And "Riverside" looks after "Grandma"

  # PRD: Definitions → Assignment (Coverage is optional … a team that keeps none simply has no
  #      assignments, and nothing else in the app changes)
  # PRD: Home (a team that keeps no assignments simply sees nothing there)
  Scenario: A team that keeps no roster has nobody on duty and nothing ahead
    When "Sam" opens who is on duty for "Grandma"
    Then the answer is 200
    And nobody is listed
    When "Sam" opens the assignments ahead of "Grandma"
    Then the answer is 200
    And nobody is listed
    When "Sam" opens the coverage schedules of "Grandma"
    Then the answer is 200
    And no coverage schedules are listed

  # PRD: Definitions → Assignment (Assignments can overlap, since a family member and a paid aide are
  #      often present together)
  # PRD: Home (Home also names who is on duty for this receiver right now)
  Scenario: Everyone whose assignment covers this moment is on duty, overlaps and all
    Given "Alex" assigns "Sam" to "Grandma" from 1 hour ago for 3 hours
    And "Alex" assigns "Jordan" to "Grandma" from 2 hours ago for 4 hours
    And "Alex" assigns "Alex" to "Grandma" from 2 days from now for 8 hours
    When "Sam" opens who is on duty for "Grandma"
    Then the answer is 200
    And on duty are "Sam" and "Jordan"

  # PRD: Team → Care receiver (the assignments ahead)
  # Contract: GET /v1/receivers/{receiverId}/assignments lists them soonest first
  Scenario: The assignments ahead are listed soonest first
    Given "Alex" assigns "Jordan" to "Grandma" from 3 days from now for 8 hours
    And "Alex" assigns "Sam" to "Grandma" from 1 day from now for 8 hours
    And "Alex" assigns "Alex" to "Grandma" from 1 hour ago for 2 hours
    When "Sam" opens the assignments ahead of "Grandma"
    Then the answer is 200
    And the assignments are by "Alex", "Sam" and "Jordan", soonest first

  # PRD: Definitions → Assignment (Admins manage the roster — creating, changing, and reassigning a
  #      team's assignments)
  # PRD: Team → An assignment (the caregiver; when it runs; hand it to someone else; remove it)
  Scenario: An admin adds an assignment, hands it to someone else, and removes it
    When "Alex" assigns "Sam" to "Grandma" tomorrow from 08:00 to 16:00
    Then the answer is 201
    When "Jordan" opens the assignments ahead of "Grandma"
    Then "Sam" is assigned tomorrow from 08:00 to 16:00
    When "Alex" hands "Sam"'s assignment to "Jordan"
    Then the answer is 200
    When "Jordan" opens the assignments ahead of "Grandma"
    Then "Jordan" is assigned tomorrow from 08:00 to 16:00
    And "Sam" is not assigned tomorrow
    When "Alex" removes "Jordan"'s assignment
    Then the answer is 204
    When "Sam" opens the assignments ahead of "Grandma"
    Then nobody is listed

  # PRD: Team → Care receiver (The Tuesdays already past stay either way: they say who was
  #      responsible, and this week's decision does not get to rewrite that)
  # Contract: changeAssignment and removeAssignment answer 409 AssignmentEnded
  Scenario: An assignment that has ended cannot be handed off or removed
    Given "Sam" was on duty for "Grandma" from 10 hours ago for 2 hours
    When "Alex" hands "Sam"'s assignment to "Jordan"
    Then the answer is 409
    When "Alex" removes "Sam"'s assignment
    Then the answer is 409

  # PRD: Definitions → Coverage schedule (A recurring rule that generates assignments, such as
  #      "Trevor, every Tuesday 8am–4pm")
  # PRD: Team → Care receiver (the coverage schedules behind them, in a separate labelled group)
  Scenario: A coverage schedule makes its assignments ahead
    When "Alex" schedules "Sam" to cover "Grandma" every day from 08:00 to 16:00
    Then the answer is 201
    When "Jordan" opens the assignments ahead of "Grandma"
    Then "Sam" is assigned tomorrow from 08:00 to 16:00
    And "Sam" is assigned in 7 days from 08:00 to 16:00
    And "Sam"'s assignment tomorrow belongs to a coverage schedule
    When "Jordan" opens the coverage schedules of "Grandma"
    Then the answer is 200
    And the coverage schedules listed are for "Sam"

  # PRD: Team → A coverage schedule (the days and the hours)
  # Contract: CoverageSchedule.end_time (earlier than start_time means it runs past midnight)
  Scenario: A night shift runs past midnight
    When "Alex" schedules "Sam" to cover "Grandma" every day from 22:00 to 06:00
    Then the answer is 201
    When "Jordan" opens the assignments ahead of "Grandma"
    Then "Sam" is assigned tomorrow from 22:00 to 06:00 the next day

  # PRD: Definitions → Coverage schedule (A schedule can end on a set date, so a temporary
  #      arrangement stops on its own)
  # PRD: Team → A coverage schedule (when it ends, if it ends)
  Scenario: A coverage schedule with an end date stops on its own
    When "Alex" schedules "Sam" to cover "Grandma" every day from 08:00 to 16:00 until in 3 days
    Then the answer is 201
    When "Jordan" opens the coverage schedules of "Grandma"
    Then "Sam"'s coverage schedule ends in 3 days
    When "Jordan" opens the assignments ahead of "Grandma"
    Then "Sam" is assigned tomorrow from 08:00 to 16:00
    And "Sam" is not assigned in 4 days
    And "Sam" is not assigned in 5 days

  # PRD: Definitions → Coverage schedule (A single generated assignment can be handed to another
  #      caregiver without touching the rule behind it … An assignment changed that way belongs to
  #      no rule afterward)
  # PRD: Team → An assignment (Save, hand to someone else, or remove → Care receiver, with the rule
  #      that generated it untouched)
  Scenario: Handing one generated assignment to someone else leaves the rule alone
    Given "Alex" schedules "Sam" to cover "Grandma" every day from 08:00 to 16:00
    When "Alex" hands "Sam"'s assignment tomorrow on "Grandma" to "Jordan"
    Then the answer is 200
    When "Sam" opens the assignments ahead of "Grandma"
    Then "Jordan" is assigned tomorrow from 08:00 to 16:00
    And "Jordan"'s assignment tomorrow does not belong to a coverage schedule
    And "Sam" is not assigned tomorrow
    And "Sam" is assigned in 2 days from 08:00 to 16:00
    When "Sam" opens the coverage schedules of "Grandma"
    Then the coverage schedules listed are for "Sam"

  # PRD: Team → Care receiver (dropping a single Thursday loses nothing but that Thursday)
  # PRD: Team → An assignment (remove → Care receiver, with the rule that generated it untouched)
  Scenario: Removing one generated assignment drops only that one
    Given "Alex" schedules "Sam" to cover "Grandma" every day from 08:00 to 16:00
    When "Alex" removes "Sam"'s assignment tomorrow on "Grandma"
    Then the answer is 204
    When "Jordan" opens the assignments ahead of "Grandma"
    Then "Sam" is not assigned tomorrow
    And "Sam" is assigned in 2 days from 08:00 to 16:00
    When "Jordan" opens the coverage schedules of "Grandma"
    Then the coverage schedules listed are for "Sam"

  # PRD: Definitions → Coverage schedule (Changing the rule later — a later start, a different day —
  #      redraws the assignments still ahead of it, except any that someone already changed by
  #      hand: the Tuesday somebody agreed to cover stays theirs)
  Scenario: Changing a rule redraws what is ahead but keeps the day someone agreed to cover
    Given "Alex" schedules "Sam" to cover "Grandma" every day from 08:00 to 16:00
    And "Alex" hands "Sam"'s assignment tomorrow on "Grandma" to "Jordan"
    When "Alex" changes "Sam"'s coverage schedule to every day from 09:00 to 17:00
    Then the answer is 200
    When "Sam" opens the assignments ahead of "Grandma"
    Then "Jordan" is assigned tomorrow from 08:00 to 16:00
    And "Sam" is not assigned tomorrow
    And "Sam" is assigned in 2 days from 09:00 to 17:00

  # PRD: Definitions → Coverage schedule (removing one stops the future without rewriting the past
  #      … the ones still ahead go with the rule … An assignment changed that way belongs to no
  #      rule afterward, and stays or goes on its own)
  # PRD: Team → Remove this coverage schedule? (what goes — the rule, and every assignment it made
  #      that is still ahead)
  Scenario: Removing a rule takes what it made ahead and leaves the day someone agreed to cover
    Given "Alex" schedules "Sam" to cover "Grandma" every day from 08:00 to 16:00
    And "Alex" hands "Sam"'s assignment tomorrow on "Grandma" to "Jordan"
    When "Alex" removes "Sam"'s coverage schedule
    Then the answer is 204
    When "Sam" opens the assignments ahead of "Grandma"
    Then "Jordan" is assigned tomorrow from 08:00 to 16:00
    And "Sam" is not assigned in 2 days
    When "Sam" opens the coverage schedules of "Grandma"
    Then no coverage schedules are listed

  # PRD: Definitions → Assignment (Admins manage the roster)
  # PRD: Team → Care receiver (an assignment, or add one — admin; a coverage schedule, or add one —
  #      admin)
  Scenario: A caregiver who is not an admin cannot change the roster
    Given "Alex" assigns "Jordan" to "Grandma" tomorrow from 08:00 to 16:00
    And "Alex" schedules "Jordan" to cover "Grandma" every day from 18:00 to 20:00
    When "Sam" assigns "Sam" to "Grandma" tomorrow from 08:00 to 16:00
    Then the answer is 403
    When "Sam" hands "Jordan"'s assignment to "Sam"
    Then the answer is 403
    When "Sam" removes "Jordan"'s assignment
    Then the answer is 403
    When "Sam" schedules "Sam" to cover "Grandma" every day from 08:00 to 16:00
    Then the answer is 403
    When "Sam" changes "Jordan"'s coverage schedule to every day from 09:00 to 17:00
    Then the answer is 403
    When "Sam" removes "Jordan"'s coverage schedule
    Then the answer is 403

  # PRD: Definitions → Care team (Their place on the roster goes with the access: the assignments
  #      still ahead of them are removed, one they are partway through ends the moment they go, and
  #      any coverage schedule that names them ends that day)
  # PRD: Team (The assignments still ahead of them go with them, and one they are partway through
  #      ends when they do, for the same reason)
  Scenario Outline: <who> takes their place on the roster with them
    Given "Alex" schedules "Sam" to cover "Grandma" every day from 08:00 to 16:00
    And "Alex" assigns "Sam" to "Grandma" in 3 days from 18:00 to 20:00
    When "<by>" removes "Sam" from "Riverside"
    Then the answer is 204
    When "Jordan" opens the assignments ahead of "Grandma"
    Then "Sam" is not assigned tomorrow
    And "Sam" is not assigned in 3 days
    When "Jordan" opens the coverage schedules of "Grandma"
    Then "Sam"'s coverage schedule ends today

    Examples:
      | who                                    | by   |
      | A caregiver who leaves                 | Sam  |
      | A caregiver an admin removes from team | Alex |

  # PRD: Team → Care receiver (when archived, all of it unchanged but read-only)
  # Contract: every roster write answers 409 for an archived care receiver
  Scenario: An archived care receiver's roster can be read but not changed
    Given "Alex" assigns "Sam" to "Grandma" tomorrow from 08:00 to 16:00
    And "Alex" schedules "Jordan" to cover "Grandma" every day from 18:00 to 20:00
    And "Alex" archives the care receiver "Grandma"
    When "Alex" assigns "Jordan" to "Grandma" in 2 days from 08:00 to 16:00
    Then the answer is 409
    When "Alex" schedules "Jordan" to cover "Grandma" every day from 08:00 to 16:00
    Then the answer is 409
    When "Alex" hands "Sam"'s assignment to "Jordan"
    Then the answer is 409
    When "Alex" removes "Sam"'s assignment
    Then the answer is 409
    When "Alex" changes "Jordan"'s coverage schedule to every day from 09:00 to 17:00
    Then the answer is 409
    When "Alex" removes "Jordan"'s coverage schedule
    Then the answer is 409
    When "Jordan" opens the assignments ahead of "Grandma"
    Then the answer is 200
    And "Sam" is assigned tomorrow from 08:00 to 16:00
    When "Jordan" opens who is on duty for "Grandma"
    Then the answer is 200
    When "Jordan" opens the coverage schedules of "Grandma"
    Then the answer is 200

  # PRD: Definitions → Care receiver (If a receiver's time zone changes … their routines keep their
  #      wall-clock times and shift with them)
  # PRD: Team → Edit care receiver (time zone — changing it keeps the receiver's routines at their
  #      wall-clock times and shifts them along)
  Scenario: Moving a care receiver keeps their assignments at the same wall-clock time
    Given "Alex" assigns "Sam" to "Grandma" in 2 days from 08:00 to 16:00
    When "Alex" moves the care receiver "Grandma" to the time zone "Europe/London"
    Then the answer is 200
    When "Jordan" opens the assignments ahead of "Grandma"
    Then "Sam" is assigned in 2 days from 08:00 to 16:00
    And "Sam"'s assignment in 2 days starts at 08:00 in "Europe/London"
