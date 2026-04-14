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

local function snapshotTerritories(standing, ownerID)
    local terrIDs = {}
    for terrID, ts in pairs(standing.Territories) do
        if ts.OwnerPlayerID == ownerID then
            terrIDs[#terrIDs + 1] = terrID
        end
    end
    return terrIDs
end

function Server_AdvanceTurn_Order(game, order, orderResult, skipThisOrder, addNewOrder)
    if order.proxyType ~= 'GameOrderAttackTransfer' then return end
    if not orderResult.IsAttack then return end

    local standing   = game.ServerGame.LatestTurnStanding
    local attackerID = order.PlayerID
    local defenderID = standing.Territories[order.To].OwnerPlayerID

    if defenderID == WL.PlayerID.Neutral then return end

    if orderResult.IsSuccessful then
        -- Successful attack: record attacker as killer of defender
        if not _KGL_wasAlive[defenderID] then return end
        _KGL_transfers[defenderID] = {
            killerID = attackerID,
            terrIDs  = snapshotTerritories(standing, defenderID),
        }

    else
        -- Failed attack: record defender as potential killer of attacker.
        -- We only act on this in _End if the attacker actually ends up eliminated.
        if not _KGL_wasAlive[attackerID] then return end
        _KGL_transfers[attackerID] = {
            killerID = defenderID,
            terrIDs  = snapshotTerritories(standing, attackerID),
        }
    end
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

        -- Only transfer territories that are still neutral at end of turn.
        -- If another player captured one, leave it with them.
        local standing = game.ServerGame.LatestTurnStanding
        local mods = {}
        for _, terrID in ipairs(transfer.terrIDs) do
            local ts = standing.Territories[terrID]
            if ts.IsNeutral or ts.OwnerPlayerID == playerID then
                local mod = WL.TerritoryModification.Create(terrID)
                mod.SetOwnerOpt = killerID
                mods[#mods + 1] = mod
            end
        end

        if #mods == 0 then goto continue end

        local loserName  = players[playerID].DisplayName(nil, false)
        local killerName = players[killerID].DisplayName(nil, false)
        local msg = loserName .. ' was eliminated. '
                    .. #mods .. ' of their territories have been transferred to '
                    .. killerName .. '.'

        addNewOrder(WL.GameOrderEvent.Create(
            killerID,
            msg,
            nil,
            mods,
            nil,
            nil
        ))

        ::continue::
    end
end
