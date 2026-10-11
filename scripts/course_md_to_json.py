#!/usr/bin/env python3
"""Convert a Scholar Path course written in Markdown into the app's path JSON.

Usage:
    python3 scripts/course_md_to_json.py COURSE.md \
        --subject lds-doctrine --prefix ldsd \
        [--questions QUESTIONS.json] [--unpublish 4] \
        -o Hearken/Resources/Content/path-lds-doctrine.json

The Markdown follows the course template: "## Course N. Title", "### N.M. Module",
then **Objectives**, **Learning items**, **Original Hearken article · 20 XP**,
**Assigned readings · 30 XP each**, **Application · 10 XP per exercise**,
**Optional deeper reading**, **Course checkpoint**, **Optional YouTube / accessible
alternative**, **Optional books**, **Stage N advancement**, and a "## Sage capstone" section.

IDs come from position (course, module, item order), e.g. ldsd.c1.m2.read1. Adding an item at
the end of a list is safe; reordering or inserting in the middle changes later IDs, and XP is
keyed to IDs, so avoid that once a course has shipped.

Questions live in a separate JSON file (they are not in the course Markdown):
    {"questions": [{"id": "...", "assessment": "ldsd.c1.checkpoint", "kind": "multipleChoice",
                    "prompt": "...", "options": [...], "answer": 1, "explanation": "...",
                    "reference": "..."},
                   {"id": "...", "assessment": "ldsd.s1.advance", "kind": "shortAnswer",
                    "prompt": "...", "guide": "What a full-credit answer includes", "reference": "..."}]}
Each question's "assessment" puts it in that check's pool.
"""
import argparse
import json
import re
import sys

STAGE_NAMES = {
    1: ("Foundations", "Define essential terms and describe the subject's central questions accurately."),
    2: ("Exploration", "Explain context, distinguish text from interpretation, and connect several course topics."),
    3: ("Comparison and evaluation", "Fairly describe competing perspectives and assess the relevance and limitations of evidence."),
    4: ("Synthesis", "Construct a supported explanation or argument, address a serious alternative, and disclose uncertainty."),
}
# Planning estimates in minutes (the course gives none per item).
MINUTES = {"lesson": 10, "scripture": 10, "source": 15, "practice": 15, "video": 15}

LINK = re.compile(r"\[([^\]]+)\]\((https?://[^)]+)\)")
SCRIPTURE = re.compile(r"https://www\.churchofjesuschrist\.org/study/scriptures/([^/]+)/([^/]+)/(\d+)\?lang=eng(?:&id=p(\d+)(?:-p(\d+))?)?")
YOUTUBE = re.compile(r"(?:youtube\.com/watch\?v=|youtu\.be/)([\w-]{6,})")


def clean(text):
    return re.sub(r"\s+", " ", text).strip()


def passage(url):
    m = SCRIPTURE.match(url)
    if not m:
        return None
    volume, book, chapter, first, last = m.groups()
    first = int(first) if first else 1
    last = int(last) if last else (first if m.group(4) else 999)
    return {"chapterID": f"{volume}.{book}.{chapter}", "from": first, "to": last}


def reading_item(item_id, line, required):
    m = LINK.search(line)
    if not m:
        raise ValueError(f"reading without a link: {line}")
    title, url = m.group(1), m.group(2)
    prompt = clean(line[m.end():].lstrip(":").strip()) or "Summarize the reading and name one limit of what it shows."
    item = {"id": item_id, "kind": "reading", "title": title, "required": required, "prompt": prompt}
    p = passage(url)
    if p:
        item["passage"] = p
        item["minutes"] = MINUTES["scripture"]
    else:
        item["source"] = {"title": title, "url": url}
        item["minutes"] = MINUTES["source"]
    if not required:
        item["equivalenceGroup"] = "reading:" + (f"{p['chapterID']}:{p['from']}-{p['to']}" if p else url)
    return item


def short_title(text, limit=64):
    text = text.strip().rstrip(".")
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0].rstrip(",;:")
    return cut + "…"


def practice_item(item_id, line):
    text = clean(line)
    prompt, _, criteria = text.partition("Success criteria:")
    return {"id": item_id, "kind": "practice", "title": short_title(prompt), "required": True,
            "minutes": MINUTES["practice"], "prompt": prompt.strip(), "successCriteria": criteria.strip() or None}


def parse(md, prefix):
    lines = md.split("\n")
    title = clean(lines[0].lstrip("# ")) if lines and lines[0].startswith("# ") else "Course"
    intro = []
    for line in lines[1:]:
        if line.startswith("## "):
            break
        if line.strip():
            intro.append(clean(line))
    summary = intro[0] if intro else ""

    courses, stages_adv, capstone_lines = [], {}, []
    course = module = None
    section = None
    lesson_lines = []
    in_capstone = False

    def close_lesson():
        nonlocal lesson_lines
        if module is not None and lesson_lines:
            body, prompt = [], "Write a short summary naming one source and one interpretive limit."
            for text in lesson_lines:
                if text.startswith("Completion:"):
                    prompt = clean(text[len("Completion:"):])
                    prompt = prompt[0].upper() + prompt[1:]
                else:
                    body.append(text)
            module["items"].insert(0, {"id": f"{module['id']}.lesson", "kind": "lesson", "title": module["title"],
                                       "required": True, "minutes": MINUTES["lesson"],
                                       "body": "\n\n".join(body), "prompt": prompt})
        lesson_lines = []

    for raw in lines:
        line = raw.rstrip()
        m = re.match(r"^## Course (\d+)\. (.*)", line)
        if m:
            close_lesson()
            in_capstone = False
            course = {"id": f"{prefix}.c{m.group(1)}", "number": int(m.group(1)), "title": clean(m.group(2)),
                      "summary": "", "milestone": None, "objectives": [], "modules": [], "checkpoint": None,
                      "videos": [], "books": []}
            courses.append(course)
            module, section = None, None
            continue
        if line.startswith("## "):
            close_lesson()
            course, module, section = None, None, None
            in_capstone = line.lower().startswith("## sage capstone")
            continue
        if in_capstone:
            capstone_lines.append(line)
            continue
        if course is None:
            continue

        m = re.match(r"^\*\*Study tier:\*\*.*\*\*Milestone:\*\* (.*)", line)
        if m:
            course["milestone"] = clean(m.group(1))
            course["summary"] = course["milestone"]
            continue
        m = re.match(r"^### (\d+)\.(\d+)\. (.*)", line)
        if m:
            close_lesson()
            module = {"id": f"{prefix}.c{m.group(1)}.m{m.group(2)}", "number": f"{m.group(1)}.{m.group(2)}",
                      "title": clean(m.group(3)), "objectives": [], "keyPoints": [], "items": []}
            course["modules"].append(module)
            section = None
            continue
        if line.startswith("**"):
            close_lesson()
            label = line.strip("*").lower()
            if label.startswith("objectives"):
                section = "objectives"
            elif label.startswith("learning items"):
                section = "keypoints"
            elif label.startswith("original hearken article"):
                section = "lesson"
            elif label.startswith("assigned readings"):
                section = "readings"
            elif label.startswith("application"):
                section = "practice"
            elif label.startswith("optional deeper reading"):
                section = "optional"
            elif label.startswith("course checkpoint"):
                section = "checkpoint"
                course["checkpoint"] = {"id": f"{course['id']}.checkpoint", "questionPool": [], "questionCount": 10, "passPercent": 80}
            elif label.startswith("optional youtube"):
                section = "video"
            elif label.startswith("optional books"):
                section = "books"
            elif label.startswith("stage ") and "advancement" in label:
                section = "advancement"
                number = int(re.match(r"stage (\d+)", label).group(1))
                stages_adv[number] = {"id": f"{prefix}.s{number}.advance", "questionPool": [], "questionCount": 5, "passPercent": 80}
            else:
                section = None
            continue
        if section == "advancement" and line.strip():
            m = re.search(r"Pass (\w+) applied questions at (\d+)/(\d+)", line)
            if m:
                words = {"five": 5, "ten": 10, "six": 6, "eight": 8}
                count = words.get(m.group(1).lower(), 5)
                stages_adv[max(stages_adv)]["questionCount"] = count
                stages_adv[max(stages_adv)]["passPercent"] = round(100 * int(m.group(2)) / int(m.group(3)))
            continue
        if section == "lesson" and module is not None:
            if line.strip():
                lesson_lines.append(clean(line))
            continue
        if not line.startswith("- "):
            continue
        text = line[2:]
        if section == "objectives" and module is not None:
            module["objectives"].append(clean(text))
        elif section == "keypoints" and module is not None:
            module["keyPoints"].append(clean(text))
        elif section == "readings" and module is not None:
            n = sum(1 for i in module["items"] if i["kind"] == "reading" and i["required"]) + 1
            module["items"].append(reading_item(f"{module['id']}.read{n}", text, True))
        elif section == "optional" and module is not None:
            n = sum(1 for i in module["items"] if i["kind"] == "reading" and not i["required"]) + 1
            module["items"].append(reading_item(f"{module['id']}.extra{n}", text, False))
        elif section == "practice" and module is not None:
            n = sum(1 for i in module["items"] if i["kind"] == "practice") + 1
            module["items"].append(practice_item(f"{module['id']}.app{n}", text))
        elif section == "video":
            links = LINK.findall(text)
            video_title, url = links[0]
            vid = YOUTUBE.search(url)
            transcript = next((u for t, u in links[1:] if "transcript" in t.lower()), None)
            speaker = clean(text.split("—", 1)[1].split(";")[0]) if "—" in text else None
            task = re.search(r"Task: (.*?)(?: If unavailable|$)", text)
            alt = re.search(r"read the original article [“\"]([^”\"]+)[”\"]", text)
            n = len(course["videos"]) + 1
            course["videos"].append({
                "id": f"{course['id']}.video{n}", "kind": "video", "title": video_title, "required": False,
                "minutes": MINUTES["video"], "prompt": clean(task.group(1)) if task else "Summarize the main idea and one claim that needs a source.",
                "video": {"provider": "youtube", "videoID": vid.group(1) if vid else "", "speaker": speaker, "transcriptURL": transcript},
                "alternativeTitle": alt.group(1) if alt else None,
                "equivalenceGroup": f"video:{vid.group(1)}" if vid else None,
            })
        elif section == "books":
            m = LINK.search(text)
            if m:
                note = clean(text[m.end():].lstrip(" —-"))
                course["books"].append({"title": m.group(1), "url": m.group(2), "note": note or None})
    close_lesson()

    # Videos' reading alternatives point at the lesson with that title.
    lessons = {i["title"]: i["id"] for c in courses for mo in c["modules"] for i in mo["items"] if i["kind"] == "lesson"}
    for c in courses:
        for v in c["videos"]:
            v["alternativeItemID"] = lessons.get(v.pop("alternativeTitle", None) or "")

    # Two courses per stage, in order.
    stages = []
    for number in sorted({(c["number"] + 1) // 2 for c in courses}):
        name, outcome = STAGE_NAMES.get(number, (f"Stage {number}", ""))
        stages.append({"number": number, "title": name, "outcome": outcome, "published": True,
                       "courses": [c for c in courses if (c["number"] + 1) // 2 == number],
                       "advancementCheck": stages_adv.get(number)})

    capstone = None
    if capstone_lines:
        text = [clean(l) for l in capstone_lines if l.strip()]
        reqs = [clean(l[2:]) for l in capstone_lines if l.startswith("- ")]
        rubric_line = next((t for t in text if t.startswith("**Rubric:**")), "")
        capstone = {"id": f"{prefix}.capstone", "title": text[0] if text else "Capstone",
                    "summary": text[1] if len(text) > 1 else "", "requirements": reqs,
                    "rubric": [clean(rubric_line.replace("**Rubric:**", ""))] if rubric_line else []}

    return {"title": title, "summary": summary, "stages": stages, "capstone": capstone}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("markdown")
    ap.add_argument("--subject", required=True)
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--questions", help="JSON file of check questions")
    ap.add_argument("--unpublish", type=int, action="append", default=[], help="stage number to hide (repeatable)")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()

    parsed = parse(open(args.markdown, encoding="utf-8").read(), args.prefix)
    questions = []
    if args.questions:
        data = json.load(open(args.questions, encoding="utf-8"))
        checks = {c["checkpoint"]["id"]: c["checkpoint"] for s in parsed["stages"] for c in s["courses"] if c["checkpoint"]}
        checks.update({s["advancementCheck"]["id"]: s["advancementCheck"] for s in parsed["stages"] if s["advancementCheck"]})
        for q in data.get("questions", []):
            target = checks.get(q.pop("assessment", ""))
            if target is None:
                sys.exit(f"question {q.get('id')} names an unknown assessment")
            target["questionPool"].append(q["id"])
            questions.append(q)
    for stage in parsed["stages"]:
        if stage["number"] in args.unpublish:
            stage["published"] = False

    out = {"subjectID": args.subject, "ruleVersion": 1, "title": parsed["title"], "summary": parsed["summary"],
           "stages": parsed["stages"], "capstone": parsed["capstone"], "questions": questions}
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    items = sum(len(m["items"]) for s in parsed["stages"] for c in s["courses"] for m in c["modules"])
    print(f"Wrote {args.output}: {len(parsed['stages'])} stages, {sum(len(s['courses']) for s in parsed['stages'])} courses, {items} module items, {len(questions)} questions")


if __name__ == "__main__":
    main()
