# Hearken integration notes

The curriculum is authored and validated in this project’s deliverables directory. The application repository has not been modified during this course-building task. The app currently uses a subject/unit/resource catalog and a recall-based rank model; this package adds concepts that need explicit support rather than being dropped into the existing catalog unchanged.

## Content organization

- New subject ID: `lds-doctrine`; display name: **Latter-day Saint Doctrine**. Keep existing `doctrinal-mastery` and `doctrine-and-covenants` subjects and their progress intact. This course can cross-link their existing scripture content.
- One subject learning path, eight sequential courses, thirty-two modules, and four advancement stages.
- Stable IDs and one-time award keys appear in `curriculum.json`. Keep award keys unchanged when correcting wording. A newly versioned assessment need not re-award XP already earned for the same milestone.
- Required activities are original lessons, prompted readings, submitted exercises, course checkpoints, and a capstone. Optional activities are deeper readings and provider-hosted videos with an original accessible alternative.
- Use `chapterID` and `verses` to navigate the existing scripture reader. The supplied validator checks both against the local scripture JSON files.
- `sourceIDs` resolve into the package’s provenance and rights register. Display perspective labels where a source is used. Original interpretive teaching should remain distinguishable from quoted or attributed claims.

## Models and storage

Add explicit path/stage/course/module/activity models, assessment submission and review models, and a subject-scoped XP ledger. The current unit/resource model alone cannot enforce this path. Do not silently discard the original article, prompt, success criteria, source disposition, prerequisites, or review requirements when adapting content.

Suggested ledger fields: event ID, learner ID, subject ID, activity ID, award key, content version, XP, timestamp, completion evidence reference, reviewer/assessment ID, and outcome. Enforce uniqueness on `(learnerID, subjectID, awardKey)` in the persistence layer. A video and its original fallback share the same key. Repeated placements of the same optional selection also share a key. Checkpoint retries and revision drafts never issue additional completion awards.

Persist course checkpoints, stage checks, and capstone outcomes separately from XP totals. Tier evaluation needs both a sufficient subject XP balance and all required gates. Optional XP is supplementary, not a substitute for any required work. Existing recall mastery and account-wide review XP remain separate measures.

## Course screen

Show the current tier, the next milestone, subject XP, and required items remaining. Within a course, show objectives, explicit learning items, original articles, linked/reader-based selections, response prompts, exercises, and checkpoint status. Make each item's completion evidence clear before submission. Display optional enrichment separately so learners understand it is not necessary to buy a book or use YouTube to progress.

An article opens inside the app; scripture selections navigate the reader; external copyrighted articles open their hosted source. A saved link, an opened page, or elapsed playback does not establish learning completion.

## YouTube

Use the provider's official iframe player in an appropriate web view when embedding is allowed. Configure inline playback using the current provider and platform guidance. Test every ID in the actual app, including caption availability, region limits, origin/referrer requirements, and failure behavior. Keep player controls and attribution intact. The curated ASL selection is labeled as an ASL interpretation; the Wilcox item is a short excerpt, not the entire devotional.

Provide an external YouTube link and the original lesson/task fallback on failure or accessibility need. Never download or rehost recordings, ingest copyrighted transcripts, or create an offline audio version. The video metadata in this package is source-identity checked; runtime playback is explicitly unverified.

Provider documentation: [YouTube IFrame Player API](https://developers.google.com/youtube/iframe_api_reference).

## Assessment delivery

`ASSESSMENT_GUIDE.md` is a facilitator document. `curriculum.json` is an editorial master containing answer guides. Do not bundle it unchanged if revealing answer guides would compromise the intended assessment experience. Produce a learner-facing projection and retain reviewer keys in an appropriate review service or facilitator workflow.

Short-answer checkpoints need review. This package specifies what qualifies as a pass but does not provide a validated grading engine. Human review is the initial workable implementation. Automated assessment must be calibrated against reviewed examples before it can issue progression outcomes. Assess reasoning, not religious assent.

Course checkpoint: ten questions, 0–2 each, pass at 16/20, 100 XP once. Stage advancement: five applied questions, 0–2 each, pass at 8/10, 0 XP. Capstone: four 0–3 criteria, pass at 9/12 with no zero, 200 XP once. Unlimited revision and retries.

## Publication and maintenance

Use content versions, a correction log, source attribution, and periodic source checking. Review original doctrinal explanations before release. Rights dispositions are per source; no modern Church article or recording is assumed public domain. The public-domain Talmage editions are presently linked, not imported. Existing scripture edition rights require their own audit.

Run `validate_curriculum.py --scripture-dir /Users/stephenwarren/Developer/hearken/Hearken/Resources/Content` to check arithmetic, identifiers, prerequisites, assessment rules, source references, and all assigned chapter/verse locators. Validation does not establish doctrinal endorsement, copyright clearance for every territory, or working video playback.
