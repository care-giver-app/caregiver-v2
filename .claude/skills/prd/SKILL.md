---
name: prd
description: Use when working on docs/PRD.md or docs/PRDWorkspace.md — refining a workspace idea, merging one into the PRD, writing or changing a definition or UX flow, or recording a gap or open question.
---

# PRD work

## Overview

Two documents, one loop. `docs/PRD.md` is the authority on what the product is — when it and the
built app disagree, the app is what changes. `docs/PRDWorkspace.md` is the staging area where ideas
land raw, get refined, and then leave.

**An idea moves in one direction: workspace → refined → checked against the PRD → merged → deleted
from the workspace.** The workspace file states that last step about itself, and it is the step most
easily forgotten.

## The loop

1. **Read both documents first.** Not the workspace note alone — the idea's neighbors in the PRD
   decide half of what it should say.
2. **Pressure-test the idea against the PRD** (below). Report the findings before drafting anything.
3. **Ask the refining questions** — one per message, highest-leverage first.
4. **Draft in the PRD's voice and present it in chat.** Write no file until Trevor approves the
   draft.
5. **Merge**, then clear the merged idea out of the workspace.

## Pressure-test the idea

A workspace note is one person thinking out loud. The job is to find what it collides with. Grep the
PRD for the idea's nouns, read the definitions on either side of where it would land, and report:

- **Contradiction** — does this conflict with something already settled? A new rule about who may do
  what is the usual offender.
- **Forced cross-references** — which existing text must change if this lands? _Admin_'s list of
  what admins manage, _Care receiver_, and the flow diagrams are the ones that keep coming up.
- **Vocabulary drift** — does it introduce a second word for something the PRD already names? The
  vocabulary is deliberate (_entry_, not _event_; _care team_, not _group_). A new term needs a
  reason.
- **Altitude** — does it reach into screens' internals, endpoints, files, or data shapes? Those
  never enter the PRD.
- **Unstated consequences** — who writes it and who reads it, what becomes of it when its care
  receiver or team goes away, and whether it appears in timelines, insights, or notifications.
- **Reachability** — if a caregiver is meant to see it, which flow gets them there? If none does,
  that is a gap bullet, not silence.

Say plainly which findings block the merge and which should be recorded and merged anyway. Trevor
decides. Never resolve a contradiction by quietly picking a side.

## Refining questions

One per message. The ladder that works, in order:

1. **Shape** — what _is_ this thing? A document, a list, a structured record?
2. **The part that cannot be prose** — what must a caregiver act on (call, tap, be reminded by) that
   has to be real fields rather than sentences?
3. **The rule that makes it trustworthy** — how does a caregiver know it is current, correct, or
   theirs to act on?

For a flow rather than a definition, the same ladder reads:

1. **Scope** — what is this screen about, and what reloads when that changes?
2. **What is on it** — which goals earn a place, and what carries the screen's stated purpose. Name
   what the goals silently drop; a note that says "forget what we have" is not a decision to drop
   the things it forgot to mention.
3. **What clears it** — when does something leave the screen? A screen that only accumulates stops
   being read.

Offer concrete options with previews rather than open-ended prompts. YAGNI hard: the simplest shape
that survives the questions wins.

## What a definition is

Prose, never bullets. In order:

1. **The term in bold, an em dash, and what it is** — one sentence a caregiver would recognize.
2. **A concrete example or two** from the real domain — pills with food, the walker past the
   kitchen.
3. **The rule that bites** — the constraint someone would otherwise get wrong.
4. **The "because" clause.** Every definition in this PRD says _why_ it works the way it does. One
   without a because is unfinished.
5. **Ownership and edges** — who may change it, and what it deliberately is not.

Multiple paragraphs are normal; see _Invitation_, _Assignment_, _Entry_. Wrap prose by hand at 100
columns.

## What a flow section is

Same voice, different parts. In order:

1. **One sentence naming the question the screen answers**, and what it is scoped to.
2. **Prose for the reasoning**, before any diagram — why the screen is built this way. The
   "because" clause lives here.
3. **A mermaid `flowchart`** — one box per screen listing its contents, one labelled arrow per
   action that leaves it, and `classDef handoff` for boxes that belong to another section.
4. **A line separating sheets from pushed screens**, and a line for what stays put rather than
   navigating.
5. **`#### Gaps in this flow`** — each a bold lead sentence, then the explanation.

Every arrow needs a destination that exists somewhere in the PRD. When a rewrite creates a box
nothing describes yet, shade it as a handoff and say plainly that the rewrite created that
obligation. Flow sections are edited in place; they are never appended to.

## Merging

- **Placement** — put it where it reads in sequence, not at the end. The definitions run people →
  coordination → receiver reference → tracking → notification → insight.
- **Update every cross-reference** the pressure-test turned up, in the same pass.
- **Give unresolved things a home.** A hole in one flow becomes a bullet under that flow's _Gaps in
  this flow_ — bold lead sentence, then the explanation. A decision with real trade-offs becomes a
  numbered _Open question_ stating what is likely and what is still open.
- **Rewrite the gaps the change resolves.** A merge that answers an existing gap must narrow,
  reword, or delete that bullet in the same pass. A gap left standing beside the text that answers
  it is worse than no gap at all.
- **Clear the workspace** of the merged idea, leaving the file and its headings intact.
- **Run** `pnpm exec prettier --write` on both files.
- **Never commit** unless asked. These files may be untracked; that is fine.

## Quick reference

| Situation                          | Where it goes                                |
| ---------------------------------- | -------------------------------------------- |
| A new concept the product needs    | A definition, placed in sequence             |
| A path nobody has thought through  | _Gaps in this flow_, under the affected flow |
| A decision with real trade-offs    | A numbered _Open question_                   |
| Screen internals, endpoints, files | Nowhere — below the PRD's altitude           |
| An idea that survived the merge    | Deleted from the workspace                   |
| A screen's contents and exits      | Its flow section, rewritten in place         |

## Common mistakes

- Drafting before pressure-testing, so the cross-reference surfaces after the merge instead of
  before it.
- Writing bullets where the document writes prose.
- Dropping the "because" clause, leaving a rule with no reasoning behind it.
- Merging and leaving the idea sitting in the workspace.
- Leaving a gap bullet standing after the merge answered it.
- Resolving an ambiguity silently instead of naming it and asking.
