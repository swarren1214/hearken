import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from v2lib import Module

M = Module("lds-doctrine-c01-m03", "1.3", "lds-doctrine-c01", "The Godhead: three distinct beings",
           "Explain the Latter-day Saint teaching that the Father, Son and Holy Ghost are distinct beings, one in purpose.",
           "lds-doctrine-c01-m02-objective-01", "Explain the LDS distinction between unity and identity.")
DC = M.source("dc-130", "Doctrine and Covenants 130", passage={"chapterID": "dc-testament.dc.130", "from": 1, "to": 23})
NT = M.source("nt-scenes", "Matthew 3:13–17; Acts 7:55–56; John 17:20–26", passage={"chapterID": "nt.matt.3", "from": 13, "to": 17})
GH = M.source("godhead", "Godhead (Gospel Topics)", url="https://www.churchofjesuschrist.org/study/manual/gospel-topics/godhead?lang=eng",
              perspective="Latter-day Saint institutional")
ART = "article"
METHOD = "Original Hearken reading method grounded in the cited sources"
INST = "Latter-day Saint institutional"
OLD = {k: f"lds-doctrine-c01-m02-bank-q{k}" for k in ["001", "002", "003", "005", "007", "009"]}
OLDM = "lds-doctrine-c01-m02-match-q001"

# Reading A: D&C 130
a = [
    M.mc("dc130-reason", "According to Doctrine and Covenants 130:22, why is the Holy Ghost a personage of Spirit rather than embodied?",
         ["“Were it not so, the Holy Ghost could not dwell in us.”", "Because the Holy Ghost is not a member of the Godhead",
          "Because only the Father has a body", "The verse gives no reason"], 1,
         "Verse 22 ends with its reason: “Were it not so, the Holy Ghost could not dwell in us.” It does not remove the Holy Ghost from the Godhead, and it says the Son also has a body.",
         [(DC, "D&C 130:22")]),
    M.tf("dc130-tarry", "Doctrine and Covenants 130:23 says a person may receive the Holy Ghost, and it may descend upon them and not tarry.", True,
         "Verse 23: “A man may receive the Holy Ghost, and it may descend upon him and not tarry with him.”",
         [(DC, "D&C 130:23")]),
    M.mc("dc130-setting", "Section 130 collects items of instruction Joseph Smith gave at Ramus, Illinois, in 1843, on several subjects. What does that mean for citing it?",
         ["Cite the specific verse that supports your claim, not the section as a whole", "None of it should be treated as canonical",
          "Every verse in it is about the Godhead", "It should be cited only alongside a conference talk"], 1,
         "The section is canonical, but its verses address different subjects, so the precise verse is the right citation. It is not limited to the Godhead, and it needs no other source to be cited.",
         [(DC, "D&C 130"), (ART, "Bodies and spirit: Doctrine and Covenants 130")], difficulty="application", perspective=METHOD),
    M.mc("dc130-man", "According to Doctrine and Covenants 130:1, what shall we see when the Savior appears?",
         ["That he is a man like ourselves", "That he is a spirit without form", "That he is the Father", "That he cannot be seen"], 1,
         "Verse 1: “we shall see that he is a man like ourselves.” The other options contradict the verse or say something it doesn't.",
         [(DC, "D&C 130:1")]),
    M.mc("dc130-limit", "A writer claims Doctrine and Covenants 130:22 explains everything about the nature of God. Which response is most accurate?",
         ["The verse states that the Father and Son have bodies and the Holy Ghost is a personage of Spirit; further detail is interpretation",
          "The verse says nothing about the Father", "The verse is not canonical", "The verse describes the Father's body in detail"], 1,
         "Verse 22 makes specific statements and leaves much open. Detailed claims beyond it should be marked as interpretation. It does speak of the Father, it is canonical, and it gives no detailed description.",
         [(DC, "D&C 130:22"), (ART, "Bodies and spirit: Doctrine and Covenants 130")], difficulty="application", perspective=METHOD),
    M.tf("dc130-sociality", "Doctrine and Covenants 130:2 says the same sociality that exists among people here will exist there, coupled with eternal glory.", True,
         "Verse 2: “that same sociality which exists among us here will exist among us there, only it will be coupled with eternal glory.”",
         [(DC, "D&C 130:2")]),
]

# Reading B: New Testament scenes
b = [
    M.mc("matt3-scene", "In Matthew 3:16–17, what happens as Jesus comes up out of the water?",
         ["The Spirit of God descends like a dove, and a voice from heaven speaks", "John the Baptist is also baptized",
          "Jesus is taken up into heaven", "A Personage of fire appears to the crowd"], 1,
         "Verses 16–17 describe the heavens opening, the Spirit descending like a dove, and a voice saying, “This is my beloved Son.”",
         [(NT, "Matthew 3:16–17")]),
    M.mc("acts7-vision", "In Acts 7:55–56, what does Stephen see?",
         ["The glory of God, and Jesus standing on the right hand of God", "Jesus alone, seated on a throne",
          "The Holy Ghost in the form of a dove", "An angel holding a book"], 1,
         "Verse 55 says Stephen “saw the glory of God, and Jesus standing on the right hand of God”; verse 56 repeats it.",
         [(NT, "Acts 7:55–56")]),
    M.mc("john17-request", "In John 17:21–22, what does Jesus ask for his disciples?",
         ["That they may be one, as he and the Father are one", "That they may become the Father",
          "That they may leave the world immediately", "That they may never be hated"], 1,
         "Verse 21 asks “that they all may be one; as thou, Father, art in me, and I in thee,” and verse 22 “that they may be one, even as we are one.” Verse 15 says he does not ask that they be taken out of the world.",
         [(NT, "John 17:15, 21–22")]),
    M.mc("john17-argument", "How do Latter-day Saint sources use John 17:21–22?",
         ["As evidence that the oneness of Father and Son is a unity distinct persons can share", "As proof that the disciples became one person",
          "As a passage Latter-day Saints reject", "As evidence that Jesus prayed to himself"], 1,
         "The argument runs: Jesus asks that his distinct disciples be one as he and the Father are one, so the oneness is one that distinct persons can share. The other options misstate the argument.",
         [(NT, "John 17:21–22"), (ART, "What \"one\" means in Latter-day Saint sources")], difficulty="application", perspective=METHOD),
    M.tf("john17-other-readings", "Other Christian traditions also read John 17, within their own teaching about God, without drawing the Latter-day Saint conclusion.", True,
         "The Latter-day Saint reading of John 17 is an interpretation. Other traditions read the same passage within their own understanding of God.",
         [(ART, "What \"one\" means in Latter-day Saint sources")], perspective=METHOD),
    M.mc("matt3-why", "Why do Latter-day Saint sources cite Matthew 3:13–17 when teaching about the Godhead?",
         ["The Son, the Spirit and the Father's voice appear together in one scene", "It is the only passage that mentions the Holy Ghost",
          "It says the three are one person", "It describes the Father's body"], 1,
         "In one scene, the Son stands in the river, the Spirit descends and the Father speaks; Latter-day Saints read that as showing three distinct beings. The passage doesn't make the other claims.",
         [(NT, "Matthew 3:13–17"), (ART, "Distinct beings in the scriptures")], perspective=METHOD),
]

# Reading C: Godhead page
c = [
    M.mc("gh-prayer", "According to the Church's Godhead page, to whom do Latter-day Saints pray?",
         ["To the Father, in the name of Jesus Christ", "To the Holy Ghost, in the name of the Father",
          "To Jesus Christ, in the name of the Father", "To the three members of the Godhead jointly"], 1,
         "The page says Latter-day Saints pray to the Father in the name of Jesus Christ, consistent with 2 Nephi 32:9 and Christ's prayers to the Father in John 17.",
         [(GH, "Roles")], perspective=INST),
    M.tf("gh-bodies", "The Church's Godhead page says the Father and the Son have tangible bodies of flesh and bones.", True,
         "The page teaches this and cites Doctrine and Covenants 130:22.",
         [(GH, "Roles and bodies")], perspective=INST),
    M.mc("gh-aof", "Which scripture does the Godhead page cite for the belief in the Father, the Son and the Holy Ghost?",
         ["Article of Faith 1:1", "Article of Faith 1:13", "Moses 1:39", "Doctrine and Covenants 1:38"], 1,
         "The page cites Article of Faith 1:1. The other passages concern conduct, God's purpose and the Lord's word.",
         [(GH, "Scriptures cited")], perspective=INST),
]

# Article and module quiz
godhead_word = M.mc("godhead-word", "In Latter-day Saint usage, what does “Godhead” mean?",
                    ["The Father, the Son and the Holy Ghost together", "A divine substance the three share", "The Father alone", "The Holy Ghost alone"], 1,
                    "Latter-day Saints use “Godhead” for the three together. In this usage it does not name a shared divine substance.",
                    [(ART, "Three named in one sentence"), (GH, "Definition")], perspective=INST)
god_whole = M.mc("god-whole", "Which passage uses “God” for the Father, the Son and the Holy Ghost together?",
                 ["2 Nephi 31:21", "Article of Faith 1", "Acts 7:55", "Matthew 3:17"], 1,
                 "2 Nephi 31:21 speaks of the doctrine “of the Father, and of the Son, and of the Holy Ghost, which is one God.” Article of Faith 1 and Acts 7:55 use “God” of the Father; Matthew 3:17 records the Father's voice.",
                 [(ART, "What \"one\" means in Latter-day Saint sources")])
roles = M.tf("roles-not-division", "The roles on the Church's Godhead page mean the Father has no part in redemption.", False,
             "The page describes how the sources usually speak of each member and says the three are perfectly united in the Father's plan; roles are not a strict division of labor.",
             [(GH, "Roles"), (ART, "Roles: Father, Son and Holy Ghost")], perspective=METHOD)
beyond = M.mc("beyond-sources", "Which claim goes beyond the canonical and institutional sources in this module?",
              ["A detailed description of exactly how the Holy Ghost dwells in a person", "The Father and the Son have bodies of flesh and bones",
               "The Father, Son and Holy Ghost are one in purpose", "The Holy Ghost is a personage of Spirit"], 1,
              "The sources state the other three. They say little about how the Holy Ghost dwells in a person, so a detailed account of it is commentary or speculation.",
              [(ART, "What the sources leave open")], difficulty="application", perspective=METHOD)
scenes = M.match("scenes", "Who appears?", "Match each scene to what it describes.",
                 [("Jesus's baptism (Matthew 3:16–17)", "The Son in the water, the Spirit like a dove, the Father's voice"),
                  ("Stephen's vision (Acts 7:55–56)", "The glory of God, and Jesus standing at his right hand"),
                  ("Joseph Smith—History 1:17", "Two Personages, one introducing the other"),
                  ("3 Nephi 11:7–8", "A voice introducing the Son, who then descends")],
                 "Each scene is one Latter-day Saints cite for the distinctness of the Father, Son and Holy Ghost.",
                 [(NT, "Matthew 3; Acts 7"), (ART, "Distinct beings in the scriptures")], overlaps=[b[0], b[1], b[5]])

M.add_to_pool(*OLD.values(), OLDM)
M.set_article("article.md", 16, {
    "Three named in one sentence": [godhead_word],
    "Distinct beings in the scriptures": [b[5]],
    "Bodies and spirit: Doctrine and Covenants 130": [OLD["005"]],
    "Roles: Father, Son and Holy Ghost": [roles],
    "What \"one\" means in Latter-day Saint sources": [god_whole],
    "What the sources leave open": [beyond],
    "Explaining it well": [OLD["003"]],
})
M.reading("dc130", "Doctrine and Covenants 130", 12,
          ["Which verses speak about the Father, the Son and the Holy Ghost, and which address other subjects?",
           "What does verse 22 state about each member of the Godhead, and what reason does it give?",
           "What does verse 22 leave unexplained?"],
          a + [OLD["001"], OLD["005"]], passages=[{"chapterID": "dc-testament.dc.130", "from": 1, "to": 23}])
M.reading("nt", "Matthew 3:13–17, Acts 7:55–56 and John 17:20–26", 12,
          ["In each scene, which members of the Godhead appear or act, and how?",
           "What does Jesus ask for his disciples in John 17?",
           "How would you describe the unity Jesus prays for, using the passage's own words?"],
          b, passages=[{"chapterID": "nt.matt.3", "from": 13, "to": 17}, {"chapterID": "nt.acts.7", "from": 55, "to": 56}, {"chapterID": "nt.john.17", "from": 20, "to": 26}])
M.reading("godhead", "Godhead (Gospel Topics)", 10,
          ["What roles does the page give the Father, the Son and the Holy Ghost?",
           "How does the page describe their unity?",
           "Which scriptures does it cite?"],
          c + [OLD["002"], OLD["007"], OLD["009"]],
          source={"title": "Godhead", "url": "https://www.churchofjesuschrist.org/study/manual/gospel-topics/godhead?lang=eng",
                  "publisher": "The Church of Jesus Christ of Latter-day Saints", "perspective": INST})
M.set_practice("Who appears?", scenes)
M.set_essay([
    ("Explain the Latter-day Saint teaching about the Godhead to a curious newcomer. Cite at least two sources from this module and define one term that could mislead them.",
     "Name the three (Article of Faith 1) and the term Godhead; distinct beings, with a cited scene (Matthew 3:16–17, Acts 7:55–56 or JS—H 1:17); D&C 130:22 on bodies and the Holy Ghost as a personage of Spirit; unity of purpose (Godhead page). A defined term might be “Godhead” (the three together, not a shared substance) or “one.” Avoid describing other traditions."),
    ("Set out the Latter-day Saint argument from John 17:21–22 about what “one” means. Then explain why it is an interpretation, and how you would present it fairly.",
     "Jesus prays that his disciples be one as he and the Father are one; the disciples remain distinct, so the oneness is one distinct persons can share (unity of purpose). It is an interpretation because other traditions read John 17 within their own teaching and don't draw this conclusion. Fair presentation attributes the argument and avoids claiming the passage settles the question."),
    ("Explain what Doctrine and Covenants 130:22 states, what it leaves open, and why the setting of section 130 matters when you cite it.",
     "States: the Father and Son have bodies of flesh and bones; the Holy Ghost is a personage of Spirit, so it can dwell in us. Leaves open: detailed descriptions of divine nature, how embodiment relates to time before Christ's mortal life. Setting: items of instruction at Ramus, Illinois, 1843, on several subjects, so cite the specific verse."),
])
M.build(os.path.dirname(os.path.abspath(__file__)))
