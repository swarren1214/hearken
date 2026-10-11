import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from v2lib import Module

M = Module("lds-doctrine-c02-m01", "2.1", "lds-doctrine-c02", "The plan of salvation",
           "Trace the plan of salvation from premortal life to judgment, citing the source for each part.",
           "lds-doctrine-c02-m01-objective-01", "Outline the plan of salvation from its canonical and institutional sources, distinguishing quotation from interpretation.")
MA = M.source("moses1-abr3", "Moses 1:30–39; Abraham 3:22–28", passage={"chapterID": "pgp.moses.1", "from": 30, "to": 39})
POS = M.source("plan-of-salvation", "Plan of Salvation (Gospel Topics)", url="https://www.churchofjesuschrist.org/study/manual/gospel-topics/plan-of-salvation?lang=eng",
               perspective="Latter-day Saint institutional")
AL = M.source("alma-42", "Alma 42", passage={"chapterID": "bofm.alma.42", "from": 1, "to": 31})
ART = "article"
METHOD = "Original Hearken reading method grounded in the cited sources"
INST = "Latter-day Saint institutional"

a = [
    M.mc("moses1-39", "According to Moses 1:39, what is God's work and glory?",
         ["To bring to pass the immortality and eternal life of man", "To create worlds without number",
          "To test only the faithful", "To reveal all things to Moses"], 1,
         "Verse 39 names immortality and eternal life. Verse 33 mentions worlds without number, but as creation, not as God's stated work and glory; verse 35 says Moses is told only about this earth.",
         [(MA, "Moses 1:33–39")]),
    M.mc("moses1-31", "When Moses asks why the creations exist (Moses 1:30), how does God first answer?",
         ["He made them for his own purpose, and that wisdom remains in him", "He explains every reason in detail",
          "He refuses to speak with Moses", "He says Moses already knows the answer"], 1,
         "Verse 31: “For mine own purpose have I made these things. Here is wisdom and it remaineth in me.” He then tells Moses some things, but not all.",
         [(MA, "Moses 1:31")]),
    M.mc("moses1-son", "According to Moses 1:32–33, by whom did God create?",
         ["By his Only Begotten Son", "By Moses", "By the angels", "By the Holy Ghost alone"], 1,
         "Verse 33: “by the Son I created them, which is mine Only Begotten.”",
         [(MA, "Moses 1:32–33")]),
    M.tf("moses1-35", "In Moses 1:35, God says he will give Moses only an account of this earth and its inhabitants.", True,
         "Verse 35: “only an account of this earth, and the inhabitants thereof, give I unto you.”",
         [(MA, "Moses 1:35")]),
    M.mc("abr3-22", "What was Abraham shown in Abraham 3:22?",
         ["The intelligences that were organized before the world was", "The location of the Garden of Eden",
          "The final judgment", "The building of a temple"], 1,
         "Verse 22: “the intelligences that were organized before the world was; and among all these there were many of the noble and great ones.”",
         [(MA, "Abraham 3:22")]),
    M.mc("abr3-25", "According to Abraham 3:25, what was the earth for?",
         ["To prove them, to see if they would do all things the Lord commanded", "To give the noble and great ones a reward",
          "To keep the spirits away from God", "To end the premortal council"], 1,
         "Verse 25: “we will prove them herewith, to see if they will do all things whatsoever the Lord their God shall command them.”",
         [(MA, "Abraham 3:25")]),
    M.mc("abr3-26", "According to Abraham 3:26, what will those who keep their second estate receive?",
         ["Glory added upon their heads for ever and ever", "To be added upon", "A place in the same kingdom as those who did not", "Nothing further"], 1,
         "Verse 26 says those who keep their first estate “shall be added upon,” and those who keep their second estate “shall have glory added upon their heads for ever and ever.”",
         [(MA, "Abraham 3:26")]),
    M.mc("abr3-27", "How does the council in Abraham 3:27–28 end?",
         ["The Lord sends the first who answered; the second is angry, and many follow him", "Both volunteers are sent",
          "The Lord sends the second who answered", "No one answers the Lord's question"], 1,
         "Verse 27: “I will send the first.” Verse 28: “the second was angry, and kept not his first estate; and, at that day, many followed after him.”",
         [(MA, "Abraham 3:27–28")]),
    M.tf("abr3-define", "Abraham 3:26 defines “first estate” as premortal life.", False,
         "The verse uses the terms without defining them. Reading the first estate as premortal life is a widely taught interpretation, and should be attributed as one.",
         [(MA, "Abraham 3:26"), (ART, "Before this life: Abraham 3")], perspective=METHOD),
]

b = [
    M.mc("pos-premortal", "What does the Church's Plan of Salvation page say about life before birth?",
         ["People lived with heavenly parents as their spirit children", "People did not exist before birth",
          "Only prophets existed before birth", "Spirits were created at the moment of birth"], 1,
         "The page says that before birth people lived with heavenly parents as their spirit children.",
         [(POS, "Premortal life")], perspective=INST),
    M.mc("pos-mortality", "Which purposes of mortal life does the page name?",
         ["Gaining a physical body and using agency", "Earning a place in the premortal council", "Avoiding every trial", "Learning the location of Eden"], 1,
         "The page names gaining a physical body and agency, including choosing to repent and to receive ordinances.",
         [(POS, "Purposes of mortal life")], perspective=INST),
    M.mc("pos-atonement", "According to the page, why was the Atonement of Jesus Christ necessary?",
         ["Because no unclean thing can dwell with God", "Because the premortal council failed", "Because the earth needed to be created", "Because agency had been destroyed"], 1,
         "The page says the Atonement was necessary because nothing unclean can live with God, and that through it people can repent and return.",
         [(POS, "The Atonement")], perspective=INST),
    M.tf("pos-death", "According to the page, death separates the spirit from the body, and the spirit continues to live.", True,
         "The page teaches that at death the spirit separates from the body and continues to live.",
         [(POS, "Death and the spirit world")], perspective=INST),
    M.mc("pos-third", "The page says a third of Heavenly Father's spirit children followed Lucifer. Where does that detail come from?",
         ["The Church's page, which cites Revelation 12; Abraham 3:28 says only “many followed after him”",
          "Abraham 3:28, which gives the fraction", "Moses 1:39", "Alma 42:15"], 1,
         "The fraction comes from the page and the passage it cites. Abraham 3:28 says “many,” so a careful claim attributes the detail to its own source.",
         [(POS, "Premortal life"), (MA, "Abraham 3:28"), (ART, "The council and agency: Moses 4")], difficulty="application", perspective=METHOD),
    M.mc("pos-judgment", "According to the page, by what are people judged at the final judgment?",
         ["Their desires and their obedience to the commandments", "Their premortal choices only", "Their knowledge of scripture", "The number of ordinances they received"], 1,
         "The page says God judges people according to their desires and obedience to the commandments.",
         [(POS, "Judgment")], perspective=INST),
]

c = [
    M.mc("alma42-justice", "According to Alma 42:25, can mercy rob justice?",
         ["No, “not one whit”", "Yes, whenever a person repents", "Yes, at the final judgment", "The chapter doesn't say"], 1,
         "Verse 25: “What, do ye suppose that mercy can rob justice? I say unto you, Nay; not one whit.”",
         [(AL, "Alma 42:25")]),
    M.mc("alma42-15", "According to Alma 42:15, why must an atonement be made?",
         ["The plan of mercy could not be brought about without it", "To end the probationary state", "To replace the law", "To make justice unnecessary"], 1,
         "Verse 15: “the plan of mercy could not be brought about except an atonement should be made; therefore God himself atoneth for the sins of the world.”",
         [(AL, "Alma 42:15")]),
    M.mc("alma42-4", "How does Alma 42:4 describe the time granted to people?",
         ["As a probationary time, a time to repent and serve God", "As a punishment for Adam's transgression",
          "As a reward for the premortal council", "As a time without law"], 1,
         "Verse 4: “a probationary time, a time to repent and serve God.” Verse 10 also calls it “a preparatory state.”",
         [(AL, "Alma 42:4, 10")]),
    M.tf("alma42-23", "Alma 42:23 says the atonement brings to pass the resurrection, which brings people back into God's presence to be judged.", True,
         "Verse 23 links the atonement, the resurrection, the return to God's presence and judgment “according to their works.”",
         [(AL, "Alma 42:23")]),
    M.mc("alma42-27", "What does Alma 42:27 say about those who will not come and partake of the waters of life?",
         ["They are not compelled to come", "They are forced to come", "They are already saved", "They are not mentioned"], 1,
         "Verse 27: “whosoever will come may come … and whosoever will not come the same is not compelled to come.”",
         [(AL, "Alma 42:27")]),
    M.tf("alma42-suspend", "In Alma 42, mercy works by setting justice aside.", False,
         "Alma says mercy cannot rob justice (verse 25); mercy claims the penitent because of the atonement (verse 23), so both are satisfied.",
         [(AL, "Alma 42:23–25"), (ART, "Christ's Atonement at the center")]),
]

happiness = M.mc("alma42-8", "Which name for the plan does Alma 42:8 use?",
                 ["The great plan of happiness", "The plan of mercy", "The plan of redemption", "The great plan of salvation"], 1,
                 "Verse 8 says “great plan of happiness.” Alma uses the others in verses 15, 11 and 5.",
                 [(AL, "Alma 42:5, 8, 11, 15")])
names = M.match("plan-names", "Names for the plan", "Match each name for the plan to the verse in Alma 42 that uses it.",
                [("The great plan of salvation", "Alma 42:5"), ("The great plan of happiness", "Alma 42:8"),
                 ("The plan of redemption", "Alma 42:11"), ("The plan of mercy", "Alma 42:15")],
                "Alma uses all four names in one chapter, each highlighting a different aspect of the same plan.",
                [(AL, "Alma 42:5, 8, 11, 15")], overlaps=[happiness])
outline = M.mc("interpretation-label", "Which of these is a widely taught reading rather than a quotation?",
               ["“The second estate is mortal life.”", "“This is my work and my glory” (Moses 1:39)",
                "“We will prove them herewith” (Abraham 3:25)", "“Mercy claimeth the penitent” (Alma 42:23)"], 1,
               "The other three quote scripture. Identifying the second estate with mortal life is a common reading of Abraham 3:26, and belongs in notes labeled as interpretation.",
               [(MA, "Abraham 3:26"), (ART, "Keeping the outline honest")], difficulty="application", perspective=METHOD)
selective = M.mc("moses1-scope", "Moses 1:39 is a strong source for which claim?",
                 ["In Latter-day Saint scripture, God's work centers on human immortality and eternal life", "Detailed facts about other worlds",
                  "The exact number of God's creations", "Everything about why God created"], 1,
                 "The passage states God's purpose and openly declines to give details about other worlds or all of God's reasons (verses 31, 35).",
                 [(MA, "Moses 1:31–39"), (ART, "God's stated purpose: Moses 1:39")], difficulty="application", perspective=METHOD)
council = M.mc("council-sources", "What does each passage contribute to the account of the premortal council?",
               ["Abraham 3 gives the setting, the purpose of proving the spirits and the two volunteers; Moses 4 names agency as the issue",
                "Abraham 3 names agency as the issue; Moses 4 gives the two volunteers only", "Both passages say exactly the same things",
                "Neither passage mentions the council"], 1,
               "Read side by side, the passages complement each other; a careful account cites the passage for each detail.",
               [(MA, "Abraham 3:22–28"), (ART, "The council and agency: Moses 4")], difficulty="application", perspective=METHOD)

M.set_article("article.md", 16, {
    "A plan with many names": [happiness],
    "God's stated purpose: Moses 1:39": [selective],
    "Before this life: Abraham 3": [a[8]],
    "The council and agency: Moses 4": [council],
    "Mortal life: bodies, choices and trials": [c[2]],
    "Christ's Atonement at the center": [c[5]],
    "After this life": [c[3]],
    "Keeping the outline honest": [outline],
})
M.reading("moses-abraham", "Moses 1:30–39 and Abraham 3:22–28", 12,
          ["What does God tell Moses, and what does he decline to tell him?",
           "What does Abraham see, and what is the earth's purpose in verse 25?",
           "What do the terms “first estate” and “second estate” refer to in verse 26, and does the verse define them?"],
          a, passages=[{"chapterID": "pgp.moses.1", "from": 30, "to": 39}, {"chapterID": "pgp.abr.3", "from": 22, "to": 28}])
M.reading("gospel-topics", "Plan of Salvation (Gospel Topics)", 10,
          ["What does the page say about life before birth?",
           "Which purposes of mortal life does it name?",
           "What does it say follows death?"],
          b, source={"title": "Plan of Salvation", "url": "https://www.churchofjesuschrist.org/study/manual/gospel-topics/plan-of-salvation?lang=eng",
                     "publisher": "The Church of Jesus Christ of Latter-day Saints", "perspective": INST})
M.reading("alma42", "Alma 42", 15,
          ["Which names does Alma give the plan, and in which verses?",
           "How does Alma explain the relationship between justice and mercy?",
           "What does he say about the time people are given in this life?"],
          c, passages=[{"chapterID": "bofm.alma.42", "from": 1, "to": 31}])
M.set_practice("Names for the plan", names)
M.set_essay([
    ("Outline the plan of salvation from premortal life to judgment. For each stage, cite the passage or page that teaches it, and mark any point that is a widely taught reading rather than a quotation.",
     "Premortal life (Abraham 3:22–23; Plan of Salvation page); the council and agency (Abraham 3:24–28; Moses 4:1–3); mortality as probation (Abraham 3:25; Alma 42:4, 10; page on bodies and agency); the Atonement (Alma 42:15, 23; page); death and the spirit world (page); resurrection and judgment (Alma 42:23; page). Labels the first/second estate reading as interpretation."),
    ("Explain how Alma 42 describes the relationship between justice and mercy. Quote at least two verses.",
     "Mercy cannot rob justice (v25); the plan of mercy requires an atonement (v15); mercy claims the penitent because of the atonement (v23); repentance is the condition (v13, 22). Both justice and mercy are satisfied, rather than justice being set aside."),
    ("Compare what Abraham 3:22–28 and Moses 4:1–4 each contribute to the account of the premortal council, and identify one detail that comes from the Church's page rather than either passage.",
     "Abraham 3: intelligences, the noble and great, the purpose of proving, two volunteers, many followed the second. Moses 4: Satan's offer to redeem all, the Son's “thy will be done,” Satan seeking to destroy agency. The page adds that a third followed Lucifer, citing Revelation 12."),
])
M.build(os.path.dirname(os.path.abspath(__file__)))
