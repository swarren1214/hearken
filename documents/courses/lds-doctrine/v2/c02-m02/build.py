import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from v2lib import Module

M = Module("lds-doctrine-c02-m02", "2.2", "lds-doctrine-c02", "Agency and the Fall",
           "Explain agency, opposition and the Fall as 2 Nephi 2 and the Book of Moses describe them.",
           "lds-doctrine-c02-m02-objective-01", "Explain the Latter-day Saint teaching on agency and the Fall from 2 Nephi 2, Moses 4–5 and Article of Faith 2.")
NE = M.source("2ne-2", "2 Nephi 2", passage={"chapterID": "bofm.2-ne.2", "from": 1, "to": 30})
MO = M.source("moses-4-5", "Moses 4:1–4; 5:9–12", passage={"chapterID": "pgp.moses.4", "from": 1, "to": 4})
AOF = M.source("aof-2", "Article of Faith 2", passage={"chapterID": "pgp.a-of-f.1", "from": 2, "to": 2})
ART = "article"
METHOD = "Original Hearken reading method grounded in the cited sources"

a = [
    M.mc("2ne2-11", "What does Lehi say “must needs be” in 2 Nephi 2:11?",
         ["That there is an opposition in all things", "That all people are saved", "That there is no law", "That Adam remains in the garden"], 1,
         "Verse 11: “it must needs be, that there is an opposition in all things.”",
         [(NE, "2 Nephi 2:11")]),
    M.mc("2ne2-16-gift", "According to 2 Nephi 2:16, what did the Lord God give to man?",
         ["That he should act for himself", "That he should never be tempted", "That he should be acted upon", "That he should know all things"], 1,
         "Verse 16: “the Lord God gave unto man that he should act for himself.”",
         [(NE, "2 Nephi 2:16")]),
    M.mc("2ne2-16-enticed", "What condition does 2 Nephi 2:16 attach to acting for oneself?",
         ["Man could not act for himself unless he was enticed by the one or the other", "Man must first receive the priesthood",
          "Man must live in the garden", "There is no condition"], 1,
         "Verse 16: “man could not act for himself save it should be that he was enticed by the one or the other.” Real choice needs real alternatives.",
         [(NE, "2 Nephi 2:16")], difficulty="application"),
    M.mc("2ne2-25", "Which sentence comes from 2 Nephi 2:25?",
         ["“Adam fell that men might be; and men are, that they might have joy.”", "“Men will be punished for their own sins.”",
          "“This is my work and my glory.”", "“Thy will be done, and the glory be thine forever.”"], 1,
         "That is verse 25. The others come from Article of Faith 2, Moses 1:39 and Moses 4:2.",
         [(NE, "2 Nephi 2:25")]),
    M.mc("2ne2-22-23", "According to 2 Nephi 2:22–23, what would have happened if Adam had not transgressed?",
         ["He and Eve would have remained in Eden and had no children", "They would have had more children",
          "They would have been redeemed sooner", "The earth would have been destroyed"], 1,
         "Verses 22–23 say they would have remained in the garden, “they would have had no children,” and remained in innocence.",
         [(NE, "2 Nephi 2:22–23")]),
    M.mc("2ne2-26", "According to 2 Nephi 2:26, what are people free to do because they are redeemed from the Fall?",
         ["To act for themselves and not to be acted upon", "To avoid the final judgment", "To return to the garden", "To live without law"], 1,
         "Verse 26: redeemed from the fall, they have become “free forever, knowing good from evil; to act for themselves and not to be acted upon.”",
         [(NE, "2 Nephi 2:26")]),
    M.tf("2ne2-27", "2 Nephi 2:27 says people are free to choose liberty and eternal life through the great Mediator, or captivity and death.", True,
         "Verse 27 sets out that choice in those words.",
         [(NE, "2 Nephi 2:27")]),
    M.mc("2ne2-8", "According to 2 Nephi 2:8, how can anyone dwell in the presence of God?",
         ["Only through the merits, and mercy, and grace of the Holy Messiah", "By keeping the law perfectly on their own",
          "By being born in the garden", "By avoiding all opposition"], 1,
         "Verse 8 says no flesh can dwell in God's presence “save it be through the merits, and mercy, and grace of the Holy Messiah.” Verse 5 says by the law no flesh is justified.",
         [(NE, "2 Nephi 2:5, 8")]),
    M.mc("2ne2-13", "Lehi's chain of reasoning in 2 Nephi 2:13 begins “if ye shall say there is no law.” How does it end?",
         ["“If these things are not there is no God.”", "“There is no opposition in heaven.”", "“Men are that they might have joy.”", "“The law is given unto men.”"], 1,
         "The chain runs from law to sin, righteousness, happiness and punishment, ending: “if these things are not there is no God.”",
         [(NE, "2 Nephi 2:13")]),
    M.mc("2ne2-devil", "What does Lehi say about the devil in 2 Nephi 2:17–18?",
         ["An angel of God had fallen from heaven and sought the misery of all mankind", "He was never in heaven",
          "He offered to help Adam and Eve", "He is not mentioned in the chapter"], 1,
         "Verse 17 says Lehi supposes “an angel of God … had fallen from heaven,” and verse 18 that he “sought also the misery of all mankind.” Notice Lehi presents verse 17 as his supposition from what he has read.",
         [(NE, "2 Nephi 2:17–18")]),
]

b = [
    M.mc("moses4-3", "According to Moses 4:3, what did Satan seek to destroy?",
         ["The agency of man", "The earth", "The Book of Moses", "The garden of Eden"], 1,
         "Verse 3: Satan “sought to destroy the agency of man, which I, the Lord God, had given him.”",
         [(MO, "Moses 4:3")]),
    M.mc("moses4-1", "What did Satan propose in Moses 4:1?",
         ["To redeem all mankind so that not one soul would be lost, in exchange for God's honor", "To follow the Father's will",
          "To leave the council", "To create a new earth"], 1,
         "Verse 1: “I will redeem all mankind, that one soul shall not be lost … wherefore give me thine honor.”",
         [(MO, "Moses 4:1")]),
    M.mc("moses4-2", "How did the Beloved Son answer in Moses 4:2?",
         ["“Father, thy will be done, and the glory be thine forever.”", "“Here am I, send me, and give me thine honor.”",
          "“I will redeem all mankind.”", "“Let another be sent.”"], 1,
         "Verse 2 records the Son's answer. The demand for honor was Satan's (verse 1).",
         [(MO, "Moses 4:2")]),
    M.mc("moses5-10", "What does Adam say in Moses 5:10?",
         ["“Because of my transgression my eyes are opened, and in this life I shall have joy”", "“I wish I had never left the garden”",
          "“My transgression has no consequences”", "“I shall never see God again”"], 1,
         "Verse 10: “because of my transgression my eyes are opened, and in this life I shall have joy, and again in the flesh I shall see God.”",
         [(MO, "Moses 5:10")]),
    M.mc("moses5-11", "What does Eve say in Moses 5:11?",
         ["Were it not for their transgression they would never have had seed or known good and evil", "That Adam alone was responsible",
          "That they should return to the garden", "That redemption is impossible"], 1,
         "Verse 11 lists seed, knowledge of good and evil, the joy of redemption and eternal life as coming because of their transgression.",
         [(MO, "Moses 5:11")]),
    M.tf("moses5-9", "In Moses 5:9, the Holy Ghost bears record to Adam that as he has fallen he may be redeemed.", True,
         "Verse 9: “that as thou hast fallen thou mayest be redeemed, and all mankind, even as many as will.”",
         [(MO, "Moses 5:9")]),
    M.mc("guarantee", "Why would a plan guaranteeing that no one could be lost conflict with Lehi's teaching in 2 Nephi 2?",
         ["It would remove the real choice and opposition Lehi says are necessary", "Because Lehi teaches that most people are lost",
          "Because 2 Nephi 2 says agency is unimportant", "It wouldn't; the two are the same idea"], 1,
         "Lehi says acting for oneself requires enticement by “the one or the other” and opposition in all things; a guaranteed outcome removes that choice, which is the issue Moses 4:3 names.",
         [(NE, "2 Nephi 2:11, 16"), (MO, "Moses 4:1–3"), (ART, "Agency in the premortal council")], difficulty="application", perspective=METHOD),
]

aof = M.mc("aof2-scope", "Which statement does Article of Faith 2 support?",
           ["People are accountable for their own sins and are not punished for Adam's transgression", "The Fall had no effects on anyone",
            "Every Christian tradition rejects original sin", "Adam's transgression was not real"], 1,
           "The article denies punishment for Adam's transgression and affirms accountability for one's own sins. It does not deny the Fall's effects, which 2 Nephi 2 and Alma 42 describe, or speak for other traditions.",
           [(AOF, "Article of Faith 2"), (ART, "Responsibility: Article of Faith 2")], difficulty="application")
noeffect = M.tf("aof2-effects", "Article of Faith 2 says the Fall had no effects.", False,
                "It says people are not punished for Adam's transgression. Other passages describe real effects of the Fall: mortality and separation from God's presence.",
                [(AOF, "Article of Faith 2"), (ART, "Responsibility: Article of Faith 2")])
word = M.mc("transgression-word", "Which word do Moses 5:10–11 use for what Adam and Eve did?",
            ["Transgression", "Crime", "Mistake", "Rebellion"], 1,
            "Both Adam and Eve speak of “our transgression.” Latter-day Saint teaching often uses this word for the Fall; quote the passages' own words.",
            [(MO, "Moses 5:10–11"), (ART, "The Fall as a step forward")])
redeemer = M.mc("agency-redeemer", "According to 2 Nephi 2:26–27, how is human freedom connected to Christ?",
                ["People become free to choose because the Messiah redeems them from the Fall", "Freedom has nothing to do with Christ",
                 "Christ removes the need to choose", "Only those who choose captivity are free"], 1,
                "Verse 26 says the Messiah redeems people from the Fall, and because of that they are free; verse 27 calls him “the great Mediator of all men.”",
                [(NE, "2 Nephi 2:26–27"), (ART, "To act and not to be acted upon")], difficulty="application")
together = M.mc("fall-and-redemption", "How does 2 Nephi 2 present the Fall?",
                ["Together with redemption through the Holy Messiah", "As the end of God's plan", "As a story with no connection to Christ", "As something people are punished for"], 1,
                "Lehi's chapter centers on the Redeemer (verses 6–10, 26–28); describing the Fall without redemption describes half the teaching.",
                [(NE, "2 Nephi 2:6–10, 26"), (ART, "Redemption from the Fall")], perspective=METHOD)
concepts = M.match("agency-verses", "Where does it say that?", "Match each teaching to the verse that states it.",
                   [("There is an opposition in all things", "2 Nephi 2:11"), ("Adam fell that men might be", "2 Nephi 2:25"),
                    ("To act for themselves and not to be acted upon", "2 Nephi 2:26"), ("Satan sought to destroy the agency of man", "Moses 4:3")],
                   "Knowing which verse states which teaching lets you cite each claim precisely.",
                   [(NE, "2 Nephi 2:11, 25, 26"), (MO, "Moses 4:3")], overlaps=[a[0], a[3], a[5], b[0]])

M.set_article("article.md", 16, {
    "Why agency comes first": [b[0]],
    "Opposition in all things": [a[8]],
    "To act and not to be acted upon": [a[2]],
    "Agency in the premortal council": [b[6]],
    "The Fall as a step forward": [a[4]],
    "Responsibility: Article of Faith 2": [noeffect],
    "Redemption from the Fall": [together],
    "Describing it well": [redeemer],
})
M.reading("2ne2", "2 Nephi 2", 18,
          ["What does Lehi say about opposition, and why does he think it is necessary?",
           "What does he say about acting for oneself, and what condition does he attach?",
           "How does he connect the Fall to the Messiah?"],
          a, passages=[{"chapterID": "bofm.2-ne.2", "from": 1, "to": 30}])
M.reading("moses", "Moses 4:1–4 and 5:9–12", 8,
          ["What did Satan propose, and what did the Son answer?",
           "What does Moses 4:3 name as the issue?",
           "How do Adam and Eve describe their transgression after learning of redemption?"],
          b, passages=[{"chapterID": "pgp.moses.4", "from": 1, "to": 4}, {"chapterID": "pgp.moses.5", "from": 9, "to": 12}])
M.set_practice("Where does it say that?", concepts)
M.set_essay([
    ("Explain what 2 Nephi 2 teaches about agency and opposition, and why Lehi thinks a world with real choice is necessary. Quote at least two verses.",
     "Opposition in all things (v11); without it no righteousness, happiness or misery (v11–13); God gave man to act for himself, which requires enticement by one or the other (v16); redeemed from the Fall, people are free to act and not be acted upon (v26) and to choose liberty and eternal life or captivity and death (v27)."),
    ("Explain the Latter-day Saint teaching that the Fall was a necessary step, using 2 Nephi 2:22–25 and Moses 5:10–11. Then explain how Article of Faith 2 fits with it.",
     "Without the Fall, Adam and Eve would have remained in Eden, had no children, and known no joy (2 Ne 2:22–23); “Adam fell that men might be” (v25); Adam and Eve rejoice once they learn of redemption (Moses 5:10–11). Article of Faith 2: people are punished for their own sins, not Adam's transgression; the Fall still has effects, but not guilt."),
    ("Compare how Abraham 3 (from module 2.1) and Moses 4:1–4 describe the premortal council, and explain how 2 Nephi 2 helps explain why agency was the issue.",
     "Abraham 3 gives the volunteers and the purpose of proving; Moses 4 says Satan offered to redeem all, sought God's honor and sought to destroy agency. 2 Nephi 2 explains why choice requires opposition and enticement, so a guaranteed outcome would remove agency."),
])
M.build(os.path.dirname(os.path.abspath(__file__)))
