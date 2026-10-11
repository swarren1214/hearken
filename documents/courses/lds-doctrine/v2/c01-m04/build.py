import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from v2lib import Module

M = Module("lds-doctrine-c01-m04", "1.4", "lds-doctrine-c01", "Unity language and the Nicene comparison",
           "Compare Latter-day Saint and Catholic teaching on the Godhead and the Trinity in terms each would call fair.",
           "lds-doctrine-c01-m02-objective-02", "Represent Nicene belief without caricature.")
NE = M.source("3ne-11", "3 Nephi 11:1–41", passage={"chapterID": "bofm.3-ne.11", "from": 1, "to": 41})
CCC = M.source("catholic-trinity", "Catechism of the Catholic Church §§232–267", url="https://www.vatican.va/archive/ENG0015/__P17.HTM",
               perspective="Roman Catholic institutional")
ART = "article"
METHOD = "Original Hearken reading method grounded in the cited sources"
CATH = "Roman Catholic institutional"
COMP = "Comparative reading of Latter-day Saint and Roman Catholic institutional sources"
OLD = {k: f"lds-doctrine-c01-m02-bank-q{k}" for k in ["004", "006", "008", "010"]}
OLDM = "lds-doctrine-c01-m02-match-q002"

# Reading A: 3 Nephi 11
a = [
    M.mc("3ne11-voice", "In 3 Nephi 11:7, what does the voice from heaven say?",
         ["“Behold my Beloved Son, in whom I am well pleased … hear ye him.”", "“Behold, I am Jesus Christ.”",
          "“Arise and come forth unto me.”", "“On this wise shall ye baptize.”"], 1,
         "Verse 7 records the Father's voice introducing the Son. Christ himself speaks the other words, in verses 10, 14 and 22.",
         [(NE, "3 Nephi 11:7")]),
    M.mc("3ne11-one", "According to 3 Nephi 11:27, what does Christ say about the Father, the Son and the Holy Ghost?",
         ["That they are one, and that he is in the Father and the Father in him", "That they are three gods",
          "That only the Father is God", "That the Holy Ghost is the Father"], 1,
         "Verse 27: “the Father, and the Son, and the Holy Ghost are one; and I am in the Father, and the Father in me.”",
         [(NE, "3 Nephi 11:27")]),
    M.mc("3ne11-words", "Which words does 3 Nephi 11:25 give for baptism?",
         ["“Having authority given me of Jesus Christ, I baptize you in the name of the Father, and of the Son, and of the Holy Ghost. Amen.”",
          "“I baptize you in the name of Jesus Christ only.”", "“By the power of the Holy Ghost, I baptize you.”", "“In the name of the Godhead, I baptize you.”"], 1,
         "Verse 25 gives the prayer exactly, beginning with authority from Jesus Christ and naming all three.",
         [(NE, "3 Nephi 11:25")]),
    M.mc("3ne11-reading", "How do Latter-day Saint readers usually take the oneness language in 3 Nephi 11?",
         ["As unity of purpose and witness among distinct beings, since the chapter also speaks of them distinctly",
          "As teaching one divine substance shared by three persons", "As teaching that Christ and the Father are one person",
          "As a passage that contradicts the rest of their scripture"], 1,
         "Latter-day Saints read verses 27 and 36 alongside verses 7, 11 and 32, where the Father's voice, the Son and the Holy Ghost act distinctly. That is the tradition's reading of its own scripture.",
         [(NE, "3 Nephi 11:7, 11, 27, 32, 36"), (ART, "\"One\" in 3 Nephi 11")], difficulty="application", perspective=METHOD),
    M.mc("3ne11-contention", "What does Christ say about disputes in 3 Nephi 11:28–29?",
         ["There should be no disputations about his doctrine, and the spirit of contention is not of him",
          "Disputes are the best way to find the truth", "Only leaders may discuss doctrine", "Contention is acceptable about baptism"], 1,
         "Verse 28 says there shall be no disputations about baptism or “the points of my doctrine,” and verse 29 says “he that hath the spirit of contention is not of me.”",
         [(NE, "3 Nephi 11:28–29")]),
    M.tf("3ne11-record", "In 3 Nephi 11:32, Christ says the Holy Ghost bears record of the Father and of him.", True,
         "Verse 32: “the Holy Ghost beareth record of the Father and me.”",
         [(NE, "3 Nephi 11:32")]),
    M.mc("3ne11-distinct", "Which verse shows the chapter speaking of the Father and the Son distinctly?",
         ["Verse 11, where Christ says he has suffered “the will of the Father in all things”", "Verse 1, where a multitude gathers at the temple",
          "Verse 19, where Nephi bows at the Lord's feet", "Verse 41, where Christ sends them to declare his words"], 1,
         "In verse 11 the Son speaks of doing the Father's will. The other verses describe the people or a commission, not the relation of Father and Son.",
         [(NE, "3 Nephi 11:11")]),
]

# Reading B: Catechism §§232–267
b = [
    M.mc("ccc-253", "According to the Catechism (paragraph 253), what does the Catholic Church confess?",
         ["One God in three persons, not three Gods", "Three Gods united in purpose", "One person who appears in three roles", "A Father who alone is God"], 1,
         "Paragraph 253 says the Church does not confess three Gods but one God in three persons. The other options describe views the Catechism rejects.",
         [(CCC, "CCC 253")], perspective=CATH),
    M.mc("ccc-252-substance", "In the Catechism's vocabulary (paragraph 252), what does “substance” name?",
         ["The divine being in its unity", "Each person in their distinction", "The relationships among the persons", "The Son's human body"], 1,
         "Paragraph 252 uses substance (essence, nature) for the divine being in its unity, person for the real distinction, and relation for how that distinction consists.",
         [(CCC, "CCC 252")], perspective=CATH),
    M.mc("ccc-254", "What does the Catechism (paragraph 254) say about the divine persons?",
         ["They are really distinct, not mere modes of the divine being, and differ by their relations of origin",
          "They are three modes in which one person appears", "They are separate beings with separate substances", "They differ only in their names"], 1,
         "Paragraph 254 says the persons are really distinct and not modes, distinguished by relations of origin: the Father begets, the Son is begotten, the Spirit proceeds.",
         [(CCC, "CCC 254")], difficulty="application", perspective=CATH),
    M.mc("ccc-nicaea", "According to the Catechism (paragraph 242), what did the Council of Nicaea in 325 confess about the Son?",
         ["That he is consubstantial with the Father", "That he was created before all ages", "That he is a separate embodied being", "That he is an angel"], 1,
         "Paragraph 242 says Nicaea confessed the Son consubstantial with the Father, one God with him.",
         [(CCC, "CCC 242")], perspective=CATH),
    M.tf("ccc-mystery", "The Catechism (paragraph 237) calls the Trinity a mystery that could not be known unless God revealed it.", True,
         "Paragraph 237 describes the Trinity as a mystery in the strict sense, known only through revelation.",
         [(CCC, "CCC 237")], perspective=CATH),
    M.mc("ccc-381", "According to the Catechism (paragraph 245), how did the Council of Constantinople in 381 confess the Holy Spirit?",
         ["As “the Lord and giver of life”", "As a creature made by the Son", "As another name for the Father", "As a force rather than a person"], 1,
         "Paragraph 245 cites Constantinople's confession of the Spirit as “the Lord and giver of life,” worshipped and glorified with the Father and the Son.",
         [(CCC, "CCC 245")], perspective=CATH),
    M.mc("ccc-234", "How does the Catechism (paragraph 234) describe the mystery of the Trinity?",
         ["As the central mystery of Christian faith and life", "As an optional teaching", "As a later Latin invention", "As a philosophical theory to be proven"], 1,
         "Paragraph 234 calls it the central mystery of Christian faith and life, the source of the other mysteries.",
         [(CCC, "CCC 234")], perspective=CATH),
]

# Article and module quiz
modalism = M.mc("modalism", "What is the view called that the Father, Son and Spirit are three modes or appearances of one person?",
                ["Modalism", "Tritheism", "Arianism", "Nicene orthodoxy"], 1,
                "That view is modalism, which the Catechism rejects in paragraph 254. Tritheism means three gods; Arianism held that the Son was created.",
                [(CCC, "CCC 254"), (ART, "Three caricatures to avoid")], perspective=COMP)
differ = M.mc("real-difference", "Where do Catholic and Latter-day Saint teaching really differ?",
              ["In the kind of oneness: one divine substance, or unity of purpose among separate beings",
               "In whether the Father, Son and Spirit are distinct", "In whether the three are one in any sense", "In whether Jesus Christ is named in their creeds or articles"], 1,
              "Both affirm that the three are distinct and in some sense one. The difference is what the oneness is: the Catechism's one substance, or Latter-day Saint unity of purpose among separate beings.",
              [(CCC, "CCC 252–254"), (ART, "Where the traditions really differ")], difficulty="application", perspective=COMP)
both = M.tf("both-affirm", "Both Catholic and Latter-day Saint teaching affirm that the Father, the Son and the Holy Spirit are distinct and that they are one.", True,
            "Both affirm distinctness and oneness; they differ on what kind of oneness it is.",
            [(ART, "Where the traditions really differ")], perspective=COMP)
first_step = M.mc("fair-first-step", "What is the first step in a fair comparison of two traditions?",
                  ["Describe each from its own authoritative sources", "Translate both into one tradition's vocabulary",
                   "Start with the strongest objection to each", "Find an analogy that fits both"], 1,
                  "Describing each tradition from its own sources comes first; the other approaches tend to import one side's meanings into the other.",
                  [(ART, "Writing a fair comparison")], perspective=METHOD)
person = M.mc("person-personage", "Which statement about “person” and “personage” is accurate?",
              ["In the Catechism, “person” names Father, Son and Spirit in their real distinction; in D&C 130:22, “personage” refers to an individual being",
               "Both sources use the word to mean the divine substance", "Neither source uses either word", "The Catechism uses “person” to mean a body of flesh and bones"], 1,
              "The traditions use related words differently: the Catechism's technical term defined by relation, and the canonical “personage” for an individual being, embodied or a spirit.",
              [(CCC, "CCC 252"), (ART, "Same words, different meanings")], difficulty="application", perspective=COMP)
cartoons = M.match("caricatures", "Correct the caricature", "Match each caricature to the source that corrects it.",
                   [("“One God wearing three masks”", "Catechism 254: the persons are really distinct, not modes"),
                    ("“Three gods with one label”", "Catechism 253: one God in three persons, not three Gods"),
                    ("“The Son is a created, lesser being”", "Nicaea (325), in Catechism 242: the Son is consubstantial with the Father"),
                    ("“Latter-day Saints don't believe in Jesus Christ”", "Article of Faith 1 and 3 Nephi 11 center on him")],
                   "Each caricature is answered by the tradition's own sources, which is the standard this module sets for comparison.",
                   [(CCC, "CCC 242, 253–254"), (NE, "3 Nephi 11"), (ART, "Three caricatures to avoid")],
                   overlaps=[b[0], b[2], b[3], modalism], difficulty="application", perspective=COMP)

M.add_to_pool(*OLD.values(), OLDM)
M.set_article("article.md", 17, {
    "Comparing fairly": [first_step],
    "\"One\" in 3 Nephi 11": [a[3]],
    "The Trinity in its own words": [b[1]],
    "Three caricatures to avoid": [modalism],
    "Where the traditions really differ": [differ],
    "Same words, different meanings": [person],
    "Writing a fair comparison": [OLD["006"]],
})
M.reading("3ne11", "3 Nephi 11:1–41", 15,
          ["Where does the chapter speak of the Father, the Son and the Holy Ghost as one?",
           "Where does it speak of them acting distinctly?",
           "What does Christ say about baptism and about disputes?"],
          a, passages=[{"chapterID": "bofm.3-ne.11", "from": 1, "to": 41}])
M.reading("catechism", "Catechism of the Catholic Church, paragraphs 232–267", 20,
          ["What do “substance,” “person” and “relation” mean in paragraph 252?",
           "Which views does the Catechism explicitly reject?",
           "What did the councils of Nicaea and Constantinople confess?"],
          b + [OLD["004"], OLD["010"]],
          source={"title": "Catechism of the Catholic Church, §§232–267", "url": "https://www.vatican.va/archive/ENG0015/__P17.HTM",
                  "publisher": "The Holy See", "perspective": CATH})
M.set_practice("Correct the caricature", cartoons)
M.set_essay([
    ("Explain the difference between Latter-day Saint teaching about the Godhead and Catholic teaching about the Trinity in a way a member of each tradition would call fair. Cite at least one source from each.",
     "Both name the three and affirm distinctness and oneness. Catholic: one God in three persons sharing one divine substance (CCC 252–253), persons really distinct by relation, not modes (254). Latter-day Saint: three separate beings one in purpose (Godhead page; 3 Nephi 11 read with distinct actions), Father and Son embodied (D&C 130:22). The real difference is the kind of oneness. No caricature of either side."),
    ("Name three common caricatures of the Trinity and show how the Catechism itself corrects each one. Then name one caricature of Latter-day Saint belief and correct it from its sources.",
     "Modalism corrected by CCC 254; three gods corrected by CCC 253; a created Son corrected by Nicaea's consubstantial (CCC 242). Latter-day Saint caricature, e.g. not believing in Christ, corrected by Article of Faith 1 or 3 Nephi 11."),
    ("Write a short two-column glossary for “one,” “person” and “being” as each tradition uses them. Then use it to explain 3 Nephi 11:27 and Catechism 253 side by side.",
     "One: Catholic unity of divine substance; Latter-day Saint unity of purpose and doctrine. Person: Catholic technical term defined by relation; “personage” in D&C 130:22 an individual being. Being: Latter-day Saint three separate beings; Catholic one divine being in three persons. 3 Nephi 11:27's “are one” read by Latter-day Saints as unity of purpose; CCC 253's one God in three persons as one substance."),
])
M.build(os.path.dirname(os.path.abspath(__file__)))
