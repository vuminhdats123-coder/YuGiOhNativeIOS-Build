/* SPDX-License-Identifier: AGPL-3.0-or-later
 * OCG API 11 prompt decisions. Protocol: pinned ocgcore/playerop.cpp.
 * This module is shared verbatim by JavaScriptCore on iOS and the Node tests.
 */
(function (root) {
  'use strict';
  const PROMPTS = new Set([10,11,12,13,14,15,16,18,19,20,21,22,23,24,25,26,132,140,141,142,143]);
  const MAX_ITEMS = 4096, MAX_SEARCH = 200000;
  // Profiles below follow the bundled, pinned official c<ID>.lua scripts. Unknown optional
  // effects are passed in live-board mode; this is a bounded tactical policy, not an effect interpreter.
  const CARD = {DARK_HOLE:53129443,RAIGEKI:12580477,REBORN:83764718,MST:5318639,
    JUDGMENT:41420027,JAMMER:77414722,CHALICE:25789292,RUSH:70046172,MIRROR:44095762,
    NEGATE_ATTACK:14315573,POLY:24094653,RITUAL:55761792,POT:55144522,CHARITY:79571449,
    UPSTART:70368879,FISSURE:66788016,SMASHING:97169186,BOOK:14087893,
    AQUAMIRROR:46159582,PHOENIX:2857636,COWBOY:12014404,FIRE:46918794,
    BOTTOMLESS:29401950,TORRENTIAL:53582587,COMPULSORY:94192409,DIMENSIONAL:70342110,
    DUST_TORNADO:60082869,SUPER_POLY:48130390,SUMMON_STRIKE:40605147,SUMMON_WARNING:84749824,
    VEILER:97268402,ASH:14558127,RAIGEKI_BREAK:4178474,DUALITY:98645731,ONE_FOR_ONE:2295440,
    MELODY:48800175,FOOLISH:81439173,FOOLISH_GOODS:35726888,REINCARNATION:74848038,
    PREMATURE:70828912,CALL_HAUNTED:97077563,TRADE_IN:38120068,SILVER_CRY:87025064,
    ROTA:32807846,JUNK_SYNCHRON:63977008,JUNK_WARRIOR:60800381,CYBER_DRAGON:70095154,
    BLUE_EYES_ALT:38517737,CYBER_NOVA:58069384,CYBER_INFINITY:10443957,SCRAP_WARRIOR:42711820,
    JUNK_GARDNA:37993923,JUNK_DESTROYER:74860293,JUNK_BERSERKER:59771339,DECODE:1861629,D_D_WARRIOR:7572887,
    EFFECT_VEILER:97268402,CYBER_CORE:23893227,PREMATURE_BURIAL:70828912,RAIGEKI_BOTTLE:11741041};
  const PROFILE = Object.freeze({
    removal:new Set([CARD.RAIGEKI,CARD.MST,CARD.FISSURE,CARD.SMASHING,CARD.BOTTOMLESS,CARD.TORRENTIAL,CARD.COMPULSORY,CARD.DIMENSIONAL,CARD.DUST_TORNADO,CARD.RAIGEKI_BREAK]),
    negate:new Set([CARD.JUDGMENT,CARD.JAMMER,CARD.SUMMON_STRIKE,CARD.SUMMON_WARNING,CARD.VEILER,CARD.ASH]),
    revive:new Set([CARD.REBORN,CARD.REINCARNATION,CARD.PREMATURE,CARD.CALL_HAUNTED,CARD.SILVER_CRY]),
    draw:new Set([CARD.POT,CARD.CHARITY,CARD.UPSTART,CARD.TRADE_IN,CARD.DUALITY]),
    search:new Set([CARD.ROTA,CARD.MELODY,CARD.FOOLISH,CARD.FOOLISH_GOODS,CARD.ONE_FOR_ONE]),
    battle:new Set([CARD.RUSH,CARD.CHALICE,CARD.MIRROR,CARD.NEGATE_ATTACK,CARD.BOOK]),
    extra:new Set([CARD.PHOENIX,CARD.COWBOY,CARD.DECODE,CARD.CYBER_NOVA,CARD.CYBER_INFINITY,CARD.SCRAP_WARRIOR,CARD.JUNK_GARDNA,CARD.JUNK_DESTROYER,CARD.JUNK_BERSERKER,CARD.JUNK_WARRIOR])
  });
  function safeBoard(input) {
    if (!input || !input.self || !input.opponent || !Array.isArray(input.self.cards) || !Array.isArray(input.opponent.cards)) return null;
    const number=(v,fallback=0)=>Number.isFinite(v)?Math.max(0,Math.min(100000000,v)):fallback;
    const record=(c,location)=>{
      if(!c || c.location!==location || !Number.isInteger(c.sequence)) return null;
      const base={code:Number.isInteger(c.code)&&c.code>0?c.code:0,location,sequence:c.sequence,position:Number.isInteger(c.position)?c.position:0};
      // Private hand/Extra belong to the AI; public Grave is safe for both players. No Main Deck/banished arrays are accepted.
      if(location===2 || location===64 || location===16 || (base.position&5))
        return {...base,type:number(c.type),attack:number(c.attack),defense:number(c.defense),level:number(c.level),rank:number(c.rank),link:number(c.link),disabled:c.disabled===true};
      return {...base,code:0};
    };
    const side=s=>({lp:number(s.lp,8000),handCount:number(s.handCount),deckCount:number(s.deckCount),extraCount:number(s.extraCount),
      hand:Array.isArray(s.hand)?s.hand.slice(0,64).map(c=>record(c,2)).filter(Boolean):[],
      extra:Array.isArray(s.extra)?s.extra.slice(0,64).map(c=>record(c,64)).filter(Boolean):[],
      grave:Array.isArray(s.grave)?s.grave.slice(0,64).map(c=>record(c,16)).filter(Boolean):[],
      cards:Array.isArray(s.cards)?s.cards.slice(0,32).filter(c=>c && [4,8].includes(c.location) && Number.isInteger(c.sequence)).map(c=>{
        const base={code:0,location:c.location,sequence:c.sequence,position:Number.isInteger(c.position)?c.position:0};
        // Neither hidden identities nor extra caller-provided fields can enter tactical state.
        if (!(base.position&5) || !Number.isInteger(c.code) || c.code<=0) return base;
        return {...base,code:c.code,type:number(c.type),attack:number(c.attack),defense:number(c.defense),
          level:number(c.level),rank:number(c.rank),link:number(c.link),disabled:c.disabled===true};
      }):[]});
    return {self:side(input.self),opponent:side(input.opponent)};
  }
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
      // Avoid exploring every combination of small contributions before a
      // sufficient later card. Keep wire indices independent of search order.
      const ordered = optional.map((card,index) => ({index,values:choices(card.value)}));
      ordered.sort((a,b) => Math.max(...b.values)-Math.max(...a.values) || a.index-b.index);
      const stack = [{index:0, indices:[], ...start}];
      while (stack.length) {
        tick(); const state = stack.pop();
        // Matches SelectSum's greater-or-equal/minimal-contribution validation.
        if (state.max >= target && state.sum - state.least < target && mandatory.length + state.indices.length > 0) return state.indices;
        if (state.index >= optional.length || state.sum - state.least >= target) continue;
        const next = state.index + 1, entry = ordered[state.index], values = entry.values;
        stack.push({...state, index:next});
        stack.push({index:next, indices:[...state.indices,entry.index], sum:state.sum + Math.min(...values),
                    max:state.max + Math.max(...values), least:Math.min(state.least,...values)});
      }
    } else fail('Unknown sum mode');
    fail('No legal sum selection found');
  }

  function create(metadata = {}, selfPlayer = 1) {
    if (selfPlayer !== 0 && selfPlayer !== 1) fail('Invalid AI player');
    const used = new Set(); let decisions = 0, lastChainPlayer = null, selectionHint = null, attackingCard = null;
    let board=null, lastChain=null, pendingSummon=null, combat=null, damageWindow=false, canBattle=false, intent=null;
    const field = card => board && (card.controller===selfPlayer?board.self:board.opponent).cards.find(c=>c.location===card.location&&c.sequence===card.sequence);
    function known(card) {
      if (card.publicEvent===true) return true;
      if (card.location===16 || (card.location&128)) return true;
      if (card.controller!==selfPlayer && board && (card.location&12)) {
        const current=field(card);
        return !!(current && current.code && (current.position&5));
      }
      return !(card.controller !== selfPlayer && (card.location === 1 || card.location === 2 || card.location === 64 ||
        (card.position & 10) || (card.position === undefined && (card.location & 12))));
    }
    function info(card) {
      if (!known(card)) return null;
      const current=field(card);
      return current && current.code ? current : metadata[String(card.code)] || null;
    }
    const codeOf=card=>known(card)?(field(card)?.code || card.code):0;
    function score(card) {
      // Never infer hidden opponent cards from unfiltered core selection codes.
      const data=info(card); return data?Math.max(0,data.attack||0):0;
    }
    const sideCards=(self,location)=>board?(self?board.self:board.opponent).cards.filter(c=>c.location===location)
      .map(c=>({...c,controller:self?selfPlayer:1-selfPlayer})):[];
    const privateCards=(self,zone)=>board?(self?board.self:board.opponent)[zone].map(c=>({...c,controller:self?selfPlayer:1-selfPlayer})):[];
    const monsters=self=>sideCards(self,4), spells=self=>sideCards(self,8);
    const hand=self=>privateCards(self,'hand'), extra=self=>privateCards(self,'extra'), grave=self=>privateCards(self,'grave');
    const ownHand=()=>hand(true), ownGrave=()=>grave(true), ownExtra=()=>extra(true);
    const profile=(card,set)=>set.has(codeOf(card));
    const hasCode=(cards,code)=>cards.some(card=>codeOf(card)===code);
    const isMonster=(card)=>{const data=info(card);return !!(data&&(data.type&1));};
    const isLevel8=(card)=>{const data=info(card);return !!(data&&data.level>=8);};
    const isDragonNormal=(card)=>{const data=info(card);return !!(data&&data.type&1&&data.level>0&&(data.type&0x10));};
    const isLevel2=(card)=>{const data=info(card);return !!(data&&data.level>0&&data.level<=2);};
    function value(card) {
      const data=info(card);
      if (!data) return card.location===8?650:900;
      if ((data.type&1) || card.location===4 || data.attack || data.defense)
        return 250+Math.max(0,data.attack||0)*0.7+Math.max(0,data.defense||0)*0.3+((data.type&32)&&!data.disabled?180:0)+(data.link||0)*80;
      const code=codeOf(card);
      if (PROFILE.negate.has(code)||PROFILE.revive.has(code)||PROFILE.draw.has(code)) return 1400;
      if (PROFILE.removal.has(code)||PROFILE.battle.has(code)||PROFILE.search.has(code)) return 1150;
      if (PROFILE.extra.has(code)) return 1800;
      return 750;
    }
    const total=cards=>cards.reduce((n,c)=>n+value(c),0);
    const strongest=self=>Math.max(0,...monsters(self).map(c=>score(c)));
    const same=(a,b)=>a&&b&&a.controller===b.controller&&a.location===b.location&&a.sequence===b.sequence;
    const power=c=>{ const data=info(c); return data?Math.max(0,(c.position&12)?data.defense||0:data.attack||0):null; };
    function battlePair() {
      if (!board || !combat) return null;
      const attacker=field(combat.attacker), defender=combat.defender.location?field(combat.defender):null;
      if (!attacker) return null;
      return {attacker:{...attacker,controller:combat.attacker.controller},
        defender:defender?{...defender,controller:combat.defender.controller}:null};
    }
    function incomingDanger(extraAttack=0) {
      const pair=battlePair();
      if (!pair || pair.attacker.controller===selfPlayer) return 0;
      const atk=score(pair.attacker)+extraAttack, defense=pair.defender?power(pair.defender):0;
      if (defense===null) return 0;
      const damage=pair.defender&&(pair.defender.position&12)?0:Math.max(0,atk-defense);
      if (damage>=board.self.lp && damage>0) return 10000;
      return damage*0.5+(pair.defender&&atk>defense?value(pair.defender):0);
    }
    function boostPlan(amount,negatesOwn=false) {
      if (!damageWindow) return {utility:0};
      const pair=battlePair();
      if (!pair) return {utility:0};
      const own=pair.attacker.controller===selfPlayer?pair.attacker:pair.defender;
      if (!own || own.controller!==selfPlayer || !(own.position&1)) return {utility:0};
      const enemy=pair.attacker.controller===selfPlayer?pair.defender:pair.attacker;
      const opposing=enemy?power(enemy):0;
      if (opposing===null) return {utility:0};
      const attack=score(own), enemyAttacks=pair.attacker.controller!==selfPlayer;
      let benefit=attack<=opposing&&attack+amount>opposing?value(own)+(enemy?value(enemy):0):0;
      if (!enemyAttacks && (!enemy || (enemy.position&1)) && attack-opposing<board.opponent.lp && attack+amount-opposing>=board.opponent.lp) benefit=10000;
      if (negatesOwn && (info(own)?.type&32)) benefit-=600;
      return {utility:Math.max(0,benefit-400),target:own};
    }
    function chainThreat() {
      if (!lastChain || lastChainPlayer===selfPlayer) return 0;
      const own=total(monsters(true)), enemy=total(monsters(false));
      switch(lastChain.code) {
      case CARD.DARK_HOLE:return Math.max(0,own-enemy);
      case CARD.RAIGEKI:return own;
      case CARD.MIRROR:return total(monsters(true).filter(c=>c.position&1));
      case CARD.MST:return spells(true).length?650:0;
      case CARD.POT:return 1650;
      case CARD.CHARITY:return 1450;
      case CARD.UPSTART:return 350; // One draw also heals us; normally not worth a discard/counter trap.
      case CARD.REBORN:return 1800;
      case CARD.POLY:case CARD.RITUAL:case CARD.AQUAMIRROR:return 1900;
      case CARD.FIRE:return board.self.lp<=1000?10000:500;
      case CARD.RUSH:return incomingDanger(700);
      case CARD.CHALICE:return incomingDanger(400)+(lastChain.location===4?600:0);
      case CARD.FISSURE:case CARD.SMASHING:return monsters(true).length?Math.max(...monsters(true).map(value)):0;
      default:return lastChain.location===4?value(lastChain)*0.6:250;
      }
    }
    function bestGrave(predicate) {
      const candidates=ownGrave().filter(c=>isMonster(c)&&(!predicate||predicate(c)));
      candidates.sort((a,b)=>value(b)-value(a)||a.sequence-b.sequence);
      return candidates[0]||null;
    }
    function bestGraveAny(predicate) {
      const candidates=ownGrave().filter(predicate);
      candidates.sort((a,b)=>value(b)-value(a)||a.sequence-b.sequence);
      return candidates[0]||null;
    }
    function comboPlan(card) {
      const code=codeOf(card), target=bestGrave();
      if (code===CARD.FOOLISH) {
        const payoff=hasCode(ownHand(),CARD.REBORN)||hasCode(ownHand(),CARD.SILVER_CRY)||hasCode(ownHand(),CARD.REINCARNATION);
        return {utility:board.self.deckCount>0&&payoff?2600:0};
      }
      if (code===CARD.REBORN||code===CARD.REINCARNATION||code===CARD.PREMATURE||code===CARD.CALL_HAUNTED) {
        return {utility:target?Math.max(0,1900+value(target)-(monsters(true).length>=5?850:0)):0,target};
      }
      if (code===CARD.TRADE_IN) {
        const discard=ownHand().filter(c=>c!==card&&isLevel8(c));
        return {utility:discard.length&&board.self.deckCount>=2?(1600+Math.min(2,discard.length)*280):0,target:discard[0]};
      }
      if (code===CARD.SILVER_CRY) {
        const dragon=bestGrave(isDragonNormal);
        return {utility:dragon?2200+value(dragon):0,target:dragon};
      }
      if (code===CARD.ROTA) {
        const junk=hasCode(ownHand(),CARD.JUNK_SYNCHRON), payoff=hasCode(ownExtra(),CARD.JUNK_WARRIOR)||hasCode(ownExtra(),CARD.JUNK_DESTROYER);
        return {utility:!junk&&payoff&&bestGrave(isLevel2)?2400:(!junk?600:0)};
      }
      if (code===CARD.MELODY) {
        const dragon=ownHand().filter(c=>isMonster(c)&&((info(c)?.type||0)&0x200));
        return {utility:dragon.length&&board.self.deckCount>=2?1300:0,target:dragon[0]};
      }
      if (code===CARD.FOOLISH_GOODS) {
        return {utility:hasCode(ownHand(),CARD.SILVER_CRY)||hasCode(ownHand(),CARD.PREMATURE)?1450:0};
      }
      if (code===CARD.ONE_FOR_ONE) {
        return {utility:hasCode(ownHand(),CARD.JUNK_SYNCHRON)&&bestGrave(isLevel2)?1750:0};
      }
      return {utility:0};
    }
    function extraComboPlan(card) {
      const code=codeOf(card), tuner=hasCode(ownHand(),CARD.JUNK_SYNCHRON)||
        (board&&board.self.cards.some(c=>c.location===4&&c.code===CARD.JUNK_SYNCHRON)),
        level2=bestGraveAny(c=>{const data=info(c)||c;const level=Number(data.level||c.level||0);return level>0&&level<=2;});
      if (code===CARD.JUNK_WARRIOR) return {utility:tuner&&level2?4200:0,target:level2};
      if (code===CARD.SCRAP_WARRIOR||code===CARD.JUNK_GARDNA||code===CARD.JUNK_DESTROYER||code===CARD.JUNK_BERSERKER)
        return {utility:ownHand().some(isMonster)&&monsters(true).length<5?1500:0};
      if (code===CARD.CYBER_NOVA||code===CARD.CYBER_INFINITY)
        return {utility:monsters(true).filter(c=>codeOf(c)===CARD.CYBER_DRAGON).length>=2?3600:0};
      if (code===CARD.PHOENIX) { const plan=effectPlan(card); return plan.utility>0?{...plan,utility:Math.max(plan.utility,3600)}:plan; }
      if (code===CARD.COWBOY) return effectPlan(card);
      if (code===CARD.DECODE) return {utility:monsters(true).length>=2?4200:0};
      return {utility:0};
    }
    function effectPlan(card) {
      if (!board || !known(card)) return {utility:0};
      const code=codeOf(card), own=monsters(true), enemy=monsters(false);
      switch(code) {
      case CARD.DARK_HOLE: {
        const gain=total(enemy)-total(own);
        return {utility:gain>350?10000+gain:incomingDanger()>=10000?12000:0};
      }
      case CARD.RAIGEKI:return {utility:enemy.length?9000+total(enemy):0};
      case CARD.REBORN:case CARD.REINCARNATION:case CARD.PREMATURE:case CARD.CALL_HAUNTED:case CARD.FOOLISH:
      case CARD.TRADE_IN:case CARD.SILVER_CRY:case CARD.ROTA:case CARD.MELODY:case CARD.FOOLISH_GOODS:case CARD.ONE_FOR_ONE:
        return comboPlan(card);
      case CARD.JUNK_SYNCHRON:
        return {utility:bestGrave(isLevel2)&&ownExtra().some(c=>codeOf(c)===CARD.JUNK_WARRIOR)?3300:0,target:bestGrave(isLevel2)};
      case CARD.MST: {
        const targets=spells(false).filter(c=>!(same(c,lastChain)&&!(info(c)?.type&(0x20000|0x40000|0x80000))));
        targets.sort((a,b)=>value(b)-value(a)||a.sequence-b.sequence);
        return {utility:targets.length?900+value(targets[0]):0,target:targets[0]};
      }
      case CARD.JAMMER:return {utility:board.self.handCount?Math.max(0,chainThreat()-(board.self.handCount<=1?1700:1150)):0};
      case CARD.JUDGMENT: {
        let threat=chainThreat();
        if (!lastChain && pendingSummon && pendingSummon.controller!==selfPlayer && known(pendingSummon)) {
          const attack=score(pendingSummon);
          threat=attack>strongest(true)?value(pendingSummon)*0.9:0;
          if (attack-strongest(true)>=board.self.lp) threat=10000;
        }
        return {utility:Math.max(0,threat-Math.max(900,board.self.lp*0.175+500))};
      }
      case CARD.RUSH:return boostPlan(700);
      case CARD.CHALICE: {
        if (lastChain && lastChainPlayer!==selfPlayer && lastChain.location===4 && !info(lastChain)?.disabled)
          return {utility:Math.max(0,chainThreat()-300),target:lastChain};
        return boostPlan(400,true);
      }
      case CARD.MIRROR:return {utility:incomingDanger()>500?total(enemy.filter(c=>c.position&1)):enemy.filter(c=>c.position&1).length>=2?total(enemy):0};
      case CARD.NEGATE_ATTACK:return {utility:Math.max(0,incomingDanger()-500)};
      case CARD.FISSURE:case CARD.SMASHING:return {utility:enemy.some(c=>c.position&5)?2500:0};
      case CARD.BOOK: {
        const targets=enemy.filter(c=>(c.position&5)&&!(info(c)?.type&0x4000000));
        targets.sort((a,b)=>score(b)-score(a)||a.sequence-b.sequence);
        return {utility:targets.length&&(incomingDanger()>500||score(targets[0])>strongest(true))?1700:0,target:targets[0]};
      }
      case CARD.POT:return {utility:board.self.deckCount>=2?4200:0};
      case CARD.CHARITY:return {utility:board.self.deckCount>=3?2600:0};
      case CARD.UPSTART:return {utility:board.self.deckCount>=1&&board.self.handCount<5?800:0};
      case CARD.DUALITY:return {utility:board.self.deckCount>=3&&board.self.handCount<6?1100:0};
      case CARD.SUMMON_STRIKE:case CARD.SUMMON_WARNING:case CARD.VEILER:case CARD.ASH:
        return {utility:Math.max(0,chainThreat()- (board.self.handCount<=1?1100:600))};
      case CARD.BOTTOMLESS:case CARD.TORRENTIAL:case CARD.COMPULSORY:case CARD.DIMENSIONAL:
        return {utility:enemy.length?Math.max(...enemy.map(value)):0};
      case CARD.DUST_TORNADO:return {utility:spells(false).length?1050+Math.max(...spells(false).map(value)):0};
      case CARD.RAIGEKI_BREAK:return {utility:enemy.length&&board.self.handCount>1?900+Math.max(...enemy.map(value)):0};
      case CARD.FOOLISH_GOODS:return comboPlan(card);
      case CARD.POLY:case CARD.RITUAL:return {utility:own.length<5?2300:0};
      case CARD.AQUAMIRROR:return {utility:card.location===16?1300:own.length<5?2300:0};
      case CARD.PHOENIX: {
        const targets=spells(false).filter(c=>!(same(c,lastChain)&&!(info(c)?.type&(0x20000|0x40000|0x80000))));
        targets.sort((a,b)=>value(b)-value(a)||a.sequence-b.sequence);
        // The discard buys removal of opposing backrow before our new Link monster can attack.
        return {utility:targets.length&&board.self.handCount?Math.max(0,value(targets[0])+600-(board.self.handCount<=1?1000:650)):0,target:targets[0]};
      }
      case CARD.COWBOY: {
        const current=field(card), defense=(current?.position||card.position||0)&12;
        if (defense) return {utility:board.opponent.lp<=800?12000:1250};
        // Its attack-position operation is a later battle-start +1000/-500, not the 800 burn.
        return {utility:canBattle&&enemy.some(c=>power(c)!==null&&score(card)<=power(c)&&score(card)+1500>power(c))?2200:0};
      }
      case CARD.PHOENIX: {
        const targets=spells(false).filter(c=>!(same(c,lastChain)&&!(info(c)?.type&(0x20000|0x40000|0x80000))));
        targets.sort((a,b)=>value(b)-value(a)||a.sequence-b.sequence);
        return {utility:targets.length&&board.self.handCount?Math.max(0,value(targets[0])+600-(board.self.handCount<=1?1000:650)):0,target:targets[0]};
      }
      case CARD.FIRE:return {utility:board.self.lp<=500||board.self.lp<=1000&&board.opponent.lp>1000?0:board.opponent.lp<=1000?12000:1400};
      default: {
        const data=info(card);
        // Placing a known Pendulum monster as a scale is a specific, bounded fallback.
        if (data&&(data.type&0x1000000)&&card.location===2&&spells(true).filter(c=>c.sequence===0||c.sequence===4).length<2)
          return {utility:1200};
        return {utility:0};
      }
      }
    }
    function attackValue(card,allowBoost=false) {
      const attack=score(card), enemy=monsters(false);
      if (card.direct || !enemy.length) return attack>0?attack+(attack>=board.opponent.lp?10000:0):0;
      return Math.max(0,...enemy.map(target=>{
        const defending=power(target);
        if (defending===null) return attack>=(board.self.lp<=1000?2200:1800)?300:0;
        if (attack>defending) return value(target)+500+((target.position&1)?(attack-defending)*0.3:0);
        if (attack===defending && (target.position&1) && value(target)>value(card)+300) return 200;
        return allowBoost&&attack+700>defending?Math.max(0,value(target)-500):0;
      }));
    }
    function wantsDefense(card) {
      const data=info(card)||{};
      if (data.type&0x4000000) return false;
      if (board&&codeOf(card)===CARD.COWBOY&&(!canBattle||board.opponent.lp<=800)) return true;
      const attack=Math.max(0,data.attack||0), defense=Math.max(0,data.defense||0);
      return defense>attack && (!board || attack<strongest(false) || attack<1000);
    }
    const actionKey=(c,prefix)=>`${prefix}:${c.controller}:${known(c)?codeOf(c):'hidden'}:${c.location}:${c.sequence}:${c.description||''}`;
    function tacticalAction(cards,command,prefix,evaluate,plainIndex=false) {
      const available=cards.filter(c=>!used.has(actionKey(c,prefix))).map(card=>({card,plan:evaluate(card)}))
        .filter(c=>c.plan.utility>0).sort((a,b)=>b.plan.utility-a.plan.utility||a.card.index-b.card.index);
      if (!available.length) return null;
      return {utility:available[0].plan.utility,commit:()=>{
        const {card,plan}=available[0]; used.add(actionKey(card,prefix));
        intent=['activate','chain','battle-effect'].includes(prefix)?{code:codeOf(card),target:plan.target}:null;
        return integer(plainIndex?card.index:card.index*65536+command);
      }};
    }
    function rankSelection(cards, hint) {
      const ranked = cards.slice();
      if (board) {
        if ([500,501].includes(hint) && cards.every(c=>c.controller===selfPlayer))
          return ranked.sort((a,b)=>value(a)-value(b)||a.index-b.index);
        if (hint===504) return ranked.sort((a,b)=>value(b)-value(a)||a.index-b.index);
        if (intent?.target && ![500,501,504].includes(hint))
          return ranked.sort((a,b)=>Number(same(b,intent.target))-Number(same(a,intent.target))||value(b)-value(a)||a.index-b.index);
        if ([506,508,509].includes(hint)) return ranked.sort((a,b)=>value(b)-value(a)||a.index-b.index);
        if (hint===502) {
          const removal=c=>c.controller!==selfPlayer?100000+value(c):-value(c);
          return ranked.sort((a,b)=>removal(b)-removal(a)||a.index-b.index);
        }
        if (hint===549 && attackingCard) {
          const attack=score(attackingCard);
          const quality=c=>{const defense=power(c); return defense===null?250:attack>defense?2000+value(c):attack===defense?0:-10000-defense;};
          return ranked.sort((a,b)=>quality(b)-quality(a)||a.index-b.index);
        }
        return ranked;
      }
      if (hint === 501 && cards.every(c => c.controller === selfPlayer && c.location === 2)) {
        ranked.sort((a,b) => score(a)-score(b) || a.index-b.index);
      } else if ([506,508,509].includes(hint)) {
        ranked.sort((a,b) => score(b)-score(a) || a.index-b.index);
      } else if (hint === 502) {
        const value = c => c.controller !== selfPlayer ? 100000+score(c) : -score(c);
        ranked.sort((a,b) => value(b)-value(a) || a.index-b.index);
      } else if (hint === 549 && attackingCard && cards.every(c => c.controller !== selfPlayer && c.location === 4)) {
        const attackerPower = score(attackingCard);
        const target = c => {
          const info = known(c) ? metadata[String(c.code)] : null;
          if (!info) return [1,0]; // Deterministic unknown-target policy, never use its code.
          const power = Math.max(0,(c.position & 4) ? info.defense || 0 : info.attack || 0);
          return [power < attackerPower ? 0 : power === attackerPower ? 2 : 3,power];
        };
        ranked.sort((a,b) => { const x=target(a), y=target(b); return x[0]-y[0] || x[1]-y[1] || a.index-b.index; });
      }
      return ranked;
    }
    function chooseAction(cards, command, usedPrefix, plainIndex = false) {
      const key = c => `${usedPrefix}:${c.controller}:${known(c) ? c.code : 'hidden'}:${c.location}:${c.sequence}:${c.description || ''}`;
      const candidates = cards.filter(c => !used.has(key(c)));
      candidates.sort((a,b) => score(b)-score(a) || a.index-b.index);
      if (!candidates.length) return null;
      const card = candidates[0]; used.add(key(card));
      return integer(plainIndex ? card.index : card.index * 65536 + command);
    }
    return {
      observe(message, bytes = []) {
        // Whitelist public decisions/events. Draw, shuffle, deck-top and private reveal packets
        // cannot become memory, even if an adapter accidentally passes their raw bytes here.
        if (![2,40,41,60,61,62,63,64,65,70,71,72,73,74,75,76,110,113,114].includes(message)) return;
        if (message === 40) {
          used.clear(); decisions = 0; lastChainPlayer = null; selectionHint = null; attackingCard = null;
          lastChain=null; pendingSummon=null; combat=null; damageWindow=false; canBattle=false; intent=null;
        }
        if (message === 2) {
          const r = new Reader(bytes), type = r.u8(), player = r.u8(), value = r.u64(); r.end();
          if (type === 3 && player === selfPlayer) selectionHint = value <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(value) : null;
        }
        if (message===41) { combat=null; damageWindow=false; }
        if (message === 74) {lastChainPlayer=null;lastChain=null;intent=null;}
        if (message === 70) {
          const r = new Reader(bytes), card=r.card(true); lastChainPlayer=r.u8();
          // The activating player can differ from the card's location controller (both-side effects).
          lastChain={...card,publicEvent:true};
        }
        if ([60,62,64].includes(message)) {
          const r=new Reader(bytes), card=r.card(true);r.end();
          pendingSummon=(card.position&5)?{...card,publicEvent:true}:null;
        }
        if ([61,63,65].includes(message)) pendingSummon=null;
        if (message===110) {const r=new Reader(bytes);combat={attacker:r.location(),defender:r.location()};r.end();damageWindow=false;}
        if (message===113) damageWindow=true;
        if (message===114) {damageWindow=false;combat=null;}
      },
      forHuman(message, bytes, hideDeckOrder = false) {
        const output = bytes.slice(), r = new Reader(output);
        const hide = offset => { for(let i=0;i<4;i++) output[offset+i]=0; };
        if (message === 90 || message === 33 || message === 39) {
          const player = r.u8(), count = r.count();
          for(let i=0;i<count;i++) { const offset=r.at; r.u32(); const pos=message===90?r.u32():0; if(player===selfPlayer&&!(pos&5)) hide(offset); }
          r.end();
        } else if(message===50) {
          r.u32(); r.location(); const location=r.location();
          if(location.controller===selfPlayer && !(location.location&(16|128)) && ((location.location&(1|2)) || (location.position&10))) hide(0);
        } else if(message===54 || message===62) {
          r.u32(); const location=r.location();
          if(message===54 || (location.controller===selfPlayer&&(location.position&10))) hide(0);
        } else if(message===31) {
          const player=r.u8(), count=r.count();
          if(count>0) { r.u32(); r.u8(); const location=r.u8(); if(player===selfPlayer&&(location===1||location===64)) return null; }
        } else if([15,20,23,26].includes(message)) {
          const player=r.u8();
          const hideCard=(full,extra)=>{
            const offset=r.at, entry=r.card(full);
            const location=entry.location&~128;
            const publicIdentity=(entry.location&128)||location===16||
              (full&&[4,8,32].includes(location)&&(entry.position&5));
            if(entry.controller!==player&&!publicIdentity) hide(offset);
            // AI deck searches may inspect legal card identities, but not their future draw positions.
            // Human ClientAnalyze still needs original GetCard coordinates, so its default stays unchanged.
            if(hideDeckOrder===true&&entry.location===1)
              for(let i=0;i<4;i++) output[offset+6+i]=0;
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
      decide(message, bytes, declarable = [], ownPositions = {}, liveBoard = null) {
        board=safeBoard(liveBoard);
        if(liveBoard!==null&&liveBoard!==undefined&&!board) fail('Invalid tactical board');
        if (!PROMPTS.has(message)) fail(`Unknown AI prompt ${message}`);
        const r = new Reader(bytes), player = r.u8();
        if (player !== 0 && player !== 1) fail('Invalid selecting player');
        if (player !== selfPlayer) return {handled:false};
        if (++decisions > 2048) fail('AI turn decision budget exceeded');
        const requestedHint = selectionHint;
        if ([15,20,23,26].includes(message)) selectionHint = null;
        let response;
        if (message === 10 || message === 11) {
          const effect = () => ({...r.card(false), description:r.u64().toString(), flag:r.u8()});
          if (message === 11) {
            const summon = r.list(() => r.card(false)), special = r.list(() => r.card(false));
            const reposition = r.list(() => ({code:r.u32(),controller:r.u8(),location:r.u8(),sequence:r.u8()}));
            const setMonster = r.list(() => r.card(false)), setSpell = r.list(() => r.card(false)), activate = r.list(effect);
            const battle = r.u8(), end = r.u8(); r.u8(); r.end();
            canBattle=!!battle;
            if (board) {
              const summonPlan=(card,setting=false)=>{
                const data=info(card)||{}, tributeCount=(data.level||0)>6?2:(data.level||0)>4?1:0;
                const cost=monsters(true).map(value).sort((a,b)=>a-b).slice(0,tributeCount).reduce((a,b)=>a+b,0);
                if (!setting && wantsDefense(card) && setMonster.some(c=>c.code===card.code&&c.sequence===card.sequence)) return {utility:0};
                return {utility:Math.max(0,800+value(card)-(setting?0:cost))};
              };
              const actions=[
                tacticalAction(activate,5,'activate',effectPlan),
                tacticalAction(special,1,'special',c=>{
                  const plan=extraComboPlan(c);
                  if(plan.utility>0) return plan;
                  // Unknown Extra Deck effects are not auto-used merely because the engine lists them.
                  return PROFILE.extra.has(codeOf(c))?{utility:900+value(c)*0.2}:{utility:0};
                }),
                tacticalAction(summon,0,'normal',c=>summonPlan(c)),
                tacticalAction(setMonster,3,'setmonster',c=>wantsDefense(c)?summonPlan(c,true):{utility:0}),
                tacticalAction(setSpell,4,'setspell',c=>({utility:spells(true).length<4&&((info(c)?.type||0)&(4|0x10000))?200+value(c)*0.1:0})),
                tacticalAction(reposition,2,'reposition',c=>{
                  const position=field(c)?.position||ownPositions[String(c.sequence)]||0;
                  return {utility:((position&1)&&wantsDefense(c))||((position&14)&&!wantsDefense(c))?1800:0};
                })].filter(Boolean).sort((a,b)=>b.utility-a.utility);
              response=actions.length?actions[0].commit():battle?integer(6):end?integer(7):fail('No legal idle decision');
            } else {
            response = chooseAction(special,1,'special') || chooseAction(summon,0,'normal') || chooseAction(activate,5,'activate') ||
              chooseAction(setMonster,3,'setmonster') || chooseAction(setSpell,4,'setspell') ||
              chooseAction(reposition.filter(c => ((ownPositions[String(c.sequence)] || 0)&14) &&
                score(c)>=(metadata[String(c.code)]?.defense || 0)),2,'reposition');
            if (!response) response = battle ? integer(6) : end ? integer(7) : fail('No legal idle decision');
            }
          } else {
            const activate = r.list(effect);
            const attacks = r.list(() => ({code:r.u32(),controller:r.u8(),location:r.u8(),sequence:r.u8(),direct:r.u8()}));
            const main2 = r.u8(), end = r.u8(); r.end();
            // Attack availability already accounts for remaining attacks and engine restrictions.
            if (board) {
              const boost=activate.some(c=>codeOf(c)===CARD.RUSH&&!used.has(actionKey(c,'battle-effect'))&&!used.has(actionKey(c,'chain')));
              const possible=attacks.map(card=>({card,utility:attackValue(card,boost)})).filter(c=>c.utility>0)
                .sort((a,b)=>b.utility-a.utility||a.card.index-b.card.index);
              const effect=tacticalAction(activate,0,'battle-effect',effectPlan);
              if (effect && (!possible.length||effect.utility>possible[0].utility)) response=effect.commit();
              else if (possible.length) {attackingCard=possible[0].card;response=integer(attackingCard.index*65536+1);}
            } else {
              attacks.sort((a,b) => score(b)-score(a) || a.index-b.index);
              attackingCard = attacks.length ? attacks[0] : null;
              response = attacks.length ? integer(attacks[0].index * 65536 + 1) : chooseAction(activate,0,'battle-effect');
            }
            if (!response) response = main2 ? integer(2) : end ? integer(3) : fail('No legal battle decision');
          }
        } else if (message === 12) {
          const card=r.card(true);r.u64();r.end();
          const plan=board?effectPlan(card):{utility:1};
          if(plan.utility>0) intent={code:codeOf(card),target:plan.target};
          response=integer(plan.utility>0?1:0);
        } else if (message === 13) {
          const description=r.u64(); r.end();
          // Pinned processor.cpp: 31 asks to attack directly; 30 asks to continue an attack replay.
          const attackChoice=attackingCard&&(description===31n?!!attackingCard.direct:description===30n?attackValue(attackingCard)>0:false);
          response = integer(!board||intent||attackChoice?1:0);
        } else if (message === 14 || message === 143) {
          const count = r.u8(); for (let i=0;i<count;i++) r.u64(); r.end();
          if (!count) fail('Empty option list'); response = integer(0);
        } else if (message === 15) {
          r.u8(); const min = r.count(), max = r.count(), cards = r.list(() => r.card(true)); r.end();
          if (min > max || min > cards.length) fail('Impossible card count');
          response = selected(rankSelection(cards,requestedHint).slice(0,min).map(c => c.index));
        } else if (message === 26) {
          const finishable = r.u8(), cancelable = r.u8(); const min = r.count(), max = r.count();
          const select = r.list(() => r.card(true)), unselect = r.list(() => r.card(true)); r.end();
          if (min > max) fail('Invalid unselect bounds');
          // Group-summon procedures filter the remaining legal zones/cards on every toggle.
          // MSG26 min/max do not cap the final group; preserve finish behavior for material pickers.
          const ownSummonCard = c => c.controller === selfPlayer && (c.location === 2 || (c.location === 64 && (c.position & 5)));
          const extendSummon = requestedHint === 509 && select.length > 0 && select.every(ownSummonCard) && unselect.every(ownSummonCard);
          const ranked=board?rankSelection(select,extendSummon?509:requestedHint):select;
          const preserveSpace=board&&finishable&&extendSummon&&monsters(true).length+unselect.length>=4&&value(ranked[0])<1000;
          response = (finishable && (!extendSummon||preserveSpace)) || (cancelable && !select.length) ? integer(-1) :
            select.length ? [...integer(1),...integer(ranked[0].index)] : unselect.length ? [...integer(1),...integer(select.length)] : fail('Empty forced selection');
        } else if (message === 16) {
          r.u8(); const forced = r.u8(); r.u32(); r.u32();
          const cards = r.list(() => ({...r.card(true),description:r.u64().toString(),flag:r.u8()})); r.end();
          if (forced && !cards.length) fail('Forced empty chain');
          if(board) {
            const action=lastChainPlayer===selfPlayer?null:tacticalAction(cards,0,'chain',effectPlan,true);
            response=forced?integer(cards.slice().sort((a,b)=>value(b)-value(a)||a.index-b.index)[0].index):action?action.commit():integer(-1);
          } else response = forced ? integer(0) : lastChainPlayer===selfPlayer ? integer(-1) : (chooseAction(cards,0,'chain',true) || integer(-1));
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
          const code = r.u32(), mask = r.u8(); r.end();
          const data = metadata[String(code)], defensive = board?wantsDefense({code,controller:selfPlayer,location:0,sequence:0}):data && (data.defense || 0) > (data.attack || 0);
          const position = (defensive ? [4,8,1,2] : [1,4,8,2]).find(p => (mask&p)!==0);
          if (!position || (mask & ~15)) fail('Invalid position mask'); response = integer(position);
        } else if (message === 20) {
          const cancelable = r.u8(), min = r.count(), max = r.count();
          const cards = r.list(() => ({...r.card(false),value:r.u8()})); r.end();
          const order=cards.slice().sort((a,b)=>board?value(a)/Math.max(1,a.value)-value(b)/Math.max(1,b.value)||a.index-b.index:b.value-a.value||score(a)-score(b)||a.index-b.index);
          let ids = [], sum = 0;
          for (const card of order) { if (sum>=min || ids.length>=max) break; ids.push(card.index); sum+=card.value; }
          // If low-value single tributes cannot meet a strict card-count cap, preserve protocol legality.
          if(sum<min&&board) {ids=[];sum=0;cards.sort((a,b)=>b.value-a.value||value(a)-value(b)||a.index-b.index);
            for(const card of cards) {if(sum>=min||ids.length>=max) break;ids.push(card.index);sum+=card.value;}}
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
          const ordered=board?optional.slice().sort((a,b)=>value(a)-value(b)||a.index-b.index):optional;
          response = selected(solveSum(mode,target,min,max,mandatory,ordered).map(i=>ordered[i].index));
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
