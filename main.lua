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

-- Theme
local theme = {
    accent = Color3.fromRGB(0, 190, 255),
    bg = Color3.fromRGB(20, 20, 25),
    text = Color3.fromRGB(240, 240, 240),
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
    -- Return ISO8601 UTC timestamp for Discord embed
    -- os.date("!%Y-%m-%dT%H:%M:%SZ") returns UTC in some environments; fallback to approximate
    local ok, t = pcall(function() return os.date("!%Y-%m-%dT%H:%M:%SZ") end)
    if ok and type(t) == "string" then return t end
    return os.date("%Y-%m-%dT%H:%M:%SZ")
end

-- =======================
-- GUI Setup (visuals kept from previous polished version)
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

-- (Mini HUD creation - kept compact)
local hud = Instance.new("Frame")
hud.Name = "LunarHUD"
hud.Size = UDim2.new(0, 220, 0, 100)
hud.Position = UDim2.new(1, -230, 0, 50)
hud.BackgroundColor3 = theme.bg
hud.BackgroundTransparency = 0.12
hud.Parent = screenGui
local hudCorner = Instance.new("UICorner"); hudCorner.CornerRadius = UDim.new(0, 10); hudCorner.Parent = hud
local hudStroke = Instance.new("UIStroke"); hudStroke.Thickness = 1; hudStroke.Color = theme.accent; hudStroke.Parent = hud

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.95, 0, 0, 34)
title.Position = UDim2.new(0.03, 0, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Lunar Anti-AFK"
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = theme.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = hud

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -8, 0, 18)
status.Position = UDim2.new(0, 4, 0, 36)
status.BackgroundTransparency = 1
status.Text = "Status: Active"
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(200, 200, 200)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = hud

local rightCol = Instance.new("Frame")
rightCol.Size = UDim2.new(1, -8, 0, 34)
rightCol.Position = UDim2.new(0, 4, 0, 56)
rightCol.BackgroundTransparency = 1
rightCol.Parent = hud

local fpsLbl = Instance.new("TextLabel")
fpsLbl.Size = UDim2.new(0.5, -4, 1, 0)
fpsLbl.Position = UDim2.new(0, 0, 0, 0)
fpsLbl.BackgroundTransparency = 1
fpsLbl.Text = "FPS: --"
fpsLbl.Font = Enum.Font.GothamSemibold
fpsLbl.TextSize = 13
fpsLbl.TextColor3 = theme.text
fpsLbl.TextXAlignment = Enum.TextXAlignment.Left
fpsLbl.Parent = rightCol

local uptimeLbl = Instance.new("TextLabel")
uptimeLbl.Size = UDim2.new(0.5, -4, 1, 0)
uptimeLbl.Position = UDim2.new(0.5, 4, 0, 0)
uptimeLbl.BackgroundTransparency = 1
uptimeLbl.Text = "Uptime: 00:00:00"
uptimeLbl.Font = Enum.Font.GothamSemibold
uptimeLbl.TextSize = 13
uptimeLbl.TextColor3 = theme.text
uptimeLbl.TextXAlignment = Enum.TextXAlignment.Right
uptimeLbl.Parent = rightCol

local progressBg = Instance.new("Frame")
progressBg.Size = UDim2.new(1, -12, 0, 6)
progressBg.Position = UDim2.new(0, 6, 1, -14)
progressBg.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
progressBg.Parent = hud
local progressCorner = Instance.new("UICorner"); progressCorner.CornerRadius = UDim.new(0, 4); progressCorner.Parent = progressBg

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.new(0.0, 0, 1, 0)
progressFill.BackgroundColor3 = theme.accent
progressFill.Parent = progressBg
local progressFillCorner = Instance.new("UICorner"); progressFillCorner.CornerRadius = UDim.new(0, 4); progressFillCorner.Parent = progressFill

makeClickThrough(hud)

-- =======================
-- AFK prevention + render loop
-- =======================
local startTime = tick()
local lastTick = tick()
local frames = 0
local hue = 0

RunService.RenderStepped:Connect(function()
    hue = (hue + 0.006) % 1
    title.TextColor3 = Color3.fromHSV(hue, 0.7, 1)

    local elapsed = tick() - startTime
    uptimeLbl.Text = string.format("Uptime: %02d:%02d:%02d", math.floor(elapsed/3600), math.floor((elapsed%3600)/60), math.floor(elapsed%60))

    frames = frames + 1
    if tick() - lastTick >= 1 then
        fpsLbl.Text = "FPS: " .. tostring(frames)
        local period = 60
        local pct = (elapsed % period) / period
        pcall(function()
            TweenService:Create(progressFill, TweenInfo.new(0.8, Enum.EasingStyle.Quart), {Size = UDim2.new(pct, 0, 1, 0)}):Play()
        end)
        local clr = (frames >= 50 and Color3.fromRGB(0, 255, 127)) or (frames >= 30 and Color3.fromRGB(255, 170, 0)) or Color3.fromRGB(255, 85, 85)
        progressFill.BackgroundColor3 = clr
        fpsLbl.TextColor3 = clr
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
-- Analytics: send only on first run
-- =======================
local function trySendFirstRunEmbed()
    if not ENABLE_ANALYTICS then return false, "disabled" end
    if not isValidWebhookUrl(WEBHOOK_URL) then return false, "invalid-webhook" end
    if not HttpService then return false, "no-httpservice" end

    -- Rate-limit locally too
    if os.time() - _lastAnalyticsSent < ANALYTICS_MIN_INTERVAL then
        return false, "rate-limited"
    end

    local isFirstRun = false
    local totalRuns = "N/A"
    local uniqueDevices = "N/A"

    -- 1) Increment total runs and read count (best-effort; non-fatal)
    pcall(function()
        local res = HttpService:GetAsync(apiTotal)
        local decoded = HttpService:JSONDecode(res)
        totalRuns = tostring(decoded.count or decoded.value or "N/A")
    end)

    -- 2) Check/increment unique for this user key (u_<UserId>)
    pcall(function()
        local userKey = "u_" .. tostring(player.UserId)
        -- This endpoint increments per-user and returns count; if it's 1, this is the user's first run
        local checkUrl = "https://api.counterapi.dev/v1/" .. NAMESPACE .. "/" .. userKey .. "/up"
        local res = HttpService:GetAsync(checkUrl)
        local decoded = HttpService:JSONDecode(res)
        local count = tonumber(decoded.count) or tonumber(decoded.value) or 0
        if count == 1 then
            isFirstRun = true
            -- increment global unique devices count
            pcall(function() HttpService:GetAsync(apiUnique .. "/up") end)
        end

        -- fetch final unique count for display
        local finalUnique = HttpService:GetAsync(apiUnique)
        local dec2 = HttpService:JSONDecode(finalUnique)
        uniqueDevices = tostring(dec2.count or dec2.value or "N/A")
    end)

    -- only send the embed when this is the user's first run
    if not isFirstRun then
        return false, "not-first-run"
    end

    -- Build improved embed
    local profileUrl = "https://www.roblox.com/users/" .. tostring(player.UserId) .. "/profile"
    local headshot = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. tostring(player.UserId) .. "&width=420&height=420&format=png"

    local embed = {
        username = "Lunar System",
        avatar_url = "https://i.imgur.com/your_icon.png", -- change to your icon if desired
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

    -- send using safeRequest or HttpService
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
    -- silent failure; nothing else needed
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
