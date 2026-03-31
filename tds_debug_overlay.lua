-- // TDS Debug Overlay
-- // Starts minimized, shows newest on top, tracks slot numbers

local function attachOverlay(TDS)
    if not TDS then
        warn("[TDS Overlay] Error: TDS table is nil")
        return nil
    end
    
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local localPlayer = Players.LocalPlayer
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    
    -- Remove old overlay
    local existingOverlay = playerGui:FindFirstChild("TDS_DebugOverlay")
    if existingOverlay then
        existingOverlay:Destroy()
    end
    
    -- Create GUI
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TDS_DebugOverlay"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 999
    screenGui.Parent = playerGui
    
    -- Track towers by slot number
    local slotTowers = {}
    
    -- Main window (starts minimized)
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 80, 0, 80)
    mainFrame.Position = UDim2.new(0, 10, 0, 10)
    mainFrame.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
    mainFrame.BorderSizePixel = 1
    mainFrame.BorderColor3 = Color3.fromRGB(55, 55, 75)
    mainFrame.Parent = screenGui
    
    local corner = Instance.new("UICorner", mainFrame)
    corner.CornerRadius = UDim.new(0, 8)
    
    -- Minimized button
    local minimizedButton = Instance.new("TextButton")
    minimizedButton.Size = UDim2.new(1, 0, 1, 0)
    minimizedButton.BackgroundTransparency = 1
    minimizedButton.Text = "Debug"
    minimizedButton.TextColor3 = Color3.fromRGB(225, 225, 245)
    minimizedButton.Font = Enum.Font.GothamBold
    minimizedButton.TextSize = 14
    minimizedButton.Parent = mainFrame
    
    -- Expanded window (hidden)
    local expandedFrame = Instance.new("Frame")
    expandedFrame.Size = UDim2.new(0, 600, 0, 500)
    expandedFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 23)
    expandedFrame.BorderSizePixel = 1
    expandedFrame.BorderColor3 = Color3.fromRGB(55, 55, 75)
    expandedFrame.Visible = false
    expandedFrame.Parent = mainFrame
    
    local expandedCorner = Instance.new("UICorner", expandedFrame)
    expandedCorner.CornerRadius = UDim.new(0, 8)
    
    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = expandedFrame
    
    local titleCorner = Instance.new("UICorner", titleBar)
    titleCorner.CornerRadius = UDim.new(0, 8)
    
    local titleText = Instance.new("TextLabel")
    titleText.Text = "TDS Debug"
    titleText.Size = UDim2.new(1, -100, 1, 0)
    titleText.Position = UDim2.new(0, 12, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.TextColor3 = Color3.fromRGB(225, 225, 245)
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Font = Enum.Font.GothamBold
    titleText.TextSize = 13
    titleText.Parent = titleBar
    
    -- Minimize button
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
    
    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Text = "✕"
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -80, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(55, 40, 40)
    closeBtn.TextColor3 = Color3.fromRGB(210, 110, 110)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = titleBar
    
    local closeCorner = Instance.new("UICorner", closeBtn)
    closeCorner.CornerRadius = UDim.new(0, 5)
    
    -- Scroll frame
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
    
    -- Update layout orders (newest on top)
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
    
    -- Format number with proper decimal places (coordinates only)
    local function formatNumber(num)
        if type(num) ~= "number" then return tostring(num) end
        return string.format("%.2f", num)
    end
    
    -- Format slot number (whole number)
    local function formatSlot(num)
        if type(num) ~= "number" then return tostring(num) end
        return tostring(math.floor(num)) -- Convert to whole number
    end
    
    -- Add action
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
        
        -- Spinner animation
        local spinFrames = {"◐", "◓", "◑", "◒"}
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
    
    -- Expand/collapse
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
    
    local function close()
        screenGui:Destroy()
    end
    
    minimizedButton.MouseButton1Click:Connect(expand)
    minimizeBtn.MouseButton1Click:Connect(collapse)
    closeBtn.MouseButton1Click:Connect(close)
    
    -- WRAP TDS METHODS
    
    -- Wrap Place - tracks slot number
    if TDS.Place then
        local original = TDS.Place
        TDS.Place = function(self, ...)
            local args = {...}
            local towerName = tostring(args[1])
            
            -- Find which slot this tower is placed in
            local slot = nil
            for i = 2, #args do
                local val = args[i]
                if type(val) == "number" and val >= 1 and val <= 100 then
                    slot = math.floor(val) -- Convert to whole number
                    break
                end
            end
            
            -- Track slot
            if slot then
                slotTowers[slot] = towerName
                print(string.format("[TDS Overlay] Tower placed: %s in slot %d", towerName, slot))
            end
            
            -- Format the raw command
            local rawArgs = {}
            for i, arg in ipairs(args) do
                if type(arg) == "number" then
                    -- Check if this is likely a slot number (1-100) or coordinate
                    if arg >= 1 and arg <= 100 and i > 1 then
                        rawArgs[i] = formatSlot(arg)
                    else
                        rawArgs[i] = formatNumber(arg)
                    end
                elseif type(arg) == "string" then
                    rawArgs[i] = '"' .. arg .. '"'
                else
                    rawArgs[i] = tostring(arg)
                end
            end
            
            local rawCommand = "TDS:Place(" .. table.concat(rawArgs, ", ") .. ")"
            local displayText = rawCommand .. "  -- " .. tostring(slot or "?")
            
            local markDone = addAction(displayText)
            local success, result = pcall(original, self, ...)
            markDone()
            
            if not success then
                warn("[TDS Overlay] Place error:", result)
            end
            return result
        end
    end
    
    -- Wrap Upgrade - shows which slot is being upgraded
    if TDS.Upgrade then
        local original = TDS.Upgrade
        TDS.Upgrade = function(self, slot)
            -- Ensure slot is a whole number
            local slotNum = math.floor(slot)
            local towerName = slotTowers[slotNum]
            local displayText
            
            if towerName then
                displayText = string.format("TDS:Upgrade(%d)  -- %s", slotNum, towerName)
            else
                displayText = string.format("TDS:Upgrade(%d)", slotNum)
            end
            
            local markDone = addAction(displayText)
            local success, result = pcall(original, self, slot)
            markDone()
            
            if not success then
                warn("[TDS Overlay] Upgrade error:", result)
            end
            return result
        end
    end
    
    -- Wrap Sell - shows which slot is being sold
    if TDS.Sell then
        local original = TDS.Sell
        TDS.Sell = function(self, slot)
            local slotNum = math.floor(slot)
            local towerName = slotTowers[slotNum]
            local displayText
            
            if towerName then
                displayText = string.format("TDS:Sell(%d)  -- %s", slotNum, towerName)
            else
                displayText = string.format("TDS:Sell(%d)", slotNum)
            end
            
            local markDone = addAction(displayText)
            local success, result = pcall(original, self, slot)
            markDone()
            
            if success then
                slotTowers[slotNum] = nil
            end
            
            if not success then
                warn("[TDS Overlay] Sell error:", result)
            end
            return result
        end
    end
    
    -- Wrap Mode
    if TDS.Mode then
        local original = TDS.Mode
        TDS.Mode = function(self, mode)
            local rawCommand = 'TDS:Mode("' .. tostring(mode) .. '")'
            local markDone = addAction(rawCommand)
            local success, result = pcall(original, self, mode)
            markDone()
            if not success then warn("[TDS Overlay] Mode error:", result) end
            return result
        end
    end
    
    -- Wrap Loadout
    if TDS.Loadout then
        local original = TDS.Loadout
        TDS.Loadout = function(self, ...)
            local args = {...}
            local rawArgs = {}
            for i, arg in ipairs(args) do
                rawArgs[i] = '"' .. tostring(arg) .. '"'
            end
            local rawCommand = "TDS:Loadout(" .. table.concat(rawArgs, ", ") .. ")"
            
            if #rawCommand > 70 then
                rawCommand = rawCommand:sub(1, 67) .. "..."
            end
            
            local markDone = addAction(rawCommand)
            local success, result = pcall(original, self, ...)
            markDone()
            if not success then warn("[TDS Overlay] Loadout error:", result) end
            return result
        end
    end
    
    -- Wrap Ready
    if TDS.Ready then
        local original = TDS.Ready
        TDS.Ready = function(self)
            local markDone = addAction("TDS:Ready()")
            local success, result = pcall(original, self)
            markDone()
            if not success then warn("[TDS Overlay] Ready error:", result) end
            return result
        end
    end
    
    -- Wrap Ability
    if TDS.Ability then
        local original = TDS.Ability
        TDS.Ability = function(self, slot, ability)
            local slotNum = math.floor(slot)
            local towerName = slotTowers[slotNum]
            local displayText
            
            if towerName then
                displayText = string.format('TDS:Ability(%d, "%s")  -- %s', slotNum, tostring(ability), towerName)
            else
                displayText = string.format('TDS:Ability(%d, "%s")', slotNum, tostring(ability))
            end
            
            local markDone = addAction(displayText)
            local success, result = pcall(original, self, slot, ability)
            markDone()
            if not success then warn("[TDS Overlay] Ability error:", result) end
            return result
        end
    end
    
    -- Wrap SetOption
    if TDS.SetOption then
        local original = TDS.SetOption
        TDS.SetOption = function(self, slot, key, value)
            local rawCommand = 'TDS:SetOption(' .. tostring(slot) .. ', "' .. tostring(key) .. '", ' .. tostring(value) .. ')'
            local markDone = addAction(rawCommand)
            local success, result = pcall(original, self, slot, key, value)
            markDone()
            if not success then warn("[TDS Overlay] SetOption error:", result) end
            return result
        end
    end
    
    -- Welcome message
    task.spawn(function()
        wait(0.5)
        local markDone = addAction("✓ TDS Debug Active")
        wait(0.1)
        markDone()
    end)
    
    print("[TDS Overlay] Complete! Click 'Debug' cube to expand")
    print("[TDS Overlay] Slot tracking active - shows which slot each tower is in")
    return TDS
end

return attachOverlay