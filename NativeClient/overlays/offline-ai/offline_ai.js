/* SPDX-License-Identifier: AGPL-3.0-or-later
 * OCG API 11 prompt decisions. Protocol: pinned ocgcore/playerop.cpp.
 * This module is shared verbatim by JavaScriptCore on iOS and the Node tests.
 */
(function (root) {
  'use strict';
  const PROMPTS = new Set([10,11,12,13,14,15,16,18,19,20,21,22,23,24,25,26,132,140,141,142,143]);
  const MAX_ITEMS = 4096, MAX_SEARCH = 200000;
  function fail(message) { throw new Error(message); }
  class Reader {
    constructor(bytes) {
      if (!Array.isArray(bytes) || bytes.length > 1048576 || bytes.some(v => !Number.isInteger(v) || v < 0 || v > 255)) fail('Invalid prompt bytes');
      this.b = bytes; this.at = 0;
    }
    number(n) {
      if (this.at + n > this.b.length) fail('Truncated prompt');
      let value = 0;
      for (let i = 0; i < n; i++) value += this.b[this.at++] * 2 ** (i * 8);
      return value;
    }
    u8() { return this.number(1); }
    u16() { return this.number(2); }
    u32() { return this.number(4); }
    u64() { const lo = this.u32(), hi = this.u32(); return BigInt(lo) | BigInt(hi) << 32n; }
    count() { const n = this.u32(); if (n > MAX_ITEMS) fail('Prompt exceeds item limit'); return n; }
    end() { if (this.at !== this.b.length) fail('Unexpected trailing prompt bytes'); }
    location() { return {controller:this.u8(), location:this.u8(), sequence:this.u32(), position:this.u32()}; }
    card(full) { const code = this.u32(); return full ? {code, ...this.location()} : {code,controller:this.u8(),location:this.u8(),sequence:this.u32()}; }
    list(read) { const count = this.count(); return Array.from({length:count}, (_, index) => ({...read(), index})); }
  }
  function integer(value, bytes = 4) {
    let n = BigInt.asUintN(bytes * 8, BigInt(value)); const out = [];
    for (let i = 0; i < bytes; i++) { out.push(Number(n & 255n)); n >>= 8n; }
    return out;
  }
  function selected(indices) {
    if (indices.length > MAX_ITEMS || new Set(indices).size !== indices.length || indices.some(i => !Number.isInteger(i) || i < 0 || i >= MAX_ITEMS)) fail('Invalid selection');
    // Explicit uint32-list format: mode, count, indices. Mandatory sum cards are not included.
    return [...integer(0), ...integer(indices.length), ...indices.flatMap(i => integer(i))];
  }
  function choices(value) {
    const low = value & 65535, high = (value | 0) >> 16;
    if (low <= 0 || high < 0) fail('Unsupported non-positive sum operand');
    return high > 0 && high !== low ? [low, high] : [low];
  }
  function solveSum(mode, target, min, max, mandatory, optional) {
    let work = 0;
    const tick = () => { if (++work > MAX_SEARCH) fail('Selection search budget exceeded'); };
    if (!Number.isInteger(target) || target <= 0 || min > max || optional.length > 256) fail('Invalid sum constraint');
    if (mode === 0) {
      let sums = new Set([0]);
      for (const card of mandatory) {
        const next = new Set();
        for (const sum of sums) for (const value of choices(card.value)) { tick(); if (sum + value <= target) next.add(sum + value); }
        sums = next;
      }
      let states = new Map([...sums].map(sum => [`0:${sum}`, {sum, indices:[]} ]));
      for (let i = 0; i <= optional.length; i++) {
        for (const state of states.values()) {
          if (state.sum === target && state.indices.length >= min && state.indices.length <= max && mandatory.length + state.indices.length > 0) return state.indices;
        }
        if (i === optional.length) break;
        const next = new Map(states);
        for (const state of states.values()) {
          if (state.indices.length >= max) continue;
          for (const value of choices(optional[i].value)) {
            tick(); const sum = state.sum + value;
            if (sum <= target) next.set(`${state.indices.length + 1}:${sum}`, {sum, indices: [...state.indices,i]});
          }
        }
        states = next;
      }
    } else if (mode === 1) {
      function aggregate(cards) {
        const values = cards.map(c => choices(c.value));
        return {sum:values.reduce((s,a) => s + Math.min(...a),0), max:values.reduce((s,a) => s + Math.max(...a),0), least:values.length ? Math.min(...values.flat()) : Infinity};
      }
      const start = aggregate(mandatory);
      const stack = [{index:0, indices:[], ...start}];
      while (stack.length) {
        tick(); const state = stack.pop();
        // Matches SelectSum's greater-or-equal/minimal-contribution validation.
        if (state.max >= target && state.sum - state.least < target && mandatory.length + state.indices.length > 0) return state.indices;
        if (state.index >= optional.length || state.sum - state.least >= target) continue;
        const next = state.index + 1, values = choices(optional[state.index].value);
        stack.push({...state, index:next});
        stack.push({index:next, indices:[...state.indices,state.index], sum:state.sum + Math.min(...values),
                    max:state.max + Math.max(...values), least:Math.min(state.least,...values)});
      }
    } else fail('Unknown sum mode');
    fail('No legal sum selection found');
  }

  function create(metadata = {}) {
    const used = new Set(); let decisions = 0, lastChainPlayer = null;
    function score(card) {
      // Never infer hidden opponent cards from unfiltered core selection codes.
      if (card.controller === 0 && (card.location === 1 || card.location === 2 || card.location === 64 ||
          (card.position & 10) || (card.position === undefined && (card.location & 12)))) return 0;
      const info = metadata[String(card.code)]; return info ? Math.max(0, info.attack || 0) : 0;
    }
    function chooseAction(cards, command, usedPrefix, plainIndex = false) {
      const candidates = cards.filter(c => !used.has(`${usedPrefix}:${c.code}:${c.location}:${c.sequence}:${c.description || ''}`));
      candidates.sort((a,b) => score(b)-score(a) || a.index-b.index);
      if (!candidates.length) return null;
      const card = candidates[0]; used.add(`${usedPrefix}:${card.code}:${card.location}:${card.sequence}:${card.description || ''}`);
      return integer(plainIndex ? card.index : card.index * 65536 + command);
    }
    return {
      observe(message, bytes = []) {
        if (message === 40) { used.clear(); decisions = 0; lastChainPlayer = null; }
        if (message === 74) lastChainPlayer = null;
        if (message === 70) { const r = new Reader(bytes); r.card(true); lastChainPlayer = r.u8(); }
      },
      forHuman(message, bytes) {
        const output = bytes.slice(), r = new Reader(output);
        const hide = offset => { for(let i=0;i<4;i++) output[offset+i]=0; };
        if (message === 90 || message === 33 || message === 39) {
          const player = r.u8(), count = r.count();
          for(let i=0;i<count;i++) { const offset=r.at; r.u32(); const pos=message===90?r.u32():0; if(player===1&&!(pos&5)) hide(offset); }
          r.end();
        } else if(message===50) {
          r.u32(); r.location(); const location=r.location();
          if(location.controller===1 && !(location.location&(16|128)) && ((location.location&(1|2)) || (location.position&10))) hide(0);
        } else if(message===54 || message===62) {
          r.u32(); const location=r.location();
          if(message===54 || (location.controller===1&&(location.position&10))) hide(0);
        } else if(message===31) {
          const player=r.u8(), count=r.count();
          if(count>0) { r.u32(); r.u8(); const location=r.u8(); if(player===1&&(location===1||location===64)) return null; }
        } else if([15,20,23,26].includes(message)) {
          const player=r.u8();
          const hideCard=(full,extra)=>{
            const offset=r.at, entry=r.card(full);
            if(entry.controller!==player) hide(offset);
            if(extra===1) r.u8(); else if(extra===4) r.u32();
            return entry;
          };
          if(message===23) {
            r.u8();r.u32();r.count();r.count();r.list(()=>hideCard(true,4));r.list(()=>hideCard(true,4));
          } else {
            r.u8(); if(message===26) r.u8(); r.count();r.count();
            r.list(()=>hideCard(message!==20,message===20?1:0));
            if(message===26) r.list(()=>hideCard(true,0));
          }
          r.end();
        }
        return output;
      },
      decide(message, bytes, declarable = [], ownPositions = {}) {
        if (!PROMPTS.has(message)) fail(`Unknown AI prompt ${message}`);
        const r = new Reader(bytes), player = r.u8();
        if (player !== 0 && player !== 1) fail('Invalid selecting player');
        if (player === 0) return {handled:false};
        if (++decisions > 2048) fail('AI turn decision budget exceeded');
        let response;
        if (message === 10 || message === 11) {
          const effect = () => ({...r.card(false), description:r.u64().toString(), flag:r.u8()});
          if (message === 11) {
            const summon = r.list(() => r.card(false)), special = r.list(() => r.card(false));
            const reposition = r.list(() => ({code:r.u32(),controller:r.u8(),location:r.u8(),sequence:r.u8()}));
            const setMonster = r.list(() => r.card(false)), setSpell = r.list(() => r.card(false)), activate = r.list(effect);
            const battle = r.u8(), end = r.u8(); r.u8(); r.end();
            response = chooseAction(special,1,'special') || chooseAction(summon,0,'normal') || chooseAction(activate,5,'activate') ||
              chooseAction(setMonster,3,'setmonster') || chooseAction(setSpell,4,'setspell') ||
              chooseAction(reposition.filter(c => ((ownPositions[String(c.sequence)] || 0)&14) &&
                score(c)>=(metadata[String(c.code)]?.defense || 0)),2,'reposition');
            if (!response) response = battle ? integer(6) : end ? integer(7) : fail('No legal idle decision');
          } else {
            const activate = r.list(effect);
            const attacks = r.list(() => ({code:r.u32(),controller:r.u8(),location:r.u8(),sequence:r.u8(),direct:r.u8()}));
            const main2 = r.u8(), end = r.u8(); r.end();
            // Attack availability already accounts for remaining attacks and engine restrictions.
            attacks.sort((a,b) => score(b)-score(a) || a.index-b.index);
            response = attacks.length ? integer(attacks[0].index * 65536 + 1) : chooseAction(activate,0,'battle-effect');
            if (!response) response = main2 ? integer(2) : end ? integer(3) : fail('No legal battle decision');
          }
        } else if (message === 12) {
          r.u32(); r.location(); r.u64(); r.end(); response = integer(1);
        } else if (message === 13) {
          r.u64(); r.end(); response = integer(1);
        } else if (message === 14 || message === 143) {
          const count = r.u8(); for (let i=0;i<count;i++) r.u64(); r.end();
          if (!count) fail('Empty option list'); response = integer(0);
        } else if (message === 15) {
          r.u8(); const min = r.count(), max = r.count(), cards = r.list(() => r.card(true)); r.end();
          if (min > max || min > cards.length) fail('Impossible card count');
          response = selected(cards.slice(0,min).map(c => c.index));
        } else if (message === 26) {
          const finishable = r.u8(), cancelable = r.u8(); const min = r.count(), max = r.count();
          const select = r.list(() => r.card(true)), unselect = r.list(() => r.card(true)); r.end();
          if (min > max) fail('Invalid unselect bounds');
          response = finishable || (cancelable && !select.length) ? integer(-1) :
            select.length ? [...integer(1),...integer(0)] : unselect.length ? [...integer(1),...integer(select.length)] : fail('Empty forced selection');
        } else if (message === 16) {
          r.u8(); const forced = r.u8(); r.u32(); r.u32();
          const cards = r.list(() => ({...r.card(true),description:r.u64().toString(),flag:r.u8()})); r.end();
          if (forced && !cards.length) fail('Forced empty chain');
          response = forced ? integer(0) : lastChainPlayer===1 ? integer(-1) : (chooseAction(cards,0,'chain',true) || integer(-1));
        } else if (message === 18 || message === 24) {
          const count = Math.max(1,r.u8()), unavailable = r.u32(); r.end(); const available = (~unavailable) >>> 0;
          const places = [];
          for (let bit=0;bit<32;bit++) {
            const offset = bit%16;
            if (offset === 7 || !(available & 2 ** bit)) continue;
            places.push([bit<16 ? player : 1-player,offset<8 ? 4 : 8,offset<8 ? offset : offset-8]);
          }
          if (places.length < count) fail('Not enough legal zones'); response = places.slice(0,count).flat();
        } else if (message === 19) {
          r.u32(); const mask = r.u8(); r.end(); const position = [1,4,8,2].find(p => (mask&p)!==0);
          if (!position || (mask & ~15)) fail('Invalid position mask'); response = integer(position);
        } else if (message === 20) {
          const cancelable = r.u8(), min = r.count(), max = r.count();
          const cards = r.list(() => ({...r.card(false),value:r.u8()})); r.end();
          cards.sort((a,b) => b.value-a.value || score(a)-score(b) || a.index-b.index);
          const ids = []; let sum = 0;
          for (const card of cards) { if (sum>=min || ids.length>=max) break; ids.push(card.index); sum+=card.value; }
          if (sum < min) response = cancelable ? integer(-1) : fail('No legal tribute'); else response = selected(ids);
        } else if (message === 22) {
          r.u16(); let remaining = r.u16();
          const cards = r.list(() => ({code:r.u32(),controller:r.u8(),location:r.u8(),sequence:r.u8(),value:r.u16()})); r.end();
          response = cards.flatMap(card => { const take = Math.min(card.value, remaining,32767); remaining-=take; return integer(take,2); });
          if (remaining) fail('Not enough counters');
        } else if (message === 23) {
          const mode = r.u8(), target = r.u32(), min = r.count(), max = r.count();
          const read = () => ({...r.card(true),value:r.u32()});
          const mandatory = r.list(read), optional = r.list(read); r.end();
          response = selected(solveSum(mode,target,min,max,mandatory,optional));
        } else if (message === 21 || message === 25) {
          r.list(() => ({code:r.u32(),controller:r.u8(),location:r.u32(),sequence:r.u32()})); r.end(); response = integer(-1);
        } else if (message === 132) {
          r.end(); response = integer(2);
        } else if (message === 140 || message === 141) {
          let count = r.u8(); const mask = message === 140 ? r.u64() : BigInt(r.u32()); r.end(); let chosen = 0n;
          for (let bit=0;bit<(message === 140 ? 64 : 32)&&count;bit++) { const flag=1n<<BigInt(bit); if(mask&flag) {chosen|=flag; count--;} }
          if(count) fail('Invalid announcement count'); response = integer(chosen,message === 140 ? 8 : 4);
        } else if (message === 142) {
          const count=r.u8(); for(let i=0;i<count;i++) r.u64(); r.end();
          if (!Array.isArray(declarable) || !declarable.length || !Number.isInteger(declarable[0]) || declarable[0]<=0 || declarable[0]>0xffffffff) fail('No validated declarable card');
          response=integer(declarable[0]);
        }
        if (!response || !response.length || response.length>65536) fail('Invalid encoded AI response');
        return {handled:true,response};
      }
    };
  }
  const api = {create, promptTypes:[...PROMPTS], solveSum};
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.OfflineDuelAI = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
