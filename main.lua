-- Lunar Anti-AFK | Visuals & Safe Analytics (first-run only)
-- WARNING: Embedding a Discord webhook in client-side code can leak information.
-- Use ENABLE_ANALYTICS = true only for personal/testing use. Analytics will send only once per-user (first run),
-- using a remote counter API to detect unique devices.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer

-- =======================
-- CONFIG
-- =======================
local GUI_NAME = "Lunar Anti-AFK"
local NAMESPACE = "lunar"

-- If you want the webhook to send on first run, set ENABLE_ANALYTICS = true and provide a webhook below.
local ENABLE_ANALYTICS = true
local WEBHOOK_URL = "https://discord.com/api/webhooks/1258312038560825364/5Og_5cBl5lHHCWFa38msgOiZen0lbGSXOQmkEBuQeVzfzjZZMKsNwT3PxV4QyGvbJ2tK"

-- Counter API endpoints (used to detect unique first-run per UserId and to increment total runs)
local apiTotal = "https://api.counterapi.dev/v1/" .. NAMESPACE .. "/total_execs/up"
local apiUnique = "https://api.counterapi.dev/v1/" .. NAMESPACE .. "/unique_devices"

-- Analytics send rate-limiting (in case)
local ANALYTICS_MIN_INTERVAL = 60
local _lastAnalyticsSent = 0

-- Cinematic intro toggle (pulled from Hurr's style)
local ENABLE_CINEMATIC_INTRO = true

-- Theme (updated to neon accent + minimal text)
local theme = {
    accent = Color3.fromRGB(126, 87, 255), -- neon purple
    accent2 = Color3.fromRGB(0, 190, 255), -- cyan accent for subtle gradient
    text = Color3.fromRGB(245, 245, 250),
}

-- =======================
-- Helpers
-- =======================
local function safeRequest(payload)
    if type(payload) ~= "table" or type(payload.Url) ~= "string" then
        return nil, "invalid-payload"
    end

    -- Try common exploit request functions first (for compatibility)
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    if req then
        local ok, res = pcall(function() return req(payload) end)
        if ok then return res end
    end

    -- Fall back to HttpService if allowed
    if HttpService and HttpService.HttpEnabled then
        local method = (payload.Method or "GET"):upper()
        local url = payload.Url
        local body = payload.Body or ""
        local ok, res = pcall(function()
            if method == "POST" then
                local response = HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
                return {Body = response, Success = true}
            else
                local response = HttpService:GetAsync(url)
                return {Body = response, Success = true}
            end
        end)
        if ok then return res end
    end

    return nil, "no-request-method-available"
end

local function isValidWebhookUrl(url)
    if type(url) ~= "string" then return false end
    if not url:match("^https://") then return false end
    if url:match("localhost") or url:match("127%.0%.0%.1") then return false end
    return true
end

local function anonymizeUserId(id)
    id = tonumber(id) or 0
    local magic = 2654435761
    local ob = (id * magic) % 4294967296
    local chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    local out = ""
    repeat
        local rem = (ob % 36) + 1
        out = chars:sub(rem, rem) .. out
        ob = math.floor(ob / 36)
    until ob == 0
    return out
end

local function isoTimestampUTC()
    local ok, t = pcall(function() return os.date("!%Y-%m-%dT%H:%M:%SZ") end)
    if ok and type(t) == "string" then return t end
    return os.date("%Y-%m-%dT%H:%M:%SZ")
end

-- =======================
-- GUI Setup (revamped: smaller, no background, opening splash/animation)
-- =======================
local function getTargetParent()
    if RunService:IsStudio() then
        return player:WaitForChild("PlayerGui")
    end
    return CoreGui
end

local targetParent = getTargetParent()
local existing = targetParent:FindFirstChild(GUI_NAME)
if existing then existing:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = targetParent

local function makeClickThrough(obj)
    if typeof(obj) ~= "Instance" then return end
    if obj:IsA("GuiObject") then
        pcall(function() obj.Active = false end)
        pcall(function() obj.Selectable = false end)
    end
    for _, child in ipairs(obj:GetChildren()) do makeClickThrough(child) end
end
makeClickThrough(screenGui)

-- Small, elegant HUD: transparent background, neon outline + logo
local hud = Instance.new("Frame")
hud.Name = "LunarHUD"
hud.Size = UDim2.new(0, 160, 0, 48)
hud.Position = UDim2.new(1, -180, 0, 36)
hud.BackgroundTransparency = 1 -- no opaque background
hud.Parent = screenGui

-- Glow / outline using UIStroke
local hudStroke = Instance.new("UIStroke")
hudStroke.Thickness = 2
hudStroke.Color = theme.accent
hudStroke.Transparency = 0.5
hudStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
hudStroke.Parent = hud

-- Circular logo
local logo = Instance.new("Frame")
logo.Name = "Logo"
logo.Size = UDim2.new(0, 44, 0, 44)
logo.Position = UDim2.new(0, 6, 0.5, -22)
logo.BackgroundTransparency = 0
logo.BackgroundColor3 = theme.accent
logo.Parent = hud
local logoCorner = Instance.new("UICorner")
logoCorner.CornerRadius = UDim.new(1, 0)
logoCorner.Parent = logo

-- subtle radial gradient for logo (UIGradient simulates it)
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, theme.accent), ColorSequenceKeypoint.new(1, theme.accent2)})
grad.Rotation = 45
grad.Parent = logo

local logoInner = Instance.new("ImageLabel")
logoInner.Name = "LogoInner"
logoInner.BackgroundTransparency = 1
logoInner.Size = UDim2.new(0.6, 0, 0.6, 0)
logoInner.Position = UDim2.new(0.2, 0, 0.2, 0)
logoInner.Image = "" -- optional: set a small icon image URL or asset
logoInner.Parent = logo

-- Title / small label (no big bg)
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(0, 90, 0, 44)
title.Position = UDim2.new(0, 56, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Lunar"
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = theme.text
title.TextTransparency = 0
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = hud

-- small subtitle
local sub = Instance.new("TextLabel")
sub.Name = "Sub"
sub.Size = UDim2.new(0, 90, 0, 16)
sub.Position = UDim2.new(0, 56, 0, 26)
sub.BackgroundTransparency = 1
sub.Text = "Anti-AFK"
sub.Font = Enum.Font.Gotham
sub.TextSize = 11
sub.TextColor3 = Color3.fromRGB(200,200,210)
sub.TextTransparency = 0
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Parent = hud

-- tiny FPS / status dot (right side)
local statusDot = Instance.new("Frame")
statusDot.Name = "StatusDot"
statusDot.Size = UDim2.new(0, 10, 0, 10)
statusDot.Position = UDim2.new(1, -18, 0.5, -5)
statusDot.BackgroundColor3 = theme.accent2
statusDot.BackgroundTransparency = 0
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = statusDot
statusDot.Parent = hud

-- make elements click-through
makeClickThrough(hud)

-- Cinematic intro inspired by Hurr (keeps the feel, minimal changes)
local function playCinematicIntro()
    if not ENABLE_CINEMATIC_INTRO then return end
    -- sounds (optional; pcall to avoid errors in environments where Sound fails)
    local startSound, typeSound
    pcall(function()
        startSound = Instance.new("Sound")
        startSound.SoundId = "rbxassetid://6518811702"
        startSound.Volume = 0.7
        startSound.Parent = screenGui
        startSound:Play()

        typeSound = Instance.new("Sound")
        typeSound.SoundId = "rbxassetid://421058925"
        typeSound.Volume = 0.45
        typeSound.Parent = screenGui
    end)

    -- blur the world subtly
    local blur
    pcall(function()
        blur = Instance.new("BlurEffect")
        blur.Size = 0
        blur.Parent = Lighting
        TweenService:Create(blur, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {Size = 18}):Play()
    end)

    -- container for letters
    local introContainer = Instance.new("Frame")
    introContainer.Size = UDim2.new(1, 0, 1, 0)
    introContainer.BackgroundTransparency = 1
    introContainer.Parent = screenGui
    makeClickThrough(introContainer)

    local fullText = "Lunar Anti-AFK"
    local letters = {}
    local totalWidth = 0

    for i = 1, #fullText do
        local char = fullText:sub(i, i)
        local charWidth = (char == " " and 18 or 44)
        local lbl = Instance.new("TextLabel")
        lbl.Text = char
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 48
        lbl.TextColor3 = Color3.fromRGB(255,255,255)
        lbl.TextTransparency = 1
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(0, charWidth, 0, 64)
        lbl.Parent = introContainer

        local glow = Instance.new("TextLabel")
        glow.Text = char
        glow.Font = Enum.Font.GothamBold
        glow.TextSize = 56
        glow.TextColor3 = theme.accent2
        glow.TextTransparency = 1
        glow.BackgroundTransparency = 1
        glow.Size = UDim2.new(1, 0, 1, 0)
        glow.ZIndex = lbl.ZIndex - 1
        glow.Parent = lbl

        table.insert(letters, {lbl = lbl, glow = glow, char = char})
        totalWidth = totalWidth + charWidth
    end

    -- center letters
    local currentPos = (introContainer.AbsoluteSize.X / 2) - (totalWidth / 2)
    for _, item in pairs(letters) do
        item.lbl.Position = UDim2.new(0, currentPos, 0.5, 40)
        currentPos = currentPos + item.lbl.Size.X.Offset
    end

    -- animate letters in sequence
    for i, item in ipairs(letters) do
        task.wait(0.06)
        if item.char ~= " " then pcall(function() if typeSound then typeSound:Play() end end) end
        TweenService:Create(item.lbl, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0, item.lbl.Position.X.Offset, 0.5, -10), TextTransparency = 0}):Play()
        TweenService:Create(item.glow, TweenInfo.new(0.6), {TextTransparency = 0.35}):Play()
    end

    -- hold, then animate out into the compact HUD
    task.wait(1.1)
    for _, item in pairs(letters) do
        TweenService:Create(item.lbl, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {TextTransparency = 1, Position = UDim2.new(0, item.lbl.Position.X.Offset, 0.5, -140)}):Play()
        TweenService:Create(item.glow, TweenInfo.new(0.55), {TextTransparency = 1}):Play()
    end

    -- restore blur
    pcall(function()
        if blur then TweenService:Create(blur, TweenInfo.new(0.9), {Size = 0}):Play(); wait(0.95); blur:Destroy() end
    end)

    -- cleanup sounds
    pcall(function() if startSound then startSound:Destroy() end if typeSound then typeSound:Destroy() end end)
    pcall(function() introContainer:Destroy() end)
end

-- Play intro asynchronously (minimal change vs. previous splash)
task.spawn(function()
    wait(0.08)
    pcall(playCinematicIntro)
end)

-- =======================
-- AFK prevention + render loop (updated to work with compact HUD)
-- =======================
local startTime = tick()
local lastTick = tick()
local frames = 0
local hue = 0

RunService.RenderStepped:Connect(function()
    hue = (hue + 0.006) % 1
    -- gentle animated accent tint for logo and outline
    local accent = Color3.fromHSV(hue, 0.7, 1)
    pcall(function()
        logo.BackgroundColor3 = accent
        hudStroke.Color = accent
        statusDot.BackgroundColor3 = (frames >= 50 and Color3.fromRGB(0,255,127)) or (frames >= 30 and Color3.fromRGB(255,170,0)) or Color3.fromRGB(255,85,85)
    end)

    local elapsed = tick() - startTime

    frames = frames + 1
    if tick() - lastTick >= 1 then
        -- fps pulse handled here (we don't display it to keep HUD minimal)
        frames = 0
        lastTick = tick()
    end
end)

player.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0,0))
    end)
end)

-- =======================
-- Analytics: send only on first run (unchanged)
-- =======================
local function trySendFirstRunEmbed()
    if not ENABLE_ANALYTICS then return false, "disabled" end
    if not isValidWebhookUrl(WEBHOOK_URL) then return false, "invalid-webhook" end
    if not HttpService then return false, "no-httpservice" end

    if os.time() - _lastAnalyticsSent < ANALYTICS_MIN_INTERVAL then
        return false, "rate-limited"
    end

    local isFirstRun = false
    local totalRuns = "N/A"
    local uniqueDevices = "N/A"

    pcall(function()
        local res = HttpService:GetAsync(apiTotal)
        local decoded = HttpService:JSONDecode(res)
        totalRuns = tostring(decoded.count or decoded.value or "N/A")
    end)

    pcall(function()
        local userKey = "u_" .. tostring(player.UserId)
        local checkUrl = "https://api.counterapi.dev/v1/" .. NAMESPACE .. "/" .. userKey .. "/up"
        local res = HttpService:GetAsync(checkUrl)
        local decoded = HttpService:JSONDecode(res)
        local count = tonumber(decoded.count) or tonumber(decoded.value) or 0
        if count == 1 then
            isFirstRun = true
            pcall(function() HttpService:GetAsync(apiUnique .. "/up") end)
        end

        local finalUnique = HttpService:GetAsync(apiUnique)
        local dec2 = HttpService:JSONDecode(finalUnique)
        uniqueDevices = tostring(dec2.count or dec2.value or "N/A")
    end)

    if not isFirstRun then
        return false, "not-first-run"
    end

    local profileUrl = "https://www.roblox.com/users/" .. tostring(player.UserId) .. "/profile"
    local headshot = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. tostring(player.UserId) .. "&width=420&height=420&format=png"

    local embed = {
        username = "Lunar System",
        avatar_url = "https://i.imgur.com/your_icon.png",
        embeds = {{
            title = "Lunar Anti-AFK Activated",
            description = string.format("A new installation of Lunar Anti-AFK was detected and activated."),
            color = 0x00beff,
            author = {
                name = "Lunar Anti-AFK",
                url = profileUrl,
                icon_url = headshot
            },
            fields = {
                {name = "Player", value = ("[%s](%s)"):format(player.Name, profileUrl), inline = true},
                {name = "Anon ID", value = anonymizeUserId(player.UserId), inline = true},
                {name = "Total Runs", value = "``" .. tostring(totalRuns) .. "``", inline = true},
                {name = "Unique Devices", value = "``" .. tostring(uniqueDevices) .. "``", inline = true},
                {name = "PlaceId", value = tostring(game.PlaceId), inline = true},
                {name = "Version", value = "visual-2026-09", inline = true},
            },
            thumbnail = {url = headshot},
            footer = {text = "Lunar Anti-AFK • " .. os.date("%H:%M:%S")},
            timestamp = isoTimestampUTC()
        }}
    }

    local ok, err = pcall(function()
        local payload = {
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(embed)
        }
        local res, rerr = safeRequest(payload)
        if not res then error(rerr or "request-failed") end
        return res
    end)

    if ok then
        _lastAnalyticsSent = os.time()
        return true, "sent"
    else
        return false, err
    end
end

-- Attempt to send once (non-blocking)
task.spawn(function()
    local ok, res = pcall(trySendFirstRunEmbed)
end)

-- expose small API for runtime control
local LunarAntiAFK = {}

function LunarAntiAFK.EnableAnalytics(enable, webhook)
    ENABLE_ANALYTICS = enable and true or false
    if webhook and type(webhook) == "string" then WEBHOOK_URL = webhook end
    if ENABLE_ANALYTICS then
        pcall(trySendFirstRunEmbed)
    end
    return ENABLE_ANALYTICS
end

function LunarAntiAFK.Cleanup()
    if screenGui and screenGui.Parent then
        pcall(function() screenGui:Destroy() end)
    end
end

screenGui:SetAttribute("LunarAntiAFK_Version", "visual-2026-09")

return LunarAntiAFK
