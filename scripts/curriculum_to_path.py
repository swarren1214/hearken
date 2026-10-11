#!/usr/bin/env python3
"""Build the app's Scholar Path file from a course package's curriculum.json.

Usage:
    python3 scripts/curriculum_to_path.py PATH/TO/curriculum.json \
        [--unpublish 4] -o Hearken/Resources/Content/path-lds-doctrine.json

curriculum.json is the editorial master (stable IDs, award keys, answer guides, sources). This
keeps its IDs and award keys exactly, so XP already earned stays earned when wording changes.
Every check question becomes a short answer scored on device against its answer guide, unless
the master marks it "multipleChoice" with "options" and "answer".

Note: answer guides ship in the app because on-device scoring needs them. The app never shows a
check's guide to the learner.
"""
import argparse
import json
import re

STAGE_NAMES = {
    1: ("Foundations", "Define essential terms and describe the subject's central questions accurately."),
    2: ("Exploration", "Explain context, distinguish text from interpretation, and connect several course topics."),
    3: ("Comparison and evaluation", "Fairly describe competing perspectives and assess the relevance and limitations of evidence."),
    4: ("Synthesis", "Construct a supported explanation or argument, address a serious alternative, and disclose uncertainty."),
}


def short_title(text, limit=64):
    text = text.strip().rstrip(".")
    if len(text) <= limit:
        return text
    return text[:limit].rsplit(" ", 1)[0].rstrip(",;:") + "…"


def build(master, unpublish):
    sources = {s["id"]: s for s in master["sources"]}
    courses_by_id = {c["id"]: c for c in master["courses"]}
    modules_flat = [m for c in master["courses"] for m in c["modules"]]
    videos = {v["id"]: v for v in master["videos"]}

    def source_resource(source_id, note=None):
        s = sources.get(source_id)
        if not s:
            return None
        return {"title": s["title"], "url": s.get("url"), "note": note or s.get("perspective")}

    def reference_for(source_ids):
        names = [sources[i]["title"] for i in source_ids if i in sources]
        return "; ".join(names) or None

    def reading(r, module):
        item = {"id": r["id"], "kind": "reading", "title": r["reference"], "required": r["required"],
                "minutes": r.get("estimatedMinutes"), "prompt": r["prompt"], "guide": r.get("answerGuide"),
                "completion": r.get("completion")}
        if r.get("chapterID"):
            first, _, last = r["verses"].partition("-")
            item["passage"] = {"chapterID": r["chapterID"], "from": int(first), "to": int(last or first)}
        else:
            item["source"] = source_resource(r["sourceID"])
        if r.get("awardKey") and r["awardKey"] != r["id"]:
            item["equivalenceGroup"] = r["awardKey"]
        return item

    def module_out(course, index, m):
        lesson = m["lessonActivity"]
        items = [{"id": lesson["id"], "kind": "lesson", "title": m["title"], "required": lesson["required"],
                  "minutes": lesson.get("estimatedMinutes"), "body": m["lesson"],
                  "prompt": "Write a 2–3 sentence summary of the lesson that names one source and one limit.",
                  "completion": lesson.get("completion")}]
        items += [reading(r, m) for r in m["readings"]]
        for p in m["practices"]:
            items.append({"id": p["id"], "kind": "practice", "title": short_title(p["prompt"]), "required": p["required"],
                          "minutes": p.get("estimatedMinutes"), "prompt": p["prompt"],
                          "successCriteria": p.get("successCriteria"), "completion": p.get("completion")})
        items += [reading(r, m) for r in m.get("optionalReadings", [])]
        return {"id": m["id"], "number": f"{course['number']}.{index + 1}", "title": m["title"],
                "objectives": m.get("objectives", []), "keyPoints": m.get("learningItems", []), "items": items}

    def video_out(course, video_id):
        v = videos[video_id]
        fallback = v.get("fallback") or {}
        alt = modules_flat[fallback["moduleIndex"]]["lessonActivity"]["id"] if "moduleIndex" in fallback else None
        transcript = sources.get(v.get("transcriptSourceID"), {}).get("url")
        return {"id": f"{course['id']}-{v['id']}", "kind": "video", "title": v["title"], "required": v["required"],
                "minutes": 15, "prompt": v["completion"]["prompt"], "completion": v["completion"].get("criteria"),
                "video": {"provider": "youtube", "videoID": v["youtubeVideoID"], "speaker": v.get("speaker"), "transcriptURL": transcript},
                "alternativeItemID": alt, "equivalenceGroup": v["awardKey"]}

    questions = []

    def assessment(a):
        pool = []
        for q in a["questions"]:
            out = {"id": q["id"], "kind": q.get("kind", "shortAnswer"), "prompt": q["prompt"],
                   "guide": q.get("answerGuide"), "reference": reference_for(q.get("sourceIDs", []))}
            if out["kind"] == "multipleChoice":
                out["options"], out["answer"], out["explanation"] = q["options"], q["answer"], q.get("explanation")
            questions.append(out)
            pool.append(q["id"])
        return {"id": a["id"], "questionPool": pool, "questionCount": len(pool), "passPercent": a["passPercent"]}

    stages = []
    for st in sorted(master["stages"], key=lambda s: s["number"]):
        name, outcome = STAGE_NAMES.get(st["number"], (f"Stage {st['number']}", ""))
        courses = []
        for cid in st["courseIDs"]:
            c = courses_by_id[cid]
            books = []
            for b in master["books"]:
                if b["sourceID"] in c.get("optionalBookSourceIDs", []):
                    s = sources.get(b["sourceID"], {})
                    books.append({"title": s.get("title", b["sourceID"]), "url": s.get("url"), "note": b.get("use") or b.get("caution")})
            courses.append({
                "id": c["id"], "number": c["number"], "title": c["title"], "summary": c["milestone"],
                "milestone": c["milestone"], "objectives": [],
                "modules": [module_out(c, i, m) for i, m in enumerate(c["modules"])],
                "checkpoint": assessment(c["checkpoint"]) if c.get("checkpoint") else None,
                "videos": [video_out(c, vid) for vid in c.get("optionalVideoIDs", [])],
                "books": books,
            })
        stages.append({"number": st["number"], "title": name, "outcome": outcome,
                       "published": st["number"] not in unpublish, "courses": courses,
                       "advancementCheck": assessment(st["advancementCheck"]) if st.get("advancementCheck") else None})

    capstone = None
    for c in master["courses"]:
        cap = c.get("capstone")
        if cap:
            capstone = {"id": cap["id"], "title": cap["title"], "summary": "Formats: " + "; ".join(cap.get("formats", [])),
                        "requirements": cap.get("requirements", []),
                        "rubric": [f"{r['title']}: 0–3" for r in cap.get("rubric", [])]}

    return {"subjectID": master["subjectID"], "ruleVersion": 1, "contentVersion": master.get("contentVersion", 1),
            "title": master["title"], "summary": master.get("scopeNote", ""),
            "stages": stages, "capstone": capstone, "questions": questions}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("curriculum")
    ap.add_argument("--unpublish", type=int, action="append", default=[], help="stage number to hide (repeatable)")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()
    out = build(json.load(open(args.curriculum, encoding="utf-8")), set(args.unpublish))
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    items = sum(len(m["items"]) for s in out["stages"] for c in s["courses"] for m in c["modules"])
    print(f"Wrote {args.output}: {len(out['stages'])} stages, {sum(len(s['courses']) for s in out['stages'])} courses, "
          f"{items} module items, {len(out['questions'])} questions")


if __name__ == "__main__":
    main()
