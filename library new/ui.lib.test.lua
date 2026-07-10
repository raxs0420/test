local Library = {}
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local DefaultTheme = {
    Background = Color3.fromRGB(30,30,30),
    Accent = Color3.fromRGB(70,150,70),
    Text = Color3.fromRGB(255,255,255),
    Button = Color3.fromRGB(70,70,70),
    ButtonHover = Color3.fromRGB(90,90,90),
    ToggleOn = Color3.fromRGB(70,150,70),
    ToggleOff = Color3.fromRGB(50,50,50),
}

local currentTheme = DefaultTheme

function Library:setTheme(theme)
    for k,v in pairs(theme) do currentTheme[k] = v end
end

local function createStyledButton(parent, text, callback, size, position)
    local btn = Instance.new("TextButton")
    btn.Size = size or UDim2.new(0, 150, 0, 28)
    btn.Position = position or UDim2.new(0, 0, 0, 0)
    btn.Text = text or ""
    btn.TextColor3 = currentTheme.Text
    btn.BackgroundColor3 = currentTheme.Button
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 12
    btn.AutoButtonColor = false
    btn.Parent = parent
    Instance.new("UICorner", btn)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = currentTheme.ButtonHover}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = currentTheme.Button}):Play()
    end)
    if callback then btn.MouseButton1Click:Connect(callback) end
    return btn
end

function Library:CreateWindow(opts)
    opts = opts or {}
    local title = opts.Title or "Window"
    local size = opts.Size or UDim2.new(0, 400, 0, 500)
    local position = opts.Position or UDim2.new(0.5, -size.X.Offset/2, 0.5, -size.Y.Offset/2)
    if opts.Theme then Library:setTheme(opts.Theme) end

    local gui = Instance.new("ScreenGui")
    gui.Name = "UIWindow"
    gui.ResetOnSpawn = false
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = size
    frame.Position = position
    frame.BackgroundColor3 = currentTheme.Background
    frame.BackgroundTransparency = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui
    Instance.new("UICorner", frame)

    local titleBar = Instance.new("TextLabel")
    titleBar.Size = UDim2.new(1, 0, 0, 30)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.Text = title
    titleBar.TextColor3 = currentTheme.Text
    titleBar.BackgroundTransparency = 1
    titleBar.Font = Enum.Font.GothamBold
    titleBar.TextSize = 16
    titleBar.TextXAlignment = Enum.TextXAlignment.Left
    titleBar.Parent = frame

    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Size = UDim2.new(0, 25, 0, 25)
    minimizeBtn.Position = UDim2.new(1, -30, 0, 3)
    minimizeBtn.Text = "_"
    minimizeBtn.TextColor3 = currentTheme.Text
    minimizeBtn.BackgroundColor3 = currentTheme.Button
    minimizeBtn.Parent = frame
    Instance.new("UICorner", minimizeBtn)

    local isMinimized = false
    minimizeBtn.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        frame.Visible = not isMinimized
    end)

    local tabContainer = Instance.new("Frame")
    tabContainer.Size = UDim2.new(1, -10, 0, 28)
    tabContainer.Position = UDim2.new(0, 5, 0, 32)
    tabContainer.BackgroundTransparency = 1
    tabContainer.Parent = frame
    local tabLayout = Instance.new("UIListLayout", tabContainer)
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 5)
    tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(1, -10, 1, -70)
    contentFrame.Position = UDim2.new(0, 5, 0, 65)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = frame

    local window = {}
    window.frame = frame
    window.gui = gui
    window.contentFrame = contentFrame
    window.tabs = {}

    function window:SetVisible(visible)
        frame.Visible = visible
    end

    function window:GetFrame()
        return frame
    end

    function window:CreateTab(tabName)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 70, 0, 22)
        btn.Text = tabName
        btn.TextColor3 = currentTheme.Text
        btn.BackgroundColor3 = currentTheme.Button
        btn.Font = Enum.Font.GothamSemibold
        btn.TextSize = 12
        btn.Parent = tabContainer
        Instance.new("UICorner", btn)

        local page = Instance.new("Frame")
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.Parent = contentFrame
        page.Visible = false

        local pageLayout = Instance.new("UIListLayout", page)
        pageLayout.Padding = UDim.new(0, 6)
        pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
        pageLayout.FillDirection = Enum.FillDirection.Vertical

        local tab = {}
        tab.page = page
        tab.btn = btn

        function tab:CreateSection(sectionTitle)
            local section = Instance.new("Frame")
            section.Size = UDim2.new(1, -10, 0, 30)
            section.BackgroundTransparency = 1
            section.Parent = page

            local titleLabel = Instance.new("TextLabel")
            titleLabel.Size = UDim2.new(1, 0, 0, 20)
            titleLabel.Position = UDim2.new(0, 0, 0, 0)
            titleLabel.Text = sectionTitle
            titleLabel.TextColor3 = currentTheme.Accent
            titleLabel.BackgroundTransparency = 1
            titleLabel.Font = Enum.Font.GothamBold
            titleLabel.TextSize = 12
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left
            titleLabel.Parent = section

            local sectionContent = Instance.new("Frame")
            sectionContent.Size = UDim2.new(1, 0, 0, 0)
            sectionContent.Position = UDim2.new(0, 0, 0, 22)
            sectionContent.BackgroundTransparency = 1
            sectionContent.Parent = section

            local contentLayout = Instance.new("UIListLayout", sectionContent)
            contentLayout.Padding = UDim.new(0, 4)
            contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
            contentLayout.FillDirection = Enum.FillDirection.Vertical
            contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

            local sectionObj = {}
            sectionObj.container = sectionContent

            function sectionObj:CreateButton(opts)
                local btn = createStyledButton(sectionContent, opts.Text, opts.Callback)
                return btn
            end

            function sectionObj:CreateToggle(opts)
                local frameToggle = Instance.new("Frame")
                frameToggle.Size = UDim2.new(1, 0, 0, 28)
                frameToggle.BackgroundTransparency = 1
                frameToggle.Parent = sectionContent

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(0, 180, 0, 28)
                label.Position = UDim2.new(0, 0, 0, 0)
                label.Text = opts.Text
                label.TextColor3 = currentTheme.Text
                label.TextSize = 12
                label.TextXAlignment = Enum.TextXAlignment.Left
                label.BackgroundTransparency = 1
                label.Parent = frameToggle

                local toggleBg = Instance.new("Frame")
                toggleBg.Size = UDim2.new(0, 40, 0, 20)
                toggleBg.Position = UDim2.new(1, -45, 0.5, -10)
                toggleBg.BackgroundColor3 = currentTheme.ToggleOff
                toggleBg.Parent = frameToggle
                local corner = Instance.new("UICorner", toggleBg)
                corner.CornerRadius = UDim.new(1, 0)

                local toggleCircle = Instance.new("Frame")
                toggleCircle.Size = UDim2.new(0, 16, 0, 16)
                toggleCircle.Position = UDim2.new(0, 2, 0.5, -8)
                toggleCircle.BackgroundColor3 = currentTheme.Text
                toggleCircle.Parent = toggleBg
                local circleCorner = Instance.new("UICorner", toggleCircle)
                circleCorner.CornerRadius = UDim.new(1, 0)

                local value = opts.Default or false
                local function updateToggle()
                    if value then
                        toggleBg.BackgroundColor3 = currentTheme.ToggleOn
                        toggleCircle.Position = UDim2.new(0, 22, 0.5, -8)
                    else
                        toggleBg.BackgroundColor3 = currentTheme.ToggleOff
                        toggleCircle.Position = UDim2.new(0, 2, 0.5, -8)
                    end
                end
                updateToggle()

                local toggleBtn = Instance.new("TextButton")
                toggleBtn.Size = UDim2.new(1, 0, 1, 0)
                toggleBtn.BackgroundTransparency = 1
                toggleBtn.Parent = frameToggle
                toggleBtn.MouseButton1Click:Connect(function()
                    value = not value
                    updateToggle()
                    if opts.Callback then opts.Callback(value) end
                end)

                return { SetValue = function(self, newVal) value = newVal updateToggle() end }
            end

            function sectionObj:CreateScrollingFrame(opts)
                local scroller = Instance.new("ScrollingFrame")
                scroller.Size = opts.Size or UDim2.new(1, 0, 0, 150)
                scroller.BackgroundColor3 = Color3.fromRGB(40,40,40)
                scroller.BorderSizePixel = 0
                scroller.ScrollBarThickness = 6
                scroller.Parent = sectionContent
                Instance.new("UICorner", scroller)

                local layout = Instance.new("UIListLayout", scroller)
                layout.Padding = UDim.new(0, 4)
                layout.SortOrder = Enum.SortOrder.LayoutOrder
                layout.FillDirection = Enum.FillDirection.Vertical
                layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

                scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
                layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                    scroller.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
                end)

                return scroller
            end

            return sectionObj
        end

        btn.MouseButton1Click:Connect(function()
            for _, t in pairs(window.tabs) do
                t.page.Visible = false
                t.btn.BackgroundColor3 = currentTheme.Button
            end
            page.Visible = true
            btn.BackgroundColor3 = currentTheme.Accent
        end)

        table.insert(window.tabs, tab)
        if #window.tabs == 1 then
            page.Visible = true
            btn.BackgroundColor3 = currentTheme.Accent
        end

        return tab
    end

    return window
end

return Library