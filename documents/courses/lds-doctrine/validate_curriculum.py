#!/usr/bin/env python3
"""Validate authored course integrity; optionally check all scripture locators against Hearken."""
import argparse,json,pathlib,re,sys
parser=argparse.ArgumentParser()
parser.add_argument('--scripture-dir',type=pathlib.Path)
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parent
data=json.loads((root/'curriculum.json').read_text())
errors=[]
def check(ok,message):
 if not ok: errors.append(message)
sources={s['id']:s for s in data['sources']}
check(len(sources)==len(data['sources']),'Duplicate source IDs')
allowed={'link_only','existing_app_text','public_domain_US','recommendation_only','provider_embed_only'}
for s in sources.values():
 check(s['rights'] in allowed,f"Unknown rights disposition: {s['id']}")
 check(s['url'].startswith('https://'),f"Source is not HTTPS: {s['id']}")
 check(bool(s['perspective']) and bool(s['verificationMethod']),f"Missing provenance: {s['id']}")
ids=set(); required_keys=set(); optional_keys={}; readings=[];required_xp=0; required_counts={'lesson':0,'reading':0,'practice':0,'course_checkpoint':0,'capstone':0}
def unique_id(item):
 check(item['id'] not in ids,'Duplicate item ID: '+item['id']);ids.add(item['id'])
def refs(item):
 for sid in item.get('sourceIDs',[]):check(sid in sources,'Unresolved source: '+sid)
 if 'sourceID' in item:check(item['sourceID'] in sources,'Unresolved source: '+item['sourceID'])
def activity(item,required):
 global required_xp
 unique_id(item)
 check(item['required']==required,'Incorrect required flag: '+item['id'])
 check(item['xp']>=0 and isinstance(item['xp'],int),'Invalid XP: '+item['id'])
 expected={'lesson':20,'reading':30,'practice':10,'course_checkpoint':100,'capstone':200}.get(item['kind'])
 check(item['xp']==expected,'Wrong activity XP: '+item['id'])
 if required:
  check(item['awardKey'] not in required_keys,'Repeated required award key: '+item['awardKey']);required_keys.add(item['awardKey']);required_xp+=item['xp'];required_counts[item['kind']]+=1
 else:
  key=item['awardKey'];check(key not in required_keys,'Optional reading duplicates a required award: '+key)
  if key in optional_keys:check(optional_keys[key]==item['xp'],'Inconsistent optional dedup award: '+key)
  optional_keys[key]=item['xp']
 refs(item)
 if item['kind']=='reading':readings.append(item)
 if item['kind'] in {'lesson','reading','practice'}:check(bool(item['completion']),'Missing completion evidence: '+item['id'])
 if item['kind']=='practice':check(bool(item['successCriteria']),'Missing practice rubric: '+item['id'])
def exam(item,count):
 check(len(item['questions'])==count,'Wrong exam length: '+item['id'])
 check(item['passPercent']==80,'Wrong exam pass threshold: '+item['id'])
 check(item['maxPoints']==count*2,'Wrong exam max points: '+item['id'])
 for q in item['questions']:
  unique_id(q);refs(q);check(bool(q['answerGuide']) and bool(q['prompt']),'Missing question/guide: '+q['id'])
check(len(data['courses'])==8,'Expected eight courses')
check(len(data['stages'])==4,'Expected four stages')
for i,c in enumerate(data['courses']):
 unique_id(c);subtotal=0
 check(c['stage']==i//2+1,'Wrong stage: '+c['id'])
 check(c['prerequisiteCourseIDs']==([] if i==0 else [data['courses'][i-1]['id']]),'Incorrect course prerequisites: '+c['id'])
 expected_gate=[] if i not in (2,4,6) else [data['stages'][i//2-1]['advancementCheck']['id']]
 check(c['prerequisiteAdvancementCheckIDs']==expected_gate,'Incorrect advancement prerequisite: '+c['id'])
 for m in c['modules']:
  unique_id(m);refs(m)
  check(len(m['lesson'].split())>=90,'Lesson too short: '+m['id'])
  check(len(m['learningItems'])>=3 and len(m['objectives'])>=2,'Missing learning specification: '+m['id'])
  acts=[m['lessonActivity']]+m['readings']+m['practices']
  for a in acts:activity(a,True)
  xp=sum(a['xp'] for a in acts);check(xp==m['requiredXP'],'Module arithmetic: '+m['id']);subtotal+=xp
  for r in m.get('optionalReadings',[]):activity(r,False)
 activity(c['checkpoint'],True);exam(c['checkpoint'],10);subtotal+=100
 if 'capstone' in c:
  a=c['capstone'];activity(a,True);subtotal+=200
  check(a['passRule']=={'minTotal':9,'maxTotal':12,'minEach':1},'Capstone threshold differs from Scholar path')
  check(len(a['rubric'])==4 and all(len(x['descriptors'])==4 for x in a['rubric']),'Capstone rubric incomplete')
 check(subtotal==c['requiredXP'],'Course arithmetic: '+c['id'])
for i,s in enumerate(data['stages']):
 unique_id(s);exam(s['advancementCheck'],5);unique_id(s['advancementCheck'])
 check(s['advancementCheck']['xp']==0,'Advancement checks must not award XP')
 check(s['courseIDs']==[c['id'] for c in data['courses'][i*2:i*2+2]],'Stage course list mismatch')
 check(s['requiredXP']==sum(c['requiredXP'] for c in data['courses'][i*2:i*2+2]),'Stage XP mismatch')
 check(s['cumulativeXP']==[500,1500,3000,5000][i],'Tier threshold mismatch')
for v in data['videos']:
 unique_id(v)
 check(re.fullmatch(r'[A-Za-z0-9_-]{11}',v['youtubeVideoID']) is not None,'Invalid YouTube ID')
 check(v['id'] in sources,'Missing video source')
 check(v['transcriptSourceID'] in sources,'Missing transcript source')
 check(v['xp']==20 and not v['required'],'Video must be optional at 20 XP')
 check(v['awardKey']==v['fallback']['awardKey'] and v['xp']==v['fallback']['xp'],'Video fallback permits duplicate/different XP')
 check(0<=v['fallback']['moduleIndex']<32,'Unresolved fallback module')
for c in data['courses']:
 for vid in c['optionalVideoIDs']:check(vid in {v['id'] for v in data['videos']},'Unresolved video placement')
 for sid in c['optionalBookSourceIDs']:check(sid in sources,'Unresolved book placement')
check(required_xp==data['requiredXP']==5000,'Required path must total exactly 5,000 XP')
check(required_counts=={'lesson':32,'reading':92,'practice':60,'course_checkpoint':8,'capstone':1},'Required activity counts changed')
check(len(data['videos'])==8,'Expected eight curated videos')
check(len(data['books'])==4,'Expected four book recommendations')
checked_locators=0
if args.scripture_dir:
 chapters={}
 for path in args.scripture_dir.glob('scripture-*.json'):
  volume=json.loads(path.read_text())['volume']
  for book in volume['books']:
   for chapter in book['chapters']:chapters[chapter['id']]={v['number'] for v in chapter['verses']}
 check(bool(chapters),'No scripture chapters found')
 for r in readings:
  if 'chapterID' not in r:continue
  cid=r['chapterID'];check(cid in chapters,'Unknown chapter: '+cid)
  if cid not in chapters:continue
  selection=r.get('verses','')
  if selection:
   numbers=list(map(int,selection.split('-')));nums=range(numbers[0],numbers[-1]+1)
   check(all(n in chapters[cid] for n in nums),'Invalid verse range: '+r['reference'])
  checked_locators+=1
# Always write the report so it cannot be confused with a prior successful run.
report=dict(status='pass' if not errors else 'fail',requiredXP=required_xp,requiredActivityCounts=required_counts,courses=len(data['courses']),modules=sum(len(c['modules']) for c in data['courses']),assessmentQuestions=sum(len(c['checkpoint']['questions']) for c in data['courses'])+sum(len(s['advancementCheck']['questions']) for s in data['stages']),optionalReadingPlacements=sum(len(m.get('optionalReadings',[])) for c in data['courses'] for m in c['modules']),videos=len(data['videos']),books=len(data['books']),scriptureLocatorsChecked=checked_locators,networkPlaybackTested=False,editorialReviewCompleted=False,errors=errors)
(root/'VALIDATION_REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
sys.exit(bool(errors))
