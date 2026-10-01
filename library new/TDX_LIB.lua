local _recSettings = (getgenv and getgenv().TDX_RECORDER) or _G.TDX_RECORDER or {}
local SKIP_WAITS = _recSettings.SkipWaits == true
local SHOW_DEBUG_UI = _recSettings.DebugUI ~= false

local REBUILD_PRIORITY = { "EDJ", "Combat Medic", "Medic" }

local RETRY_DELAY = 3
local MIN_FIRE_GAP = 0.3
local MATCH_DISTANCE = 8
local IDLE_POLL = 0.01
local PLACE_MAX_ATTEMPTS = 6
local DEBUG_MAX = 1000

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
if not Remotes then error("[TDX] Remotes folder not found") end

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
local TowerReviveStateChanged = grab(Remotes, "TowerReviveStateChanged")

local _debugScroll
local _debugStatus
local _debugOrder = 0

local function createDebugUI()
    if not SHOW_DEBUG_UI then return end
    local ok, err = pcall(function()
        local parent
        if gethui then
            local okh, hui = pcall(gethui)
            if okh and hui then parent = hui end
        end
        if not parent then
            local okc, cg = pcall(function() return game:GetService("CoreGui") end)
            if okc and cg then parent = cg end
        end
        if not parent then
            parent = LocalPlayer:WaitForChild("PlayerGui")
        end

        local gui = Instance.new("ScreenGui")
        gui.Name = "TDX_DebugUI"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
        gui.Parent = parent

        local frame = Instance.new("Frame")
        frame.Name = "Panel"
        frame.Size = UDim2.new(0, 380, 0, 280)
        frame.Position = UDim2.new(1, -390, 0, 10)
        frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
        frame.BackgroundTransparency = 0.1
        frame.BorderSizePixel = 0
        frame.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(60, 60, 75)
        stroke.Thickness = 1
        stroke.Transparency = 0.3
        stroke.Parent = frame

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, -10, 0, 20)
        title.Position = UDim2.new(0, 6, 0, 4)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.Code
        title.Text = "TDX DEBUG"
        title.TextSize = 14
        title.TextColor3 = Color3.fromRGB(180, 210, 255)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = frame

        local status = Instance.new("TextLabel")
        status.Name = "Status"
        status.Size = UDim2.new(1, -12, 0, 16)
        status.Position = UDim2.new(0, 6, 0, 24)
        status.BackgroundTransparency = 1
        status.Font = Enum.Font.Code
        status.Text = "Status: idle"
        status.TextSize = 12
        status.TextColor3 = Color3.fromRGB(255, 220, 140)
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.TextTruncate = Enum.TextTruncate.AtEnd
        status.Parent = frame
        _debugStatus = status

        local scroll = Instance.new("ScrollingFrame")
        scroll.Name = "Log"
        scroll.Size = UDim2.new(1, -10, 1, -48)
        scroll.Position = UDim2.new(0, 5, 0, 43)
        scroll.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        scroll.BackgroundTransparency = 0.4
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 4
        scroll.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 110)
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.ScrollingDirection = Enum.ScrollingDirection.Y
        scroll.Parent = frame
        _debugScroll = scroll

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 2)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = scroll

        local padding = Instance.new("UIPadding")
        padding.PaddingTop = UDim.new(0, 3)
        padding.PaddingBottom = UDim.new(0, 3)
        padding.PaddingLeft = UDim.new(0, 4)
        padding.PaddingRight = UDim.new(0, 4)
        padding.Parent = scroll
    end)
    if not ok then
        warn("[TDX] debug UI failed:", err)
    end
end

local function setStatus(text)
    if _debugStatus then
        _debugStatus.Text = "Status: " .. tostring(text or "idle")
    end
end

local function pushDebug(text, color)
    if not _debugScroll then return end
    _debugOrder = _debugOrder + 1

    local label = Instance.new("TextLabel")
    label.Name = "Entry"
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -4, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Font = Enum.Font.Code
    label.TextSize = 12
    label.TextColor3 = color or Color3.fromRGB(200, 200, 210)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.TextWrapped = true
    label.LayoutOrder = _debugOrder
    label.Text = text
    label.Parent = _debugScroll

    local count = 0
    for _, c in ipairs(_debugScroll:GetChildren()) do
        if c:IsA("TextLabel") then count = count + 1 end
    end
    while count > DEBUG_MAX do
        local removed = false
        for _, c in ipairs(_debugScroll:GetChildren()) do
            if c:IsA("TextLabel") then
                c:Destroy()
                count = count - 1
                removed = true
                break
            end
        end
        if not removed then break end
    end

    task.defer(function()
        if _debugScroll then
            _debugScroll.CanvasPosition = Vector2.new(0, _debugScroll.AbsoluteCanvasSize.Y)
        end
    end)
end

local function nowStamp()
    local t = tick() % 86400
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = math.floor(t % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function fmt(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    return table.concat(parts, " ")
end

local function log(...)
    local msg = fmt(...)
    print("[TDX]", msg)
    pushDebug(nowStamp() .. " " .. msg, Color3.fromRGB(200, 210, 225))
end

local function warnUser(...)
    local msg = fmt(...)
    warn("[TDX]", msg)
    pushDebug(nowStamp() .. " ! " .. msg, Color3.fromRGB(255, 150, 150))
end

local function action(...)
    local msg = fmt(...)
    pushDebug(nowStamp() .. " > " .. msg, Color3.fromRGB(150, 230, 160))
end

local function retryMsg(...)
    local msg = fmt(...)
    pushDebug(nowStamp() .. " ~ " .. msg, Color3.fromRGB(255, 210, 130))
end

createDebugUI()

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
TDX._lastFire = {}
TDX._rebuildQueue = {}
TDX._rebuildWorkerRunning = false
TDX._placeLock = false

TDX._aliveWaiters = {}
TDX._levelWaiters = {}
TDX._targetWaiters = {}

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

local function priorityIndex(name)
    for i, n in ipairs(REBUILD_PRIORITY) do
        if n == name then return i end
    end
    return math.huge
end

local function queueAdd(slotId)
    for _, id in ipairs(TDX._rebuildQueue) do
        if id == slotId then return end
    end
    table.insert(TDX._rebuildQueue, slotId)
end

local function queueRemove(slotId)
    for i, id in ipairs(TDX._rebuildQueue) do
        if id == slotId then
            table.remove(TDX._rebuildQueue, i)
            return
        end
    end
end

local function queueSort()
    table.sort(TDX._rebuildQueue, function(a, b)
        local sa = TDX._slots[a]
        local sb = TDX._slots[b]
        if not sa and not sb then return a < b end
        if not sa then return false end
        if not sb then return true end
        local pa = priorityIndex(sa.name)
        local pb = priorityIndex(sb.name)
        if pa ~= pb then return pa < pb end
        return a < b
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

local function remapId(recorded)
    if recorded == nil then return nil end
    return TDX._idRemap[recorded] or recorded
end

local function resolveKey(tbl, key)
    local list = tbl[key]
    if not list then return end
    tbl[key] = nil
    for _, resolve in ipairs(list) do
        resolve(true)
    end
end

local function awaitEvent(tbl, key, timeout)
    local d = { done = false, result = nil, event = Instance.new("BindableEvent") }
    local function resolve(v)
        if d.done then return end
        d.done = true
        d.result = v
        d.event:Fire()
    end

    local list = tbl[key]
    if not list then
        list = {}
        tbl[key] = list
    end
    table.insert(list, resolve)

    if timeout then
        task.delay(math.max(0, timeout), resolve)
    end

    if not d.done then
        d.event.Event:Wait()
    end

    for i = #list, 1, -1 do
        if list[i] == resolve then
            table.remove(list, i)
        end
    end
    if #list == 0 and tbl[key] == list then
        tbl[key] = nil
    end

    return d.result
end

local function acquirePlaceLock()
    while TDX._placeLock do
        task.wait()
    end
    TDX._placeLock = true
end

local function releasePlaceLock()
    TDX._placeLock = false
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
                resolveKey(TDX._levelWaiters, id)
            end

            if username == LocalPlayer.Name and typeof(pos) == "Vector3" then
                for i = 1, #TDX._pendingPlaces do
                    local p = TDX._pendingPlaces[i]
                    if not p.id and p.name == name and typeof(p.pos) == "Vector3" then
                        if (p.pos - pos).Magnitude < MATCH_DISTANCE then
                            p.id = id
                            table.remove(TDX._pendingPlaces, i)
                            p.resolve(id)
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
                resolveKey(TDX._levelWaiters, hash)
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
                resolveKey(TDX._targetWaiters, hash)
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

local ensureWorker
local placeInternal
local restoreLevel

if TowerAliveStateChanged then
    TowerAliveStateChanged.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        local hash = tonumber(data.Hash)
        if hash == nil then return end

        if data.IsAlive == false then
            TDX._aliveState[hash] = false
            resolveKey(TDX._levelWaiters, hash)
            resolveKey(TDX._targetWaiters, hash)

            local slotId, slot = findSlotByActualId(hash)
            if not slotId or not slot or not slot.autoReplace then return end
            if slot.deadId == hash then return end

            local lvl = TDX._levelCache[hash] or { slot.lastT or 0, slot.lastB or 0 }
            slot.deathLevel = { lvl[1] or 0, lvl[2] or 0 }
            slot.deadId = hash
            slot.deathTime = tick()
            slot.reviving = false
            slot.awaitingRevive = false

            log(string.format("Slot %s (ID %s) died at %d/%d, queued for rebuild",
                tostring(slotId), tostring(hash), slot.deathLevel[1], slot.deathLevel[2]))

            queueAdd(slotId)
            ensureWorker()
        elseif data.IsAlive == true then
            TDX._aliveState[hash] = true
            local slotId, slot = findSlotByActualId(hash)
            if slotId and slot then
                if slot.deadId == hash then
                    log(string.format("Slot %s revived (ID %s)", tostring(slotId), tostring(hash)))
                    slot.deadId = nil
                    slot.deathLevel = nil
                    slot.deathTime = nil
                end
                slot.awaitingRevive = false
                slot.reviving = false
                queueRemove(slotId)
                resolveKey(TDX._aliveWaiters, slotId)
            end
        end
    end)
end

if TowerReviveStateChanged then
    TowerReviveStateChanged.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        local hash = tonumber(data.Hash)
        if hash == nil then return end

        local slotId, slot = findSlotByActualId(hash)
        if not slotId or not slot then return end

        if data.Reviving == true then
            slot.reviving = true
            slot.awaitingRevive = true
            queueRemove(slotId)
            log(string.format("Slot %s (ID %s) is reviving, rebuild cancelled",
                tostring(slotId), tostring(hash)))
        elseif data.Reviving == false then
            slot.reviving = false
            if slot.deadId == hash and TDX._aliveState[hash] == false then
                slot.awaitingRevive = false
                log(string.format("Slot %s (ID %s) revive failed, queued for rebuild",
                    tostring(slotId), tostring(hash)))
                queueAdd(slotId)
                ensureWorker()
            end
        end
    end)
end

local function slotReady(slot)
    return slot
        and slot.actualId
        and not slot.deadId
        and not slot.restoring
        and not slot.awaitingRevive
        and not slot.reviving
        and TDX._aliveState[slot.actualId] == true
end

local function awaitAlive(slotId)
    local announced = false
    while true do
        local slot = TDX._slots[slotId]
        if not slot then return nil end
        if slotReady(slot) then return slot.actualId end
        if not slot.autoReplace and not slot.actualId then return nil end
        if not slot.autoReplace and slot.actualId and TDX._aliveState[slot.actualId] == false then return nil end
        if not announced then
            setStatus("waiting on slot " .. tostring(slotId))
            action(string.format("waiting for slot %s to be ready", tostring(slotId)))
            announced = true
        end
        awaitEvent(TDX._aliveWaiters, slotId)
    end
end

local function awaitLevelChange(actualId, before, timeout)
    local deadline = tick() + (timeout or RETRY_DELAY)
    while true do
        local lvl = TDX._levelCache[actualId]
        if lvl and (lvl[1] > before[1] or lvl[2] > before[2]) then
            return lvl
        end
        if TDX._aliveState[actualId] == false then
            return nil
        end
        local remaining = deadline - tick()
        if remaining <= 0 then
            return nil
        end
        awaitEvent(TDX._levelWaiters, actualId, remaining)
    end
end

local function awaitTarget(actualId, queryType, timeout)
    local deadline = tick() + (timeout or RETRY_DELAY)
    while true do
        if TDX._targetCache[actualId] == queryType then return true end
        if TDX._aliveState[actualId] == false then return false end
        local remaining = deadline - tick()
        if remaining <= 0 then return false end
        awaitEvent(TDX._targetWaiters, actualId, remaining)
    end
end

ensureWorker = function()
    if TDX._rebuildWorkerRunning then return end
    TDX._rebuildWorkerRunning = true
    task.defer(function()
        while true do
            if #TDX._rebuildQueue == 0 then
                task.wait(IDLE_POLL)
            else
                queueSort()
                local sid = TDX._rebuildQueue[1]
                local s = TDX._slots[sid]

                if not s or not s.deadId or s.awaitingRevive or s.reviving or not s.autoReplace then
                    queueRemove(sid)
                elseif s.actualId ~= s.deadId then
                    log(string.format("Slot %s re-placed externally, dropping from queue", tostring(sid)))
                    s.deadId = nil
                    queueRemove(sid)
                else
                    local deadId = s.deadId
                    local targetT = s.deathLevel and s.deathLevel[1] or 0
                    local targetB = s.deathLevel and s.deathLevel[2] or 0

                    log(string.format("Auto-replacing slot %s: %s -> restore %d/%d",
                        tostring(sid), tostring(s.name), targetT, targetB))
                    setStatus("rebuilding slot " .. tostring(sid) .. " (" .. tostring(s.name) .. ")")
                    action(string.format("REBUILD slot %s %s", tostring(sid), tostring(s.name)))

                    local newId = placeInternal(s.name, s.pos, s.aim, s.rebuild)
                    local sl = TDX._slots[sid]

                    if not sl then
                        queueRemove(sid)
                    elseif sl.deadId ~= deadId or sl.actualId ~= deadId
                        or sl.awaitingRevive or sl.reviving then
                        log(string.format("Slot %s state changed during placement, cancelled",
                            tostring(sid)))
                        queueRemove(sid)
                    elseif newId then
                        TDX._idRemap[sid] = newId
                        TDX._aliveState[newId] = true
                        TDX._levelCache[newId] = { 0, 0 }
                        sl.actualId = newId
                        sl.deadId = nil
                        sl.deathLevel = nil
                        sl.deathTime = nil
                        sl.awaitingRevive = false
                        sl.reviving = false
                        sl.lastT = 0
                        sl.lastB = 0
                        queueRemove(sid)
                        resolveKey(TDX._aliveWaiters, sid)

                        log(string.format("Auto-replaced %s (slot %s -> ID %s)",
                            sl.name, tostring(sid), tostring(newId)))

                        if targetT > 0 or targetB > 0 then
                            sl.restoring = true
                            setStatus(string.format("restoring slot %s to %d/%d",
                                tostring(sid), targetT, targetB))
                            task.spawn(function()
                                local ok, err = pcall(restoreLevel, sid, targetT, targetB)
                                if not ok then warnUser("restoreLevel error:", err) end
                                local s2 = TDX._slots[sid]
                                if s2 then s2.restoring = false end
                                resolveKey(TDX._aliveWaiters, sid)
                            end)
                        end
                    else
                        log(string.format("Slot %s place failed (likely still alive/reviving), dropping from queue",
                            tostring(sid)))
                        if sl and sl.deadId == deadId then
                            sl.deadId = nil
                            sl.deathLevel = nil
                            sl.deathTime = nil
                        end
                        queueRemove(sid)
                    end
                end
            end
        end
    end)
end

placeInternal = function(name, pos, aim, rebuild)
    if not PlaceTower then return nil end

    local attempts = 0
    while attempts < PLACE_MAX_ATTEMPTS do
        attempts = attempts + 1
        acquirePlaceLock()

        local pending = { name = name, pos = pos, id = nil, resolve = nil }
        local _, resolve, await = (function()
            local d = { done = false, result = nil, event = Instance.new("BindableEvent") }
            return d,
                function(v)
                    if d.done then return end
                    d.done = true
                    d.result = v
                    d.event:Fire()
                end,
                function()
                    if d.done then return d.result end
                    d.event.Event:Wait()
                    return d.result
                end
        end)()
        pending.resolve = resolve
        table.insert(TDX._pendingPlaces, pending)

        local timerArg = workspace:GetServerTimeNow()
        local ok2, res = pcall(function()
            if aim and typeof(aim) == "Vector3" then
                return PlaceTower:InvokeServer(timerArg, name, pos, rebuild and 1 or 0, aim)
            end
            return PlaceTower:InvokeServer(timerArg, name, pos, rebuild and 1 or 0)
        end)

        releasePlaceLock()

        if ok2 and res == true then
            local id = await()
            if id then return id end
            for i, p in ipairs(TDX._pendingPlaces) do
                if p == pending then table.remove(TDX._pendingPlaces, i) break end
            end
            return nil
        end

        for i, p in ipairs(TDX._pendingPlaces) do
            if p == pending then table.remove(TDX._pendingPlaces, i) break end
        end
        warnUser(string.format("Place rejected for %s (result %s), attempt %d/%d",
            tostring(name), tostring(res), attempts, PLACE_MAX_ATTEMPTS))
        if attempts < PLACE_MAX_ATTEMPTS then
            task.wait(RETRY_DELAY)
        end
    end
    return nil
end

restoreLevel = function(slotId, targetT, targetB)
    local slot = TDX._slots[slotId]
    if not slot then return false end
    local actual = slot.actualId

    while true do
        local s = TDX._slots[slotId]
        if not s or s.actualId ~= actual then return false end

        local lvl = TDX._levelCache[actual] or { 0, 0 }
        if lvl[1] >= targetT and lvl[2] >= targetB then return true end

        local patch, need
        if lvl[1] < targetT then
            patch, need = 1, targetT - lvl[1]
        else
            patch, need = 2, targetB - lvl[2]
        end

        waitMinFireGap("upgrade_" .. tostring(actual))
        markFire("upgrade_" .. tostring(actual))
        pcall(function() TowerUpgradeRequest:FireServer(actual, patch, need) end)

        local after = awaitLevelChange(actual, lvl, RETRY_DELAY)
        if not after and TDX._aliveState[actual] == false then
            return false
        end
    end
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

    setStatus("placing " .. name .. " (slot " .. tostring(slotId) .. ")")
    action(string.format("PLACE %s slot=%s rebuild=%s", name, tostring(slotId), tostring(rebuild)))

    local existing = TDX._slots[slotId]
    if existing then
        if existing.deadId then
            existing.deadId = nil
            existing.deathLevel = nil
            existing.deathTime = nil
            existing.awaitingRevive = false
            existing.reviving = false
            queueRemove(slotId)
            log(string.format("Slot %s rebuild cancelled by explicit place", tostring(slotId)))
        end
        if existing.actualId and TDX._aliveState[existing.actualId] == true then
            log(string.format("Slot %s already alive (ID %s), skipping place",
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
        deadId = nil,
        lastT = 0,
        lastB = 0,
        deathLevel = nil,
        deathTime = nil,
        restoring = false,
        reviving = false,
        awaitingRevive = false,
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

    action(string.format("UPGRADE slot=%s patch=%d count=%d", tostring(hash), patch, count))

    local attempts = 0
    while true do
        attempts = attempts + 1
        local actual = awaitAlive(hash)
        if not actual then
            warnUser("Upgrade: slot " .. tostring(hash) .. " is gone")
            return false
        end

        local before = TDX._levelCache[actual] or { 0, 0 }
        local cur = before[patch] or 0
        local target = cur + count
        if cur >= target then return true end

        setStatus(string.format("upgrading ID %s patch %d (%d/%d)",
            tostring(actual), patch, before[1], before[2]))
        waitMinFireGap("upgrade_" .. tostring(actual))
        markFire("upgrade_" .. tostring(actual))

        pcall(function()
            TowerUpgradeRequest:FireServer(actual, patch, target - cur)
        end)

        local after = awaitLevelChange(actual, before, RETRY_DELAY)
        if after then
            local newCur = after[patch] or 0
            if newCur >= target then return true end
            count = target - newCur
            attempts = 0
        elseif TDX._aliveState[actual] == false then
            retryMsg(string.format("ID %s died mid-upgrade, awaiting rebuild", tostring(actual)))
            attempts = 0
        else
            retryMsg(string.format("ID %s patch %d not confirmed, retry #%d",
                tostring(actual), patch, attempts))
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
    if actual == nil then return false end

    action("SELL slot=" .. tostring(hash) .. " ID=" .. tostring(actual))
    pcall(function() SellTower:FireServer(actual) end)

    TDX._levelCache[actual] = nil
    TDX._targetCache[actual] = nil
    TDX._aliveState[actual] = false
    resolveKey(TDX._levelWaiters, actual)
    resolveKey(TDX._targetWaiters, actual)

    local slotId, slot = findSlotByActualId(actual)
    if slotId and slot then
        slot.deadId = nil
        slot.deathLevel = nil
        slot.deathTime = nil
        slot.awaitingRevive = false
        slot.reviving = false
        slot.autoReplace = false
        queueRemove(slotId)
        resolveKey(TDX._aliveWaiters, slotId)
    end

    return true
end

function TDX:Skip(wave)
    if not SkipWaveVoteCast then
        warnUser("SkipWaveVoteCast remote missing")
        return false
    end

    action("SKIP wave")
    while not TDX._skipSuccess do
        waitMinFireGap("skip")
        markFire("skip")
        pcall(function() SkipWaveVoteCast:FireServer(true) end)
        task.wait(RETRY_DELAY)
    end

    TDX._skipSuccess = false
    return true
end

function TDX:Ability(hash, slot, pos)
    hash = tonumber(hash) or hash
    slot = tonumber(slot) or 1

    if not TowerUseAbilityRequest then
        warnUser("TowerUseAbilityRequest remote missing")
        return false
    end

    action(string.format("ABILITY slot=%s ability=%d", tostring(hash), slot))

    while true do
        local actual = awaitAlive(hash)
        if not actual then return false end

        waitMinFireGap("ability_" .. tostring(actual))
        markFire("ability_" .. tostring(actual))

        local ok, result = pcall(function()
            if pos and typeof(pos) == "Vector3" then
                return TowerUseAbilityRequest:InvokeServer(actual, slot, pos)
            end
            return TowerUseAbilityRequest:InvokeServer(actual, slot)
        end)

        if ok and result == true then return true end
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

    action("RETARGET slot=" .. tostring(hash))

    while true do
        local actual = awaitAlive(hash)
        if not actual then return false end

        waitMinFireGap("retarget_" .. tostring(actual))
        markFire("retarget_" .. tostring(actual))

        local ok, result = pcall(function()
            return RetargetTower:InvokeServer(actual, pos)
        end)

        if ok and result == true then return true end
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

    action(string.format("TARGET slot=%s type=%d", tostring(hash), queryType))

    local attempts = 0
    while true do
        attempts = attempts + 1
        local actual = awaitAlive(hash)
        if not actual then return false end

        if TDX._targetCache[actual] == queryType then return true end

        waitMinFireGap("target_" .. tostring(actual))
        markFire("target_" .. tostring(actual))

        pcall(function()
            ChangeQueryType:FireServer(actual, queryType)
        end)

        if awaitTarget(actual, queryType, RETRY_DELAY) then
            return true
        end

        if TDX._aliveState[actual] == false then
            retryMsg(string.format("ID %s died mid-target, awaiting rebuild", tostring(actual)))
            attempts = 0
        else
            retryMsg(string.format("ID %s target %d not confirmed, retry #%d",
                tostring(actual), queryType, attempts))
        end
    end
end

function TDX:Mode(mode)
    local net = ReplicatedStorage:FindFirstChild("Network") or ReplicatedStorage:FindFirstChild("Remotes")
    if net then
        local partyType = net:FindFirstChild("ClientChangePartyTypeRequest")
        local partyMap = net:FindFirstChild("ClientChangePartyMapRequest")
        if partyType and partyMap then
            partyType:FireServer("Party")
            task.wait(0.5)
            partyMap:FireServer(mode)
            task.wait(0.5)
            TDX:StartMatchmaking()
        end
    end
end

function TDX:StartMatchmaking()
    local net = ReplicatedStorage:FindFirstChild("Network") or ReplicatedStorage:FindFirstChild("Remotes")
    if net then
        local start = net:FindFirstChild("ClientStartGameRequest")
        if start then
            start:FireServer()
        end
    end
    task.wait(0.5)
end

function TDX:Loadout(id)
    task.wait(2)
    local load = getRemote("LoadoutSelectionChanged")
    if load then
        load:FireServer(id)
    end
    task.wait(0.5)
end

function TDX:VoteDifficulty(diff)
    task.wait(5.5)
    local vote = getRemote("DifficultyVoteCast")
    if vote then
        vote:FireServer(diff)
    end
    task.wait(0.5)
    local ready = getRemote("DifficultyVoteReady")
    if ready then
        ready:FireServer(diff)
    end
    task.wait(1)
end

function TDX:VoteMap(map, attempts)
    attempts = attempts or 10
    for _ = 1, attempts do
        local vote = getRemote("MapVoteCast")
        if vote then
            vote:FireServer(map)
            task.wait(0.5)
            TDX:Ready()
            return true
        end
        local change = getRemote("MapChangeVoteCast")
        if change then
            change:FireServer(true)
        end
        task.wait(1)
    end
    return false
end

function TDX:Ready()
    local ready = getRemote("MapVoteReady")
    if ready then
        ready:FireServer()
    end
    task.wait(0.3)
end

function TDX:Equip(items)
    local net = ReplicatedStorage:FindFirstChild("Network") or ReplicatedStorage:FindFirstChild("Remotes")
    if net then
        local eq = net:FindFirstChild("UpdateLoadout")
        if eq then
            eq:FireServer(items)
        end
    end
    task.wait(0.5)
end

function TDX:ForceRebuild(slotId)
    slotId = tonumber(slotId)
    if not slotId then return false end
    local slot = TDX._slots[slotId]
    if not slot then return false end
    slot.awaitingRevive = false
    slot.reviving = false
    if slot.deadId then
        action("FORCE REBUILD slot=" .. tostring(slotId))
        queueAdd(slotId)
        ensureWorker()
        return true
    end
    return false
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
        rebuildQueue = TDX._rebuildQueue,
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
    TDX._lastFire = {}
    TDX._rebuildQueue = {}
    TDX._aliveWaiters = {}
    TDX._levelWaiters = {}
    TDX._targetWaiters = {}
    TDX._placeLock = false
end

if getgenv then getgenv().TDX = TDX end
_G.TDX = TDX

if SKIP_WAITS then
    log("Library loaded. Waits will be skipped.")
else
    log("Library loaded. Waits will be honored.")
end

return TDX