-- Hurr Anti-AFK | Master Edition (Fixed Intro & Counters)
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local webhookURL = "https://discord.com/api/webhooks/1258312038560825364/5Og_5cBl5lHHCWFa38msgOiZen0lbGSXOQmkEBuQeVzfzjZZMKsNwT3PxV4QyGvbJ2tK"

-- مفاتيح العدادات
local ns = "hurr_final_2026_fixed"
local apiTotal = "https://api.counterapi.dev/v1/" .. ns .. "/total_execs/up"
local apiUnique = "https://api.counterapi.dev/v1/" .. ns .. "/unique_devices"

-- تنظيف النسخ السابقة
local targetParent = (RunService:IsStudio() and player:WaitForChild("PlayerGui")) or CoreGui
if targetParent:FindFirstChild("HurrAntiAFK_Master") then targetParent.HurrAntiAFK_Master:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HurrAntiAFK_Master"; screenGui.IgnoreGuiInset = true; screenGui.ResetOnSpawn = false; screenGui.Parent = targetParent

local function makeClickThrough(obj)
    obj.Active = false
    if obj:IsA("GuiObject") then obj.Selectable = false end
end

-- === 1. ريجوع الإنترو الفخم (حروف منفصلة + توهج) ===
local function playCinematicIntro()
    local startSound = Instance.new("Sound")
    startSound.SoundId = "rbxassetid://6518811702"; startSound.Volume = 0.8; startSound.Parent = screenGui; startSound:Play()
    local typeSound = Instance.new("Sound")
    typeSound.SoundId = "rbxassetid://421058925"; typeSound.Volume = 0.5; typeSound.Parent = screenGui

    local blur = Instance.new("BlurEffect"); blur.Size = 0; blur.Parent = Lighting
    TweenService:Create(blur, TweenInfo.new(1), {Size = 24}):Play()

    local introContainer = Instance.new("Frame")
    introContainer.Size = UDim2.new(1, 0, 1, 0); introContainer.BackgroundTransparency = 1; introContainer.Parent = screenGui
    makeClickThrough(introContainer)

    local fullText = "Hurr Anti-AFK"
    local letters = {}
    local totalWidth = 0
    local skyBlue = Color3.fromRGB(0, 190, 255)
    
    for i = 1, #fullText do
        local char = fullText:sub(i, i)
        local charWidth = (char == " " and 25 or 50)
        local lbl = Instance.new("TextLabel")
        lbl.Text = char; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 60
        lbl.TextColor3 = Color3.fromRGB(255, 255, 255); lbl.TextTransparency = 1; lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(0, charWidth, 0, 80); lbl.Parent = introContainer
        local glow = Instance.new("TextLabel")
        glow.Text = char; glow.Font = Enum.Font.GothamBold; glow.TextSize = 68
        glow.TextColor3 = skyBlue; glow.TextTransparency = 1; glow.BackgroundTransparency = 1
        glow.Position = UDim2.new(0.5, 0, 0.5, 0); glow.AnchorPoint = Vector2.new(0.5, 0.5)
        glow.Size = UDim2.new(1, 0, 1, 0); glow.ZIndex = lbl.ZIndex - 1; glow.Parent = lbl
        table.insert(letters, {lbl = lbl, glow = glow, char = char})
        totalWidth = totalWidth + charWidth
    end

    local currentPos = (introContainer.AbsoluteSize.X / 2) - (totalWidth / 2)
    for _, item in pairs(letters) do
        item.lbl.Position = UDim2.new(0, currentPos, 0.5, 50)
        currentPos = currentPos + item.lbl.Size.X.Offset
    end

    for i, item in pairs(letters) do
        task.wait(0.07)
        if item.char ~= " " then typeSound:Play() end
        TweenService:Create(item.lbl, TweenInfo.new(0.7, Enum.EasingStyle.Back), {Position = UDim2.new(0, item.lbl.Position.X.Offset, 0.5, -40), TextTransparency = 0}):Play()
        TweenService:Create(item.glow, TweenInfo.new(0.7), {TextTransparency = 0.4}):Play()
    end

    task.wait(3)
    TweenService:Create(blur, TweenInfo.new(1.2), {Size = 0}):Play()
    for _, item in pairs(letters) do
        TweenService:Create(item.lbl, TweenInfo.new(0.6), {TextTransparency = 1, Position = UDim2.new(0, item.lbl.Position.X.Offset, 0.5, -100)}):Play()
        TweenService:Create(item.glow, TweenInfo.new(0.6), {TextTransparency = 1}):Play()
    end
    task.wait(1.5); blur:Destroy(); introContainer:Destroy(); startSound:Destroy(); typeSound:Destroy()
end

-- === 2. فصل العدادات (تشغيل مستمر vs أجهزة فريدة) ===
local function sendAnalytics()
    local totalRuns = "1"
    local uniqueDevices = "1"

    -- زيادة عداد التشغيل (دائماً يزيد)
    pcall(function()
        local res = HttpService:GetAsync(apiTotal)
        totalRuns = tostring(HttpService:JSONDecode(res).count or "1")
    end)

    -- عداد الأجهزة (يزيد فقط لأول مرة لكل UserID)
    pcall(function()
        local userKey = "u_" .. player.UserId
        local check = HttpService:GetAsync("https://api.counterapi.dev/v1/" .. ns .. "/" .. userKey .. "/up")
        local count = HttpService:JSONDecode(check).count
        
        if count == 1 then
            HttpService:GetAsync(apiUnique .. "/up")
        end
        
        local finalUnique = HttpService:GetAsync(apiUnique)
        uniqueDevices = tostring(HttpService:JSONDecode(finalUnique).count or "1")
    end)

    local data = {
        ["embeds"] = {{
            ["title"] = "<:hdiam:1493979575275749386> Hurr System Active",
            ["color"] = 0x00beff,
            ["fields"] = {
                {["name"] = "<:hummy:1493979962108149981> Player", ["value"] = "[" .. player.Name .. "](https://www.roblox.com/users/" .. player.UserId .. "/profile)", ["inline"] = true},
                {["name"] = "<:dunno:1493979357176401931> Total Runs", ["value"] = "``" .. totalRuns .. "``", ["inline"] = true},
                {["name"] = "<:hlock:1493979467003990076> Unique Devices", ["value"] = "``" .. uniqueDevices .. "``", ["inline"] = true},
                {["name"] = "<:hdairy:1493980053648838686> User ID", ["value"] = "``" .. player.UserId .. "``", ["inline"] = false}
            },
            ["footer"] = {["text"] = "Hurr Anti-AFK • " .. os.date("%H:%M:%S")},
            ["thumbnail"] = {["url"] = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. player.UserId .. "&width=420&height=420&format=png"}
        }}
    }

    local function send(content)
        local req = (syn and syn.request) or (http and http.request) or http_request or request
        if req then
            req({Url = webhookURL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(content)})
        else
            HttpService:PostAsync(webhookURL, HttpService:JSONEncode(content))
        end
    end

    pcall(function() send(data) end)
end

-- === 3. HUD SETUP ===
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0, 180, 0, 30); titleLabel.Position = UDim2.new(1, -190, 0, 50)
titleLabel.BackgroundTransparency = 1; titleLabel.Text = "Hurr Anti-AFK"; titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 16; titleLabel.TextXAlignment = Enum.TextXAlignment.Right; titleLabel.Parent = screenGui

local function createRow(icon, pos)
    local f = Instance.new("Frame"); f.Size = UDim2.new(0, 120, 0, 25); f.Position = pos; f.BackgroundTransparency = 1; f.Parent = screenGui
    local i = Instance.new("ImageLabel"); i.Size = UDim2.new(0, 16, 0, 16); i.Position = UDim2.new(0, 0, 0.5, -8); i.Image = icon; i.BackgroundTransparency = 1; i.Parent = f
    local l = Instance.new("TextLabel"); l.Size = UDim2.new(1, -25, 1, 0); l.Position = UDim2.new(0, 25, 0, 0); l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(240, 240, 240); l.TextSize = 12; l.Font = Enum.Font.GothamMedium; l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = f
    return i, l
end

local fpsI, fpsL = createRow("rbxassetid://11419705273", UDim2.new(1, -130, 1, -80))
local upI, upL = createRow("rbxassetid://11419708905", UDim2.new(1, -130, 1, -50))

-- === 4. EXECUTION ===
task.spawn(playCinematicIntro)
task.spawn(sendAnalytics)

local start = tick(); local last = tick(); local frms = 0; local h = 0
RunService.RenderStepped:Connect(function()
    h = (h + 0.005) % 1
    titleLabel.TextColor3 = Color3.fromHSV(h, 0.6, 1)
    local d = tick() - start
    upL.Text = string.format("%02d:%02d:%02d", math.floor(d/3600), math.floor((d%3600)/60), math.floor(d%60))
    frms = frms + 1
    if tick() - last >= 1 then
        fpsL.Text = frms .. " FPS"
        local clr = (frms >= 50 and Color3.fromRGB(0, 255, 127)) or (frms >= 30 and Color3.fromRGB(255, 170, 0)) or Color3.fromRGB(255, 85, 85)
        fpsL.TextColor3, fpsI.ImageColor3 = clr, clr
        frms, last = 0, tick()
    end
end)

player.Idled:Connect(function()
    VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new())
end)
