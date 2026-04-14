-- Server_AdvanceTurn.lua
-- "Killer Gets the Land" mod
--
-- When a player is eliminated this turn, all their remaining territories
-- are transferred to whoever killed them (the last player to successfully
-- attack one of their territories this turn).
--
-- If no killer is recorded (e.g. eliminated by a blockade, or surrendered),
-- territories go neutral as normal.
--
-- Works independently of teams — the killer always gets the land.

-- _KGL_transfers[playerID] = { killerID=x, terrIDs={...} }
-- Snapshot is taken at the moment of the killing blow in _Order,
-- while LatestTurnStanding still shows the defender's territories.
_KGL_transfers = {}
_KGL_wasAlive  = {}

function Server_AdvanceTurn_Start(game, addNewOrder)
    _KGL_transfers = {}
    _KGL_wasAlive  = {}

    for _, player in pairs(game.Game.Players) do
        if player.State == WL.GamePlayerState.Playing then
            _KGL_wasAlive[player.ID] = true
        end
    end
end

function Server_AdvanceTurn_Order(game, order, orderResult, skipThisOrder, addNewOrder)
    if order.proxyType ~= 'GameOrderAttackTransfer' then return end
    if not orderResult.IsAttack then return end
    if not orderResult.IsSuccessful then return end

    local standing   = game.ServerGame.LatestTurnStanding
    local attackerID = order.PlayerID
    local defenderID = standing.Territories[order.To].OwnerPlayerID

    if defenderID == WL.PlayerID.Neutral then return end
    if not _KGL_wasAlive[defenderID] then return end

    -- Snapshot all territories owned by the defender right now,
    -- before this attack is applied and before Warzone neutralizes them.
    -- We overwrite on each successful attack so the last kill counts.
    local terrIDs = {}
    for terrID, ts in pairs(standing.Territories) do
        if ts.OwnerPlayerID == defenderID then
            terrIDs[#terrIDs + 1] = terrID
        end
    end

    _KGL_transfers[defenderID] = {
        killerID = attackerID,
        terrIDs  = terrIDs,
    }
end

function Server_AdvanceTurn_End(game, addNewOrder)
    local players = game.Game.Players

    for playerID, transfer in pairs(_KGL_transfers) do
        local player  = players[playerID]
        local nowElim = (player.State == WL.GamePlayerState.Eliminated)

        -- Only act if the player was actually eliminated this turn
        if not nowElim then goto continue end

        -- Follow the kill chain: if the killer was also eliminated this turn,
        -- their killer inherits the transfer, and so on up the chain.
        -- (Circular chains are impossible since eliminated players stop acting.)
        local killerID = transfer.killerID
        while true do
            local killerPlayer = players[killerID]
            if killerPlayer.State ~= WL.GamePlayerState.Eliminated then
                break  -- found an alive killer
            end
            local killerTransfer = _KGL_transfers[killerID]
            if killerTransfer == nil then
                killerID = nil  -- no one killed this player, territories go neutral
                break
            end
            killerID = killerTransfer.killerID
        end

        if killerID == nil then goto continue end
        transfer.killerID = killerID
        if #transfer.terrIDs == 0 then goto continue end

        local mods = {}
        for _, terrID in ipairs(transfer.terrIDs) do
            local mod = WL.TerritoryModification.Create(terrID)
            mod.SetOwnerOpt = transfer.killerID
            mods[#mods + 1] = mod
        end

        local loserName  = players[playerID].DisplayName(nil, false)
        local killerName = players[transfer.killerID].DisplayName(nil, false)
        local msg = loserName .. ' was eliminated. Their '
                    .. #transfer.terrIDs
                    .. ' territories have been transferred to '
                    .. killerName .. '.'

        addNewOrder(WL.GameOrderEvent.Create(
            transfer.killerID,
            msg,
            nil,
            mods,
            nil,
            nil
        ))

        ::continue::
    end
end
