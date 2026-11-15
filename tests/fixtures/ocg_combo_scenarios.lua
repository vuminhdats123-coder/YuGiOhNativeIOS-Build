-- Combo setup and passive assertions only. Canonical scripts execute each sequence.
function HostComboScenario(player, kind, marker)
    Debug.ReloadFieldBegin(DUEL_MODE_MR5, 0)
    Debug.SetPlayerInfo(0, 8000, 0, 0)
    Debug.SetPlayerInfo(1, 8000, 0, 0)
    for p = 0, 1 do
        for _, code in ipairs({89631139, 46986414, 70781052}) do
            Debug.AddCard(code, p, p, LOCATION_DECK, 0, POS_FACEDOWN_DEFENSE)
        end
    end
    local completed=false
    local function complete() assert(not completed);completed=true;Duel.Hint(HINT_MESSAGE,player,marker) end
    local function observe(event, operation)
        local e=Effect.GlobalEffect();e:SetType(EFFECT_TYPE_FIELD|EFFECT_TYPE_CONTINUOUS);e:SetCode(event)
        e:SetOperation(function(...) if not completed then operation(...) end end);Duel.RegisterEffect(e,player)
    end
    local function add(code,owner,location,sequence,position) return Debug.AddCard(code,owner,owner,location,sequence,position) end
    if kind=="foolish_reborn" then
        local blueeyes=add(89631139,player,LOCATION_DECK,0,POS_FACEDOWN_DEFENSE)
        local foolish=add(81439173,player,LOCATION_HAND,0,POS_FACEDOWN_DEFENSE)
        local reborn=add(83764718,player,LOCATION_HAND,0,POS_FACEDOWN_DEFENSE)
        observe(EVENT_CHAIN_END,function()
            if not reborn:IsLocation(LOCATION_GRAVE) then return end
            assert(foolish:IsLocation(LOCATION_GRAVE))
            assert(blueeyes:IsLocation(LOCATION_MZONE) and blueeyes:IsControler(player) and blueeyes:IsFaceup())
            assert(Duel.GetFieldGroupCount(player,LOCATION_MZONE,0)==1)
            assert(Duel.GetLP(player)==8000 and Duel.GetLP(1-player)==8000)
            complete()
        end)
    elseif kind=="tradein_silverscry" then
        local blueeyes=add(89631139,player,LOCATION_HAND,0,POS_FACEDOWN_DEFENSE)
        local trade=add(38120068,player,LOCATION_HAND,0,POS_FACEDOWN_DEFENSE)
        local cry=add(87025064,player,LOCATION_HAND,0,POS_FACEDOWN_DEFENSE)
        observe(EVENT_CHAIN_END,function()
            if not cry:IsLocation(LOCATION_GRAVE) then return end
            assert(trade:IsLocation(LOCATION_GRAVE))
            assert(blueeyes:IsLocation(LOCATION_MZONE) and blueeyes:IsControler(player) and blueeyes:IsFaceup())
            assert(Duel.GetLP(player)==8000 and Duel.GetLP(1-player)==8000)
            complete()
        end)
    elseif kind=="rota_junk_search_summon" then
        local quill=add(23571046,player,LOCATION_GRAVE,0,POS_FACEUP_DEFENSE)
        local rota=add(32807846,player,LOCATION_HAND,0,POS_FACEDOWN_DEFENSE)
        local synchron=add(63977008,player,LOCATION_DECK,0,POS_FACEDOWN_DEFENSE)
        observe(EVENT_SUMMON_SUCCESS,function(e,tp,eg)
            assert(eg:IsContains(synchron))
            assert(synchron:IsLocation(LOCATION_MZONE) and synchron:IsControler(player) and synchron:IsFaceup())
            assert(rota:IsLocation(LOCATION_GRAVE) and quill:IsLocation(LOCATION_GRAVE))
            complete()
        end)
    else error("Unknown host combo scenario") end
    Debug.ReloadFieldEnd()
end
