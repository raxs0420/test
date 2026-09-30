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

local RETRY_DELAY = 1
local POLL_INTERVAL = 0.05
local FACTORY_TIMEOUT = 8
local MATCH_DISTANCE = 8

local TDX = {}

TDX._levelCache = {}
TDX._targetCache = {}
TDX._placeHistory = {}
TDX._idRemap = {}
TDX._placeCount = 0
TDX._pendingPlaces = {}
TDX._skipSuccess = false

local function log(...)
    print("[TDX]", ...)
end

local function warnUser(...)
    warn("[TDX]", ...)
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

            if id and type(lvl) == "table" then
                TDX._levelCache[id] = { lvl[1] or 0, lvl[2] or 0 }
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
                TDX._levelCache[item.Hash] = { lvl[1] or 0, lvl[2] or 0 }
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

    local timerArg = workspace:GetServerTimeNow()
    local pending = { name = name, pos = pos, resolved = false, id = nil }
    table.insert(TDX._pendingPlaces, pending)

    while true do
        local ok, result = pcall(function()
            if aim and typeof(aim) == "Vector3" then
                return PlaceTower:InvokeServer(timerArg, name, pos, rebuild and 1 or 0, aim)
            end
            return PlaceTower:InvokeServer(timerArg, name, pos, rebuild and 1 or 0)
        end)

        if ok and result == true then
            break
        end

        task.wait(RETRY_DELAY)
    end

    local start = tick()
    while not pending.resolved and tick() - start < FACTORY_TIMEOUT do
        task.wait(0.05)
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

    TDX._placeCount = TDX._placeCount + 1
    TDX._idRemap[slotId] = pending.id
    TDX._placeHistory[slotId] = {
        name = name,
        actualId = pending.id,
        recordedId = slotId,
    }
    log(string.format("Placed %s (recorded ID %s -> actual %s)", name, tostring(slotId), tostring(pending.id)))
    return pending.id
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
    local before = TDX._levelCache[actual] or { 0, 0 }
    local expectT = before[1] + (patch == 1 and count or 0)
    local expectB = before[2] + (patch == 2 and count or 0)

    while true do
        local lvl = TDX._levelCache[actual]
        if lvl and lvl[1] >= expectT and lvl[2] >= expectB then
            return true
        end

        pcall(function()
            TowerUpgradeRequest:FireServer(actual, patch, count)
        end)

        local waitStart = tick()
        while tick() - waitStart < RETRY_DELAY do
            local cur = TDX._levelCache[actual]
            if cur and cur[1] >= expectT and cur[2] >= expectB then
                return true
            end
            task.wait(POLL_INTERVAL)
        end
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

    task.wait(RETRY_DELAY)
    TDX._levelCache[actual] = nil
    TDX._targetCache[actual] = nil
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

        pcall(function()
            SkipWaveVoteCast:FireServer(true)
        end)

        local waitStart = tick()
        while tick() - waitStart < RETRY_DELAY do
            if TDX._skipSuccess then return true end
            task.wait(POLL_INTERVAL)
        end
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

        pcall(function()
            ChangeQueryType:FireServer(actual, queryType)
        end)

        local waitStart = tick()
        while tick() - waitStart < RETRY_DELAY do
            if TDX._targetCache[actual] == queryType then
                return true
            end
            task.wait(POLL_INTERVAL)
        end
    end
end

function TDX:GetStatus()
    return {
        placeCount = TDX._placeCount,
        placeHistory = TDX._placeHistory,
        idRemap = TDX._idRemap,
        levelCache = TDX._levelCache,
        targetCache = TDX._targetCache,
    }
end

function TDX:Reset()
    TDX._levelCache = {}
    TDX._targetCache = {}
    TDX._placeHistory = {}
    TDX._idRemap = {}
    TDX._placeCount = 0
    TDX._pendingPlaces = {}
end

if getgenv then getgenv().TDX = TDX end
_G.TDX = TDX

if SKIP_WAITS then
    log("Library loaded. Waits will be skipped.")
else
    log("Library loaded. Waits will be honored.")
end

return TDX