/* SPDX-License-Identifier: AGPL-3.0-or-later
 * JSON-lines test adapter. Executes the exact production decision module.
 * It does not implement a second AI or load any native library.
 */
'use strict';
const readline = require('node:readline');
const ai = require('./offline_ai.js');
const bots = new Map();

function publicObservation(message, bytes, player) {
  if (!Array.isArray(bytes) || bytes.some(v => !Number.isInteger(v) || v < 0 || v > 255)) return null;
  const sizes = {2:10,40:1,41:2,60:14,61:0,62:14,63:0,64:14,65:0,70:32,71:1,72:1,73:1,74:0,75:1,76:1,110:20,113:0,114:0};
  if (sizes[message] === undefined || bytes.length !== sizes[message]) return null;
  if (message === 2 && (bytes[0] !== 3 || bytes[1] !== player)) return null;
  const result = bytes.slice();
  if ([60,62,64].includes(message) && !(result[10] & 5)) result.fill(0,0,4);
  if (message === 70) {
    if ([1,2,64].includes(result[5])) result.fill(0,6,10);
    if ([1,2,64].includes(result[15])) result.fill(0,16,20);
  }
  return result;
}

function visibleBoard(board) {
  if (board === undefined || board === null) return undefined;
  const integer = value => { if (!Number.isInteger(value)) throw new Error('Invalid board integer'); return value; };
  const result = {};
  for (const side of ['self','opponent']) {
    const source = board[side];
    if (!source || !Array.isArray(source.cards) || source.cards.length > 15) throw new Error('Invalid board side');
    const target = {lp:integer(source.lp),handCount:integer(source.handCount),deckCount:integer(source.deckCount),extraCount:integer(source.extraCount),cards:[]};
    for (const card of source.cards) {
      if (![4,8].includes(card.location)) continue;
      const entry = {code:0,location:card.location,sequence:integer(card.sequence),position:integer(card.position)};
      if ((entry.position & 5) && card.code !== 0) {
        for (const key of ['code','type','attack','defense','level','rank','link']) entry[key]=integer(card[key]);
        entry.disabled=Boolean(card.disabled);
      }
      target.cards.push(entry);
    }
    result[side]=target;
  }
  return result;
}

function handle(request) {
  if (!request || typeof request !== 'object' || Array.isArray(request)) throw new Error('Expected a request object');
  const id = request.botID === undefined ? 1 : request.botID;
  if (id !== 0 && id !== 1) throw new Error('botID must be 0 or 1');
  if (request.op === 'start') {
    bots.set(id, ai.create(request.metadata || {}, id));
    return {botID:id};
  }
  if (request.op === 'stop') { bots.delete(id); return null; }
  if (request.op === 'observe' && request.botID === undefined) {
    for (const [player,bot] of bots) {
      const bytes=publicObservation(request.message,request.bytes || [],player);
      if (bytes !== null) bot.observe(request.message,bytes);
    }
    return null;
  }
  const bot = bots.get(id);
  if (!bot) throw new Error(`Bot ${id} was not started`);
  if (request.op === 'observe') {
    const bytes=publicObservation(request.message,request.bytes || [],id);
    if (bytes !== null) bot.observe(request.message,bytes);
    return null;
  }
  if (request.op === 'forHuman') return bot.forHuman(request.message, request.bytes);
  if (request.op === 'decide') {
    const bytes=bot.forHuman(request.message,request.bytes,true);
    if (!Array.isArray(bytes)) throw new Error('Decision prompt is not visible');
    return bot.decide(request.message, bytes, request.declarable || [], request.ownPositions || {}, visibleBoard(request.board));
  }
  throw new Error('Unknown host operation');
}

if (require.main === module) {
  const input = readline.createInterface({input:process.stdin, crlfDelay:Infinity});
  input.on('line', line => {
    let response;
    try {
      if (line.length > 8 * 1024 * 1024) throw new Error('Request exceeds size limit');
      response = {ok:true,result:handle(JSON.parse(line))};
    } catch (error) {
      response = {ok:false,error:error instanceof Error ? error.message : String(error)};
    }
    process.stdout.write(JSON.stringify(response) + '\n');
  });
}
module.exports = {handle, publicObservation, visibleBoard};
