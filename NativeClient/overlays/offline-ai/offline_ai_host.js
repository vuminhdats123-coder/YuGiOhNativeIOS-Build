/* SPDX-License-Identifier: AGPL-3.0-or-later
 * JSON-lines test adapter. Executes the exact production decision module.
 * It does not implement a second AI or load any native library.
 */
'use strict';
const readline = require('node:readline');
const ai = require('./offline_ai.js');
const bots = new Map();

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
    for (const bot of bots.values()) bot.observe(request.message, request.bytes || []);
    return null;
  }
  const bot = bots.get(id);
  if (!bot) throw new Error(`Bot ${id} was not started`);
  if (request.op === 'observe') { bot.observe(request.message, request.bytes || []); return null; }
  if (request.op === 'forHuman') return bot.forHuman(request.message, request.bytes);
  if (request.op === 'decide') return bot.decide(request.message, request.bytes, request.declarable || [], request.ownPositions || {});
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
module.exports = {handle};
