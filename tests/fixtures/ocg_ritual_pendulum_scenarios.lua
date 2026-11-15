-- Starting positions and passive observers only; canonical scripts perform all summons/effects.
function HostRitualPendulumScenario(player, kind, marker)
    Debug.ReloadFieldBegin(DUEL_MODE_MR5, 0)
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
        observer:SetOperation(function(...)
            if not completed then operation(...) end
        end)
        Duel.RegisterEffect(observer, player)
    end
    local function add(code, owner, location, sequence, position)
        return Debug.AddCard(code, owner, owner, location, sequence, position)
    end
    local function scales()
        local low = add(15146890, player, LOCATION_PZONE, 0, POS_FACEUP_ATTACK)
        local high = add(51531505, player, LOCATION_PZONE, 1, POS_FACEUP_ATTACK)
        assert(low:GetLeftScale() == 1 and high:GetRightScale() == 8)
        assert(low:GetSequence() == 0 and high:GetSequence() == 4)
        return low, high
    end
    local function assert_pendulum(card)
        assert(card:IsLocation(LOCATION_MZONE) and card:IsControler(player) and card:IsFaceup())
        assert(card:IsSummonType(SUMMON_TYPE_PENDULUM))
    end
    if kind == "ritual_exact_level" or kind == "ritual_greater_level" then
        local exact = kind == "ritual_exact_level"
        local monster = add(exact and 45222299 or 5405694, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local spell = add(exact and 46159582 or 55761792, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local materials, forbidden = {}, nil
        if exact then
            materials[1] = add(90357090, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
            materials[2] = add(90357090, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
            forbidden = add(89631139, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        else
            materials[1] = add(98777036, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        end
        observe(EVENT_CHAIN_END, function()
            if not spell:IsLocation(LOCATION_GRAVE) then return end
            assert(monster:IsLocation(LOCATION_MZONE) and monster:IsControler(player) and monster:IsFaceup())
            assert(monster:IsSummonType(SUMMON_TYPE_RITUAL) and monster:IsStatus(STATUS_PROC_COMPLETE))
            local used = monster:GetMaterial()
            assert(#used == #materials)
            local total = 0
            for _, card in ipairs(materials) do
                assert(used:IsContains(card) and card:IsLocation(LOCATION_GRAVE))
                assert(card:IsReason(REASON_MATERIAL) and card:IsReason(REASON_RITUAL) and card:IsReason(REASON_RELEASE))
                total = total + card:GetLevel()
            end
            if exact then
                assert(total == 6 and monster:GetLevel() == 6)
                assert(forbidden:IsLocation(LOCATION_HAND) and not used:IsContains(forbidden))
            else
                assert(total == 10 and monster:GetLevel() == 8 and total > monster:GetLevel())
            end
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 8000)
            complete()
        end)
    elseif kind == "pendulum_mixed_scale_bounds" then
        local low, high = scales()
        local hand = add(9365703, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local lower_endpoint = add(27288416, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local upper_endpoint = add(89631139, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local extra = add(21970285, player, LOCATION_EXTRA, 0, POS_FACEUP_DEFENSE)
        observe(EVENT_SPSUMMON_SUCCESS, function(e, tp, eg)
            assert(#eg == 2 and eg:IsContains(hand) and eg:IsContains(extra), "Pendulum group must include both legal hand and Extra cards")
            assert_pendulum(hand)
            assert_pendulum(extra)
            assert(hand:GetSequence() < 5 and extra:GetSequence() == 5)
            assert(lower_endpoint:IsLocation(LOCATION_HAND) and lower_endpoint:GetLevel() == 1)
            assert(upper_endpoint:IsLocation(LOCATION_HAND) and upper_endpoint:GetLevel() == 8)
            assert(low:IsLocation(LOCATION_PZONE) and high:IsLocation(LOCATION_PZONE))
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 8000)
            complete()
        end)
    elseif kind == "pendulum_extra_unlinked" or kind == "pendulum_extra_linked" then
        scales()
        local linked = kind == "pendulum_extra_linked"
        local link = linked and add(1861629, player, LOCATION_MZONE, 5, POS_FACEUP_ATTACK) or nil
        local hunter = add(21970285, player, LOCATION_EXTRA, 0, POS_FACEUP_DEFENSE)
        local dragon = add(16178681, player, LOCATION_EXTRA, 0, POS_FACEUP_DEFENSE)
        observe(EVENT_SPSUMMON_SUCCESS, function(e, tp, eg)
            assert(#eg == (linked and 2 or 1))
            if linked then
                assert(eg:IsContains(hunter) and eg:IsContains(dragon))
                assert_pendulum(hunter)
                assert_pendulum(dragon)
                local zones = (1 << hunter:GetSequence()) | (1 << dragon:GetSequence())
                assert(zones == ((1 << 0) | (1 << 2)))
                assert(link:GetSequence() == 5 and link:GetLinkedGroup():Includes(eg))
            else
                local summoned = eg:GetFirst()
                assert(summoned == hunter or summoned == dragon)
                assert_pendulum(summoned)
                assert(summoned:GetSequence() == 5)
                local remaining = summoned == hunter and dragon or hunter
                assert(remaining:IsLocation(LOCATION_EXTRA) and remaining:IsFaceup())
                assert(Duel.GetFieldGroupCount(player, LOCATION_MZONE, 0) == 1)
            end
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 8000)
            complete()
        end)
    elseif kind == "pendulum_destroy_return" then
        local low, high = scales()
        local hunter = add(21970285, player, LOCATION_MZONE, 0, POS_FACEUP_ATTACK)
        local hole = add(53129443, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local destroyed = false
        observe(EVENT_CHAIN_END, function()
            if not hole:IsLocation(LOCATION_GRAVE) then return end
            assert(hunter:IsLocation(LOCATION_EXTRA) and hunter:IsFaceup())
            assert(hunter:IsReason(REASON_DESTROY) and hunter:IsReason(REASON_EFFECT))
            assert(hunter:GetReasonEffect():GetHandler() == hole)
            destroyed = true
        end)
        observe(EVENT_SPSUMMON_SUCCESS, function(e, tp, eg)
            assert(destroyed and #eg == 1 and eg:IsContains(hunter))
            assert_pendulum(hunter)
            assert(hunter:GetSequence() == 5 and hunter:GetPreviousLocation() == LOCATION_EXTRA)
            assert(low:IsLocation(LOCATION_PZONE) and high:IsLocation(LOCATION_PZONE))
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 8000)
            complete()
        end)
    else
        error("Unknown host Ritual/Pendulum scenario")
    end
    Debug.ReloadFieldEnd()
end
