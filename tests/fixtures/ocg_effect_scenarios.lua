-- Test-only setup and observation. Card effects come from the pinned canonical scripts.
-- Neither this fixture nor its observers activate, copy, replace or resolve card effects.
function HostEffectScenario(player, kind, marker)
    local flags = DUEL_MODE_MR5
    if kind == "effect_and_battle_damage" then flags = flags | DUEL_ATTACK_FIRST_TURN end
    Debug.ReloadFieldBegin(flags, 0)
    Debug.SetPlayerInfo(0, 8000, 0, 0)
    Debug.SetPlayerInfo(1, 8000, 0, 0)
    for p = 0, 1 do
        for _, code in ipairs({89631139, 46986414, 70781052}) do
            Debug.AddCard(code, p, p, LOCATION_DECK, 0, POS_FACEDOWN_DEFENSE)
        end
    end
    local completed = false
    local function complete()
        assert(not completed)
        completed = true
        Duel.Hint(HINT_MESSAGE, player, marker)
    end
    local function observe(event, operation)
        local observer = Effect.GlobalEffect()
        observer:SetType(EFFECT_TYPE_FIELD | EFFECT_TYPE_CONTINUOUS)
        observer:SetCode(event)
        observer:SetOperation(operation)
        Duel.RegisterEffect(observer, player)
    end
    local function add(code, owner, location, sequence, position)
        return Debug.AddCard(code, owner, owner, location, sequence, position)
    end
    if kind == "destruction_revival" then
        local blueeyes = add(89631139, player, LOCATION_MZONE, 0, POS_FACEUP_ATTACK)
        local magician = add(46986414, 1-player, LOCATION_MZONE, 0, POS_FACEUP_ATTACK)
        local opposing_dragon = add(89631139, 1-player, LOCATION_MZONE, 1, POS_FACEUP_ATTACK)
        local hole = add(53129443, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local reborn = add(83764718, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local destroyed = false
        observe(EVENT_DESTROYED, function(e, tp, eg)
            if not eg:IsContains(blueeyes) or not eg:IsContains(magician) or not eg:IsContains(opposing_dragon) then return end
            assert(blueeyes:IsLocation(LOCATION_GRAVE) and magician:IsLocation(LOCATION_GRAVE))
            for _, card in ipairs({blueeyes, magician, opposing_dragon}) do
                assert(card:IsReason(REASON_DESTROY) and card:IsReason(REASON_EFFECT))
                assert(card:GetReasonEffect():GetHandler() == hole)
            end
            destroyed = true
        end)
        observe(EVENT_CHAIN_END, function()
            if not reborn:IsLocation(LOCATION_GRAVE) then return end
            assert(destroyed and hole:IsLocation(LOCATION_GRAVE))
            assert(blueeyes:IsLocation(LOCATION_MZONE) and blueeyes:IsControler(player) and blueeyes:IsFaceup())
            assert(magician:IsLocation(LOCATION_GRAVE) and opposing_dragon:IsLocation(LOCATION_GRAVE))
            assert(Duel.GetFieldGroupCount(player, LOCATION_MZONE, LOCATION_MZONE) == 1)
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 8000)
            complete()
        end)
    elseif kind == "spell_activation_negation" then
        local own = add(27288416, player, LOCATION_MZONE, 0, POS_FACEUP_ATTACK)
        local magician = add(46986414, 1-player, LOCATION_MZONE, 0, POS_FACEUP_ATTACK)
        local hole = add(53129443, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local jammer = add(77414722, 1-player, LOCATION_SZONE, 0, POS_FACEDOWN_DEFENSE)
        -- A low-ATK Level 10 discard stays in hand and makes saving the defender worthwhile.
        local discard = add(78371393, 1-player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local negated = false
        observe(EVENT_CHAIN_NEGATED, function(e, tp, eg, ep, ev)
            assert(Duel.GetChainInfo(ev, CHAININFO_TRIGGERING_EFFECT):GetHandler() == hole)
            negated = true
        end)
        observe(EVENT_CHAIN_END, function()
            if not hole:IsLocation(LOCATION_GRAVE) then return end
            assert(negated and jammer:IsLocation(LOCATION_GRAVE))
            assert(discard:IsLocation(LOCATION_GRAVE) and discard:IsReason(REASON_COST) and discard:IsReason(REASON_DISCARD))
            assert(own:IsLocation(LOCATION_MZONE) and magician:IsLocation(LOCATION_MZONE))
            assert(Duel.GetFieldGroupCount(player, LOCATION_MZONE, LOCATION_MZONE) == 2)
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 8000)
            complete()
        end)
    elseif kind == "effect_and_battle_damage" then
        local blueeyes = add(89631139, player, LOCATION_MZONE, 0, POS_FACEUP_ATTACK)
        local fire = add(46918794, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local burned, battled = false, false
        observe(EVENT_CHAIN_END, function()
            if not fire:IsLocation(LOCATION_GRAVE) then return end
            assert(Duel.GetLP(player) == 7500 and Duel.GetLP(1-player) == 7000)
            burned = true
        end)
        observe(EVENT_BATTLE_DAMAGE, function(e, tp, eg, ep, ev)
            assert(burned and ep == 1-player and ev == 3000)
            assert(Duel.GetAttacker() == blueeyes and Duel.GetAttackTarget() == nil)
            battled = true
        end)
        observe(EVENT_DAMAGE_STEP_END, function()
            assert(burned and battled)
            assert(Duel.GetLP(player) == 7500 and Duel.GetLP(1-player) == 4000)
            assert(blueeyes:IsLocation(LOCATION_MZONE))
            complete()
        end)
    elseif kind == "fusion_summon" then
        local materials = {}
        for i = 1, 3 do materials[i] = add(89631139, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE) end
        local polymerization = add(24094653, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local ultimate = add(23995346, player, LOCATION_EXTRA, 0, POS_FACEDOWN_DEFENSE)
        observe(EVENT_CHAIN_END, function()
            if not polymerization:IsLocation(LOCATION_GRAVE) then return end
            assert(ultimate:IsLocation(LOCATION_MZONE) and ultimate:IsControler(player) and ultimate:IsFaceup())
            assert(ultimate:IsSummonType(SUMMON_TYPE_FUSION))
            local used = ultimate:GetMaterial()
            assert(#used == 3)
            for _, card in ipairs(materials) do
                assert(used:IsContains(card) and card:IsLocation(LOCATION_GRAVE))
                assert(card:IsReason(REASON_MATERIAL) and card:IsReason(REASON_FUSION))
            end
            assert(Duel.GetFieldGroupCount(player, LOCATION_HAND, 0) == 0)
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 8000)
            complete()
        end)
    else
        error("Unknown host effect scenario")
    end
    Debug.ReloadFieldEnd()
end
