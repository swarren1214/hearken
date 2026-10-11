#!/usr/bin/env python3
"""Install a v2 module into a Scholar Path file and write its question bank.

    python3 scripts/module_v2_to_path.py \
        documents/courses/lds-doctrine/v2/c01-m01/module.json \
        --banks documents/courses/lds-doctrine/v2/c01-m01/question-banks/*.json \
        --path Hearken/Resources/Content/path-lds-doctrine.json \
        --bank-out Hearken/Resources/Content/bank-lds-doctrine-c01-m01.json

The module with the same ID in the path file has its items replaced by the v2 steps:
article, readings (each with a quiz), practice, module quiz, essay. Every question the module
uses must be in one of the banks; only those questions are written to the bank file.
The script refuses to write if a quiz can't be drawn (too few families) or an ID is missing.
"""
import argparse, json, sys
from collections import Counter


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def check_quiz(name, quiz, questions, errors):
    pool = quiz["questionPool"]
    missing = [i for i in pool if i not in questions]
    if missing:
        errors.append(f"{name}: missing questions {missing}")
        return
    families = Counter(questions[i]["questionFamilyID"] for i in pool)
    if len(families) < quiz["questionCount"]:
        errors.append(f"{name}: {len(families)} families can't fill {quiz['questionCount']} questions")
    if quiz["passCount"] > quiz["questionCount"]:
        errors.append(f"{name}: pass mark above question count")


def module_items(module, questions, errors):
    """The path items for one v2 module: article, readings, practice, module quiz, essay."""
    art = module["article"]
    items = [{
        "id": art["id"], "kind": "article", "title": module["title"], "required": True,
        "minutes": art["minutes"], "body": art["markdown"], "prompt": "",
        "sectionChecks": art["sectionChecks"],
    }]
    headings = {line[3:].strip() for line in art["markdown"].splitlines() if line.startswith("## ")}
    for check in art["sectionChecks"]:
        if check["section"] not in headings:
            errors.append(f"{module['id']} article: section check for unknown heading {check['section']!r}")
        for qid in check["questionIDs"]:
            if qid not in questions:
                errors.append(f"{module['id']} article: missing question {qid}")
    for reading in module["readings"]:
        item = {"id": reading["id"], "kind": "reading", "title": reading["title"], "required": True,
                "minutes": reading["minutes"], "prompt": "", "focusQuestions": reading["focusQuestions"], "quiz": reading["quiz"]}
        if "passages" in reading:
            item["passages"] = reading["passages"]
        if "source" in reading:
            src = reading["source"]
            item["source"] = {"title": src["title"], "url": src["url"], "note": src.get("perspective")}
        check_quiz(reading["id"], reading["quiz"], questions, errors)
        items.append(item)
    practice = module["practice"]
    if practice["questionID"] not in questions:
        errors.append(f"{module['id']} practice: missing question {practice['questionID']}")
    items.append({"id": practice["id"], "kind": "practice", "title": practice["title"], "required": True,
                  "minutes": practice["minutes"], "prompt": "", "questionID": practice["questionID"]})
    quiz = module["moduleQuiz"]
    spec = {k: quiz[k] for k in ("questionPool", "questionCount", "passCount", "maxTrueFalse", "maxMatching") if k in quiz}
    check_quiz(f"{module['id']} module quiz", spec, questions, errors)
    items.append({"id": quiz["id"], "kind": "quiz", "title": "Module quiz", "required": True,
                  "minutes": quiz["minutes"], "prompt": "", "quiz": spec})
    essay = module["essay"]
    items.append({"id": essay["id"], "kind": "essay", "title": "Essay", "required": True,
                  "minutes": essay["minutes"], "prompt": "",
                  "essay": {k: essay[k] for k in ("minWords", "maxWords", "revisionsBeforeCompletion", "rubric", "prompts")}})
    return items


def used_questions(items):
    used = set()
    for item in items:
        used.update(item.get("quiz", {}).get("questionPool", []))
        for check in item.get("sectionChecks", []):
            used.update(check["questionIDs"])
        if item.get("questionID"):
            used.add(item["questionID"])
    return used


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("module")
    ap.add_argument("--banks", nargs="+", required=True)
    ap.add_argument("--path", required=True)
    ap.add_argument("--bank-out", required=True)
    args = ap.parse_args()

    module = load(args.module)
    questions = {}
    for bank_path in args.banks:
        for q in load(bank_path)["questions"]:
            questions[q["id"]] = q
    errors = []
    items = module_items(module, questions, errors)
    if len({i["id"] for i in items}) != len(items):
        errors.append("duplicate item IDs")
    path = load(args.path)
    target = next((m for st in path["stages"] for c in st["courses"] for m in c["modules"] if m["id"] == module["id"]), None)
    if target is None:
        errors.append(f"module {module['id']} not found in {args.path}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(1)
    target["title"] = module["title"]
    target["objectives"] = [o["text"] for o in module["objectives"]]
    target["keyPoints"] = target.get("keyPoints", [])
    target["items"] = items
    bank = {"moduleID": module["id"], "questions": [questions[i] for i in sorted(used_questions(items))]}
    with open(args.path, "w", encoding="utf-8") as f:
        json.dump(path, f, ensure_ascii=False, indent=1)
    with open(args.bank_out, "w", encoding="utf-8") as f:
        json.dump(bank, f, ensure_ascii=False, indent=1)
    print(f"{module['id']}: {len(items)} items installed; {len(bank['questions'])} questions written to {args.bank_out}")


if __name__ == "__main__":
    main()
