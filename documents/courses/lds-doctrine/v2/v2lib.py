"""Authoring helpers for Hearken v2 modules.

A module script builds a Module, adds sources and questions, the article, readings, practice,
module quiz and essay, then calls build(outdir) to write:
  module.json                                    the module definition
  question-banks/<moduleID>-additions.json       its new questions (assessment-design bank format)
Existing reviewed questions are referenced by ID and must be passed to the installer's --banks.
"""
import json, os

STAGE1_RUBRIC = [
    {"id": "accuracy", "title": "Accuracy", "full": "States each teaching as its sources do", "partial": "Mostly accurate, with a loose or blurred point", "none": "Misstates the teaching, or answers a different question"},
    {"id": "evidence", "title": "Evidence", "full": "Cites an assigned source with chapter and verse, or title and section", "partial": "Names a source without a precise reference", "none": "No source, or a source that doesn't support the claim"},
    {"id": "precision", "title": "Precision and fairness", "full": "Scopes each claim to what its source shows and describes other views as their own sources would", "partial": "One claim is broader than its source", "none": "Sweeping claims, or a caricature of another tradition"},
]

GUIDE = {"id": "authority", "title": "Approaching Latter-day Saint Doctrine",
         "url": "https://newsroom.churchofjesuschrist.org/article/approaching-mormon-doctrine",
         "perspective": "Latter-day Saint institutional", "rights": "link_only"}


class Module:
    def __init__(self, mid, number, course, title, summary, objective_id, objective_text):
        self.id, self.number, self.course, self.title, self.summary = mid, number, course, title, summary
        self.objective = {"id": objective_id, "text": objective_text}
        self.sources = []
        self.questions = []
        self.n = 0
        self.m = 100
        self.article = None
        self.readings = []
        self.practice = None
        self.extra_pool = []
        self.essay = None
        self.source("article", f"{title} (Hearken article)", perspective="Original Hearken teaching method", rights="original_content")

    # sources
    def source(self, sid, title, url=None, passage=None, perspective="Latter-day Saint canonical text", rights=None):
        s = {"id": sid, "title": title, "perspective": perspective,
             "rights": rights or ("link_only" if url else "existing_app_text"),
             "verifiedDate": "2026-10-10",
             "verificationMethod": "web_fetch_read" if url else ("local_scripture_text_check" if passage else "authored")}
        if url: s["url"] = url
        if passage: s["passage"] = passage
        self.sources.append(s)
        return sid

    def _src(self, sources):
        ids = [s if isinstance(s, str) else s[0] for s in sources]
        locs = [{"sourceID": s, "locator": "Whole source"} if isinstance(s, str) else {"sourceID": s[0], "locator": s[1]} for s in sources]
        return ids, locs

    def _base(self, family, difficulty, perspective, uses):
        return {"revision": 1, "subjectID": "lds-doctrine", "courseID": self.course, "moduleID": self.id,
                "objectiveIDs": [self.objective["id"]], "questionFamilyID": f"{self.id}:{family}",
                "difficulty": difficulty, "perspective": perspective,
                "eligibleAssessmentTypes": uses or ["lesson_check", "reading_check", "practice", "course_checkpoint", "stage_advancement"]}

    def mc(self, family, prompt, options, correct, explanation, sources, difficulty="introductory", perspective="Latter-day Saint canonical text", uses=None):
        assert len(options) == 4 and 1 <= correct <= 4 and len(set(o.casefold() for o in options)) == 4, prompt
        self.n += 1
        ids, locs = self._src(sources)
        q = {"id": f"{self.id}-bank-q{100 + self.n:03d}", "type": "multiple_choice", "prompt": prompt,
             "options": [{"id": f"o{i+1}", "text": t} for i, t in enumerate(options)], "correctOptionID": f"o{correct}",
             "explanation": explanation, "sourceIDs": ids, "sourceLocators": locs}
        q.update(self._base(family, difficulty, perspective, uses))
        self.questions.append(q)
        return q["id"]

    def tf(self, family, prompt, truth, explanation, sources, perspective="Latter-day Saint canonical text", uses=None):
        self.n += 1
        ids, locs = self._src(sources)
        q = {"id": f"{self.id}-bank-q{100 + self.n:03d}", "type": "true_false", "prompt": prompt,
             "options": [{"id": "o1", "text": "True"}, {"id": "o2", "text": "False"}], "correctOptionID": "o1" if truth else "o2",
             "explanation": explanation, "sourceIDs": ids, "sourceLocators": locs}
        q.update(self._base(family, "introductory", perspective, uses))
        self.questions.append(q)
        return q["id"]

    def match(self, family, title, prompt, pairs, explanation, sources, overlaps=(), difficulty="introductory", perspective="Latter-day Saint canonical text"):
        """pairs: list of (left, right) texts in answer order. Right items are stored in a fixed scrambled order."""
        assert 3 <= len(pairs) <= 5
        self.m += 1
        ids, locs = self._src(sources)
        left = [{"id": f"l{i+1}", "text": l} for i, (l, _) in enumerate(pairs)]
        right_ids = [f"r{i+1}" for i in range(len(pairs))]
        order = right_ids[1:] + right_ids[:1]
        texts = {f"r{i+1}": r for i, (_, r) in enumerate(pairs)}
        q = {"id": f"{self.id}-match-q{self.m:03d}", "type": "matching", "title": title, "prompt": prompt,
             "instructions": "Match each item on the left to exactly one answer on the right. Use every answer once.",
             "leftItems": left, "rightItems": [{"id": r, "text": texts[r]} for r in order],
             "correctPairs": [{"leftID": f"l{i+1}", "rightID": f"r{i+1}"} for i in range(len(pairs))],
             "explanation": explanation, "sourceIDs": ids, "sourceLocators": locs,
             "scoring": {"maxPoints": 1, "method": "all_pairs_correct", "partialFeedback": True, "awardAdditionalXP": False},
             "presentation": {"shuffleLeftItems": True, "shuffleRightItems": True, "requireIndependentOrder": True,
                              "interactionModes": ["tap_to_pair", "drag_to_pair"],
                              "accessibility": "Every pair must be makeable by tapping a left item, then a right item; dragging is optional."},
             "overlapsWithQuestionIDs": list(overlaps)}
        q.update(self._base(family, difficulty, perspective, ["lesson_check", "practice", "course_checkpoint", "stage_advancement"]))
        self.questions.append(q)
        return q["id"]

    # structure
    def set_article(self, path, minutes, checks):
        self.article = {"path": path, "minutes": minutes, "checks": checks}

    def reading(self, slug, title, minutes, focus, pool, passages=None, source=None):
        r = {"id": f"{self.id}-reading-{slug}", "title": title, "minutes": minutes, "xp": 40, "focusQuestions": focus,
             "quiz": {"questionPool": pool, "questionCount": 5, "passCount": 4, "maxTrueFalse": 1}}
        if passages: r["passages"] = passages
        if source: r["source"] = source
        self.readings.append(r)

    def set_practice(self, title, qid, minutes=10):
        self.practice = {"id": f"{self.id}-practice", "title": title, "minutes": minutes, "xp": 30, "questionID": qid}

    def add_to_pool(self, *ids):
        self.extra_pool.extend(ids)

    def set_essay(self, prompts):
        self.essay = {"id": f"{self.id}-essay", "minutes": 20, "xp": 60, "minWords": 150, "maxWords": 250, "revisionsBeforeCompletion": 3,
                      "rubric": STAGE1_RUBRIC,
                      "prompts": [{"id": f"{self.id}-essay-p{i+1}", "prompt": p, "guide": g} for i, (p, g) in enumerate(prompts)]}

    def build(self, outdir):
        md = open(os.path.join(outdir, self.article["path"]), encoding="utf-8").read()
        heads = {l[3:].strip() for l in md.splitlines() if l.startswith("## ")}
        for h in self.article["checks"]:
            assert h in heads, f"{self.id}: no heading {h!r}"
        pool = []
        for qid in [q["id"] for q in self.questions] + self.extra_pool:
            if qid not in pool: pool.append(qid)
        module = {
            "id": self.id, "number": self.number, "title": self.title, "summary": self.summary,
            "objectives": [self.objective],
            "article": {"id": f"{self.id}-article", "title": self.title, "minutes": self.article["minutes"], "xp": 50, "markdown": md,
                        "sectionChecks": [{"section": h, "questionIDs": ids} for h, ids in self.article["checks"].items()]},
            "readings": self.readings, "practice": self.practice,
            "moduleQuiz": {"id": f"{self.id}-quiz", "minutes": 15, "xp": 80, "questionCount": 12, "passCount": 10, "maxTrueFalse": 2, "maxMatching": 1, "questionPool": pool},
            "essay": self.essay,
        }
        bank = {"schemaVersion": "1.1", "contentVersion": 1, "status": "draft_pending_review", "subjectID": "lds-doctrine",
                "courseID": self.course, "moduleID": self.id, "title": self.title, "objectives": [self.objective],
                "sources": self.sources + [GUIDE], "questions": self.questions,
                "review": {"note": "Authored by Claude for Hearken's v2 course; scripture wording checked against the app's text and linked pages read in full. Needs Steve's review before shipping."}}
        os.makedirs(os.path.join(outdir, "question-banks"), exist_ok=True)
        json.dump(module, open(os.path.join(outdir, "module.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        json.dump(bank, open(os.path.join(outdir, "question-banks", f"{self.id}-additions.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        tf = sum(q["type"] == "true_false" for q in self.questions)
        mt = sum(q["type"] == "matching" for q in self.questions)
        print(f"{self.id}: {len(self.questions)} new ({tf} TF, {mt} matching), pool {len(pool)}; readings {[len(r['quiz']['questionPool']) for r in self.readings]}")
