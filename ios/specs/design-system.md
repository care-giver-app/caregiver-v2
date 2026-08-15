# Stride design system — component catalog

A quick-reference guide to the SwiftUI components in `ios/Caregiver/DesignSystem/`. Use this when
laying out a new view to see what's already available before building something new. Purely a
catalog of what each component is for — no implementation detail here; read the component's source
for that.

## Buttons & actions

| Component      | Used for                                                                          |
| -------------- | --------------------------------------------------------------------------------- |
| `StrideButton` | The primary tappable action on a screen (continue, save, confirm, retry).         |
| `StrideChip`   | A small selectable pill for filters or single-choice pickers (e.g. role, status). |
| `StrideBadge`  | A short status label (Due, Missed, Logged, You…) tucked into a row or card.       |

## Inputs & forms

| Component           | Used for                                                          |
| ------------------- | ----------------------------------------------------------------- |
| `StrideField`       | A single-line text or secure entry field (email, name, password). |
| `StrideCodeInput`   | A 6-digit confirmation/verification code entry.                   |
| `StrideDatePicker`  | Picking a date and/or time.                                       |
| `StrideToggleStyle` | The on/off switch look for a system `Toggle`.                     |

## Cards & list rows

| Component              | Used for                                                                               |
| ---------------------- | -------------------------------------------------------------------------------------- |
| `strideCard()`         | Generic card background/border treatment for wrapping arbitrary content.               |
| `StrideTrackerRow`     | A tracker's full-width list row (Trackers screen).                                     |
| `StrideTrackerTile`    | A compact tracker snapshot cell for a two-column grid (Home).                          |
| `StrideMemberRow`      | A row in the Team roster — an active member or a pending invite.                       |
| `StrideReceiverRow`    | A care-receiver row in the switch/add-receiver sheets.                                 |
| `StrideSettingsRow`    | A row in a Settings list, with a chevron/check/value/toggle trailing accessory.        |
| `StrideInsightCard`    | An Insights overview card for one tracker — count, latest value, and a mini sparkline. |
| `StrideStatCard`       | A compact single-stat card (label, value, optional delta) for stat strips.             |
| `StrideInviteCard`     | The pending-invite share card showing the invite code and a share action.              |
| `StrideTemplateCard`   | A tracker-template picker card in the add-tracker wizard grid.                         |
| `StrideSelectTile`     | A selectable tile in a picker grid (e.g. choosing a tracker to log).                   |
| `StrideComingUpBanner` | A tappable banner surfacing the single soonest upcoming scheduled item.                |

## Navigation & structure

| Component                 | Used for                                                                             |
| ------------------------- | ------------------------------------------------------------------------------------ |
| `StrideTabBar`            | The app's bottom tab bar (Home/Insights/Team/Settings) with a quick-log FAB.         |
| `StrideSectionHeader`     | A section label above a group of content, with an optional "See all" action.         |
| `StrideStepDots`          | Step progress dots for a multi-step wizard.                                          |
| `StrideTimeframeSelector` | A segmented control for choosing an analytics timeframe (Week/Month/3M/Year/Custom). |

## Feedback & state

| Component           | Used for                                                         |
| ------------------- | ---------------------------------------------------------------- |
| `StrideDialog`      | A modal confirm/alert dialog with a title, message, and actions. |
| `StrideLoadingView` | A full-space loading spinner placeholder.                        |
| `StrideEmptyState`  | A full-space "nothing here" placeholder message.                 |
| `StrideErrorState`  | A full-space error message with a retry action.                  |

## Data visualization

| Component            | Used for                                                                |
| -------------------- | ----------------------------------------------------------------------- |
| `StrideLineChart`    | A value-over-time line chart with one or more named series (e.g. BP).   |
| `StrideScatterChart` | An hour-of-day-by-date scatter plot (e.g. medication adherence timing). |
| `StrideBarChart`     | A count-per-time-bucket bar chart (e.g. weekly log counts).             |
| `StrideTimeline`     | A vertical event timeline with time, title, and description per node.   |

## Brand & backgrounds

| Component                | Used for                                           |
| ------------------------ | -------------------------------------------------- |
| `StrideBrand`            | The app logo mark.                                 |
| `strideAuthBackground()` | The gradient background behind auth screens.       |
| `strideBackground()`     | The gradient background behind post-login screens. |
