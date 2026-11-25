# PRD: Settings (Changing an address asks for the current password first … The code goes to the new
#      address, and the change is not finished until it is entered)
# PRD: Settings → Change email
Feature: Changing the address an account signs in with
  The current password comes first, a code goes to the new address, and the
  old address stays the account's until the code is entered. The sheet says
  plainly what went wrong.

  # PRD: Settings → Change email (Confirm → Settings)
  # PRD: Settings (the change is not finished until it is entered)
  @inprocess
  Scenario: The address changes only once the code is entered
    Given "Sam" signs in
    When "Sam" asks to change their email to a new address with their password
    Then the answer is 204
    And "Sam"'s account shows their old address
    When "Sam" enters the code sent to the new address
    Then "Sam"'s account shows their new address

  # PRD: Settings → Change email (Send code, with a current password that is not right → saying the
  #      password is not right)
  Scenario: A wrong current password is named as such
    Given "Sam" signs in
    When "Sam" asks to change their email to a new address with a wrong password
    Then the answer is 403 saying "the password is not right"
    And "Sam"'s account shows their old address

  # PRD: Settings → Change email (Send code, with an address another account already uses → saying
  #      that address is already in use)
  Scenario: An address another account uses is refused
    Given "Jordan" signs in
    And "Sam" signs in
    When "Sam" asks to change their email to "Jordan"'s address with their password
    Then the answer is 409 saying "already uses that address"
    And "Sam"'s account shows their old address

  # PRD: Settings → Change email (Send code, after too many wrong passwords in a short time → saying
  #      to try again later)
  @inprocess
  Scenario: Too many wrong passwords ask the caregiver to try again later
    Given "Sam" signs in
    And "Sam" has tried a wrong password 5 times
    When "Sam" asks to change their email to a new address with their password
    Then the answer is 429 saying "try again later"
