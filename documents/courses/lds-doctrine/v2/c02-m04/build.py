import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from v2lib import Module

M = Module("lds-doctrine-c02-m04", "2.4", "lds-doctrine-c02", "The Holy Ghost and enduring to the end",
           "Describe what Latter-day Saint scripture teaches about the gift of the Holy Ghost, prayer and enduring to the end.",
           "lds-doctrine-c02-m04-objective-01", "Describe the gift of the Holy Ghost, prayer and enduring to the end as the doctrine of Christ presents them, attributing claims about spiritual experience to their sources.")
HG = M.source("2ne32-moro10", "2 Nephi 32:1–9; Moroni 10:3–5; John 14:26", passage={"chapterID": "bofm.2-ne.32", "from": 1, "to": 9})
AL = M.source("alma-36", "Alma 36:12–24", passage={"chapterID": "bofm.alma.36", "from": 12, "to": 24})
DC = M.source("dc-130-23", "Doctrine and Covenants 130:22–23", passage={"chapterID": "dc-testament.dc.130", "from": 22, "to": 23})
ART = "article"
METHOD = "Original Hearken reading method grounded in the cited sources"

a = [
    M.mc("2ne32-angels", "According to 2 Nephi 32:3, how do angels speak?",
         ["By the power of the Holy Ghost, so they speak the words of Christ", "Only in dreams", "In a language no one understands", "Only to prophets"], 1,
         "Verse 3: “Angels speak by the power of the Holy Ghost; wherefore, they speak the words of Christ.”",
         [(HG, "2 Nephi 32:3")]),
    M.mc("2ne32-feast", "What does Nephi tell his readers to feast upon in 2 Nephi 32:3?",
         ["The words of Christ", "The law of Moses", "The records of their fathers", "The fruit of the tree of life"], 1,
         "Verse 3: “feast upon the words of Christ; for behold, the words of Christ will tell you all things what ye should do.”",
         [(HG, "2 Nephi 32:3")]),
    M.mc("2ne32-5", "According to 2 Nephi 32:5, what will the Holy Ghost do for those who enter in by the way?",
         ["Show them all things what they should do", "Remove all their trials", "Make prayer unnecessary", "Give them a new body"], 1,
         "Verse 5: “if ye will enter in by the way, and receive the Holy Ghost, it will show unto you all things what ye should do.”",
         [(HG, "2 Nephi 32:5")]),
    M.mc("2ne32-8", "According to 2 Nephi 32:8, what does the evil spirit teach?",
         ["That a man must not pray", "That a man must pray always", "That a man should feast on the words of Christ", "That a man should be baptized"], 1,
         "Verse 8: “the evil spirit teacheth not a man to pray, but teacheth him that he must not pray.”",
         [(HG, "2 Nephi 32:8")]),
    M.mc("2ne32-9", "According to 2 Nephi 32:9, to whom and in whose name should people pray?",
         ["To the Father, in the name of Christ", "To Christ, in the name of the Father", "To the Holy Ghost, in the name of Christ", "To angels, in the name of God"], 1,
         "Verse 9: “ye shall pray unto the Father in the name of Christ, that he will consecrate thy performance unto thee.”",
         [(HG, "2 Nephi 32:9")]),
    M.mc("moro10-conditions", "Which conditions does Moroni 10:4 attach to asking God?",
         ["A sincere heart, real intent, and faith in Christ", "Reading the book twice", "Asking in a temple", "No conditions"], 1,
         "Verse 4: “if ye shall ask with a sincere heart, with real intent, having faith in Christ.” Verse 3 also asks readers to remember and ponder.",
         [(HG, "Moroni 10:3–4")]),
    M.mc("moro10-whom", "Whom does Moroni 10:4 tell readers to ask?",
         ["God, the Eternal Father, in the name of Christ", "Their bishop", "Moroni himself", "The Holy Ghost, in the name of the Father"], 1,
         "Verse 4: “ask God, the Eternal Father, in the name of Christ, if these things are not true.”",
         [(HG, "Moroni 10:4")]),
    M.tf("moro10-5", "Moroni 10:5 says that by the power of the Holy Ghost people may know the truth of all things.", True,
         "Verse 5: “by the power of the Holy Ghost ye may know the truth of all things.”",
         [(HG, "Moroni 10:5")]),
    M.mc("john14-26", "According to John 14:26, what will the Comforter, the Holy Ghost, do?",
         ["Teach all things and bring to remembrance what Jesus said", "Replace the apostles", "Write a new gospel", "Judge the world"], 1,
         "Verse 26: “he shall teach you all things, and bring all things to your remembrance, whatsoever I have said unto you.”",
         [(HG, "John 14:26")]),
    M.mc("moro10-summary", "Which summary of Moroni 10:3–5 is most accurate?",
         ["Moroni promises that those who ask God sincerely, with real intent and faith in Christ, will be shown the truth by the power of the Holy Ghost",
          "Moroni promises that every reader will believe the Book of Mormon", "Moroni says the book's truth cannot be known",
          "Moroni says reading is enough without asking"], 1,
         "The accurate summary keeps the conditions. The others drop them, overstate the promise, or contradict it.",
         [(HG, "Moroni 10:3–5"), (ART, "Moroni's promise")], difficulty="application", perspective=METHOD),
]

b = [
    M.mc("alma36-16", "According to Alma 36:16, how long was Alma racked with torment?",
         ["Three days and three nights", "Forty days", "Seven years", "One night"], 1,
         "Verse 16: “for three days and for three nights was I racked.”",
         [(AL, "Alma 36:16")]),
    M.mc("alma36-17", "What did Alma remember in Alma 36:17?",
         ["His father's prophecy of Jesus Christ, who would atone for the sins of the world", "A verse from Isaiah",
          "The words of an angel to Nephi", "The law of Moses"], 1,
         "Verse 17: he remembered his father prophesying “concerning the coming of one Jesus Christ, a Son of God, to atone for the sins of the world.”",
         [(AL, "Alma 36:17")]),
    M.mc("alma36-18", "What does Alma cry within his heart in Alma 36:18?",
         ["“O Jesus, thou Son of God, have mercy on me”", "“Why hast thou forsaken me?”", "“I will never sin again”", "“Let me be banished”"], 1,
         "Verse 18 gives his cry. Verse 15 records his earlier wish to be banished, before he remembered Christ.",
         [(AL, "Alma 36:15–18")]),
    M.mc("alma36-20", "How does Alma describe what followed in Alma 36:20?",
         ["Joy and marvelous light", "Silence and darkness", "Continued torment", "A long journey"], 1,
         "Verse 20: “oh, what joy, and what marvelous light I did behold.”",
         [(AL, "Alma 36:20")]),
    M.tf("alma36-24", "In Alma 36:24, Alma says he has labored so that others might be born of God and filled with the Holy Ghost.", True,
         "Verse 24 says he labored “that they might also be born of God, and be filled with the Holy Ghost.”",
         [(AL, "Alma 36:24")]),
    M.mc("alma36-kind", "How should a careful student describe Alma 36?",
         ["As Alma's account, told to his son, of his own repentance, which Latter-day Saints use to teach about repentance",
          "As a historian's report of a public event", "As a list of commandments", "As an account of Nephi's conversion"], 1,
         "It is a first-person narrative of experience addressed to Helaman. Both that and its use in teaching are accurate, and they should be kept distinct.",
         [(AL, "Alma 36"), (ART, "Repentance and joy: Alma 36")], difficulty="application", perspective=METHOD),
    M.mc("alma36-22", "What does Alma say he thought he saw in Alma 36:22?",
         ["God sitting upon his throne, surrounded by concourses of angels", "His father in a dream", "The tree of life", "The plates of brass"], 1,
         "Verse 22: “methought I saw, even as our father Lehi saw, God sitting upon his throne, surrounded with numberless concourses of angels.”",
         [(AL, "Alma 36:22")]),
]

tarry = M.mc("dc130-23-caution", "What caution does Doctrine and Covenants 130:23 give about receiving the Holy Ghost?",
             ["The Holy Ghost may descend upon a person and not tarry with them", "The Holy Ghost can never be received",
              "The Holy Ghost only comes once", "The Holy Ghost has a body"], 1,
             "Verse 23: “A man may receive the Holy Ghost, and it may descend upon him and not tarry with him.” Verse 22 says the Holy Ghost is a personage of Spirit.",
             [(DC, "D&C 130:22–23"), (ART, "The gift of the Holy Ghost")])
gift = M.mc("influence-gift", "How does Latter-day Saint teaching distinguish the gift of the Holy Ghost?",
            ["It is given after baptism by the laying on of hands, distinct from the influence anyone may feel", "It is given at birth to everyone",
             "It is the same as reading scripture", "It is given only to apostles"], 1,
            "Latter-day Saint teaching describes the gift as conferred after baptism (Article of Faith 4), distinct from the Holy Ghost's influence, which anyone may feel.",
            [(ART, "The gift of the Holy Ghost")], perspective=METHOD)
endure = M.mc("endure-content", "According to 2 Nephi 31:20, what does enduring to the end involve?",
              ["Pressing forward with steadfastness in Christ, hope, love of God and all men, and feasting on the word", "Only avoiding sin",
               "Waiting without effort", "Being baptized again each year"], 1,
              "Verse 20 gives enduring that content; it continues the same pattern as the rest of the doctrine of Christ.",
              [(ART, "Enduring to the end")])
moroni7 = M.mc("moroni7-16", "Moroni 7:16 says everything that invites to do good and persuades to believe in Christ is sent by the power and gift of Christ. What is that verse about?",
               ["The Spirit of Christ given to every person, a principle for judging good from evil", "The gift of the Holy Ghost after baptism",
                "Angels appearing to prophets", "The priesthood"], 1,
               "Verse 16 begins, “the Spirit of Christ is given to every man, that he may know good from evil.” Cite it as a related source, not as a description of the gift of the Holy Ghost.",
               [(ART, "Moroni's promise")], difficulty="application", perspective=METHOD)
belief = M.tf("not-assessed", "This course assesses whether a learner has had a spiritual experience.", False,
              "The course assesses whether you can describe what the sources teach about the Holy Ghost accurately; it never assesses personal experience or belief.",
              [(ART, "After the gate")], perspective=METHOD)
roles = M.match("hg-promises", "What the Holy Ghost does", "Match each description to the passage that gives it.",
                [("Teach you all things, and bring all things to your remembrance", "John 14:26"),
                 ("Show unto you all things what ye should do", "2 Nephi 32:5"),
                 ("Manifest the truth of it unto you", "Moroni 10:4"),
                 ("Beareth record of the Father and me", "3 Nephi 11:32")],
                "Each passage describes a different aspect of the Holy Ghost's work; citing the right one keeps a claim precise.",
                [(HG, "John 14:26; 2 Nephi 32:5; Moroni 10:4"), (ART, "Who the Holy Ghost is")], overlaps=[a[2], a[8]])

M.set_article("article.md", 16, {
    "After the gate": [belief],
    "Who the Holy Ghost is": [a[8]],
    "The gift of the Holy Ghost": [tarry],
    "\"Feast upon the words of Christ\"": [a[1]],
    "Moroni's promise": [a[9]],
    "Repentance and joy: Alma 36": [b[5]],
    "Enduring to the end": [endure],
    "Describing it well": [gift],
})
M.reading("2ne32-moroni10", "2 Nephi 32:1–9, Moroni 10:3–5 and John 14:26", 12,
          ["What two sources of guidance does Nephi name in 2 Nephi 32:3–5?",
           "What does Nephi teach about prayer, and to whom it is offered?",
           "What conditions does Moroni attach to his promise?"],
          a, passages=[{"chapterID": "bofm.2-ne.32", "from": 1, "to": 9}, {"chapterID": "bofm.moro.10", "from": 3, "to": 5}, {"chapterID": "nt.john.14", "from": 26, "to": 26}])
M.reading("alma36", "Alma 36:12–24", 10,
          ["What did Alma experience before he remembered his father's words?",
           "What did he remember, and what did he cry out?",
           "What changed afterward, and what did he do with his life?"],
          b, passages=[{"chapterID": "bofm.alma.36", "from": 12, "to": 24}])
M.set_practice("What the Holy Ghost does", roles)
M.set_essay([
    ("Describe what Latter-day Saint scripture teaches about the Holy Ghost's role after baptism. Cite at least two passages and keep each claim attributed.",
     "Gift after baptism (2 Ne 31:12–13; Article of Faith 4); shows all things to do (2 Ne 32:5); teaches and brings to remembrance (John 14:26); witnesses of Father and Son (3 Ne 11:32; 2 Ne 31:18); may not tarry (D&C 130:23). Describes teachings, not anyone's experience."),
    ("Explain Moroni's promise in Moroni 10:3–5, including all its conditions, and show how a summary that drops the conditions misdescribes it.",
     "Remember and ponder (v3); ask God the Eternal Father in Christ's name, with a sincere heart, real intent and faith in Christ (v4); truth manifested by the Holy Ghost (v4–5). A summary like “everyone who reads it will believe” drops the conditions and overstates the promise."),
    ("Using 2 Nephi 31:19–20 and 2 Nephi 32, explain what “enduring to the end” involves, and why Nephi says the path isn't finished at baptism.",
     "Nephi asks if all is done and says no (31:19); pressing forward with steadfastness in Christ, hope and love, feasting on the word (31:20); relying on Christ's merits (31:19); the Holy Ghost and words of Christ guide (32:3, 5); praying always to the Father in Christ's name (32:8–9)."),
])
M.build(os.path.dirname(os.path.abspath(__file__)))
