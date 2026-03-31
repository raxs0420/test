-- // TDS Debug Overlay
-- // GitHub: https://raw.githubusercontent.com/yourusername/yourrepo/main/tds_debug_overlay.lua
-- //
-- // USAGE:
-- //   local TDS = loadstring(game:HttpGet("your_tds_library_url"))()
-- //   loadstring(game:HttpGet("https://raw.githubusercontent.com/yourusername/yourrepo/main/tds_debug_overlay.lua"))()(TDS)
-- //   TDS:Mode("Polluted")  -- This will now show in the overlay

print("[TDS Overlay] Loading...")

-- The main overlay function
local function attachOverlay(TDS)
    if not TDS then
        warn("[TDS Overlay] Error: TDS table is nil")
        return nil
    end
    
    print("[TDS Overlay] Attaching to TDS...")
    
    -- Count methods
    local methodCount = 0
    for k, v in pairs(TDS) do
        if type(v) == "function" then
            methodCount = methodCount + 1
        end
    end
    
    if methodCount == 0 then
        warn("[TDS Overlay] Error: No methods found in TDS")
        return nil
    end
    
    print("[TDS Overlay] Found " .. methodCount .. " methods to monitor")
    
    local Players = game:GetService("Players")
    local UIS = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")
    local RunService = game:GetService("RunService")
    local localPlayer = Players.LocalPlayer
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    
    -- Remove old overlay if exists
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
    
    -- Main window
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 420, 0, 380)
    mainFrame.Position = UDim2.new(0.5, -210, 0.05, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 23)
    mainFrame.BorderSizePixel = 1
    mainFrame.BorderColor3 = Color3.fromRGB(55, 55, 75)
    mainFrame.ClipsDescendants = false
    mainFrame.Parent = screenGui
    
    -- Corner radius
    local corner = Instance.new("UICorner", mainFrame)
    corner.CornerRadius = UDim.new(0, 8)
    
    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 42)
    titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    
    local titleCorner = Instance.new("UICorner", titleBar)
    titleCorner.CornerRadius = UDim.new(0, 8)
    
    -- Drag handle icon
    local dragHandle = Instance.new("TextLabel")
    dragHandle.Text = "⋮⋮"
    dragHandle.Size = UDim2.new(0, 35, 1, 0)
    dragHandle.Position = UDim2.new(0, 8, 0, 0)
    dragHandle.BackgroundTransparency = 1
    dragHandle.TextColor3 = Color3.fromRGB(140, 140, 165)
    dragHandle.TextXAlignment = Enum.TextXAlignment.Center
    dragHandle.Font = Enum.Font.Gotham
    dragHandle.TextSize = 16
    dragHandle.Parent = titleBar
    
    local titleText = Instance.new("TextLabel")
    titleText.Text = "TDS Debug (" .. methodCount .. ")"
    titleText.Size = UDim2.new(1, -150, 1, 0)
    titleText.Position = UDim2.new(0, 45, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.TextColor3 = Color3.fromRGB(225, 225, 245)
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Font = Enum.Font.GothamBold
    titleText.TextSize = 12
    titleText.Parent = titleBar
    
    local counterText = Instance.new("TextLabel")
    counterText.Text = "0/0"
    counterText.Size = UDim2.new(0, 50, 1, 0)
    counterText.Position = UDim2.new(1, -115, 0, 0)
    counterText.BackgroundTransparency = 1
    counterText.TextColor3 = Color3.fromRGB(140, 140, 165)
    counterText.TextXAlignment = Enum.TextXAlignment.Right
    counterText.Font = Enum.Font.Gotham
    counterText.TextSize = 10
    counterText.Parent = titleBar
    
    -- Buttons
    local closeBtn = Instance.new("TextButton")
    closeBtn.Text = "✕"
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -36, 0, 7)
    closeBtn.BackgroundColor3 = Color3.fromRGB(55, 40, 40)
    closeBtn.TextColor3 = Color3.fromRGB(210, 110, 110)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = titleBar
    
    local closeCorner = Instance.new("UICorner", closeBtn)
    closeCorner.CornerRadius = UDim.new(0, 5)
    
    closeBtn.MouseButton1Click:Connect(function()
        screenGui:Destroy()
    end)
    
    -- For mobile touch
    closeBtn.TouchTap:Connect(function()
        screenGui:Destroy()
    end)
    
    local minBtn = Instance.new("TextButton")
    minBtn.Text = "−"
    minBtn.Size = UDim2.new(0, 28, 0, 28)
    minBtn.Position = UDim2.new(1, -72, 0, 7)
    minBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    minBtn.TextColor3 = Color3.fromRGB(190, 190, 215)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 18
    minBtn.BorderSizePixel = 0
    minBtn.Parent = titleBar
    
    local minCorner = Instance.new("UICorner", minBtn)
    minCorner.CornerRadius = UDim.new(0, 5)
    
    local clearBtn = Instance.new("TextButton")
    clearBtn.Text = "🗑"
    clearBtn.Size = UDim2.new(0, 28, 0, 28)
    clearBtn.Position = UDim2.new(1, -108, 0, 7)
    clearBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    clearBtn.TextColor3 = Color3.fromRGB(190, 190, 215)
    clearBtn.Font = Enum.Font.GothamBold
    clearBtn.TextSize = 12
    clearBtn.BorderSizePixel = 0
    clearBtn.Parent = titleBar
    
    local clearCorner = Instance.new("UICorner", clearBtn)
    clearCorner.CornerRadius = UDim.new(0, 5)
    
    -- Scroll frame
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Size = UDim2.new(1, -12, 1, -52)
    scrollFrame.Position = UDim2.new(0, 6, 0, 48)
    scrollFrame.BackgroundColor3 = Color3.fromRGB(13, 13, 18)
    scrollFrame.BorderSizePixel = 0
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 95)
    scrollFrame.Parent = mainFrame
    
    local scrollCorner = Instance.new("UICorner", scrollFrame)
    scrollCorner.CornerRadius = UDim.new(0, 6)
    
    -- UIListLayout for vertical stacking
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 2)
    layout.Parent = scrollFrame
    
    -- Padding
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 6)
    padding.PaddingBottom = UDim.new(0, 6)
    padding.PaddingLeft = UDim.new(0, 6)
    padding.PaddingRight = UDim.new(0, 6)
    padding.Parent = scrollFrame
    
    -- Variables
    local queue = {}
    local actionCount = 0
    local completedCount = 0
    local minimized = false
    
    -- Spinner animation
    local spinnerFrames = {"◐", "◓", "◑", "◒"}
    local spinnerIndex = 0
    
    task.spawn(function()
        while screenGui and screenGui.Parent do
            spinnerIndex = (spinnerIndex % 4) + 1
            for _, entry in ipairs(queue) do
                if entry.status == "running" and entry.icon then
                    entry.icon.Text = spinnerFrames[spinnerIndex]
                end
            end
            task.wait(0.12)
        end
    end)
    
    -- Function to update all layout orders (newest at top = lowest LayoutOrder)
    local function updateLayoutOrders()
        local children = {}
        for _, child in pairs(scrollFrame:GetChildren()) do
            if child:IsA("Frame") and child ~= layout and child ~= padding then
                table.insert(children, child)
            end
        end
        
        -- Reverse order so newest (last in table) gets lowest LayoutOrder
        for i = #children, 1, -1 do
            local orderIndex = (#children - i)
            children[i].LayoutOrder = orderIndex
        end
        
        -- Update canvas size
        local totalHeight = 0
        for _, child in ipairs(children) do
            totalHeight = totalHeight + child.Size.Y.Offset + 2
        end
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight + 10)
        
        -- Scroll to top to show newest
        scrollFrame.CanvasPosition = Vector2.new(0, 0)
    end
    
    -- Add action function (adds to end of list but will be ordered to top)
    local function addAction(text, status)
        actionCount = actionCount + 1
        
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 32)
        row.BackgroundColor3 = Color3.fromRGB(23, 23, 30)
        row.BorderSizePixel = 0
        row.Parent = scrollFrame
        
        local rowCorner = Instance.new("UICorner", row)
        rowCorner.CornerRadius = UDim.new(0, 4)
        
        local icon = Instance.new("TextLabel")
        icon.Size = UDim2.new(0, 28, 1, 0)
        icon.Position = UDim2.new(0, 5, 0, 0)
        icon.BackgroundTransparency = 1
        icon.TextXAlignment = Enum.TextXAlignment.Center
        icon.Font = Enum.Font.Gotham
        icon.TextSize = 12
        icon.Parent = row
        
        local timestamp = Instance.new("TextLabel")
        timestamp.Text = os.date("%H:%M:%S")
        timestamp.Size = UDim2.new(0, 55, 1, 0)
        timestamp.Position = UDim2.new(0, 38, 0, 0)
        timestamp.BackgroundTransparency = 1
        timestamp.TextColor3 = Color3.fromRGB(110, 110, 135)
        timestamp.TextXAlignment = Enum.TextXAlignment.Left
        timestamp.Font = Enum.Font.Code
        timestamp.TextSize = 9
        timestamp.Parent = row
        
        local actionText = Instance.new("TextLabel")
        actionText.Text = text
        actionText.Size = UDim2.new(1, -165, 1, 0)
        actionText.Position = UDim2.new(0, 98, 0, 0)
        actionText.BackgroundTransparency = 1
        actionText.TextColor3 = Color3.fromRGB(215, 215, 235)
        actionText.TextXAlignment = Enum.TextXAlignment.Left
        actionText.Font = Enum.Font.Code
        actionText.TextSize = 10
        actionText.TextTruncate = Enum.TextTruncate.AtEnd
        actionText.Parent = row
        
        local statusText = Instance.new("TextLabel")
        statusText.Size = UDim2.new(0, 65, 1, 0)
        statusText.Position = UDim2.new(1, -70, 0, 0)
        statusText.BackgroundTransparency = 1
        statusText.TextXAlignment = Enum.TextXAlignment.Right
        statusText.Font = Enum.Font.GothamBold
        statusText.TextSize = 9
        statusText.Parent = row
        
        local entry = {row = row, icon = icon, statusText = statusText, actionText = actionText, status = status}
        
        if status == "running" then
            icon.Text = spinnerFrames[1]
            icon.TextColor3 = Color3.fromRGB(255, 210, 70)
            statusText.Text = "RUN"
            statusText.TextColor3 = Color3.fromRGB(255, 210, 70)
        elseif status == "done" then
            icon.Text = "✓"
            icon.TextColor3 = Color3.fromRGB(80, 255, 120)
            statusText.Text = "DONE"
            statusText.TextColor3 = Color3.fromRGB(80, 255, 120)
            completedCount = completedCount + 1
        elseif status == "error" then
            icon.Text = "✗"
            icon.TextColor3 = Color3.fromRGB(255, 90, 90)
            statusText.Text = "ERR"
            statusText.TextColor3 = Color3.fromRGB(255, 90, 90)
        else
            icon.Text = "○"
            icon.TextColor3 = Color3.fromRGB(255, 160, 110)
            statusText.Text = "PEND"
            statusText.TextColor3 = Color3.fromRGB(255, 160, 110)
        end
        
        -- Add to queue
        table.insert(queue, entry)
        
        -- Update layout orders to put newest at top
        updateLayoutOrders()
        
        counterText.Text = completedCount .. "/" .. actionCount
        
        return entry
    end
    
    -- Update status function
    local function updateStatus(entry, newStatus)
        entry.status = newStatus
        if newStatus == "done" then
            entry.icon.Text = "✓"
            entry.icon.TextColor3 = Color3.fromRGB(80, 255, 120)
            entry.statusText.Text = "DONE"
            entry.statusText.TextColor3 = Color3.fromRGB(80, 255, 120)
            completedCount = completedCount + 1
            counterText.Text = completedCount .. "/" .. actionCount
        elseif newStatus == "error" then
            entry.icon.Text = "✗"
            entry.icon.TextColor3 = Color3.fromRGB(255, 90, 90)
            entry.statusText.Text = "ERR"
            entry.statusText.TextColor3 = Color3.fromRGB(255, 90, 90)
            entry.actionText.TextColor3 = Color3.fromRGB(255, 140, 140)
        end
    end
    
    -- Minimize
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            local tween = TweenService:Create(mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                Size = UDim2.new(0, 420, 0, 46)
            })
            tween:Play()
            scrollFrame.Visible = false
            minBtn.Text = "+"
        else
            local tween = TweenService:Create(mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                Size = UDim2.new(0, 420, 0, 380)
            })
            tween:Play()
            scrollFrame.Visible = true
            minBtn.Text = "−"
            task.wait(0.2)
            updateLayoutOrders()
        end
    end)
    
    -- Also handle touch for mobile
    minBtn.TouchTap:Connect(function()
        minimized = not minimized
        if minimized then
            local tween = TweenService:Create(mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                Size = UDim2.new(0, 420, 0, 46)
            })
            tween:Play()
            scrollFrame.Visible = false
            minBtn.Text = "+"
        else
            local tween = TweenService:Create(mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                Size = UDim2.new(0, 420, 0, 380)
            })
            tween:Play()
            scrollFrame.Visible = true
            minBtn.Text = "−"
            task.wait(0.2)
            updateLayoutOrders()
        end
    end)
    
    -- Clear
    clearBtn.MouseButton1Click:Connect(function()
        for _, child in pairs(scrollFrame:GetChildren()) do
            if child:IsA("Frame") and child ~= layout and child ~= padding then
                child:Destroy()
            end
        end
        queue = {}
        actionCount = 0
        completedCount = 0
        counterText.Text = "0/0"
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    end)
    
    clearBtn.TouchTap:Connect(function()
        for _, child in pairs(scrollFrame:GetChildren()) do
            if child:IsA("Frame") and child ~= layout and child ~= padding then
                child:Destroy()
            end
        end
        queue = {}
        actionCount = 0
        completedCount = 0
        counterText.Text = "0/0"
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    end)
    
    -- DRAG FUNCTIONALITY - FIXED FOR MOBILE
    local dragData = {
        dragging = false,
        startPos = nil,
        startMousePos = nil,
        connections = {}
    }
    
    local function startDrag(input)
        dragData.dragging = true
        dragData.startPos = mainFrame.Position
        dragData.startMousePos = input.Position
        
        -- Clean up old connections
        if dragData.connections.drag then
            dragData.connections.drag:Disconnect()
        end
        if dragData.connections.release then
            dragData.connections.release:Disconnect()
        end
        
        -- Create new connections
        dragData.connections.drag = UIS.InputChanged:Connect(function(dragInput)
            if dragData.dragging and (dragInput.UserInputType == Enum.UserInputType.MouseMovement or 
               dragInput.UserInputType == Enum.UserInputType.Touch) then
                local delta = dragInput.Position - dragData.startMousePos
                mainFrame.Position = UDim2.new(
                    dragData.startPos.X.Scale,
                    dragData.startPos.X.Offset + delta.X,
                    dragData.startPos.Y.Scale,
                    dragData.startPos.Y.Offset + delta.Y
                )
            end
        end)
        
        dragData.connections.release = UIS.InputEnded:Connect(function(endedInput)
            if dragData.dragging and (endedInput.UserInputType == Enum.UserInputType.MouseButton1 or
               endedInput.UserInputType == Enum.UserInputType.Touch) then
                dragData.dragging = false
                dragData.connections.drag:Disconnect()
                dragData.connections.release:Disconnect()
                dragData.connections = {}
            end
        end)
    end
    
    -- Make title bar and drag handle draggable for both mouse and touch
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            startDrag(input)
        end
    end)
    
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            startDrag(input)
        end
    end)
    
    -- WRAP ALL TDS METHODS
    print("[TDS Overlay] Wrapping methods...")
    
    for methodName, methodFunc in pairs(TDS) do
        if type(methodFunc) == "function" then
            local originalMethod = methodFunc
            TDS[methodName] = function(self, ...)
                local args = {...}
                
                -- Format the action label
                local label = methodName
                if #args > 0 then
                    local argStrings = {}
                    for i, arg in ipairs(args) do
                        local argType = type(arg)
                        if argType == "string" then
                            argStrings[i] = '"' .. arg .. '"'
                        elseif argType == "number" then
                            argStrings[i] = string.format("%g", arg)
                        elseif argType == "boolean" then
                            argStrings[i] = tostring(arg)
                        elseif argType == "table" then
                            argStrings[i] = "{...}"
                        else
                            argStrings[i] = tostring(arg)
                        end
                    end
                    label = label .. "(" .. table.concat(argStrings, ", ") .. ")"
                else
                    label = label .. "()"
                end
                
                if #label > 55 then
                    label = label:sub(1, 52) .. "..."
                end
                
                local entry = addAction(label, "running")
                
                local success, result = pcall(originalMethod, self, table.unpack(args))
                
                if success then
                    updateStatus(entry, "done")
                else
                    updateStatus(entry, "error")
                    warn("[TDS Overlay] Error in " .. methodName .. ": " .. tostring(result))
                end
                
                return result
            end
        end
    end
    
    -- Welcome messages
    addAction("✓ Overlay Active", "done")
    addAction("→ Monitoring " .. methodCount .. " methods", "pending")
    
    print("[TDS Overlay] Successfully attached to TDS!")
    print("[TDS Overlay] Window is draggable on PC and mobile")
    print("[TDS Overlay] Newest actions appear at the TOP of the list")
    
    return TDS
end

-- Return the attach function
return attachOverlay