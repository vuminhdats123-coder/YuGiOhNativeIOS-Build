'use strict';
const assert = require('node:assert/strict');
const ai = require('./offline_ai.js');
const u = (v,n=4) => { let b=BigInt.asUintN(n*8,BigInt(v)),a=[]; for(let i=0;i<n;i++){a.push(Number(b&255n));b>>=8n;} return a; };
const loc=(c=1,l=4,s=0,p=1)=>[c,l,...u(s),...u(p)];
const card=(code=100,c=1,l=4,s=0,p=1)=>[...u(code),...loc(c,l,s,p)];
const short=(code=100,c=1,l=2,s=0)=>[...u(code),c,l,...u(s)];
const list=a=>[...u(a.length),...a.flat()];
const selected=a=>[...u(0),...u(a.length),...a.flatMap(i=>u(i))];
const empty=list([]);
const effect=(code=100,c=1,l=8,s=0)=>[...short(code,c,l,s),...u(1,8),0];
const metadata={100:{attack:1000,defense:500},200:{attack:2000,defense:1000}};
const fixtures=new Map([
 [10, [[1,...empty,...list([[...u(100),1,4,0,1],[...u(200),1,4,1,1]]),1,1],u(65537)]],
 [11, [[1,...list([short(100),short(200)]),...empty,...empty,...empty,...empty,...empty,1,1,0],u(65536)]],
 [12, [[1,...card(),...u(100,8)],u(1)]],
 [13, [[1,...u(100,8)],u(1)]],
 [14, [[1,2,...u(12,8),...u(22,8)],u(0)]],
 [15, [[1,0,...u(2),...u(3),...list([card(),card(200),card(300)])],selected([0,1])]],
 [16, [[1,0,1,...u(0),...u(0),...list([[...card(),...u(1,8),0]])],u(0)]],
 [18, [[1,2,...u((~(1|65536))>>>0)],[1,4,0,0,4,0]]],
 [19, [[1,...u(100),5],u(1)]],
 [20, [[1,0,...u(2),...u(1),...list([[...short(100),1],[...short(200),2]])],selected([1])]],
 [21, [[1,...list([[...u(100),1,...u(4),...u(0)]])],u(-1)]],
 [22, [[1,...u(1,2),...u(3,2),...list([[...u(100),1,4,0,...u(2,2)],[...u(200),1,4,1,...u(2,2)]])],[2,0,1,0]]],
 [23, [[1,0,...u(6),...u(1),...u(2),...list([[...card(),...u(2)]]),...list([[...card(200),...u(2)],[...card(300),...u(4)]])],selected([1])]],
 [24, [[1,1,...u((~(1<<24))>>>0)],[0,8,0]]],
 [25, [[1,...list([[...u(100),1,...u(4),...u(0)]])],u(-1)]],
 [26, [[1,1,0,...u(0),...u(2),...empty,...empty],u(-1)]],
 [132, [[1],u(2)]],
 [140, [[1,2,...u((1n<<50n)|2n,8)],u((1n<<50n)|2n,8)]],
 [141, [[1,2,...u(33)],u(33)]],
 [142, [[1,1,...u(1,8)],u(89631139)]],
 [143, [[1,2,...u(7,8),...u(11,8)],u(0)]]
]);
assert.deepEqual([...fixtures.keys()].sort((a,b)=>a-b),ai.promptTypes.slice().sort((a,b)=>a-b));
for(const [message,[payload,expected]] of fixtures) {
  const result=ai.create(metadata).decide(message,payload,[89631139]);
  assert.equal(result.handled,true); assert.deepEqual(result.response,expected,`prompt ${message}`);
  assert.deepEqual(ai.create(metadata).decide(message,[0,...payload.slice(1)]),{handled:false},`human ${message}`);
  assert.throws(()=>ai.create(metadata).decide(message,payload.slice(0,-1),[89631139]),`truncated ${message}`);
  assert.throws(()=>ai.create(metadata).decide(message,[...payload,0],[89631139]),`trailing ${message}`);
}
assert.throws(()=>ai.create().decide(255,[1]),/Unknown/);
assert.throws(()=>ai.create().decide(15,[1,0,...u(2),...u(1),...empty]),/Impossible/);
assert.throws(()=>ai.create().decide(16,[1,0,1,...u(0),...u(0),...empty]),/Forced/);
assert.throws(()=>ai.create().decide(20,[1,0,...u(3),...u(1),...list([[...short(),1]])]),/No legal tribute/);
assert.throws(()=>ai.create().decide(23,[1,0,...u(99),...u(1),...u(1),...empty,...list([[...card(),...u(1)]])]),/No legal sum/);
assert.deepEqual(ai.create().decide(23,[1,1,...u(5),...u(0),...u(0),...list([[...card(),...u(2)]]),...list([[...card(200),...u(3)]])]).response,selected([0]));
assert.deepEqual(ai.create().decide(26,[1,0,0,...u(1),...u(2),...list([card()]),...empty]).response,[...u(1),...u(0)]);
assert.throws(()=>ai.create().decide(26,[1,0,0,...u(1),...u(2),...empty,...empty]),/Empty forced/);
assert.throws(()=>ai.create().decide(142,fixtures.get(142)[0],[]),/declarable/);
assert.throws(()=>ai.create().decide(18,[1,1,...u(0xffffffff)]),/legal zones/);
assert.throws(()=>ai.create().decide(19,[1,...u(100),0]),/position/);

// Optional chains are real choices, bounded once per turn; don't chain to own effect.
const optionalChain=[1,0,0,...u(0),...u(0),...list([[...card(100),...u(1,8),0],[...card(200),...u(2,8),0]])];
const bot=ai.create(metadata);
assert.deepEqual(bot.decide(16,optionalChain).response,u(1));
bot.observe(70,[...card(200),1]);
assert.deepEqual(bot.decide(16,optionalChain).response,u(-1));
bot.observe(74); bot.observe(40);
assert.deepEqual(bot.decide(16,optionalChain).response,u(1));

// Do not blindly turn an attacking monster into defense.
const reposition=[1,...empty,...empty,...list([[...u(200),1,4,0]]),...empty,...empty,...empty,0,1,0];
assert.deepEqual(ai.create(metadata).decide(11,reposition,[],{'0':1}).response,u(7));
assert.deepEqual(ai.create(metadata).decide(11,reposition,[],{'0':8}).response,u(2));

// Short tribute records omit position: hidden opponent identity must not change choices.
const tributeBlind=(a,b)=>[1,0,...u(1),...u(1),...list([[...short(a,0,4,0),1],[...short(b,0,4,1),1]])];
assert.deepEqual(ai.create(metadata).decide(20,tributeBlind(100,200)).response,
                 ai.create(metadata).decide(20,tributeBlind(200,100)).response);

// Preserve public effects and own cards; redact private draw/move/confirmation data.
const hiddenDraw=[1,...u(1),...u(89631139),...u(8)];
assert.deepEqual(bot.forHuman(90,hiddenDraw),[1,...u(1),...u(0),...u(8)]);
assert.deepEqual(bot.forHuman(90,[0,...hiddenDraw.slice(1)]),[0,...hiddenDraw.slice(1)]);
assert.deepEqual(bot.forHuman(90,[1,...u(1),...u(89631139),...u(1)]),[1,...u(1),...u(89631139),...u(1)]);
const hiddenMove=[...u(89631139),...loc(1,1,0,8),...loc(1,2,0,8),...u(0)];
assert.deepEqual(bot.forHuman(50,hiddenMove).slice(0,4),u(0));
assert.equal(bot.forHuman(31,[1,...u(1),...u(89631139),1,1,...u(0)]),null);
assert.throws(()=>bot.forHuman(90,hiddenDraw.slice(0,-1)),/Truncated/);
const blindChoice=[0,0,...u(1),...u(1),...list([card(89631139,1,2,0,8)])];
assert.deepEqual(bot.forHuman(15,blindChoice).slice(14,18),u(0));

// A second perspective uses the production decision logic, without rewriting bytes.
assert.throws(()=>ai.create({},2),/Invalid AI player/);
const zeroIdle=[0,...list([short(100,0),short(200,0)]),...empty,...empty,...empty,...empty,...empty,1,1,0];
assert.deepEqual(ai.create(metadata,0).decide(11,zeroIdle).response,u(65536));
assert.deepEqual(ai.create(metadata,0).decide(11,fixtures.get(11)[0]),{handled:false});
assert.deepEqual(ai.create(metadata,0).decide(18,[0,2,...u((~(1|65536))>>>0)]).response,[0,4,0,1,4,0]);
const zeroHiddenTribute=(a,b)=>[0,0,...u(1),...u(1),...list([[...short(a,1,4,0),1],[...short(b,1,4,1),1]])];
assert.deepEqual(ai.create(metadata,0).decide(20,zeroHiddenTribute(100,200)).response,
                 ai.create(metadata,0).decide(20,zeroHiddenTribute(200,100)).response);
assert.deepEqual(ai.create(metadata,0).forHuman(90,[0,...hiddenDraw.slice(1)]),[0,...u(1),...u(0),...u(8)]);

// HINT_SELECTMSG supplies the selection's purpose. Keep heuristics tied to that
// public engine event instead of guessing that every card picker is a target.
const tactical=ai.create({...metadata,300:{attack:0,defense:2000},400:{attack:3000,defense:2500}});
const hint=(id,player=1)=>[3,player,...u(id,8)];
const pick=cards=>[1,0,...u(1),...u(1),...list(cards)];
tactical.observe(2,hint(501));
assert.deepEqual(tactical.decide(15,pick([card(200,1,2,0,8),card(100,1,2,1,8)])).response,selected([1]));
tactical.observe(2,hint(509));
assert.deepEqual(tactical.decide(15,pick([card(100,1,1,0,8),card(200,1,1,1,8)])).response,selected([1]));
assert.deepEqual(tactical.decide(19,[1,...u(300),5]).response,u(4));
assert.deepEqual(tactical.decide(19,[1,...u(300),1]).response,u(1));
tactical.decide(10,fixtures.get(10)[0]);
tactical.observe(2,hint(549));
assert.deepEqual(tactical.decide(15,pick([card(400,0,4,0,1),card(100,0,4,1,1)])).response,selected([1]));
function blindAttack(first,second) {
  const duel=ai.create({...metadata,400:{attack:3000,defense:2500}});
  duel.decide(10,fixtures.get(10)[0]); duel.observe(2,hint(549));
  return duel.decide(15,pick([card(first,0,4,0,8),card(second,0,4,1,8)])).response;
}
assert.deepEqual(blindAttack(100,400),blindAttack(400,100));
// Hidden identities must not leak through the once-per-turn action history.
const hiddenChain=code=>[1,0,0,...u(0),...u(0),...list([[...card(code,0,4,0,8),...u(1,8),0]])];
const hiddenFirst=ai.create(metadata),hiddenSecond=ai.create(metadata);
hiddenFirst.decide(16,hiddenChain(100)); hiddenSecond.decide(16,hiddenChain(100));
assert.deepEqual(hiddenFirst.decide(16,hiddenChain(100)).response,
                 hiddenSecond.decide(16,hiddenChain(200)).response);
tactical.observe(2,hint(509,0)); // The other player's hint must not affect us.
assert.deepEqual(tactical.decide(15,pick([card(100),card(200)])).response,selected([0]));
for(const player of [0,1]) for(let mask=1;mask<16;mask++) {
  const answer=ai.create({300:{attack:0,defense:2000}},player).decide(19,[player,...u(300),mask]).response;
  const position=answer[0];
  assert([1,2,4,8].includes(position) && (position&mask)===position,`invalid position ${mask}`);
}

// Pendulum procedures repeat HINTMSG_SPSUMMON for each legal group addition.
// MSG26 min/max=1 describe the toggle, not the final summon group's size.
for(const player of [0,1]) {
  const group=ai.create({},player), hand=card(100,player,2,0,8), extra=card(200,player,64,0,4);
  const hand2=card(300,player,2,1,8), toggle=[...u(1),...u(0)];
  const prompt=(finishable,choices,chosen)=>[player,Number(finishable),1,...u(1),...u(1),...list(choices),...list(chosen)];
  const summon=(finishable,choices,chosen)=>{
    group.observe(2,hint(509,player));
    return group.decide(26,prompt(finishable,choices,chosen)).response;
  };
  assert.deepEqual(summon(false,[hand,extra,hand2],[]),toggle);
  assert.deepEqual(summon(true,[extra,hand2],[hand]),toggle,`mixed Pendulum player ${player}`);
  assert.deepEqual(summon(true,[hand2],[hand,extra]),toggle);
  assert.deepEqual(summon(true,[],[hand,extra,hand2]),u(-1));
  // A consumed hint cannot affect another picker; other players' hints are ignored.
  assert.deepEqual(group.decide(26,prompt(true,[extra],[hand])).response,u(-1));
  group.observe(2,hint(509,1-player));
  assert.deepEqual(group.decide(26,prompt(true,[extra],[hand])).response,u(-1));
  for(const otherHint of [500,511,512,513,533,549,999]) {
    group.observe(2,hint(otherHint,player));
    assert.deepEqual(group.decide(26,prompt(true,[extra],[hand])).response,u(-1));
  }
  // Do not extend material/hidden-opponent pickers merely because they share MSG26.
  for(const ineligible of [card(100,1-player,2,0,8),card(100,player,64,0,8),card(100,player,4,0,1)]) {
    assert.deepEqual(summon(true,[ineligible],[hand]),u(-1));
    assert.deepEqual(summon(true,[extra,ineligible],[hand]),u(-1));
    assert.deepEqual(summon(true,[extra],[hand,ineligible]),u(-1));
  }
}

// Exhaustive small-domain oracle: validate against the engine's mathematical
// constraints, not the production solver's DP/DFS implementation.
const smallContributions=Array.from({length:20},()=>({value:1}));
assert.deepEqual(ai.solveSum(1,30,0,0,[],[...smallContributions,{value:100}]),[20]);
assert.deepEqual(ai.solveSum(1,30,0,0,[],[...smallContributions,{value:17},{value:18}]),[21,20]);
let seed=0x7484;
function random(n) { seed=(Math.imul(seed,1664525)+1013904223)>>>0; return seed%n; }
function valueOptions(card) { const low=card.value&65535,high=card.value>>>16; return high?[low,high]:[low]; }
function sumAccepts(mode,target,min,max,mandatory,optional,indices) {
  if(new Set(indices).size!==indices.length || indices.some(i=>i<0||i>=optional.length)) return false;
  const cards=mandatory.concat(indices.map(i=>optional[i]));
  if(!cards.length) return false;
  if(mode===0) {
    if(indices.length<min||indices.length>max) return false;
    let totals=[0];
    for(const card of cards) totals=totals.flatMap(total=>valueOptions(card).map(value=>total+value));
    return totals.includes(target);
  }
  const values=cards.map(valueOptions),low=values.map(v=>Math.min(...v)),high=values.map(v=>Math.max(...v));
  return high.reduce((a,b)=>a+b,0)>=target && low.reduce((a,b)=>a+b,0)-Math.min(...low)<target;
}
for(let trial=0;trial<1000;trial++) {
  const makeCard=()=>({value:(1+random(8))+(random(4)===0?(1+random(8))*65536:0)});
  const mandatory=Array.from({length:random(3)},makeCard), optional=Array.from({length:1+random(7)},makeCard);
  const mode=random(2), target=1+random(30), min=mode?0:random(3), max=mode?0:min+random(4);
  const valid=[];
  for(let mask=0;mask<2**optional.length;mask++) {
    const selectedIndices=optional.map((_,i)=>i).filter(i=>mask&(1<<i));
    if(sumAccepts(mode,target,min,max,mandatory,optional,selectedIndices)) valid.push(selectedIndices);
  }
  if(valid.length) {
    const answer=ai.solveSum(mode,target,min,max,mandatory,optional);
    assert(sumAccepts(mode,target,min,max,mandatory,optional,answer),`invalid sum witness ${trial}`);
  } else assert.throws(()=>ai.solveSum(mode,target,min,max,mandatory,optional),/No legal sum/);
}

// Paired tactical decisions run the production policy, changing only public board facts.
const C={DARK:53129443,RAIGEKI:12580477,REBORN:83764718,MST:5318639,JUDGMENT:41420027,
  JAMMER:77414722,CHALICE:25789292,RUSH:70046172,POT:55144522,UPSTART:70368879,FIRE:46918794};
const tacticsMetadata={901:{type:17,attack:300,defense:100,level:1},902:{type:17,attack:1800,defense:2000,level:4},
  903:{type:33,attack:3000,defense:2500,level:8},904:{type:33,attack:2000,defense:1500,level:4},
  905:{type:33,attack:1700,defense:1000,level:4},906:{type:0x20002,attack:0,defense:0,level:0},
  ...Object.fromEntries(Object.values(C).map(code=>[code,{type:[C.JAMMER,C.JUDGMENT].includes(code)?0x100004:2,attack:0,defense:0,level:0}]))};
const onField=(code,sequence=0,overrides={})=>({code,location:4,sequence,position:1,...tacticsMetadata[code],...overrides});
const state=(own=[],enemy=[],options={})=>({self:{lp:8000,handCount:2,deckCount:20,extraCount:0,cards:own,...options.self},
  opponent:{lp:8000,handCount:2,deckCount:20,extraCount:0,cards:enemy,...options.opponent}});
const idleEffects=(codes,normal=[])=>[1,...list(normal),...empty,...empty,...empty,...empty,
  ...list(codes.map(code=>effect(code,1,2,0))),0,1,0];
const battlePrompt=(codes=[902],effects=[])=>[1,...list(effects.map(code=>effect(code,1,8,0))),
  ...list(codes.map((code,index)=>[...u(code),1,4,index,0])),1,1];
const chainPrompt=codes=>[1,0,0,...u(0),...u(0),...list(codes.map((code,index)=>[...card(code,1,8,index,8),...u(1,8),0]))];
const chainEvent=(code,controller=0,location=8,sequence=0)=>[
  ...card(code,controller,location,sequence,1),controller,location,...u(sequence),...u(1,8),...u(1)];
const act=(message,payload,live,prepare)=>{const bot=ai.create(tacticsMetadata);if(prepare)prepare(bot);return bot.decide(message,payload,[],{},live).response;};
const strongSelf=state([onField(903)],[onField(901)]),strongEnemy=state([onField(901)],[onField(903)]);
assert.deepEqual(act(11,idleEffects([C.DARK]),strongSelf),u(7));
assert.deepEqual(act(11,idleEffects([C.DARK]),strongEnemy),u(5));
assert.deepEqual(act(11,idleEffects([C.DARK],[short(902)]),strongEnemy),u(5),'clear before adding our own body');
assert.deepEqual(act(11,idleEffects([C.RAIGEKI]),state()),u(7));
assert.deepEqual(act(11,idleEffects([C.RAIGEKI]),strongEnemy),u(5));
assert.deepEqual(act(11,idleEffects([999999]),strongEnemy),u(7),'unknown optional effect is conservative');
assert.throws(()=>ai.create(tacticsMetadata).decide(11,idleEffects([C.DARK]),[],{},{self:{},opponent:{}}),/tactical board/);

// Current public stats, not the printed CDB value, determine whether an attack is safe.
const printedWeakButBuffed=state([onField(902)],[onField(901,0,{attack:3200})]);
const sameCardWeakened=state([onField(902)],[onField(901,0,{attack:500})]);
assert.deepEqual(act(10,battlePrompt(),printedWeakButBuffed),u(2));
assert.deepEqual(act(10,battlePrompt(),sameCardWeakened),u(1));
assert.deepEqual(act(19,[1,...u(902),5],printedWeakButBuffed),u(4));
assert.deepEqual(act(19,[1,...u(902),5],sameCardWeakened),u(1));
assert.deepEqual(act(15,pick([card(C.REBORN,1,2,0,8),card(901,1,2,1,8)]),state(),b=>b.observe(2,hint(501))),selected([1]));
const weakTributes=[1,0,...u(2),...u(2),...list([[...short(903,1,4,0),1],[...short(901,1,4,1),1],[...short(901,1,4,2),1]])];
assert.deepEqual(act(20,weakTributes,state([onField(903),onField(901,1),onField(901,2)])),selected([1,2]));

// Public Graveyard cards remain rankable; hand/deck/facedown choices do not reveal their identities.
const privacy=ai.create(tacticsMetadata),publicGY=pick([card(901,1,16,0,1),card(903,0,16,0,1)]);
assert.deepEqual(privacy.forHuman(15,publicGY),publicGY);
const ownDeckChoice=pick([card(901,1,1,7,8),card(903,1,1,12,8)]);
assert.deepEqual(privacy.forHuman(15,ownDeckChoice),ownDeckChoice,'human GetCard coordinates stay intact');
const deckDecision=privacy.forHuman(15,ownDeckChoice,true);
assert.deepEqual(deckDecision,pick([card(901,1,1,0,8),card(903,1,1,0,8)]),'AI sees legal IDs without deck order');
assert.deepEqual(act(15,deckDecision,state(),b=>b.observe(2,hint(509))),selected([1]),'wire selection index survives deck-coordinate redaction');
const shortDeckChoice=[1,0,...u(1),...u(1),...list([[...short(901,1,1,7),1]])];
assert.deepEqual(privacy.forHuman(20,shortDeckChoice),shortDeckChoice);
assert.deepEqual(privacy.forHuman(20,shortDeckChoice,true),[1,0,...u(1),...u(1),...list([[...short(901,1,1,0),1]])]);
assert.deepEqual(act(15,privacy.forHuman(15,publicGY),state(),b=>b.observe(2,hint(509))),selected([1]));
for(const [location,position] of [[1,8],[2,8],[4,8],[8,8],[32,8],[64,1]]) {
  const raw=pick([card(903,0,location,3,position)]),hidden=privacy.forHuman(15,raw);
  assert.deepEqual(hidden.slice(14,18),u(0));
  assert.deepEqual(hidden.slice(18),raw.slice(18),'selection indices/locations must remain intact');
}
for(const [location,position] of [[4,1],[8,1],[16,8],[32,1],[128|4,2]]) {
  const raw=pick([card(903,0,location,3,position)]);
  assert.deepEqual(privacy.forHuman(15,raw),raw);
}

const spellBoard=(code)=>state([onField(903)],[onField(901),onField(code,0,{location:8,type:tacticsMetadata[code].type})]);
assert.deepEqual(act(16,chainPrompt([C.JAMMER]),spellBoard(C.DARK),b=>b.observe(70,chainEvent(C.DARK))),u(0));
assert.deepEqual(act(16,chainPrompt([C.JAMMER]),spellBoard(C.UPSTART),b=>b.observe(70,chainEvent(C.UPSTART))),u(-1));
assert.deepEqual(act(16,chainPrompt([C.MST]),spellBoard(C.DARK),b=>b.observe(70,chainEvent(C.DARK))),u(-1),'destroying a normal spell does not negate it');
assert.deepEqual(act(16,chainPrompt([C.MST]),spellBoard(906),b=>b.observe(70,chainEvent(906))),u(0));
const judgment=(own)=>act(16,chainPrompt([C.JUDGMENT]),state(own),b=>b.observe(62,card(903,0,4,0,1)));
assert.deepEqual(judgment([onField(901)]),u(0));
assert.deepEqual(judgment([onField(903,0,{attack:4000})]),u(-1));
assert.deepEqual(act(11,idleEffects([C.FIRE]),state([],[],{self:{lp:500}})),u(7));
assert.deepEqual(act(11,idleEffects([C.FIRE]),state()),u(5));
assert.deepEqual(act(11,idleEffects([C.POT]),state([],[],{self:{deckCount:1}})),u(7),'do not draw into an empty deck');

// Rush waits for actual Damage Step and is spent only when +700 changes the outcome or is lethal.
const rushBattle=state([onField(902,0,{defense:1000})],[onField(904)]);
assert.deepEqual(act(10,battlePrompt([902],[C.RUSH]),rushBattle),u(1),'a known legal boost can justify an attack');
const rush=ai.create(tacticsMetadata);rush.observe(110,[...loc(1,4,0,1),...loc(0,4,0,1)]);
assert.deepEqual(rush.decide(16,chainPrompt([C.RUSH]),[],{},rushBattle).response,u(-1));
rush.observe(113);
assert.deepEqual(rush.decide(16,chainPrompt([C.RUSH]),[],{},rushBattle).response,u(0));
rush.observe(2,hint(514));
assert.deepEqual(rush.decide(15,pick([card(904,0,4,0,1),card(902,1,4,0,1)]),[],{},rushBattle).response,selected([1]));
assert.deepEqual(act(16,chainPrompt([C.RUSH]),state([onField(902)],[onField(905)]),b=>{
  b.observe(110,[...loc(1,4,0,1),...loc(0,4,0,1)]);b.observe(113);
}),u(-1),'preserve a boost in an already won nonlethal battle');
assert.deepEqual(act(16,chainPrompt([C.CHALICE]),state([onField(902)],[onField(904)]),b=>b.observe(70,chainEvent(904,0,4,0))),u(0));
assert.deepEqual(act(16,chainPrompt([C.CHALICE]),state([onField(902)],[onField(904,0,{disabled:true})]),b=>b.observe(70,chainEvent(904,0,4,0))),u(-1));
const bothSideEffect=ai.create(tacticsMetadata),bothSideBoard=state([onField(903)],[onField(904)]);
bothSideEffect.observe(70,[...card(903,1,4,0,1),0,4,...u(0),...u(1,8),...u(1)]);
assert.deepEqual(bothSideEffect.decide(16,chainPrompt([C.CHALICE]),[],{},bothSideBoard).response,u(0));
bothSideEffect.observe(2,hint(514));
assert.deepEqual(bothSideEffect.decide(15,pick([card(903,1,4,0,1),card(904,0,4,0,1)]),[],{},bothSideBoard).response,selected([0]),
  'chain target uses the wire location controller, not the effect activator');

// Hidden-state permutations and guessed future draws cannot affect identical current knowledge.
const hiddenBoards=[state([onField(902)],[onField(901,0,{position:8})]),
  state([onField(902)],[onField(903,0,{position:8,attack:999999,defense:999999})])];
assert.deepEqual(act(10,battlePrompt(),hiddenBoards[0]),act(10,battlePrompt(),hiddenBoards[1]));
const nextDrawBoards=[JSON.parse(JSON.stringify(strongEnemy)),JSON.parse(JSON.stringify(strongEnemy))];
nextDrawBoards[0].self.nextDraw=903;nextDrawBoards[0].self.deck=[903,901];
nextDrawBoards[1].self.nextDraw=901;nextDrawBoards[1].self.deck=[901,903];
assert.deepEqual(act(11,idleEffects([C.DARK]),nextDrawBoards[0],b=>b.observe(90,[1,...u(1),...u(903),...u(8)])),
  act(11,idleEffects([C.DARK]),nextDrawBoards[1],b=>b.observe(90,[1,...u(1),...u(901),...u(8)])));
for(const [a,b] of [[901,903],[903,901]]) {
  const hiddenTargets=pick([card(a,0,4,0,8),card(b,0,4,1,8)]);
  const hiddenState=state([onField(902)],[onField(a,0,{position:8}),onField(b,1,{position:8})]);
  assert.deepEqual(act(15,hiddenTargets,hiddenState,x=>x.observe(2,hint(502))),selected([0]));
}

// Verify the real JSON-lines adapter in a separate Node process: independent
// state for both players, strict human routing, and no non-JSON stdout noise.
const {spawnSync}=require('node:child_process');
const requests=[
  {op:'start',botID:0,metadata}, {op:'start',botID:1,metadata},
  {op:'decide',botID:0,message:11,bytes:zeroIdle},
  {op:'decide',botID:1,message:11,bytes:fixtures.get(11)[0]},
  {op:'decide',botID:0,message:11,bytes:fixtures.get(11)[0]},
  {op:'observe',message:40,bytes:[0]},
  {op:'decide',botID:0,message:11,bytes:zeroIdle},
  {op:'decide',botID:1,message:255,bytes:[1]},
  {op:'stop',botID:0}, {op:'decide',botID:0,message:11,bytes:zeroIdle}
];
const hosted=spawnSync(process.execPath,[require.resolve('./offline_ai_host.js')],
  {input:requests.map(r=>JSON.stringify(r)).join('\n')+'\n',encoding:'utf8',timeout:10000});
assert.equal(hosted.status,0,hosted.stderr);
const replies=hosted.stdout.trim().split('\n').map(line=>JSON.parse(line));
assert.equal(replies.length,requests.length);
for(const i of [2,3,6]) assert.deepEqual(replies[i],{ok:true,result:{handled:true,response:u(65536)}});
assert.deepEqual(replies[4],{ok:true,result:{handled:false}});
assert.equal(replies[7].ok,false); assert.match(replies[7].error,/Unknown AI prompt/);
assert.equal(replies[9].ok,false); assert.match(replies[9].error,/not started/);
console.log(`Offline AI: ${fixtures.size} prompt families, paired live-board tactics, Damage Step, sums, timing and privacy checks passed.`);
