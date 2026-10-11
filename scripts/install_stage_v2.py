#!/usr/bin/env python3
"""Install a whole v2 stage into a Scholar Path file: its courses' modules, each course's
checkpoint (objective questions across the course's modules, plus an essay) and the stage's
advancement exam (across every module in the stage, plus an essay).

    python3 scripts/install_stage_v2.py documents/courses/lds-doctrine/v2/stage1.json \
        --path Hearken/Resources/Content/path-lds-doctrine.json \
        --bank-dir Hearken/Resources/Content

The manifest names the modules (folders holding module.json and question-banks/) and the
check specs; paths in it are relative to the manifest. One bank-<moduleID>.json is written per
module. Refuses to write if any question is missing or a quiz can't be drawn.
"""
import argparse, glob, json, os, sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from module_v2_to_path import load, module_items, used_questions, check_quiz


def eligible(questions, ids, use):
    return [i for i in ids if use in questions[i].get("eligibleAssessmentTypes", [])]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("--path", required=True)
    ap.add_argument("--bank-dir", required=True)
    args = ap.parse_args()

    base = os.path.dirname(os.path.abspath(args.manifest))
    manifest = load(args.manifest)
    questions = {}
    for pattern in manifest["banks"]:
        for bank_path in glob.glob(os.path.join(base, pattern)):
            for q in load(bank_path)["questions"]:
                questions[q["id"]] = q

    path = load(args.path)
    stage = next(s for s in path["stages"] if s["number"] == manifest["stage"])
    errors = []
    stage_groups = []
    banks = {}
    for spec in manifest["courses"]:
        course = next(c for c in stage["courses"] if c["id"] == spec["id"])
        modules, groups = [], []
        for folder in spec["modules"]:
            module = load(os.path.join(base, folder, "module.json"))
            items = module_items(module, questions, errors)
            modules.append({"id": module["id"], "number": module["number"], "title": module["title"],
                            "objectives": [o["text"] for o in module["objectives"]], "keyPoints": [], "items": items})
            used = sorted(used_questions(items))
            banks[module["id"]] = used
            groups.append([q for q in module["moduleQuiz"]["questionPool"] if q in questions])
        course["modules"] = modules
        if "summary" in spec:
            course["summary"] = spec["summary"]
        cp = spec["checkpoint"]
        cgroups = [eligible(questions, g, "course_checkpoint") for g in groups]
        pool = [q for g in cgroups for q in g]
        quiz = {"questionPool": pool, "questionCount": cp["questionCount"], "passCount": cp["passCount"],
                "maxTrueFalse": cp["maxTrueFalse"], "maxMatching": cp["maxMatching"], "groups": cgroups}
        check_quiz(cp["id"], quiz, questions, errors)
        course["checkpoint"] = {"id": cp["id"], "questionPool": [], "questionCount": cp["questionCount"], "passPercent": 80,
                                "quiz": quiz, "essay": cp["essay"]}
        stage_groups.extend(groups)

    # Optional videos keep a reading alternative: old v1 lessons map to the new articles.
    alternatives = manifest.get("videoAlternatives", {})
    for course in stage["courses"]:
        for video in course.get("videos", []):
            alt = video.get("alternativeItemID")
            if alt in alternatives:
                video["alternativeItemID"] = alternatives[alt]

    ex = manifest["advancement"]
    sgroups = [eligible(questions, g, "stage_advancement") for g in stage_groups]
    pool = [q for g in sgroups for q in g]
    quiz = {"questionPool": pool, "questionCount": ex["questionCount"], "passCount": ex["passCount"],
            "maxTrueFalse": ex["maxTrueFalse"], "maxMatching": ex["maxMatching"], "groups": sgroups}
    check_quiz(ex["id"], quiz, questions, errors)
    stage["advancementCheck"] = {"id": ex["id"], "questionPool": [], "questionCount": ex["questionCount"], "passPercent": 80,
                                 "quiz": quiz, "essay": ex["essay"]}

    ids = [i["id"] for c in stage["courses"] for m in c["modules"] for i in m["items"]]
    dupes = [i for i, n in Counter(ids).items() if n > 1]
    if dupes:
        errors.append(f"duplicate item IDs: {dupes}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(1)

    # Old bank files for this stage's modules are replaced.
    for old in glob.glob(os.path.join(args.bank_dir, "bank-*.json")):
        if os.path.basename(old)[5:-5] in banks or os.path.basename(old)[5:-5].startswith(tuple(c["id"] for c in manifest["courses"])):
            os.remove(old)
    for mid, used in banks.items():
        with open(os.path.join(args.bank_dir, f"bank-{mid}.json"), "w", encoding="utf-8") as f:
            json.dump({"moduleID": mid, "questions": [questions[i] for i in used]}, f, ensure_ascii=False, indent=1)
    with open(args.path, "w", encoding="utf-8") as f:
        json.dump(path, f, ensure_ascii=False, indent=1)

    xp = sum(sum({"article": 50, "quiz": 80, "essay": 60}.get(i["kind"], 40 if i["kind"] == "reading" else 30) for i in m["items"])
             for c in stage["courses"] for m in c["modules"]) + sum(c["checkpoint"]["questionCount"] * 10 for c in stage["courses"])
    print(f"Stage {stage['number']}: {len(ids)} items in {sum(len(c['modules']) for c in stage['courses'])} modules; "
          f"checkpoints draw from {[len(c['checkpoint']['quiz']['questionPool']) for c in stage['courses']]}; exam from {len(pool)}; "
          f"required XP {xp}; {sum(len(v) for v in banks.values())} questions in {len(banks)} bank files")


if __name__ == "__main__":
    main()
