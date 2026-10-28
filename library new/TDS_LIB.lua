if not game:IsLoaded() then game.Loaded:Wait() end

shared = shared or {}
_G = _G or {}

function save_auto_rejoin_state(state, timerStart)
    if not writefile then return end
    local content = tostring(state)
    if timerStart then content = content .. "|" .. tostring(timerStart) end
    pcall(function() writefile("TDS_AutoRejoin.txt", content) end)
end

function load_auto_rejoin_state()
    if not readfile then return true, nil end
    local saved = true
    local timerStart = nil
    pcall(function()
        local content = readfile("TDS_AutoRejoin.txt")
        if content then
            local stateStr, timerStr = content:match("^(.-)|(.*)$")
            if stateStr then
                saved = stateStr == "true"
                if timerStr and timerStr ~= "" then timerStart = tonumber(timerStr) end
            else
                saved = content == "true"
            end
        end
    end)
    return saved, timerStart
end

_G.AutoRejoin, _G.AutoRejoinTimerStart = load_auto_rejoin_state()
_G.LobbyRejoin = _G.LobbyRejoin or 120
_G.LobbyRejoinPending = false

function identify_game_state()
    local players = game:GetService("Players")
    local temp_player = players.LocalPlayer or players.PlayerAdded:Wait()
    local temp_gui = temp_player:WaitForChild("PlayerGui")
    while true do
        if temp_gui:FindFirstChild("ReactLobbyHud") then
            return "LOBBY"
        elseif temp_gui:FindFirstChild("ReactUniversalHotbar") then
            return "GAME"
        end
        task.wait(1)
    end
end

game_state = identify_game_state()

if game_state == "LOBBY" then
    _G.AutoRejoin = true
    _G.AutoRejoinTimerStart = nil
    save_auto_rejoin_state(_G.AutoRejoin, _G.AutoRejoinTimerStart)
end

HttpService = game:GetService("HttpService")
send_request = request or http_request or httprequest
if not send_request then
    _G.SendWebhook = false
    warn("No HTTP function - webhooks disabled")
end
WEBHOOK = _G.Webhook or ""

CHESTS = {
    ["rbxassetid://"] = "Showtime Crate",
    ["rbxassetid://and116682554518868"] = "Hollow Crate",
    ["rbxassetid://100652254678254"] = "Beach Crate",
    ["rbxassetid://71674076269696"] = "Scuba Ops Crate",
    ["rbxassetid://"] = "Patriotic Crate",
}

CONSUMABLES = {
    ["rbxassetid://100201829226448"] = "Ducky Squad(s)",
    ["rbxassetid://17447507910"] = "Timescale Ticket(s)",
    ["rbxassetid://17438486690"] = "Range Flag(s)",
    ["rbxassetid://17438486138"] = "Damage Flag(s)",
    ["rbxassetid://17438487774"] = "Cooldown Flag(s)",
    ["rbxassetid://17429537022"] = "Blizzard(s)",
    ["rbxassetid://17448596749"] = "Napalm Strike(s)",
    ["rbxassetid://18493073533"] = "Spin Ticket(s)",
    ["rbxassetid://17429548305"] = "Supply Drop(s)",
    ["rbxassetid://98556517737333"] = "Low Grade Consumable Crate(s)",
    ["rbxassetid://90205718290985"] = "Mid Grade Consumable Crate(s)",
    ["rbxassetid://103153842896752"] = "High Grade Consumable Crate(s)",
    ["rbxassetid://136180382135048"] = "Santa Radio(s)",
    ["rbxassetid://115421293343588"] = "Easter Egg(s)",
    ["rbxassetid://95120437798143"] = "Molten Monster(s)",
    ["rbxassetid://132155797622156"] = "Christmas Tree(s)",
    ["rbxassetid://124065875200929"] = "Fruit Cake(s)",
    ["rbxassetid://17429541513"] = "Barricade(s)",
    ["rbxassetid://110415073436604"] = "Holy Hand Grenade(s)",
    ["rbxassetid://17429533728"] = "Frag Grenade(s)",
    ["rbxassetid://17437703262"] = "Molotov(s)",
    ["rbxassetid://139414922355803"] = "Present Clusters(s)",
}

MAIN = {
    ["rbxassetid://6794340240"] = "XP",
    ["rbxassetid://128907328829271"] = "Coins",
    ["rbxassetid://108777382125602"] = "Gems",
}

EVOLVED_XP = {
    ["rbxassetid://99276263993721"] = "Scout XP",
    ["rbxassetid://16742109340"] = "Minigunner XP",
    ["rbxassetid://16742038000"] = "Crook Boss XP",
    ["rbxassetid://94394209436954"] = "Operator XP",
    ["rbxassetid://127024651233382"] = "Juggernaut XP",
    ["rbxassetid://74602401810472"] = "Kingpin XP",
}

ITEM_NAMES = {}
for k, v in pairs(CHESTS) do ITEM_NAMES[k] = v end
for k, v in pairs(CONSUMABLES) do ITEM_NAMES[k] = v end
for k, v in pairs(MAIN) do ITEM_NAMES[k] = v end
for k, v in pairs(EVOLVED_XP) do ITEM_NAMES[k] = v end

function get_item_category(iconId)
    if CHESTS[iconId] then return "chests" end
    if CONSUMABLES[iconId] then return "consumables" end
    if MAIN[iconId] then return "main" end
    if EVOLVED_XP[iconId] then return "evolved_xp" end
    return "unknown"
end

function extract_number(str)
    if type(str) ~= "string" then return 0 end
    return tonumber(str:match("%d+")) or 0
end

function format_number(n)
    return tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

function get_player_gui()
    local lp = game:GetService("Players").LocalPlayer
    return lp and lp:FindFirstChild("PlayerGui")
end

function tds_get_rewards_section()
    local pg = get_player_gui(); if not pg then return end
    local root = pg:FindFirstChild("ReactGameNewRewards"); if not root then return end
    local frame = root:FindFirstChild("Frame"); if not frame then return end
    local gameOver = frame:FindFirstChild("gameOver"); if not gameOver then return end
    local rewardsScreen = gameOver:FindFirstChild("RewardsScreen"); if not rewardsScreen then return end
    return rewardsScreen:FindFirstChild("RewardsSection")
end

function tds_get_stats_container()
    local pg = get_player_gui(); if not pg then return end
    local root = pg:FindFirstChild("ReactGameNewRewards"); if not root then return end
    local frame = root:FindFirstChild("Frame"); if not frame then return end
    local gameOver = frame:FindFirstChild("gameOver"); if not gameOver then return end
    local rewardsScreen = gameOver:FindFirstChild("RewardsScreen"); if not rewardsScreen then return end
    local gameStats = rewardsScreen:FindFirstChild("gameStats"); if not gameStats then return end
    return gameStats:FindFirstChild("stats")
end

function tds_get_wave()
    local pg = get_player_gui(); if not pg then return "0" end
    local top = pg:FindFirstChild("ReactGameTopGameDisplay"); if not top then return "0" end
    local frame = top:FindFirstChild("Frame"); if not frame then return "0" end
    local wave = frame:FindFirstChild("wave"); if not wave then return "0" end
    local container = wave:FindFirstChild("container"); if not container then return "0" end
    local value = container:FindFirstChild("value")
    if value and value:IsA("TextLabel") then
        return string.match(value.Text or "0/0", "^(%d+)") or "0"
    end
    return "0"
end

function tds_find_text_in_section(section, keyword)
    if not section then return "" end
    for _, child in ipairs(section:GetDescendants()) do
        if child:IsA("TextLabel") and child.Text and string.find(child.Text, keyword) then
            return child.Text
        end
    end
    return ""
end

function tds_parse_stats(stats)
    local result = { time = "", map = "", difficulty = "" }
    if not stats then return result end
    for _, child in ipairs(stats:GetChildren()) do
        local label = child:FindFirstChild("textLabel")
        local value = child:FindFirstChild("textLabel2")
        if label and label:IsA("TextLabel") and value then
            local label_text = label.Text or ""
            local val_text = ""
            local refLabel = value:FindFirstChild("refLabel")
            if refLabel and refLabel:IsA("TextLabel") then
                val_text = refLabel.Text or ""
            elseif value:IsA("TextLabel") then
                val_text = value.Text or ""
            end
            if string.find(label_text, "Time") then result.time = val_text
            elseif string.find(label_text, "Map") then result.map = val_text
            elseif string.find(label_text, "Difficulty") or string.find(label_text, "Mode") then result.difficulty = val_text
            end
        end
    end
    return result
end

function tds_collect_items()
    local all_items = {}
    local section = tds_get_rewards_section()
    if not section then return all_items end
    for _, child in ipairs(section:GetChildren()) do
        if child:IsA("GuiObject") or child:IsA("Frame") or child:IsA("ImageLabel")
            or child:IsA("ImageButton") or child:IsA("TextLabel") then
            local iconFrame = child:FindFirstChild("icon")
            if not iconFrame then pcall(function() iconFrame = child.icon end) end
            if iconFrame then
                local iconImage = iconFrame:FindFirstChild("icon")
                if not iconImage then pcall(function() iconImage = iconFrame.icon end) end
                local iconId = ""
                if iconImage then
                    local success, img = pcall(function() return iconImage.Image end)
                    if success and img and img ~= "" then iconId = tostring(img) end
                end
                if iconId ~= "" then
                    local countText = ""
                    local countLabel = iconFrame:FindFirstChild("textLabel")
                    if not countLabel then pcall(function() countLabel = iconFrame.textLabel end) end
                    if countLabel then
                        local success, txt = pcall(function() return countLabel.Text end)
                        if success and txt and txt ~= "" then countText = txt end
                    end
                    if countText == "" then
                        for _, desc in ipairs(iconFrame:GetDescendants()) do
                            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                                local success, txt = pcall(function() return desc.Text end)
                                if success and txt and txt ~= "" then countText = txt; break end
                            end
                        end
                    end
                    if countText == "" then
                        for _, desc in ipairs(child:GetDescendants()) do
                            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                                local success, txt = pcall(function() return desc.Text end)
                                if success and txt and txt ~= "" and txt ~= " " then countText = txt; break end
                            end
                        end
                    end
                    local count = extract_number(countText)
                    if count == 0 and countText ~= "" then
                        local x_match = string.match(countText, "x(%d+)")
                        if x_match then count = tonumber(x_match) or 0 end
                    end
                    if count == 0 and countText == "" then count = 1 end
                    if count > 0 then
                        table.insert(all_items, {
                            icon = iconId, count = count,
                            category = get_item_category(iconId),
                        })
                    end
                end
            end
        end
    end
    return all_items
end

function tds_collect()
    local section = tds_get_rewards_section()
    if not section then return nil end
    local banner_text = ""
    local pg = get_player_gui()
    if pg then
        local root = pg:FindFirstChild("ReactGameNewRewards")
        if root then
            local frame = root:FindFirstChild("Frame")
            if frame then
                local gameOver = frame:FindFirstChild("gameOver")
                if gameOver then
                    local rewardsScreen = gameOver:FindFirstChild("RewardsScreen")
                    if rewardsScreen then
                        local rewardBanner = rewardsScreen:FindFirstChild("RewardBanner")
                        if rewardBanner then
                            local label = rewardBanner:FindFirstChild("textLabel") or rewardBanner:FindFirstChildOfClass("TextLabel")
                            if label and label:IsA("TextLabel") then banner_text = label.Text or "" end
                        end
                    end
                end
            end
        end
    end
    local is_win = false
    local upper = string.upper(banner_text)
    if string.find(upper, "TRIUMPH") or string.find(upper, "VICTORY") or string.find(upper, "WIN") then
        is_win = true
    elseif string.find(upper, "LOST") or string.find(upper, "DEFEAT") or string.find(upper, "FAIL") then
        is_win = false
    else
        for _, child in ipairs(section:GetDescendants()) do
            if child:IsA("TextLabel") and child.Text then
                local txt = string.upper(child.Text)
                if string.find(txt, "TRIUMPH") or string.find(txt, "VICTORY") or string.find(txt, "WIN") then
                    is_win = true; break
                elseif string.find(txt, "LOST") or string.find(txt, "DEFEAT") or string.find(txt, "FAIL") then
                    is_win = false; break
                end
            end
        end
    end
    return {
        status = is_win and "WIN" or "DEFEAT",
        coins_gain = extract_number(tds_find_text_in_section(section, "Coins")),
        gems_gain = extract_number(tds_find_text_in_section(section, "Gems")),
        wave = tds_get_wave(),
        map = tds_parse_stats(tds_get_stats_container()).map,
        difficulty = tds_parse_stats(tds_get_stats_container()).difficulty,
        time_display = tds_parse_stats(tds_get_stats_container()).time,
        tokens_gain = 0, cookies_gain = 0,
        items = tds_collect_items(),
    }
end

function format_category_items(items, category)
    local lines = {}
    for _, item in ipairs(items) do
        if item.category == category then
            local item_name = ITEM_NAMES[item.icon]
            if item_name then
                table.insert(lines, string.format("%s x%d", item_name, item.count))
            else
                local assetId = string.match(item.icon, "rbxassetid://(%d+)") or "?"
                table.insert(lines, string.format("Unknown x%d (`%s`)", item.count, assetId))
            end
        end
    end
    return lines
end

function send_embed(data, game_name)
    local webhook_url = _G.Webhook or WEBHOOK
    if webhook_url == "" or webhook_url == nil then
        warn("WEBHOOK: No URL set (_G.Webhook is empty)"); return
    end
    if type(send_request) ~= "function" then
        warn("WEBHOOK: No HTTP function available"); return
    end
    local ok, err = pcall(function()
        local color = (data.status == "WIN") and 0x2ecc71 or 0xe74c3c
        local title = (data.status == "WIN") and "🏆 Victory"
            or (data.status == "DEFEAT" and "💀 Defeat" or "❓ Unknown")
        local parts = {}
        table.insert(parts, string.format("**Game:** %s", game_name))
        table.insert(parts, string.format("**Difficulty:** %s | **Map:** %s",
            data.difficulty ~= "" and data.difficulty or "?",
            data.map ~= "" and data.map or "?"))
        table.insert(parts, string.format("**Time:** %s | **Wave:** %s",
            data.time_display or "?", data.wave ~= "" and data.wave or "?"))
        local lp = game:GetService("Players").LocalPlayer
        local coins_total = lp and lp:FindFirstChild("Coins") and lp.Coins.Value or 0
        local gems_total = lp and lp:FindFirstChild("Gems") and lp.Gems.Value or 0
        local coins_str = "**Coins:** " .. format_number(coins_total)
        if data.coins_gain > 0 then coins_str = coins_str .. " (+" .. data.coins_gain .. ")" end
        local gems_str = "**Gems:** " .. format_number(gems_total)
        if data.gems_gain > 0 then gems_str = gems_str .. " (+" .. data.gems_gain .. ")" end
        table.insert(parts, coins_str .. " | " .. gems_str)
        if data.items and #data.items > 0 then
            local chests     = format_category_items(data.items, "chests")
            local consumables = format_category_items(data.items, "consumables")
            local main       = format_category_items(data.items, "main")
            local evolved    = format_category_items(data.items, "evolved_xp")
            local unknown    = format_category_items(data.items, "unknown")
            if #chests > 0 then table.insert(parts, "**💎 Chests:** " .. table.concat(chests, " | ")) end
            if #consumables > 0 then table.insert(parts, "**📦 Consumables:** " .. table.concat(consumables, " | ")) end
            if #main > 0 then table.insert(parts, "**💰 Main:** " .. table.concat(main, " | ")) end
            if #evolved > 0 then table.insert(parts, "**⭐ Evolved XP:** " .. table.concat(evolved, " | ")) end
            if #unknown > 0 then table.insert(parts, "**❓ Unknown:** " .. table.concat(unknown, " | ")) end
        else
            table.insert(parts, "**Items:** None")
        end
        table.insert(parts, "**Account:** " .. (lp and lp.Name or "?"))
        local payload = HttpService:JSONEncode({ embeds = {{
            title = title, color = color,
            description = table.concat(parts, "\n"),
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }}})
        local res = send_request({
            Url = webhook_url, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = payload
        })
        if res and res.StatusCode and res.StatusCode >= 200 and res.StatusCode < 300 then
            print("WEBHOOK SENT OK")
        else
            warn("WEBHOOK FAILED:", res and res.StatusCode or "no response")
        end
    end)
    if not ok then warn("WEBHOOK ERROR:", err) end
end

teleport_service   = game:GetService("TeleportService")
marketplace_service = game:GetService("MarketplaceService")
replicated_storage = game:GetService("ReplicatedStorage")
remote_func        = replicated_storage:WaitForChild("RemoteFunction")
remote_event       = replicated_storage:WaitForChild("RemoteEvent")
players_service    = game:GetService("Players")
local_player       = players_service.LocalPlayer or players_service.PlayerAdded:Wait()
player_gui         = local_player:WaitForChild("PlayerGui")
Players            = game:GetService("Players")
RunService         = game:GetService("RunService")
localPlayer        = Players.LocalPlayer

auto_rejoin_monitor_running = false
auto_pickups_running = false
auto_skip_running = false
anti_lag_running = false
auto_smart_skip_running = false
auto_bounty_running = false
auto_mercenary_running = false
auto_uber_running = false
auto_chain_running = false
auto_dj_running = false
auto_support_running = false
auto_necro_running = false
auto_claim_rewards = false

TDS = {
    placed_towers = {},
    active_strat = true,
    matchmaking_map = {
        ["Pizza Party"] = "halloween",
        ["Badlands"] = "badlands",
        ["Polluted"] = "polluted"
    },
    strategies = {},
    current_strategy = nil,
    current_map = nil,
    pending_strategy = nil,
    ReplayCallback = nil
}

upgrade_history = {}
shared.TDS_Table = TDS

function check_res_ok(data)
    if data == true then return true end
    if data == false or data == nil then return false end

    local t = type(data)
    if t == "userdata" then return true end

    if t == "table" then
        if data.Success == true or data.success == true then return true end
        if data.OK == true or data.ok == true then return true end

        for _, v in pairs(data) do
            if v == true then return true end
            if type(v) == "userdata" then return true end
        end
    end

    return false
end

function SmartTeleportToLobby()
    local lobbyId = 3260590327
    local IsMobile = game:GetService("UserInputService").TouchEnabled
    Globals = Globals or {}
    local privateCode = Globals.PrivateCode or _G.PrivateCode
    pcall(function()
        if not IsMobile and privateCode and privateCode ~= "" then
            game:GetService("ExperienceService"):LaunchExperience({
                placeId = lobbyId, linkCode = privateCode
            })
        else
            teleport_service:Teleport(lobbyId)
        end
    end)
end

function check_lobby_rejoin_timer()
    if not _G.LobbyRejoin or _G.LobbyRejoin <= 0 then return false end
    if not _G.AutoRejoin then return false end
    if game.PlaceId == 3260590327 then
        if _G.AutoRejoinTimerStart or _G.LobbyRejoinPending then
            _G.AutoRejoinTimerStart = nil
            _G.LobbyRejoinPending = false
            save_auto_rejoin_state(_G.AutoRejoin, _G.AutoRejoinTimerStart)
        end
        return false
    end
    if not _G.AutoRejoinTimerStart then
        _G.AutoRejoinTimerStart = os.time()
        save_auto_rejoin_state(_G.AutoRejoin, _G.AutoRejoinTimerStart)
        return false
    end
    if os.time() - _G.AutoRejoinTimerStart >= _G.LobbyRejoin * 60 then
        _G.LobbyRejoinPending = true
    end
    return false
end

function rejoin_match()
    while not _G.AutoRejoin do task.wait(0.5) end
    local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
    local IsMobile = game:GetService("UserInputService").TouchEnabled
    Globals = Globals or {}
    local privateCode = Globals.PrivateCode or _G.PrivateCode
    if privateCode and privateCode ~= "" and not IsMobile then
        SmartTeleportToLobby(); task.wait(9e9); return
    end
    while true do
        local stateReplicator = replicated_storage:FindFirstChild("StateReplicators")
        local gs = stateReplicator and stateReplicator:FindFirstChild("GameStateReplicator")
        if gs then
            local DisplayName = gs:GetAttribute("DifficultyDisplayName")
            local GameMode = gs:GetAttribute("GameMode")
            local Difficulty = gs:GetAttribute("Difficulty")
            if DisplayName then
                local ok, result = pcall(function()
                    local payload
                    local modeToUse = string.gsub(DisplayName, " ", "")
                    local act_match = Difficulty and Difficulty:match("^Act(%d+)")
                    if GameMode == "Halloween2026" and act_match then
                        payload = { difficulty = Difficulty, night = tonumber(act_match), count = 1, mode = "halloween2026" }
                    elseif modeToUse == "PizzaParty" then payload = { mode = "halloween", count = 1 }
                    elseif modeToUse == "Hardcore" then payload = { mode = "hardcore", difficulty = "Easy", count = 1 }
                    elseif modeToUse == "Voidcore" then payload = { mode = "hardcore", difficulty = "Hard", count = 1 }
                    elseif modeToUse == "PollutedWasteland" then payload = { mode = "polluted", count = 1 }
                    elseif modeToUse == "Badlands" then payload = { mode = "badlands", count = 1 }
                    elseif GameMode == "DuckEvent" then payload = { difficulty = DisplayName, mode = "ducky2025", count = 1 }
                    elseif modeToUse == "Trial" then SmartTeleportToLobby(); return true
                    else payload = { difficulty = DisplayName, mode = "survival", count = 1 }
                    end
                    return remote:InvokeServer("Multiplayer", "v2:start", payload)
                end)
                if ok and check_res_ok(result) then
                    return result
                end
            end
        end
        task.wait(2)
    end
end

last_webhook_key = ""

function start_auto_rejoin_monitor()
    if auto_rejoin_monitor_running then return end
    auto_rejoin_monitor_running = true
    task.spawn(function()
        while true do
            check_lobby_rejoin_timer()
            local pg = game.Players.LocalPlayer:FindFirstChild("PlayerGui")
            if pg and pg:FindFirstChild("ReactUniversalHotbar") then
                local uiRoot = pg:FindFirstChild("ReactGameNewRewards")
                if uiRoot then
                    local mainFrame = uiRoot:FindFirstChild("Frame")
                    if mainFrame and mainFrame.Visible then
                        local gameOver = mainFrame:FindFirstChild("gameOver")
                        if gameOver and gameOver.Visible then
                            local rewardsScreen = gameOver:FindFirstChild("RewardsScreen")
                            if rewardsScreen and rewardsScreen.Visible then
                                local topBanner = rewardsScreen:FindFirstChild("RewardBanner")
                                if topBanner then
                                    local label = topBanner:FindFirstChild("textLabel") or topBanner:FindFirstChildOfClass("TextLabel")
                                    if label then
                                        local txt = label.Text:upper()
                                        if txt ~= "" and (txt:find("TRIUMPH") or txt:find("VICTORY") or txt:find("WIN")
                                            or txt:find("LOST") or txt:find("DEFEAT") or txt:find("FAIL")) then
                                            local wave = "0"
                                            local top = pg:FindFirstChild("ReactGameTopGameDisplay")
                                            if top then
                                                local f = top:FindFirstChild("Frame")
                                                if f then
                                                    local w = f:FindFirstChild("wave")
                                                    if w then
                                                        local c = w:FindFirstChild("container")
                                                        if c then
                                                            local v = c:FindFirstChild("value")
                                                            if v and v:IsA("TextLabel") then
                                                                wave = v.Text:match("^(%d+)") or "0"
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                            local current_key = txt .. "_" .. wave .. "_" .. tostring(game.PlaceId)
                                            if current_key ~= last_webhook_key then
                                                last_webhook_key = current_key
                                                task.spawn(function()
                                                    local found_section = false
                                                    repeat
                                                        task.wait(0.1)
                                                        local f = uiRoot:FindFirstChild("Frame")
                                                        local g = f and f:FindFirstChild("gameOver")
                                                        local s = g and g:FindFirstChild("RewardsScreen")
                                                        if s and s:FindFirstChild("RewardsSection") then found_section = true end
                                                    until found_section
                                                    task.wait(0.5)
                                                    local data = tds_collect()
                                                    if data then send_embed(data, "TDS") end
                                                    task.wait(0.2)
                                                    if _G.LobbyRejoinPending then
                                                        _G.LobbyRejoinPending = false
                                                        _G.AutoRejoinTimerStart = nil
                                                        save_auto_rejoin_state(_G.AutoRejoin, _G.AutoRejoinTimerStart)
                                                        while not _G.AutoRejoin do task.wait(0.5) end
                                                        SmartTeleportToLobby()
                                                    else
                                                        rejoin_match()
                                                    end
                                                end)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            task.wait(0.2)
        end
    end)
end
start_auto_rejoin_monitor()

function run_vote_skip()
    while true do
        local success = pcall(function()
            remote_func:InvokeServer("Voting", "Skip")
        end)
        if success then break end
        task.wait(0.2)
    end
end

match_ready_up_running = false

function match_ready_up()
    if match_ready_up_running then return end
    match_ready_up_running = true
    task.spawn(function()
        while true do
            local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")

            if pg and pg:FindFirstChild("ReactUniversalHotbar") then
                match_ready_up_running = false
                if TDS.pending_strategy then
                    task.spawn(TDS.pending_strategy)
                    TDS.pending_strategy = nil
                end
                return
            end

            local ui_ready = false
            if pg then
                local ui_overrides = pg:FindFirstChild("ReactOverridesVote")
                local main_frame = ui_overrides and ui_overrides:FindFirstChild("Frame")
                if main_frame then
                    local vote_node = main_frame:FindFirstChild("votes")
                    if vote_node then
                        local container = vote_node:FindFirstChild("container")
                        if container then
                            local ready = container:FindFirstChild("ready")
                            if ready and ready.Visible == true then
                                ui_ready = true
                            end
                        end
                    end
                end
            end

            pcall(function() remote_event:FireServer("LobbyVoting", "Ready") end)
            pcall(function() remote_func:InvokeServer("Voting", "Skip") end)

            if ui_ready then
                match_ready_up_running = false
                if TDS.pending_strategy then
                    task.spawn(TDS.pending_strategy)
                    TDS.pending_strategy = nil
                end
                return
            end

            task.wait(2)
        end
    end)
end

function cast_map_vote(map_id, pos_vec)
    remote_event:FireServer("LobbyVoting", "Vote", map_id or "Simplicity", pos_vec or Vector3.new(0,0,0))
end

function lobby_ready_up()
    pcall(function() remote_event:FireServer("LobbyVoting", "Ready") end)
end

function select_map_override(map_id, ...)
    local args = {...}
    if args[#args] == "vip" then
        remote_func:InvokeServer("LobbyVoting", "Override", map_id)
    end
    task.wait(1)
    cast_map_vote(map_id, Vector3.new(12.59, 10.64, 52.01))
    task.wait(0.5)
    lobby_ready_up()
    match_ready_up()
end

function cast_modifier_vote(mods_table)
    local bulk = replicated_storage:WaitForChild("Network"):WaitForChild("Modifiers")
        :WaitForChild("RF:BulkVoteModifiers")
    local selected_mods = mods_table or {
        HiddenEnemies = true, Glass = true, ExplodingEnemies = true,
        Limitation = true, Committed = true, HealthyEnemies = true,
        SpeedyEnemies = true, Quarantine = true, Fog = true,
        FlyingEnemies = true, Broke = true, Jailed = true, Inflation = true
    }
    pcall(function() bulk:InvokeServer(selected_mods) end)
end

function is_map_available(name)
    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local t = g:FindFirstChild("Title")
            if t and t.Text == name then return true end
        end
    end
    return false
end

function veto_and_wait_for_maps()
    local veto_ui = player_gui:FindFirstChild("ReactGameIntermission")
    if not veto_ui then return false end
    local frame = veto_ui:FindFirstChild("Frame"); if not frame then return false end
    local buttons = frame:FindFirstChild("buttons"); if not buttons then return false end
    local veto_button = buttons:FindFirstChild("veto"); if not veto_button then return false end
    local veto_value = veto_button:FindFirstChild("value"); if not veto_value then return false end
    local current_str, total_str = veto_value.Text:match("(%d+)/(%d+)")
    local current = current_str and tonumber(current_str) or 0
    local total = total_str and tonumber(total_str) or #players_service:GetPlayers()
    if total > 0 and current == 0 then
        remote_event:FireServer("LobbyVoting", "Veto")
    end
    return true
end

function get_available_maps()
    local maps = {}
    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local title = g:FindFirstChild("Title")
            if title and title.Text ~= "" then table.insert(maps, title.Text) end
        end
    end
    return maps
end

function set_game_timescale(target_val)
    local speed_list = {0, 0.5, 1, 1.5, 2}
    local target_idx
    for i, v in ipairs(speed_list) do if v == target_val then target_idx = i; break end end
    if not target_idx then return end
    local speed_label = game.Players.LocalPlayer.PlayerGui.ReactUniversalHotbar.Frame.timescale.Speed
    local current_val = tonumber(speed_label.Text:match("x([%d%.]+)"))
    if not current_val then return end
    local current_idx
    for i, v in ipairs(speed_list) do if v == current_val then current_idx = i; break end end
    if not current_idx then return end
    local diff = target_idx - current_idx
    if diff < 0 then diff = #speed_list + diff end
    for _ = 1, diff do
        replicated_storage.RemoteFunction:InvokeServer("TicketsManager", "CycleTimeScale")
        task.wait(0.5)
    end
end

function unlock_speed_tickets()
    if local_player.TimescaleTickets.Value >= 1 then
        if game.Players.LocalPlayer.PlayerGui.ReactUniversalHotbar.Frame.timescale.Lock.Visible then
            replicated_storage.RemoteFunction:InvokeServer('TicketsManager', 'UnlockTimeScale')
        end
    else
        warn("no tickets left")
    end
end

function isTowerStunned(tower)
    if not tower then return false end
    local rep = tower:FindFirstChild("TowerReplicator")
    if not rep then return false end
    return rep:GetAttribute("IsStunned") == true
end

function waitUntilUnstunned(tower)
    while isTowerStunned(tower) do task.wait(0.05) end
end

function getTowerPosition(towerModel)
    local primary = towerModel:FindFirstChild("PrimaryPart") or towerModel:FindFirstChild("Head")
        or towerModel:FindFirstChildWhichIsA("BasePart")
    if primary then return primary.Position end
    return nil
end

_G.CurrentWave = 0

function read_current_wave_safe()
    local pg = get_player_gui()
    if not pg then return 0 end
    local top = pg:FindFirstChild("ReactGameTopGameDisplay")
    if not top then return 0 end
    local frame = top:FindFirstChild("Frame")
    if not frame then return 0 end
    local wave = frame:FindFirstChild("wave")
    if not wave then return 0 end
    local container = wave:FindFirstChild("container")
    if not container then return 0 end
    local value = container:FindFirstChild("value")
    if value and value:IsA("TextLabel") then
        return tonumber(value.Text:match("^(%d+)")) or 0
    end
    return 0
end

function start_wave_tracker()
    task.spawn(function()
        while true do
            pcall(function()
                _G.CurrentWave = read_current_wave_safe()
            end)
            task.wait(0.2)
        end
    end)
end
start_wave_tracker()

function do_place_tower(t_name, t_pos)
    local rx = math.random(-99, 99) / 1000000
    local rz = math.random(-99, 99) / 1000000
    local fx = t_pos.X + rx
    local fz = t_pos.Z + rz
    local fy = t_pos.Y

    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Place", {
                Rotation = CFrame.new(),
                Position = Vector3.new(fx, fy, fz)
            }, t_name)
        end)

        if ok and check_res_ok(res) then
            return true
        end

        task.wait(0.15)
    end
end

function do_upgrade_tower(t_obj, path_id)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Upgrade", "Set", { Troop = t_obj, Path = path_id })
        end)
        if ok and check_res_ok(res) then return true end
        task.wait(0.25)
    end
end

function do_sell_tower(t_obj)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Sell", { Troop = t_obj })
        end)
        if ok and check_res_ok(res) then return true end
        task.wait(0.15)
    end
end

function do_set_option(t_obj, opt_name, opt_val)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Option", "Set", {
                Troop = t_obj, Name = opt_name, Value = opt_val
            })
        end)
        if ok and check_res_ok(res) then return true end
        task.wait(0.25)
    end
end

function do_activate_ability(t_obj, ab_name, ab_data, is_looping)
    if type(ab_data) == "boolean" then is_looping = ab_data; ab_data = nil end
    ab_data = type(ab_data) == "table" and ab_data or nil
    local positions = ab_data and type(ab_data.towerPosition) == "table" and ab_data.towerPosition or nil
    local clone_list = {}
    if ab_data and type(ab_data.cloneTowerList) == "table" then
        clone_list = ab_data.cloneTowerList
    elseif ab_data and ab_data.towerToClone then
        clone_list = { ab_data.towerToClone }
    end
    local target_idx = ab_data and ab_data.towerTarget
    local attempts_per_id = (ab_data and ab_data.attemptsPerId) or 3
    local current_index, attempt_counter, list_len = 1, 0, #clone_list
    local function attempt_ability(clone_id)
        local tower_to_clone = TDS.placed_towers[clone_id]
        if not tower_to_clone then return false end
        local data = ab_data and table.clone(ab_data) or nil
        if data then
            if positions and #positions > 0 then data.towerPosition = positions[math.random(#positions)] end
            data.towerToClone = tower_to_clone
            if type(target_idx) == "number" then data.towerTarget = TDS.placed_towers[target_idx] end
        end
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Abilities", "Activate", {
                Troop = t_obj, Name = ab_name, Data = data
            })
        end)
        if not ok then warn("Ability invoke failed:", res); return false end
        return check_res_ok(res)
    end
    local function run_cycle()
        if list_len == 0 then attempt_ability(nil); return end
        local clone_id = clone_list[current_index]
        attempt_ability(clone_id)
        attempt_counter = attempt_counter + 1
        if attempt_counter >= attempts_per_id then
            attempt_counter = 0
            current_index = current_index % list_len + 1
        end
    end
    if is_looping then
        local active = true
        task.spawn(function()
            while active do run_cycle(); task.wait(1) end
        end)
        return function() active = false end
    else
        run_cycle()
    end
    return nil
end

function TDS:Loadout(...)
    local raw_args = {...}
    local desiredTowers = (#raw_args == 1 and type(raw_args[1]) == "table") and raw_args[1] or raw_args
    if #desiredTowers == 0 then return false, "no towers provided" end
    local replicated = game:GetService("ReplicatedStorage")
    local httpService = game:GetService("HttpService")
    local player = game:GetService("Players").LocalPlayer
    local remote = replicated:FindFirstChild("RemoteFunction")
    if not remote then return false, "RemoteFunction not found" end
    local currentlyEquipped = {}
    local SR = replicated:FindFirstChild("StateReplicators")
    if SR then
        for _, folder in ipairs(SR:GetChildren()) do
            if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == player.UserId then
                local eq = folder:GetAttribute("EquippedTowers")
                if type(eq) == "string" then
                    local cleaned = eq:match("%[.*%]")
                    local ok, decoded = pcall(function() return httpService:JSONDecode(cleaned) end)
                    if ok and type(decoded) == "table" then currentlyEquipped = decoded end
                end
                break
            end
        end
    end
    local desiredLookup = {}
    for _, n in ipairs(desiredTowers) do if n and n ~= "" then desiredLookup[n] = true end end
    for _, currentTower in ipairs(currentlyEquipped) do
        if currentTower ~= "None" and not desiredLookup[currentTower] then
            repeat
                local ok = pcall(function() remote:InvokeServer("Inventory", "Unequip", "tower", currentTower) end)
                if ok then break end
                task.wait(0.2)
            until false
            task.wait(0.3)
        end
    end
    task.wait(0.5)
    for _, towerName in ipairs(desiredTowers) do
        if towerName and towerName ~= "" then
            local already = false
            for _, e in ipairs(currentlyEquipped) do if e == towerName then already = true; break end end
            if not already then
                repeat
                    local ok = pcall(function() remote:InvokeServer("Inventory", "Equip", "tower", towerName) end)
                    if ok then break end
                    task.wait(0.2)
                until false
                task.wait(0.3)
            end
        end
    end
    task.wait(0.5)
    return true
end


function TDS:UnlockTimeScale() unlock_speed_tickets() end
function TDS:TimeScale(val) set_game_timescale(val) end
function TDS:Ready()
    if game_state ~= "GAME" then return false end
    match_ready_up()
end

function TDS:Place(t_name, px, py, pz, ...)
    if game_state ~= "GAME" then return false end
    local existing = {}
    for _, child in ipairs(workspace.Towers:GetChildren()) do
        for _, sc in ipairs(child:GetChildren()) do
            if sc.Name == "Owner" and sc.Value == local_player.UserId then existing[child] = true; break end
        end
    end
    do_place_tower(t_name, Vector3.new(px, py, pz))
    local new_t
    repeat
        for _, child in ipairs(workspace.Towers:GetChildren()) do
            if not existing[child] then
                for _, sc in ipairs(child:GetChildren()) do
                    if sc.Name == "Owner" and sc.Value == local_player.UserId then new_t = child; break end
                end
            end
            if new_t then break end
        end
        task.wait(0.05)
    until new_t
    table.insert(self.placed_towers, new_t)
    return #self.placed_towers
end

function TDS:Upgrade(idx, p_id)
    local t = self.placed_towers[idx]
    if t then
        do_upgrade_tower(t, p_id or 1)
        upgrade_history[idx] = (upgrade_history[idx] or 0) + 1
    end
end

function TDS:Sell(idx)
    local t = self.placed_towers[idx]
    if t and do_sell_tower(t) then return true end
    return false
end

function TDS:SetTarget(idx, target_type)
    local t = self.placed_towers[idx]; if not t then return end
    pcall(function()
        remote_func:InvokeServer("Troops", "Target", "Set", { Troop = t, Target = target_type })
    end)
end

function TDS:SetOption(idx, name, val)
    local t = self.placed_towers[idx]
    if t then return do_set_option(t, name, val) end
    return false
end

function TDS:MedicSelect(idx, val)
    local t = self.placed_towers[idx]
    local target = self.placed_towers[val]
    if t and target then
        remote_func:InvokeServer("Troops", "TowerServerEvent", "ToggleSelectedTower", t, target)
        return true
    end
    return false
end

function TDS:Ability(idx, name, data, loop)
    local t = self.placed_towers[idx]
    if not t then return false end
    return do_activate_ability(t, name, data, loop)
end

function TDS:PresetLoadout(name)
    if type(name) ~= "string" then return false end
    return pcall(function()
        if name == "Own" then
            game:GetService("ReplicatedStorage").Network.PlayerManager["RE:UserLoadout"]:FireServer()
        else
            game:GetService("ReplicatedStorage").Network.PlayerManager["RE:SelectLoadout"]:FireServer(name)
        end
    end)
end

function TDS:Continue()
    repeat
        task.wait(0.1)
        local uiRoot = player_gui:FindFirstChild("ReactGameNewRewards")
        if uiRoot then
            local mainFrame = uiRoot:FindFirstChild("Frame")
            if mainFrame and mainFrame.Visible then
                local gameOver = mainFrame:FindFirstChild("gameOver")
                if gameOver and gameOver.Visible then
                    local rs = gameOver:FindFirstChild("RewardsScreen")
                    if rs and rs.Visible then
                        local tb = rs:FindFirstChild("RewardBanner")
                        if tb then
                            local lbl = tb:FindFirstChild("textLabel") or tb:FindFirstChildOfClass("TextLabel")
                            if lbl then
                                local txt = lbl.Text:upper()
                                if txt ~= "" and (txt:find("TRIUMPH") or txt:find("VICTORY") or txt:find("WIN")
                                    or txt:find("LOST") or txt:find("DEFEAT") or txt:find("FAIL")) then
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    until false
    task.wait(1)
    game:GetService("ReplicatedStorage").Network.GameManager["RF:NextMission"]:InvokeServer()
end

function TDS:RegisterStrategy(mapName, strategyFunction)
    self.strategies[mapName] = strategyFunction
end
function TDS:RegisterStrategies(strategyTable)
    for mapName, strategyFunc in pairs(strategyTable) do
        self:RegisterStrategy(mapName, strategyFunc)
    end
end

function TDS:SelectMapWithPriority(mapPriorityList, maxAttempts)
    if marketplace_service:UserOwnsGamePassAsync(game.Players.LocalPlayer.UserId, 10518590) then
        return mapPriorityList[1]
    end
    maxAttempts = maxAttempts or 2
    repeat task.wait() until game.Players.LocalPlayer.PlayerGui:FindFirstChild("ReactGameIntermission")
    task.wait(1)
    local selectedMap = nil
    for attempt = 1, maxAttempts do
        local availableMaps = self:GetAvailableMaps()
        for _, preferredMap in ipairs(mapPriorityList) do
            for _, availableMap in ipairs(availableMaps) do
                if availableMap == preferredMap then selectedMap = preferredMap; break end
            end
            if selectedMap then break end
        end
        if selectedMap then break end
        if attempt == 1 then self:VetoMaps(); task.wait(1) end
    end
    if not selectedMap then
        task.wait(1)
        teleport_service:Teleport(3260590327)
        return nil
    end
    return selectedMap
end

function TDS:RunStrategy(config)
    if not config.mode then error("TDS:RunStrategy - mode is required") end
    if not config.mapPriority then error("TDS:RunStrategy - mapPriority is required") end
    self:Mode(config.mode)
    local selectedMap = self:SelectMapWithPriority(config.mapPriority, config.maxAttempts)
    if not selectedMap then return false end
    local strategy = config.strategies and config.strategies[selectedMap]
    if not strategy and config.defaultStrategy then strategy = config.defaultStrategy end
    if strategy then self.pending_strategy = strategy end
    self:GameInfo(selectedMap, config.modifiers or {})
    return true
end

function TDS:GameInfo(mapName, modifiers)
    while not _G.AutoRejoin do task.wait(0.5) end
    modifiers = modifiers or {}
    if game_state ~= "GAME" then warn("Not in game state for GameInfo"); return false end

    local vote_gui
    while true do
        vote_gui = player_gui:FindFirstChild("ReactGameIntermission")
        if vote_gui and vote_gui.Enabled then break end
        task.wait(2)
    end

    local frame
    while true do
        frame = vote_gui:FindFirstChild("Frame")
        if frame then break end
        task.wait(2)
    end

    cast_modifier_vote(modifiers)
    task.wait(0.5)

    if marketplace_service:UserOwnsGamePassAsync(local_player.UserId, 10518590) then
        select_map_override(mapName, "vip"); return true
    end

    local veto_cast = false
    local veto_value = frame.buttons.veto.value
    repeat
        if is_map_available(mapName) then select_map_override(mapName); return true end
        local veto_text = veto_value.Text
        if veto_text ~= "" and not veto_text:find("Veto") then break end
        local current_str, total_str = veto_text:match("(%d+)/(%d+)")
        local current = current_str and tonumber(current_str) or 0
        local total = total_str and tonumber(total_str) or #Players:GetChildren()
        if not veto_cast and total > 0 and current == 0 then
            veto_and_wait_for_maps(); veto_cast = true
        end
        task.wait(2)
        if #Players:GetChildren() > 0 and current == #Players:GetChildren() then break end
    until false
    warn("Map '" .. tostring(mapName) .. "' not available after veto, teleporting to lobby")
    task.wait(1)
    teleport_service:Teleport(3260590327, local_player)
    return false
end

function TDS:HandleGameEnd()
    while true do
        local uiRoot = player_gui:FindFirstChild("ReactGameNewRewards")
        if uiRoot then
            local mainFrame = uiRoot:FindFirstChild("Frame")
            if mainFrame and mainFrame.Visible then
                local gameOver = mainFrame:FindFirstChild("gameOver")
                if gameOver and gameOver.Visible then
                    local rewardsScreen = gameOver:FindFirstChild("RewardsScreen")
                    if rewardsScreen and rewardsScreen.Visible then
                        local topBanner = rewardsScreen:FindFirstChild("RewardBanner")
                        if topBanner then
                            local label = topBanner:FindFirstChild("textLabel") or topBanner:FindFirstChildOfClass("TextLabel")
                            if label then
                                local txt = label.Text:upper()
                                if txt ~= "" then
                                    local isLoss = false
                                    if txt:find("LOST") or txt:find("DEFEAT") or txt:find("FAIL") then isLoss = true
                                    elseif txt:find("TRIUMPH") or txt:find("VICTORY") or txt:find("WIN") then isLoss = false end

                                    if isLoss then
                                        task.wait(0.2)
                                        self.placed_towers = {}
                                        upgrade_history = {}
                                    end

                                    local deadline = tick() + 30
                                    while tick() < deadline do
                                        task.wait(0.1)
                                        local f = uiRoot:FindFirstChild("Frame")
                                        local g = f and f:FindFirstChild("gameOver")
                                        local s = g and g:FindFirstChild("RewardsScreen")
                                        if s and s:FindFirstChild("RewardsSection") then break end
                                    end

                                    while true do
                                        local still = false
                                        local u2 = player_gui:FindFirstChild("ReactGameNewRewards")
                                        if u2 then
                                            local f2 = u2:FindFirstChild("Frame")
                                            if f2 and f2.Visible then
                                                local g2 = f2:FindFirstChild("gameOver")
                                                if g2 and g2.Visible then
                                                    local s2 = g2:FindFirstChild("RewardsScreen")
                                                    if s2 and s2.Visible then still = true end
                                                end
                                            end
                                        end
                                        if not still then break end
                                        run_vote_skip()
                                        task.wait(0.1)
                                    end

                                    if self.ReplayCallback then
                                        local cb = self.ReplayCallback
                                        task.spawn(function()
                                            local ok, err = pcall(cb)
                                            if not ok then warn("ReplayCallback error:", err) end
                                        end)
                                    end
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
        task.wait(0.1)
    end
end

function TDS:Mode(difficulty)
    while not _G.AutoRejoin do task.wait(0.5) end
    if game_state ~= "LOBBY" then return false end

    if type(difficulty) == "string" then
        local act_num = difficulty:match("^Act(%d+)")
        if act_num then
            local remote = replicated_storage:WaitForChild("RemoteFunction")
            local success = false
            repeat
                local ok, result = pcall(function()
                    return remote:InvokeServer("Multiplayer", "v2:start", {
                        difficulty = difficulty, night = tonumber(act_num),
                        count = 1, mode = "halloween2026"
                    })
                end)
                if ok and check_res_ok(result) then success = true
                else task.wait(2) end
            until success
            return true
        end
    end

    if difficulty == "Trial" then
        local Elevators = workspace:WaitForChild("Elevators")
        local Network = replicated_storage:WaitForChild("Network")
        if Elevators and Network then
            local targetElevator
            repeat
                for _, v in pairs(Elevators:GetChildren()) do
                    if v.Name:match("Trial") or v.Name:match("Event") then targetElevator = v; break end
                end
                if not targetElevator then task.wait(2) end
            until targetElevator
            task.spawn(function()
                local EN = Network:WaitForChild("Elevators")
                pcall(function() EN:WaitForChild("RF:Enter"):InvokeServer(targetElevator) end)
                pcall(function() EN:WaitForChild("RF:SetSize"):InvokeServer(1) end)
                pcall(function() EN:WaitForChild("RF:SetReady"):InvokeServer(true) end)
            end)
            return true
        end
    end

    local LobbyHud
    while true do
        LobbyHud = player_gui:FindFirstChild("ReactLobbyHud")
        if LobbyHud then break end
        task.wait(2)
    end
    local frame
    while true do
        frame = LobbyHud:FindFirstChild("Frame")
        if frame then break end
        task.wait(2)
    end
    local MatchMaking
    while true do
        MatchMaking = frame:FindFirstChild("matchmaking")
        if MatchMaking then break end
        task.wait(2)
    end

    local remote = replicated_storage:WaitForChild("RemoteFunction")
    local success = false
    repeat
        local ok, result = pcall(function()
            local mode = TDS.matchmaking_map[difficulty]
            local payload
            if difficulty == "Hardcore" then payload = { mode = "hardcore", difficulty = "Easy", count = 1 }
            elseif difficulty == "Voidcore" then payload = { mode = "hardcore", difficulty = "Hard", count = 1 }
            elseif mode then payload = { mode = mode, count = 1 }
            else payload = { difficulty = difficulty, mode = "survival", count = 1 }
            end
            return remote:InvokeServer("Multiplayer", "v2:start", payload)
        end)
        if ok and check_res_ok(result) then success = true
        else task.wait(2) end
    until success
    return true
end

function is_void_charm(obj) return math.abs(obj.Position.Y) > 999999 end
function get_root()
    local char = local_player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

function start_auto_pickups()
    if auto_pickups_running or not _G.AutoPickups then return end
    auto_pickups_running = true
    task.spawn(function()
        while _G.AutoPickups do
            local folder = workspace:FindFirstChild("Pickups")
            local hrp = get_root()
            if folder and hrp then
                for _, item in ipairs(folder:GetChildren()) do
                    if not _G.AutoPickups then break end
                    if item:IsA("MeshPart") and (item.Name == "Fragment" or item.Name == "Lorebook") then
                        if not is_void_charm(item) then
                            local old = hrp.CFrame
                            hrp.CFrame = item.CFrame * CFrame.new(0, 3, 0)
                            task.wait(0.2)
                            hrp.CFrame = old
                            task.wait(0.3)
                        end
                    end
                end
            end
            task.wait(1)
        end
        auto_pickups_running = false
    end)
end

last_skip_click = 0

function is_skip_vote_visible()
    local b = player_gui:FindFirstChild("ReactOverridesVote")
    b = b and b:FindFirstChild("Frame")
    b = b and b:FindFirstChild("votes")
    b = b and b:FindFirstChild("vote", true)
    return b and b.Visible and b.Position == UDim2.new(0.5, 0, 0.5, 0)
end

function click_skip_vote()
    local now = tick()
    if now - last_skip_click < 0.3 then return end
    last_skip_click = now
    pcall(function() remote_func:InvokeServer("Voting", "Skip") end)
    pcall(function() remote_event:FireServer("Voting", "Skip") end)
end

function skip_is_active()
    if type(_G.ReverseAutoSkip) == "table" and #_G.ReverseAutoSkip > 0 then return true end
    if _G.AutoSkip == true then return true end
    if type(_G.AutoSkip) == "table" and #_G.AutoSkip > 0 then return true end
    return false
end

function should_skip_wave(wave)
    if not wave or wave <= 0 then return false end

    if type(_G.ReverseAutoSkip) == "table" and #_G.ReverseAutoSkip > 0 then
        for _, w in ipairs(_G.ReverseAutoSkip) do
            if w == wave then return false end
        end
        return true
    end

    if _G.AutoSkip == true then return true end

    if type(_G.AutoSkip) == "table" and #_G.AutoSkip > 0 then
        for _, w in ipairs(_G.AutoSkip) do
            if w == wave then return true end
        end
    end
    return false
end

function start_auto_skip()
    if auto_skip_running then return end
    auto_skip_running = true
    task.spawn(function()
        while true do
            if skip_is_active() then
                local wave = read_current_wave_safe()
                if should_skip_wave(wave) and is_skip_vote_visible() then
                    click_skip_vote()
                end
            end
            task.wait(0.1)
        end
    end)
end

function start_claim_rewards()
    if auto_claim_rewards or not _G.ClaimRewards or game_state ~= "LOBBY" then return end
    auto_claim_rewards = true
    local player = game:GetService("Players").LocalPlayer
    local network = game:GetService("ReplicatedStorage"):WaitForChild("Network")
    local st = player:WaitForChild("SpinTickets", 15)
    if st and st.Value > 0 then
        local rs = network:WaitForChild("DailySpin", 5)
        local redeem = rs and rs:WaitForChild("RF:RedeemSpin", 5)
        if redeem then
            for i = 1, st.Value do redeem:InvokeServer(); task.wait(0.5) end
        end
    end
    for i = 1, 6 do
        network:WaitForChild("PlaytimeRewards"):WaitForChild("RF:ClaimReward"):InvokeServer(i)
        task.wait(0.5)
    end
    auto_claim_rewards = false
end

auto_cutscene_skip_running = false

function find_hold_to_skip_button()
    local pg = get_player_gui(); if not pg then return nil end
    for _, v in ipairs(pg:GetDescendants()) do
        if (v:IsA("TextLabel") or v:IsA("TextButton")) and (v.Text or ""):upper():find("HOLD TO SKIP") then
            local c = v
            while c and c ~= pg do
                if c:IsA("GuiButton") then return c end
                c = c.Parent
            end
        end
    end
    return nil
end

function fire_cutscene_skip(button)
    if not button or not button.Parent then return end
    pcall(function() firesignal(button.MouseButton1Down) end)
    task.wait(1.5)
    if not button.Parent then return end
    pcall(function() firesignal(button.MouseButton1Up) end)
    pcall(function() firesignal(button.MouseButton1Click) end)
    pcall(function() firesignal(button.Activated) end)
end

function start_auto_cutscene_skip()
    if auto_cutscene_skip_running then return end
    auto_cutscene_skip_running = true
    local pg = get_player_gui()
    local last = nil
    local function try_skip()
        local b = find_hold_to_skip_button()
        if b and b ~= last then last = b; task.spawn(fire_cutscene_skip, b)
        elseif not b then last = nil end
    end
    if pg then
        pg.DescendantAdded:Connect(function(obj)
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then try_skip() end
        end)
    end
    task.spawn(function()
        while true do try_skip(); task.wait(0.5) end
    end)
end

task.spawn(function()
    while true do
        if not auto_cutscene_skip_running then start_auto_cutscene_skip() end
        task.wait(1)
    end
end)

function start_anti_lag()
    if anti_lag_running then return end
    anti_lag_running = true
    local settings = settings().Rendering
    settings.QualityLevel = Enum.QualityLevel.Level01
    local Lighting = game:GetService("Lighting")
    local player = game:GetService("Players").LocalPlayer
    local pg = player:WaitForChild("PlayerGui")
    local Terrain = workspace:FindFirstChildOfClass("Terrain")

    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogStart = 0
        Lighting.FogEnd = 9e9
        Lighting.FogColor = Color3.fromRGB(180, 180, 180)
    end)
    if Terrain then
        pcall(function()
            Terrain.WaterWaveSize = 0; Terrain.WaterWaveSpeed = 0
            Terrain.WaterReflectance = 0; Terrain.WaterTransparency = 0
        end)
    end
    for _, v in ipairs(Lighting:GetDescendants()) do
        pcall(function()
            if v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("ColorCorrectionEffect")
                or v:IsA("BloomEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("Atmosphere") then
                v.Enabled = false
            end
        end)
    end

    function processPart(v)
        if not v or not v.Parent then return end
        pcall(function()
            if v:IsA("BasePart") or v:IsA("UnionOperation") or v:IsA("MeshPart")
                or v:IsA("CornerWedgePart") or v:IsA("TrussPart") then
                if v.Material ~= Enum.Material.SmoothPlastic and v.Material ~= Enum.Material.Neon
                    and v.Material ~= Enum.Material.ForceField then
                    v.Material = Enum.Material.Plastic
                end
                v.Reflectance = 0
                v.CastShadow = false
            end
            if v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1 end
            if v:IsA("ParticleEmitter") or v:IsA("Trail") then v.Enabled = false end
        end)
    end

    task.spawn(function()
        local desc = workspace:GetDescendants()
        local b = 200
        for i = 1, #desc, b do
            for j = i, math.min(i + b - 1, #desc) do processPart(desc[j]) end
            task.wait(0.05)
        end
    end)

    local conns = {}
    table.insert(conns, workspace.DescendantAdded:Connect(function(v)
        task.wait(0.1)
        if _G.AntiLag then processPart(v) end
    end))
    table.insert(conns, Lighting.DescendantAdded:Connect(function(v)
        task.wait(0.1)
        if _G.AntiLag then
            pcall(function()
                if v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("ColorCorrectionEffect")
                    or v:IsA("BloomEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("Atmosphere") then
                    v.Enabled = false
                end
            end)
        end
    end))

    function muteSound(name)
        local sg = pg:FindFirstChild("SoundGui"); if not sg then return end
        local s = sg:FindFirstChild(name)
        if s and s:IsA("Sound") then s.Volume = 0
        else
            table.insert(conns, sg.ChildAdded:Connect(function(c)
                if c.Name == name and c:IsA("Sound") then c.Volume = 0 end
            end))
        end
    end
    muteSound("Error")
    muteSound("Notification")

    local ro = pg:FindFirstChild("ReactOverridesNotifications")
    if ro then ro:Destroy() end
    table.insert(conns, pg.ChildAdded:Connect(function(c)
        if c.Name == "ReactOverridesNotifications" then c:Destroy() end
    end))

    task.spawn(function()
        while _G.AntiLag do
            local tf = workspace:FindFirstChild("Towers")
            local cu = workspace:FindFirstChild("ClientUnits")
            if tf then
                for _, t in ipairs(tf:GetChildren()) do
                    for _, n in ipairs({"Animations","Weapon","Projectiles"}) do
                        local f = t:FindFirstChild(n); if f then f:Destroy() end
                    end
                end
            end
            if cu then for _, u in ipairs(cu:GetChildren()) do u:Destroy() end end
            task.wait(0.5)
        end
        anti_lag_running = false
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    end)
end

function autoReadyLoop()
    while true do
        if _G.AutoReady then
            local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
            if pg then
                local ui_ov = pg:FindFirstChild("ReactOverridesVote")
                local frame = ui_ov and ui_ov:FindFirstChild("Frame")
                local votes = frame and frame:FindFirstChild("votes")
                local cont = votes and votes:FindFirstChild("container")
                local ready = cont and cont:FindFirstChild("ready")
                    
                if ready and ready.Visible then
                    local r_cont = ready:FindFirstChild("container")
                    local txt = r_cont and r_cont:FindFirstChild("text")
        
                    if txt and txt.Text == "READY" then
                        pcall(function() remote_event:FireServer("LobbyVoting", "Ready") end)
                        pcall(function() remote_func:InvokeServer("Voting", "Skip") end)
                    
                        pcall(match_ready_up)
                    
                        task.wait(0.5)
                    else
                        task.wait(0.1)
                    end
                else
                    task.wait(0.1)
                end
            else
                task.wait(0.1)
            end
        else
            task.wait(0.1)
        end
    end
end
task.spawn(autoReadyLoop)

function start_rejoin_on_disconnect()
    task.spawn(function()
        game.Players.PlayerRemoving:connect(function(plr)
            if plr == game.Players.LocalPlayer then
                game:GetService('TeleportService'):Teleport(3260590327, plr)
            end
        end)
    end)
end
start_rejoin_on_disconnect()

VirtualUser = game:GetService("VirtualUser")
function setupAntiAFK()
    pcall(function()
        localPlayer.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end)
end
setupAntiAFK()
localPlayer.CharacterAdded:Connect(function()
    task.wait(1); setupAntiAFK()
end)

function start_auto_dj_booth()
    if auto_dj_running or not _G.AutoDJ then return end
    auto_dj_running = true
    task.spawn(function()
        while _G.AutoDJ do
            local tf = workspace:FindFirstChild("Towers")
            if tf then
                for _, t in ipairs(tf:GetDescendants()) do
                    if t:IsA("Folder") and t.Name == "TowerReplicator"
                        and t:GetAttribute("Name") == "DJ Booth"
                        and t:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                        and (t:GetAttribute("Upgrade") or 0) >= 3 then
                        DJ = t.Parent
                    end
                end
            end
            if DJ then
                remote_func:InvokeServer("Troops", "Abilities", "Activate",
                    { Troop = DJ, Name = "Drop The Beat", Data = {} })
            end
            task.wait(1)
        end
        auto_dj_running = false
    end)
end

function start_auto_uber()
    if auto_uber_running or not _G.AutoUber then return end
    auto_uber_running = true
    task.spawn(function()
        while _G.AutoUber do
            local tf = workspace:FindFirstChild("Towers")
            if tf then
                for _, t in ipairs(tf:GetDescendants()) do
                    if t:IsA("Folder") and t.Name == "TowerReplicator"
                        and t:GetAttribute("Name") == "Medic"
                        and t:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                        and (t:GetAttribute("Upgrade") or 0) >= 3 then
                        remote_func:InvokeServer("Troops", "Abilities", "Activate",
                            { Troop = t.Parent, Name = "Ubercharge", Data = {} })
                        task.wait(0.5)
                    end
                end
            end
            task.wait(0.2)
        end
        auto_uber_running = false
    end)
end

function start_auto_chain()
    if auto_chain_running or not _G.AutoChain then return end
    auto_chain_running = true
    function get_commanders_with_pos()
        local commanders = {}
        local tf = workspace:FindFirstChild("Towers"); if not tf then return commanders end
        for _, t in ipairs(tf:GetDescendants()) do
            if t:IsA("Folder") and t.Name == "TowerReplicator"
                and t:GetAttribute("Name") == "Commander"
                and t:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                and (t:GetAttribute("Upgrade") or 0) >= 2 then
                local pos = getTowerPosition(t.Parent)
                if pos then table.insert(commanders, {commander = t.Parent, pos = pos}) end
            end
        end
        return commanders
    end
    function form_groups_of_three(list)
        local groups, ungrouped = {}, {}
        for i, d in ipairs(list) do ungrouped[i] = {commander = d.commander, pos = d.pos} end
        while #ungrouped >= 3 do
            local anchor = ungrouped[1]
            local nearest = {}
            for i = 2, #ungrouped do
                table.insert(nearest, {idx = i, dist = (anchor.pos - ungrouped[i].pos).Magnitude})
            end
            table.sort(nearest, function(a,b) return a.dist < b.dist end)
            table.insert(groups, {anchor.commander, ungrouped[nearest[1].idx].commander, ungrouped[nearest[2].idx].commander})
            local to_remove = {1, nearest[1].idx, nearest[2].idx}
            table.sort(to_remove, function(a,b) return a > b end)
            for _, r in ipairs(to_remove) do table.remove(ungrouped, r) end
        end
        return groups
    end

    task.spawn(function()
        while _G.AutoChain and auto_chain_running do
            local groups = form_groups_of_three(get_commanders_with_pos())
            if #groups == 0 then task.wait(1)
            else
                local counter = 0
                for _, group in ipairs(groups) do
                    counter = counter + 1
                    task.spawn(function()
                        for _, c in ipairs(group) do
                            if not (_G.AutoChain and auto_chain_running) then break end
                            pcall(function()
                                remote_func:InvokeServer("Troops", "Abilities", "Activate",
                                    { Troop = c, Name = "Call Of Arms", Data = {} })
                            end)
                            local ts = player_gui:FindFirstChild("ReactUniversalHotbar")
                                and player_gui.ReactUniversalHotbar:FindFirstChild("Frame")
                                and player_gui.ReactUniversalHotbar.Frame:FindFirstChild("timescale")
                            task.wait((ts and ts.Visible and ts:FindFirstChild("Lock")) and 10.3 or 5.25)
                        end
                        counter = counter - 1
                    end)
                end
                while counter > 0 do task.wait(0.5) end
            end
        end
        auto_chain_running = false
    end)
end

function start_auto_support()
    if auto_support_running or not _G.AutoSupport then return end
    auto_support_running = true
    task.spawn(function()
        while _G.AutoSupport do
            local tf = workspace:FindFirstChild("Towers")
            if tf then
                for _, t in ipairs(tf:GetDescendants()) do
                    if t:IsA("Folder") and t.Name == "TowerReplicator"
                        and t:GetAttribute("Name") == "Commander"
                        and t:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                        and (t:GetAttribute("Upgrade") or 0) >= 4 then
                        remote_func:InvokeServer("Troops", "Abilities", "Activate",
                            { Troop = t.Parent, Name = "Support Caravan", Data = {} })
                        task.wait(0.5)
                    end
                end
            end
            task.wait(0.2)
        end
        auto_support_running = false
    end)
end

NECRO_DELAY = 1.5
necroTimers = {}
remoteFunc = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteFunction")

function start_auto_necro()
    if auto_necro_running or not _G.AutoNecro then return end
    auto_necro_running = true
    task.spawn(function()
        while _G.AutoNecro do
            local now = tick()
            local towers = workspace:FindFirstChild("Towers")
            if towers then
                for _, t in pairs(towers:GetChildren()) do
                    local rep = t:FindFirstChild("TowerReplicator")
                    if rep and rep:GetAttribute("Name") == "Necromancer"
                        and rep:GetAttribute("OwnerId") == localPlayer.UserId then
                        local ammo = rep:GetAttribute("Ammo") or 0
                        local max = rep:GetAttribute("MaxAmmo") or 1
                        if ammo == max then
                            if not necroTimers[t] then necroTimers[t] = now
                            elseif now - necroTimers[t] >= NECRO_DELAY then
                                if remoteFunc then
                                    remoteFunc:InvokeServer("Troops", "Abilities", "Activate",
                                        { Troop = t, Name = "Raise The Dead", Data = {} })
                                end
                                necroTimers[t] = nil
                            end
                        else necroTimers[t] = nil end
                    end
                end
            end
            task.wait()
        end
        auto_necro_running = false
        necroTimers = {}
    end)
end

function start_smart_auto_skip()
    if auto_smart_skip_running or not _G.AutoSmartSkip then return end
    auto_smart_skip_running = true
    local HEALTH_THRESHOLDS = { [1] = 10, [6] = 50, [16] = 150, [26] = 500, [36] = 2500 }
    local tracking = {wave = 0, wave_start_time = 0, skip_active = false}

    local function smart_wave_get()
        local ok, r = pcall(function()
            local v = player_gui.ReactGameTopGameDisplay.Frame.wave.container.value
            return tonumber(v.Text:match("^(%d+)")) or 0
        end)
        return ok and r or 0
    end
    local function total_enemy_health()
        local total = 0
        local sr = replicated_storage:FindFirstChild("StateReplicators"); if not sr then return 0 end
        for _, f in ipairs(sr:GetChildren()) do
            if f.Name == "NPCReplicator" and f:GetAttribute("Type") == "Enemies"
                and f:GetAttribute("DisplayName") ~= "Corpse" then
                local h = f:GetAttribute("Health")
                if h and type(h) == "number" and h > 0 then total = total + h end
            end
        end
        return total
    end
    local function is_vote_visible()
        local b = player_gui:FindFirstChild("ReactOverridesVote")
        b = b and b:FindFirstChild("Frame")
        b = b and b:FindFirstChild("votes")
        b = b and b:FindFirstChild("vote", true)
        return b and b.Visible and b.Position == UDim2.new(0.5, 0, 0.5, 0)
    end
    local function click_vote()
        local b = player_gui:FindFirstChild("ReactOverridesVote")
        b = b and b:FindFirstChild("Frame")
        b = b and b:FindFirstChild("votes")
        b = b and b:FindFirstChild("vote", true)
        if b then
            if b:IsA("GuiButton") then b:Click() end
            for _, e in ipairs(b:GetChildren()) do if e:IsA("BindableEvent") then e:Fire() end end
        end
        pcall(function() remote_func:InvokeServer("Voting", "Skip") end)
        pcall(function() remote_event:FireServer("Voting", "Skip") end)
    end

    task.spawn(function()
        while _G.AutoSmartSkip do
            local cw = smart_wave_get()
            if cw ~= tracking.wave then
                tracking.wave = cw
                tracking.wave_start_time = tick()
                tracking.skip_active = false
            end
            if not tracking.skip_active and tick() - tracking.wave_start_time > 10 then
                local h = total_enemy_health()
                local threshold = 2500
                for w, t in pairs(HEALTH_THRESHOLDS) do if cw >= w then threshold = t end end
                if h < threshold then
                    tracking.skip_active = true
                    task.spawn(function()
                        while tracking.skip_active and _G.AutoSmartSkip do
                            if smart_wave_get() > tracking.wave then tracking.skip_active = false; break end
                            if is_vote_visible() then click_vote() end
                            task.wait(0.1)
                        end
                    end)
                end
            end
            task.wait(0.2)
        end
        auto_smart_skip_running = false
    end)
end

if _G.AutoSmartSkip then task.spawn(start_smart_auto_skip) end

bountyModeConfigs = { Frost = { threshold = 10000, priorityThreshold = 60000 } }
defaultBountyThreshold = 5000
defaultBountyPriority  = 20000
auto_bounty_running    = false

function getBountyThresholds()
    if _G.AutoBountyThreshold or _G.AutoBountyPriority then
        return _G.AutoBountyThreshold or defaultBountyThreshold,
               _G.AutoBountyPriority  or defaultBountyPriority
    end
    local mode
    local sr = replicated_storage:FindFirstChild("StateReplicators")
    if sr then
        local gs = sr:FindFirstChild("GameStateReplicator")
        if gs then mode = gs:GetAttribute("DifficultyDisplayName") or gs:GetAttribute("GameMode") end
    end
    local cfg = bountyModeConfigs[mode]
    if cfg then return cfg.threshold, cfg.priorityThreshold end
    return defaultBountyThreshold, defaultBountyPriority
end

function getEnemyPosition(enemyFolder)
    local name = enemyFolder.Name
    local model = workspace:FindFirstChild(name)
    if model then
        local p = model:FindFirstChild("PrimaryPart") or model:FindFirstChild("Head")
            or model:FindFirstChildWhichIsA("BasePart")
        if p then return p.Position end
    end
    for _, part in ipairs(workspace:GetDescendants()) do
        if part.Name == name and part:IsA("BasePart") then return part.Position end
    end
    return nil
end

function getEligibleEnemies(threshold, priorityThreshold)
    local enemies = { priority = {}, normal = {} }
    local sr = replicated_storage:FindFirstChild("StateReplicators"); if not sr then return enemies end
    for _, f in ipairs(sr:GetChildren()) do
        if f:IsA("Folder") and f:GetAttribute("MaxHealth") then
            local hp = f:GetAttribute("MaxHealth")
            if hp and hp >= threshold then
                local e = { folder = f, hp = hp, pos = getEnemyPosition(f) }
                if hp >= priorityThreshold then table.insert(enemies.priority, e)
                else table.insert(enemies.normal, e) end
            end
        end
    end
    table.sort(enemies.priority, function(a,b) return a.hp > b.hp end)
    return enemies
end

function getOwnedKingpins()
    local list = {}
    local tf = workspace:FindFirstChild("Towers"); if not tf then return list end
    for _, f in ipairs(tf:GetChildren()) do
        local rep = f:FindFirstChild("TowerReplicator")
        if rep and rep:GetAttribute("Name") and string.lower(rep:GetAttribute("Name")):find("kingpin") then
            if tostring(rep:GetAttribute("OwnerId")) == tostring(local_player.UserId) then
                table.insert(list, f)
            end
        end
    end
    return list
end

function useBountyOnEnemy(tower, enemyFolder)
    if not remote_func or not tower or not enemyFolder then return false end
    local ok, result = pcall(function()
        return remote_func:InvokeServer("Troops", "Abilities", "Activate", {
            Troop = tower, Name = "Bounty", Data = { ReplicatorFolder = enemyFolder }
        })
    end)
    return ok and result == true
end

function start_auto_bounty()
    if auto_bounty_running or not _G.AutoBounty then return end
    auto_bounty_running = true
    task.spawn(function()
        while _G.AutoBounty do
            local threshold, priorityThreshold = getBountyThresholds()
            local enemies = getEligibleEnemies(threshold, priorityThreshold)
            local kingpins = getOwnedKingpins()
            if #kingpins == 0 or (#enemies.priority == 0 and #enemies.normal == 0) then
                task.wait(0.5)
            else
                local used = {}
                local targeted = 0
                for _, king in ipairs(kingpins) do
                    local chosen
                    local kpos = getTowerPosition(king)
                    for _, e in ipairs(enemies.priority) do
                        if not used[e.folder] then chosen = e; break end
                    end
                    if not chosen and #enemies.normal > 0 then
                        if kpos then
                            table.sort(enemies.normal, function(a,b)
                                return (a.pos and (a.pos - kpos).Magnitude or math.huge)
                                     < (b.pos and (b.pos - kpos).Magnitude or math.huge)
                            end)
                        else
                            table.sort(enemies.normal, function(a,b) return a.hp > b.hp end)
                        end
                        for _, e in ipairs(enemies.normal) do
                            if not used[e.folder] then chosen = e; break end
                        end
                    end
                    if not chosen then break end
                    if useBountyOnEnemy(king, chosen.folder) then
                        used[chosen.folder] = true
                        targeted = targeted + 1
                    end
                    task.wait(1)
                end
                task.wait(targeted == 0 and 1 or 0.2)
            end
        end
        auto_bounty_running = false
    end)
end

if _G.AutoBounty then task.spawn(start_auto_bounty) end

function start_auto_mercenary()
    if auto_mercenary_running or not _G.AutoMercenary then return end
    auto_mercenary_running = true
    task.spawn(function()
        while _G.AutoMercenary do
            local tf = workspace:FindFirstChild("Towers")
            if tf then
                for _, t in ipairs(tf:GetDescendants()) do
                    if t:IsA("Folder") and t.Name == "TowerReplicator"
                        and t:GetAttribute("Name") == "Mercenary Base"
                        and t:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                        and (t:GetAttribute("Upgrade") or 0) >= 5 then
                        remote_func:InvokeServer("Troops", "Abilities", "Activate", {
                            Troop = t.Parent, Name = "Air-Drop",
                            Data = { pathName = 1, directionCFrame = CFrame.new(), dist = _G.MercDistance or 195 }
                        })
                        task.wait(0.5)
                    end
                end
            end
            task.wait(0.2)
        end
        auto_mercenary_running = false
    end)
end

task.spawn(function()
    while true do
        if _G.AutoPickups       and not auto_pickups_running        then start_auto_pickups()       end
        if _G.AutoSmartSkip     and not auto_smart_skip_running     then start_smart_auto_skip()    end
        if _G.AutoNecro         and not auto_necro_running          then start_auto_necro()         end
        if skip_is_active() and not auto_skip_running then start_auto_skip() end
        if _G.AutoChain         and not auto_chain_running          then start_auto_chain()         end
        if _G.AutoDJ            and not auto_dj_running             then start_auto_dj_booth()      end
        if _G.AntiLag           and not anti_lag_running            then start_anti_lag()           end
        if _G.AutoMercenary     and not auto_mercenary_running      then start_auto_mercenary()     end
        if _G.AutoUber          and not auto_uber_running           then start_auto_uber()          end
        if _G.AutoSupport       and not auto_support_running        then start_auto_support()       end
        task.wait(1)
    end
end)

if _G.ClaimRewards and not auto_claim_rewards then start_claim_rewards() end

function create_buttons()
    local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    if playerGui:FindFirstChild("AutoRejoinButton") then return end

    local TweenService = game:GetService("TweenService")

    local accent      = Color3.fromRGB(65, 150, 130)
    local accentLit   = Color3.fromRGB(100, 185, 160)
    local bgPanel     = Color3.fromRGB(28, 32, 38)
    local bgRow       = Color3.fromRGB(38, 43, 50)
    local bgRowHover  = Color3.fromRGB(46, 52, 60)
    local bgDark      = Color3.fromRGB(16, 18, 22)
    local textPrimary = Color3.fromRGB(235, 240, 245)
    local textMuted   = Color3.fromRGB(150, 160, 172)
    local danger      = Color3.fromRGB(210, 90, 90)

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoRejoinButton"
    screenGui.Parent = playerGui
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 220, 0, 0)
    main.AutomaticSize = Enum.AutomaticSize.Y
    main.Position = UDim2.new(0, 12, 0, 12)
    main.BackgroundColor3 = bgPanel
    main.BorderSizePixel = 0
    main.Parent = screenGui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

    local mainStroke = Instance.new("UIStroke", main)
    mainStroke.Color = accent
    mainStroke.Thickness = 1
    mainStroke.Transparency = 0.55

    local pad = Instance.new("UIPadding", main)
    pad.PaddingTop    = UDim.new(0, 10)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.PaddingLeft   = UDim.new(0, 10)
    pad.PaddingRight  = UDim.new(0, 10)

    local list = Instance.new("UIListLayout", main)
    list.FillDirection = Enum.FillDirection.Vertical
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 8)

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.LayoutOrder = 1
    header.Size = UDim2.new(1, 0, 0, 24)
    header.BackgroundTransparency = 1
    header.Parent = main

    local headerLayout = Instance.new("UIListLayout", header)
    headerLayout.FillDirection = Enum.FillDirection.Horizontal
    headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    headerLayout.Padding = UDim.new(0, 8)

    local dot = Instance.new("Frame")
    dot.Name = "Dot"
    dot.Size = UDim2.new(0, 8, 0, 8)
    dot.BackgroundColor3 = accentLit
    dot.BorderSizePixel = 0
    dot.Parent = header
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    local dotStroke = Instance.new("UIStroke", dot)
    dotStroke.Color = accentLit
    dotStroke.Thickness = 2
    dotStroke.Transparency = 0.65

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 1, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextColor3 = textPrimary
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "TDS  HELPER"
    title.Parent = header

    local rejoinRow = Instance.new("TextButton")
    rejoinRow.Name = "RejoinRow"
    rejoinRow.LayoutOrder = 2
    rejoinRow.Size = UDim2.new(1, 0, 0, 36)
    rejoinRow.BackgroundColor3 = bgRow
    rejoinRow.AutoButtonColor = false
    rejoinRow.Text = ""
    rejoinRow.Parent = main
    Instance.new("UICorner", rejoinRow).CornerRadius = UDim.new(0, 7)

    local rejoinLabel = Instance.new("TextLabel")
    rejoinLabel.Size = UDim2.new(1, -60, 1, 0)
    rejoinLabel.Position = UDim2.new(0, 12, 0, 0)
    rejoinLabel.BackgroundTransparency = 1
    rejoinLabel.Font = Enum.Font.GothamMedium
    rejoinLabel.TextSize = 12
    rejoinLabel.TextColor3 = textPrimary
    rejoinLabel.TextXAlignment = Enum.TextXAlignment.Left
    rejoinLabel.Text = "Auto Rejoin"
    rejoinLabel.Parent = rejoinRow

    local toggle = Instance.new("Frame")
    toggle.Name = "Toggle"
    toggle.Size = UDim2.new(0, 36, 0, 20)
    toggle.Position = UDim2.new(1, -48, 0.5, 0)
    toggle.AnchorPoint = Vector2.new(0, 0.5)
    toggle.BackgroundColor3 = bgDark
    toggle.BorderSizePixel = 0
    toggle.Parent = rejoinRow
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = UDim2.new(0, 2, 0.5, 0)
    knob.AnchorPoint = Vector2.new(0, 0.5)
    knob.BackgroundColor3 = textMuted
    knob.BorderSizePixel = 0
    knob.Parent = toggle
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local startMatchButton = Instance.new("TextButton")
    startMatchButton.Name = "StartMatchButton"
    startMatchButton.LayoutOrder = 3
    startMatchButton.Size = UDim2.new(1, 0, 0, 34)
    startMatchButton.BackgroundColor3 = accent
    startMatchButton.AutoButtonColor = false
    startMatchButton.Font = Enum.Font.GothamBold
    startMatchButton.TextSize = 12
    startMatchButton.TextColor3 = Color3.new(1, 1, 1)
    startMatchButton.Text = "START MATCH"
    startMatchButton.Parent = main
    Instance.new("UICorner", startMatchButton).CornerRadius = UDim.new(0, 7)

    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    header.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)

    local function updateRejoinVisuals()
        local on = _G.AutoRejoin
        TweenService:Create(toggle, TweenInfo.new(0.2), {
            BackgroundColor3 = on and accent or bgDark
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.2), {
            Position = on and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
            BackgroundColor3 = on and Color3.new(1, 1, 1) or textMuted
        }):Play()
        TweenService:Create(dot, TweenInfo.new(0.2), {
            BackgroundColor3 = on and accentLit or danger
        }):Play()
        TweenService:Create(dotStroke, TweenInfo.new(0.2), {
            Color = on and accentLit or danger
        }):Play()
        rejoinLabel.TextColor3 = on and textPrimary or textMuted
        mainStroke.Color = on and accent or Color3.fromRGB(70, 45, 45)
    end

    rejoinRow.MouseEnter:Connect(function()
        TweenService:Create(rejoinRow, TweenInfo.new(0.15), { BackgroundColor3 = bgRowHover }):Play()
    end)
    rejoinRow.MouseLeave:Connect(function()
        TweenService:Create(rejoinRow, TweenInfo.new(0.15), { BackgroundColor3 = bgRow }):Play()
    end)
    rejoinRow.MouseButton1Click:Connect(function()
        _G.AutoRejoin = not _G.AutoRejoin
        updateRejoinVisuals()
        save_auto_rejoin_state(_G.AutoRejoin, _G.AutoRejoinTimerStart)
    end)

    startMatchButton.MouseEnter:Connect(function()
        TweenService:Create(startMatchButton, TweenInfo.new(0.15), { BackgroundColor3 = accentLit }):Play()
    end)
    startMatchButton.MouseLeave:Connect(function()
        TweenService:Create(startMatchButton, TweenInfo.new(0.15), { BackgroundColor3 = accent }):Play()
    end)
    startMatchButton.MouseButton1Click:Connect(function()
        if TDS.ReplayCallback then TDS.ReplayCallback()
        else warn("No replay callback set. Use TDS.ReplayCallback = function() ... end") end
    end)

    local function updateVisibility()
        startMatchButton.Visible = playerGui:FindFirstChild("ReactLobbyHud") ~= nil
    end
    updateVisibility()
    playerGui.ChildAdded:Connect(function(c)
        if c.Name == "ReactLobbyHud" then updateVisibility() end
    end)
    playerGui.ChildRemoved:Connect(function(c)
        if c.Name == "ReactLobbyHud" then updateVisibility() end
    end)

    updateRejoinVisuals()

    task.spawn(function()
        for _ = 1, 15 do
            local tdsUI = playerGui:FindFirstChild("TDS_UI")
            if tdsUI and tdsUI:IsA("ScreenGui") and tdsUI.Enabled then
                _G.AutoRejoin = false
                updateRejoinVisuals()
                screenGui.Enabled = false
                break
            end
            task.wait(1)
        end
    end)
end

task.spawn(function()
    game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    create_buttons()
end)

return TDS
