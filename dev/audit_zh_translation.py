"""Read-only Chinese audit against the user's installed official locale."""
from pathlib import Path
import json,re,zipfile,hashlib,collections,subprocess,argparse
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--upstream',type=Path,default=ROOT);parser.add_argument('--out',type=Path,default=ROOT/'dev/.cache/zh-audit');parser.add_argument('--official-game',type=Path,required=True);args=parser.parse_args()
UP=args.upstream.resolve();OUT=args.out.resolve();OUT.mkdir(parents=True,exist_ok=True)
GAME=args.official_game
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('os=nil;io=nil;package=nil;require=nil;dofile=nil;loadfile=nil')
def plain(v):
 if hasattr(v,'items'):
  d={k:plain(x) for k,x in v.items()}
  if d and all(isinstance(k,int) for k in d):return [d[k] for k in sorted(d)]
  return d
 return v
def read(p):return plain(lua.execute(p.read_text(encoding='utf-8-sig')))
def locale(lang):
 result=read(UP/'locales'/f'{lang}.lua');origin={k:f'locales/{lang}.lua' for k in result}
 for p in sorted((UP/'locales/content'/lang).glob('*.lua')):
  d=read(p);result.update(d);origin.update({k:p.relative_to(UP).as_posix() for k in d})
 return result,origin
zh,origins=locale('zh_CN');en,_=locale('en')
with zipfile.ZipFile(GAME) as z:
 raw=z.read('localization/zh_CN.lua');official=plain(lua.execute(raw.decode('utf-8-sig')))
 official_en=plain(lua.execute(z.read('localization/en-us.lua').decode('utf-8-sig')))
def text(v):
 if isinstance(v,str):return v
 if isinstance(v,list):return '\n'.join(text(x) for x in v)
 if isinstance(v,dict):
  if 'text' in v:return text(v['text'])
  if 'segments' in v:return ''.join(text(x) for x in v['segments'])
 return ''
def strings(v):
 if isinstance(v,str):return [v]
 if isinstance(v,list):return [s for x in v for s in strings(x)]
 if isinstance(v,dict):return [s for k,x in v.items() if k not in {'color_key'} for s in strings(x)]
 return []
def norm(v):return re.sub(r'[\s\u3000]+','',v)
def clean(v):return re.sub(r'\{[^}]*\}','',text(v)).replace('*','')
def ref(category,id):return official['descriptions'].get(category,{}).get(id)
alias={'j_ancient_joker':'j_ancient','j_baseball_card':'j_baseball','j_flash_card':'j_flash','j_golden_joker':'j_golden','j_seltzer':'j_selzer','j_smiley_face':'j_smiley','j_spare_trousers':'j_trousers','j_stone_joker':'j_stone','j_trading_card':'j_trading','v_overstock':'v_overstock_norm','planet_x':'c_planet_x','j_canio':'j_caino','v_reroll':'v_reroll_surplus','v_nacho':'v_nacho_tong','v_overstock_norm':'v_overstock','tag_tag_double':'tag_double'}
catmap={'joker':['Joker'],'consumable':['Tarot','Planet','Spectral'],'voucher':['Voucher'],'deck':['Back'],'blind':['Blind'],'stake':['Stake'],'tag':['Tag'],'edition':['Edition'],'enhancement':['Enhanced'],'seal':['Other']}
records=[];unmapped=[]
for key,current in sorted(zh.items()):
 if not key.endswith('.name'):continue
 namespace,id,_=key.split('.',2)
 if namespace not in catmap:continue
 oid=alias.get(id,id)
 if namespace=='consumable':oid=re.sub(r'^(tarot|planet|spectral)_','c_',oid).replace('hierophant','heirophant')
 if namespace=='edition':oid='e_'+oid
 if namespace=='enhancement':oid='m_'+oid
 if namespace=='seal':oid=oid+'_seal'
 found=None
 for c in catmap[namespace]:
  entry=ref(c,oid)
  if entry and entry.get('name'):found=(c,oid,entry);break
 if not found:
  unmapped.append(key);continue
 c,oid,entry=found
 desc_key=key[:-4]+'description'
 records.append({'key':key,'category':c,'official_id':oid,'current':current,'official':entry['name'],'equal':norm(str(current))==norm(entry['name']),'description_current':text(zh.get(desc_key)), 'description_official':clean(entry.get('text',[])),'source':origins[key]})
missing=sorted(set(en)-set(zh));same=[];placeholders=[]
for key,a in en.items():
 if key not in zh:continue
 b=zh[key]
 if a==b and re.search(r'[A-Za-z]{3,}',text(a)):same.append(key)
 aa='\n'.join(strings(a));bb='\n'.join(strings(b))
 ap=collections.Counter(re.findall(r'\{([\w]+)\}',aa));bp=collections.Counter(re.findall(r'\{([\w]+)\}',bb))
 af=re.findall(r'%(?:[-+ #0]*\d*(?:\.\d+)?)?[cdiouxXeEfgGqs%]',aa);bf=re.findall(r'%(?:[-+ #0]*\d*(?:\.\d+)?)?[cdiouxXeEfgGqs%]',bb)
 if ap!=bp or af!=bf:placeholders.append({'key':key,'en':aa,'zh':bb,'en_named':dict(ap),'zh_named':dict(bp),'en_format':af,'zh_format':bf})
counts={cat:{'checked':len(xs),'different':sum(not x['equal'] for x in xs)} for cat in sorted(set(x['category'] for x in records)) for xs in [[x for x in records if x['category']==cat]]}
report={'upstream_tag':subprocess.check_output(['git','-C',str(UP),'describe','--tags','--always','HEAD'],text=True).strip(),'source_commit':subprocess.check_output(['git','-C',str(UP),'rev-parse','HEAD'],text=True).strip(),'official_locale_sha256':hashlib.sha256(raw).hexdigest(),'zh_top_level_keys':len(zh),'english_interface_template_keys':len(en),'names_by_category':counts,'name_differences':[x for x in records if not x['equal']],'unmapped_names':unmapped,'missing_english_keys':missing,'same_english_values':same,'placeholder_findings':placeholders}
(OUT/'audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'catalog-comparison.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'locale-values.json').write_text(json.dumps(zh,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k not in {'name_differences','placeholder_findings'}},ensure_ascii=False,indent=2))
print('NAME EXAMPLES',[(x['key'],x['current'],x['official']) for x in report['name_differences'][:18]])
print('PLACEHOLDERS',json.dumps(placeholders,ensure_ascii=False))

if report['name_differences'] or unmapped or missing or placeholders: raise SystemExit(1)
