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
console.log(`Offline AI: ${fixtures.size} prompt families, human routing, malformed/forced choices, sums, timing and privacy checks passed.`);
