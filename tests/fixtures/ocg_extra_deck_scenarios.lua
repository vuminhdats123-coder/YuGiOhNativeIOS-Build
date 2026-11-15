-- Test setup and observation only. Summon procedures and card effects are canonical scripts.
function HostExtraDeckScenario(player, kind, marker)
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
    local function assert_materials(monster, materials, reason)
        local used = monster:GetMaterial()
        assert(#used == #materials)
        for _, card in ipairs(materials) do
            assert(used:IsContains(card) and card:IsLocation(LOCATION_GRAVE))
            assert(card:IsReason(REASON_MATERIAL) and card:IsReason(reason))
        end
    end
    local function assert_summon(monster, summon_type, sequence)
        assert(monster:IsLocation(LOCATION_MZONE) and monster:IsControler(player) and monster:IsFaceup())
        assert(monster:IsSummonType(summon_type) and monster:IsStatus(STATUS_PROC_COMPLETE))
        assert(monster:GetSequence() == sequence)
    end
    if kind == "synchro_trigger" or kind == "synchro_summon_negation" then
        local synchron = add(63977008, player, LOCATION_MZONE, 0, POS_FACEUP_ATTACK)
        local speed = add(9365703, player, LOCATION_MZONE, 1, POS_FACEUP_ATTACK)
        local mokey = add(27288416, player, LOCATION_MZONE, 2, POS_FACEUP_ATTACK)
        local warrior = add(60800381, player, LOCATION_EXTRA, 0, POS_FACEDOWN_DEFENSE)
        if kind == "synchro_trigger" then
            local summoned = false
            observe(EVENT_SPSUMMON_SUCCESS, function(e, tp, eg)
                if not eg:IsContains(warrior) then return end
                assert_summon(warrior, SUMMON_TYPE_SYNCHRO, 0)
                assert_materials(warrior, {synchron, speed}, REASON_SYNCHRO)
                summoned = true
            end)
            observe(EVENT_CHAIN_END, function()
                if not summoned then return end
                assert_summon(warrior, SUMMON_TYPE_SYNCHRO, 0)
                assert_materials(warrior, {synchron, speed}, REASON_SYNCHRO)
                assert(mokey:IsLocation(LOCATION_MZONE) and mokey:GetSequence() == 2)
                assert(warrior:GetAttack() == 2600 and mokey:GetAttack() == 300)
                assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 8000)
                complete()
            end)
        else
            local judgment = add(41420027, 1-player, LOCATION_SZONE, 0, POS_FACEDOWN_DEFENSE)
            local negated = false
            observe(EVENT_SPSUMMON_SUCCESS, function(e, tp, eg)
                assert(not eg:IsContains(warrior), "Negated Synchro summon incorrectly succeeded")
            end)
            observe(EVENT_SPSUMMON_NEGATED, function(e, tp, eg)
                if eg:IsContains(warrior) then negated = true end
            end)
            observe(EVENT_ADJUST, function()
                if not negated or not judgment:IsLocation(LOCATION_GRAVE) then return end
                assert(warrior:IsLocation(LOCATION_GRAVE) and not warrior:IsStatus(STATUS_PROC_COMPLETE))
                assert(warrior:IsReason(REASON_DESTROY) and warrior:IsReason(REASON_EFFECT))
                assert(warrior:GetReasonEffect():GetHandler() == judgment)
                assert_materials(warrior, {synchron, speed}, REASON_SYNCHRO)
                assert(mokey:IsLocation(LOCATION_MZONE))
                assert(Duel.GetFieldGroupCount(player, LOCATION_MZONE, 0) == 1)
                assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 4000)
                complete()
            end)
        end
    elseif kind == "xyz_detach_damage" then
        local warwolf = add(69247929, player, LOCATION_MZONE, 0, POS_FACEUP_ATTACK)
        local dragon = add(43096270, player, LOCATION_MZONE, 1, POS_FACEUP_ATTACK)
        local cowboy = add(12014404, player, LOCATION_EXTRA, 0, POS_FACEDOWN_DEFENSE)
        local summoned = false
        observe(EVENT_SPSUMMON_SUCCESS, function(e, tp, eg)
            if not eg:IsContains(cowboy) then return end
            assert_summon(cowboy, SUMMON_TYPE_XYZ, 0)
            assert(cowboy:GetRank() == 4 and cowboy:IsPosition(POS_FACEUP_DEFENSE))
            local overlay = cowboy:GetOverlayGroup()
            assert(#overlay == 2 and overlay:IsContains(warwolf) and overlay:IsContains(dragon))
            assert(warwolf:GetOverlayTarget() == cowboy and dragon:GetOverlayTarget() == cowboy)
            summoned = true
        end)
        observe(EVENT_CHAIN_END, function()
            if not summoned then return end
            assert_summon(cowboy, SUMMON_TYPE_XYZ, 0)
            assert(cowboy:IsPosition(POS_FACEUP_DEFENSE) and cowboy:GetOverlayCount() == 1)
            local detached, attached = 0, 0
            for _, card in ipairs({warwolf, dragon}) do
                if card:IsLocation(LOCATION_GRAVE) then
                    assert(card:IsReason(REASON_COST) and card:GetReasonEffect():GetHandler() == cowboy)
                    detached = detached + 1
                else
                    assert(card:IsLocation(LOCATION_OVERLAY) and card:GetOverlayTarget() == cowboy)
                    attached = attached + 1
                end
            end
            assert(detached == 1 and attached == 1)
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 7200)
            complete()
        end)
    elseif kind == "link_discard_destroy" then
        local warwolf = add(69247929, player, LOCATION_MZONE, 0, POS_FACEUP_ATTACK)
        local dragon = add(43096270, player, LOCATION_MZONE, 1, POS_FACEUP_ATTACK)
        local discard = add(89631139, player, LOCATION_HAND, 0, POS_FACEDOWN_DEFENSE)
        local target = add(77414722, 1-player, LOCATION_SZONE, 0, POS_FACEDOWN_DEFENSE)
        local phoenix = add(2857636, player, LOCATION_EXTRA, 0, POS_FACEDOWN_DEFENSE)
        local summoned = false
        observe(EVENT_SPSUMMON_SUCCESS, function(e, tp, eg)
            if not eg:IsContains(phoenix) then return end
            assert_summon(phoenix, SUMMON_TYPE_LINK, 5)
            assert_materials(phoenix, {warwolf, dragon}, REASON_LINK)
            summoned = true
        end)
        observe(EVENT_CHAIN_END, function()
            if not summoned then return end
            assert_summon(phoenix, SUMMON_TYPE_LINK, 5)
            assert_materials(phoenix, {warwolf, dragon}, REASON_LINK)
            assert(phoenix:GetLink() == 2 and phoenix:GetMutualLinkedGroupCount() == 0)
            assert(discard:IsLocation(LOCATION_GRAVE) and discard:IsReason(REASON_COST) and discard:IsReason(REASON_DISCARD))
            assert(target:IsLocation(LOCATION_GRAVE) and target:IsReason(REASON_DESTROY) and target:IsReason(REASON_EFFECT))
            assert(target:GetReasonEffect():GetHandler() == phoenix)
            assert(Duel.GetFieldGroupCount(player, LOCATION_HAND, 0) == 0)
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 8000)
            complete()
        end)
    elseif kind == "link_rating_material" then
        local synchron = add(63977008, player, LOCATION_MZONE, 0, POS_FACEUP_ATTACK)
        local phoenix = add(2857636, player, LOCATION_MZONE, 5, POS_FACEUP_ATTACK)
        local decode = add(1861629, player, LOCATION_EXTRA, 0, POS_FACEDOWN_DEFENSE)
        observe(EVENT_SPSUMMON_SUCCESS, function(e, tp, eg)
            if not eg:IsContains(decode) then return end
            assert_summon(decode, SUMMON_TYPE_LINK, 5)
            assert_materials(decode, {synchron, phoenix}, REASON_LINK)
            assert(decode:GetLink() == 3 and phoenix:GetLink() == 2)
            assert(Duel.GetFieldGroupCount(player, LOCATION_MZONE, 0) == 1)
            assert(decode:GetAttack() == 2300)
            assert(Duel.GetLP(player) == 8000 and Duel.GetLP(1-player) == 8000)
            complete()
        end)
    else
        error("Unknown host Extra Deck scenario")
    end
    Debug.ReloadFieldEnd()
end
