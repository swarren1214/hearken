import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from v2lib import Module

M = Module("lds-doctrine-c02-m03", "2.3", "lds-doctrine-c02", "Faith, repentance and baptism",
           "Describe the first steps of the doctrine of Christ and the baptismal covenant from their sources.",
           "lds-doctrine-c02-m03-objective-01", "Describe faith, repentance and baptism as the doctrine of Christ presents them, including the baptismal covenant and its authority.")
NE = M.source("2ne-31", "2 Nephi 31", passage={"chapterID": "bofm.2-ne.31", "from": 1, "to": 21})
BAP = M.source("baptism-passages", "Mosiah 18:8–10; Acts 2:37–38; 3 Nephi 11:21–26", passage={"chapterID": "bofm.mosiah.18", "from": 8, "to": 10})
AOF = M.source("aof-4-5", "Articles of Faith 4–5", passage={"chapterID": "pgp.a-of-f.1", "from": 4, "to": 5})
ART = "article"
METHOD = "Original Hearken reading method grounded in the cited sources"

a = [
    M.mc("2ne31-5", "What argument does Nephi make in 2 Nephi 31:5?",
         ["If the holy Lamb of God needed baptism, how much more do the unholy", "Baptism is only for prophets",
          "The Lamb of God did not need to be baptized", "Baptism is optional for the faithful"], 1,
         "Verse 5: “if the Lamb of God, he being holy, should have need to be baptized by water … how much more need have we, being unholy.”",
         [(NE, "2 Nephi 31:5")]),
    M.mc("2ne31-7", "According to 2 Nephi 31:7, what did Christ's baptism witness to the Father?",
         ["That he would be obedient in keeping the Father's commandments", "That he needed forgiveness",
          "That he was the Father", "That baptism was no longer needed"], 1,
         "Verse 7: he “witnesseth unto the Father that he would be obedient unto him in keeping his commandments.” Nephi stresses that Christ was holy.",
         [(NE, "2 Nephi 31:7")]),
    M.mc("2ne31-8", "What happened after Christ was baptized, according to 2 Nephi 31:8?",
         ["The Holy Ghost descended upon him in the form of a dove", "He was taken into heaven", "John was baptized by him", "Nothing further"], 1,
         "Verse 8: “the Holy Ghost descended upon him in the form of a dove,” matching Matthew 3:16.",
         [(NE, "2 Nephi 31:8")]),
    M.mc("2ne31-10", "What words of Christ does Nephi quote in 2 Nephi 31:10?",
         ["“Follow thou me.”", "“This is my beloved Son.”", "“Endure to the end.”", "“Feast upon my words.”"], 1,
         "Verse 10: “Follow thou me.” Nephi adds, “can we follow Jesus save we shall be willing to keep the commandments of the Father?”",
         [(NE, "2 Nephi 31:10")]),
    M.mc("2ne31-17", "In 2 Nephi 31:17, what is “the gate by which ye should enter”?",
         ["Repentance and baptism by water", "Prayer and fasting", "Reading the scriptures", "Enduring to the end"], 1,
         "Verse 17: “the gate by which ye should enter is repentance and baptism by water; and then cometh a remission of your sins by fire and by the Holy Ghost.”",
         [(NE, "2 Nephi 31:17")]),
    M.mc("2ne31-13", "Which phrase does 2 Nephi 31:13 use to describe how to follow the Son?",
         ["With full purpose of heart, acting no hypocrisy and no deception, but with real intent", "With perfect knowledge",
          "Without any repentance", "Only after the Holy Ghost is received"], 1,
         "Verse 13 sets those conditions, and connects them to repenting and taking the name of Christ by baptism.",
         [(NE, "2 Nephi 31:13")]),
    M.tf("2ne31-19", "In 2 Nephi 31:19, Nephi says that all is done once a person has entered the gate.", False,
         "Nephi asks, “I would ask if all is done?” and answers, “Nay.” Verse 20 describes pressing forward and enduring.",
         [(NE, "2 Nephi 31:19–20")]),
    M.mc("2ne31-20", "How does 2 Nephi 31:20 describe pressing forward?",
         ["With steadfastness in Christ, a perfect brightness of hope, and a love of God and of all men", "With fear of failure",
          "By avoiding all other people", "By relying on one's own merits"], 1,
         "Verse 20 names steadfastness, hope, love and feasting on the word. Verse 19 says to rely wholly on the merits of Christ, not one's own.",
         [(NE, "2 Nephi 31:19–20")]),
    M.mc("2ne31-21", "How does 2 Nephi 31:21 end its description of the doctrine of Christ?",
         ["“…which is one God, without end.”", "“…which is three Gods.”", "“…which is the Father only.”", "“…which is not yet revealed.”"], 1,
         "Verse 21 calls it “the only and true doctrine of the Father, and of the Son, and of the Holy Ghost, which is one God, without end.”",
         [(NE, "2 Nephi 31:21")]),
    M.mc("2ne31-15", "What does the Father's voice say in 2 Nephi 31:15?",
         ["“He that endureth to the end, the same shall be saved.”", "“Repent ye, repent ye.”", "“Follow thou me.”", "“Hear ye him.”"], 1,
         "Verse 15 records the Father's words about enduring. “Repent ye” is the Father's voice in verse 11; “Follow thou me” is the Son's in verse 10.",
         [(NE, "2 Nephi 31:10–15")]),
]

b = [
    M.mc("mosiah18-willing", "According to Mosiah 18:8–9, those ready for baptism are willing to do what?",
         ["Bear one another's burdens, mourn with those that mourn, comfort those in need, and stand as witnesses of God",
          "Leave their families", "Give all their property to Alma", "Never speak of their faith"], 1,
         "Verses 8–9 list these, “even until death.”",
         [(BAP, "Mosiah 18:8–9")]),
    M.mc("mosiah18-witness", "According to Mosiah 18:10, baptism is a witness of what?",
         ["That they have entered into a covenant to serve God and keep his commandments", "That they have already been perfected",
          "That they have joined Alma's family", "That they have seen an angel"], 1,
         "Verse 10: baptism is “a witness before him that ye have entered into a covenant with him, that ye will serve him and keep his commandments.”",
         [(BAP, "Mosiah 18:10")]),
    M.mc("mosiah18-promise", "What does Mosiah 18:10 say God will do for those who make this covenant?",
         ["Pour out his Spirit more abundantly upon them", "Remove all their trials", "Give them wealth", "Show them the plates"], 1,
         "Verse 10: “that he may pour out his Spirit more abundantly upon you.”",
         [(BAP, "Mosiah 18:10")]),
    M.mc("acts2-38", "What does Peter tell his hearers in Acts 2:38?",
         ["Repent, and be baptized in the name of Jesus Christ for the remission of sins, and receive the gift of the Holy Ghost",
          "Be baptized first, and repent later", "Pray without being baptized", "Wait for the apostles to return"], 1,
         "Verse 38 gives that sequence. Latter-day Saints cite it alongside 2 Nephi 31.",
         [(BAP, "Acts 2:38")]),
    M.mc("3ne11-26", "According to 3 Nephi 11:26, how is baptism performed?",
         ["The person is immersed in the water and comes forth out of the water", "Water is sprinkled on the person",
          "Water is poured on the head", "The person washes their own hands"], 1,
         "Verse 26: “then shall ye immerse them in the water, and come forth again out of the water.”",
         [(BAP, "3 Nephi 11:26")]),
    M.tf("3ne11-power", "In 3 Nephi 11:21–22, Christ gives Nephi and others power to baptize.", True,
         "Verse 21: “I give unto you power that ye shall baptize this people”; verse 22 extends it to others.",
         [(BAP, "3 Nephi 11:21–22")]),
    M.mc("acts-parallel", "Why do Latter-day Saints cite Acts 2:38 alongside 2 Nephi 31?",
         ["Both present the same pattern: repentance, baptism and the gift of the Holy Ghost", "Acts 2 is quoted in 2 Nephi 31",
          "Both describe the baptism of Jesus", "Acts 2:38 corrects 2 Nephi 31"], 1,
         "The two texts share the pattern; Latter-day Saints read that as the same doctrine in both books.",
         [(BAP, "Acts 2:38"), (NE, "2 Nephi 31:13, 17"), (ART, "Baptism: the gate")], difficulty="application", perspective=METHOD),
]

immersion = M.mc("aof4-mode", "How does Article of Faith 4 describe baptism?",
                 ["Baptism by immersion for the remission of sins", "Baptism by sprinkling as a symbol",
                  "Baptism for children at birth", "Baptism by the Holy Ghost only"], 1,
                 "Article of Faith 4 names “Baptism by immersion for the remission of sins” as the third first principle and ordinance.",
                 [(AOF, "Article of Faith 4")])
authority = M.mc("aof5-authority", "According to Article of Faith 5, how must a person be called to administer the ordinances?",
                 ["Called of God, by prophecy, and by the laying on of hands by those in authority", "Chosen by the congregation",
                  "Self-appointed after study", "Called by a family member"], 1,
                 "Article of Faith 5 states the principle; 3 Nephi 11:21–25 ties baptism to authority given by Christ.",
                 [(AOF, "Article of Faith 5"), (ART, "How baptism is performed")])
phrase = M.mc("doctrine-of-christ", "In 2 Nephi 31–32 and 3 Nephi 11, what does “the doctrine of Christ” name?",
              ["A pattern: faith in Christ, repentance, baptism, the Holy Ghost, and enduring to the end", "All of Christian teaching",
               "The doctrine of the Godhead only", "A list of commandments about the Sabbath"], 1,
              "In these chapters the phrase names a particular pattern for coming to Christ, not every Christian teaching.",
              [(NE, "2 Nephi 31:2, 21"), (ART, "The doctrine of Christ")], perspective=METHOD)
gift = M.tf("gift-laying-on", "In Latter-day Saint practice, the gift of the Holy Ghost is conferred by the laying on of hands after baptism.", True,
            "Article of Faith 4 lists laying on of hands for the gift of the Holy Ghost after baptism.",
            [(AOF, "Article of Faith 4"), (ART, "Baptism: the gate")])
gate = M.mc("gate-image", "What does Nephi's image of a gate suggest about baptism?",
            ["It is a beginning that opens onto a path", "It is the end of the journey", "It is optional", "It replaces repentance"], 1,
            "A gate opens onto “this strait and narrow path which leads to eternal life” (verse 18); Nephi then asks whether all is done and says no.",
            [(NE, "2 Nephi 31:17–19"), (ART, "Baptism: the gate")], difficulty="application", perspective=METHOD)
fulfil = M.mc("fulfil-righteousness", "Where does the phrase “to fulfil all righteousness,” used in 2 Nephi 31, first appear in the Bible?",
              ["Matthew 3:15, in Jesus's answer to John", "Acts 2:38", "John 17:21", "Acts 7:56"], 1,
              "In Matthew 3:15 Jesus says, “thus it becometh us to fulfil all righteousness.”",
              [(NE, "2 Nephi 31:5–6"), (ART, "Christ's own baptism")])
covenant = M.match("covenant-terms", "Terms of the covenant", "Match each promise to the passage that states it.",
                   [("Bear one another's burdens", "Mosiah 18:8"), ("Stand as witnesses of God at all times and in all things", "Mosiah 18:9"),
                    ("Take upon you the name of Christ", "2 Nephi 31:13"), ("God will pour out his Spirit more abundantly", "Mosiah 18:10")],
                   "Citing each term of the baptismal covenant to its verse keeps a description accurate.",
                   [(BAP, "Mosiah 18:8–10"), (NE, "2 Nephi 31:13")], overlaps=[b[0], b[2]])

M.set_article("article.md", 16, {
    "The doctrine of Christ": [phrase],
    "Christ's own baptism": [fulfil],
    "Faith and repentance": [a[5]],
    "Baptism: the gate": [gate],
    "How baptism is performed": [authority],
    "The baptismal covenant": [b[1]],
    "A sequence, not a checklist": [a[6]],
    "Describing it well": [gift],
})
M.reading("2ne31", "2 Nephi 31", 15,
          ["Why, according to Nephi, was Christ baptized?",
           "What does Nephi call the gate, and what follows it?",
           "What does Nephi say is required after entering the path?"],
          a, passages=[{"chapterID": "bofm.2-ne.31", "from": 1, "to": 21}])
M.reading("baptism", "Mosiah 18:8–10, Acts 2:37–38 and 3 Nephi 11:21–26", 10,
          ["What are people willing to do, according to Mosiah 18:8–9?",
           "What does God promise in Mosiah 18:10?",
           "How is baptism to be performed, and by whom, in 3 Nephi 11?"],
          b, passages=[{"chapterID": "bofm.mosiah.18", "from": 8, "to": 10}, {"chapterID": "nt.acts.2", "from": 37, "to": 38}, {"chapterID": "bofm.3-ne.11", "from": 21, "to": 26}])
M.set_practice("Terms of the covenant", covenant)
M.set_essay([
    ("Explain the first steps of the doctrine of Christ as 2 Nephi 31 presents them. Use Nephi's image of the gate and the path.",
     "Faith in Christ with full purpose of heart and real intent (v13, 19); repentance (v11, 13, 17); baptism following Christ's example (v5–10); the gate is repentance and baptism, then remission by fire and the Holy Ghost (v17); the path continues (v18–20). Uses the passage's own terms."),
    ("Describe the baptismal covenant from Mosiah 18:8–10 and 2 Nephi 31:13. What do people promise, and what does God promise?",
     "People: to come into the fold of God, bear burdens, mourn, comfort, stand as witnesses, serve God and keep commandments (Mosiah 18:8–10), and take the name of Christ (2 Ne 31:13). God: to pour out his Spirit more abundantly (Mosiah 18:10). Strong answers cite verses for each term."),
    ("Explain how baptism is performed and why authority matters in Latter-day Saint teaching, citing 3 Nephi 11 and the Articles of Faith.",
     "Immersion (3 Ne 11:26; AoF 4) with the prescribed words beginning “Having authority given me of Jesus Christ” (v25); Christ gives power to baptize (v21–22); AoF 5 requires a call by prophecy and laying on of hands by those in authority. May note that this is why converts are baptized again."),
])
M.build(os.path.dirname(os.path.abspath(__file__)))
