"""Run the hash-pinned official x86 OCG DLL in isolated portable Python, never compile.

Native gameplay evidence on Windows is not evidence of the iOS GUI or device runtime.
"""
from __future__ import annotations
import argparse, collections, ctypes as C, hashlib, json, os, platform, random, shutil
import sqlite3, struct, subprocess, sys, time, urllib.request, zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from smoke_ocg_host import DEFAULT_DLL, verify_binary, inspect_pe, SOURCE_REVISION, IOS_CORE_REVISION
PYTHON_URL = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-win32.zip'
PYTHON_SHA256 = '084b9eb24cb848605c895d05b738fbc2572efc8b4c18c415a824065864a2b853'
PYTHON_SOURCE = PYTHON_URL + '.spdx.json'
PYTHON_DIR = ROOT / 'outputs/ocg-reference/python-3.12.10-win32'
SCRIPT_ARCHIVE = ROOT / 'outputs/ocg-reference/CardScripts-14f3b8905ff95a8f869fd6891aec4d6b580db1e1.zip'
AI_DIR = ROOT / 'NativeClient/overlays/offline-ai'
PROMPTS = {10,11,12,13,14,15,16,18,19,20,21,22,23,24,25,26,132,140,141,142,143}
MR5 = 0x800 | 0x2000 | 0x4000 | 0x8000 | 0x20000
SCENARIO_SOURCE = ROOT / 'tests/fixtures/ocg_prompt_scenarios.lua'
SCENARIO_PROMPTS = {
    'choices': {13,14,19,22,24,25,132,140,141,142,143},
    'attack_cost_order': {21},
    'forced_chain': {16},
}
EFFECT_SCENARIO_SOURCE = ROOT / 'tests/fixtures/ocg_effect_scenarios.lua'
EFFECT_SCENARIOS = {
    'destruction_revival': {'messages': {50,63,74}, 'scripts': {'c53129443.lua','c83764718.lua'}},
    'spell_activation_negation': {'messages': {50,74,75}, 'scripts': {'c53129443.lua','c77414722.lua'}},
    'effect_and_battle_damage': {'messages': {74,91,110,111}, 'scripts': {'c46918794.lua'}},
    'fusion_summon': {'messages': {50,63,74}, 'scripts': {'c24094653.lua','c23995346.lua','proc_fusion.lua'}},
}

def sha(data): return hashlib.sha256(data).hexdigest()
def packets(data):
    at = 0
    while at < len(data):
        if at + 4 > len(data): raise ValueError('Truncated core frame length')
        n = struct.unpack_from('<I', data, at)[0]; at += 4
        if n < 1 or at + n > len(data): raise ValueError('Invalid core frame length')
        yield data[at], data[at+1:at+n]
        at += n

def scenario_completed(message, payload, player, marker):
    # HINT_MESSAGE = 2. The marker comes from resumed Lua, never from a fabricated packet.
    return message == 2 and len(payload) == 10 and struct.unpack('<BBQ', payload) == (2, player, marker)

def require_scenario_evidence(expected_messages, observed_messages, required_scripts=(), loaded_scripts=()):
    missing=set(expected_messages)-set(observed_messages)
    if missing: raise ValueError('Scenario did not issue expected messages: '+str(sorted(missing)))
    missing=set(required_scripts)-set(loaded_scripts)
    if missing: raise ValueError('Scenario did not execute required canonical scripts: '+str(sorted(missing)))

def parse_deck(path):
    zones = {'main':[], 'extra':[], 'side':[]}; zone = 'main'
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if line in ('#main','#extra','!side'): zone=line[1:]; continue
        if not line or line.startswith('#'): continue
        if not line.isascii() or not line.isdecimal(): raise ValueError('Invalid YDK code')
        zones[zone].append(int(line))
    if not 40 <= len(zones['main']) <= 60 or len(zones['extra']) > 15 or len(zones['side']) > 15: raise ValueError('Invalid YDK zone sizes')
    return zones

def source_equivalence():
    core = ROOT / 'NativeClient/edopro/ocgcore'
    def git(*args): return subprocess.check_output(['git','-C',str(core),*args],text=True).strip()
    changed = git('diff','--name-only',SOURCE_REVISION,IOS_CORE_REVISION).splitlines()
    allowed={'.github/workflows/ygopro-core.yml','jni/Application.mk','premake5.lua','scripts/deploy.sh','scripts/llvm-objcopy','scripts/llvm-strip','scripts/predeploy.sh'}
    if set(changed) != allowed: raise ValueError('Unexpected core source difference; refusing compatibility assumption')
    lua = [git('ls-tree',rev,'lua/src') for rev in (SOURCE_REVISION,IOS_CORE_REVISION)]
    if lua[0] != lua[1]: raise ValueError('Lua source pin differs')
    return {'changedBuildFiles':changed,'luaGitlink':lua[0],'coreCodeAndLuaEqual':True}

def declarable(card, opcodes):
    """Host-only translation of pinned DataManager::IsCardDeclarable, no strategy."""
    stack=[]; aliases=False; tokens=False
    binary={0x40000000:lambda a,b:a+b,0x40000001:lambda a,b:a-b,0x40000002:lambda a,b:a*b,
            0x40000003:lambda a,b:(abs(a)//abs(b))*(-1 if (a<0)!=(b<0) else 1),
            0x40000004:lambda a,b:int(bool(a) and bool(b)),0x40000005:lambda a,b:int(bool(a) or bool(b)),
            0x40000008:lambda a,b:a&b,0x40000009:lambda a,b:a|b,0x40000011:lambda a,b:a^b,
            0x40000012:lambda a,b:a<<b if 0<=b<64 else 0,0x40000013:lambda a,b:a>>b if 0<=b<64 else 0}
    values={0x40000100:card.code,0x40000102:card.type,0x40000103:card.race,0x40000104:card.attribute}
    getters={0x40000105:card.code,0x40000107:card.type,0x40000108:card.race,0x40000109:card.attribute}
    for full in opcodes:
        op=full>>32 if full&0xffffffff==0 else None
        if op in binary:
            if len(stack)>=2:
                b=stack.pop();a=stack.pop()
                if op==0x40000003 and b==0: return False
                stack.append(C.c_int64(binary[op](a,b)).value)
        elif op in (0x40000006,0x40000007,0x40000010):
            if stack:
                a=stack.pop();stack.append(C.c_int64(-a if op==0x40000006 else int(not a) if op==0x40000007 else ~a).value)
        elif op in values:
            if stack:
                a=stack.pop();stack.append(int(values[op]==a) if op==0x40000100 else values[op]&a)
        elif op in getters: stack.append(getters[op])
        elif op==0x40000101:
            if stack:
                a=stack.pop();i=0;found=False
                while card.setcodes[i]:
                    sc=card.setcodes[i];found |= (sc&0xfff)==(a&0xfff) and (sc&0xf000&a)==(a&0xf000);i+=1
                stack.append(int(found))
        elif op==0x40000014: aliases=True
        elif op==0x40000015: tokens=True
        else: stack.append(C.c_int64(full).value)
    return len(stack)==1 and stack[0]!=0 and (card.code in (78734254,13857930) or ((aliases or not card.alias) and (tokens or card.type&0x4001!=0x4001)))

def prepare_python(download=False):
    archive = PYTHON_DIR.parent / 'python-3.12.10-embed-win32.zip'
    if not archive.exists():
        if not download: raise ValueError('Portable Python missing; use --download-python')
        archive.parent.mkdir(parents=True, exist_ok=True)
        data = urllib.request.urlopen(PYTHON_URL, timeout=30).read(12000000)
        if sha(data) != PYTHON_SHA256: raise ValueError('Official Python archive SHA256 mismatch')
        archive.write_bytes(data)
    if sha(archive.read_bytes()) != PYTHON_SHA256: raise ValueError('Cached Python archive SHA256 mismatch')
    PYTHON_DIR.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for item in z.infolist():
            target = (PYTHON_DIR / item.filename).resolve()
            if not target.is_relative_to(PYTHON_DIR.resolve()): raise ValueError('Unsafe ZIP path')
            if item.is_dir(): continue
            data = z.read(item)
            if target.exists() and target.read_bytes() != data: raise ValueError('Portable runtime changed: ' + item.filename)
            if not target.exists(): target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(data)
    return PYTHON_DIR / 'python.exe'

class Card(C.Structure):
    _fields_=[('code',C.c_uint32),('alias',C.c_uint32),('setcodes',C.POINTER(C.c_uint16)),('type',C.c_uint32),('level',C.c_uint32),('attribute',C.c_uint32),('race',C.c_uint64),('attack',C.c_int32),('defense',C.c_int32),('lscale',C.c_uint32),('rscale',C.c_uint32),('link_marker',C.c_uint32)]
class Player(C.Structure): _fields_=[('startingLP',C.c_uint32),('startingDrawCount',C.c_uint32),('drawCountPerTurn',C.c_uint32)]
DATA=C.CFUNCTYPE(None,C.c_void_p,C.c_uint32,C.POINTER(Card))
SCRIPT=C.CFUNCTYPE(C.c_int,C.c_void_p,C.c_void_p,C.c_char_p)
LOG=C.CFUNCTYPE(None,C.c_void_p,C.c_char_p,C.c_int)
DONE=C.CFUNCTYPE(None,C.c_void_p,C.POINTER(Card))
class Options(C.Structure):
    _fields_=[('seed',C.c_uint64*4),('flags',C.c_uint64),('team1',Player),('team2',Player),('cardReader',DATA),('payload1',C.c_void_p),('scriptReader',SCRIPT),('payload2',C.c_void_p),('logHandler',LOG),('payload3',C.c_void_p),('cardReaderDone',DONE),('payload4',C.c_void_p),('enableUnsafeLibraries',C.c_uint8)]
class NewCard(C.Structure): _fields_=[('team',C.c_uint8),('duelist',C.c_uint8),('code',C.c_uint32),('con',C.c_uint8),('loc',C.c_uint32),('seq',C.c_uint32),('pos',C.c_uint32)]
class Query(C.Structure): _fields_=[('flags',C.c_uint32),('con',C.c_uint8),('loc',C.c_uint32),('seq',C.c_uint32),('overlay_seq',C.c_uint32)]

class Node:
    def __init__(self,metadata):
        exe=shutil.which('node')
        if not exe: raise ValueError('Existing Node executable missing')
        self.p=subprocess.Popen([exe,str(AI_DIR/'offline_ai_host.js')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8',bufsize=1)
        for player in (0,1): self.call(op='start',botID=player,metadata=metadata)
    def call(self,**request):
        self.p.stdin.write(json.dumps(request,separators=(',',':'))+'\n');self.p.stdin.flush()
        line=self.p.stdout.readline()
        if not line: raise ValueError('Node adapter terminated: '+self.p.stderr.read()[:1000])
        result=json.loads(line)
        if not result['ok']: raise ValueError('AI: '+result['error'])
        return result['result']
    def close(self):
        if self.p.poll() is None: self.p.terminate()
        self.p.wait(timeout=10)

class Engine:
    def __init__(self,runtime):
        data=DEFAULT_DLL.read_bytes();self.binary=verify_binary(data);pe=inspect_pe(data)
        if self.binary['sha256']!='cc066dfe50d0ad1fd47645634d058771b02292fec83b7ab1eb4f755e5f7f303b': raise ValueError('DLL SHA256 mismatch')
        if os.name!='nt' or C.sizeof(C.c_void_p)!=4 or pe['architecture']!='x86': raise ValueError('Must run under Windows x86 process')
        if [C.sizeof(t) for t in (Card,Player,Options,NewCard,Query)] != [56,12,104,24,20]: raise ValueError('Unexpected OCG x86 ABI layout')
        # ocgapi.h uses ordinary C declarations: cdecl, not WinDLL/stdcall.
        self.dll=C.CDLL(str(DEFAULT_DLL))
        defs={'OCG_GetVersion':(None,[C.POINTER(C.c_int),C.POINTER(C.c_int)]),'OCG_CreateDuel':(C.c_int,[C.POINTER(C.c_void_p),C.POINTER(Options)]),'OCG_DestroyDuel':(None,[C.c_void_p]),'OCG_DuelNewCard':(None,[C.c_void_p,C.POINTER(NewCard)]),'OCG_StartDuel':(None,[C.c_void_p]),'OCG_DuelProcess':(C.c_int,[C.c_void_p]),'OCG_DuelGetMessage':(C.c_void_p,[C.c_void_p,C.POINTER(C.c_uint32)]),'OCG_DuelSetResponse':(None,[C.c_void_p,C.c_void_p,C.c_uint32]),'OCG_LoadScript':(C.c_int,[C.c_void_p,C.c_char_p,C.c_uint32,C.c_char_p]),'OCG_DuelQuery':(C.c_void_p,[C.c_void_p,C.POINTER(C.c_uint32),C.POINTER(Query)])}
        for name,(restype,args) in defs.items(): f=getattr(self.dll,name);f.restype=restype;f.argtypes=args
        major=C.c_int();minor=C.c_int();self.dll.OCG_GetVersion(C.byref(major),C.byref(minor));self.version=[major.value,minor.value]
        if self.version!=[11,0]: raise ValueError('Unexpected OCG API version')
        lock=json.loads((ROOT/'NativeClient/upstream.lock.json').read_text());self.runtime=runtime
        cdb=runtime/'cards.cdb'
        if sha(cdb.read_bytes())!=lock['database']['sha256']: raise ValueError('Pinned CDB mismatch')
        if sha(SCRIPT_ARCHIVE.read_bytes())!=lock['scripts']['archiveSHA256']: raise ValueError('Pinned script archive mismatch')
        self.scripts={}
        with zipfile.ZipFile(SCRIPT_ARCHIVE) as z:
            for name in z.namelist():
                if name.endswith('.lua'): self.scripts[name.split('/',1)[1]]=z.read(name)
        self.canonical_hashes={sha(data) for data in self.scripts.values()}
        self.manifest=json.loads((runtime/'package-manifest.json').read_text())
        self.script_cache={}
        self.cards={};self.setcodes={};self.rows={}
        db=sqlite3.connect(cdb.as_uri()+'?mode=ro',uri=True);db.row_factory=sqlite3.Row
        for r in db.execute('select * from datas'):
            r=dict(r);code=r['id'];packed=r['setcode']&((1<<64)-1);sc=[(packed>>i)&65535 for i in range(0,64,16) if (packed>>i)&65535]
            self.setcodes[code]=(C.c_uint16*(len(sc)+1))(*sc,0)
            card=Card(code,r['alias'],self.setcodes[code],r['type'],r['level']&255,r['attribute'],r['race']&((1<<64)-1),r['atk'],0 if r['type']&0x4000000 else r['def'],(r['level']>>24)&255,(r['level']>>16)&255,r['def'] if r['type']&0x4000000 else 0)
            self.cards[code]=card;self.rows[code]=r
        db.close()
        self.metadata={str(code):{'attack':c.attack,'defense':c.defense,'type':c.type,'level':c.level} for code,c in self.cards.items()}
        self.errors=[];self.loaded=set();self.read_codes=set();self.missing=set()
        self.callbacks=(DATA(self.read_card),SCRIPT(self.read_script),LOG(self.log),DONE(lambda *_:None))
    def read_card(self,payload,code,out):
        if code in self.cards: C.memmove(out,C.byref(self.cards[code]),C.sizeof(Card));self.read_codes.add(code)
        else: self.errors.append('Missing card '+str(code))
    def read_script(self,payload,duel,name):
        try:
            name=name.decode('utf-8')
            if '\\' in name or '..' in Path(name).parts or Path(name).is_absolute(): raise ValueError('Unsafe requested script path')
            key=next((p for p in (name,'official/'+name,'unofficial/'+name) if (self.runtime/'script'/p).is_file()),None)
            if key is None: self.missing.add(name);return 0
            if key not in self.script_cache:
                data=(self.runtime/'script'/key).read_bytes();h=sha(data)
                if h not in self.canonical_hashes or h!=self.manifest['files']['script/'+key]['sha256']: raise ValueError('Runtime Lua differs from canonical archive/manifest: '+key)
                self.script_cache[key]=data
            data=self.script_cache[key];self.loaded.add(key)
            return self.dll.OCG_LoadScript(duel,data,len(data),name.encode())
        except Exception as e: self.errors.append(str(e));return 0
    def log(self,payload,message,kind): self.errors.append({'kind':kind,'message':message.decode('utf-8','replace')})
    def messages(self,duel):
        n=C.c_uint32();ptr=self.dll.OCG_DuelGetMessage(duel,C.byref(n))
        return list(packets(C.string_at(ptr,n.value))) if n.value else []
    def positions(self,duel,player):
        result={}
        for seq in range(7):
            n=C.c_uint32();q=Query(2,player,4,seq,0);ptr=self.dll.OCG_DuelQuery(duel,C.byref(n),C.byref(q))
            if not ptr or not n.value: continue
            b=C.string_at(ptr,n.value);at=0
            while at+2<=len(b):
                size=struct.unpack_from('<H',b,at)[0];at+=2
                if not size: break
                if at+size>len(b): raise ValueError('Malformed position query')
                flag=struct.unpack_from('<I',b,at)[0]
                if flag==2: result[str(seq)]=struct.unpack_from('<I',b,at+4)[0]
                at+=size
        return result
    def answer(self,node,duel,message,payload):
        if not payload or payload[0] not in (0,1): raise ValueError('Invalid selecting player')
        codes=[]
        if message==142:
            if len(payload)<2 or len(payload)!=2+payload[1]*8: raise ValueError('Malformed announce-card request')
            ops=struct.unpack_from('<'+'Q'*payload[1],payload,2)
            codes=[code for code,c in sorted(self.cards.items()) if declarable(c,ops)]
        result=node.call(op='decide',botID=payload[0],message=message,bytes=list(payload),
                         declarable=codes,ownPositions=self.positions(duel,payload[0]))
        if result.get('handled') is not True: raise ValueError('AI did not handle its prompt')
        response=bytes(result['response'])
        if not response or len(response)>65536: raise ValueError('Invalid AI response length')
        return response
    def match(self,paths,seed,max_turns=120,max_steps=100000):
        self.errors=[];self.loaded=set();self.read_codes=set();self.missing=set()
        report={'decks':[p.name for p in paths],'deckHashes':[sha(p.read_bytes()) for p in paths],'seed':seed,'status':'running','turns':0,'winner':None,'winReason':None,'messages':{},'promptCounts':{},'responses':0,'retryCount':0}
        counts=collections.Counter();prompts=collections.Counter();trace=[];node=None;duel=C.c_void_p();started=time.monotonic()
        try:
            decks=[parse_deck(p) for p in paths]
            for d in decks:
                if any(c not in self.cards for z in d.values() for c in z): raise ValueError('Deck card absent from CDB')
            node=Node(self.metadata);rng=random.Random(seed)
            opts=Options((C.c_uint64*4)(*[rng.getrandbits(64) for _ in range(4)]),MR5,Player(8000,5,1),Player(8000,5,1),self.callbacks[0],None,self.callbacks[1],None,self.callbacks[2],None,self.callbacks[3],None,0)
            result=self.dll.OCG_CreateDuel(C.byref(duel),C.byref(opts))
            if result or not duel: raise ValueError('OCG_CreateDuel status '+str(result))
            for name in (b'constant.lua',b'utility.lua'):
                if not self.read_script(None,duel,name): raise ValueError('Base Lua failed '+str(name))
            for player,deck in enumerate(decks):
                rng.shuffle(deck['main'])
                for loc,zone in ((1,'main'),(64,'extra')):
                    for code in reversed(deck[zone]): self.dll.OCG_DuelNewCard(duel,C.byref(NewCard(player,0,code,player,loc,0,8)))
            self.dll.OCG_StartDuel(duel)
            for step in range(max_steps):
                status=self.dll.OCG_DuelProcess(duel);batch=self.messages(duel);responded=False
                for message,payload in batch:
                    counts[message]+=1
                    if message==1: report['retryCount']+=1;raise ValueError('Core MSG_RETRY rejected AI response')
                    if message==40: report['turns']+=1
                    if report['turns']>max_turns: raise ValueError('Turn limit reached')
                    node.call(op='observe',message=message,bytes=list(payload))
                    if message==5:
                        if len(payload)!=2: raise ValueError('Invalid MSG_WIN')
                        report['winner'],report['winReason']=payload;report['status']='completed';break
                    if message in PROMPTS:
                        player=payload[0];prompts[message]+=1
                        response=self.answer(node,duel,message,payload)
                        trace.append({'message':message,'player':player,'payload':list(payload),'response':list(response)})
                        if len(trace)>30: trace.pop(0)
                        self.dll.OCG_DuelSetResponse(duel,response,len(response));report['responses']+=1;responded=True
                if report['status']=='completed': break
                if self.errors: raise ValueError('Core callback/script errors')
                if status==0: raise ValueError('Core ended without MSG_WIN')
                if status==1 and not responded: raise ValueError('Core awaiting with no supported prompt')
            else: raise ValueError('Step limit reached')
        except Exception as e: report['status']='failed';report['error']=str(e);report['lastPrompts']=trace
        finally:
            if duel: self.dll.OCG_DestroyDuel(duel)
            if node: node.close()
        report.update(messages=dict(sorted(counts.items())),promptCounts=dict(sorted(prompts.items())),scriptsLoaded=sorted(self.loaded),missingScriptRequests=sorted(self.missing),cardsRead=len(self.read_codes),scriptErrors=self.errors,durationSeconds=round(time.monotonic()-started,3))
        return report

    def prompt_scenario(self,kind,player,seed,effect=False):
        definitions=EFFECT_SCENARIOS if effect else SCENARIO_PROMPTS
        if kind not in definitions or player not in (0,1): raise ValueError('Unknown scenario')
        expected=EFFECT_SCENARIOS[kind]['messages'] if effect else SCENARIO_PROMPTS[kind]
        required=EFFECT_SCENARIOS[kind]['scripts'] if effect else set()
        self.errors=[];self.loaded=set();self.read_codes=set();self.missing=set()
        report={'scenario':kind,'player':player,'seed':seed,'status':'running','retryCount':0,
                'expectedMessages' if effect else 'expectedPrompts':sorted(expected),'responses':[], 'forcedChains':0}
        duel=C.c_void_p();node=None;counts=collections.Counter();marker=9000000+seed
        source=(EFFECT_SCENARIO_SOURCE if effect else SCENARIO_SOURCE).read_bytes()
        entry=f'Host{"Effect" if effect else "Prompt"}Scenario({player},"{kind}",{marker})'.encode()
        report.update(testLuaSHA256=sha(source),entryScript=entry.decode(),completionMarker=marker)
        if effect: report.update(requiredCanonicalScripts=sorted(required),events=[])
        started=time.monotonic()
        try:
            node=Node(self.metadata)
            opts=Options((C.c_uint64*4)(seed,2,3,4),MR5,Player(8000,0,0),Player(8000,0,0),
                         self.callbacks[0],None,self.callbacks[1],None,self.callbacks[2],None,self.callbacks[3],None,0)
            if self.dll.OCG_CreateDuel(C.byref(duel),C.byref(opts)) or not duel: raise ValueError('Scenario duel creation failed')
            for name in (b'constant.lua',b'utility.lua'):
                if not self.read_script(None,duel,name): raise ValueError('Scenario base Lua failed')
            for data,name in ((source,b'host-scenarios'),(entry,b'host-scenario-entry')):
                if not self.dll.OCG_LoadScript(duel,data,len(data),name): raise ValueError('Scenario Lua load failed')
            self.dll.OCG_StartDuel(duel)
            for step in range(500):
                status=self.dll.OCG_DuelProcess(duel);responded=False
                for message,payload in self.messages(duel):
                    counts[message]+=1
                    if effect and message in {50,62,63,70,71,72,73,74,75,91,110,111,113,114}:
                        report['events'].append({'message':message,'payload':list(payload)})
                    if message==1: report['retryCount']+=1;raise ValueError('Core rejected scenario response')
                    node.call(op='observe',message=message,bytes=list(payload))
                    if scenario_completed(message,payload,player,marker):
                        report['status']='accepted_completion_marker';break
                    if message==5: raise ValueError('Duel ended before scenario completion; not counting it as a match')
                    if message in PROMPTS:
                        response=self.answer(node,duel,message,payload)
                        report['responses'].append({'message':message,'player':payload[0],'payload':list(payload),'response':list(response)})
                        if message==16 and len(payload)>2 and payload[2]: report['forcedChains']+=1
                        self.dll.OCG_DuelSetResponse(duel,response,len(response));responded=True
                if self.errors: raise ValueError('Scenario callback/script errors')
                if report['status']=='accepted_completion_marker': break
                if status==0: raise ValueError('Core ended without scenario marker')
                if status==1 and not responded: raise ValueError('Core awaiting without a supported prompt')
            else: raise ValueError('Scenario step limit reached')
            require_scenario_evidence(expected,counts,required,self.loaded)
            if kind=='forced_chain' and not report['forcedChains']: raise ValueError('No forced chain was exercised')
        except Exception as error: report['status']='failed';report['error']=str(error)
        finally:
            if duel: self.dll.OCG_DestroyDuel(duel)
            if node: node.close()
        report.update(messages=dict(sorted(counts.items())),scriptErrors=self.errors,canonicalScriptsLoaded=sorted(self.loaded),
                      durationSeconds=round(time.monotonic()-started,3),fullMatch=False)
        if effect: report['requiredCanonicalScriptSHA256']={name:sha(self.script_cache[name]) for name in sorted(required) if name in self.loaded}
        return report

    def initialize_pool(self):
        audit_path=self.runtime/'reports/mapping-audit.json'
        if sha(audit_path.read_bytes())!=self.manifest['files']['reports/mapping-audit.json']['sha256']: raise ValueError('Pool mapping audit hash mismatch')
        audit=json.loads(audit_path.read_text());codes=sorted(set(audit['bridge']['konamiToCoreCode'].values()))
        self.errors=[];self.loaded=set();self.read_codes=set();self.missing=set();batches=[]
        for start in range(0,len(codes),32):
            group=codes[start:start+32];before=len(self.errors);duel=C.c_void_p()
            opts=Options((C.c_uint64*4)(start+1,2,3,4),MR5,Player(8000,0,0),Player(8000,0,0),self.callbacks[0],None,self.callbacks[1],None,self.callbacks[2],None,self.callbacks[3],None,0)
            try:
                status=self.dll.OCG_CreateDuel(C.byref(duel),C.byref(opts))
                if status: raise ValueError('Pool OCG_CreateDuel '+str(status))
                for name in (b'constant.lua',b'utility.lua'):
                    if not self.read_script(None,duel,name): raise ValueError('Pool base Lua load failed')
                for code in group:
                    if code not in self.cards: raise ValueError('Pool card missing in CDB '+str(code))
                    loc=64 if self.cards[code].type&(0x40|0x2000|0x800000|0x4000000) else 1
                    self.dll.OCG_DuelNewCard(duel,C.byref(NewCard(0,0,code,0,loc,0,8)))
                if len(self.errors)>before: batches.append({'codes':group,'errors':self.errors[before:]})
            finally:
                if duel: self.dll.OCG_DestroyDuel(duel)
        required=[];normal=[]
        for name in sorted(self.missing):
            if name=='c0.lua': continue
            try: code=int(name[1:-4]);card=self.cards[code]
            except (ValueError,KeyError): required.append(name);continue
            (required if card.type&(2|4|0x20|0x1000000) else normal).append(name)
        return {'status':'passed' if not self.errors and not required else 'failed','mappedUniqueCodes':len(codes),'batches':(len(codes)+31)//32,'cardsReadIncludingDependencies':len(self.read_codes),'canonicalRuntimeScriptsLoaded':len(self.loaded),'missingRequiredScripts':required,'missingNormalCardScripts':len(normal),'errors':batches,'auditSHA256':sha(audit_path.read_bytes()),'scope':'Card creation and initial_effect/base dependency execution only; does not exercise every effect activation.'}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--worker',action='store_true');p.add_argument('--download-python',action='store_true');p.add_argument('--runtime',type=Path,default=ROOT/'outputs/edopro-game-v6');p.add_argument('--deck-a');p.add_argument('--deck-b');p.add_argument('--seed',type=int,default=1);p.add_argument('--matches',type=int,default=1);p.add_argument('--sample-decks',action='store_true');p.add_argument('--suite',action='store_true',help='Fixed 36-match OBB regression suite');p.add_argument('--pool-check',action='store_true');p.add_argument('--prompt-scenarios',action='store_true',help='Bounded real-core prompt acceptance scenarios, not complete matches');p.add_argument('--effect-scenarios',action='store_true',help='Bounded canonical card effect interactions with final-state assertions');p.add_argument('--report',type=Path);args=p.parse_args()
    if not 1<=args.matches<=100: p.error('--matches must be 1..100')
    if args.prompt_scenarios and args.effect_scenarios: p.error('Select one scenario suite')
    if (args.prompt_scenarios or args.effect_scenarios) and (args.suite or args.sample_decks or args.pool_check or args.deck_a or args.deck_b or args.matches!=1): p.error('Scenario suites cannot be combined with match or pool options')
    if args.seed<1: p.error('--seed must be positive')
    if args.report is None: args.report=ROOT/'NativeClient'/('host-effect-validation.json' if args.effect_scenarios else 'host-prompt-validation.json' if args.prompt_scenarios else 'host-validation.json')
    if not args.worker:
        exe=prepare_python(args.download_python)
        cmd=[str(exe),str(Path(__file__).resolve()),'--worker',*sys.argv[1:]]
        result=subprocess.run(cmd,timeout=240*args.matches+600,capture_output=True,text=True,encoding='utf-8')
        print(result.stdout,end='');print(result.stderr,end='',file=sys.stderr)
        if result.returncode: raise SystemExit(result.returncode)
        return
    equivalence=source_equivalence();ai_hash=sha((AI_DIR/'offline_ai.js').read_bytes());host_hash=sha((AI_DIR/'offline_ai_host.js').read_bytes())
    engine=Engine(args.runtime.resolve())
    if args.prompt_scenarios or args.effect_scenarios:
        fixture=EFFECT_SCENARIO_SOURCE if args.effect_scenarios else SCENARIO_SOURCE
        fixture_hash=sha(fixture.read_bytes());harness_hash=sha(Path(__file__).read_bytes());scenarios=[]
        for kind in (EFFECT_SCENARIOS if args.effect_scenarios else SCENARIO_PROMPTS):
            for player in (0,1):
                result=engine.prompt_scenario(kind,player,args.seed+len(scenarios),effect=args.effect_scenarios);scenarios.append(result)
                print(json.dumps({k:result[k] for k in ('scenario','player','status','retryCount','forcedChains','durationSeconds')}),flush=True)
        if fixture_hash!=sha(fixture.read_bytes()) or harness_hash!=sha(Path(__file__).read_bytes()) or ai_hash!=sha((AI_DIR/'offline_ai.js').read_bytes()) or host_hash!=sha((AI_DIR/'offline_ai_host.js').read_bytes()): raise ValueError('Scenario, harness or AI changed during validation')
        counts=collections.Counter(r['message'] for s in scenarios for r in s['responses'])
        missing=set() if args.effect_scenarios else {21,22,24,25,132,140,141,142}-set(counts)
        report={'schemaVersion':1,'scope':'Real OCG-generated prompts answered by production JavaScript; completion markers prove resumed Lua operations, not complete matches or iOS UI execution.',
                'platform':'Windows x86 portable Python 3.12.10','pythonURL':PYTHON_URL,'pythonSHA256':PYTHON_SHA256,'pythonHashSource':PYTHON_SOURCE,
                'coreBinary':engine.binary,'binarySourceRevision':SOURCE_REVISION,'iosCoreRevision':IOS_CORE_REVISION,'exactIOSRevisionBinary':False,
                'coreSourceEquivalent':equivalence,'sourceEquivalenceNote':'Only 7 build/deploy files differ; C++/headers and Lua gitlink identical. Official binary provenance is not reproducible-build proof.',
                'nativeAPIVersion':engine.version,'aiSHA256':ai_hash,'hostAdapterSHA256':host_hash,'testLuaSHA256':fixture_hash,
                'scenariosAccepted':sum(s['status']=='accepted_completion_marker' for s in scenarios),'scenarios':scenarios,
                'promptResponseCounts':dict(sorted(counts.items())),'previouslyUncoveredPromptIDs':[21,22,24,25,132,140,141,142],'missingTargetPrompts':sorted(missing),
                'fullMatchesExecutedThisRun':0,'buildTriggered':False,'iosRuntimeVerified':False,'invocation':sys.argv[1:]}
        if args.effect_scenarios:
            report.pop('previouslyUncoveredPromptIDs');report.pop('missingTargetPrompts')
            report.update(scope='Canonical card scripts executed by real OCG with production AI; observer Lua asserts final game state before completion markers. These are bounded scenarios, not full games or iOS UI execution.',
                          harnessSHA256=harness_hash,databaseSHA256=sha((engine.runtime/'cards.cdb').read_bytes()),
                          canonicalScriptArchiveSHA256=sha(SCRIPT_ARCHIVE.read_bytes()),
                          interactions=list(EFFECT_SCENARIOS),testAssertionsVerified=all(s['status']=='accepted_completion_marker' for s in scenarios))
        args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
        if missing or any(s['status']!='accepted_completion_marker' for s in scenarios): raise SystemExit(1)
        return
    files=sorted((args.runtime/'deck').glob('*.ydk'));paths=[Path(args.deck_a) if args.deck_a else files[0],Path(args.deck_b) if args.deck_b else files[1]]
    cases=[]
    def sampled(count,seed):
        return [([files[i*len(files)//count],files[(i*len(files)//count+1)%len(files)]],seed+i) for i in range(count)]
    if args.suite:
        targeted=[args.runtime/'deck/OBB_NPC-YuseiFudo-B_bf18cbb498.ydk',args.runtime/'deck/OBB_NPC-JadenYuki-B_a15bc7c49f.ydk']
        cases=sampled(8,41)+[(targeted,seed) for seed in range(71,75)]+sampled(24,101)
    elif args.sample_decks: cases=sampled(args.matches,args.seed)
    else: cases=[(paths,args.seed+i) for i in range(args.matches)]
    matches=[]
    for paths,seed in cases:
        matches.append(engine.match(paths,seed));print(json.dumps({k:v for k,v in matches[-1].items() if k not in ('lastPrompts','scriptsLoaded','messages','scriptErrors','missingScriptRequests','deckHashes')}),flush=True)
    pool=engine.initialize_pool() if args.pool_check else None
    if ai_hash!=sha((AI_DIR/'offline_ai.js').read_bytes()) or host_hash!=sha((AI_DIR/'offline_ai_host.js').read_bytes()): raise ValueError('AI changed during validation; rerun the suite')
    report={'schemaVersion':1,'platform':'Windows x86 portable Python 3.12.10','pythonURL':PYTHON_URL,'pythonSHA256':PYTHON_SHA256,'pythonHashSource':PYTHON_SOURCE,'coreBinary':engine.binary,'binarySourceRevision':SOURCE_REVISION,'iosCoreRevision':IOS_CORE_REVISION,'exactIOSRevisionBinary':False,'coreSourceEquivalent':equivalence,'sourceEquivalenceNote':'git diff contains only 7 build/deploy files; C++/headers and Lua gitlink identical. Binary compilation provenance is official ProjectIgnis/bin commit, not reproducible-build proof.','nativeAPIVersion':engine.version,'aiSHA256':ai_hash,'hostAdapterSHA256':host_hash,'fullMatchesCompleted':sum(m['status']=='completed' for m in matches),'matches':matches,'poolInitialization':pool,'buildTriggered':False,'iosRuntimeVerified':False,'invocation':sys.argv[1:]}
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    if pool: print(json.dumps(pool),flush=True)
    if any(m['status']!='completed' for m in matches) or (pool and pool['status']!='passed'): raise SystemExit(1)
if __name__=='__main__': main()
