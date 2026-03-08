-- VertictHub Key System
-- Taruh di PALING ATAS sssource-1.lua, sebelum semua kode lain

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local API_BASE    = "https://vh-api-alpha.vercel.app"  -- ganti dengan URL Vercel kamu
local KEY_FILE    = "vh_key.txt"                      -- disimpan di folder executor

-- ── HWID: pakai kombinasi UserId + MachineId ──
local function getHWID()
    local uid = tostring(LocalPlayer.UserId)
    local mid = "unknown"
    pcall(function() mid = tostring(game:GetService("RbxAnalyticsService"):GetClientId()) end)
    return uid .. "-" .. mid
end

-- ── Simpan / Load key dari file ───────────────
local function saveKey(key)
    pcall(function() writefile(KEY_FILE, key) end)
end

local function loadKey()
    local ok, key = pcall(function() return readfile(KEY_FILE) end)
    if ok and key and #key > 0 then return key:gsub("%s+", "") end
    return nil
end

-- ── GUI Key System ────────────────────────────

local KeyGui = Instance.new("ScreenGui")
KeyGui.Name           = "VHKeySystem"
KeyGui.ResetOnSpawn   = false
KeyGui.DisplayOrder   = 9999
KeyGui.Parent         = LocalPlayer.PlayerGui

local Overlay = Instance.new("Frame", KeyGui)
Overlay.Size             = UDim2.new(1, 0, 1, 0)
Overlay.BackgroundColor3 = Color3.fromRGB(5, 5, 10)
Overlay.BackgroundTransparency = 0.2
Overlay.BorderSizePixel  = 0

local Card = Instance.new("Frame", KeyGui)
Card.Size = UDim2.new(0, 370, 0, 240)
Card.Position         = UDim2.new(0.5, -180, 0.5, -100)
Card.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
Card.BorderSizePixel  = 0
Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 14)
local CardStroke = Instance.new("UIStroke", Card)
CardStroke.Color     = Color3.fromRGB(55, 55, 100)
CardStroke.Thickness = 1.5

local CardPad = Instance.new("UIPadding", Card)
CardPad.PaddingLeft   = UDim.new(0, 20)
CardPad.PaddingRight  = UDim.new(0, 20)
CardPad.PaddingTop    = UDim.new(0, 20)
CardPad.PaddingBottom = UDim.new(0, 20)

local CardLayout = Instance.new("UIListLayout", Card)
CardLayout.Padding   = UDim.new(0, 10)
CardLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- Logo + title
local TitleL = Instance.new("TextLabel", Card)
TitleL.Size               = UDim2.new(1, 0, 0, 28)
TitleL.BackgroundTransparency = 1
TitleL.Text               = "⚡ VertictHub"
TitleL.TextColor3         = Color3.fromRGB(160, 160, 255)
TitleL.TextSize           = 20
TitleL.Font               = Enum.Font.GothamBold
TitleL.TextXAlignment     = Enum.TextXAlignment.Center
TitleL.LayoutOrder        = 0

local SubL = Instance.new("TextLabel", Card)
SubL.Size               = UDim2.new(1, 0, 0, 16)
SubL.BackgroundTransparency = 1
SubL.Text               = "Masukkan key untuk melanjutkan"
SubL.TextColor3         = Color3.fromRGB(100, 100, 130)
SubL.TextSize           = 12
SubL.Font               = Enum.Font.Gotham
SubL.TextXAlignment     = Enum.TextXAlignment.Center
SubL.LayoutOrder        = 1

-- Input box
local InputBg = Instance.new("Frame", Card)
InputBg.Size             = UDim2.new(1, 0, 0, 38)
InputBg.BackgroundColor3 = Color3.fromRGB(18, 18, 30)
InputBg.BorderSizePixel  = 0
InputBg.LayoutOrder      = 2
Instance.new("UICorner", InputBg).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", InputBg).Color = Color3.fromRGB(45, 45, 80)

local KeyInput = Instance.new("TextBox", InputBg)
KeyInput.Size               = UDim2.new(1, -16, 1, -10)
KeyInput.Position           = UDim2.new(0, 8, 0, 5)
KeyInput.BackgroundTransparency = 1
KeyInput.Text               = ""
KeyInput.PlaceholderText    = "VH-XXXXXX-XXXXXX-XXXXXX"
KeyInput.PlaceholderColor3  = Color3.fromRGB(70, 70, 100)
KeyInput.TextColor3         = Color3.fromRGB(200, 255, 200)
KeyInput.TextSize           = 13
KeyInput.Font               = Enum.Font.GothamMedium
KeyInput.TextXAlignment     = Enum.TextXAlignment.Center
KeyInput.ClearTextOnFocus   = false

-- Submit button
local SubmitBtn = Instance.new("TextButton", Card)
SubmitBtn.Size             = UDim2.new(1, 0, 0, 38)
SubmitBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 130)
SubmitBtn.BorderSizePixel  = 0
SubmitBtn.Text             = "✅ Verifikasi Key"
SubmitBtn.TextColor3       = Color3.fromRGB(220, 220, 255)
SubmitBtn.TextSize         = 13
SubmitBtn.Font             = Enum.Font.GothamBold
SubmitBtn.LayoutOrder      = 3
Instance.new("UICorner", SubmitBtn).CornerRadius = UDim.new(0, 8)

-- Get key button
local GetKeyBtn = Instance.new("TextButton", Card)
GetKeyBtn.Size             = UDim2.new(1, 0, 0, 34)
GetKeyBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
GetKeyBtn.BorderSizePixel  = 0
GetKeyBtn.Text             = "🔗 Belum punya key? Klik di sini"
GetKeyBtn.TextColor3       = Color3.fromRGB(100, 100, 180)
GetKeyBtn.TextSize         = 12
GetKeyBtn.Font             = Enum.Font.Gotham
GetKeyBtn.LayoutOrder      = 4
Instance.new("UICorner", GetKeyBtn).CornerRadius = UDim.new(0, 8)

-- Status label
local StatusL = Instance.new("TextLabel", Card)
StatusL.Size               = UDim2.new(1, 0, 0, 16)
StatusL.BackgroundTransparency = 1
StatusL.Text               = ""
StatusL.TextColor3         = Color3.fromRGB(200, 100, 100)
StatusL.TextSize           = 11
StatusL.Font               = Enum.Font.Gotham
StatusL.TextXAlignment     = Enum.TextXAlignment.Center
StatusL.LayoutOrder        = 5

-- ── Logic ─────────────────────────────────────

local function setStatus(msg, isOk)
    StatusL.Text       = msg
    StatusL.TextColor3 = isOk
        and Color3.fromRGB(100, 220, 120)
        or  Color3.fromRGB(220, 100, 100)
end

local function checkKey(key)
    setStatus("Memeriksa key...", true)
    SubmitBtn.Active = false

    local hwid = getHWID()
    local ok, res = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet(API_BASE .. "/api/checkkey?key=" .. HttpService:UrlEncode(key) .. "&hwid=" .. HttpService:UrlEncode(hwid))
        )
    end)

    SubmitBtn.Active = true

    if not ok then
        setStatus("❌ Gagal koneksi ke server", false)
        return false
    end

    if res.valid then
        local exp = res.expires and (" | Expires: " .. res.expires:sub(1,10)) or ""
        local msg = res.bound and "✅ Key berhasil diaktifkan" .. exp or "✅ Key valid" .. exp
        setStatus(msg, true)
        saveKey(key)
        task.wait(1)
        KeyGui:Destroy()
        return true
    else
        setStatus("❌ " .. (res.reason or "Key tidak valid"), false)
        return false
    end
end

-- Tombol get key — buka browser ke halaman Linkvertise
GetKeyBtn.MouseButton1Click:Connect(function()
    local hwid = getHWID()
    local url  = API_BASE .. "/getkey?hwid=" .. HttpService:UrlEncode(hwid)
    setStatus("Membuka browser...", true)
    pcall(function() setclipboard(url) end)
    setStatus("Link disalin! Buka di browser → selesaikan verifikasi → dapat key", true)
end)

SubmitBtn.MouseButton1Click:Connect(function()
    local key = KeyInput.Text:gsub("%s+", ""):upper()
    if #key < 5 then
        setStatus("❌ Key terlalu pendek", false)
        return
    end
    checkKey(key)
end)

KeyInput.FocusLost:Connect(function(enter)
    if enter then
        local key = KeyInput.Text:gsub("%s+", ""):upper()
        if #key > 5 then checkKey(key) end
    end
end)

-- ── Auto check key tersimpan ──────────────────

local function waitForKey()
    local saved = loadKey()
    if saved and #saved > 5 then
        KeyInput.Text = saved
        setStatus("Memeriksa key tersimpan...", true)
        task.wait(0.5)
        if checkKey(saved) then return end
    end
    -- tunggu user submit
    repeat task.wait(0.1) until not KeyGui.Parent or not KeyGui.Parent.Parent
end

-- Jalankan key check — BLOCK eksekusi sampai valid
local keyValid = false
local thread = coroutine.create(function()
    waitForKey()
    keyValid = true
end)
coroutine.resume(thread)

-- Block sampai key valid atau GUI dihancurkan
while not keyValid and KeyGui and KeyGui.Parent do
    task.wait(0.1)
end

-- Kalau GUI di-destroy paksa (key valid), lanjut ke script utama
-- =====================================================
-- TARUH SISA KODE SCRIPT DI BAWAH INI
-- =====================================================
