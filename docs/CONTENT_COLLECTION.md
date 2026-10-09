# Hearken starter collection

Reviewed 2026-10-09. This is an implemented starter catalog, not a complete course or a release claim. Content version 2 preserves all previously present subject, unit, resource and question IDs. Display names and explanations can improve without replacing IDs that user progress depends on.

## Repository findings

`ContentModels.swift` defines a `SubjectCatalog` with subjects and questions. Subjects contain numbered units and resources. Units contain whole-chapter reading IDs, not verse selections or lessons. Resources support seven kinds, attribution, a note, an optional URL and an optional scripture chapter. Questions hold options, a zero-based answer index, a plain reference string, explanation and optional chapter link.

`ContentService.swift` loads `subjects.json` from the app bundle, then lazily reads five scripture-volume JSON files. No remote content ingestion, database compilation or migration is currently implemented. `scripts/import_standard_works.py` imports a local Standard-Works checkout and normalizes text into permanent Church-slug-based IDs. The current bundle contains 1,582 chapters and 41,995 verses. The README's older sample-scripture description is stale. Scripture coverage does not imply coverage of copyrighted introductions, chapter summaries, footnotes or Official Declarations. The importer is a transformation, not a rights audit of its upstream data.

The current unit screen renders chapter links and a randomized check of up to five questions. Non-scripture readings appear in each subject's Library, not in the unit screen. Resources with URLs open externally. Resource notes and question explanations carry visible perspective labels. Question reference URLs are plain text, not tappable source buttons. Chronology Challenge currently receives every subject question, including questions that are not chronology exercises. Map Quest is a placeholder. The additions do not claim to implement maps or interactive timelines.

## Implemented organization

| Subject | Units | Starter material |
| --- | ---: | --- |
| Doctrinal Mastery | 6 | Spiritual learning; 96 reference-only passage entries across four courses; themed comparison; six checks |
| Book of Mormon Narrative and Geography | 5 | Narrative sequence, internal places, textual readings, limits of modern geography proposals |
| Biblical Timeline | 8 | Narrative eras and contextual chapter readings; caution about traditional dates |
| Doctrine and Covenants and LDS History | 6 | New York, Kirtland, Missouri, Nauvoo, migration and declarations; documentary and institutional sources |
| Ancient Israelite Theology | 8 | Covenant, divine names, sacred space, sacrifice, festivals, prophets, wisdom, messianic interpretation |
| History of Christianity | 7 | Existing long-range outline; added council chronology and differing continuity claims |
| World Faiths | 8 | Existing comparison outline; Catholic and Orthodox self-description and LDS comparison |
| Biblical Geography | 4 | Regions, Jerusalem/exile, Gospel settings, Acts journeys |
| Scriptural Texts and Transmission | 4 | Witness comparison, Dead Sea Scrolls, NT textual research, LDS documentary history |
| Early Christian Writers | 4 | Didache, Justin, Irenaeus and Martyrdom of Polycarp |

Totals: **10 subjects, 60 units, 155 resources, 44 questions** (34 new), including **96 Doctrinal Mastery references**. All four DM course lists link to full chapters; exact passage references appear as resource titles. Opening a reference shows the whole chapter because verse-range navigation is not modeled. Twenty-two units still lack checks. This is particularly true of medieval/reformation history and the existing Lutheran, Reformed, evangelical, Jewish and Muslim outlines. Existing bibliographic-only entries remain bibliography rather than newly verified available readings.

## Source and evidence policy

1. **Scriptural narrative** means what a text reports. A text is primary evidence for its wording and presentation, not independent corroboration of every narrated event.
2. **Tradition-specific doctrine** must name the tradition. LDS restoration and Godhead teachings, Catholic Trinitarian explanations and Orthodox creed wording are not interchangeable. Do not grade disagreement with a tradition as historical ignorance.
3. **Historical evidence** should identify documentary witnesses, date recorded, authorship, genre and provenance. Distinguish the alleged event date from the date of the surviving account.
4. **Scholarly consensus** requires representative current academic support, not an institutional assertion or two opposing advocacy books. This starter avoids manufacturing a consensus rating. A next review should assemble independent academic sources before grading historical reconstruction of the Exodus, united monarchy or Book of Mormon ancient setting.
5. **Disputed reconstruction** must retain uncertainty. Do not pin Zarahemla, Bountiful or the American land of Nephi to modern coordinates as established sites. Even identical place names within a text need separate IDs and contexts. Internal diagrams, when added, must be explicitly schematic.
6. **Rights**: new prose is original; external publications are linked, not copied. Scripture references are factual identifiers. A public-domain ancient author does not make every modern translation or website presentation public domain. Do not redistribute manuals, modern book chapters, copyrighted maps or translations without evaluating permission.

The inherited question about Lehi's departure now explicitly identifies the textual dating tension between about 600 BCE and Zedekiah's conventionally dated accession in 597 BCE. Other inherited historical date explanations remain starter material pending an independent chronology review. No claim that all initial content is scholarly consensus is intended.

## Verified reading sources

- [Doctrinal Mastery course references](https://www.churchofjesuschrist.org/study/manual/doctrinal-mastery-core-document-2023/doctrinal-mastery-passages-and-key-phrases?lang=eng): the linked page lists 24 references in each course. The URL includes 2023 while its displayed publication citation says 2021. Treat this as a pinned linked edition, not an assertion of the latest curriculum in every region. The Old Testament course includes Pearl of Great Price readings; the D&C course includes Joseph Smith—History. Official key phrases have not been reproduced.
- [Acquiring Spiritual Knowledge](https://www.churchofjesuschrist.org/study/manual/doctrinal-mastery-core-document-2023/acquiring-spiritual-knowledge?lang=eng): LDS seminary's own explanation of its learning principles.
- [Book of Mormon Geography](https://www.churchofjesuschrist.org/study/manual/gospel-topics/book-of-mormon-geography?lang=eng): Church position on limits of geographic endorsement. This is a statement of institutional belief, not archaeological validation.
- [Bible Maps](https://www.churchofjesuschrist.org/study/scriptures/bible-maps?lang=eng): linked LDS reference maps. Site identifications and routes need academic review before conversion into graded map tasks.
- [Dead Sea Scrolls introduction](https://www.deadseascrolls.org.il/learn-about-the-scrolls/introduction): Israel Antiquities Authority overview of archaeological manuscript evidence, including resemblance to and differences from the Masoretic Text.
- [Institute for New Testament Textual Research](https://www.uni-muenster.de/INTF/): University of Münster's account of its critical editions and transmission research. Next expand with witness-specific sources and edition apparatus for Mark 16 and John 7:53–8:11; current chapter assignments alone do not teach those variant histories.
- [First Vision accounts](https://www.josephsmithpapers.org/site/accounts-of-the-first-vision): documentary edition distinguishes firsthand accounts and later reported accounts. The surviving documents differ; comparison must not silently combine them into one purported contemporary report.
- [Catholic Catechism, §§232–267](https://www.vatican.va/archive/ENG0015/__P17.HTM) and [Orthodox Nicene Creed](https://www.oca.org/orthodoxy/the-orthodox-faith/doctrine-scripture/the-symbol-of-faith/nicene-creed): self-description, including distinct formulations concerning the Holy Spirit.
- [Didache](https://www.newadvent.org/fathers/0714.htm), [Justin's First Apology](https://www.newadvent.org/fathers/0126.htm), [Irenaeus, Against Heresies III](https://www.newadvent.org/fathers/0103.htm), [Martyrdom of Polycarp](https://www.newadvent.org/fathers/0102.htm): ancient primary texts in historical English translations hosted by a Catholic reference site. Publisher-added headings and linked terminology require distinction from ancient text; dating, authorship and reception need modern critical editions for deeper study.
- [Race and the Priesthood](https://www.churchofjesuschrist.org/study/manual/gospel-topics-essays/race-and-the-priesthood?lang=eng), [Plural Marriage in Kirtland and Nauvoo](https://www.churchofjesuschrist.org/study/manual/gospel-topics-essays/plural-marriage-in-kirtland-and-nauvoo?lang=eng), [The Manifesto and the End of Plural Marriage](https://www.churchofjesuschrist.org/study/manual/gospel-topics-essays/the-manifesto-and-the-end-of-plural-marriage?lang=eng): LDS official historical interpretations with documentary citations. Extend with independent academic histories and affected members' primary accounts. OD1/OD2 remain external canonical readings because the bundle omits them.

## Next schema and editorial work (proposed, not implemented)

Add optional unit `resourceIDs`, objectives and authored lesson sections; retain existing chapter links. Add shared source records with author/editor, publication, edition, locator, URL, rights, checked date and perspective. Questions should reference source IDs and specific locators, with source buttons visible in the game. Add question kind so chronology games can exclude other material.

Timeline events should store structured dates, dating basis (narrative/traditional/documented), precision, optional alternatives, places and citations. Separate event, recording and publication dates. Avoid astronomical-year versus BCE/CE conversion errors. Place records should store textual identity separately from modern identification, coordinate precision, evidence and disputed alternatives. Book of Mormon internal places should permit absent modern coordinates.

Prioritize five meaningful checks per active unit, source-based lesson prose, independent academic biblical chronology, and primary readings for remaining Christian traditions. Expand patristics with Ignatius, Athanasius, the Cappadocians, Augustine and Syriac Christianity using critical editions and explicit reception labels. Extend LDS history beyond the American pioneer narrative with women, Black Saints, Indigenous experiences, succession branches, and global communities. Independent source coverage is a release prerequisite for modules that claim scholarly consensus.

## Validation and workflow

Run `python3 scripts/validate_content.py` before bundling. It checks ID uniqueness, unit ownership, answer bounds, duplicate options, HTTPS link shape, scripture chapter existence and every DM verse range. It reports empty question coverage rather than hiding it. It does not validate live link availability or whether a source supports every claim.

Use the existing scripture import script only for scripture updates. Edit `subjects.json` for this catalog, increment the catalog version for a release, preserve IDs, review evidence/rights and validate. Current `contentVersion` is descriptive; ContentService does not enforce or migrate catalog versions.

Validation completed: the Python integrity check passed; the actual Swift `SubjectCatalog` and `ScriptureVolumeFile` models decoded the updated catalog and all five volume files successfully; the content diff passed whitespace checks. No simulator UI or full Xcode test run was performed.

[British Museum Babylonian Chronicle collection record](https://www.britishmuseum.org/collection/object/W_1896-0409-51) supplies the 597 BCE campaign dating used in the chronology caution; compare 2 Kings 24:17 for Zedekiah. The museum record was available in indexed search but its full page returned an access error during this review.
