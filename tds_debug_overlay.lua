local function attachOverlay(TDS)
    if not TDS then
        warn("[TDS Overlay] Error: TDS table is nil")
        return nil
    end
    
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local localPlayer = Players.LocalPlayer
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    
    local existingOverlay = playerGui:FindFirstChild("TDS_DebugOverlay")
    if existingOverlay then
        existingOverlay:Destroy()
    end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TDS_DebugOverlay"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 999
    screenGui.Parent = playerGui
    
    local slotTowers = {}      
    local towerCounts = {}
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 80, 0, 80)
    mainFrame.Position = UDim2.new(0, 10, 0, 10)
    mainFrame.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
    mainFrame.BorderSizePixel = 1
    mainFrame.BorderColor3 = Color3.fromRGB(55, 55, 75)
    mainFrame.Parent = screenGui
    
    local corner = Instance.new("UICorner", mainFrame)
    corner.CornerRadius = UDim.new(0, 8)
    
    local minimizedButton = Instance.new("TextButton")
    minimizedButton.Size = UDim2.new(1, 0, 1, 0)
    minimizedButton.BackgroundTransparency = 1
    minimizedButton.Text = "Debug"
    minimizedButton.TextColor3 = Color3.fromRGB(225, 225, 245)
    minimizedButton.Font = Enum.Font.GothamBold
    minimizedButton.TextSize = 14
    minimizedButton.Parent = mainFrame
    
    local expandedFrame = Instance.new("Frame")
    expandedFrame.Size = UDim2.new(0, 600, 0, 500)
    expandedFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 23)
    expandedFrame.BorderSizePixel = 1
    expandedFrame.BorderColor3 = Color3.fromRGB(55, 55, 75)
    expandedFrame.Visible = false
    expandedFrame.Parent = mainFrame
    
    local expandedCorner = Instance.new("UICorner", expandedFrame)
    expandedCorner.CornerRadius = UDim.new(0, 8)
    
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = expandedFrame
    
    local titleCorner = Instance.new("UICorner", titleBar)
    titleCorner.CornerRadius = UDim.new(0, 8)
    
    local titleText = Instance.new("TextLabel")
    titleText.Text = "TDS Debug"
    titleText.Size = UDim2.new(1, -60, 1, 0)
    titleText.Position = UDim2.new(0, 12, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.TextColor3 = Color3.fromRGB(225, 225, 245)
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Font = Enum.Font.GothamBold
    titleText.TextSize = 13
    titleText.Parent = titleBar
    
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Text = "−"
    minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
    minimizeBtn.Position = UDim2.new(1, -40, 0, 5)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    minimizeBtn.TextColor3 = Color3.fromRGB(190, 190, 215)
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.TextSize = 20
    minimizeBtn.BorderSizePixel = 0
    minimizeBtn.Parent = titleBar
    
    local minCorner = Instance.new("UICorner", minimizeBtn)
    minCorner.CornerRadius = UDim.new(0, 5)
    
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Size = UDim2.new(1, -12, 1, -50)
    scrollFrame.Position = UDim2.new(0, 6, 0, 46)
    scrollFrame.BackgroundColor3 = Color3.fromRGB(13, 13, 18)
    scrollFrame.BorderSizePixel = 0
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 95)
    scrollFrame.Parent = expandedFrame
    
    local scrollCorner = Instance.new("UICorner", scrollFrame)
    scrollCorner.CornerRadius = UDim.new(0, 6)
    
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 2)
    layout.Parent = scrollFrame
    
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 6)
    padding.PaddingBottom = UDim.new(0, 6)
    padding.PaddingLeft = UDim.new(0, 6)
    padding.PaddingRight = UDim.new(0, 6)
    padding.Parent = scrollFrame
    
    local isExpanded = false
    
    local function updateLayoutOrders()
        local children = {}
        for _, child in pairs(scrollFrame:GetChildren()) do
            if child:IsA("Frame") and child ~= layout and child ~= padding then
                table.insert(children, child)
            end
        end
        
        for i = #children, 1, -1 do
            children[i].LayoutOrder = (#children - i)
        end
        
        local totalHeight = 0
        for _, child in ipairs(children) do
            totalHeight = totalHeight + child.Size.Y.Offset + 2
        end
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight + 10)
        scrollFrame.CanvasPosition = Vector2.new(0, 0)
    end
    
    local function formatNumber(num)
        if type(num) ~= "number" then return tostring(num) end
        return string.format("%.5f", num)
    end
    
    local function addAction(text)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 32)
        row.BackgroundColor3 = Color3.fromRGB(23, 23, 30)
        row.BorderSizePixel = 0
        row.Parent = scrollFrame
        
        local rowCorner = Instance.new("UICorner", row)
        rowCorner.CornerRadius = UDim.new(0, 4)
        
        local icon = Instance.new("TextLabel")
        icon.Size = UDim2.new(0, 30, 1, 0)
        icon.Position = UDim2.new(0, 5, 0, 0)
        icon.BackgroundTransparency = 1
        icon.TextXAlignment = Enum.TextXAlignment.Center
        icon.Font = Enum.Font.Gotham
        icon.TextSize = 12
        icon.Parent = row
        
        local actionText = Instance.new("TextLabel")
        actionText.Text = text
        actionText.Size = UDim2.new(1, -45, 1, 0)
        actionText.Position = UDim2.new(0, 40, 0, 0)
        actionText.BackgroundTransparency = 1
        actionText.TextColor3 = Color3.fromRGB(215, 215, 235)
        actionText.TextXAlignment = Enum.TextXAlignment.Left
        actionText.Font = Enum.Font.Code
        actionText.TextSize = 11
        actionText.TextTruncate = Enum.TextTruncate.AtEnd
        actionText.Parent = row
        
        local spinFrames = {"◐", "◐", "◓", "◓", "◑", "◑", "◒", "◒"}
        local spinIndex = 1
        icon.Text = spinFrames[1]
        icon.TextColor3 = Color3.fromRGB(255, 210, 70)
        
        local spinnerConnection
        spinnerConnection = RunService.RenderStepped:Connect(function()
            if row and row.Parent then
                spinIndex = (spinIndex % 4) + 1
                icon.Text = spinFrames[spinIndex]
            elseif spinnerConnection then
                spinnerConnection:Disconnect()
            end
        end)
        
        updateLayoutOrders()
        
        local function markDone()
            if spinnerConnection then
                spinnerConnection:Disconnect()
            end
            if row and row.Parent and icon then
                icon.Text = "✓"
                icon.TextColor3 = Color3.fromRGB(80, 255, 120)
            end
        end
        
        return markDone
    end
    
    local function expand()
        if isExpanded then return end
        isExpanded = true
        expandedFrame.Visible = true
        minimizedButton.Visible = false
        mainFrame.Size = UDim2.new(0, 600, 0, 500)
        updateLayoutOrders()
    end
    
    local function collapse()
        if not isExpanded then return end
        isExpanded = false
        expandedFrame.Visible = false
        minimizedButton.Visible = true
        mainFrame.Size = UDim2.new(0, 80, 0, 80)
    end
    
    minimizedButton.MouseButton1Click:Connect(expand)
    minimizeBtn.MouseButton1Click:Connect(collapse)
    
    local function waitForTowerInSlot(slot)
        local startTime = tick()
        local timeout = 5
        
        while tick() - startTime < timeout do
            local towers = workspace:FindFirstChild("Towers")
            if towers then
                for _, tower in ipairs(towers:GetChildren()) do
                    local replicator = tower:FindFirstChild("TowerReplicator")
                    if replicator then
                        local ownerId = replicator:GetAttribute("OwnerId")
                        if ownerId == localPlayer.UserId then
                            local towerSlot = TDS.placed_towers and #TDS.placed_towers
                            if towerSlot == slot then
                                return true
                            end
                        end
                    end
                end
            end
            task.wait(0.1)
        end
        return false
    end
    
    local originalPlace = TDS.Place
    if originalPlace then
        TDS.Place = function(self, ...)
            local args = {...}
            local towerName = tostring(args[1])
            local x = type(args[2]) == "number" and args[2] or 0
            local z = type(args[4]) == "number" and args[4] or 0
            
            local rawArgs = {}
            for i, arg in ipairs(args) do
                if type(arg) == "number" then
                    rawArgs[i] = formatNumber(arg)
                elseif type(arg) == "string" then
                    rawArgs[i] = '"' .. arg .. '"'
                else
                    rawArgs[i] = tostring(arg)
                end
            end
            
            local rawCommand = "TDS:Place(" .. table.concat(rawArgs, ", ") .. ")"
            
            local displayText = rawCommand .. "  -- " .. towerName .. " #" .. (towerCounts[towerName] or 0) + 1
            local markDone = addAction(displayText)
            
            local slot = originalPlace(self, ...)
            
            task.spawn(function()
                local maxWait = 5
                local startWait = tick()
                local towerPlaced = false
                
                while tick() - startWait < maxWait do
                    if TDS.placed_towers and TDS.placed_towers[slot] then
                        towerPlaced = true
                        break
                    end
                    task.wait(0.1)
                end
                
                if slot and type(slot) == "number" then
                    towerCounts[towerName] = (towerCounts[towerName] or 0) + 1
                    local towerNumber = towerCounts[towerName]
                    slotTowers[slot] = {name = towerName, number = towerNumber}
                    
                end
                
                markDone()
            end)
            
            return slot
        end
    end
    
    local originalUpgrade = TDS.Upgrade
    if originalUpgrade then
        TDS.Upgrade = function(self, slot, ...)
            local towerInfo = slotTowers[slot]
            local displayText
            
            if towerInfo then
                displayText = string.format("TDS:Upgrade(%d)  -- %s #%d", slot, towerInfo.name, towerInfo.number)
            else
                displayText = string.format("TDS:Upgrade(%d)", slot)
            end
            
            local markDone = addAction(displayText)
            local result = originalUpgrade(self, slot, ...)
            markDone()
            
            return result
        end
    end
    
    local originalSell = TDS.Sell
    if originalSell then
        TDS.Sell = function(self, slot)
            local towerInfo = slotTowers[slot]
            local displayText
            
            if towerInfo then
                displayText = string.format("TDS:Sell(%d)  -- %s #%d", slot, towerInfo.name, towerInfo.number)
            else
                displayText = string.format("TDS:Sell(%d)", slot)
            end
            
            local markDone = addAction(displayText)
            local result = originalSell(self, slot)
            markDone()
            
            if result and towerInfo then
                slotTowers[slot] = nil
            end
            
            return result
        end
    end
    
    local originalMode = TDS.Mode
    if originalMode then
        TDS.Mode = function(self, mode)
            local displayText = 'TDS:Mode("' .. tostring(mode) .. '")'
            local markDone = addAction(displayText)
            local result = originalMode(self, mode)
            markDone()
            return result
        end
    end
    
    local originalLoadout = TDS.Loadout
    if originalLoadout then
        TDS.Loadout = function(self, ...)
            local args = {...}
            local rawArgs = {}
            for i, arg in ipairs(args) do
                rawArgs[i] = '"' .. tostring(arg) .. '"'
            end
            local displayText = "TDS:Loadout(" .. table.concat(rawArgs, ", ") .. ")"
            
            if #displayText > 70 then
                displayText = displayText:sub(1, 67) .. "..."
            end
            
            local markDone = addAction(displayText)
            local result = originalLoadout(self, ...)
            markDone()
            return result
        end
    end
    
    local originalReady = TDS.Ready
    if originalReady then
        TDS.Ready = function(self)
            local markDone = addAction("TDS:Ready()")
            local result = originalReady(self)
            markDone()
            return result
        end
    end
    
    local originalAbility = TDS.Ability
    if originalAbility then
        TDS.Ability = function(self, slot, ability, data, loop)
            local towerInfo = slotTowers[slot]
            local displayText
            
            if towerInfo then
                displayText = string.format('TDS:Ability(%d, "%s", ...)  -- %s #%d', slot, tostring(ability), towerInfo.name, towerInfo.number)
            else
                displayText = string.format('TDS:Ability(%d, "%s", ...)', slot, tostring(ability))
            end
            
            local markDone = addAction(displayText)
            local result = originalAbility(self, slot, ability, data, loop)
            markDone()
            return result
        end
    end
    
    local originalSetOption = TDS.SetOption
    if originalSetOption then
        TDS.SetOption = function(self, slot, key, value, req_wave)
            local displayText = string.format('TDS:SetOption(%d, "%s", %s)', slot, tostring(key), tostring(value))
            local markDone = addAction(displayText)
            local result = originalSetOption(self, slot, key, value, req_wave)
            markDone()
            return result
        end
    end
    
    local originalAutoChain = TDS.AutoChain
    if originalAutoChain then
        TDS.AutoChain = function(self, ...)
            local args = {...}
            local displayText = "TDS:AutoChain(" .. table.concat(args, ", ") .. ")"
            local markDone = addAction(displayText)
            local result = originalAutoChain(self, ...)
            markDone()
            return result
        end
    end


return attachOverlay
