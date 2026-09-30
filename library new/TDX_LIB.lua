local _recSettings = (getgenv and getgenv().TDX_RECORDER) or _G.TDX_RECORDER or {}
local SKIP_WAITS = _recSettings.SkipWaits == true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local function grab(parent, name, timeout)
    local c = parent:FindFirstChild(name)
    if c then return c end
    local ok, res = pcall(function() return parent:WaitForChild(name, timeout or 15) end)
    return ok and res or nil
end

local Remotes = grab(ReplicatedStorage, "Remotes", 30)
if not Remotes then
    error("[TDX] Remotes folder not found")
end

local PlaceTower = grab(Remotes, "PlaceTower")
local TowerUpgradeRequest = grab(Remotes, "TowerUpgradeRequest")
local TowerUpgradeQueueUpdated = grab(Remotes, "TowerUpgradeQueueUpdated")
local TowerFactoryQueueUpdated = grab(Remotes, "TowerFactoryQueueUpdated")
local SellTower = grab(Remotes, "SellTower")
local TowerUseAbilityRequest = grab(Remotes, "TowerUseAbilityRequest")
local SkipWaveVoteCast = grab(Remotes, "SkipWaveVoteCast")
local SkipWaveVoteStateUpdate = grab(Remotes, "SkipWaveVoteStateUpdate")
local RetargetTower = grab(Remotes, "RetargetTower")
local ChangeQueryType = grab(Remotes, "ChangeQueryType")
local TowerQueryTypeIndexChanged = grab(Remotes, "TowerQueryTypeIndexChanged")
local TowerAliveStateChanged = grab(Remotes, "TowerAliveStateChanged")

local RETRY_DELAY = 2
local MIN_FIRE_GAP = 0.2
local POLL_INTERVAL = 0.01
local FACTORY_TIMEOUT = 8
local MATCH_DISTANCE = 8
local REVIVE_WAIT = 8
local SELL_DELAY = 1
local PLACE_RETRY_CAP = 3

local TDX = {}

TDX._levelCache = {}
TDX._targetCache = {}
TDX._aliveState = {}
TDX._slots = {}
TDX._placeHistory = {}
TDX._idRemap = {}
TDX._placeCount = 0
TDX._pendingPlaces = {}
TDX._skipSuccess = false
TDX._pendingUpgrades = {}
TDX._lastFire = {}

local function log(...)
    print("[TDX]", ...)
end

local function warnUser(...)
    warn("[TDX]", ...)
end

local function waitMinFireGap(key)
    local last = TDX._lastFire[key]
    if last then
        local elapsed = tick() - last
        if elapsed < MIN_FIRE_GAP then
            task.wait(MIN_FIRE_GAP - elapsed)
        end
    end
end

local function markFire(key)
    TDX._lastFire[key] = tick()
end

if TowerFactoryQueueUpdated then
    TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        for _, item in ipairs(data) do
            if type(item) ~= "table" or not item.Creation then continue end
            if type(item.Data) ~= "table" then continue end
            local info = item.Data[1]
            if type(info) ~= "table" then continue end

            local id = info[1]
            local name = info[2]
            local pos = info[4]
            local username = info[7]
            local lvl = info[8]

            if id ~= nil then
                TDX._aliveState[id] = true
                if type(lvl) == "table" then
                    TDX._levelCache[id] = { lvl[1] or 0, lvl[2] or 0 }
                end
            end

            if username == LocalPlayer.Name and typeof(pos) == "Vector3" then
                for i = #TDX._pendingPlaces, 1, -1 do
                    local p = TDX._pendingPlaces[i]
                    if not p.resolved and p.name == name and typeof(p.pos) == "Vector3" then
                        if (p.pos - pos).Magnitude < MATCH_DISTANCE then
                            p.resolved = true
                            p.id = id
                            table.remove(TDX._pendingPlaces, i)
                            break
                        end
                    end
                end
            end
        end
    end)
end

if TowerUpgradeQueueUpdated then
    TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        for _, item in ipairs(data) do
            if type(item) == "table" and item.Hash and type(item.LevelReplicationData) == "table" then
                local lvl = item.LevelReplicationData
                local hash = item.Hash
                TDX._levelCache[hash] = { lvl[1] or 0, lvl[2] or 0 }
                for _, slot in pairs(TDX._slots) do
                    if slot.actualId == hash then
                        slot.lastT = lvl[1] or 0
                        slot.lastB = lvl[2] or 0
                        break
                    end
                end
            end
        end
    end)
end

if TowerQueryTypeIndexChanged then
    TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        for _, entry in ipairs(data) do
            local hash, newType
            local ok = pcall(function()
                hash = entry.X
                newType = entry.Y
            end)
            if ok and hash and newType then
                TDX._targetCache[hash] = newType
            end
        end
    end)
end

if SkipWaveVoteStateUpdate then
    SkipWaveVoteStateUpdate.OnClientEvent:Connect(function(state)
        if type(state) ~= "table" then return end
        local yes = tonumber(state.YesVotes)
        if yes and yes >= 1 then
            TDX._skipSuccess = true
        end
    end)
end

local function findSlotByActualId(actualId)
    for slotId, slot in pairs(TDX._slots) do
        if slot.actualId == actualId then
            return slotId, slot
        end
    end
    return nil, nil
end

local performAutoReplace

local function scheduleAutoReplace(slotId, hash)
    local slot = TDX._slots[slotId]
    if not slot then return end
    if not slot.autoReplace then
        log(string.format("Slot %s (ID %s) died, auto-replace disabled", tostring(slotId), tostring(hash)))
        return
    end
    if slot.replaceScheduled then return end

    local lvl = TDX._levelCache[hash] or { slot.lastT or 0, slot.lastB or 0 }
    slot.deathLevel = { lvl[1] or 0, lvl[2] or 0 }
    slot.replaceScheduled = true
    slot.deathTime = tick()

    log(string.format("Slot %s (ID %s) died at %d/%d, replacing in %ds",
        tostring(slotId), tostring(hash), slot.deathLevel[1], slot.deathLevel[2], REVIVE_WAIT))

    task.spawn(function()
        task.wait(REVIVE_WAIT)
        local s = TDX._slots[slotId]
        if not s then return end
        if not s.replaceScheduled then return end
        if s.actualId ~= hash then return end
        s.replaceScheduled = false
        performAutoReplace(slotId)
    end)
end

if TowerAliveStateChanged then
    TowerAliveStateChanged.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        local hash = tonumber(data.Hash)
        if hash == nil then return end

        if data.IsAlive == false then
            TDX._aliveState[hash] = false
            local slotId = findSlotByActualId(hash)
            if slotId then
                scheduleAutoReplace(slotId, hash)
            end
        elseif data.IsAlive == true then
            TDX._aliveState[hash] = true
        end
    end)
end

local function remapId(recorded)
    if recorded == nil then return nil end
    return TDX._idRemap[recorded] or recorded
end

function TDX:Wait(seconds)
    if SKIP_WAITS then return end
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return end
    local target = workspace:GetServerTimeNow() + seconds
    while workspace:GetServerTimeNow() < target do
        task.wait(0.02)
    end
end

local function placeInternal(name, pos, aim, rebuild)
    if not PlaceTower then return nil end

    local pending = { name = name, pos = pos, resolved = false, id = nil }
    table.insert(TDX._pendingPlaces, pending)

    local attempts = 0
    while attempts < PLACE_RETRY_CAP do
        attempts = attempts + 1
        local timerArg = workspace:GetServerTimeNow()
        local ok, result = pcall(function()
            if aim and typeof(aim) == "Vector3" then
                return PlaceTower:InvokeServer(timerArg, name, pos, rebuild and 1 or 0, aim)
            end
            return PlaceTower:InvokeServer(timerArg, name, pos, rebuild and 1 or 0)
        end)

        if ok and result == true then break end

        if attempts < PLACE_RETRY_CAP then
            task.wait(RETRY_DELAY)
        end
    end

    if attempts >= PLACE_RETRY_CAP and not pending.resolved then
        for i, p in ipairs(TDX._pendingPlaces) do
            if p == pending then
                table.remove(TDX._pendingPlaces, i)
                break
            end
        end
        return nil
    end

    local start = tick()
    while not pending.resolved and tick() - start < FACTORY_TIMEOUT do
        task.wait(POLL_INTERVAL)
    end

    for i, p in ipairs(TDX._pendingPlaces) do
        if p == pending then
            table.remove(TDX._pendingPlaces, i)
            break
        end
    end

    if not pending.resolved then
        warnUser("Place succeeded but no factory confirm:", name)
        return nil
    end
    return pending.id
end

performAutoReplace = function(slotId)
    local slot = TDX._slots[slotId]
    if not slot then return end
    if slot.autoReplacing then return end

    slot.autoReplacing = true

    local targetT = slot.deathLevel and slot.deathLevel[1] or 0
    local targetB = slot.deathLevel and slot.deathLevel[2] or 0

    log(string.format("Auto-replacing slot %s: %s -> restore %d/%d",
        tostring(slotId), tostring(slot.name), targetT, targetB))

    local newId = placeInternal(slot.name, slot.pos, slot.aim, slot.rebuild)
    if not newId then
        warnUser("Auto-replace failed for slot", slotId, "(slot likely occupied)")
        slot.autoReplacing = false
        return
    end

    TDX._idRemap[slotId] = newId
    TDX._aliveState[newId] = true
    TDX._levelCache[newId] = { 0, 0 }
    slot.actualId = newId
    slot.lastT = 0
    slot.lastB = 0
    slot.autoReplacing = false

    log(string.format("Auto-replace placed %s (slot %s -> new ID %s)", slot.name, tostring(slotId), tostring(newId)))

    if targetT > 0 then
        task.spawn(function()
            TDX:Upgrade(slotId, 1, targetT)
            log(string.format("Auto-replace slot %s restored top to %d", tostring(slotId), targetT))
        end)
    end
    if targetB > 0 then
        task.spawn(function()
            TDX:Upgrade(slotId, 2, targetB)
            log(string.format("Auto-replace slot %s restored bottom to %d", tostring(slotId), targetB))
        end)
    end
end

function TDX:Place(name, timer, pos, rebuild, aim, slotId)
    name = tostring(name or "Unknown")
    timer = tonumber(timer) or 0
    rebuild = (rebuild == true)

    if not PlaceTower then
        warnUser("PlaceTower remote missing")
        return nil
    end
    if typeof(pos) ~= "Vector3" then
        warnUser("Place: pos must be Vector3")
        return nil
    end

    slotId = tonumber(slotId)
    if slotId == nil then
        slotId = TDX._placeCount + 1
    end

    local existing = TDX._slots[slotId]
    if existing then
        if existing.replaceScheduled then
            existing.replaceScheduled = false
            log(string.format("Slot %s auto-replace cancelled by explicit place", tostring(slotId)))
        end
        if existing.actualId and TDX._aliveState[existing.actualId] == true then
            log(string.format("Slot %s already alive (ID %s), skipping explicit place",
                tostring(slotId), tostring(existing.actualId)))
            return existing.actualId
        end
    end

    local newId = placeInternal(name, pos, aim, rebuild)
    if not newId then
        warnUser("Place failed:", name)
        return nil
    end

    TDX._placeCount = TDX._placeCount + 1
    TDX._idRemap[slotId] = newId
    TDX._aliveState[newId] = true
    TDX._levelCache[newId] = { 0, 0 }

    TDX._slots[slotId] = {
        name = name,
        pos = pos,
        aim = aim,
        rebuild = rebuild,
        autoReplace = rebuild,
        actualId = newId,
        lastT = 0,
        lastB = 0,
        replaceScheduled = false,
        autoReplacing = false,
    }

    TDX._placeHistory[slotId] = {
        name = name,
        actualId = newId,
        recordedId = slotId,
    }

    log(string.format("Placed %s (slot %s -> ID %s, auto-replace %s)",
        name, tostring(slotId), tostring(newId), tostring(rebuild)))
    return newId
end

function TDX:Upgrade(hash, patch, count)
    hash = tonumber(hash) or hash
    patch = tonumber(patch) or 1
    count = tonumber(count) or 1

    if not TowerUpgradeRequest then
        warnUser("TowerUpgradeRequest remote missing")
        return false
    end

    local actual = remapId(hash)

    while true do
        while TDX._pendingUpgrades[actual] and TDX._pendingUpgrades[actual] > 0 do
            task.wait(POLL_INTERVAL)
        end

        local before = TDX._levelCache[actual] or { 0, 0 }
        local expectT = before[1] + (patch == 1 and count or 0)
        local expectB = before[2] + (patch == 2 and count or 0)

        if before[1] >= expectT and before[2] >= expectB then
            return true
        end

        waitMinFireGap("upgrade_" .. tostring(actual))

        TDX._pendingUpgrades[actual] = (TDX._pendingUpgrades[actual] or 0) + 1
        markFire("upgrade_" .. tostring(actual))

        pcall(function()
            TowerUpgradeRequest:FireServer(actual, patch, count)
        end)

        local start = tick()
        local confirmed = false
        while tick() - start < RETRY_DELAY do
            local lvl = TDX._levelCache[actual]
            if lvl and lvl[1] >= expectT and lvl[2] >= expectB then
                confirmed = true
                break
            end
            task.wait(POLL_INTERVAL)
        end

        TDX._pendingUpgrades[actual] = math.max(0, (TDX._pendingUpgrades[actual] or 1) - 1)

        if confirmed then
            return true
        end

        warnUser("Upgrade not confirmed within " .. RETRY_DELAY .. "s on ID", actual, "- retrying")
    end
end

function TDX:Sell(hash)
    hash = tonumber(hash) or hash

    if not SellTower then
        warnUser("SellTower remote missing")
        return false
    end

    local actual = remapId(hash)

    pcall(function()
        SellTower:FireServer(actual)
    end)

    task.wait(SELL_DELAY)
    TDX._levelCache[actual] = nil
    TDX._targetCache[actual] = nil
    TDX._aliveState[actual] = false

    local slotId, slot = findSlotByActualId(actual)
    if slotId and slot then
        slot.replaceScheduled = false
        slot.autoReplace = false
    end

    return true
end

function TDX:Skip(wave)
    wave = tonumber(wave)

    if not SkipWaveVoteCast then
        warnUser("SkipWaveVoteCast remote missing")
        return false
    end

    while true do
        if TDX._skipSuccess then return true end

        TDX._skipSuccess = false

        waitMinFireGap("skip")
        markFire("skip")

        pcall(function()
            SkipWaveVoteCast:FireServer(true)
        end)

        local start = tick()
        local confirmed = false
        while tick() - start < RETRY_DELAY do
            if TDX._skipSuccess then
                confirmed = true
                break
            end
            task.wait(POLL_INTERVAL)
        end

        if confirmed then
            return true
        end

        warnUser("Skip not confirmed within " .. RETRY_DELAY .. "s - retrying")
    end
end

function TDX:Ability(hash, slot, pos)
    hash = tonumber(hash) or hash
    slot = tonumber(slot) or 1

    if not TowerUseAbilityRequest then
        warnUser("TowerUseAbilityRequest remote missing")
        return false
    end

    local actual = remapId(hash)

    while true do
        waitMinFireGap("ability_" .. tostring(actual))
        markFire("ability_" .. tostring(actual))

        local ok, result = pcall(function()
            if pos and typeof(pos) == "Vector3" then
                return TowerUseAbilityRequest:InvokeServer(actual, slot, pos)
            end
            return TowerUseAbilityRequest:InvokeServer(actual, slot)
        end)

        if ok and result == true then
            return true
        end

        task.wait(RETRY_DELAY)
    end
end

function TDX:Retarget(hash, pos)
    hash = tonumber(hash) or hash

    if not RetargetTower then
        warnUser("RetargetTower remote missing")
        return false
    end
    if typeof(pos) ~= "Vector3" then
        warnUser("Retarget: pos must be Vector3")
        return false
    end

    local actual = remapId(hash)

    while true do
        waitMinFireGap("retarget_" .. tostring(actual))
        markFire("retarget_" .. tostring(actual))

        local ok, result = pcall(function()
            return RetargetTower:InvokeServer(actual, pos)
        end)

        if ok and result == true then
            return true
        end

        task.wait(RETRY_DELAY)
    end
end

function TDX:Target(hash, queryType)
    hash = tonumber(hash) or hash
    queryType = tonumber(queryType) or 0

    if not ChangeQueryType then
        warnUser("ChangeQueryType remote missing")
        return false
    end

    local actual = remapId(hash)

    while true do
        if TDX._targetCache[actual] == queryType then
            return true
        end

        waitMinFireGap("target_" .. tostring(actual))
        markFire("target_" .. tostring(actual))

        pcall(function()
            ChangeQueryType:FireServer(actual, queryType)
        end)

        local start = tick()
        local confirmed = false
        while tick() - start < RETRY_DELAY do
            if TDX._targetCache[actual] == queryType then
                confirmed = true
                break
            end
            task.wait(POLL_INTERVAL)
        end

        if confirmed then
            return true
        end

        warnUser("Target not confirmed within " .. RETRY_DELAY .. "s on ID", actual, "- retrying")
    end
end

function TDX:GetStatus()
    return {
        placeCount = TDX._placeCount,
        placeHistory = TDX._placeHistory,
        idRemap = TDX._idRemap,
        levelCache = TDX._levelCache,
        targetCache = TDX._targetCache,
        aliveState = TDX._aliveState,
        slots = TDX._slots,
    }
end

function TDX:Reset()
    TDX._levelCache = {}
    TDX._targetCache = {}
    TDX._aliveState = {}
    TDX._slots = {}
    TDX._placeHistory = {}
    TDX._idRemap = {}
    TDX._placeCount = 0
    TDX._pendingPlaces = {}
    TDX._pendingUpgrades = {}
    TDX._lastFire = {}
end

if getgenv then getgenv().TDX = TDX end
_G.TDX = TDX

if SKIP_WAITS then
    log("Library loaded. Waits will be skipped.")
else
    log("Library loaded. Waits will be honored.")
end

return TDX