-- Modern Scanner V3 Enhanced - Safe Remote Scanning
-- Fixed: Protected remote scanning that won't freeze the game

local TS = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local WS = game:GetService("Workspace")
local RS = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local HTTP = game:GetService("HttpService")
local SG = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")

local Plr = Players.LocalPlayer

-- Use CoreGui for persistence
local function GetGuiParent()
    local success, result = pcall(function()
        return CoreGui
    end)
    if success then
        return CoreGui
    else
        return Plr:WaitForChild("PlayerGui")
    end
end

local PGui = GetGuiParent()

-- Clear existing instances
for _, gui in pairs(PGui:GetChildren()) do
    if gui.Name == "ModernScanner" then
        gui:Destroy()
    end
end

for _, blur in pairs(Lighting:GetChildren()) do
    if blur.Name == "ModernScannerBlur" then
        blur:Destroy()
    end
end

local Results, FilterClass, AutoScan, AutoDebounce, CurrentTab, Tabs, States, SavedSize = {}, "ALL", false, false, nil, {}, {}, nil
local UniqueID, AllRemotes, RemoteText = 0, {}, ""
local RemoteCallLog = {}
local ActiveRemoteMonitor = {}
local RemoteScanRunning = false

local HasFileSystem = pcall(function() 
    return writefile and readfile and isfolder and makefolder
end)

-- Helper Functions
local function Tween(obj, time, props, style, dir)
    TS:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end

local function New(class, props)
    local obj = Instance.new(class)
    for k, v in pairs(props) do obj[k] = v end
    return obj
end

local function Corner(parent, radius)
    return New("UICorner", {Parent = parent, CornerRadius = UDim.new(0, radius or 6)})
end

local function Stroke(parent, color, thickness)
    return New("UIStroke", {Parent = parent, Color = color, Thickness = thickness or 1})
end

local function ShowNotif(title, msg, dur, color)
    dur, color = dur or 3, color or Color3.fromRGB(80, 80, 90)
    local notif = New("Frame", {
        Parent = NotifContainer,
        BackgroundColor3 = color,
        Size = UDim2.new(1, 0, 0, 70),
        Position = UDim2.new(1, 20, 0, 0),
        BorderSizePixel = 0,
        ZIndex = 201
    })
    Corner(notif, 8)
    Stroke(notif, Color3.fromRGB(100, 100, 110))
    
    New("TextLabel", {
        Parent = notif, BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 5), Size = UDim2.new(1, -20, 0, 20),
        Font = Enum.Font.GothamBold, Text = title,
        TextColor3 = Color3.new(1, 1, 1), TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 202
    })
    
    New("TextLabel", {
        Parent = notif, BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 30), Size = UDim2.new(1, -20, 0, 35),
        Font = Enum.Font.Gotham, Text = msg,
        TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = 202
    })
    
    Tween(notif, 0.4, {Position = UDim2.new(0, 0, 0, 0)}, Enum.EasingStyle.Back)
    task.delay(dur, function()
        Tween(notif, 0.3, {Position = UDim2.new(1, 20, 0, 0)})
        task.wait(0.3)
        notif:Destroy()
    end)
end

local function CopyClip(txt)
    local ok = pcall(function()
        (setclipboard or toclipboard or set_clipboard)(txt)
    end)
    if ok then
        ShowNotif("Copy Success", "Copied to clipboard!", 2, Color3.fromRGB(100, 200, 100))
    else
        ShowNotif("Copy Error", "Clipboard not supported!", 2, Color3.fromRGB(220, 50, 50))
    end
    return ok
end

local function SaveToFile(filename, content)
    if not HasFileSystem then
        ShowNotif("File System Error", "writefile not supported on this executor!", 3, Color3.fromRGB(220, 50, 50))
        return false
    end
    
    local success, err = pcall(function()
        if not isfolder("ScannerExports") then
            makefolder("ScannerExports")
        end
        
        local filepath = "ScannerExports/" .. filename
        writefile(filepath, content)
    end)
    
    if success then
        return true
    else
        ShowNotif("File Save Error", tostring(err), 3, Color3.fromRGB(220, 50, 50))
        return false
    end
end

local function BtnEffect(btn, hover, click)
    local orig = btn.BackgroundColor3
    btn.MouseEnter:Connect(function() if not UIS.TouchEnabled then Tween(btn, 0.2, {BackgroundColor3 = hover}) end end)
    btn.MouseLeave:Connect(function() if not UIS.TouchEnabled then Tween(btn, 0.2, {BackgroundColor3 = orig}) end end)
    btn.MouseButton1Down:Connect(function() Tween(btn, 0.1, {BackgroundColor3 = click}) end)
    btn.MouseButton1Up:Connect(function() Tween(btn, 0.1, {BackgroundColor3 = orig}) end)
end

-- Create UI
local SGui = New("ScreenGui", {
    Name = "ModernScanner", 
    Parent = PGui, 
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, 
    ResetOnSpawn = false, 
    DisplayOrder = 100,
    IgnoreGuiInset = true
})

local Blur = New("BlurEffect", {Name = "ModernScannerBlur", Size = 0, Parent = Lighting})

local Main = New("Frame", {
    Name = "MainWindow", Parent = SGui,
    BackgroundColor3 = Color3.fromRGB(25, 25, 30),
    BorderSizePixel = 0,
    Position = UDim2.new(0.5, -225, 0.5, -200),
    Size = UDim2.new(0, 450, 0, 400),
    Active = true, ClipsDescendants = true
})
Corner(Main, 12)
Stroke(Main, Color3.fromRGB(60, 60, 70), 2)

local TBar = New("Frame", {
    Name = "TitleBar", Parent = Main,
    BackgroundColor3 = Color3.fromRGB(255, 85, 0),
    BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 40), Active = true
})
Corner(TBar, 12)

New("TextLabel", {
    Parent = TBar, BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0.6, 0, 1, 0),
    Font = Enum.Font.GothamBold, Text = "Scanner V3 Enhanced",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left
})

local CloseBtn = New("TextButton", {
    Parent = TBar, BackgroundColor3 = Color3.fromRGB(220, 50, 50),
    Position = UDim2.new(1, -38, 0.5, -12), Size = UDim2.new(0, 24, 0, 24),
    Font = Enum.Font.GothamBold, Text = "×",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 18, AutoButtonColor = false
})
Corner(CloseBtn, 6)

local MinBtn = New("TextButton", {
    Parent = TBar, BackgroundColor3 = Color3.fromRGB(80, 80, 90),
    Position = UDim2.new(1, -70, 0.5, -12), Size = UDim2.new(0, 24, 0, 24),
    Font = Enum.Font.GothamBold, Text = "—",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 14, AutoButtonColor = false
})
Corner(MinBtn, 6)

local TabCont = New("Frame", {
    Name = "TabContainer", Parent = Main,
    BackgroundColor3 = Color3.fromRGB(30, 30, 36),
    BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(1, 0, 0, 38)
})

local TabList = New("Frame", {Parent = TabCont, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0)})
local TabLayout = New("UIListLayout", {
    Parent = TabList, FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5)
})
New("UIPadding", {Parent = TabList, PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 4)})

local Content = New("Frame", {
    Name = "ContentContainer", Parent = Main,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 0, 0, 78), Size = UDim2.new(1, 0, 1, -78),
    ClipsDescendants = true
})

local Resize = New("TextButton", {
    Parent = Main, BackgroundColor3 = Color3.fromRGB(60, 60, 70),
    Position = UDim2.new(1, -15, 1, -15), Size = UDim2.new(0, 15, 0, 15),
    Text = "", AutoButtonColor = false
})
Corner(Resize, 4)

NotifContainer = New("Frame", {
    Name = "NotificationContainer", Parent = SGui,
    BackgroundTransparency = 1,
    Position = UDim2.new(1, -320, 1, -20),
    Size = UDim2.new(0, 300, 0, 500), ZIndex = 200
})
New("UIListLayout", {
    Parent = NotifContainer,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
    SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10)
})

-- Dragging
local dragging, dragStart, startPos
TBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, input.Position, Main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        Tween(Main, 0.1, {Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)})
    end
end)

-- Resizing
local resizing, resizeStart, resizeSize
Resize.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        resizing, resizeStart, resizeSize = true, input.Position, Main.Size
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then resizing, SavedSize = false, Main.Size end
        end)
    end
end)

UIS.InputChanged:Connect(function(input)
    if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - resizeStart
        Main.Size = UDim2.new(0, math.max(400, resizeSize.X.Offset + delta.X), 0, math.max(350, resizeSize.Y.Offset + delta.Y))
    end
end)

BtnEffect(CloseBtn, Color3.fromRGB(240, 70, 70), Color3.fromRGB(200, 40, 40))
BtnEffect(MinBtn, Color3.fromRGB(100, 100, 110), Color3.fromRGB(70, 70, 80))

CloseBtn.MouseButton1Click:Connect(function()
    RemoteScanRunning = false
    Tween(Blur, 0.3, {Size = 0})
    Tween(Main, 0.3, {Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0.5, 0, 0.5, 0)}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    task.wait(0.3)
    SGui:Destroy()
    Blur:Destroy()
end)

local IsMin = false
MinBtn.MouseButton1Click:Connect(function()
    IsMin = not IsMin
    if IsMin then
        SavedSize, MinBtn.Text = Main.Size, "+"
        Tween(Main, 0.3, {Size = UDim2.new(0, SavedSize.X.Offset, 0, 40)})
        Tween(Blur, 0.3, {Size = 0})
        Content.Visible, TabCont.Visible = false, false
    else
        MinBtn.Text = "—"
        Tween(Main, 0.3, {Size = SavedSize or UDim2.new(0, 450, 0, 400)})
        Tween(Blur, 0.3, {Size = 15})
        Content.Visible, TabCont.Visible = true, true
    end
end)

-- Toggle Switch
local function CreateToggle(parent, init)
    local frame = New("Frame", {
        Parent = parent,
        BackgroundColor3 = init and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(60, 60, 70),
        Size = UDim2.new(0, 40, 0, 20), BorderSizePixel = 0
    })
    Corner(frame, 10)
    
    local knob = New("Frame", {
        Parent = frame, BackgroundColor3 = Color3.new(1, 1, 1),
        Position = init and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
        Size = UDim2.new(0, 16, 0, 16), BorderSizePixel = 0
    })
    Corner(knob, 8)
    Stroke(knob, Color3.new(0, 0, 0), 1).Transparency = 0.7
    
    local state = init
    local function toggle()
        state = not state
        Tween(frame, 0.2, {BackgroundColor3 = state and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(60, 60, 70)})
        Tween(knob, 0.2, {Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)})
        return state
    end
    
    local function setState(s)
        if state ~= s then
            state = s
            Tween(frame, 0.2, {BackgroundColor3 = state and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(60, 60, 70)})
            Tween(knob, 0.2, {Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)})
        end
    end
    
    return frame, toggle, function() return state end, setState
end

-- Tab System
local function CreateTab(name, icon)
    local btn = New("TextButton", {
        Name = name, Parent = TabList,
        BackgroundColor3 = Color3.fromRGB(40, 40, 48),
        Size = UDim2.new(0, 100, 0, 30),
        Font = Enum.Font.GothamBold, Text = icon .. " " .. name,
        TextColor3 = Color3.fromRGB(150, 150, 150),
        TextSize = 11, AutoButtonColor = false
    })
    Corner(btn, 6)
    
    local ind = New("Frame", {
        Name = "Indicator", Parent = btn,
        BackgroundColor3 = Color3.fromRGB(255, 85, 0),
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(0, 0, 0, 3)
    })
    Corner(ind, 2)
    Stroke(ind, Color3.fromRGB(255, 85, 0), 2).Transparency = 0.5
    
    local cont = New("ScrollingFrame", {
        Name = name .. "Content", Parent = Content,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(1, 0, 0, 0),
        Visible = false, ScrollBarThickness = 5, BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
    })
    
    local lay = New("UIListLayout", {Parent = cont, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)})
    New("UIPadding", {Parent = cont, PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)})
    
    lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        cont.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 16)
    end)
    
    btn.MouseButton1Click:Connect(function()
        for _, tab in pairs(Tabs) do
            Tween(tab.Button, 0.2, {BackgroundColor3 = Color3.fromRGB(40, 40, 48), TextColor3 = Color3.fromRGB(150, 150, 150)})
            Tween(tab.Indicator, 0.2, {Size = UDim2.new(0, 0, 0, 3)})
            if tab.Content.Visible then
                Tween(tab.Content, 0.3, {Position = UDim2.new(-1, 0, 0, 0)})
                task.wait(0.3)
                tab.Content.Visible = false
            end
        end
        
        Tween(btn, 0.2, {BackgroundColor3 = Color3.fromRGB(50, 50, 60), TextColor3 = Color3.new(1, 1, 1)})
        Tween(ind, 0.3, {Size = UDim2.new(1, 0, 0, 3)})
        cont.Visible = true
        cont.Position = UDim2.new(1, 0, 0, 0)
        Tween(cont, 0.3, {Position = UDim2.new(0, 0, 0, 0)})
        CurrentTab = name
    end)
    
    Tabs[name] = {Button = btn, Content = cont, Indicator = ind}
    return cont
end

local function CreateSection(parent, title)
    local sec = New("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(35, 35, 42),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0
    })
    Corner(sec, 8)
    
    New("TextLabel", {
        Parent = sec, BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 18),
        Font = Enum.Font.GothamBold, Text = title,
        TextColor3 = Color3.new(1, 1, 1), TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left
    })
    
    local cont = New("Frame", {
        Parent = sec, BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y
    })
    
    New("UIListLayout", {Parent = cont, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6)})
    New("UIPadding", {Parent = cont, PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 8)})
    
    return cont
end

-- Tabs
local MainTab = CreateTab("Main", "🔍")
local ResultTab = CreateTab("Results", "📋")
local RemoteTab = CreateTab("Remote", "📡")
local DebugTab = CreateTab("Debug", "🐛")

-- MAIN TAB
local CtrlSec = CreateSection(MainTab, "Scanner Controls")

local SearchBox = New("TextBox", {
    Parent = CtrlSec,
    BackgroundColor3 = Color3.fromRGB(50, 50, 60),
    Size = UDim2.new(1, 0, 0, 32),
    Font = Enum.Font.Gotham,
    PlaceholderText = "Enter part name or '*' for all",
    Text = "", TextColor3 = Color3.new(1, 1, 1), TextSize = 12
})
Corner(SearchBox, 6)

local RangeBox = New("TextBox", {
    Parent = CtrlSec,
    BackgroundColor3 = Color3.fromRGB(50, 50, 60),
    Size = UDim2.new(1, 0, 0, 32),
    Font = Enum.Font.Gotham,
    PlaceholderText = "Max distance (studs) - Leave empty for unlimited",
    Text = "", TextColor3 = Color3.new(1, 1, 1), TextSize = 12
})
Corner(RangeBox, 6)

local BtnCont = New("Frame", {Parent = CtrlSec, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32)})
New("UIListLayout", {Parent = BtnCont, FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left, Padding = UDim.new(0, 6)})

local ClassBtn = New("TextButton", {
    Parent = BtnCont,
    BackgroundColor3 = Color3.fromRGB(70, 70, 80),
    Size = UDim2.new(0.3, -4, 0, 32),
    Font = Enum.Font.GothamBold, Text = "ALL",
    TextColor3 = Color3.fromRGB(255, 255, 0), TextSize = 11, AutoButtonColor = false
})
Corner(ClassBtn, 6)

local ScanBtn = New("TextButton", {
    Parent = BtnCont,
    BackgroundColor3 = Color3.fromRGB(0, 170, 0),
    Size = UDim2.new(0.7, -2, 0, 32),
    Font = Enum.Font.GothamBold, Text = "🔍 SCAN NOW",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12, AutoButtonColor = false
})
Corner(ScanBtn, 6)

local ExportMainBtn = New("TextButton", {
    Parent = CtrlSec,
    BackgroundColor3 = Color3.fromRGB(100, 100, 200),
    Size = UDim2.new(1, 0, 0, 32),
    Font = Enum.Font.GothamBold, Text = "📤 EXPORT CONFIG",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12, AutoButtonColor = false
})
Corner(ExportMainBtn, 6)

local AutoSec = CreateSection(MainTab, "Auto Scan")

local AutoCont = New("Frame", {
    Parent = AutoSec,
    BackgroundColor3 = Color3.fromRGB(45, 45, 55),
    Size = UDim2.new(1, 0, 0, 36), BorderSizePixel = 0
})
Corner(AutoCont, 6)

local AutoLabel = New("TextLabel", {
    Parent = AutoCont, BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -60, 1, 0),
    Font = Enum.Font.GothamBold, Text = "Auto Scan: OFF",
    TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left
})

local AutoToggle, AutoToggleFunc, AutoGetState, AutoSetState = CreateToggle(AutoCont, false)
AutoToggle.Position = UDim2.new(1, -48, 0.5, -10)

local AutoBtn = New("TextButton", {
    Parent = AutoCont, BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0), Text = "", AutoButtonColor = false
})

-- RESULTS TAB
local ResSec = CreateSection(ResultTab, "Scan Results")

local ResInfo = New("TextLabel", {
    Parent = ResSec,
    BackgroundColor3 = Color3.fromRGB(45, 45, 55),
    Size = UDim2.new(1, 0, 0, 32),
    Font = Enum.Font.GothamBold, Text = "No results yet - Run a scan first",
    TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 12
})
Corner(ResInfo, 6)

local FilterBox = New("TextBox", {
    Parent = ResSec,
    BackgroundColor3 = Color3.fromRGB(50, 50, 60),
    Size = UDim2.new(1, 0, 0, 32),
    Font = Enum.Font.Gotham,
    PlaceholderText = "Filter results by name...",
    Text = "", TextColor3 = Color3.new(1, 1, 1), TextSize = 12
})
Corner(FilterBox, 6)

local BulkCont = New("Frame", {Parent = ResSec, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36)})
New("UIListLayout", {Parent = BulkCont, FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left, Padding = UDim.new(0, 6)})

local EnableBtn = New("TextButton", {
    Parent = BulkCont,
    BackgroundColor3 = Color3.fromRGB(0, 150, 0),
    Size = UDim2.new(0.5, -3, 0, 36),
    Font = Enum.Font.GothamBold, Text = "✓ ENABLE ALL",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12, AutoButtonColor = false
})
Corner(EnableBtn, 6)

local DisableBtn = New("TextButton", {
    Parent = BulkCont,
    BackgroundColor3 = Color3.fromRGB(170, 50, 50),
    Size = UDim2.new(0.5, -3, 0, 36),
    Font = Enum.Font.GothamBold, Text = "✕ DISABLE ALL",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12, AutoButtonColor = false
})
Corner(DisableBtn, 6)

local ExportResBtn = New("TextButton", {
    Parent = ResSec,
    BackgroundColor3 = Color3.fromRGB(100, 100, 200),
    Size = UDim2.new(1, 0, 0, 36),
    Font = Enum.Font.GothamBold, Text = "📤 EXPORT RESULTS",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12, AutoButtonColor = false
})
Corner(ExportResBtn, 6)

local ResFrame = New("Frame", {
    Parent = ResSec,
    BackgroundColor3 = Color3.fromRGB(30, 30, 36),
    Size = UDim2.new(1, 0, 0, 180), BorderSizePixel = 0
})
Corner(ResFrame, 6)

local ScrollList = New("ScrollingFrame", {
    Parent = ResFrame, Active = true, BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0), CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollBarThickness = 5, BorderSizePixel = 0,
    ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
})

local UIList = New("UIListLayout", {Parent = ScrollList, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3)})
New("UIPadding", {Parent = ScrollList, PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)})

-- REMOTE TAB
local RemSec = CreateSection(RemoteTab, "Remote Finder")

local RemBtnCont = New("Frame", {Parent = RemSec, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40)})
New("UIListLayout", {Parent = RemBtnCont, FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8)})

local SearchRemBtn = New("TextButton", {
    Parent = RemBtnCont,
    BackgroundColor3 = Color3.fromRGB(70, 130, 200),
    Size = UDim2.new(0.3, 0, 1, 0),
    Font = Enum.Font.GothamMedium, Text = "Search",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12, AutoButtonColor = false
})
Corner(SearchRemBtn, 6)

local CopyRemBtn = New("TextButton", {
    Parent = RemBtnCont,
    BackgroundColor3 = Color3.fromRGB(60, 180, 100),
    Size = UDim2.new(0.3, 0, 1, 0),
    Font = Enum.Font.GothamMedium, Text = "Copy All",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12, AutoButtonColor = false
})
Corner(CopyRemBtn, 6)

local ClearRemBtn = New("TextButton", {
    Parent = RemBtnCont,
    BackgroundColor3 = Color3.fromRGB(180, 80, 80),
    Size = UDim2.new(0.3, 0, 1, 0),
    Font = Enum.Font.GothamMedium, Text = "Clear",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12, AutoButtonColor = false
})
Corner(ClearRemBtn, 6)

local ExportRemBtn = New("TextButton", {
    Parent = RemSec,
    BackgroundColor3 = Color3.fromRGB(100, 100, 200),
    Size = UDim2.new(1, 0, 0, 35),
    Font = Enum.Font.GothamBold, Text = "📤 EXPORT REMOTES",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12, AutoButtonColor = false
})
Corner(ExportRemBtn, 6)

local RemStatus = New("TextLabel", {
    Parent = RemSec,
    BackgroundColor3 = Color3.fromRGB(45, 45, 55),
    Size = UDim2.new(1, 0, 0, 30),
    Font = Enum.Font.Gotham, Text = "Press 'Search' to find remotes (Safe Mode)",
    TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left
})
Corner(RemStatus, 6)
New("UIPadding", {Parent = RemStatus, PaddingLeft = UDim.new(0, 8)})

local RemFrame = New("Frame", {
    Parent = RemSec,
    BackgroundColor3 = Color3.fromRGB(30, 30, 36),
    Size = UDim2.new(1, 0, 0, 200), BorderSizePixel = 0
})
Corner(RemFrame, 6)

local RemScroll = New("ScrollingFrame", {
    Parent = RemFrame, Active = true, BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0), CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollBarThickness = 5, BorderSizePixel = 0,
    ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
})

local RemList = New("UIListLayout", {Parent = RemScroll, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5)})
New("UIPadding", {Parent = RemScroll, PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5)})

-- DEBUG TAB
local DbgSec = CreateSection(DebugTab, "UI Monitor")

local DbgInfo = New("TextLabel", {
    Parent = DbgSec,
    BackgroundColor3 = Color3.fromRGB(45, 45, 55),
    Size = UDim2.new(1, 0, 0, 30),
    Font = Enum.Font.Gotham, Text = "Fast monitoring active (0.1s refresh)",
    TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 11
})
Corner(DbgInfo, 6)

local CopyDbgBtn = New("TextButton", {
    Parent = DbgSec,
    BackgroundColor3 = Color3.fromRGB(70, 130, 200),
    Size = UDim2.new(1, 0, 0, 35),
    Font = Enum.Font.GothamMedium, Text = "Copy All Info",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12, AutoButtonColor = false
})
Corner(CopyDbgBtn, 6)

local ExportDbgBtn = New("TextButton", {
    Parent = DbgSec,
    BackgroundColor3 = Color3.fromRGB(100, 100, 200),
    Size = UDim2.new(1, 0, 0, 35),
    Font = Enum.Font.GothamBold, Text = "📤 EXPORT DEBUG",
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12, AutoButtonColor = false
})
Corner(ExportDbgBtn, 6)

local DbgFrame = New("Frame", {
    Parent = DbgSec,
    BackgroundColor3 = Color3.fromRGB(30, 30, 36),
    Size = UDim2.new(1, 0, 0, 200), BorderSizePixel = 0
})
Corner(DbgFrame, 6)

local DbgScroll = New("ScrollingFrame", {
    Parent = DbgFrame, Active = true, BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0), CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollBarThickness = 5, BorderSizePixel = 0,
    ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
})

local DbgLabel = New("TextLabel", {
    Parent = DbgScroll, BackgroundTransparency = 1,
    Size = UDim2.new(1, -10, 0, 0), Position = UDim2.new(0, 5, 0, 5),
    Font = Enum.Font.Gotham, Text = "Waiting for UI...",
    TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y
})

-- Button Effects
BtnEffect(ClassBtn, Color3.fromRGB(90, 90, 100), Color3.fromRGB(60, 60, 70))
BtnEffect(ScanBtn, Color3.fromRGB(0, 190, 0), Color3.fromRGB(0, 150, 0))
BtnEffect(EnableBtn, Color3.fromRGB(0, 170, 0), Color3.fromRGB(0, 130, 0))
BtnEffect(DisableBtn, Color3.fromRGB(190, 70, 70), Color3.fromRGB(150, 40, 40))
BtnEffect(SearchRemBtn, Color3.fromRGB(90, 150, 220), Color3.fromRGB(50, 110, 180))
BtnEffect(CopyRemBtn, Color3.fromRGB(80, 200, 120), Color3.fromRGB(40, 160, 80))
BtnEffect(ClearRemBtn, Color3.fromRGB(200, 100, 100), Color3.fromRGB(160, 60, 60))
BtnEffect(CopyDbgBtn, Color3.fromRGB(90, 150, 220), Color3.fromRGB(50, 110, 180))
BtnEffect(ExportMainBtn, Color3.fromRGB(120, 120, 220), Color3.fromRGB(80, 80, 180))
BtnEffect(ExportResBtn, Color3.fromRGB(120, 120, 220), Color3.fromRGB(80, 80, 180))
BtnEffect(ExportRemBtn, Color3.fromRGB(120, 120, 220), Color3.fromRGB(80, 80, 180))
BtnEffect(ExportDbgBtn, Color3.fromRGB(120, 120, 220), Color3.fromRGB(80, 80, 180))

-- SCANNER LOGIC (keeping original, already working)
local function GetDist(obj)
    if Plr.Character and Plr.Character:FindFirstChild("HumanoidRootPart") and obj then
        local pos
        if obj:IsA("Model") then
            pos = obj.PrimaryPart and obj.PrimaryPart.Position or obj:GetPivot().Position
        elseif obj:IsA("BasePart") then
            pos = obj.Position
        else
            return 999999
        end
        return math.floor((Plr.Character.HumanoidRootPart.Position - pos).Magnitude)
    end
    return 999999
end

local function GetObjID(obj)
    UniqueID = UniqueID + 1
    return string.format("%s_%s_%d", obj:GetFullName(), tostring(obj), UniqueID)
end

local function CreateESP(obj)
    if not obj or not obj:IsA("BasePart") and not obj:IsA("Model") then return end
    local existing = obj:FindFirstChild("ScannerESP")
    if existing then existing:Destroy() end
    
    local bb = New("BillboardGui", {
        Name = "ScannerESP", Parent = obj, AlwaysOnTop = true,
        Size = UDim2.new(0, 100, 0, 30), StudsOffset = Vector3.new(0, 3, 0)
    })
    
    if obj:IsA("Model") then
        bb.Adornee = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
    else
        bb.Adornee = obj
    end
    
    local bg = New("Frame", {
        Parent = bb, BackgroundColor3 = Color3.fromRGB(25, 25, 30),
        BackgroundTransparency = 0.3, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0)
    })
    Corner(bg, 4)
    Stroke(bg, Color3.fromRGB(0, 255, 0))
    
    local lbl = New("TextLabel", {
        Parent = bg, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0),
        Font = Enum.Font.GothamBold, Text = obj.Name,
        TextColor3 = Color3.new(1, 1, 1), TextSize = 12,
        TextScaled = true, TextWrapped = true
    })
    New("UIPadding", {Parent = lbl, PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3)})
end

local function RemoveESP(obj)
    if obj then
        local esp = obj:FindFirstChild("ScannerESP")
        if esp then esp:Destroy() end
    end
end

local function ToggleChams(obj, id, setFunc, force)
    if not obj or not obj.Parent then return end
    local hl = obj:FindFirstChild("ScannerHighlight")
    
    if force == false then
        if hl then hl:Destroy() end
        RemoveESP(obj)
        States[id] = false
        if setFunc then setFunc(false) end
        return
    end
    
    if force == true then
        if not hl then
            New("Highlight", {
                Name = "ScannerHighlight", Adornee = obj, Parent = obj,
                FillColor = Color3.fromRGB(0, 255, 0), FillTransparency = 0.6,
                OutlineColor = Color3.new(1, 1, 1), OutlineTransparency = 0,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            })
        end
        CreateESP(obj)
        States[id] = true
        if setFunc then setFunc(true) end
        return
    end
    
    if hl then
        hl:Destroy()
        RemoveESP(obj)
        States[id] = false
        if setFunc then setFunc(false) end
    else
        New("Highlight", {
            Name = "ScannerHighlight", Adornee = obj, Parent = obj,
            FillColor = Color3.fromRGB(0, 255, 0), FillTransparency = 0.6,
            OutlineColor = Color3.new(1, 1, 1), OutlineTransparency = 0,
            DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        })
        CreateESP(obj)
        States[id] = true
        if setFunc then setFunc(true) end
    end
end

local function TPToObj(obj)
    if not obj or not obj.Parent then
        ShowNotif("Teleport Error", "Object no longer exists!", 2, Color3.fromRGB(220, 50, 50))
        return
    end
    if not Plr.Character or not Plr.Character:FindFirstChild("HumanoidRootPart") then
        ShowNotif("Teleport Error", "Player character not found!", 2, Color3.fromRGB(220, 50, 50))
        return
    end
    
    local pos
    if obj:IsA("Model") then
        pos = obj.PrimaryPart and obj.PrimaryPart.Position or obj:GetPivot().Position
    elseif obj:IsA("BasePart") then
        pos = obj.Position
    else
        ShowNotif("Teleport Error", "Invalid object type!", 2, Color3.fromRGB(220, 50, 50))
        return
    end
    
    Plr.Character.HumanoidRootPart.CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
    ShowNotif("Teleport Success", string.format("Teleported to %s!", obj.Name), 2, Color3.fromRGB(0, 170, 255))
end

local function CopyObjInfo(obj)
    if not obj or not obj.Parent then
        ShowNotif("Copy Error", "Object no longer exists!", 2, Color3.fromRGB(220, 50, 50))
        return
    end
    
    local dist = GetDist(obj)
    local info = string.format("Name: %s\nClass: %s\nPath: %s\nDistance: %d studs", obj.Name, obj.ClassName, obj:GetFullName(), dist)
    CopyClip(info)
end

local function UpdateList()
    local filter = FilterBox.Text:lower()
    table.sort(Results, function(a, b) return GetDist(a.Object) < GetDist(b.Object) end)
    
    local visible, total = 0, 0
    for i = #Results, 1, -1 do
        local data = Results[i]
        local obj, cont = data.Object, data.Container
        
        if not obj or not obj.Parent then
            if cont then cont:Destroy() end
            table.remove(Results, i)
        else
            total = total + 1
            local dist = GetDist(obj)
            local enabled = States[data.UniqueID] == true
            
            data.NameLabel.Text = string.format("%s [%d studs]", obj.Name, dist)
            if data.GetToggleState() ~= enabled then data.SetToggleState(enabled) end
            
            if filter == "" or obj.Name:lower():find(filter) then
                cont.Visible = true
                cont.LayoutOrder = i
                visible = visible + 1
            else
                cont.Visible = false
            end
        end
    end
    
    ResInfo.Text = string.format("Total Results: %d | Visible: %d", total, visible)
    ScrollList.CanvasSize = UDim2.new(0, 0, 0, UIList.AbsoluteContentSize.Y + 8)
end

local function ExecScan()
    for _, c in pairs(ScrollList:GetChildren()) do
        if c:IsA("Frame") and c.Name == "ResultItem" then c:Destroy() end
    end
    Results = {}
    
    local query, maxDist = SearchBox.Text:lower(), tonumber(RangeBox.Text) or 9999999
    if query == "" then
        ShowNotif("Error", "Please enter a search query!", 2, Color3.fromRGB(220, 50, 50))
        return
    end
    
    local found = 0
    for _, obj in pairs(WS:GetDescendants()) do
        local valid = false
        if FilterClass == "ALL" then
            valid = obj:IsA("BasePart") or obj:IsA("Model")
        elseif FilterClass == "PART" then
            valid = obj:IsA("BasePart")
        elseif FilterClass == "MODEL" then
            valid = obj:IsA("Model")
        end
        
        if valid and ((query == "*") or obj.Name:lower():find(query)) and GetDist(obj) <= maxDist then
            found = found + 1
            local id = GetObjID(obj)
            
            local item = New("Frame", {
                Name = "ResultItem", Parent = ScrollList,
                BackgroundColor3 = Color3.fromRGB(45, 45, 55),
                Size = UDim2.new(1, 0, 0, 28), BorderSizePixel = 0
            })
            Corner(item, 4)
            
            local name = New("TextLabel", {
                Parent = item, BackgroundTransparency = 1,
                Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(1, -135, 1, 0),
                Font = Enum.Font.Gotham, TextColor3 = Color3.new(1, 1, 1),
                TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd
            })
            
            local tp = New("TextButton", {
                Parent = item, BackgroundColor3 = Color3.fromRGB(0, 150, 255),
                Position = UDim2.new(1, -125, 0.5, -10), Size = UDim2.new(0, 30, 0, 20),
                Font = Enum.Font.GothamBold, Text = "TP",
                TextColor3 = Color3.new(1, 1, 1), TextSize = 9, AutoButtonColor = false
            })
            Corner(tp, 4)
            
            local copy = New("TextButton", {
                Parent = item, BackgroundColor3 = Color3.fromRGB(255, 150, 0),
                Position = UDim2.new(1, -88, 0.5, -10), Size = UDim2.new(0, 40, 0, 20),
                Font = Enum.Font.GothamBold, Text = "COPY",
                TextColor3 = Color3.new(1, 1, 1), TextSize = 8, AutoButtonColor = false
            })
            Corner(copy, 4)
            
            local init = States[id] == true
            local tog, togFunc, getState, setState = CreateToggle(item, init)
            tog.Position = UDim2.new(1, -42, 0.5, -10)
            
            if init and not obj:FindFirstChild("ScannerHighlight") then
                New("Highlight", {
                    Name = "ScannerHighlight", Adornee = obj, Parent = obj,
                    FillColor = Color3.fromRGB(0, 255, 0), FillTransparency = 0.6,
                    OutlineColor = Color3.new(1, 1, 1), OutlineTransparency = 0,
                    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                })
                CreateESP(obj)
            end
            
            table.insert(Results, {
                Object = obj, UniqueID = id, Container = item, NameLabel = name,
                ToggleFunc = togFunc, GetToggleState = getState, SetToggleState = setState,
                TPButton = tp, CopyButton = copy
            })
            
            local clickArea = New("TextButton", {
                Parent = item, BackgroundTransparency = 1,
                Position = UDim2.new(1, -42, 0.5, -10), Size = UDim2.new(0, 40, 0, 20),
                Text = "", AutoButtonColor = false
            })
            
            clickArea.MouseButton1Click:Connect(function()
                togFunc()
                ToggleChams(obj, id, setState)
            end)
            
            tp.MouseButton1Click:Connect(function() TPToObj(obj) end)
            copy.MouseButton1Click:Connect(function() CopyObjInfo(obj) end)
            
            BtnEffect(tp, Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 130, 220))
            BtnEffect(copy, Color3.fromRGB(255, 170, 20), Color3.fromRGB(220, 130, 0))
        end
    end
    
    UpdateList()
    ShowNotif("Scan Complete", string.format("Found %d objects!", found), 3, Color3.fromRGB(0, 170, 0))
    if Tabs["Results"] then Tabs["Results"].Button.MouseButton1Click:Fire() end
end

-- Export Functions
local function ExportMainConfig()
    local config = string.format([[============================
Scanner Configuration Export
============================
Search Query: %s
Max Distance: %s studs
Class Filter: %s
Auto Scan: %s
============================
Exported: %s
============================
]], SearchBox.Text ~= "" and SearchBox.Text or "Not set",
    RangeBox.Text ~= "" and RangeBox.Text or "Unlimited",
    FilterClass,
    AutoScan and "Enabled" or "Disabled",
    os.date("%Y-%m-%d %H:%M:%S"))
    
    CopyClip(config)
    
    if HasFileSystem then
        local filename = "ScannerConfig_" .. os.time() .. ".txt"
        if SaveToFile(filename, config) then
            ShowNotif("Export Success", "Config copied & saved to:\nScannerExports/" .. filename, 4, Color3.fromRGB(0, 170, 0))
        else
            ShowNotif("Export Partial", "Config copied to clipboard only!", 3, Color3.fromRGB(255, 150, 0))
        end
    else
        ShowNotif("Export Success", "Config copied to clipboard!\n(File save not supported)", 3, Color3.fromRGB(0, 170, 0))
    end
end

local function ExportResults()
    if #Results == 0 then
        ShowNotif("Export Error", "No results to export!", 2, Color3.fromRGB(220, 50, 50))
        return
    end
    
    local export = string.rep("=", 50) .. "\n"
    export = export .. "Scan Results Export\n"
    export = export .. string.rep("=", 50) .. "\n"
    export = export .. string.format("Total Results: %d\n", #Results)
    export = export .. string.format("Filter Class: %s\n", FilterClass)
    export = export .. string.rep("=", 50) .. "\n\n"
    
    for i, data in ipairs(Results) do
        local obj = data.Object
        if obj and obj.Parent then
            local dist = GetDist(obj)
            local enabled = States[data.UniqueID] == true
            export = export .. string.format("[%d] %s\n", i, obj.Name)
            export = export .. string.format("    Class: %s\n", obj.ClassName)
            export = export .. string.format("    Distance: %d studs\n", dist)
            export = export .. string.format("    Path: %s\n", obj:GetFullName())
            export = export .. string.format("    Highlight: %s\n", enabled and "Enabled" or "Disabled")
            export = export .. string.rep("-", 50) .. "\n"
        end
    end
    
    export = export .. "\nExported: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    export = export .. string.rep("=", 50)
    
    CopyClip(export)
    
    if HasFileSystem then
        local filename = "ScanResults_" .. os.time() .. ".txt"
        if SaveToFile(filename, export) then
            ShowNotif("Export Success", string.format("Results copied & saved to:\nScannerExports/%s", filename), 4, Color3.fromRGB(0, 170, 0))
        else
            ShowNotif("Export Partial", "Results copied to clipboard only!", 3, Color3.fromRGB(255, 150, 0))
        end
    else
        ShowNotif("Export Success", "Results copied to clipboard!\n(File save not supported)", 3, Color3.fromRGB(0, 170, 0))
    end
end

local function ExportRemotes()
    if #AllRemotes == 0 then
        ShowNotif("Export Error", "No remotes to export!", 2, Color3.fromRGB(220, 50, 50))
        return
    end
    
    local export = string.rep("=", 50) .. "\n"
    export = export .. "Remote Events/Functions Export\n"
    export = export .. string.rep("=", 50) .. "\n"
    
    local events, funcs, activeCount = 0, 0, 0
    for _, r in ipairs(AllRemotes) do
        if r.Type == "RemoteEvent" then events = events + 1 else funcs = funcs + 1 end
        if RemoteCallLog[r.Path] and RemoteCallLog[r.Path] > 0 then activeCount = activeCount + 1 end
    end
    
    export = export .. string.format("Total Remotes Found: %d\n", #AllRemotes)
    export = export .. string.format("RemoteEvents: %d | RemoteFunctions: %d\n", events, funcs)
    export = export .. string.format("Active Remotes: %d\n", activeCount)
    export = export .. string.rep("=", 50) .. "\n\n"
    
    local sortedRemotes = {}
    for _, r in ipairs(AllRemotes) do table.insert(sortedRemotes, r) end
    table.sort(sortedRemotes, function(a, b)
        local aCall = RemoteCallLog[a.Path] or 0
        local bCall = RemoteCallLog[b.Path] or 0
        if aCall ~= bCall then return aCall > bCall end
        return a.Name < b.Name
    end)
    
    for i, remote in ipairs(sortedRemotes) do
        local calls = RemoteCallLog[remote.Path] or 0
        local icon = remote.Type == "RemoteEvent" and "[EVENT]" or "[FUNC]"
        local status = calls > 0 and "[ACTIVE]" or "[IDLE]"
        export = export .. string.format("[%d] %s %s %s\n", i, status, icon, remote.Name)
        export = export .. string.format("    Type: %s\n", remote.Type)
        export = export .. string.format("    Path: %s\n", remote.Path)
        export = export .. string.format("    Parent: %s\n", remote.Parent or "Unknown")
        export = export .. string.format("    Calls Detected: %d\n", calls)
        export = export .. string.rep("-", 50) .. "\n"
    end
    
    export = export .. "\nExported: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    export = export .. string.rep("=", 50)
    
    CopyClip(export)
    
    if HasFileSystem then
        local filename = "RemotesList_" .. os.time() .. ".txt"
        if SaveToFile(filename, export) then
            ShowNotif("Export Success", string.format("Remotes copied & saved to:\nScannerExports/%s", filename), 4, Color3.fromRGB(0, 170, 0))
        else
            ShowNotif("Export Partial", "Remotes copied to clipboard only!", 3, Color3.fromRGB(255, 150, 0))
        end
    else
        ShowNotif("Export Success", "Remotes copied to clipboard!\n(File save not supported)", 3, Color3.fromRGB(0, 170, 0))
    end
end

local function GetHier(obj, maxDepth)
    maxDepth = maxDepth or 2
    local function buildTree(o, depth, prefix)
        if depth > maxDepth then return "" end
        local result = ""
        local children = o:GetChildren()
        for i, c in ipairs(children) do
            local isLast = i == #children
            local connector = isLast and "└─ " or "├─ "
            local nextPrefix = prefix .. (isLast and "   " or "│  ")
            result = result .. prefix .. connector .. c.Name .. " (" .. c.ClassName .. ")\n"
            if depth < maxDepth then
                result = result .. buildTree(c, depth + 1, nextPrefix)
            end
        end
        return result
    end
    return buildTree(obj, 1, "")
end

local function GetUIProperties(gui)
    local props = {}
    pcall(function() table.insert(props, "DisplayOrder: " .. gui.DisplayOrder) end)
    pcall(function() table.insert(props, "IgnoreGuiInset: " .. tostring(gui.IgnoreGuiInset)) end)
    pcall(function() table.insert(props, "ResetOnSpawn: " .. tostring(gui.ResetOnSpawn)) end)
    pcall(function() table.insert(props, "ZIndexBehavior: " .. tostring(gui.ZIndexBehavior)) end)
    return table.concat(props, " | ")
end

local function CountVisibleElements(gui)
    local visible, total = 0, 0
    for _, desc in ipairs(gui:GetDescendants()) do
        if desc:IsA("GuiObject") then
            total = total + 1
            local success, vis = pcall(function() return desc.Visible end)
            if success and vis then visible = visible + 1 end
        end
    end
    return visible, total
end

local function ExportDebug()
    local export = string.rep("=", 50) .. "\n"
    export = export .. "UI Debug Information Export\n"
    export = export .. string.rep("=", 50) .. "\n"
    export = export .. "Active ScreenGuis:\n"
    export = export .. string.rep("=", 50) .. "\n\n"
    
    local count = 0
    local targetPGui = Plr:FindFirstChild("PlayerGui")
    if targetPGui then
        for _, gui in ipairs(targetPGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Enabled and gui.Name ~= "ModernScanner" 
                and gui.Name ~= "Chat" and gui.Name ~= "BubbleChat" 
                and not gui.Name:find("Roblox") then
                count = count + 1
                local visCount, totalCount = CountVisibleElements(gui)
                local props = GetUIProperties(gui)
                
                export = export .. string.format("[%d] %s\n", count, gui.Name)
                export = export .. string.format("    ClassName: %s\n", gui.ClassName)
                export = export .. string.format("    Elements: %d visible / %d total\n", visCount, totalCount)
                export = export .. "    Properties: " .. props .. "\n"
                export = export .. "    Hierarchy:\n"
                
                local hierarchy = GetHier(gui, 3)
                if hierarchy ~= "" then
                    for line in hierarchy:gmatch("[^\n]+") do
                        export = export .. "        " .. line .. "\n"
                    end
                else
                    export = export .. "        (No children)\n"
                end
                
                export = export .. string.rep("-", 50) .. "\n"
            end
        end
    end
    
    if count == 0 then
        export = export .. "No active UIs detected.\n"
    else
        export = export .. string.format("\nTotal Active UIs: %d\n", count)
    end
    
    export = export .. "\nExported: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    export = export .. string.rep("=", 50)
    
    CopyClip(export)
    
    if HasFileSystem then
        local filename = "UIDebug_" .. os.time() .. ".txt"
        if SaveToFile(filename, export) then
            ShowNotif("Export Success", string.format("Debug info copied & saved to:\nScannerExports/%s", filename), 4, Color3.fromRGB(0, 170, 0))
        else
            ShowNotif("Export Partial", "Debug info copied to clipboard only!", 3, Color3.fromRGB(255, 150, 0))
        end
    else
        ShowNotif("Export Success", "Debug info copied to clipboard!\n(File save not supported)", 3, Color3.fromRGB(0, 170, 0))
    end
end

ExportMainBtn.MouseButton1Click:Connect(ExportMainConfig)
ExportResBtn.MouseButton1Click:Connect(ExportResults)
ExportRemBtn.MouseButton1Click:Connect(ExportRemotes)
ExportDbgBtn.MouseButton1Click:Connect(ExportDebug)

ClassBtn.MouseButton1Click:Connect(function()
    if FilterClass == "ALL" then
        FilterClass, ClassBtn.TextColor3 = "PART", Color3.fromRGB(255, 100, 100)
    elseif FilterClass == "PART" then
        FilterClass, ClassBtn.TextColor3 = "MODEL", Color3.fromRGB(100, 255, 100)
    else
        FilterClass, ClassBtn.TextColor3 = "ALL", Color3.fromRGB(255, 255, 0)
    end
    ClassBtn.Text = FilterClass
end)

ScanBtn.MouseButton1Click:Connect(ExecScan)
SearchBox.FocusLost:Connect(function(enter) if enter then ExecScan() end end)
FilterBox:GetPropertyChangedSignal("Text"):Connect(UpdateList)

EnableBtn.MouseButton1Click:Connect(function()
    local enabled = 0
    for _, data in ipairs(Results) do
        if data.Container and data.Container.Visible and States[data.UniqueID] ~= true then
            ToggleChams(data.Object, data.UniqueID, data.SetToggleState, true)
            enabled = enabled + 1
        end
    end
    UpdateList()
    ShowNotif("Enable All", string.format("Enabled %d highlights!", enabled), 2, Color3.fromRGB(0, 150, 0))
end)

DisableBtn.MouseButton1Click:Connect(function()
    for _, v in pairs(WS:GetDescendants()) do
        if v.Name == "ScannerHighlight" or v.Name == "ScannerESP" then v:Destroy() end
    end
    for _, data in pairs(Results) do States[data.UniqueID] = false end
    UpdateList()
    ShowNotif("Disable All", "All highlights removed!", 2, Color3.fromRGB(170, 50, 50))
end)

AutoBtn.MouseButton1Click:Connect(function()
    AutoScan = AutoToggleFunc()
    AutoLabel.Text = AutoScan and "Auto Scan: ON" or "Auto Scan: OFF"
    AutoLabel.TextColor3 = AutoScan and Color3.new(1, 1, 1) or Color3.fromRGB(200, 200, 200)
    ShowNotif("Auto Scan", AutoScan and "Auto-scan enabled!" or "Auto-scan disabled!", 2, AutoScan and Color3.fromRGB(0, 170, 0) or Color3.fromRGB(80, 80, 90))
end)

WS.DescendantAdded:Connect(function()
    if AutoScan and not AutoDebounce then
        AutoDebounce = true
        task.wait(2)
        if AutoScan then ExecScan() end
        task.wait(3)
        AutoDebounce = false
    end
end)

spawn(function()
    while Main.Parent do
        if #Results > 0 then UpdateList() end
        task.wait(1)
    end
end)

-- SAFE REMOTE MONITORING
local function StartRemoteMonitoring()
    pcall(function()
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" or method == "InvokeServer" then
                pcall(function()
                    local path = self:GetFullName()
                    RemoteCallLog[path] = (RemoteCallLog[path] or 0) + 1
                    ActiveRemoteMonitor[path] = tick()
                end)
            end
            return oldNamecall(self, ...)
        end)
    end)
end

local RemoteItems = {}

local function CreateRemItem(name, type, path, parent, calls, isActive)
    local item = New("Frame", {
        Name = "RemoteResultItem", Parent = RemScroll,
        BackgroundColor3 = isActive and Color3.fromRGB(50, 60, 40) or Color3.fromRGB(40, 40, 55),
        Size = UDim2.new(1, 0, 0, 70), BorderSizePixel = 0
    })
    Corner(item, 6)
    
    if isActive then
        Stroke(item, Color3.fromRGB(0, 255, 100), 2)
    end
    
    local icon = type == "RemoteEvent" and "📡" or "🔧"
    local statusIcon = isActive and "🟢" or "⚪"
    
    New("TextLabel", {
        Parent = item, BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0, 5), Size = UDim2.new(0.5, -10, 0, 18),
        Font = Enum.Font.GothamBold, Text = statusIcon .. " " .. icon .. " " .. name,
        TextColor3 = isActive and Color3.fromRGB(0, 255, 100) or Color3.new(1, 1, 1),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd
    })
    
    New("TextLabel", {
        Parent = item, BackgroundTransparency = 1,
        Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.new(0.25, 0, 0, 18),
        Font = Enum.Font.Gotham, Text = type,
        TextColor3 = type == "RemoteEvent" and Color3.fromRGB(100, 180, 255) or Color3.fromRGB(255, 180, 100),
        TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center
    })
    
    local copyBtn = New("TextButton", {
        Parent = item, BackgroundColor3 = Color3.fromRGB(70, 130, 200),
        Position = UDim2.new(0.8, 0, 0, 5), Size = UDim2.new(0.15, 0, 0, 18),
        Font = Enum.Font.Gotham, Text = "Copy",
        TextColor3 = Color3.new(1, 1, 1), TextSize = 10, AutoButtonColor = false
    })
    Corner(copyBtn, 4)
    
    New("TextLabel", {
        Parent = item, BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0, 25), Size = UDim2.new(1, -16, 0, 14),
        Font = Enum.Font.Gotham, Text = "Path: " .. path,
        TextColor3 = Color3.fromRGB(180, 180, 180), TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd
    })
    
    New("TextLabel", {
        Parent = item, BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0, 40), Size = UDim2.new(1, -16, 0, 12),
        Font = Enum.Font.Gotham, Text = "Parent: " .. parent,
        TextColor3 = Color3.fromRGB(150, 200, 150), TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd
    })
    
    local callLabel = New("TextLabel", {
        Parent = item, BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0, 52), Size = UDim2.new(1, -16, 0, 15),
        Font = Enum.Font.GothamBold,
        Text = isActive and "🔥 ACTIVE - Calls: " .. calls or (calls > 0 and "📊 Calls: " .. calls or "⚪ No calls detected"),
        TextColor3 = isActive and Color3.fromRGB(255, 200, 0) or (calls > 0 and Color3.fromRGB(255, 150, 0) or Color3.fromRGB(120, 120, 120)),
        TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left
    })
    
    copyBtn.MouseButton1Click:Connect(function()
        local fullInfo = string.format("%s (%s)\nPath: %s\nParent: %s\nCalls: %d\nStatus: %s", 
            name, type, path, parent, calls, isActive and "ACTIVE" or "IDLE")
        CopyClip(fullInfo)
        copyBtn.Text = "✓"
        task.wait(1)
        copyBtn.Text = "Copy"
    end)
    
    BtnEffect(copyBtn, Color3.fromRGB(90, 150, 220), Color3.fromRGB(50, 110, 180))
    
    return item, callLabel
end

-- SAFE REMOTE FINDER - Won't freeze gameplay
local function FindRemotes()
    if RemoteScanRunning then
        ShowNotif("Remote Scan", "Scan already in progress!", 2, Color3.fromRGB(255, 150, 0))
        return
    end
    
    RemoteScanRunning = true
    
    for _, c in ipairs(RemScroll:GetChildren()) do 
        if c:IsA("Frame") then c:Destroy() end 
    end
    
    RemStatus.Text = "🔍 Safe scanning (background mode)..."
    AllRemotes, RemoteText = {}, ""
    RemoteCallLog = {}
    RemoteItems = {}
    
    task.spawn(function()
        local scannedPaths = {}
        local itemsProcessed = 0
        
        local function searchSafe(inst, pathStr, depth)
            if not RemoteScanRunning then return end
            if depth > 12 then return end
            
            local success, children = pcall(function() return inst:GetChildren() end)
            if not success then return end
            
            for _, c in ipairs(children) do
                if not RemoteScanRunning then break end
                
                pcall(function()
                    local p = pathStr .. "." .. c.Name
                    
                    if not scannedPaths[p] then
                        scannedPaths[p] = true
                        
                        if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                            local parentName = c.Parent and c.Parent.Name or "Unknown"
                            table.insert(AllRemotes, {
                                Name = c.Name, 
                                Type = c.ClassName, 
                                Path = p, 
                                Instance = c,
                                Parent = parentName
                            })
                        end
                        
                        searchSafe(c, p, depth + 1)
                    end
                end)
                
                itemsProcessed = itemsProcessed + 1
                if itemsProcessed % 50 == 0 then
                    task.wait()
                end
            end
        end
        
        RemStatus.Text = "🔍 Scanning Workspace..."
        searchSafe(WS, "workspace", 0)
        task.wait(0.1)
        
        if RemoteScanRunning then
            RemStatus.Text = "🔍 Scanning ReplicatedStorage..."
            searchSafe(game.ReplicatedStorage, "game.ReplicatedStorage", 0)
            task.wait(0.1)
        end
        
        if RemoteScanRunning then
            RemStatus.Text = "🔍 Scanning ReplicatedFirst..."
            searchSafe(game.ReplicatedFirst, "game.ReplicatedFirst", 0)
            task.wait(0.1)
        end
        
        if RemoteScanRunning then
            RemStatus.Text = "🔍 Scanning Players..."
            searchSafe(Players, "game.Players", 0)
            task.wait(0.1)
        end
        
        if RemoteScanRunning then
            RemStatus.Text = "🔍 Scanning other services..."
            for _, svc in ipairs(game:GetChildren()) do
                if not RemoteScanRunning then break end
                if svc:IsA("Service") and svc.Name ~= "Workspace" and svc.Name ~= "CoreGui" then
                    pcall(function()
                        searchSafe(svc, "game:GetService('" .. svc.Name .. "')", 0)
                    end)
                    task.wait(0.05)
                end
            end
        end
        
        if not RemoteScanRunning then
            RemStatus.Text = "❌ Scan cancelled"
            return
        end
        
        table.sort(AllRemotes, function(a, b)
            local aCall = RemoteCallLog[a.Path] or 0
            local bCall = RemoteCallLog[b.Path] or 0
            if aCall ~= bCall then return aCall > bCall end
            return a.Name:lower() < b.Name:lower()
        end)
        
        pcall(StartRemoteMonitoring)
        
        RemStatus.Text = "🔍 Creating UI..."
        
        local BATCH_SIZE = 10
        local totalBatches = math.ceil(#AllRemotes / BATCH_SIZE)
        
        for batchNum = 1, totalBatches do
            if not RemoteScanRunning then break end
            
            local startIdx = (batchNum - 1) * BATCH_SIZE + 1
            local endIdx = math.min(batchNum * BATCH_SIZE, #AllRemotes)
            
            RemStatus.Text = string.format("Loading UI... %d%%", math.floor((batchNum / totalBatches) * 100))
            
            for i = startIdx, endIdx do
                if not RemoteScanRunning then break end
                
                local r = AllRemotes[i]
                local calls = RemoteCallLog[r.Path] or 0
                local lastCall = ActiveRemoteMonitor[r.Path] or 0
                local isActive = (tick() - lastCall) < 5
                
                local item, callLabel = CreateRemItem(r.Name, r.Type, r.Path, r.Parent, calls, isActive)
                RemoteItems[r.Path] = {Item = item, CallLabel = callLabel}
                
                RemoteText = RemoteText .. (isActive and "[ACTIVE] " or "") .. r.Name .. " (" .. r.Type .. ")\n"
                RemoteText = RemoteText .. "Path: " .. r.Path .. "\n"
                RemoteText = RemoteText .. "Parent: " .. r.Parent .. "\n"
                RemoteText = RemoteText .. "Calls: " .. calls .. "\n"
                RemoteText = RemoteText .. string.rep("-", 40) .. "\n"
            end
            
            task.wait(0.1)
        end
        
        if RemoteScanRunning then
            local events, funcs, activeCount = 0, 0, 0
            for _, r in ipairs(AllRemotes) do
                if r.Type == "RemoteEvent" then events = events + 1 else funcs = funcs + 1 end
                local lastCall = ActiveRemoteMonitor[r.Path] or 0
                if (tick() - lastCall) < 5 then activeCount = activeCount + 1 end
            end
            
            RemStatus.Text = string.format("✅ Complete: %d remotes (%d Active | %d Events, %d Functions)", 
                #AllRemotes, activeCount, events, funcs)
            RemScroll.CanvasSize = UDim2.new(0, 0, 0, RemList.AbsoluteContentSize.Y + 10)
            
            if #AllRemotes > 0 then
                ShowNotif("Remote Finder", string.format("Safe scan complete!\n%d remotes found (%d Active)", 
                    #AllRemotes, activeCount), 3, Color3.fromRGB(70, 130, 200))
            else
                ShowNotif("Remote Finder", "No remotes found", 2, Color3.fromRGB(220, 50, 50))
            end
        end
        
        RemoteScanRunning = false
    end)
end

task.spawn(function()
    while task.wait(1) do
        if CurrentTab == "Remote" and #AllRemotes > 0 and not RemoteScanRunning then
            local activeCount = 0
            for path, data in pairs(RemoteItems) do
                local calls = RemoteCallLog[path] or 0
                local lastCall = ActiveRemoteMonitor[path] or 0
                local isActive = (tick() - lastCall) < 5
                
                if isActive then activeCount = activeCount + 1 end
                
                if data.CallLabel then
                    data.CallLabel.Text = isActive and "🔥 ACTIVE - Calls: " .. calls 
                        or (calls > 0 and "📊 Calls: " .. calls or "⚪ No calls detected")
                    data.CallLabel.TextColor3 = isActive and Color3.fromRGB(255, 200, 0) 
                        or (calls > 0 and Color3.fromRGB(255, 150, 0) or Color3.fromRGB(120, 120, 120))
                end
                
                if data.Item then
                    data.Item.BackgroundColor3 = isActive and Color3.fromRGB(50, 60, 40) or Color3.fromRGB(40, 40, 55)
                end
            end
            
            local events, funcs = 0, 0
            for _, r in ipairs(AllRemotes) do
                if r.Type == "RemoteEvent" then events = events + 1 else funcs = funcs + 1 end
            end
            
            RemStatus.Text = string.format("✅ Complete: %d remotes (%d Active | %d Events, %d Functions)", 
                #AllRemotes, activeCount, events, funcs)
        end
    end
end)

SearchRemBtn.MouseButton1Click:Connect(FindRemotes)

CopyRemBtn.MouseButton1Click:Connect(function()
    if #AllRemotes == 0 then
        ShowNotif("Remote Finder", "No results to copy!", 2, Color3.fromRGB(220, 50, 50))
        return
    end
    CopyClip(RemoteText)
    CopyRemBtn.Text = "Copied!"
    task.wait(1)
    CopyRemBtn.Text = "Copy All"
end)

ClearRemBtn.MouseButton1Click:Connect(function()
    RemoteScanRunning = false
    for _, c in ipairs(RemScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    AllRemotes, RemoteText = {}, ""
    RemoteCallLog, RemoteItems, ActiveRemoteMonitor = {}, {}, {}
    RemStatus.Text = "Press 'Search' to find remotes (Safe Mode)"
    RemScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    ShowNotif("Remote Finder", "Results cleared", 2, Color3.fromRGB(80, 80, 90))
end)

-- FAST UI DEBUG
local function UpdateDbg()
    if CurrentTab ~= "Debug" then return end
    local txt = "🖥️ ACTIVE UI ELEMENTS (Fast Scan Mode)\n" .. string.rep("═", 50) .. "\n\n"
    local uiCount = 0
    
    local targetPGui = Plr:FindFirstChild("PlayerGui")
    if targetPGui then
        for _, gui in ipairs(targetPGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Enabled and gui.Name ~= "ModernScanner" 
                and gui.Name ~= "Chat" and gui.Name ~= "BubbleChat" 
                and not gui.Name:find("Roblox") then
                
                uiCount = uiCount + 1
                local visCount, totalCount = CountVisibleElements(gui)
                local props = GetUIProperties(gui)
                
                txt = txt .. string.format("📌 [%d] %s\n", uiCount, gui.Name)
                txt = txt .. string.format("   ClassName: %s\n", gui.ClassName)
                txt = txt .. string.format("   Elements: %d visible / %d total\n", visCount, totalCount)
                txt = txt .. "   Properties: " .. props .. "\n"
                txt = txt .. "   Hierarchy:\n"
                
                local hierarchy = GetHier(gui, 2)
                if hierarchy ~= "" then
                    txt = txt .. hierarchy
                else
                    txt = txt .. "      (No children)\n"
                end
                
                txt = txt .. string.rep("─", 50) .. "\n\n"
            end
        end
    end
    
    if uiCount == 0 then
        txt = txt .. "⚪ No active custom UIs detected.\n"
    else
        txt = txt .. string.format("\n✅ Total Active UIs: %d\n", uiCount)
    end
    
    txt = txt .. "\n" .. string.rep("═", 50) .. "\n"
    txt = txt .. "Last Update: " .. os.date("%H:%M:%S") .. " (Refresh: 0.1s)"
    
    DbgLabel.Text = txt
    DbgScroll.CanvasSize = UDim2.new(0, 0, 0, DbgLabel.AbsoluteSize.Y + 20)
end

CopyDbgBtn.MouseButton1Click:Connect(function()
    CopyClip(DbgLabel.Text)
    CopyDbgBtn.Text = "Copied!"
    task.wait(1)
    CopyDbgBtn.Text = "Copy All Info"
end)

task.spawn(function()
    while task.wait(0.1) do UpdateDbg() end
end)

-- INIT
if Tabs["Main"] then Tabs["Main"].Button.MouseButton1Click:Fire() end
Main.Size, Main.Position = UDim2.new(0, 0, 0, 0), UDim2.new(0.5, 0, 0.5, 0)
Tween(Main, 0.5, {Size = UDim2.new(0, 450, 0, 400), Position = UDim2.new(0.5, -225, 0.5, -200)}, Enum.EasingStyle.Back)
Tween(Blur, 0.5, {Size = 15})

local fsStatus = HasFileSystem and "✅ File exports enabled" or "📋 Clipboard-only mode"
local guiLocation = (PGui.Name == "CoreGui") and "✅ Persistent mode (CoreGui)" or "⚠️ PlayerGui mode"
ShowNotif("Scanner Loaded", string.format("Modern Scanner V3 Enhanced Ready!\n%s\n%s\nRemote scan: Safe mode enabled", fsStatus, guiLocation), 5, Color3.fromRGB(255, 85, 0))
