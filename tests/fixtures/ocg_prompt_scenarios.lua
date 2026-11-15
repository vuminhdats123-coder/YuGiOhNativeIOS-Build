-- Test-only OCG scenarios. Never bundled in the game and never declare a winner.
-- Completion markers occur only after the core resumes the operations below.
function HostPromptScenario(player, kind, marker)
    local flags = DUEL_MODE_MR5
    if kind == "attack_cost_order" then flags = flags | DUEL_ATTACK_FIRST_TURN end
    Debug.ReloadFieldBegin(flags)
    Debug.SetPlayerInfo(0, 8000, 0, 0)
    Debug.SetPlayerInfo(1, 8000, 0, 0)
    for p = 0, 1 do
        for _, code in ipairs({89631139, 46986414, 70781052}) do
            Debug.AddCard(code, p, p, LOCATION_DECK, 0, POS_FACEDOWN_DEFENSE)
        end
    end
    local a = Debug.AddCard(89631139, player, player, LOCATION_MZONE, 0, POS_FACEUP_ATTACK)
    local b = Debug.AddCard(46986414, player, player, LOCATION_MZONE, 1, POS_FACEUP_ATTACK)
    local function complete() Duel.Hint(HINT_MESSAGE, player, marker) end

    if kind == "choices" then
        a:EnableCounterPermit(0x1)
        b:EnableCounterPermit(0x1)
        Debug.PreAddCounter(a, 0x1, 2)
        Debug.PreAddCounter(b, 0x1, 2)
        local once = Effect.GlobalEffect()
        once:SetType(EFFECT_TYPE_FIELD | EFFECT_TYPE_CONTINUOUS)
        once:SetCode(EVENT_ADJUST)
        once:SetOperation(function(e)
            e:Reset()
            assert(Duel.RemoveCounter(player, 1, 0, 0x1, 3, REASON_EFFECT))
            assert(a:GetCounter(0x1) + b:GetCounter(0x1) == 1)
            assert(Duel.SelectDisableField(player, 2, LOCATION_MZONE | LOCATION_SZONE,
                LOCATION_MZONE | LOCATION_SZONE, 0) > 0)
            assert(Duel.AnnounceRace(player, 2, RACE_DRAGON | RACE_WARRIOR | RACE_SPELLCASTER) > 0)
            assert(Duel.AnnounceAttribute(player, 2, ATTRIBUTE_LIGHT | ATTRIBUTE_DARK | ATTRIBUTE_EARTH) > 0)
            assert(Duel.AnnounceCard(player, TYPE_MONSTER) > 0)
            assert(Duel.AnnounceNumber(player, 4, 8, 12) == 4)
            assert(Duel.SelectOption(player, 1, 2, 3) == 0)
            assert(Duel.SelectYesNo(player, 1))
            assert(Duel.SelectPosition(player, a, POS_FACEUP_ATTACK | POS_FACEUP_DEFENSE) == POS_FACEUP_ATTACK)
            Duel.SortDecktop(player, player, 3)
            -- Both bots use the same deterministic RPS choice; a tie is valid when repetition is disabled.
            Duel.RockPaperScissors(false)
            complete()
        end)
        Duel.RegisterEffect(once, player)
    elseif kind == "attack_cost_order" then
        local paid = 0
        for i = 1, 2 do
            local cost = Effect.CreateEffect(a)
            cost:SetType(EFFECT_TYPE_SINGLE)
            cost:SetCode(EFFECT_ATTACK_COST)
            cost:SetOperation(function(e, tp)
                Duel.PayLPCost(tp, 100)
                paid = paid + 1
                if paid == 2 then
                    assert(Duel.GetLP(player) == 7800)
                    complete()
                end
            end)
            a:RegisterEffect(cost)
        end
    elseif kind == "forced_chain" then
        local resolved = 0
        for _, card in ipairs({a, b}) do
            local trigger = Effect.CreateEffect(card)
            trigger:SetType(EFFECT_TYPE_FIELD | EFFECT_TYPE_TRIGGER_F)
            trigger:SetCode(EVENT_PHASE | PHASE_STANDBY)
            trigger:SetRange(LOCATION_MZONE)
            trigger:SetCountLimit(1)
            trigger:SetOperation(function()
                resolved = resolved + 1
                if resolved == 2 then complete() end
            end)
            card:RegisterEffect(trigger)
        end
    else
        error("Unknown host prompt scenario")
    end
    Debug.ReloadFieldEnd()
end
