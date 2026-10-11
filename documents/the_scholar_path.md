# Hearken: The Scholar Path

Design version 1 — 10 October 2026. Deliverables are a progression specification, machine-readable rules, a standalone Swift evaluator, five vector badges, transparent PNG exports, and a badge preview. These files are not yet integrated into the app.

## Meaning and scope

Each subject has its own XP ledger and earned rank: Novice → Apprentice → Investigator → Scholar → Sage. Enrollment begins at Novice; completing the first qualifying learning item earns the Novice badge. Each subsequent badge requires both XP and published learning milestones. A Sage badge means completion of Hearken's structured learning path in that subject; it is not an academic credential or a claim of exhaustive expertise.

The same progression rules apply to every subject, while objectives, sources and assessments vary. Account XP can summarize activity across subjects but cannot unlock a subject rank. Earned ranks never decrease. A separate recall indicator recommends spaced review without changing an earned badge.

## Advancement requirements

| Rank earned | Cumulative subject XP | Requirements |
| --- | ---: | --- |
| Novice | No threshold | Enrollment sets the rank; first completed learning item earns the badge |
| Apprentice | 500 | Stage 1 complete: two foundation courses, both course checkpoints, advancement check |
| Investigator | 1,500 | Stages 1–2 complete: two exploration courses in stage 2, both checkpoints, advancement check |
| Scholar | 3,000 | Stages 1–3 complete: two comparison/evaluation courses in stage 3, both checkpoints, advancement check |
| Sage | 5,000 | Stages 1–4 complete: two synthesis courses in stage 4, both checkpoints, advancement check and assessed capstone |

For every stage, complete all items labeled Required. Optional material is available early but cannot substitute for requirements. Advancement checks require 80%; course checkpoints require 80%. For a 10-question check, eight must be correct. Checks use objective knowledge, source identification and application, not assent to a religious or philosophical position. Retakes are unlimited, with explanations and targeted practice; use fresh equivalent questions where possible. No penalties, paid attempts or arbitrary waiting periods.

The four advancement checks are gates and award no additional XP. Course checkpoints earn 100 XP once when passed. At least 10 well-reviewed questions should be authored for each advancement check, with a larger pool for repeat attempts. Existing five-question unit checks are practice, not automatically qualifying tier assessments.

Stage learning outcomes:

1. Foundations: define essential terms and describe the subject's central questions accurately.
2. Exploration: explain context, distinguish text from interpretation, and connect several course topics.
3. Comparison/evaluation: fairly describe competing perspectives and assess the relevance and limitations of evidence.
4. Synthesis: construct a supported explanation or argument, address a serious alternative, and disclose uncertainty.

## Course and activity structure

Subject → four stages → two required courses per stage → modules → learning items. Eight required courses comprise the initial full path. Every course publishes objectives, prerequisites, required/optional items, expected workload, attainable XP and checkpoint criteria. Course cards show a checklist and progress toward completion. References are clickable and carry attribution, tradition/perspective and rights information.

Learning items may be original articles, assigned scripture passages, primary-source excerpts, external articles, videos, practice or assessed projects. Book recommendations are resources: saving or purchasing a book awards nothing. Assign specific sections with legal access, and provide an equivalent accessible alternative when a required item needs a purchase, account or unavailable media.

YouTube items should use the official embedded player, subject to current provider requirements, rather than downloading or rehosting video. Inline media includes attribution, an external link and captions/transcript access where available. Pausing, seeking and playback speed do not reduce XP. All video learning items require a brief learning check, with an equivalent reading path when embedding or accessibility fails. Provider integration and terms have not been verified or implemented in this deliverable.

## XP schedule

| Activity | Subject XP | Completion condition |
| --- | ---: | --- |
| Original lesson or assigned article | 20 | Mark read and pass the attached brief check |
| Assigned scripture or primary-source reading | 30 | Read the defined selection and pass the attached brief check |
| Video lesson | 20 | Pass the attached check; elapsed playback alone does not qualify |
| Practice exercise | 10 | Complete the exercise's published success criteria |
| Course checkpoint | 100 | Pass at 80% or above |
| Stage 4 capstone | 200 | Meet the capstone rubric |
| Recommendation, saved link, note count or purchase | 0 | Useful tools, not evidence of learning |
| Spaced review session | 0 subject / 5 account | Complete a due review session; account review rewards capped at 20 per local calendar day |

Attached brief checks require all answers correct, allow immediate retries with feedback, and award no separate per-answer XP. They are distinct from course and advancement assessments. Browsing outside the enrolled course remains unrestricted.

Required curriculum XP budgets by stage are 500, 1,000, 1,500 and 2,000, respectively: 5,000 total. Each pair of required courses should be authored to provide that stage's budget, including checkpoints and the capstone in stage 4. A foundation course can supply 250: two lessons (40), three readings (90), two practices (20), one checkpoint (100). Later-course item counts must follow actual workload, not artificial splitting to inflate XP. Before publishing a path, validate that its required items make every threshold attainable without optional resources or repeats. These budgets are initial tuning values, not a claim that the current catalog supplies a complete path.

Optional learning items earn the same schedule on first completion. A learner can exceed the XP threshold before finishing required courses; the UI must then show the remaining milestone rather than suggesting more XP is needed. Excess XP carries forward within the subject. A subject with an unfinished curriculum must show its current available stages and must not advertise unattainable ranks.

## Capstone

Offer at least two equivalent formats: written explanation, annotated timeline, comparative source study, or recorded explanation with transcript. All are evaluated against four criteria, each scored 0–3:

- Accuracy and context.
- Traceable, relevant sources.
- Fair treatment of an alternative or competing interpretation.
- Coherent synthesis and acknowledgment of limitations.

A pass requires at least 9/12 and no zero-scored criterion. The course supplies examples and explains what earns each score: 0 absent, 1 partial/inaccurate, 2 adequate with minor gaps, 3 clear and well supported. Revision is allowed. Completion-only checkboxes do not constitute this assessment. Use an identified human reviewer or a validated rubric-based assessment service; the current app has neither. Until assessment is implemented, stage 4 must remain unavailable. Self-reflection is valuable but should not silently substitute for the advertised assessment.

## Award integrity and persistence

Record immutable activity awards with user identity, subjectID, activityID, award type, amount, earnedAt and rule version. Deduplicate by user + subject + activity + award type. Presentation-only edits retain the activity identity and cannot re-award XP. Materially new learning gets a new identity only after editorial review. Record attempt evidence and versioned course/stage completion separately from XP. Persist durable tier grants and badge grants with their qualifying evidence.

Each enrollment activity instance credits one primary subject, displayed before completion. Cross-subject tags are discovery tools and do not multiply XP. A required shared reading can satisfy more than one relevant completion checklist; course budget validation must account for already-credited instances and supply sufficient unique activities. Alternative formats share one equivalence-group award key; completing both cannot double XP. Offline completions must merge idempotently across devices. Account totals count each activity award once and add review rewards, rather than recording duplicate copies of subject awards.

Repeated quiz attempts, video replay, note spam and toggling a reading's completion do not award first-completion XP again. Removing a completion mark changes the checklist but does not revoke previously earned XP or badges. New advancement requires the current required checklist to be complete. Preserve existing earned ranks when curricula change; show new material as an update path. Review daily limits use the user's recorded calendar/time-zone policy consistently across devices.

## Badges and display

Five transparent, 256-unit SVG badges and 512-pixel PNG exports share a shield silhouette, inset rim and center emblem. The names and distinct shapes carry the meaning independently of color. Rank dots encode one through five.

| Badge | Color | Emblem | Unlock |
| --- | --- | --- | --- |
| Novice | Copper | Spark | First completed subject learning item |
| Apprentice | Jade | Open book | 500 XP + stage 1 |
| Investigator | Blue | Magnifying glass | 1,500 XP + stage 2 |
| Scholar | Violet | Quill | 3,000 XP + stage 3 |
| Sage | Gold | Radiant star | 5,000 XP + stage 4 and capstone |

Use 64–96 point badges on subject cards and a larger view on the achievement screen. At 24–32 points use a simplified center emblem; the full shield detail has not been optimized for that size. Show locked badges muted with a lock and explicit requirements. An earned badge's detail shows subject, rank, date, XP at award and milestones. Accessible labels include subject and rank; color never determines status. A short unlock animation may scale and illuminate the badge; respect Reduce Motion and avoid flashing. Badge SVGs are source assets; transparent PNGs can be imported into Xcode image asset sets. Native rendering and export to app-specific vector formats remain integration work.

Optional achievement extensions (not designed as assets in this delivery): First Footnote (first source exercise), Bridge Builder (first passed comparison), Primary Source Sleuth (ten distinct primary readings), and Return to the Text (seven completed due-review sessions on distinct days). Keep these separate from rank requirements, one-time awards, and no additional subject XP.

## Fit with the current app

Hearken currently has four ranks derived from predicted recall: Seeker, Student, Scholar, Master. They are not XP-driven. Its XP events lack subject/activity attribution and award per-correct-answer XP. The current chapter reward is 5 XP. Simply renaming that enum would not implement this design.

Integration requires an attributed, deduplicated award ledger; persisted course and stage milestones; durable tier/badge grants; learning items and assessments; a new subject progression display; and media support. Existing global XP should remain in account history. Do not invent subject allocations for legacy events without reliable provenance. Existing reading and review evidence can support an explicitly documented migration; preserve old achievements as legacy rather than treating recall percentages as completed courses.

The included Swift core evaluates XP plus contiguous stage gates and preserves earned ranks. It assumes upstream evidence is validated and XP is deduplicated. It does not award XP, assess capstones, enroll users, grant the Novice badge, or integrate SwiftData, CloudKit, YouTube or UI. `tier-rules.json` is a matching specification, not loaded by the evaluator.
