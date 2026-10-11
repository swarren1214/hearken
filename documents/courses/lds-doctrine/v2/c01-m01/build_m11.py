"""Builds module 1.1 (Sources and authority) for course format v2:
- question-banks/lds-doctrine-c01-m01-additions.json : new objective items, bank schema 1.1
- module.json : the module definition (article, readings + quizzes, practice, module quiz, essay)
"""
import json, sys, os

OUT = sys.argv[1]
MOD = "lds-doctrine-c01-m01"
OBJ = f"{MOD}-objective-01"
COURSE = "lds-doctrine-c01"

SOURCES = [
    {"id": "authority", "title": "Approaching Latter-day Saint Doctrine",
     "url": "https://newsroom.churchofjesuschrist.org/article/approaching-mormon-doctrine",
     "perspective": "Latter-day Saint institutional", "rights": "link_only",
     "editorialNote": "Church Newsroom guide (May 2007) on identifying doctrine.", "verifiedDate": "2026-10-10",
     "verificationMethod": "web_fetch_read"},
    {"id": "scripture-pgp.a-of-f.1-1-13", "title": "Articles of Faith 1:1–13",
     "passage": {"chapterID": "pgp.a-of-f.1", "from": 1, "to": 13},
     "perspective": "Latter-day Saint canonical text", "rights": "existing_app_text",
     "verifiedDate": "2026-10-10", "verificationMethod": "local_scripture_text_check"},
    {"id": "scripture-dc.1-37-39", "title": "Doctrine and Covenants 1:37–39",
     "passage": {"chapterID": "dc-testament.dc.1", "from": 37, "to": 39},
     "perspective": "Latter-day Saint canonical text", "rights": "existing_app_text",
     "verifiedDate": "2026-10-10", "verificationMethod": "local_scripture_text_check"},
    {"id": "scripture-dc.68-1-4", "title": "Doctrine and Covenants 68:1–4",
     "passage": {"chapterID": "dc-testament.dc.68", "from": 1, "to": 4},
     "perspective": "Latter-day Saint canonical text", "rights": "existing_app_text",
     "verifiedDate": "2026-10-10", "verificationMethod": "local_scripture_text_check"},
    {"id": f"{MOD}-article-v2", "title": "Sources and authority (Hearken article)",
     "perspective": "Original Hearken teaching method", "rights": "original_content",
     "verifiedDate": "2026-10-10", "verificationMethod": "authored"},
]

qs = []
n = 0
def opts(*texts):
    return [{"id": f"o{i+1}", "text": t} for i, t in enumerate(texts)]

def mc(family, prompt, options, correct, explanation, sources, locators, difficulty="introductory", uses=None, perspective="Latter-day Saint canonical text"):
    global n
    n += 1
    qs.append({
        "id": f"{MOD}-bank-q{100 + n:03d}", "revision": 1, "type": "multiple_choice",
        "subjectID": "lds-doctrine", "courseID": COURSE, "moduleID": MOD, "objectiveIDs": [OBJ],
        "questionFamilyID": f"{MOD}:{family}", "difficulty": difficulty, "prompt": prompt,
        "options": opts(*options), "correctOptionID": f"o{correct}", "explanation": explanation,
        "sourceIDs": sources, "perspective": perspective,
        "eligibleAssessmentTypes": uses or ["lesson_check", "reading_check", "practice", "course_checkpoint", "stage_advancement"],
        "sourceLocators": [{"sourceID": s, "locator": l} for s, l in locators],
    })
    return qs[-1]["id"]

def tf(family, prompt, truth, explanation, sources, locators, perspective="Latter-day Saint canonical text", uses=None):
    global n
    n += 1
    qs.append({
        "id": f"{MOD}-bank-q{100 + n:03d}", "revision": 1, "type": "true_false",
        "subjectID": "lds-doctrine", "courseID": COURSE, "moduleID": MOD, "objectiveIDs": [OBJ],
        "questionFamilyID": f"{MOD}:{family}", "difficulty": "introductory", "prompt": prompt,
        "options": [{"id": "o1", "text": "True"}, {"id": "o2", "text": "False"}],
        "correctOptionID": "o1" if truth else "o2", "explanation": explanation,
        "sourceIDs": sources, "perspective": perspective,
        "eligibleAssessmentTypes": uses or ["lesson_check", "reading_check", "practice", "course_checkpoint", "stage_advancement"],
        "sourceLocators": [{"sourceID": s, "locator": l} for s, l in locators],
    })
    return qs[-1]["id"]

AOF = "scripture-pgp.a-of-f.1-1-13"
DC1 = "scripture-dc.1-37-39"
DC68 = "scripture-dc.68-1-4"
ART = f"{MOD}-article-v2"

# --- Reading A: Articles of Faith 1:1–13 ---
a1 = mc("aof-continuing-revelation", "Which Article of Faith states that God “will yet reveal many great and important things pertaining to the Kingdom of God”?",
        ["Article of Faith 7", "Article of Faith 8", "Article of Faith 9", "Article of Faith 10"], 3,
        "Article 9 affirms past, present and future revelation. Article 7 lists spiritual gifts such as revelation and prophecy, Article 8 concerns the Bible and Book of Mormon, and Article 10 concerns gathering, Zion and Christ's reign.",
        [AOF], [(AOF, "Articles of Faith 1:7–10")])
a2 = mc("aof-bible-qualification", "Article of Faith 8 accepts the Bible as the word of God with which qualification?",
        ["As far as it is translated correctly", "As far as it agrees with the Book of Mormon", "As far as it is interpreted by Church leaders", "As far as the New Testament is concerned"], 1,
        "The article's qualifier concerns translation. It does not make the Bible's authority depend on agreement with another book, on an interpreter, or on one testament.",
        [AOF], [(AOF, "Articles of Faith 1:8")])
a3 = tf("aof-conscience", "Article of Faith 11 claims the privilege of worshiping according to one's own conscience and allows all others the same privilege.", True,
        "Article 11 claims this privilege and extends it to all people, “let them worship how, where, or what they may.”",
        [AOF], [(AOF, "Articles of Faith 1:11")])
a4 = mc("aof-called-of-god", "According to Article of Faith 5, how must a man be called to preach the gospel and administer its ordinances?",
        ["By a vote of the local congregation", "By prophecy and the laying on of hands by those in authority", "By completing a course of religious study", "By a personal experience of conversion"], 2,
        "Article 5 names being called of God by prophecy and by the laying on of hands by those who are in authority. The article mentions none of the other options.",
        [AOF], [(AOF, "Articles of Faith 1:5")])
a5 = mc("aof-scope", "A friend says the Articles of Faith are a complete summary of Latter-day Saint doctrine. Which response best fits the text?",
        ["Yes; Article 13 states that the list is complete",
         "No; they are commentary rather than scripture",
         "They state core beliefs briefly, and Article 9 itself expects further revelation",
         "They summarize the Book of Mormon only"], 3,
        "The thirteen articles are short canonical statements of belief, and Article 9 anticipates more revelation, so they are not presented as exhaustive. Article 13 concerns conduct and virtue; the articles are canonical, in the Pearl of Great Price; and they are not a Book of Mormon summary.",
        [AOF, ART], [(AOF, "Articles of Faith 1:9, 1:13"), (ART, "The standard works: an open canon")], difficulty="application")
a6 = tf("aof-location", "The Articles of Faith are part of the Pearl of Great Price, one of the standard works.", True,
        "The thirteen Articles of Faith are printed in the Pearl of Great Price. The Church's guide also names them separately among the sources of doctrine.",
        [AOF, "authority"], [(AOF, "Articles of Faith 1"), ("authority", "Sources of doctrine")])

# --- Reading B: D&C 1:37–39 and 68:1–4 ---
b1 = mc("dc68-condition", "In Doctrine and Covenants 68:4, what is said to “be scripture”?",
        ["Every word spoken by an ordained elder", "Whatever they speak when moved upon by the Holy Ghost", "Anything printed in a Church publication", "Every sermon that is recorded in writing"], 2,
        "Verse 4 ties this broad sense of scripture to being moved upon by the Holy Ghost. It does not make ordination, publication or a written record the condition.",
        [DC68], [(DC68, "D&C 68:4")])
b2 = mc("dc1-voice", "Doctrine and Covenants 1:38 says, “whether by mine own voice or by the voice of my servants, it is the same.” What does the verse claim?",
        ["That the Lord's word, given by his own voice or through his servants, will be fulfilled",
         "That anyone who speaks about God speaks for him",
         "That servants' words replace earlier scripture",
         "That only words spoken aloud count as revelation"], 1,
        "The verse affirms that the Lord's word shall all be fulfilled, whether given by his own voice or his servants'. It does not extend this to anyone who speaks about God, say later words replace scripture, or limit revelation to speech.",
        [DC1], [(DC1, "D&C 1:38")])
b3 = tf("dc68-audience", "Doctrine and Covenants 68:1–3 first addresses Orson Hyde and presents his calling as an “ensample” for others ordained to the priesthood.", True,
        "Verse 1 names Orson Hyde; verses 2–3 call this an ensample to those ordained to this priesthood, who are to speak as moved upon by the Holy Ghost.",
        [DC68], [(DC68, "D&C 68:1–3")])
b4 = tf("dc68-canon", "Doctrine and Covenants 68:4 says that inspired words spoken by Church leaders are added to the standard works.", False,
        "The verse calls such inspired speech scripture in a broad sense, the will, mind, word and voice of the Lord, but says nothing about the standard works. Additions to the canon happen by a separate, formal process presented to the Church.",
        [DC68, ART], [(DC68, "D&C 68:4"), (ART, "Institutional teaching: how the Church speaks today")])
b5 = mc("dc68-with-guide", "Read alongside D&C 68:4, what does the Church's guide add about statements by Church leaders?",
        ["That every leader's sermon becomes doctrine once it is published",
         "That a single statement by one leader on one occasion is often a personal view, not binding on the Church",
         "That members should disregard what leaders say outside general conference",
         "That only the Bible should be treated as scripture"], 2,
        "The guide says not every statement by a leader is doctrine and that a single statement on one occasion often represents a personal, considered opinion. It does not say publication makes a sermon doctrine, tell members to disregard leaders, or limit scripture to the Bible.",
        ["authority", DC68], [("authority", "Statements by individual leaders"), (DC68, "D&C 68:4")],
        difficulty="application", perspective="Latter-day Saint institutional")

b6 = mc("dc1-record", "In Doctrine and Covenants 1:39, what does the Spirit do?",
        ["It beareth record, and the record is true", "It replaces the need for scripture", "It speaks only to the President of the Church", "It confirms every statement made in the Church"], 1,
        "Verse 39 says the Spirit beareth record and the record is true, and the truth abides forever. It does not say the Spirit replaces scripture, speaks to one person only, or confirms every statement.",
        [DC1], [(DC1, "D&C 1:39")])
b7 = tf("dc1-search", "Doctrine and Covenants 1:37 invites readers to search “these commandments.”", True,
        "Verse 37 opens, “Search these commandments, for they are true and faithful.”",
        [DC1], [(DC1, "D&C 1:37")])

# --- Reading C: Approaching Latter-day Saint Doctrine ---
c1 = mc("guide-who-establishes", "According to the Church's guide, who establishes the Church's doctrine?",
        ["Any General Authority speaking in general conference", "The First Presidency and the Quorum of the Twelve Apostles, counseling together", "Faculty in Church-sponsored universities", "Each local bishop for his own ward"], 2,
        "The guide names the First Presidency and the Quorum of the Twelve, counseling together. A conference speaker, scholars and local leaders teach, but the guide does not give them this role.",
        ["authority"], [("authority", "Who establishes doctrine")], perspective="Latter-day Saint institutional")
c2 = mc("guide-where-doctrine", "Which list matches the guide's description of where the Church's doctrine resides?",
        ["The standard works, official declarations and proclamations, and the Articles of Faith",
         "General conference talks, Church magazines and devotional books",
         "Seminary manuals and Church history volumes",
         "Popular books by Church leaders"], 1,
        "The guide names the four standard works, official declarations and proclamations, and the Articles of Faith. It adds that doctrine is consistently proclaimed in official publications, but it does not list magazines, manuals or books as the place doctrine resides.",
        ["authority"], [("authority", "Sources of doctrine")], perspective="Latter-day Saint institutional")
c3 = mc("guide-peripheral", "Which example does the guide give of a peripheral teaching that should not be treated as central?",
        ["The Atonement of Jesus Christ", "The Resurrection of Jesus Christ", "The location of the Garden of Eden", "Faith in Jesus Christ"], 3,
        "The guide contrasts core doctrines, such as the Atonement, with peripheral ones, using the location of the Garden of Eden as its example. The Resurrection and faith in Christ belong to the core it describes.",
        ["authority"], [("authority", "Central and peripheral doctrines")], perspective="Latter-day Saint institutional")
c4 = tf("guide-publications", "The Church's guide says its doctrine is consistently proclaimed in official Church publications.", True,
        "The guide states that doctrine established by the First Presidency and the Twelve is consistently proclaimed in official Church publications.",
        ["authority"], [("authority", "Who establishes doctrine")], perspective="Latter-day Saint institutional")
c5 = mc("guide-test-a-claim", "A blog post quotes a nineteenth-century sermon to prove a “Mormon doctrine.” Following the guide, which question should you ask first?",
        ["How many times has the quote been shared online?",
         "Did the speaker hold a high office in the Church?",
         "Is the teaching found in the standard works, official declarations, or current official publications?",
         "Does the sermon sound inspired to me?"], 3,
        "The guide points to the standard works, official declarations and proclamations, and consistent official publications. Popularity proves nothing; a speaker's office alone does not make a single statement doctrine; and a personal impression does not settle the source's standing.",
        ["authority", ART], [("authority", "Statements by individual leaders; sources of doctrine"), (ART, "Institutional teaching")],
        difficulty="application", perspective="Latter-day Saint institutional")
c6 = tf("guide-core", "The Church's guide says some doctrines are more central than others.", True,
        "The guide distinguishes core doctrines, such as the Atonement of Jesus Christ, from peripheral ones.",
        ["authority"], [("authority", "Central and peripheral doctrines")], perspective="Latter-day Saint institutional")
c7 = mc("guide-terms", "Why does the guide say some disagreements about Latter-day Saint belief arise?",
        ["Members are not allowed to explain their beliefs",
         "Some terms carry different meanings in Latter-day Saint usage than in other traditions",
         "The standard works contradict each other",
         "Doctrine changes every year"], 2,
        "The guide notes that terms can carry different meanings, giving being “born again” as an example. It does not claim the other reasons.",
        ["authority"], [("authority", "Terminology")], perspective="Latter-day Saint institutional")

# --- Article sections and module quiz ---
d1 = mc("classify-gospel-topics", "Which category best fits a current Gospel Topics page on the Church's website?",
        ["Canonical scripture", "Institutional explanation", "Individual commentary", "Historical record"], 2,
        "A Church-published explanation shows how the Church teaches a subject today. It is not part of the standard works, it is not one author's private interpretation, and it is not a record of a past event.",
        [ART], [(ART, "Institutional teaching")], perspective="Original Hearken reading method grounded in the cited sources")
d2 = mc("classify-conference", "How does this course classify a general conference address published by the Church?",
        ["Canonical scripture, once it is printed",
         "Institutional teaching, but not part of the standard works",
         "Personal commentary with no institutional standing",
         "A historical record only"], 2,
        "Conference addresses are delivered and published by the Church and show how it teaches. They are not added to the standard works by being printed, and treating them as mere private commentary or only as history would understate their role.",
        [ART, "authority"], [(ART, "Institutional teaching"), ("authority", "Official publications")], difficulty="application",
        perspective="Original Hearken reading method grounded in the cited sources")
d3 = mc("classify-talmage", "James E. Talmage published The Articles of Faith in 1899 and later served as an apostle. How should a careful student cite the book?",
        ["As canonical scripture", "As an official declaration", "As historical commentary, useful for context, that does not settle current teaching", "As the Church's current explanation of every article"], 3,
        "The book is one learned author's explanation in his era. Its author's later office does not make it canon or an official declaration, and an 1899 commentary cannot stand in for current institutional teaching.",
        [ART], [(ART, "Commentary: useful, but someone's reading")], difficulty="application",
        perspective="Original Hearken reading method grounded in the cited sources")
d4 = mc("ledger-setting", "Why does the source ledger record a source's setting?",
        ["Because a source's meaning and reach depend on who said it, when, to whom and why",
         "Because older sources always outrank newer ones",
         "Because the setting decides whether a source is true",
         "Because only sources with a known setting may be quoted"], 1,
        "Setting tells you what a source can show: a revelation addressed to one person, a conference address and a private letter carry different reach. Age does not determine rank, setting does not decide truth, and sources without full settings can still be used with care.",
        [ART], [(ART, "The source ledger")], perspective="Original Hearken reading method grounded in the cited sources")
d5 = mc("historical-record-reach", "A dated diary entry reports what its writer heard at an 1880 meeting. What does it most directly establish?",
        ["What the Church teaches today", "What the writer reported hearing at that meeting", "That the idea was official doctrine in 1880", "That every member present agreed"], 2,
        "A diary is a historical record of what its writer reported. By itself it does not show doctrinal status then or now, or the views of others present.",
        [ART], [(ART, "Historical records: what someone said, when")], perspective="Original Hearken reading method grounded in the cited sources")
d6 = mc("open-canon-example", "Which event shows that the Latter-day Saint canon is open?",
        ["Two revelations were accepted into scripture by a general conference in 1976 and became D&C 137 and 138",
         "A popular book was quoted in many sacrament meetings",
         "A Church magazine printed a new article",
         "A historian discovered an early diary"], 1,
        "The 1976 additions were presented to a general conference and accepted, and in 1981 became sections 137 and 138. Quotation, magazine publication and historical discovery do not change the canon.",
        [ART], [(ART, "The standard works: an open canon")], perspective="Original Hearken reading method grounded in the cited sources")

# Matching: the guide's sources of doctrine
qs.append({
    "id": f"{MOD}-match-q003", "revision": 1, "type": "matching",
    "subjectID": "lds-doctrine", "courseID": COURSE, "moduleID": MOD,
    "title": "Where doctrine comes from",
    "prompt": "Match each item from the Church's guide to its description.",
    "instructions": "Match each item on the left to exactly one description on the right. Use every description once.",
    "objectiveIDs": [OBJ], "questionFamilyID": f"{MOD}:guide-matching", "difficulty": "introductory",
    "leftItems": [
        {"id": "l1", "text": "The standard works"},
        {"id": "l2", "text": "The First Presidency and the Quorum of the Twelve"},
        {"id": "l3", "text": "A single statement by one leader on one occasion"},
        {"id": "l4", "text": "The location of the Garden of Eden"},
    ],
    "rightItems": [
        {"id": "r3", "text": "Often a personal view, not binding on the Church"},
        {"id": "r1", "text": "The Bible, Book of Mormon, Doctrine and Covenants and Pearl of Great Price"},
        {"id": "r4", "text": "The guide's example of a peripheral teaching"},
        {"id": "r2", "text": "The councils that establish doctrine together"},
    ],
    "correctPairs": [{"leftID": "l1", "rightID": "r1"}, {"leftID": "l2", "rightID": "r2"}, {"leftID": "l3", "rightID": "r3"}, {"leftID": "l4", "rightID": "r4"}],
    "sourceIDs": ["authority"],
    "explanation": "Each description follows the guide: the four standard works, the councils that establish doctrine, the caution about single statements, and its example of a peripheral subject.",
    "eligibleAssessmentTypes": ["lesson_check", "practice", "course_checkpoint", "stage_advancement"],
    "scoring": {"maxPoints": 1, "method": "all_pairs_correct", "partialFeedback": True, "awardAdditionalXP": False},
    "perspective": "Latter-day Saint institutional",
    "sourceLocators": [{"sourceID": "authority", "locator": "Sources of doctrine; individual statements; central and peripheral doctrines"}],
    "presentation": {"shuffleLeftItems": True, "shuffleRightItems": True, "requireIndependentOrder": True,
                      "interactionModes": ["tap_to_pair", "drag_to_pair"],
                      "accessibility": "Every pair must be makeable by tapping a left item, then a right item; dragging is optional."},
    "overlapsWithQuestionIDs": [c1, c2, c3, b5, f"{MOD}-bank-q001", f"{MOD}-bank-q004"],
})
match3 = qs[-1]["id"]

bank = {
    "schemaVersion": "1.1", "contentVersion": 1, "status": "draft_pending_review",
    "subjectID": "lds-doctrine", "courseID": COURSE, "moduleID": MOD, "title": "Sources and authority",
    "objectives": [{"id": OBJ, "text": "Distinguish canon, institutional teaching, commentary, and historical evidence."}],
    "sources": SOURCES, "questions": qs,
    "review": {"note": "Authored by Claude for Hearken's v2 course; scripture wording checked against the app's text and the guide read in full. Needs Steve's review before shipping."},
}

# Existing reviewed items this module uses (ids from lds-doctrine-c01-m01.json and its matching bank).
EX = {k: f"{MOD}-bank-q{k}" for k in ["001", "002", "004", "006", "008", "009", "010"]}
EXM1, EXM2 = f"{MOD}-match-q001", f"{MOD}-match-q002"

article_md = open(os.path.join(os.path.dirname(__file__), "article.md")).read()
module = {
    "id": MOD, "number": "1.1", "title": "Sources and authority",
    "summary": "Tell canon, institutional teaching, commentary and historical records apart, and say what each can show.",
    "objectives": [{"id": OBJ, "text": "Distinguish canon, institutional teaching, commentary, and historical evidence."}],
    "article": {
        "id": f"{MOD}-article", "title": "Sources and authority", "minutes": 15, "xp": 50,
        "markdown": article_md,
        "sectionChecks": [
            {"section": "Why the kind of source matters", "questionIDs": [EX["002"]]},
            {"section": "The standard works: an open canon", "questionIDs": [EX["001"], d6]},
            {"section": "Institutional teaching: how the Church speaks today", "questionIDs": [EX["004"], b4]},
            {"section": "Commentary: useful, but someone's reading", "questionIDs": [EX["010"]]},
            {"section": "Historical records: what someone said, when", "questionIDs": [d5]},
            {"section": "Central and peripheral teachings", "questionIDs": [c6]},
            {"section": "The source ledger", "questionIDs": [d4]},
        ],
    },
    "readings": [
        {"id": f"{MOD}-reading-aof", "title": "Articles of Faith 1:1–13", "minutes": 10, "xp": 40,
         "passages": [{"chapterID": "pgp.a-of-f.1", "from": 1, "to": 13}],
         "focusQuestions": ["Which articles describe God, Christ and salvation, and which describe the Church and its conduct?",
                            "Which two articles talk about scripture and revelation themselves?",
                            "What important topics do the thirteen articles leave out?"],
         "quiz": {"questionPool": [a1, a2, a3, a4, a5, a6, EX["006"], EX["008"]], "questionCount": 5, "passCount": 4, "maxTrueFalse": 1}},
        {"id": f"{MOD}-reading-dc", "title": "Doctrine and Covenants 1:37–39 and 68:1–4", "minutes": 8, "xp": 40,
         "passages": [{"chapterID": "dc-testament.dc.1", "from": 37, "to": 39}, {"chapterID": "dc-testament.dc.68", "from": 1, "to": 4}],
         "focusQuestions": ["To whom was section 68 first addressed, and how is it extended to others?",
                            "What condition does 68:4 attach to calling words scripture?",
                            "What does 1:38 say about the Lord's voice and his servants' voices?"],
         "quiz": {"questionPool": [b1, b2, b3, b4, b5, b6, b7], "questionCount": 5, "passCount": 4, "maxTrueFalse": 1}},
        {"id": f"{MOD}-reading-guide", "title": "Approaching Latter-day Saint Doctrine", "minutes": 12, "xp": 40,
         "source": {"title": "Approaching Latter-day Saint Doctrine", "url": "https://newsroom.churchofjesuschrist.org/article/approaching-mormon-doctrine",
                    "publisher": "Church Newsroom", "date": "2007-05-04", "perspective": "Latter-day Saint institutional"},
         "focusQuestions": ["Who does the guide say establishes doctrine, and where does it say doctrine is found?",
                            "What does it say about a single statement by one leader?",
                            "How does it tell central teachings from peripheral ones?"],
         "quiz": {"questionPool": [c1, c2, c3, c4, c5, c7, EX["009"]], "questionCount": 5, "passCount": 4, "maxTrueFalse": 1}},
    ],
    "practice": {"id": f"{MOD}-practice", "title": "What kind of source is this?", "minutes": 10, "xp": 30, "questionID": EXM1},
    "moduleQuiz": {
        "id": f"{MOD}-quiz", "minutes": 15, "xp": 80, "questionCount": 12, "passCount": 10, "maxTrueFalse": 2, "maxMatching": 1,
        "questionPool": sorted(set([q["id"] for q in qs] + list(EX.values()) + [EXM1, EXM2])),
    },
    "essay": {
        "id": f"{MOD}-essay", "minutes": 20, "xp": 60, "minWords": 150, "maxWords": 250, "revisionsBeforeCompletion": 3,
        "rubric": [
            {"id": "accuracy", "title": "Accuracy", "full": "States each teaching as its sources do", "partial": "Mostly accurate, with a loose or blurred point", "none": "Misstates the teaching, or answers a different question"},
            {"id": "evidence", "title": "Evidence", "full": "Cites an assigned source with chapter and verse, or title and section", "partial": "Names a source without a precise reference", "none": "No source, or a source that doesn't support the claim"},
            {"id": "precision", "title": "Precision and fairness", "full": "Scopes each claim to what its source shows and labels commentary as commentary", "partial": "One claim is broader than its source", "none": "Sweeping claims, or treats commentary or history as doctrine"},
        ],
        "prompts": [
            {"id": f"{MOD}-essay-p1", "prompt": "Classify four sources: a passage from the Doctrine and Covenants, a general conference address, an 1880 diary entry, and a popular devotional book. For each, name its category and explain what it can and cannot show.",
             "guide": "Scripture is canonical text and can show what the canon says. The conference address is institutional teaching: it shows how the Church teaches, but it is not part of the standard works. The diary is a historical record of what its writer reported at that time. The devotional book is one author's commentary. Strong answers avoid ranking sources purely by the author's title and note that each answers a different question."},
            {"id": f"{MOD}-essay-p2", "prompt": "A friend shares a quotation from a nineteenth-century sermon and says, “This is Mormon doctrine.” Using the Church's guide and one passage you read in this module, explain how you would decide what the quotation shows.",
             "guide": "Identify it as a single statement by one leader, which the guide says may be a personal view. Check whether the teaching appears in the standard works, official declarations and proclamations, or consistent current publications. A strong answer may use D&C 68:4 accurately (scripture in the broad sense is tied to being moved upon by the Holy Ghost) without claiming it canonizes every sermon, and records the sermon's date and setting."},
            {"id": f"{MOD}-essay-p3", "prompt": "Explain what an “open canon” means for Latter-day Saints, using Article of Faith 9 and one example of the canon growing. Then explain how a careful student should word a claim about a teaching that could develop over time.",
             "guide": "Article of Faith 9 expects further revelation. Examples: the revelations accepted in 1976 (now D&C 137 and 138) or Official Declaration 2 in 1978, presented to and accepted by a general conference. The guide allows for future additions or changes. Careful wording dates and attributes the claim (“As of 2026, the Church teaches… in [source]”) rather than claiming it has always or will always be so."},
        ],
    },
}

os.makedirs(os.path.join(OUT, "question-banks"), exist_ok=True)
json.dump(bank, open(os.path.join(OUT, "question-banks", f"{MOD}-additions.json"), "w"), ensure_ascii=False, indent=2)
json.dump(module, open(os.path.join(OUT, "module.json"), "w"), ensure_ascii=False, indent=2)
print(len(qs), "new questions;", len(module["moduleQuiz"]["questionPool"]), "in the module pool")
