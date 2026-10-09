#!/usr/bin/env python3
"""Validate bundled Hearken references. Run from any directory, no dependencies."""
import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / 'Hearken/Resources/Content'


def validate():
    catalog = json.loads((CONTENT / 'subjects.json').read_text())
    ids = set()
    def unique(value):
        assert isinstance(value, str) and value, 'Empty ID'
        assert value not in ids, f'Duplicate ID: {value}'
        ids.add(value)
    chapters = {}
    for path in CONTENT.glob('scripture-*.json'):
        volume = json.loads(path.read_text())['volume']
        unique(volume['id'])
        for book in volume['books']:
            unique(book['id'])
            for chapter in book['chapters']:
                unique(chapter['id'])
                chapters[chapter['id']] = chapter
                for verse in chapter['verses']:
                    unique(verse['id'])
    def chapter_ref(value):
        assert value in chapters, f'Missing chapter: {value}'
    units = {}
    subjects = {}
    kinds = {'scripture','article','manual','book','video','website','reference'}
    for subject in catalog['subjects']:
        unique(subject['id']); subjects[subject['id']] = subject
        for key in ('name','summary','symbol'):
            assert subject[key], f'Missing {key}: {subject["id"]}'
        numbers = set()
        for unit in subject['units']:
            unique(unit['id']); units[unit['id']] = subject['id']
            assert unit['number'] > 0 and unit['number'] not in numbers
            numbers.add(unit['number'])
            assert unit['title'] and unit['range']
            assert len(unit['readingChapterIDs']) == len(set(unit['readingChapterIDs']))
            for cid in unit['readingChapterIDs']: chapter_ref(cid)
        for resource in subject['resources']:
            unique(resource['id'])
            assert resource['kind'] in kinds
            assert resource['title'] and resource['author']
            if resource.get('chapterID'): chapter_ref(resource['chapterID'])
            if resource.get('url'):
                url = urlparse(resource['url'])
                assert url.scheme == 'https' and url.netloc, f'Invalid URL: {resource["id"]}'
            if resource['id'].startswith('dm.passage.'):
                # Verify every referenced verse exists, including comma-separated ranges.
                numbers = {v['number'] for v in chapters[resource['chapterID']]['verses']}
                parts = resource['title'].split(':', 1)[1].split(',')
                for part in parts:
                    bounds = [int(n) for n in re.split('[–-]', part.strip())]
                    assert all(n in numbers for n in range(bounds[0], bounds[-1]+1)), resource['title']
    for q in catalog['questions']:
        unique(q['id'])
        assert q['subjectID'] in subjects
        assert units.get(q['unitID']) == q['subjectID'], f'Wrong unit owner: {q["id"]}'
        assert len(q['options']) >= 2 and len(set(q['options'])) == len(q['options'])
        assert type(q['answer']) is int and 0 <= q['answer'] < len(q['options'])
        assert q['prompt'] and q['reference'] and q['explanation']
        if q.get('chapterID'): chapter_ref(q['chapterID'])
    passages = [r for s in catalog['subjects'] for r in s['resources'] if r['id'].startswith('dm.passage.')]
    assert len(passages) == 96, 'Linked DM edition requires 96 passages'
    print(f'Valid: {len(subjects)} subjects, {len(units)} units, {len(catalog["questions"])} questions, {len(passages)} DM references, {len(chapters)} scripture chapters')
    for subject in catalog['subjects']:
        empty = [u['id'] for u in subject['units'] if not any(q['unitID'] == u['id'] for q in catalog['questions'])]
        print(f'{subject["name"]}: {len(empty)} units awaiting questions' + (f' ({", ".join(empty)})' if empty else ''))

if __name__ == '__main__':
    validate()
