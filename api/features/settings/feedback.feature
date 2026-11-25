# PRD: Settings (About this app holds … Send feedback; It goes with their account … A switch sends it
#      anonymously instead, and anonymous means what it says)
# PRD: Settings → Send feedback
Feature: Sending feedback
  A report goes with the caregiver's account so a reply can come by email,
  unless it is sent anonymously, when nothing that identifies them goes with
  it. The version and device go either way.

  # PRD: Settings → Send feedback (Send → saying it was sent, and that any reply will come by email)
  @inprocess
  Scenario: Feedback goes with the caregiver's name and address
    Given "Sam" signs in
    When "Sam" sends a bug report reading "The chart is blank after logging"
    Then the answer is 202
    And the people behind the app receive "The chart is blank after logging" as a bug report
    And it goes with "Sam"'s name and address
    And it goes with the app's version and the device

  # PRD: Settings → Send feedback (send anonymously … nothing that identifies the caregiver goes with
  #      it — not their account, their name, or their address; the app's version and the device, which
  #      go either way)
  @inprocess
  Scenario: Anonymous feedback carries nothing that identifies the caregiver
    Given "Sam" signs in
    When "Sam" sends a suggestion reading "A dark mode, please" anonymously
    Then the answer is 202
    And the people behind the app receive "A dark mode, please" as a suggestion
    And nothing that identifies "Sam" goes with it
    And it goes with the app's version and the device

  # PRD: Settings → Send feedback (the message)
  Scenario: Feedback with no message is not sent
    Given "Sam" signs in
    When "Sam" sends feedback with no message
    Then the answer is 400
