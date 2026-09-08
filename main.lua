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

-- Opening splash: a short animated label that scales down into the HUD
local function playOpeningSplash()
    local splash = Instance.new("TextLabel")
    splash.Name = "LunarSplash"
    splash.AnchorPoint = Vector2.new(0.5, 0.5)
    splash.Size = UDim2.new(0, 280, 0, 84)
    local screenX = math.clamp(hud.AbsolutePosition.X + hud.AbsoluteSize.X/2, 140, (screenGui.AbsoluteSize and screenGui.AbsoluteSize.X) or 1000)
    local screenY = math.clamp(hud.AbsolutePosition.Y + hud.AbsoluteSize.Y/2, 84, (screenGui.AbsoluteSize and screenGui.AbsoluteSize.Y) or 600)
    splash.Position = UDim2.new(0, screenX, 0, screenY)
    splash.BackgroundTransparency = 1
    splash.Text = "LUNAR"
    splash.Font = Enum.Font.BebasNeue or Enum.Font.GothamSemibold
    splash.TextSize = 48
    splash.TextColor3 = theme.accent
    splash.TextStrokeTransparency = 0.8
    splash.TextTransparency = 1
    splash.Parent = screenGui

    -- animate: fade in & pop, then shrink & fade out
    pcall(function()
        local tweenIn = TweenService:Create(splash, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {TextTransparency = 0})
        local scaleUp = TweenService:Create(splash, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 320, 0, 96)})
        tweenIn:Play(); scaleUp:Play()
        tweenIn.Completed:Wait()

        wait(0.85)

        local tweenOut = TweenService:Create(splash, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {TextTransparency = 1, Size = UDim2.new(0, 120, 0, 36), Position = UDim2.new(0, hud.AbsolutePosition.X + 56, 0, hud.AbsolutePosition.Y + 6)})
        tweenOut:Play()
        tweenOut.Completed:Wait()
    end)
    pcall(function() splash:Destroy() end)
end

-- Play the splash asynchronously after layout is ready
task.spawn(function()
    -- wait a short moment so AbsolutePosition/Size populate
    wait(0.12)
    pcall(playOpeningSplash)
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
    -- update small uptime on hover tooltip? (kept off-screen minimal)

    frames = frames + 1
    if tick() - lastTick >= 1 then
        -- pulse the dot color based on FPS
        local fpsNow = frames
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
