import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from v2lib import Module

M = Module("lds-doctrine-c01-m02", "1.2", "lds-doctrine-c01", "Making careful claims",
           "State a doctrinal claim with its source and its limit, using Joseph Smith's First Vision accounts.",
           "lds-doctrine-c01-m01-objective-02", "State a doctrinal claim with a source and a limit.")
JSH = M.source("jsh-1-1-20", "Joseph Smith—History 1:1–20", passage={"chapterID": "pgp.js-h.1", "from": 1, "to": 20})
FVA = M.source("first-vision-accounts", "First Vision Accounts (Church topics page)",
               url="https://www.churchofjesuschrist.org/study/manual/gospel-topics/first-vision-accounts?lang=eng",
               perspective="Latter-day Saint institutional")
ART = "article"
METHOD = "Original Hearken reading method grounded in the cited sources"
INST = "Latter-day Saint institutional"

# Reading A: Joseph Smith—History 1:1–20
a = [
    M.mc("jsh-purpose", "According to Joseph Smith—History 1:1, why did Joseph Smith write this history?",
         ["To answer reports circulating about the Church and give inquirers the facts", "To record a revelation addressed to Church leaders",
          "To settle a debate with a Methodist minister", "To explain the Book of Mormon's translation"], 1,
         "Verse 1 says he wrote because of “the many reports” in circulation, to “put all inquirers after truth in possession of the facts.” It does not present the history as a revelation, a debate record or an account of translation.",
         [(JSH, "JS—H 1:1")]),
    M.mc("jsh-date", "According to Joseph Smith—History 1:2, when was this account written?",
         ["In 1838, the eighth year after the Church was organized", "In 1820, right after the vision", "In 1832, as his first written account", "In 1844, shortly before his death"], 1,
         "Verse 2 dates the writing to “now [1838] the eighth year since the organization” of the Church. The vision itself was in 1820, and the earliest written account is from 1832.",
         [(JSH, "JS—H 1:2")]),
    M.mc("jsh-james", "Which passage does Joseph Smith say came to him with great power and led him to pray?",
         ["James 1:5", "Matthew 7:7", "Moroni 10:4", "John 17:3"], 1,
         "Verses 11–12 quote James 1:5, “If any of you lack wisdom, let him ask of God.” The other passages are not cited in this account.",
         [(JSH, "JS—H 1:11–12")]),
    M.tf("jsh-methodist", "In Joseph Smith—History 1:8, Joseph says his mind had become somewhat partial to the Methodist sect.", True,
         "Verse 8 says, “my mind became somewhat partial to the Methodist sect, and I felt some desire to be united with them.”",
         [(JSH, "JS—H 1:8")]),
    M.mc("jsh-introduction", "In the 1838 account, what did one Personage say, pointing to the other?",
         ["“This is My Beloved Son. Hear Him!”", "“Join none of them.”", "“Thy sins are forgiven thee.”", "“Behold, I am Jesus Christ.”"], 1,
         "Verse 17 records the introduction. Being told to join none of the churches comes later, in verses 19–20; the other two phrases are not in this account.",
         [(JSH, "JS—H 1:17")]),
    M.mc("jsh-19-attribution", "Which sentence attributes Joseph Smith—History 1:19 most accurately?",
         ["In Joseph Smith's 1838 account, the Personage tells him to join none of the churches and condemns their creeds",
          "Latter-day Saints teach that every Christian is personally corrupt",
          "Joseph Smith's 1832 account says the creeds were an abomination",
          "The Church's guide to doctrine says all creeds are abominations"], 1,
         "The careful sentence names the account and the speaker within it, and keeps the verse's answer tied to Joseph's question about which church to join. The others stretch the verse into a claim about every person, move it to a different account, or attribute it to a different source.",
         [(JSH, "JS—H 1:18–19"), (ART, "Reading a narrative carefully")], difficulty="application", perspective=METHOD),
    M.tf("jsh-date-event", "According to Joseph Smith—History 1:14, the vision happened early in the spring of 1820.", True,
         "Verse 14 says it was “early in the spring of eighteen hundred and twenty.”",
         [(JSH, "JS—H 1:14")]),
    M.mc("jsh-20-kind", "In verse 20, Joseph writes that “the adversary was aware” early in his life that he would disturb his kingdom. What kind of claim is this?",
         ["Joseph's interpretation of his own experience", "Words spoken to Joseph by the Personage", "An institutional statement of doctrine", "A historian's conclusion about the 1820s"], 1,
         "The sentence is the narrator reflecting on what happened to him, offered as his own reading. It is not reported speech, an institutional statement or a historian's judgment.",
         [(JSH, "JS—H 1:20"), (ART, "Reading a narrative carefully")], difficulty="application", perspective=METHOD),
]

# Reading B: First Vision Accounts page
b = [
    M.mc("fva-count", "According to the Church's page on First Vision accounts, how many accounts did Joseph Smith himself leave?",
         ["Four", "One", "Two", "Nine"], 1,
         "The page says Joseph left four accounts, and that five of his contemporaries also wrote accounts after hearing him; nine is the total of both, not his own.",
         [(FVA, "Accounts")], perspective=INST),
    M.mc("fva-canonized", "Which account of the First Vision is canonized?",
         ["The 1838 account in Joseph Smith—History, in the Pearl of Great Price", "The earliest, 1832 account", "A journal entry", "An account written by a contemporary who heard him"], 1,
         "The canonized account is the one in Joseph Smith—History. The 1832 account and the journal entry were not published in Joseph's lifetime, and contemporaries' accounts are not canonized.",
         [(FVA, "Published and canonized accounts")], perspective=INST),
    M.mc("fva-1832-reason", "According to the Church's page, what reason for praying does the 1832 account emphasize?",
         ["Seeking forgiveness of his sins", "Learning which church to join", "Finding ancient records", "Learning the nature of the Godhead"], 1,
         "The page says the 1832 account emphasizes forgiveness; later accounts emphasize the question of which church to join. The page describes the two concerns as closely related.",
         [(FVA, "How the accounts differ")], perspective=INST),
    M.mc("fva-why-differ", "How does the Church's page explain the differences among the accounts?",
         ["Different audiences and purposes, and Joseph's growing understanding; historians expect such variation",
          "Later accounts were invented to replace the first one",
          "Only the 1838 account is reliable, so the others should be ignored",
          "The accounts do not actually differ"], 1,
         "The page attributes the differences to audience, purpose and growing understanding, and notes that historians expect variation in retellings. It does not dismiss any account or deny the differences.",
         [(FVA, "Why the accounts differ")], difficulty="application", perspective=INST),
    M.tf("fva-decade", "According to the Church's page, all the First Vision accounts were written more than a decade after the event.", True,
         "The page states that every account was written more than ten years after 1820.",
         [(FVA, "Dates")], perspective=INST),
    M.mc("fva-agree", "According to the Church's page, what do all the accounts emphasize?",
         ["Jesus Christ, who answers Joseph's questions", "The Father introducing the Son", "Angels accompanying the vision", "The exact date of the vision"], 1,
         "The page says the accounts all emphasize Christ. The introduction by the Father is not in the 1832 account, angels appear in one account, and dates are given differently.",
         [(FVA, "How the accounts agree")], perspective=INST),
    M.tf("fva-1832-published", "The 1832 account of the First Vision was published during Joseph Smith's lifetime.", False,
         "The page says the 1832 account and a journal entry were unpublished; the Church published them in the 1960s.",
         [(FVA, "Published and canonized accounts")], perspective=INST),
]

# Article and module quiz
slip1 = M.mc("slip-everyone", "A passage teaches X. Which sentence states that without overreaching?",
             ["“This passage teaches X.”", "“Latter-day Saints believe X.”", "“All Christians believe X.”", "“Most members have always believed X.”"], 1,
             "A passage supports a claim about what it teaches. Claims about what members or Christians believe need evidence about those people.",
             [(ART, "Three common slips")], perspective=METHOD)
slip2 = M.mc("slip-always", "An 1880 sermon says X. Which sentence stays within the source?",
             ["“An 1880 sermon taught X.”", "“The Church has always taught X.”", "“The Church teaches X today.”", "“Latter-day Saints no longer believe X.”"], 1,
             "A dated sermon supports a claim about that sermon. Claims about always, today or no longer need other evidence.",
             [(ART, "Three common slips")], perspective=METHOD)
verb = M.mc("verb-narrative", "Which sentence uses the most accurate verb for Joseph Smith—History 1:16?",
            ["Joseph Smith—History 1:16 describes a pillar of light", "Joseph Smith—History 1:16 proves that every vision includes light",
             "Joseph Smith—History 1:16 requires readers to accept the vision", "Joseph Smith—History 1:16 shows that all accounts mention light"], 1,
            "“Describes” fits a narrative. The others make claims the verse does not make, about every vision, about readers, or about other accounts.",
            [(JSH, "JS—H 1:16"), (ART, "Writing with the right confidence")], perspective=METHOD)
several = M.mc("several-accounts", "When the First Vision accounts differ, which claim is most careful?",
               ["“In the 1838 account, Joseph describes two Personages.”", "“Joseph always said he saw two beings.”",
                "“No account mentions the Father.”", "“Every account includes ‘This is My Beloved Son.’”"], 1,
               "Naming the account keeps the claim accurate. The 1832 account refers to “the Lord” and lacks the introduction, so “always” and “every account” overreach; the 1838 account does describe the Father.",
               [(FVA, "How the accounts differ"), (ART, "When there are several accounts")], difficulty="application", perspective=METHOD)
cond = M.tf("quote-condition", "When a verse begins with a condition, a careful quotation keeps the condition.", True,
            "Dropping a condition changes what the verse claims; the article's first habit for quoting is to quote enough to keep the meaning.",
            [(ART, "Quoting in context")], perspective=METHOD)
verbs = M.match("verb-matching", "Choose the verb", "Match each kind of statement to the verb that fits it best.",
                [("Repeating what a source says in so many words", "States"),
                 ("Reporting what a canonical or institutional source presents as doctrine", "Teaches"),
                 ("Summarizing events in a narrative", "Describes"),
                 ("Offering your own inference from the evidence", "Suggests")],
                "Each verb signals how close a claim is to its source, from direct statement to the writer's own inference.",
                [(ART, "Writing with the right confidence")], overlaps=[verb], perspective=METHOD)
kinds = M.match("jsh-claim-kinds", "What kind of claim is this?", "Match each line from Joseph Smith—History 1 to the kind of claim it makes.",
                [("“There was … an unusual excitement on the subject of religion” (verse 5)", "A circumstance the narrator reports"),
                 ("“Never did any passage of scripture come with more power to the heart of man” (verse 12)", "The narrator's inner experience"),
                 ("He was told he “must join none of them” (verse 19)", "Words reported as spoken to him"),
                 ("“The adversary was aware … that I was destined to prove a disturber” (verse 20)", "The narrator's interpretation")],
                "A narrative makes different kinds of claims, and each is cited differently: as reported circumstance, as the narrator's experience, as speech within the account, or as the narrator's own reading.",
                [(JSH, "JS—H 1:5, 12, 19, 20"), (ART, "Reading a narrative carefully")], overlaps=[a[7]], difficulty="application", perspective=METHOD)

EX = {k: f"lds-doctrine-c01-m01-bank-q{k}" for k in ["003", "005", "007"]}
M.add_to_pool(*EX.values())

M.set_article("article.md", 16, {
    "From source to sentence": [EX["005"]],
    "The four fields at work": [EX["007"]],
    "Three common slips": [slip1, slip2],
    "Reading a narrative carefully": [a[7]],
    "When there are several accounts": [several],
    "Quoting in context": [cond],
    "Writing with the right confidence": [verb],
})
M.reading("jsh", "Joseph Smith—History 1:1–20", 15,
          ["Which verses describe circumstances, and which describe Joseph's own thoughts and feelings?",
           "What question did Joseph bring to his prayer, and what answer does the account give?",
           "Where does Joseph comment on the meaning of what happened to him?"],
          a, passages=[{"chapterID": "pgp.js-h.1", "from": 1, "to": 20}])
M.reading("accounts", "First Vision Accounts", 12,
          ["How many accounts are there, and which one is canonized?",
           "Where do the accounts agree, and where do they differ?",
           "How does the page explain the differences?"],
          b, source={"title": "First Vision Accounts", "url": "https://www.churchofjesuschrist.org/study/manual/gospel-topics/first-vision-accounts?lang=eng",
                     "publisher": "The Church of Jesus Christ of Latter-day Saints", "perspective": INST})
M.set_practice("What kind of claim is this?", kinds)
M.set_essay([
    ("Rewrite these three claims so each one names its source and its limit: (1) “Mormons believe Joseph Smith saw God and Jesus in 1820.” (2) “The Church teaches that every other church is corrupt.” (3) “Joseph Smith always told the First Vision the same way.”",
     "(1) Attribute to the 1838 account: in Joseph Smith—History 1:14–17, Joseph describes two Personages in the spring of 1820. (2) Tie JS—H 1:19 to the account, its speaker and Joseph's question about which church to join; do not turn it into a claim about every individual without other sources. (3) Joseph left four accounts that differ in emphasis (the 1832 account stresses forgiveness and refers to “the Lord”) while all center on Christ, per the Church's page."),
    ("Explain why a careful student shouldn't blend the First Vision accounts into one story. Using the Church's page and Joseph Smith—History 1, show how you would write one claim where the accounts agree and one where they differ.",
     "Blending hides which account says what. Agreement: all center on Jesus Christ answering Joseph (Church page). Difference: the 1832 account emphasizes forgiveness and refers to “the Lord,” while the 1838 account (JS—H 1:17) describes two Personages and the introduction. Strong answers name the account in each claim and may note the page's explanation (audience, purpose, growing understanding)."),
    ("Using Joseph Smith—History 1:1–20, give one example each of a reported circumstance, the narrator's inner experience, words reported as spoken to him, and the narrator's interpretation. Explain how you would cite each kind.",
     "Circumstance: religious excitement (v5) or family joining the Presbyterians (v7). Inner experience: James 1:5's power (v12) or uncertainty (v8). Reported speech: “This is My Beloved Son” (v17) or “join none of them” (v19). Interpretation: the adversary was aware (v20). Citing: report circumstances as the account's description, inner experience as Joseph's report of it, speech with its speaker in the account, interpretation as Joseph's own reading."),
])
M.build(os.path.dirname(os.path.abspath(__file__)))
