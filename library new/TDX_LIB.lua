local _recSettings = (getgenv and getgenv().TDX_RECORDER) or _G.TDX_RECORDER or {}
local SKIP_WAITS = _recSettings.SkipWaits == true
local SHOW_DEBUG_UI = _recSettings.DebugUI ~= false
local AUTO_REJOIN = _recSettings.AutoRejoin ~= false

local REBUILD_PRIORITY = { "EDJ", "Combat Medic", "Medic", "Commander" }

local RETRY_DELAY = 3
local RESTORE_AWAIT = 1
local MIN_FIRE_GAP = 0.3
local MATCH_DISTANCE = 0.01
local COLLISION_DISTANCE = 0.2
local IDLE_POLL = 0.01
local PLACE_MAX_ATTEMPTS = 5
local DEBUG_MAX = 1000
local REBUILD_WAIT = 7
local MAX_PATH_LEVEL = 5
local VOID_REBUILD_DELAY = 1.5
local INTERNAL_SELL_FLUSH = 0.1

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local function grab(parent, name, timeout)
    local c = parent:FindFirstChild(name)
    if c then return c end
    local ok, res = pcall(function() return parent:WaitForChild(name, timeout or 15) end)
    return ok and res or nil
end

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
    Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
    if not Remotes then error("[TDX] Remotes folder not found") end
end

local PlaceTower = Remotes:FindFirstChild("PlaceTower")
local TowerUpgradeRequest = Remotes:FindFirstChild("TowerUpgradeRequest")
local TowerUpgradeQueueUpdated = Remotes:FindFirstChild("TowerUpgradeQueueUpdated")
local TowerFactoryQueueUpdated = Remotes:FindFirstChild("TowerFactoryQueueUpdated")
local SellTower = Remotes:FindFirstChild("SellTower")
local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
local SkipWaveVoteCast = Remotes:FindFirstChild("SkipWaveVoteCast")
local SkipWaveVoteStateUpdate = Remotes:FindFirstChild("SkipWaveVoteStateUpdate")
local RetargetTower = Remotes:FindFirstChild("RetargetTower")
local ChangeQueryType = Remotes:FindFirstChild("ChangeQueryType")
local TowerQueryTypeIndexChanged = Remotes:FindFirstChild("TowerQueryTypeIndexChanged")
local TowerAliveStateChanged = Remotes:FindFirstChild("TowerAliveStateChanged")
local EnemyUsedAbility = Remotes:FindFirstChild("EnemyUsedAbility")

local _debugScroll
local _debugStatus
local _debugOrder = 0
local _lastDedupKey = nil
local _lastDedupLabel = nil
local _lastDedupBaseText = nil
local _lastDedupCount = 0

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

local function pushDebug(text, color, dedupKey)
    if not _debugScroll then return end

    if dedupKey and _lastDedupKey == dedupKey and _lastDedupLabel then
        _lastDedupCount = _lastDedupCount + 1
        _lastDedupLabel.Text = _lastDedupBaseText .. string.format("  [%dx]", _lastDedupCount)
        return
    end

    local wasAtBottom = true
    local maxY = _debugScroll.AbsoluteCanvasSize.Y - _debugScroll.AbsoluteWindowSize.Y
    if maxY > 0 then
        wasAtBottom = (_debugScroll.CanvasPosition.Y >= maxY - 20)
    end

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
                if c == _lastDedupLabel then
                    _lastDedupKey = nil
                    _lastDedupLabel = nil
                    _lastDedupBaseText = nil
                    _lastDedupCount = 0
                end
                c:Destroy()
                count = count - 1
                removed = true
                break
            end
        end
        if not removed then break end
    end

    if dedupKey then
        _lastDedupKey = dedupKey
        _lastDedupLabel = label
        _lastDedupBaseText = text
        _lastDedupCount = 1
    else
        _lastDedupKey = nil
        _lastDedupLabel = nil
        _lastDedupBaseText = nil
        _lastDedupCount = 0
    end

    if wasAtBottom then
        task.defer(function()
            if _debugScroll then
                _debugScroll.CanvasPosition = Vector2.new(0, _debugScroll.AbsoluteCanvasSize.Y)
            end
        end)
    end
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
    pushDebug(nowStamp() .. " " .. msg, Color3.fromRGB(200, 210, 225), msg)
end

local function warnUser(...)
    local msg = fmt(...)
    warn("[TDX]", msg)
    pushDebug(nowStamp() .. " ! " .. msg, Color3.fromRGB(255, 150, 150), msg)
end

local function action(...)
    local msg = fmt(...)
    pushDebug(nowStamp() .. " > " .. msg, Color3.fromRGB(150, 230, 160), msg)
end

local function retryMsg(...)
    local msg = fmt(...)
    local base = msg:gsub(",%s*retry%s*#%d+", "")
    pushDebug(nowStamp() .. " ~ " .. base, Color3.fromRGB(255, 210, 130), "~" .. base)
end

createDebugUI()

local AutoSkipActive = false
local ReverseAutoSkipActive = false
local CurrentWave = 0
local WaveConnection = nil

local function parseWave(text)
    if not text then return 0 end
    local num = text:match("%d+")
    return tonumber(num) or 0
end

local function isInWaveList(wave, list)
    if not list then return false end
    for _, w in ipairs(list) do
        if w == wave then return true end
    end
    return false
end

local function updateAutoSkip()
    local vip = LocalPlayer:GetAttribute("VIP")
    if not vip then return end

    local shouldSkip = false

    if _G.AutoSkip then
        shouldSkip = isInWaveList(CurrentWave, _G.AutoSkip)
    elseif _G.ReverseAutoSkip then
        shouldSkip = not isInWaveList(CurrentWave, _G.ReverseAutoSkip)
    end

    local remote = Remotes:FindFirstChild("RequestUpdateSetting")
    if remote and AutoSkipActive ~= shouldSkip then
        AutoSkipActive = shouldSkip
        remote:FireServer("AutoSkip", shouldSkip)
        log(string.format("AutoSkip %s on wave %d", shouldSkip and "enabled" or "disabled", CurrentWave))
    end
end

local function startWaveWatcher()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local interface = playerGui:WaitForChild("Interface")
    local gameInfoBar = interface:WaitForChild("GameInfoBar")
    local default = gameInfoBar:WaitForChild("Default")
    local wave = default:WaitForChild("Wave")
    local waveText = wave:WaitForChild("WaveText")

    CurrentWave = parseWave(waveText.Text)

    WaveConnection = waveText:GetPropertyChangedSignal("Text"):Connect(function()
        CurrentWave = parseWave(waveText.Text)
        updateAutoSkip()
    end)

    updateAutoSkip()
end

if _G.AutoSkip or _G.ReverseAutoSkip then
    task.spawn(function()
        local timeout = tick() + 10
        while not LocalPlayer:GetAttribute("VIP") and tick() < timeout do
            task.wait(0.2)
        end

        if LocalPlayer:GetAttribute("VIP") then
            log("VIP detected, starting AutoSkip watcher")
            startWaveWatcher()
        else
            warnUser("VIP attribute not found, AutoSkip disabled")
        end
    end)
end

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
TDX._rebuildUrgent = 0
TDX._towerCosts = {}
TDX._deadSlotCounter = -1
TDX._internalSell = false

TDX._aliveWaiters = {}
TDX._levelWaiters = {}
TDX._targetWaiters = {}

local tbVoidPending = {}

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

local function getCashValue()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if not ls then return 0 end
    local c = ls:FindFirstChild("Cash")
    return c and c.Value or 0
end

local function scanTowerCosts()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local iface = pg and pg:FindFirstChild("Interface")
    local bb = iface and iface:FindFirstChild("BottomBar")
    local tb = bb and bb:FindFirstChild("TowersBar")
    if not tb then return 0 end
    local found = 0
    for _, towerFrame in ipairs(tb:GetChildren()) do
        if towerFrame:IsA("GuiObject") then
            local costFrame = towerFrame:FindFirstChild("CostFrame")
            local costText = costFrame and costFrame:FindFirstChild("CostText")
            if costText and costText:IsA("TextLabel") then
                local raw = costText.Text or ""
                local num = tonumber((raw:gsub("[%$,%s]", "")))
                if num and num > 0 then
                    TDX._towerCosts[towerFrame.Name] = num
                    found = found + 1
                end
            end
        end
    end
    return found
end

task.spawn(function()
    local deadline = tick() + 30
    while tick() < deadline do
        if scanTowerCosts() > 0 then break end
        task.wait(1)
    end
    while true do
        task.wait(60)
        scanTowerCosts()
    end
end)

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
                    local t = math.min(lvl[1] or 0, MAX_PATH_LEVEL)
                    local b = math.min(lvl[2] or 0, MAX_PATH_LEVEL)
                    TDX._levelCache[id] = { t, b }
                    for _, slot in pairs(TDX._slots) do
                        if slot.actualId == id then
                            if t > (slot.peakT or 0) then slot.peakT = t end
                            if b > (slot.peakB or 0) then slot.peakB = b end
                            break
                        end
                    end
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
                local t = math.min(lvl[1] or 0, MAX_PATH_LEVEL)
                local b = math.min(lvl[2] or 0, MAX_PATH_LEVEL)
                TDX._levelCache[hash] = { t, b }
                for _, slot in pairs(TDX._slots) do
                    if slot.actualId == hash then
                        slot.lastT = t
                        slot.lastB = b
                        if t > (slot.peakT or 0) then slot.peakT = t end
                        if b > (slot.peakB or 0) then slot.peakB = b end
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
            if not slotId or not slot then return end

            local lvl = TDX._levelCache[hash] or { slot.lastT or 0, slot.lastB or 0 }
            local t = math.min(lvl[1] or 0, MAX_PATH_LEVEL)
            local b = math.min(lvl[2] or 0, MAX_PATH_LEVEL)
            if t > (slot.peakT or 0) then slot.peakT = t end
            if b > (slot.peakB or 0) then slot.peakB = b end

            if data.CanRebuild == true then
                slot.awaitingGameRevive = true
                slot.deadId = nil
                slot.deathLevel = nil
                slot.deathTime = nil
                queueRemove(slotId)
                log(string.format("Slot %s (ID %s) has in-game rebuilds (%s left, %ss), skipping",
                    tostring(slotId), tostring(hash),
                    tostring(data.RebuildsLeft or "?"),
                    tostring(data.RebuildTime or "?")))
                return
            end

            slot.awaitingGameRevive = false
            slot.deathLevel = {
                math.min(slot.peakT or t, MAX_PATH_LEVEL),
                math.min(slot.peakB or b, MAX_PATH_LEVEL),
            }
            slot.deadId = hash
            slot.deathTime = tick()

            if slot.autoReplace then
                log(string.format("Slot %s (ID %s) died at %d/%d, queued (waiting %ds)",
                    tostring(slotId), tostring(hash),
                    slot.deathLevel[1], slot.deathLevel[2], REBUILD_WAIT))
                queueAdd(slotId)
                ensureWorker()
            else
                log(string.format("Slot %s (ID %s) died at %d/%d (auto-replace off, holding)",
                    tostring(slotId), tostring(hash),
                    slot.deathLevel[1], slot.deathLevel[2]))
            end
        elseif data.IsAlive == true then
            TDX._aliveState[hash] = true
            local slotId, slot = findSlotByActualId(hash)
            if slotId and slot then
                local wasPending = (slot.deadId == hash) or slot.awaitingGameRevive
                slot.deadId = nil
                slot.deathLevel = nil
                slot.deathTime = nil
                slot.awaitingGameRevive = false
                queueRemove(slotId)
                resolveKey(TDX._aliveWaiters, slotId)
                if wasPending then
                    log(string.format("Slot %s (ID %s) is alive", tostring(slotId), tostring(hash)))
                end
            end
        end
    end)
end

local function startAutoRejoin()
    if not AUTO_REJOIN then
        log("Auto-rejoin disabled by settings")
        return
    end
    local remotes = Remotes
    if not remotes then return end
    local stateChanged = remotes:FindFirstChild("GameStateChanged")
    local rejoinRemote = remotes:FindFirstChild("RequestTeleportToLobby")
    if not stateChanged or not rejoinRemote then return end
    local triggered = false
    stateChanged.OnClientEvent:Connect(function(state)
        if triggered or state ~= "EndScreen" then return end
        triggered = true
        action("ENDSCREEN detected, rejoining in 5s")
        setStatus("auto-rejoin pending")
        task.wait(5)
        local ok, err = pcall(function()
            rejoinRemote:FireServer()
        end)
        if ok then
            log("RequestTeleportToLobby fired")
        else
            warnUser("rejoin fire failed:", err)
        end
    end)
end

startAutoRejoin()

do
    local resetRemote = Remotes:FindFirstChild("ResetDataExecuted")
    if resetRemote then
        resetRemote.OnClientEvent:Connect(function(data)
            log("ResetDataExecuted received - clearing all tower state")

            local slotsCleared = 0
            for slotId, slot in pairs(TDX._slots) do
                slotsCleared = slotsCleared + 1
                if slot.deadId then queueRemove(slotId) end
            end

            TDX._slots = {}
            TDX._aliveState = {}
            TDX._levelCache = {}
            TDX._targetCache = {}
            TDX._placeHistory = {}
            TDX._idRemap = {}
            TDX._placeCount = 0
            TDX._pendingPlaces = {}
            TDX._rebuildQueue = {}
            TDX._aliveWaiters = {}
            TDX._levelWaiters = {}
            TDX._targetWaiters = {}
            TDX._deadSlotCounter = -1
            TDX._lastFire = {}

            for k in pairs(tbVoidPending) do
                tbVoidPending[k] = nil
            end

            for _, list in pairs(TDX._aliveWaiters) do
                for _, fn in ipairs(list) do pcall(fn, true) end
            end
            for _, list in pairs(TDX._levelWaiters) do
                for _, fn in ipairs(list) do pcall(fn, true) end
            end
            for _, list in pairs(TDX._targetWaiters) do
                for _, fn in ipairs(list) do pcall(fn, true) end
            end

            log(string.format("Cleared %d slots - ready for new round", slotsCleared))
        end)
    end
end

do
    if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" and SellTower then
        local oldNamecall
        local ok = pcall(function()
            oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                if self == SellTower and getnamecallmethod() == "FireServer" then
                    if not TDX._internalSell then
                        local args = table.pack(...)
                        local hash = tonumber(args[1])
                        if hash then
                            local slotId, slot = findSlotByActualId(hash)
                            if slotId and slot then
                                slot.autoReplace = false
                                slot.deadId = nil
                                slot.deathLevel = nil
                                slot.deathTime = nil
                                slot.awaitingGameRevive = false
                                queueRemove(slotId)
                                log(string.format("Sell detected: slot %s (ID %s) - auto-replace disabled",
                                    tostring(slotId), tostring(hash)))
                            end
                        end
                    end
                end
                return oldNamecall(self, ...)
            end))
        end)
        if not ok or not oldNamecall then
            warnUser("Sell hook failed to install")
        end
    end
end

local function slotReady(slot)
    return slot
        and slot.actualId
        and not slot.deadId
        and not slot.restoring
        and not slot.awaitingGameRevive
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

local function doRebuildSlot(slotId)
    local s = TDX._slots[slotId]
    if not s then return end
    if not s.deadId or not s.autoReplace then return end
    if s.awaitingGameRevive then return end
    if (tick() - (s.deathTime or 0)) < REBUILD_WAIT then return end

    if TDX._aliveState[s.deadId] == true then
        log(string.format("Slot %s already alive (game revived), skipping rebuild", tostring(slotId)))
        s.deadId = nil
        s.deathLevel = nil
        s.deathTime = nil
        queueRemove(slotId)
        return
    end

    local _conflict = nil
    for sid, oslot in pairs(TDX._slots) do
        if sid ~= slotId and oslot.actualId == s.deadId and not oslot.deadId then
            _conflict = sid
            break
        end
    end
    if _conflict then
        log(string.format("Slot %s rebuild skipped - ID %s already live in slot %s",
            tostring(slotId), tostring(s.deadId), tostring(_conflict)))
        s.deadId = nil
        s.deathLevel = nil
        s.deathTime = nil
        queueRemove(slotId)
        return
    end

    local deadId = s.deadId
    local targetT = math.min(s.deathLevel and s.deathLevel[1] or 0, MAX_PATH_LEVEL)
    local targetB = math.min(s.deathLevel and s.deathLevel[2] or 0, MAX_PATH_LEVEL)

    log(string.format("Auto-replacing slot %s: %s -> restore %d/%d",
        tostring(slotId), tostring(s.name), targetT, targetB))
    setStatus("rebuilding slot " .. tostring(slotId) .. " (" .. tostring(s.name) .. ")")
    action(string.format("REBUILD slot %s %s", tostring(slotId), tostring(s.name)))

    local newId = placeInternal(s.name, s.pos, s.aim, s.rebuild, true, function()
        local cur = TDX._slots[slotId]
        return cur and cur.deadId == deadId and cur.autoReplace and not cur.awaitingGameRevive
    end)
    local sl = TDX._slots[slotId]

    if not sl then return end
    if sl.deadId ~= deadId then
        log(string.format("Slot %s state changed during placement, cancelled", tostring(slotId)))
        return
    end
    if not newId then
        local cur = TDX._slots[slotId]
        if not cur or cur.deadId ~= deadId or cur.awaitingGameRevive then
            log(string.format("Slot %s abandoned (state changed)", tostring(slotId)))
            return
        end

        if TDX._aliveState[deadId] == true then
            log(string.format("Slot %s already alive (game revived during place), skipping", tostring(slotId)))
            cur.deadId = nil
            cur.deathLevel = nil
            cur.deathTime = nil
            queueRemove(slotId)
            return
        end

        log(string.format("Slot %s place failed, requeuing for retry", tostring(slotId)))
        cur.deathTime = tick()
        queueAdd(slotId)
        return
    end

    TDX._idRemap[slotId] = newId
    TDX._aliveState[newId] = true
    TDX._levelCache[newId] = { 0, 0 }
    sl.actualId = newId
    sl.deadId = nil
    sl.deathLevel = nil
    sl.deathTime = nil
    sl.awaitingGameRevive = false
    sl.lastT = 0
    sl.lastB = 0
    resolveKey(TDX._aliveWaiters, slotId)

    log(string.format("Auto-replaced %s (slot %s -> ID %s)",
        sl.name, tostring(slotId), tostring(newId)))

    if targetT > 0 or targetB > 0 then
        sl.restoring = true
        setStatus(string.format("restoring slot %s to %d/%d",
            tostring(slotId), targetT, targetB))

        local ok, err = pcall(restoreLevel, slotId, targetT, targetB)
        if not ok then warnUser("restoreLevel error:", err) end

        local s2 = TDX._slots[slotId]
        if s2 then s2.restoring = false end
        resolveKey(TDX._aliveWaiters, slotId)
    end
end

ensureWorker = function()
    if TDX._rebuildWorkerRunning then return end
    TDX._rebuildWorkerRunning = true
    task.defer(function()
        while true do
            local ok, err = pcall(function()
                local didWork = false

                if #TDX._rebuildQueue > 0 then
                    queueSort()

                    local toRemove = {}
                    local chosen = nil

                    for i = 1, #TDX._rebuildQueue do
                        local sid = TDX._rebuildQueue[i]
                        local s = TDX._slots[sid]

                        if not s or not s.deadId or not s.autoReplace or s.awaitingGameRevive then
                            table.insert(toRemove, i)
                        elseif s.actualId ~= s.deadId then
                            s.deadId = nil
                            table.insert(toRemove, i)
                        elseif TDX._aliveState[s.deadId] == true then
                            s.deadId = nil
                            s.deathLevel = nil
                            s.deathTime = nil
                            table.insert(toRemove, i)
                        elseif (tick() - (s.deathTime or 0)) >= REBUILD_WAIT then
                            if not chosen then
                                chosen = { index = i, slotId = sid }
                            end
                        end
                    end

                    for j = #toRemove, 1, -1 do
                        table.remove(TDX._rebuildQueue, toRemove[j])
                    end

                    if chosen then
                        didWork = true
                        local chosenSlot = TDX._slots[chosen.slotId]
                        local chosenValid = chosenSlot
                            and chosenSlot.deadId
                            and chosenSlot.autoReplace
                            and not chosenSlot.awaitingGameRevive
                            and TDX._aliveState[chosenSlot.deadId] ~= true
                            and (tick() - (chosenSlot.deathTime or 0)) >= REBUILD_WAIT

                        if chosenValid then
                            queueRemove(chosen.slotId)
                            TDX._rebuildUrgent = TDX._rebuildUrgent + 1
                            local okR, errR = pcall(doRebuildSlot, chosen.slotId)
                            TDX._rebuildUrgent = TDX._rebuildUrgent - 1
                            if not okR then warnUser("doRebuildSlot error:", errR) end
                        end
                    end
                end

                if not didWork then
                    task.wait(0.1)
                end
            end)

            if not ok then
                warnUser("rebuild worker error:", err)
                task.wait(1)
            end
        end
    end)
end

placeInternal = function(name, pos, aim, rebuild, priority, shouldContinue)
    if not PlaceTower then return nil end

    if not priority then
        local deadline = tick() + 30
        while TDX._rebuildUrgent > 0 and tick() < deadline do
            task.wait(0.05)
        end
    end

    local attempts = 0
    while attempts < PLACE_MAX_ATTEMPTS do
        local cost = TDX._towerCosts[name]

        if cost and cost > 0 then
            local loggedWait = false
            while getCashValue() < cost do
                if shouldContinue and not shouldContinue() then
                    if loggedWait then
                        log(string.format("Cash wait for %s aborted (slot state changed)", name))
                    end
                    return nil
                end
                if not loggedWait then
                    log(string.format("WAIT CASH %s -> need %d, have %d",
                        name, cost, getCashValue()))
                    loggedWait = true
                end
                task.wait(0.05)
            end
            if loggedWait then
                log(string.format("Cash ready for %s (%d), proceeding", name, cost))
            end
        end

        attempts = attempts + 1
        acquirePlaceLock()

        if cost and cost > 0 and getCashValue() < cost then
            releasePlaceLock()
            task.wait(0.1)
            attempts = attempts - 1
            continue
        end

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
                function(timeout)
                    if d.done then return d.result end
                    task.delay(timeout or 10, function()
                        if not d.done then
                            d.done = true
                            d.result = nil
                            d.event:Fire()
                        end
                    end)
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
            local id = await(10)
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

    targetT = math.min(targetT or 0, MAX_PATH_LEVEL)
    targetB = math.min(targetB or 0, MAX_PATH_LEVEL)

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

        awaitLevelChange(actual, lvl, RESTORE_AWAIT)

        if TDX._aliveState[actual] == false then
            return false
        end
    end
end

local function handleConversionBatch(affectedHashes)
    local toRebuild = {}

    for _, rawHash in ipairs(affectedHashes) do
        local hash = tonumber(rawHash)
        if hash and not tbVoidPending[hash] then
            local slotId, slot = findSlotByActualId(hash)
            if slotId and slot and slot.autoReplace then
                tbVoidPending[hash] = true
                table.insert(toRebuild, {
                    hash = hash,
                    slotId = slotId,
                    slot = slot,
                    name = tostring(slot.name),
                    peakT = math.min(slot.peakT or 0, MAX_PATH_LEVEL),
                    peakB = math.min(slot.peakB or 0, MAX_PATH_LEVEL),
                })
            end
        end
    end

    if #toRebuild == 0 then return end

    log(string.format("Conversion hit %d tower(s) - selling all then rebuilding one by one", #toRebuild))

    if SellTower then
        TDX._internalSell = true
        for _, entry in ipairs(toRebuild) do
            pcall(function() SellTower:FireServer(entry.hash) end)
        end
        task.wait(INTERNAL_SELL_FLUSH)
        TDX._internalSell = false
    end

    for _, entry in ipairs(toRebuild) do
        TDX._levelCache[entry.hash] = nil
        TDX._targetCache[entry.hash] = nil
        TDX._aliveState[entry.hash] = false
        resolveKey(TDX._levelWaiters, entry.hash)
        resolveKey(TDX._targetWaiters, entry.hash)
        log(string.format("  sold %s (ID %s)", entry.name, tostring(entry.hash)))
    end

    for _, entry in ipairs(toRebuild) do
        task.spawn(function()
            task.wait(VOID_REBUILD_DELAY)
            tbVoidPending[entry.hash] = nil

            local cur = entry.slot
            local curSlotId = entry.slotId

            if not cur then
                log(string.format("Rebuild target %s (ID %s) reference lost - dropping",
                    entry.name, tostring(entry.hash)))
                return
            end

            if TDX._slots[curSlotId] ~= cur then
                curSlotId = nil
                for sid, s in pairs(TDX._slots) do
                    if s == cur then curSlotId = sid break end
                end
                if not curSlotId then
                    log(string.format("Rebuild target %s (ID %s) removed from slots - dropping",
                        entry.name, tostring(entry.hash)))
                    return
                end
            end

            if cur.deadId == nil
                and cur.actualId ~= entry.hash
                and TDX._aliveState[cur.actualId] == true
            then
                log(string.format("Slot %s (%s) already alive under new ID %s, skipping",
                    tostring(curSlotId), entry.name, tostring(cur.actualId)))
                return
            end

            cur.deadId = entry.hash
            cur.deathLevel = { entry.peakT, entry.peakB }
            cur.deathTime = tick() - REBUILD_WAIT
            cur.autoReplace = true
            cur.awaitingGameRevive = false
            cur.peakT = entry.peakT
            cur.peakB = entry.peakB

            queueAdd(curSlotId)
            ensureWorker()
            log(string.format("  queued slot %s (%s) for rebuild",
                tostring(curSlotId), entry.name))
        end)
    end
end

if EnemyUsedAbility then
    EnemyUsedAbility.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        local payload = data[2]
        if type(payload) ~= "table" then return end

        local abilityName = payload[1]
        if type(abilityName) ~= "string" then return end
        if not abilityName:find("Conversion") then return end

        local affected = payload[9]
        if type(affected) ~= "table" then return end

        handleConversionBatch(affected)
    end)
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
            existing.awaitingGameRevive = false
            queueRemove(slotId)
            log(string.format("Slot %s rebuild cancelled by explicit place", tostring(slotId)))
        end
        if existing.actualId and TDX._aliveState[existing.actualId] == true then
            log(string.format("Slot %s already alive (ID %s), skipping place",
                tostring(slotId), tostring(existing.actualId)))
            return existing.actualId
        end
    end

    local newId = placeInternal(name, pos, aim, rebuild, false, nil)
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
        peakT = 0,
        peakB = 0,
        deathLevel = nil,
        deathTime = nil,
        restoring = false,
        awaitingGameRevive = false,
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

function TDX:Register(name, pos, id, rebuild)
    if not name or not id then return nil end
    if typeof(pos) ~= "Vector3" then return nil end

    local existingSlotId, existingSlot = findSlotByActualId(id)
    if existingSlotId and existingSlot then
        local samePlace = existingSlot.pos
            and typeof(existingSlot.pos) == "Vector3"
            and (existingSlot.pos - pos).Magnitude <= COLLISION_DISTANCE

        local sameName = existingSlot.name == name

        if samePlace and sameName then
            return existingSlotId
        end

        local isDead = existingSlot.deadId ~= nil
            or TDX._aliveState[existingSlot.actualId] == false
            or existingSlot.awaitingGameRevive

        if isDead then
            local newSlotId = TDX._deadSlotCounter
            TDX._deadSlotCounter = TDX._deadSlotCounter - 1

            while TDX._slots[newSlotId] do
                newSlotId = TDX._deadSlotCounter
                TDX._deadSlotCounter = TDX._deadSlotCounter - 1
            end

            TDX._slots[newSlotId] = existingSlot
            TDX._slots[existingSlotId] = nil

            existingSlot.actualId = newSlotId
            existingSlot.deadId = newSlotId

            for i, qid in ipairs(TDX._rebuildQueue) do
                if qid == existingSlotId then
                    TDX._rebuildQueue[i] = newSlotId
                end
            end

            log(string.format("Hash %s reused by %s - dead %s (slot %s) preserved as slot %s",
                tostring(id), tostring(name),
                tostring(existingSlot.name), tostring(existingSlotId),
                tostring(newSlotId)))
        else
            log(string.format("Hash %s reused (live slot %s dropped) - pos delta=%.2f, name %s->%s",
                tostring(id), tostring(existingSlotId),
                existingSlot.pos and typeof(existingSlot.pos) == "Vector3"
                    and (existingSlot.pos - pos).Magnitude or -1,
                tostring(existingSlot.name), tostring(name)))

            queueRemove(existingSlotId)
            if existingSlot.actualId then
                TDX._aliveState[existingSlot.actualId] = nil
                TDX._levelCache[existingSlot.actualId] = nil
                TDX._targetCache[existingSlot.actualId] = nil
            end
            TDX._slots[existingSlotId] = nil
        end
    end

    local slotId = id
    if TDX._slots[slotId] then return slotId end

    TDX._idRemap[slotId] = id
    TDX._aliveState[id] = true
    TDX._levelCache[id] = TDX._levelCache[id] or { 0, 0 }

    local lvl = TDX._levelCache[id]
    local peakT = 0
    local peakB = 0
    if lvl then
        peakT = math.min(lvl[1] or 0, MAX_PATH_LEVEL)
        peakB = math.min(lvl[2] or 0, MAX_PATH_LEVEL)
    end

    TDX._slots[slotId] = {
        name = name, pos = pos, aim = nil,
        rebuild = rebuild ~= false, autoReplace = rebuild ~= false,
        actualId = id, deadId = nil, lastT = 0, lastB = 0,
        peakT = peakT, peakB = peakB,
        deathLevel = nil, deathTime = nil,
        restoring = false, awaitingGameRevive = false,
    }

    TDX._placeHistory[slotId] = { name = name, actualId = id, recordedId = slotId }
    return slotId
end

function TDX:SetAutoReplace(slotId, enabled)
    local slot = TDX._slots[slotId]
    if not slot then return false end

    local wasOff = not slot.autoReplace
    slot.autoReplace = enabled == true

    if slot.autoReplace then
        if wasOff and slot.deadId and not slot.awaitingGameRevive then
            log(string.format("Slot %s re-enabled, requeuing", tostring(slotId)))
            queueAdd(slotId)
            ensureWorker()
        end
    else
        queueRemove(slotId)
    end

    return true
end

function TDX:SetAutoReplaceByName(name, enabled)
    local changed = false
    for slotId, slot in pairs(TDX._slots) do
        if slot.name == name then
            local wasOff = not slot.autoReplace
            slot.autoReplace = enabled == true

            if slot.autoReplace then
                if wasOff and slot.deadId and not slot.awaitingGameRevive then
                    log(string.format("Slot %s re-enabled, requeuing", tostring(slotId)))
                    queueAdd(slotId)
                    ensureWorker()
                    changed = true
                end
            else
                queueRemove(slotId)
            end
        end
    end
    return changed
end

function TDX:GetTowerCost(name)
    return TDX._towerCosts[name]
end

function TDX:RescanTowerCosts()
    return scanTowerCosts()
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
        local target = math.min(cur + count, MAX_PATH_LEVEL)
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
    TDX._internalSell = true
    pcall(function() SellTower:FireServer(actual) end)
    task.wait(INTERNAL_SELL_FLUSH)
    TDX._internalSell = false

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
        slot.awaitingGameRevive = false
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

function TDX:TimeScale(speed)
    local remote = Remotes:FindFirstChild("SoloToggleSpeedControl")
    if not remote then
        warnUser("SoloToggleSpeedControl remote missing")
        return false
    end

    if speed == 1 then
        remote:FireServer(false)
    elseif speed == 1.5 then
        remote:FireServer(true, true)
    elseif speed == 0.5 then
        remote:FireServer(true, false)
    else
        warnUser("Invalid speed:", speed)
        return false
    end

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
    local net = ReplicatedStorage:FindFirstChild("Network")
    if net then
        local partyType = net:FindFirstChild("ClientChangePartyTypeRequest")
        local partyMap = net:FindFirstChild("ClientChangePartyMapRequest")
        if partyType and partyMap then
            partyType:FireServer("Party")
            task.wait(0.5)
            partyMap:FireServer(mode)
            task.wait(0.2)
            TDX:StartMatchmaking()
        end
    end
end

function TDX:StartMatchmaking()
    local net = ReplicatedStorage:FindFirstChild("Network")
    if net then
        local start = net:FindFirstChild("ClientStartGameRequest")
        if start then
            start:FireServer()
        end
    end
    task.wait(0.2)
end

function TDX:Loadout(id)
    task.wait(2)
    local load = getRemote("LoadoutSelectionChanged")
    if load then
        load:FireServer(id)
    end
    task.wait(0.5)
end

function TDX:VoteMap(map, attempts)
    attempts = attempts or 3

    local vote = Remotes:FindFirstChild("MapVoteCast")
    if not vote then
        warnUser("MapVoteCast remote missing")
        return false
    end

    for i = 1, attempts do
        vote:FireServer(map)
        task.wait(0.3)
    end

    task.wait(1.5)

    local ready = Remotes:FindFirstChild("MapVoteReady")
    if ready then
        for i = 1, 3 do
            ready:FireServer()
            task.wait(0.3)
        end
        return true
    end

    return false
end

function TDX:VoteDifficulty(diff)
    local vote = Remotes:FindFirstChild("DifficultyVoteCast")
    if not vote then
        warnUser("DifficultyVoteCast remote missing")
        return false
    end

    local stateUpdate = Remotes:FindFirstChild("DifficultyVoteStateUpdate")
    if stateUpdate then
        local waiting = true
        local connection
        connection = stateUpdate.OnClientEvent:Connect(function(data)
            if type(data) == "table" and data.WaitingForFirstVote == false then
                waiting = false
                if connection then
                    connection:Disconnect()
                end
            end
        end)

        local timeout = tick() + 5
        while waiting and tick() < timeout do
            task.wait(0.2)
        end
        if connection then
            connection:Disconnect()
        end
    end

    for i = 1, 3 do
        vote:FireServer(diff)
        task.wait(0.3)
    end

    task.wait(1.5)

    local ready = Remotes:FindFirstChild("DifficultyVoteReady")
    if ready then
        for i = 1, 3 do
            ready:FireServer()
            task.wait(0.3)
        end
        return true
    end

    return false
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

    if slot.awaitingGameRevive and slot.actualId then
        slot.awaitingGameRevive = false
        slot.deadId = slot.actualId
        slot.deathTime = tick() - REBUILD_WAIT
        slot.deathLevel = { slot.peakT or 0, slot.peakB or 0 }
        action("FORCE REBUILD slot=" .. tostring(slotId))
        queueAdd(slotId)
        ensureWorker()
        return true
    end

    if slot.deadId then
        slot.deathTime = tick() - REBUILD_WAIT
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
        towerCosts = TDX._towerCosts,
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
    TDX._rebuildUrgent = 0
    TDX._deadSlotCounter = -1
end

if getgenv then getgenv().TDX = TDX end
_G.TDX = TDX

if SKIP_WAITS then
    log("Library loaded. Waits will be skipped.")
else
    log("Library loaded. Waits will be honored.")
end

return TDX