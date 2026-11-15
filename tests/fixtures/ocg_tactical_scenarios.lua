-- Canonical tactical scenarios: setup and passive assertions only.
function HostTacticalScenario(player, kind, marker)
    local flags = DUEL_MODE_MR5
    if kind == "rush_damage_step_win" or kind == "rush_hold_winning_battle" then
        flags = flags | DUEL_ATTACK_FIRST_TURN
    end
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
    local function observe(event, operation, condition)
        local observer = Effect.GlobalEffect()
        observer:SetType(EFFECT_TYPE_FIELD | EFFECT_TYPE_CONTINUOUS)
        observer:SetCode(event)
        observer:SetCondition(function(...)
            return not completed and (not condition or condition(...))
        end)
        observer:SetOperation(function(...)
            if not completed then operation(...) end
        end)
        Duel.RegisterEffect(observer, player)
    end
    local function add(code, owner, location, sequence, position)
        return Debug.AddCard(code, owner, owner, location, sequence, position)
    end
    local function monster(code, owner, sequence)
        return add(code, owner, LOCATION_MZONE, sequence or 0, POS_FACEUP_ATTACK)
    end
    if kind == "dark_hole_reject_bad_trade" then
        local blueeyes = monster(89631139, player, 0)
        local magician = monster(46986414, player, 1)
        monster(27288416, 1-player)
        local hole = add(53129443, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        observe(EVENT_CHAINING, function(e, tp, eg, ep, ev, re)
            assert(re:GetHandler() ~= hole, "AI must preserve its stronger board instead of using Dark Hole")
        end)
        observe(EVENT_PHASE | PHASE_END, function()
            assert(blueeyes:IsLocation(LOCATION_MZONE) and magician:IsLocation(LOCATION_MZONE))
            assert(hole:IsLocation(LOCATION_HAND | LOCATION_SZONE))
            complete()
        end, function() return Duel.GetTurnPlayer() == player end)
    elseif kind == "dark_hole_take_good_trade" then
        local own = monster(27288416, player)
        local blueeyes = monster(89631139, 1-player, 0)
        local magician = monster(46986414, 1-player, 1)
        local hole = add(53129443, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        observe(EVENT_CHAIN_END, function()
            if not hole:IsLocation(LOCATION_GRAVE) then return end
            for _, card in ipairs({own, blueeyes, magician}) do
                assert(card:IsLocation(LOCATION_GRAVE) and card:IsReason(REASON_DESTROY))
                assert(card:GetReasonEffect():GetHandler() == hole)
            end
            assert(Duel.GetFieldGroupCount(player, LOCATION_MZONE, LOCATION_MZONE) == 0)
            complete()
        end)
    elseif kind == "jammer_save_board" or kind == "mst_hold_against_normal_spell" then
        local own = monster(27288416, player)
        local defended = monster(46986414, 1-player)
        local hole = add(53129443, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local use_jammer = kind == "jammer_save_board"
        local response = add(use_jammer and 77414722 or 5318639, 1-player, LOCATION_SZONE, 0, POS_FACEDOWN_DEFENSE)
        local discard = use_jammer and add(78371393, 1-player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE) or nil
        local negated, max_chain, solving = false, 0, {}
        observe(EVENT_CHAINING, function(e, tp, eg, ep, ev, re)
            max_chain = math.max(max_chain, ev)
            if not use_jammer then assert(re:GetHandler() ~= response, "MST destruction does not negate a normal Spell") end
        end)
        observe(EVENT_CHAIN_SOLVING, function(e, tp, eg, ep, ev)
            solving[#solving+1] = ev
        end)
        observe(EVENT_CHAIN_NEGATED, function(e, tp, eg, ep, ev)
            assert(Duel.GetChainInfo(ev, CHAININFO_TRIGGERING_EFFECT):GetHandler() == hole)
            negated = true
        end)
        observe(EVENT_CHAIN_END, function()
            if not hole:IsLocation(LOCATION_GRAVE) then return end
            if use_jammer then
                assert(negated and max_chain == 2 and solving[1] == 2)
                assert(own:IsLocation(LOCATION_MZONE) and defended:IsLocation(LOCATION_MZONE))
                assert(response:IsLocation(LOCATION_GRAVE))
                assert(discard:IsLocation(LOCATION_GRAVE) and discard:IsReason(REASON_COST) and discard:IsReason(REASON_DISCARD))
            else
                assert(not negated and max_chain == 1)
                assert(own:IsLocation(LOCATION_GRAVE) and defended:IsLocation(LOCATION_GRAVE))
                assert(response:IsLocation(LOCATION_SZONE) and response:IsFacedown())
            end
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 8000)
            complete()
        end)
    elseif kind == "jammer_hold_against_upstart" then
        local upstart = add(70368879, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        monster(46986414, 1-player)
        local jammer = add(77414722, 1-player, LOCATION_SZONE, 0, POS_FACEDOWN_DEFENSE)
        local discard = add(78371393, 1-player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        observe(EVENT_CHAINING, function(e, tp, eg, ep, ev, re)
            assert(re:GetHandler() ~= jammer, "Do not spend Magic Jammer and a discard on low-impact Upstart")
        end)
        observe(EVENT_CHAIN_END, function()
            if not upstart:IsLocation(LOCATION_GRAVE) then return end
            assert(jammer:IsLocation(LOCATION_SZONE) and jammer:IsFacedown())
            assert(discard:IsLocation(LOCATION_HAND))
            assert(Duel.GetFieldGroupCount(player, LOCATION_HAND, 0) == 1)
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 9000)
            complete()
        end)
    elseif kind == "rush_damage_step_win" or kind == "rush_hold_winning_battle" then
        local need_boost = kind == "rush_damage_step_win"
        local own = monster(97590747, player)
        local opposing = monster(need_boost and 69247929 or 5053103, 1-player)
        local rush = add(70046172, player, LOCATION_SZONE, 0, POS_FACEDOWN_DEFENSE)
        local activated, damage = false, false
        observe(EVENT_CHAINING, function(e, tp, eg, ep, ev, re)
            if re:GetHandler() ~= rush then return end
            assert(need_boost, "Preserve Rush when the visible battle is already won")
            assert(Duel.GetCurrentPhase() == PHASE_DAMAGE and not Duel.IsDamageCalculated(), "Rush must resolve in the legal Damage Step window")
            activated = true
        end)
        observe(EVENT_CHAIN_END, function()
            if activated then assert(own:GetAttack() == 2500) end
        end)
        observe(EVENT_BATTLE_DAMAGE, function(e, tp, eg, ep, ev)
            assert(ep == 1-player and ev == (need_boost and 500 or 100))
            damage = true
        end)
        observe(EVENT_DAMAGE_STEP_END, function()
            assert(damage and activated == need_boost)
            assert(own:IsLocation(LOCATION_MZONE) and opposing:IsLocation(LOCATION_GRAVE))
            assert(opposing:IsReason(REASON_BATTLE))
            assert(own:GetAttack() == (need_boost and 2500 or 1800))
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == (need_boost and 7500 or 7900))
            if need_boost then assert(rush:IsLocation(LOCATION_GRAVE))
            else assert(rush:IsLocation(LOCATION_SZONE) and rush:IsFacedown()) end
            complete()
        end)
    else
        error("Unknown host tactical scenario")
    end
    Debug.ReloadFieldEnd()
end
