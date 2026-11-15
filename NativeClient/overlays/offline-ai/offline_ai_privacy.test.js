'use strict';
const assert = require('node:assert/strict');
const ai = require('./offline_ai.js');
const host = require('./offline_ai_host.js');
const u = (value, count = 4) => Array.from({length:count}, (_, i) => Number(BigInt(value) >> BigInt(i * 8) & 255n));
const loc = (player, location, sequence = 0, position = 1) => [player,location,...u(sequence),...u(position)];
const list = entries => [...u(entries.length),...entries.flat()];
const empty = list([]);
const publicCard = (code, attack, sequence = 0) => ({code,attack,defense:1000,type:33,level:4,rank:0,link:0,disabled:false,location:4,position:1,sequence});
const privateEvents = (player, secret) => [
  [90,[1-player,...u(1),...u(secret),...u(8)]],
  [33,[1-player,...u(2),...u(secret),...u(secret+1)]],
  [39,[1-player,...u(1),...u(secret)]],
  [38,[player,...u(0),...u(secret),...u(8)]],
  [50,[...u(secret),...loc(player,1,0,8),...loc(player,2,0,8),...u(0)]]
];

// Spy at the adapter/bot boundary, not just on the final answer: private packets must never arrive.
const realCreate = ai.create;
try {
  for (const player of [0,1]) {
    host.handle({op:'stop',botID:0}); host.handle({op:'stop',botID:1});
    const observations = [], decisions = [];
    const redactor = realCreate({},player);
    ai.create = () => ({forHuman:(...args) => redactor.forHuman(...args),observe:(...args) => observations.push(args), decide:(...args) => { decisions.push(args); return {handled:true,response:[7,0,0,0]}; }});
    host.handle({op:'start',botID:player});
    for (const [message,bytes] of privateEvents(player,89631139)) host.handle({op:'observe',message,bytes});
    host.handle({op:'observe',botID:player,message:111,bytes:new Array(26).fill(0)});
    host.handle({op:'observe',message:2,bytes:[3,1-player,...u(89631139,8)]});
    assert.equal(observations.length,0,'Private event reached the AI observer');
    host.handle({op:'observe',message:40,bytes:[player]});
    assert.deepEqual(observations,[[40,[player]]]);
    for (const message of [71,72,73,75,76]) {
      const before = observations.length;
      host.handle({op:'observe',message,bytes:u(1)});
      assert.equal(observations.length,before,'Wrong-width chain index reached observer');
      host.handle({op:'observe',message,bytes:[1]});
      assert.deepEqual(observations.at(-1),[message,[1]]);
    }
    const hidden = {...publicCard(89631139,3000),position:8};
    const side = {lp:8000,handCount:3,deckCount:35,extraCount:2,cards:[hidden,publicCard(100,1200,1),{...hidden,location:1},{...hidden,location:2},{...hidden,location:64}],deck:[89631139],hand:[89631139],extra:[89631139],nextDraw:89631139};
    host.handle({op:'decide',botID:player,message:11,bytes:[player],board:{self:side,opponent:side,seed:123,nextDraw:89631139}});
    const sent = decisions[0][4];
    assert.deepEqual(Object.keys(sent).sort(),['opponent','self']);
    for (const view of Object.values(sent)) {
      assert.deepEqual(Object.keys(view).sort(),['cards','deckCount','extraCount','handCount','lp']);
      assert.equal(view.cards.length,2);
      assert.deepEqual(view.cards[0],{code:0,location:4,sequence:0,position:8});
      assert.deepEqual(view.cards[1],publicCard(100,1200,1));
    }
    const chaining = [...u(53129443),...loc(player,2,7),player,1,...u(9),...u(1,8),...u(1)];
    host.handle({op:'observe',message:70,bytes:chaining});
    const delivered = observations.at(-1)[1];
    assert.deepEqual(delivered.slice(0,4),u(53129443)); // Declared effect identity is public.
    assert.deepEqual(delivered.slice(6,10),u(0));
    assert.deepEqual(delivered.slice(16,20),u(0));
    assert.deepEqual(chaining.slice(6,10),u(7),'Filter must not mutate engine bytes');
    const choices = [player,0,...u(1),...u(1),...list([
      [...u(89631139),...loc(1-player,2,7,8)],
      [...u(46986414),...loc(1-player,16,3,1)],
      [...u(100),...loc(player,1,9,8)]
    ])];
    host.handle({op:'decide',botID:player,message:15,bytes:choices});
    const filtered = decisions.at(-1)[1];
    assert.deepEqual(filtered.slice(14,18),u(0),'Opposing hand identity reached decide');
    assert.deepEqual(filtered.slice(28,32),u(46986414),'Public GY identity must remain usable');
    assert.deepEqual(filtered.slice(42,46),u(100),'Own legal search candidate must remain usable');
    for (const offset of [18,32]) assert.deepEqual(filtered.slice(offset,offset+10),choices.slice(offset,offset+10));
    assert.deepEqual(filtered.slice(48,52),u(0),'Private Deck sequence reached decide');
    assert.deepEqual(host.handle({op:'forHuman',botID:player,message:15,bytes:choices}).slice(48,52),u(9),'Human lookup sequence must remain intact');
  }
} finally {
  ai.create = realCreate;
  host.handle({op:'stop',botID:0}); host.handle({op:'stop',botID:1});
}

// The actual decision module must be invariant to private identities/order with the same visible state.
for (const player of [0,1]) {
  let expected;
  for (const secret of [89631139,46986414,70781052,60800381,12014404]) {
    host.handle({op:'start',botID:player,metadata:{100:{attack:1800,defense:1000,type:33,level:4},53129443:{attack:0,defense:0,type:2,level:0},[secret]:{attack:secret%5000,defense:secret%4000,type:33,level:8}}});
    for (const [message,bytes] of privateEvents(player,secret)) host.handle({op:'observe',botID:player,message,bytes});
    const self = {lp:8000,handCount:2,deckCount:35,extraCount:0,cards:[],deck:[secret,100],nextDraw:secret};
    const opponent = {lp:8000,handCount:4,deckCount:34,extraCount:5,cards:[publicCard(200,2400),publicCard(300,2000,1),{...publicCard(secret,secret%5000,2),position:8}],hand:[secret]};
    const normal = [...u(100),player,2,...u(0)];
    const spell = [...u(53129443),player,2,...u(1),...u(1,8),0];
    const answer = host.handle({op:'decide',botID:player,message:11,bytes:[player,...list([normal]),...empty,...empty,...empty,...empty,...list([spell]),1,1,0],board:{self,opponent,seed:secret}});
    if (expected === undefined) expected = answer;
    else assert.deepEqual(answer,expected,'Hidden identity or future deck order changed the decision');
    host.handle({op:'stop',botID:player});
  }
}
console.log('AI privacy: pre-observer filtering, field-only snapshots, hidden-stat redaction and both-player hidden-order invariance passed.');
