# C1-UI: Create Care Team Screen Design

**Date:** 2026-06-18
**Screen:** `CreateGroupView` (onboarding — shown when `session.state == .onboarding`)
**Spec series:** C1-UI design pass

---

## Context

First screen a new user sees after signing up and verifying their email. Sets the tone for the
app and introduces the core organizing concept. Single step — just naming the team.

---

## Terminology

The backend entity is `care_group` / `createCareGroup` and stays as-is. The UI uses **"care team"**
everywhere on this screen. A care team connects caregivers and the people they look after.

---

## Design

**Background:** `.earthBackground()` — same earthy gradient as auth screens.

**Layout (top → bottom):**

1. Logo — `Image("AppLogo")`, `scaledToFit`, `frame(height: 160)`
2. `Spacer()`
3. Heading — `"Welcome, {userName}!"` — `Theme.Typography.title`, `Theme.Colors.ink`
4. Subheading — `"Create a care team to get started. A care team connects caregivers and the people they look after."` — `Theme.Typography.subhead`, `Theme.Colors.ink.opacity(0.6)`, centered, multiline
5. `GlassField(placeholder: "Care team name", icon: "person.2", text: $model.name)`
   - `.textContentType(.organizationName)`
   - `.autocorrectionDisabled()`
6. Error text (if present) — `Theme.Typography.subhead`, `Theme.Colors.alert`
7. `PrimaryButton(title: "Create team", isLoading: model.isBusy)`
8. `Spacer()`

---

## What changes from current

| Area         | Current                                       | After                                         |
| ------------ | --------------------------------------------- | --------------------------------------------- |
| Background   | None (plain white)                            | `.earthBackground()`                          |
| Logo         | None                                          | `AppLogo` at 160pt                            |
| Welcome text | Plain `Text`                                  | `Theme.Typography.title` + `Theme.Colors.ink` |
| Subtitle     | Generic "Create a care group to get started." | Explains what a care team is                  |
| Name field   | Stock `TextField(.roundedBorder)`             | `GlassField` with person.2 icon               |
| Button text  | "Create group"                                | "Create team"                                 |
| Padding      | `Theme.Spacing.lg`                            | Same                                          |
