#!/usr/bin/env python3
"""Check a Scholar Path JSON file before it ships.

Usage:
    python3 scripts/validate_path.py Hearken/Resources/Content/path-lds-doctrine.json

Errors (exit code 1) block shipping; warnings are things to know about.
Checks: unique IDs; XP budgets per stage (500 / 1,000 / 1,500 / 2,000) from required items
alone, using the app's XP schedule; every rank threshold reachable; scripture passages exist in
the bundled text; check pools hold enough questions and every question exists and is well formed;
video alternatives point at real lessons; optional items never needed for a threshold.
v2 module items (article, reading with quiz, matching practice, module quiz, essay) are checked
against the bank-*.json files next to the path: every question exists and every quiz can be
drawn with one question per family. While a stage mixes v1 and v2 modules (the pilot), a stage
over budget is a warning, not an error; the budgets move with the v2 rules.
"""
import json
import os
import sys
from collections import Counter

XP = {"lesson": 20, "reading": 30, "video": 20, "practice": 10, "article": 50, "quiz": 80, "essay": 60}


def is_v2(item):
    return item["kind"] in ("article", "quiz", "essay") or "quiz" in item or "questionID" in item


def item_xp(item):
    if item["kind"] == "reading" and "quiz" in item:
        return 40
    if item["kind"] == "practice" and "questionID" in item:
        return 30
    return XP[item["kind"]]


def check_v2(item, bank, errors):
    def need(qid, where):
        if qid not in bank:
            errors.append(f"{item['id']}: {where} question {qid} isn't in any bank file")
    quiz = item.get("quiz")
    if quiz:
        for qid in quiz["questionPool"]:
            need(qid, "quiz")
        families = {bank[q]["questionFamilyID"] for q in quiz["questionPool"] if q in bank}
        if len(families) < quiz["questionCount"]:
            errors.append(f"{item['id']}: {len(families)} question families can't fill a {quiz['questionCount']}-question quiz")
        if quiz["passCount"] > quiz["questionCount"]:
            errors.append(f"{item['id']}: pass mark above the question count")
    for check in item.get("sectionChecks", []):
        if f"## {check['section']}" not in (item.get("body") or ""):
            errors.append(f"{item['id']}: section check for missing heading {check['section']!r}")
        for qid in check["questionIDs"]:
            need(qid, "section check")
    if item.get("questionID"):
        need(item["questionID"], "practice")
    if item["kind"] == "article" and not item.get("body"):
        errors.append(f"{item['id']}: article has no body")
    if item["kind"] == "essay":
        essay = item.get("essay") or {}
        if not essay.get("prompts") or not essay.get("rubric"):
            errors.append(f"{item['id']}: essay needs prompts and a rubric")
CHECKPOINT_XP, CAPSTONE_XP = 100, 200
BUDGET = {1: 500, 2: 1000, 3: 1500, 4: 2000}
THRESHOLD = {1: 500, 2: 1500, 3: 3000, 4: 5000}


def main(path):
    data = json.load(open(path, encoding="utf-8"))
    content_dir = os.path.dirname(path)
    errors, warnings = [], []

    verses = {}
    for volume in ["ot", "nt", "bofm", "dc-testament", "pgp"]:
        file = os.path.join(content_dir, f"scripture-{volume}.json")
        if not os.path.exists(file):
            warnings.append(f"scripture-{volume}.json not found next to the path; passages not checked")
            continue
        for book in json.load(open(file, encoding="utf-8"))["volume"]["books"]:
            for chapter in book["chapters"]:
                verses[chapter["id"]] = {v["number"] for v in chapter["verses"]}

    questions = {q["id"]: q for q in data.get("questions", [])}
    bank = {}
    for name in os.listdir(content_dir):
        if name.startswith("bank-") and name.endswith(".json"):
            for q in json.load(open(os.path.join(content_dir, name), encoding="utf-8"))["questions"]:
                bank[q["id"]] = q
    ids = Counter()
    lessons = set()
    for stage in data["stages"]:
        for course in stage["courses"]:
            ids[course["id"]] += 1
            for module in course["modules"]:
                ids[module["id"]] += 1
                for item in module["items"]:
                    if item["kind"] in ("lesson", "article"):
                        lessons.add(item["id"])
    for qid in questions:
        ids[qid] += 1

    cumulative = 0
    award_keys = Counter()
    for stage in sorted(data["stages"], key=lambda s: s["number"]):
        n = stage["number"]
        stage_xp = 0
        stage_has_v2 = False
        for course in stage["courses"]:
            items = [i for m in course["modules"] for i in m["items"]] + course.get("videos", [])
            course_xp = 0
            for item in items:
                ids[item["id"]] += 1
                kind = item["kind"]
                if kind not in XP:
                    errors.append(f"{item['id']}: unknown kind {kind}")
                    continue
                key = item.get("equivalenceGroup") or item["id"]
                award_keys[key] += 1
                if item["required"]:
                    if item.get("equivalenceGroup") and award_keys[key] > 1:
                        errors.append(f"{item['id']}: required item shares an award with an earlier item, so it pays nothing")
                    course_xp += item_xp(item)
                if is_v2(item):
                    stage_has_v2 = True
                    check_v2(item, bank, errors)
                elif not item.get("prompt"):
                    errors.append(f"{item['id']}: no prompt; learners need something to write")
                if kind == "lesson" and not item.get("body"):
                    errors.append(f"{item['id']}: lesson has no body")
                if kind == "practice" and not is_v2(item) and not item.get("successCriteria"):
                    warnings.append(f"{item['id']}: practice has no success criteria")
                if kind == "reading":
                    for p in item.get("passages") or ([item["passage"]] if item.get("passage") else []):
                        chapter = verses.get(p["chapterID"])
                        if verses and chapter is None:
                            errors.append(f"{item['id']}: chapter {p['chapterID']} isn't in the bundled scripture")
                        elif chapter is not None:
                            wanted = set(range(p["from"], min(p["to"], max(chapter)) + 1))
                            missing = sorted(wanted - chapter)
                            if missing:
                                errors.append(f"{item['id']}: {p['chapterID']} has no verse(s) {missing[:5]}")
                    if not (item.get("passages") or item.get("passage")) and not (item.get("source") or {}).get("url"):
                        errors.append(f"{item['id']}: reading has neither a passage nor a source link")
                if kind == "video":
                    if not (item.get("video") or {}).get("videoID"):
                        errors.append(f"{item['id']}: video has no ID")
                    alt = item.get("alternativeItemID")
                    if not alt:
                        warnings.append(f"{item['id']}: video has no reading alternative")
                    elif alt not in lessons:
                        errors.append(f"{item['id']}: alternative {alt} isn't a lesson in this path")
                    if item["required"]:
                        warnings.append(f"{item['id']}: required video; make sure the reading alternative is enough on its own")
            checkpoint = course.get("checkpoint")
            if checkpoint and checkpoint.get("quiz"):
                stage_has_v2 = True
                course_xp += checkpoint["quiz"]["questionCount"] * 10
                check_v2_assessment(checkpoint, bank, errors, warnings)
            elif checkpoint:
                course_xp += CHECKPOINT_XP
                check_pool(checkpoint, questions, errors, warnings, stage["published"])
            else:
                warnings.append(f"{course['id']}: no checkpoint")
            stage_xp += course_xp
        if n == 4 and data.get("capstone"):
            stage_xp += CAPSTONE_XP
        cumulative += stage_xp
        label = "" if stage["published"] else " (unpublished)"
        if n in BUDGET and stage_xp != BUDGET[n]:
            (warnings if stage_has_v2 else errors).append(f"Stage {n}{label}: required items give {stage_xp} XP; the budget is {BUDGET[n]}")
        # Rules v2 compute thresholds from required work, so a v2 stage always reaches its own.
        if n in THRESHOLD and cumulative < THRESHOLD[n] and not stage_has_v2:
            errors.append(f"Stage {n}{label}: required work reaches {cumulative} XP, short of the {THRESHOLD[n]} XP threshold")
        adv = stage.get("advancementCheck")
        if adv and adv.get("quiz"):
            check_v2_assessment(adv, bank, errors, warnings)
        elif adv:
            check_pool(adv, questions, errors, warnings, stage["published"])
        else:
            errors.append(f"Stage {n}: no advancement check")
        print(f"Stage {n} {stage['title']}{label}: {stage_xp} XP required work, {cumulative} cumulative")

    for key, count in ids.items():
        if count > 1:
            errors.append(f"duplicate ID {key}")
    for q in questions.values():
        if q["kind"] == "multipleChoice":
            opts = q.get("options") or []
            if len(opts) < 2 or not isinstance(q.get("answer"), int) or not 0 <= q["answer"] < len(opts):
                errors.append(f"{q['id']}: multiple choice needs options and a valid answer index")
        elif q["kind"] == "shortAnswer":
            if not q.get("guide"):
                errors.append(f"{q['id']}: short answer needs a guide for scoring")
        else:
            errors.append(f"{q['id']}: unknown question kind {q['kind']}")

    for w in warnings:
        print("warning:", w)
    for e in errors:
        print("ERROR:", e)
    print(f"\n{len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


def check_v2_assessment(assessment, bank, errors, warnings):
    quiz = assessment["quiz"]
    missing = [q for q in quiz["questionPool"] if q not in bank]
    if missing:
        errors.append(f"{assessment['id']}: {len(missing)} questions aren't in any bank file")
    families = {bank[q]["questionFamilyID"] for q in quiz["questionPool"] if q in bank}
    if len(families) < quiz["questionCount"]:
        errors.append(f"{assessment['id']}: {len(families)} question families can't fill a {quiz['questionCount']}-question check")
    elif len(families) < quiz["questionCount"] * 2:
        warnings.append(f"{assessment['id']}: {len(families)} families; retakes will repeat some questions")
    for i, group in enumerate(quiz.get("groups") or []):
        if not group:
            errors.append(f"{assessment['id']}: module group {i + 1} has no eligible questions, so it can't be covered")
    essay = assessment.get("essay")
    if not essay or not essay.get("prompts") or not essay.get("rubric"):
        errors.append(f"{assessment['id']}: v2 check needs an essay with prompts and a rubric")


def check_pool(assessment, questions, errors, warnings, published):
    pool = assessment.get("questionPool", [])
    for qid in pool:
        if qid not in questions:
            errors.append(f"{assessment['id']}: question {qid} doesn't exist")
    if not pool:
        (errors if published else warnings).append(f"{assessment['id']}: no questions yet, so it can't be passed")
    elif len(pool) < assessment["questionCount"]:
        errors.append(f"{assessment['id']}: {len(pool)} questions for a {assessment['questionCount']}-question check")
    elif len(pool) < assessment["questionCount"] * 2:
        warnings.append(f"{assessment['id']}: {len(pool)} questions; retakes will repeat questions (twice the check size gives fresh retakes)")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
