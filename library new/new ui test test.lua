if not game:IsLoaded() then game.Loaded:Wait() end

local function save_auto_rejoin_state(state)
    pcall(function()
        if writefile then
            writefile("TDS_AutoRejoin.txt", tostring(state))
        end
    end)
end

local function load_auto_rejoin_state()
    local saved = nil
    pcall(function()
        if readfile then
            local content = readfile("TDS_AutoRejoin.txt")
            if content == "true" then
                saved = true
            elseif content == "false" then
                saved = false
            end
        end
    end)
    if saved == nil then saved = true end
    return saved
end

_G.AutoRejoin = load_auto_rejoin_state()

local function identify_game_state()
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

local send_request = request or http_request or httprequest or GetDevice and GetDevice().request

if not send_request then
    warn("failure: no http function")
    return
end

local teleport_service = game:GetService("TeleportService")
local marketplace_service = game:GetService("MarketplaceService")
local replicated_storage = game:GetService("ReplicatedStorage")
local remote_func = replicated_storage:WaitForChild("RemoteFunction")
local remote_event = replicated_storage:WaitForChild("RemoteEvent")
local players_service = game:GetService("Players")
local local_player = players_service.LocalPlayer or players_service.PlayerAdded:Wait()
local player_gui = local_player:WaitForChild("PlayerGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local localPlayer = Players.LocalPlayer

local back_to_lobby_running = false
local auto_pickups_running = false
local auto_skip_running = false
local anti_lag_running = false
local hasSentLobbyWebhook = false
local hasSentMatchStartWebhook = false
local auto_smart_skip_running = false
local auto_mercenary_running = false
local auto_uber_running = false

local ItemNames = {
    ["17447507910"] = "Timescale Ticket(s)",
    ["17438486690"] = "Range Flag(s)",
    ["17438486138"] = "Damage Flag(s)",
    ["17438487774"] = "Cooldown Flag(s)",
    ["17429537022"] = "Blizzard(s)",
    ["17448596749"] = "Napalm Strike(s)",
    ["18493073533"] = "Spin Ticket(s)",
    ["17429548305"] = "Supply Drop(s)",
    ["18443277308"] = "Low Grade Consumable Crate(s)",
    ["136180382135048"] = "Santa Radio(s)",
    ["18443277106"] = "Mid Grade Consumable Crate(s)",
    ["18443277591"] = "High Grade Consumable Crate(s)",
    ["132155797622156"] = "Christmas Tree(s)",
    ["124065875200929"] = "Fruit Cake(s)",
    ["17429541513"] = "Barricade(s)",
    ["110415073436604"] = "Holy Hand Grenade(s)",
    ["139414922355803"] = "Present Clusters(s)"
}

local TDS = {
    placed_towers = {},
    active_strat = true,
    matchmaking_map = {
        ["Hardcore"] = "Hardcore",
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

local upgrade_history = {}

shared.TDS_Table = TDS

local start_coins, current_total_coins, start_gems, current_total_gems = 0, 0, 0, 0
local current_level = 0

if game_state == "LOBBY" then
    pcall(function()
        local levelObject = local_player.PlayerGui.ReactLobbyBattlepass.Frame.scaled.battlepass.content.progress.level
        if levelObject:IsA("TextLabel") or levelObject:IsA("TextButton") or levelObject:IsA("TextBox") then
            current_level = tonumber(levelObject.Text) or 0
        else
            current_level = levelObject.Value or 0
        end
    end)
elseif game_state == "GAME" then
    pcall(function()
        repeat task.wait(1) until local_player:FindFirstChild("Coins")
        start_coins = local_player.Coins.Value
        current_total_coins = start_coins
        start_gems = local_player.Gems.Value
        current_total_gems = start_gems
    end)
end

local function check_res_ok(data)
    if data == true then return true end
    if type(data) == "table" and data.Success == true then return true end
    local success, is_model = pcall(function()
        return data and data:IsA("Model")
    end)
    if success and is_model then return true end
    if type(data) == "userdata" then return true end
    return false
end

local function get_all_rewards()
    local results = {
        Coins = 0,
        Gems = 0,
        XP = 0,
        Wave = 0,
        Level = 0,
        Time = "00:00",
        Status = "UNKNOWN",
        Others = {}
    }
    local ui_root = player_gui:FindFirstChild("ReactGameNewRewards")
    local main_frame = ui_root and ui_root:FindFirstChild("Frame")
    local game_over = main_frame and main_frame:FindFirstChild("gameOver")
    local rewards_screen = game_over and game_over:FindFirstChild("RewardsScreen")
    local game_stats = rewards_screen and rewards_screen:FindFirstChild("gameStats")
    local stats_list = game_stats and game_stats:FindFirstChild("stats")
    if stats_list then
        for _, frame in ipairs(stats_list:GetChildren()) do
            local l1 = frame:FindFirstChild("textLabel")
            local l2 = frame:FindFirstChild("textLabel2")
            if l1 and l2 and l1.Text:find("Time Completed:") then
                results.Time = l2.Text
                break
            end
        end
    end
    local top_banner = rewards_screen and rewards_screen:FindFirstChild("RewardBanner")
    if top_banner and top_banner:FindFirstChild("textLabel") then
        local txt = top_banner.textLabel.Text:upper()
        results.Status = txt:find("TRIUMPH") and "WIN" or (txt:find("LOST") and "LOSS" or "UNKNOWN")
    end
    local level_value = local_player.Level
    if level_value then
        results.Level = level_value.Value or 0
    end
    local label = player_gui:WaitForChild("ReactGameTopGameDisplay").Frame.wave.container.value
    local wave_num = label.Text:match("^(%d+)")
    if wave_num then
        results.Wave = tonumber(wave_num) or 0
    end
    local section_rewards = rewards_screen and rewards_screen:FindFirstChild("RewardsSection")
    if section_rewards then
        for _, item in ipairs(section_rewards:GetChildren()) do
            if tonumber(item.Name) then
                local icon_id = "0"
                local img = item:FindFirstChildWhichIsA("ImageLabel", true)
                if img then icon_id = img.Image:match("%d+") or "0" end
                for _, child in ipairs(item:GetDescendants()) do
                    if child:IsA("TextLabel") then
                        local text = child.Text
                        local amt = tonumber(text:match("(%d+)")) or 0
                        if text:find("Coins") then
                            results.Coins = amt
                        elseif text:find("Gems") then
                            results.Gems = amt
                        elseif text:find("XP") then
                            results.XP = amt
                        elseif text:lower():find("x%d+") then
                            local displayName = ItemNames[icon_id] or "Unknown Item (" .. icon_id .. ")"
                            table.insert(results.Others, {Amount = text:match("x%d+"), Name = displayName})
                        end
                    end
                end
            end
        end
    end
    return results
end

local function SmartTeleportToLobby()
    if not _G.AutoRejoin then return end
    local lobbyId = 3260590327
    local IsMobile = game:GetService("UserInputService").TouchEnabled
    Globals = Globals or {}
    local privateCode = Globals.PrivateCode or _G.PrivateCode
    pcall(function()
        if not IsMobile and privateCode and privateCode ~= "" then
            game:GetService("ExperienceService"):LaunchExperience({
                placeId = lobbyId,
                linkCode = privateCode
            })
        else
            teleport_service:Teleport(lobbyId)
        end
    end)
end

local function rejoin_match()
    if not _G.AutoRejoin then return end
    local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
    local success = false
    local res
    local IsMobile = game:GetService("UserInputService").TouchEnabled
    Globals = Globals or {}
    local privateCode = Globals.PrivateCode or _G.PrivateCode
    if privateCode and privateCode ~= "" and not IsMobile then
        SmartTeleportToLobby()
        task.wait(9e9)
        return
    end
    repeat
        local StateFolder = replicated_storage:FindFirstChild("State")
        local CurrentMode = StateFolder and StateFolder.Difficulty.Value
        if CurrentMode then
            local ok, result = pcall(function()
                local payload
                local EventMode = StateFolder:FindFirstChild("Mode") and StateFolder.Mode.Value
                if CurrentMode == "PizzaParty" then
                    payload = { mode = "halloween", count = 1 }
                elseif CurrentMode == "Hardcore" then
                    payload = { mode = "hardcore", count = 1 }
                elseif CurrentMode == "PollutedWasteland" then
                    payload = { mode = "polluted", count = 1 }
                elseif CurrentMode == "Badlands" then
                    payload = { mode = "badlands", count = 1 }
                elseif EventMode == "DuckEvent" then
                    payload = { difficulty = CurrentMode, mode = "ducky2025", count = 1 }
                elseif CurrentMode == "Trial" then
                    SmartTeleportToLobby()
                    return true
                else
                    payload = { difficulty = CurrentMode, mode = "survival", count = 1 }
                end
                return remote:InvokeServer("Multiplayer", "v2:start", payload)
            end)
            if ok and check_res_ok(result) then
                success = true
                res = result
            else
                task.wait(0.5)
            end
        else
            task.wait(1)
        end
    until success
    return res
end

local function handle_post_match()
    if not _G.AutoRejoin then return end
    local ui_root
    repeat
        task.wait(1)
        local root = player_gui:FindFirstChild("ReactGameNewRewards")
        local frame = root and root:FindFirstChild("Frame")
        local gameOver = frame and frame:FindFirstChild("gameOver")
        local rewards_screen = gameOver and gameOver:FindFirstChild("RewardsScreen")
        ui_root = rewards_screen and rewards_screen:FindFirstChild("RewardsSection")
    until ui_root
    if not ui_root then
        if _G.sent_to_lobby then send_to_lobby() else rejoin_match() end
        return
    end
    if not _G.SendWebhook then
        if _G.sent_to_lobby then send_to_lobby() else rejoin_match() end
        return
    end
    task.wait(1)
    local match = get_all_rewards()
    current_total_coins = current_total_coins + match.Coins
    current_total_gems = current_total_gems + match.Gems
    local bonus_string = ""
    if #match.Others > 0 then
        for _, res in ipairs(match.Others) do
            bonus_string = bonus_string .. "🎁 **" .. res.Amount .. " " .. res.Name .. "**\n"
        end
    else
        bonus_string = "_No bonus rewards found._"
    end
    local post_data = {
        username = "TDS AutoStrat",
        embeds = {{
            title = (match.Status == "WIN" and "🏆 TRIUMPH" or "💀 DEFEAT"),
            color = (match.Status == "WIN" and 0x2ecc71 or 0xe74c3c),
            description = "### 📋 Match Overview\n" .. "> **Status:** `" .. match.Status .. "`\n" .. "> **Time:** `" .. match.Time .. "`\n" .. "> **Current Level:** `" .. match.Level .. "`\n" .. "> **Wave:** `" .. match.Wave .. "`\n",
            fields = {
                { name = "✨ Rewards", value = "```ansi\n[2;33mCoins:[0m +" .. match.Coins .. "\n[2;34mGems: [0m +" .. match.Gems .. "\n[2;32mXP:   [0m +" .. match.XP .. "```", inline = false },
                { name = "🎁 Bonus Items", value = bonus_string, inline = true },
                { name = "📊 Session Totals", value = "```py\n# Total Amount\nCoins: " .. current_total_coins .. "\nGems:  " .. current_total_gems .. "```", inline = true }
            },
            footer = { text = "Logged for " .. local_player.Name .. " • TDS AutoStrat" },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }
    pcall(function()
        send_request({
            Url = _G.WebhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(post_data)
        })
    end)
    task.wait(1.5)
    send_to_lobby()
end

local function log_match_start()
    if hasSentMatchStartWebhook then return end
    if not _G.SendWebhook then return end
    if type(_G.Webhook) ~= "string" or _G.Webhook == "" then return end
    if _G.Webhook:find("YOUR%-WEBHOOK") then return end
    hasSentMatchStartWebhook = true
    local start_payload = {
        username = "TDS AutoStrat",
        embeds = {{
            title = "🚀 **Match Started**",
            description = "Game loaded successfully",
            color = 3447003,
            fields = {
                { name = " Starting Coins", value = "```" .. tostring(start_coins) .. " Coins```", inline = true },
                { name = "💎 Starting Gems", value = "```" .. tostring(start_gems) .. " Gems```", inline = true },
                { name = "Status", value = "🟢 Running Script", inline = false }
            },
            footer = { text = "Logged for " .. local_player.Name .. " • Tower Defense Simulator" },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }
    pcall(function()
        send_request({
            Url = _G.Webhook,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(start_payload)
        })
    end)
end

local function send_lobby_webhook()
    if hasSentLobbyWebhook then return end
    if not _G.SendWebhook then return end
    if type(_G.Webhook) ~= "string" or _G.Webhook == "" then return end
    if _G.Webhook:find("YOUR%-WEBHOOK") then return end
    hasSentLobbyWebhook = true
    local maxAttempts = 10
    local battlepassLevel = "0"
    for attempt = 1, maxAttempts do
        local success, result = pcall(function()
            local gui = local_player.PlayerGui:WaitForChild("ReactLobbyBattlepass", 2)
            local frame = gui:WaitForChild("Frame", 1)
            local scaled = frame:WaitForChild("scaled", 1)
            local battlepass = scaled:WaitForChild("battlepass", 1)
            local content = battlepass:WaitForChild("content", 1)
            local progress = content:WaitForChild("progress", 1)
            local levelObj = progress:WaitForChild("level", 1)
            if levelObj:IsA("TextLabel") or levelObj:IsA("TextButton") or levelObj:IsA("TextBox") then
                return levelObj.Text
            else
                return tostring(levelObj.Value)
            end
        end)
        if success and result and result ~= "" and result ~= "0" then
            battlepassLevel = result
            break
        end
        task.wait(1)
    end
    local lobby_payload = {
        username = "TDS AutoStrat",
        embeds = {{
            title = "📋 **Inside Lobby**",
            description = "Script loaded successfully.",
            color = 16776960,
            fields = {
                { name = "📊 Battlepass Level", value = "```Level " .. battlepassLevel .. "```", inline = false },
                { name = "🎮 Game Status", value = "🟡 **In Lobby** - Ready to start match", inline = false }
            },
            footer = { text = "Player: " .. local_player.Name },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }
    pcall(function()
        send_request({
            Url = _G.Webhook,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(lobby_payload)
        })
    end)
end

if game_state == "LOBBY" then
    send_lobby_webhook()
elseif game_state == "GAME" then
    log_match_start()
end

local function run_vote_skip()
    while true do
        local success = pcall(function()
            remote_func:InvokeServer("Voting", "Skip")
        end)
        if success then break end
        task.wait(0.2)
    end
end

local function match_ready_up()
    local player_gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    local ui_overrides = player_gui:WaitForChild("ReactOverridesVote", 30)
    local main_frame = ui_overrides and ui_overrides:WaitForChild("Frame", 30)
    if not main_frame then return end
    local vote_ready = nil
    while not vote_ready do
        local vote_node = main_frame:FindFirstChild("votes")
        if vote_node then
            local container = vote_node:FindFirstChild("container")
            if container then
                local ready = container:FindFirstChild("ready")
                if ready then vote_ready = ready end
            end
        end
        if not vote_ready then task.wait(0.5) end
    end
    repeat task.wait(0.5) until vote_ready.Visible == true
    run_vote_skip()
    log_match_start()
    if TDS.pending_strategy then
        task.spawn(TDS.pending_strategy)
        TDS.pending_strategy = nil
    end
end

local function cast_map_vote(map_id, pos_vec)
    local target_map = map_id or "Simplicity"
    local target_pos = pos_vec or Vector3.new(0,0,0)
    remote_event:FireServer("LobbyVoting", "Vote", target_map, target_pos)
end

local function lobby_ready_up()
    pcall(function()
        remote_event:FireServer("LobbyVoting", "Ready")
    end)
end

function TDS:TeleportToLobby()
    send_to_lobby()
end

local function select_map_override(map_id, ...)
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

local function cast_modifier_vote(mods_table)
    local bulk_modifiers = replicated_storage:WaitForChild("Network"):WaitForChild("Modifiers"):WaitForChild("RF:BulkVoteModifiers")
    local selected_mods = mods_table or {
        HiddenEnemies = true, Glass = true, ExplodingEnemies = true,
        Limitation = true, Committed = true, HealthyEnemies = true,
        SpeedyEnemies = true, Quarantine = true, Fog = true,
        FlyingEnemies = true, Broke = true, Jailed = true, Inflation = true
    }
    pcall(function()
        bulk_modifiers:InvokeServer(selected_mods)
    end)
end

local function is_map_available(name)
    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local t = g:FindFirstChild("Title")
            if t and t.Text == name then
                return true
            end
        end
    end
    return false
end

local function veto_and_wait_for_maps()
    local total_players = #players_service:GetPlayers()
    remote_event:FireServer("LobbyVoting", "Veto")
    local veto_ui = player_gui:FindFirstChild("ReactGameIntermission")
    if not veto_ui then return false end
    local frame = veto_ui:FindFirstChild("Frame")
    if not frame then return false end
    local buttons = frame:FindFirstChild("buttons")
    if not buttons then return false end
    local veto_button = buttons:FindFirstChild("veto")
    if not veto_button then return false end
    local veto_value = veto_button:FindFirstChild("value")
    if not veto_value then return false end
    local max_wait_time = 10
    local start_time = os.time()
    while os.time() - start_time < max_wait_time do
        if veto_value.Text == "Veto ("..total_players.."/"..total_players..")" then
            break
        end
        task.wait(1)
    end
    task.wait(1)
    return true
end

local function get_available_maps()
    local maps = {}
    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local title = g:FindFirstChild("Title")
            if title and title.Text ~= "" then
                table.insert(maps, title.Text)
            end
        end
    end
    return maps
end

function TDS:RegisterStrategy(mapName, strategyFunction)
    self.strategies[mapName] = strategyFunction
end

function TDS:RegisterStrategies(strategyTable)
    for mapName, strategyFunc in pairs(strategyTable) do
        self:RegisterStrategy(mapName, strategyFunc)
    end
end

function TDS:GetAvailableMaps()
    return get_available_maps()
end

function TDS:VetoMaps()
    return veto_and_wait_for_maps()
end

function TDS:IsMapAvailable(mapName)
    return is_map_available(mapName)
end

function TDS:SelectMapWithPriority(mapPriorityList, maxAttempts)
    maxAttempts = maxAttempts or 2
    repeat task.wait() until game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("ReactGameIntermission")
    task.wait(1)
    local selectedMap = nil
    for attempt = 1, maxAttempts do
        local availableMaps = self:GetAvailableMaps()
        for _, preferredMap in ipairs(mapPriorityList) do
            for _, availableMap in ipairs(availableMaps) do
                if availableMap == preferredMap then
                    selectedMap = preferredMap
                    break
                end
            end
            if selectedMap then break end
        end
        if selectedMap then break end
        if attempt == 1 then
            self:VetoMaps()
            task.wait(1)
        end
    end
    if not selectedMap then
        task.wait(1)
        game:GetService("TeleportService"):Teleport(3260590327)
        return nil
    end
    return selectedMap
end

function TDS:RunStrategy(config)
    if not config.mode then
        error("TDS:RunStrategy - mode is required")
    end
    if not config.mapPriority then
        error("TDS:RunStrategy - mapPriority is required")
    end
    self:Mode(config.mode)
    local selectedMap = self:SelectMapWithPriority(config.mapPriority, config.maxAttempts)
    if not selectedMap then return false end
    local strategy = nil
    if config.strategies then
        strategy = config.strategies[selectedMap]
    end
    if not strategy and config.defaultStrategy then
        strategy = config.defaultStrategy
    end
    if strategy then
        self.pending_strategy = strategy
    end
    self:GameInfo(selectedMap, config.modifiers or {})
    return true
end

function TDS:GameInfo(mapName, modifiers)
    if not _G.AutoRejoin then
        warn("TDS:GameInfo blocked because Auto Rejoin is disabled")
        return false
    end
    modifiers = modifiers or {}
    if game_state ~= "GAME" then
        warn("Not in game state for GameInfo")
        return false
    end
    local vote_gui = player_gui:WaitForChild("ReactGameIntermission", 30)
    if not (vote_gui and vote_gui.Enabled) then
        warn("Vote GUI not found or not enabled")
        teleport_service:Teleport(3260590327, local_player)
        return false
    end
    local frame = vote_gui:WaitForChild("Frame", 5)
    if not frame then
        warn("Vote GUI Frame not found")
        teleport_service:Teleport(3260590327, local_player)
        return false
    end
    cast_modifier_vote(modifiers)
    task.wait(0.5)
    if marketplace_service:UserOwnsGamePassAsync(local_player.UserId, 10518590) then
        select_map_override(mapName, "vip")
        return true
    end
    if is_map_available(mapName) then
        select_map_override(mapName)
        return true
    end
    warn("Map '" .. tostring(mapName) .. "' not available, teleporting to lobby")
    task.wait(1)
    local success, errorMsg = pcall(function()
        teleport_service:Teleport(3260590327, local_player)
    end)
    if not success then
        warn("Teleport failed: " .. tostring(errorMsg))
    end
    return false
end

local function set_game_timescale(target_val)
    local speed_list = {0, 0.5, 1, 1.5, 2}
    local target_idx
    for i, v in ipairs(speed_list) do
        if v == target_val then
            target_idx = i
            break
        end
    end
    if not target_idx then return end
    local speed_label = game.Players.LocalPlayer.PlayerGui.ReactUniversalHotbar.Frame.timescale.Speed
    local current_val = tonumber(speed_label.Text:match("x([%d%.]+)"))
    if not current_val then return end
    local current_idx
    for i, v in ipairs(speed_list) do
        if v == current_val then
            current_idx = i
            break
        end
    end
    if not current_idx then return end
    local diff = target_idx - current_idx
    if diff < 0 then
        diff = #speed_list + diff
    end
    for _ = 1, diff do
        replicated_storage.RemoteFunction:InvokeServer("TicketsManager", "CycleTimeScale")
        task.wait(0.5)
    end
end

local function unlock_speed_tickets()
    if local_player.TimescaleTickets.Value >= 1 then
        if game.Players.LocalPlayer.PlayerGui.ReactUniversalHotbar.Frame.timescale.Lock.Visible then
            replicated_storage.RemoteFunction:InvokeServer('TicketsManager', 'UnlockTimeScale')
        end
    else
        warn("no tickets left")
    end
end

local function isTowerStunned(tower)
    if not tower then return false end
    local towerReplicator = tower:FindFirstChild("TowerReplicator")
    if not towerReplicator then return false end
    return towerReplicator:GetAttribute("IsStunned") == true
end

local function waitUntilUnstunned(tower)
    while isTowerStunned(tower) do
        task.wait(0.05)
    end
end

local function trigger_restart()
    local ui_root = player_gui:WaitForChild("ReactGameNewRewards")
    local found_section = false
    repeat
        task.wait(0.3)
        local f = ui_root:FindFirstChild("Frame")
        local g = f and f:FindFirstChild("gameOver")
        local s = g and g:FindFirstChild("RewardsScreen")
        if s and s:FindFirstChild("RewardsSection") then
            found_section = true
        end
    until found_section
    task.wait(2)
    run_vote_skip()
end

local function get_current_wave()
    local label
    repeat
        task.wait(0.5)
        label = player_gui:FindFirstChild("ReactGameTopGameDisplay", true)
            and player_gui.ReactGameTopGameDisplay.Frame.wave.container:FindFirstChild("value")
    until label ~= nil
    local text = label.Text
    local wave_num = text:match("(%d+)")
    return tonumber(wave_num) or 0
end

local function do_place_tower(t_name, t_pos)
    while true do
        local random_x_offset = (math.random(-99, 99)) / 1000000
        local random_z_offset = (math.random(-99, 99)) / 1000000
        local new_x = t_pos.X + random_x_offset
        local new_z = t_pos.Z + random_z_offset
        local final_y = t_pos.Y
        for _, child in ipairs(workspace.Towers:GetChildren()) do
            local tower_pos = child:GetPivot().Position
            if math.abs(tower_pos.X - new_x) < 1 and math.abs(tower_pos.Z - new_z) < 1 then
                final_y = t_pos.Y
                break
            end
        end
        local randomized_pos = Vector3.new(new_x, final_y, new_z)
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Place", {
                Rotation = CFrame.new(),
                Position = randomized_pos
            }, t_name)
        end)
        if ok and check_res_ok(res) then
            return true
        end
        task.wait(0.25)
    end
end

local function do_upgrade_tower(t_obj, path_id)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Upgrade", "Set", {
                Troop = t_obj,
                Path = path_id
            })
        end)
        if ok and check_res_ok(res) then return true end
        task.wait(0.25)
    end
end

local function do_sell_tower(t_obj)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Sell", { Troop = t_obj })
        end)
        if ok and check_res_ok(res) then return true end
        task.wait(0.15)
    end
end

local function do_set_option(t_obj, opt_name, opt_val, req_wave)
    if req_wave then
        repeat task.wait(0.3) until get_current_wave() >= req_wave
    end
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Option", "Set", {
                Troop = t_obj,
                Name = opt_name,
                Value = opt_val
            })
        end)
        if ok and check_res_ok(res) then return true end
        task.wait(0.25)
    end
end

local function do_activate_ability(t_obj, ab_name, ab_data, is_looping)
    if type(ab_data) == "boolean" then
        is_looping = ab_data
        ab_data = nil
    end
    ab_data = type(ab_data) == "table" and ab_data or nil
    local positions
    if ab_data and type(ab_data.towerPosition) == "table" then
        positions = ab_data.towerPosition
    end
    local clone_list = {}
    if ab_data and ab_data.cloneTowerList and type(ab_data.cloneTowerList) == "table" then
        clone_list = ab_data.cloneTowerList
    elseif ab_data and ab_data.towerToClone then
        clone_list = { ab_data.towerToClone }
    end
    local target_idx = ab_data and ab_data.towerTarget
    local attempts_per_id = ab_data and ab_data.attemptsPerId or 3
    local current_index = 1
    local attempt_counter = 0
    local list_len = #clone_list
    local function attempt_ability(clone_id)
        local tower_to_clone = TDS.placed_towers[clone_id]
        if not tower_to_clone then
            return false
        end
        local data = ab_data and table.clone(ab_data) or nil
        if data then
            if positions and #positions > 0 then
                data.towerPosition = positions[math.random(#positions)]
            end
            data.towerToClone = tower_to_clone
            if type(target_idx) == "number" then
                data.towerTarget = TDS.placed_towers[target_idx]
            end
        end
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Abilities", "Activate", {
                Troop = t_obj,
                Name = ab_name,
                Data = data
            })
        end)
        if not ok then
            warn("Ability invoke failed:", res)
            return false
        end
        return check_res_ok(res)
    end
    local function run_cycle()
        if list_len == 0 then
            attempt_ability(nil)
            return
        end
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
            while active do
                run_cycle()
                task.wait(1)
            end
        end)
        return function() active = false end
    else
        run_cycle()
    end
    return nil
end

function TDS:Mode(difficulty)
    if not _G.AutoRejoin then
        warn("TDS:Mode blocked because Auto Rejoin is disabled")
        return false
    end
    if game_state ~= "LOBBY" then
        return false
    end
    if difficulty == "Trial" then
        local Elevators = workspace:WaitForChild("Elevators")
        local Network = replicated_storage:WaitForChild("Network")
        if Elevators and Network then
            local targetElevator = nil
            repeat
                for _, v in pairs(Elevators:GetChildren()) do
                    if v.Name:match("Trial") or v.Name:match("Event") then
                        targetElevator = v
                        break
                    end
                end
                if not targetElevator then task.wait(0.5) end
            until targetElevator
            task.spawn(function()
                local ElevatorsNet = Network:WaitForChild("Elevators")
                local EnterRemote = ElevatorsNet:WaitForChild("RF:Enter")
                local SetSizeRemote = ElevatorsNet:WaitForChild("RF:SetSize")
                local SetReadyRemote = ElevatorsNet:WaitForChild("RF:SetReady")
                pcall(function() EnterRemote:InvokeServer(targetElevator) end)
                pcall(function() SetSizeRemote:InvokeServer(1) end)
                pcall(function() SetReadyRemote:InvokeServer(true) end)
            end)
            return true
        end
    end
    local LobbyHud = player_gui:WaitForChild("ReactLobbyHud", 30)
    local frame = LobbyHud and LobbyHud:WaitForChild("Frame", 30)
    local MatchMaking = frame and frame:WaitForChild("matchmaking", 30)
    if MatchMaking then
        local remote = replicated_storage:WaitForChild("RemoteFunction")
        local success = false
        local res
        repeat
            local ok, result = pcall(function()
                local mode = TDS.matchmaking_map[difficulty]
                local payload
                if mode then
                    payload = { mode = mode, count = 1 }
                elseif difficulty == "Easy" or difficulty == "Hard" then
                    payload = { difficulty = difficulty, mode = "ducky2025", count = 1 }
                else
                    payload = { difficulty = difficulty, mode = "survival", count = 1 }
                end
                return remote:InvokeServer("Multiplayer", "v2:start", payload)
            end)
            if ok and check_res_ok(result) then
                success = true
                res = result
            else
                task.wait(0.5)
            end
        until success
    end
    return true
end

function TDS:Loadout(...)
    local raw_args = {...}
    local desiredTowers = {}
    if #raw_args == 1 and type(raw_args[1]) == "table" then
        desiredTowers = raw_args[1]
    else
        desiredTowers = raw_args
    end
    if #desiredTowers == 0 then
        return false, "no towers provided"
    end
    local replicated = game:GetService("ReplicatedStorage")
    local httpService = game:GetService("HttpService")
    local player = game:GetService("Players").LocalPlayer
    local remote = replicated:FindFirstChild("RemoteFunction")
    if not remote then
        return false, "RemoteFunction not found"
    end
    local currentlyEquipped = {}
    local StateReplicators = replicated:FindFirstChild("StateReplicators")
    if StateReplicators then
        for _, folder in ipairs(StateReplicators:GetChildren()) do
            if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == player.UserId then
                local equippedAttr = folder:GetAttribute("EquippedTowers")
                if type(equippedAttr) == "string" then
                    local cleanedJson = equippedAttr:match("%[.*%]")
                    local success, decoded = pcall(function()
                        return httpService:JSONDecode(cleanedJson)
                    end)
                    if success and type(decoded) == "table" then
                        currentlyEquipped = decoded
                    end
                end
                break
            end
        end
    end
    local desiredLookup = {}
    for _, towerName in ipairs(desiredTowers) do
        if towerName and towerName ~= "" then
            desiredLookup[towerName] = true
        end
    end
    for _, currentTower in ipairs(currentlyEquipped) do
        if currentTower ~= "None" and not desiredLookup[currentTower] then
            local unequipSuccess = false
            repeat
                local ok = pcall(function()
                    remote:InvokeServer("Inventory", "Unequip", "tower", currentTower)
                end)
                if ok then
                    unequipSuccess = true
                else
                    task.wait(0.2)
                end
            until unequipSuccess
            task.wait(0.3)
        end
    end
    task.wait(0.5)
    for _, towerName in ipairs(desiredTowers) do
        if towerName and towerName ~= "" then
            local alreadyEquipped = false
            for _, equippedTower in ipairs(currentlyEquipped) do
                if equippedTower == towerName then
                    alreadyEquipped = true
                    break
                end
            end
            if not alreadyEquipped then
                local equipSuccess = false
                repeat
                    local ok = pcall(function()
                        remote:InvokeServer("Inventory", "Equip", "tower", towerName)
                    end)
                    if ok then
                        equipSuccess = true
                    else
                        task.wait(0.2)
                    end
                until equipSuccess
                task.wait(0.3)
            end
        end
    end
    task.wait(0.5)
    return true
end

function TDS:VoteSkip(start_wave, end_wave)
    task.spawn(function()
        local current_wave = get_current_wave()
        self.LastVoteSkipTarget = self.LastVoteSkipTarget or 0
        if not start_wave then
            if self.LastVoteSkipTarget < current_wave then
                self.LastVoteSkipTarget = current_wave
            else
                self.LastVoteSkipTarget = self.LastVoteSkipTarget + 1
            end
            start_wave = self.LastVoteSkipTarget
            end_wave = start_wave
        else
            end_wave = end_wave or start_wave
            self.LastVoteSkipTarget = end_wave
        end
        for wave = start_wave, end_wave do
            while get_current_wave() < wave do
                task.wait(0.5)
            end
            local target_next_wave = wave + 1
            while get_current_wave() < target_next_wave do
                local vote_ui = player_gui:FindFirstChild("ReactOverridesVote")
                local vote_button = vote_ui
                    and vote_ui:FindFirstChild("Frame")
                    and vote_ui.Frame:FindFirstChild("votes")
                    and vote_ui.Frame.votes:FindFirstChild("vote", true)
                if vote_button and vote_button.Position == UDim2.new(0.5, 0, 0.5, 0) then
                    pcall(function()
                        RemoteFunc:InvokeServer("Voting", "Skip")
                    end)
                end
                task.wait(0.1)
            end
        end
    end)
end

function TDS:UnlockTimeScale()
    unlock_speed_tickets()
end

function TDS:TimeScale(val)
    set_game_timescale(val)
end

function TDS:StartGame()
    lobby_ready_up()
end

function TDS:Ready()
    if game_state ~= "GAME" then
        return false
    end
    match_ready_up()
end

function TDS:GetWave()
    return get_current_wave()
end

function TDS:RestartGame()
    trigger_restart()
end

function TDS:Place(t_name, px, py, pz, ...)
    local args = {...}
    local stack = false
    if args[#args] == "stack" or args[#args] == true then
        py = 95
    end
    if game_state ~= "GAME" then
        return false
    end
    local final_y = py
    local above_existing = false
    for _, child in ipairs(workspace.Towers:GetChildren()) do
        local tower_pos = child:GetPivot().Position
        if math.abs(tower_pos.X - px) < 0.5 and math.abs(tower_pos.Z - pz) < 0.5 then
            above_existing = true
            break
        end
    end
    if above_existing then
        final_y = py + 25
    end
    local existing = {}
    for _, child in ipairs(workspace.Towers:GetChildren()) do
        for _, sub_child in ipairs(child:GetChildren()) do
            if sub_child.Name == "Owner" and sub_child.Value == local_player.UserId then
                existing[child] = true
                break
            end
        end
    end
    do_place_tower(t_name, Vector3.new(px, final_y, pz))
    local new_t
    repeat
        for _, child in ipairs(workspace.Towers:GetChildren()) do
            if not existing[child] then
                for _, sub_child in ipairs(child:GetChildren()) do
                    if sub_child.Name == "Owner" and sub_child.Value == local_player.UserId then
                        new_t = child
                        break
                    end
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

function TDS:SetTarget(idx, target_type, req_wave)
    if req_wave then
        repeat task.wait(0.2) until get_current_wave() >= req_wave
    end
    local t = self.placed_towers[idx]
    if not t then return end
    pcall(function()
        remote_func:InvokeServer("Troops", "Target", "Set", {
            Troop = t,
            Target = target_type
        })
    end)
end

function TDS:Sell(idx, req_wave)
    if req_wave then
        repeat task.wait(0.1) until get_current_wave() >= req_wave
    end
    local t = self.placed_towers[idx]
    if t and do_sell_tower(t) then
        return true
    end
    return false
end

function TDS:SellAll(req_wave)
    task.spawn(function()
        if req_wave then
            repeat task.wait(0.1) until get_current_wave() >= req_wave
        end
        local towers_copy = {unpack(self.placed_towers)}
        for idx, t in ipairs(towers_copy) do
            if do_sell_tower(t) then
                for i, orig_t in ipairs(self.placed_towers) do
                    if orig_t == t then
                        table.remove(self.placed_towers, i)
                        break
                    end
                end
            end
        end
        return true
    end)
end

function TDS:Ability(idx, name, data, loop)
    local t = self.placed_towers[idx]
    if not t then return false end
    return do_activate_ability(t, name, data, loop)
end

function TDS:AutoChain(...)
    local tower_indices = {...}
    if #tower_indices == 0 then return end
    local running = true
    task.spawn(function()
        local i = 1
        while running do
            local idx = tower_indices[i]
            local tower = TDS.placed_towers[idx]
            if tower then
                waitUntilUnstunned(tower)
                do_activate_ability(tower, "Call Of Arms")
            end
            local hotbar = player_gui.ReactUniversalHotbar.Frame
            local timescale = hotbar:FindFirstChild("timescale")
            if timescale then
                if timescale:FindFirstChild("Lock") then
                    task.wait(10.5)
                else
                    task.wait(5.5)
                end
            else
                task.wait(10.5)
            end
            i = i + 1
            if i > #tower_indices then
                i = 1
            end
        end
    end)
    return function()
        running = false
    end
end

function TDS:SetOption(idx, name, val, req_wave)
    local t = self.placed_towers[idx]
    if t then
        return do_set_option(t, name, val, req_wave)
    end
    return false
end

local function is_void_charm(obj)
    return math.abs(obj.Position.Y) > 999999
end

local function get_root()
    local char = local_player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function start_auto_pickups()
    if auto_pickups_running or not _G.AutoPickups then return end
    auto_pickups_running = true
    task.spawn(function()
        while _G.AutoPickups do
            local folder = workspace:FindFirstChild("Pickups")
            local hrp = get_root()
            if folder and hrp then
                for _, item in ipairs(folder:GetChildren()) do
                    if not _G.AutoPickups then break end
                    if item:IsA("MeshPart") and (item.Name == "Bunz" or item.Name == "Lorebook") then
                        if not is_void_charm(item) then
                            local old_pos = hrp.CFrame
                            hrp.CFrame = item.CFrame * CFrame.new(0, 3, 0)
                            task.wait(0.2)
                            hrp.CFrame = old_pos
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

local function start_auto_skip()
    if auto_skip_running or not _G.AutoSkip then return end
    auto_skip_running = true
    task.spawn(function()
        while _G.AutoSkip do
            local skip_visible = player_gui:FindFirstChild("ReactOverridesVote") and player_gui.ReactOverridesVote:FindFirstChild("Frame") and player_gui.ReactOverridesVote.Frame:FindFirstChild("votes") and player_gui.ReactOverridesVote.Frame.votes:FindFirstChild("vote")
            if skip_visible and skip_visible.Position == UDim2.new(0.5, 0, 0.5, 0) then
                run_vote_skip()
            end
            task.wait(0.05)
        end
        auto_skip_running = false
    end)
end

function TDS:AutoSkip(state)
    _G.AutoSkip = state == true or state == "T" or state == "t"
    start_auto_skip()
end

local function start_claim_rewards()
    if auto_claim_rewards or not _G.ClaimRewards or game_state ~= "LOBBY" then
        return
    end
    auto_claim_rewards = true
    local player = game:GetService("Players").LocalPlayer
    local network = game:GetService("ReplicatedStorage"):WaitForChild("Network")
    local spin_tickets = player:WaitForChild("SpinTickets", 15)
    if spin_tickets and spin_tickets.Value > 0 then
        local ticket_count = spin_tickets.Value
        local daily_spin = network:WaitForChild("DailySpin", 5)
        local redeem_remote = daily_spin and daily_spin:WaitForChild("RF:RedeemSpin", 5)
        if redeem_remote then
            for i = 1, ticket_count do
                redeem_remote:InvokeServer()
                task.wait(0.5)
            end
        end
    end
    for i = 1, 6 do
        local args = { i }
        network:WaitForChild("PlaytimeRewards"):WaitForChild("RF:ClaimReward"):InvokeServer(unpack(args))
        task.wait(0.5)
    end
    auto_claim_rewards = false
end

local function start_back_to_lobby()
    if back_to_lobby_running then return end
    back_to_lobby_running = true
    task.spawn(function()
        while true do
            pcall(function()
                handle_post_match()
            end)
            task.wait(5)
        end
        back_to_lobby_running = false
    end)
end

local function start_anti_lag()
    if anti_lag_running then return end
    anti_lag_running = true
    local settings = settings().Rendering
    local original_quality = settings.QualityLevel
    settings.QualityLevel = Enum.QualityLevel.Level01
    task.spawn(function()
        while _G.AntiLag do
            local towers_folder = workspace:FindFirstChild("Towers")
            local client_units = workspace:FindFirstChild("ClientUnits")
            if towers_folder then
                for _, tower in ipairs(towers_folder:GetChildren()) do
                    local anims = tower:FindFirstChild("Animations")
                    local weapon = tower:FindFirstChild("Weapon")
                    local projectiles = tower:FindFirstChild("Projectiles")
                    if anims then anims:Destroy() end
                    if projectiles then projectiles:Destroy() end
                    if weapon then weapon:Destroy() end
                end
            end
            if client_units then
                for _, unit in ipairs(client_units:GetChildren()) do
                    unit:Destroy()
                end
            end
            task.wait(0.5)
        end
        anti_lag_running = false
    end)
end

local player = game.Players.LocalPlayer

local function Jump()
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    if humanoid and humanoid.Health > 0 then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

local function RandomJumpLoop()
    while true do
        local waitTime = math.random(300, 600)
        task.wait(waitTime)
        local character = player.Character
        local humanoid = character and character:FindFirstChild("Humanoid")
        if humanoid and humanoid.Health > 0 then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end

task.spawn(RandomJumpLoop)

local function start_rejoin_on_disconnect()
    task.spawn(function()
        game.Players.PlayerRemoving:connect(function (plr)
            if plr == game.Players.LocalPlayer then
                game:GetService('TeleportService'):Teleport(3260590327, plr)
            end
        end)
    end)
end

local function start_auto_dj_booth()
    if auto_dj_running or not _G.AutoDJ then return end
    auto_dj_running = true

    task.spawn(function()
        while _G.AutoDJ do
            local towers_folder = workspace:FindFirstChild("Towers")

            if towers_folder then
                for _, towers in ipairs(towers_folder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "DJ Booth"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 3 then
                        DJ = towers.Parent
                    end
                end
            end

            if DJ then
                remote_func:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { Troop = DJ, Name = "Drop The Beat", Data = {} }
                )
            end

            task.wait(1)
        end

        auto_dj_running = false
    end)
end

local function start_auto_uber()
    if auto_uber_running or not _G.AutoUber then return end
    auto_uber_running = true
    task.spawn(function()
        while _G.AutoUber do
            local towers_folder = workspace:FindFirstChild("Towers")
            if towers_folder then
                for _, towers in ipairs(towers_folder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Medic"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 3 then
                        local medic = towers.Parent
                        remote_func:InvokeServer("Troops", "Abilities", "Activate", { Troop = medic, Name = "Ubercharge", Data = {} })
                        task.wait(0.5)
                    end
                end
            end
            task.wait(0.2)
        end
        auto_uber_running = false
    end)
end

local function start_auto_chain()
    if auto_chain_running or not _G.AutoChain then return end
    auto_chain_running = true

    task.spawn(function()
        local idx = 1

        while _G.AutoChain do
            local commander = {}
            local towers_folder = workspace:FindFirstChild("Towers")

            if towers_folder then
                for _, towers in ipairs(towers_folder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Commander"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 2 then
                        commander[#commander + 1] = towers.Parent
                    end
                end
            end

            if #commander >= 3 then
                if idx > #commander then idx = 1 end

                local current_commander = commander[idx]
                local replicator = current_commander:FindFirstChild("TowerReplicator")
                local upgrade_level = replicator and replicator:GetAttribute("Upgrade") or 0

                if upgrade_level >= 4 and _G.SupportCaravan then
                    remote_func:InvokeServer(
                        "Troops",
                        "Abilities",
                        "Activate",
                        { Troop = current_commander, Name = "Support Caravan", Data = {} }
                    )
                    task.wait(0.1)
                end

                local response = remote_func:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { Troop = current_commander, Name = "Call Of Arms", Data = {} }
                )

                if response then
                    idx = idx + 1

                    local hotbar = player_gui.ReactUniversalHotbar.Frame
                    local timescale = hotbar and hotbar:FindFirstChild("timescale")

                    if timescale and timescale.Visible then
                        if timescale:FindFirstChild("Lock") then
                            task.wait(10.3)
                        else
                            task.wait(5.25)
                        end
                    else
                        task.wait(10.3)
                    end
                else
                    task.wait(0.5)
                end
            else
                task.wait(1)
            end
        end

        auto_chain_running = false
    end)
end

local function start_auto_support()
    if auto_support_running or not _G.AutoSupport then return end
    auto_support_running = true

    task.spawn(function()
        while _G.AutoSupport do
            local towers_folder = workspace:FindFirstChild("Towers")

            if towers_folder then
                for _, towers in ipairs(towers_folder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Commander"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 4 then
                        local commander = towers.Parent
                        remote_func:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            { Troop = commander, Name = "Support Caravan", Data = {} }
                        )
                        task.wait(0.5)
                    end
                end
            end

            task.wait(0.2)
        end

        auto_support_running = false
    end)
end

local NECRO_DELAY = 1.5
local necroTimers = {}
local auto_necro_running = false
local remoteFunc = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteFunction")

local function start_auto_necro()
    if auto_necro_running or not _G.AutoNecro then return end
    auto_necro_running = true
    task.spawn(function()
        while _G.AutoNecro do
            local currentTime = tick()
            local towers = workspace:FindFirstChild("Towers")
            if towers then
                for _, tower in pairs(towers:GetChildren()) do
                    local rep = tower:FindFirstChild("TowerReplicator")
                    if not rep then continue end
                    if rep:GetAttribute("Name") == "Necromancer" and rep:GetAttribute("OwnerId") == localPlayer.UserId then
                        local currentAmmo = rep:GetAttribute("Ammo") or 0
                        local maxAmmo = rep:GetAttribute("MaxAmmo") or 1
                        if currentAmmo == maxAmmo then
                            if not necroTimers[tower] then
                                necroTimers[tower] = currentTime
                            else
                                if currentTime - necroTimers[tower] >= NECRO_DELAY then
                                    if remoteFunc then
                                        remoteFunc:InvokeServer("Troops", "Abilities", "Activate", { Troop = tower, Name = "Raise The Dead", Data = {} })
                                    end
                                    necroTimers[tower] = nil
                                end
                            end
                        else
                            necroTimers[tower] = nil
                        end
                    end
                end
            end
            task.wait()
        end
        auto_necro_running = false
        necroTimers = {}
    end)
end

local function start_smart_auto_skip()
    if auto_smart_skip_running or not _G.AutoSmartSkip then return end
    auto_smart_skip_running = true
    local HEALTH_THRESHOLDS = { [1] = 10, [6] = 50, [16] = 150, [26] = 500, [36] = 2500 }
    local current_wave_tracking = {wave = 0, wave_start_time = 0, skip_active = false}
    local function get_current_wave()
        local success, result = pcall(function()
            local value = player_gui.ReactGameTopGameDisplay.Frame.wave.container.value
            return tonumber(value.Text:match("^(%d+)")) or 0
        end)
        return success and result or 0
    end
    local function get_total_enemy_health()
        local total_health = 0
        local state_replicators = replicated_storage:FindFirstChild("StateReplicators")
        if not state_replicators then return 0 end
        for _, folder in ipairs(state_replicators:GetChildren()) do
            if folder.Name == "NPCReplicator" then
                local unit_type = folder:GetAttribute("Type")
                if unit_type == "Enemies" then
                    if folder:GetAttribute("DisplayName") ~= "Corpse" then
                        local health = folder:GetAttribute("Health")
                        if health and type(health) == "number" and health > 0 then
                            total_health = total_health + health
                        end
                    end
                end
            end
        end
        return total_health
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
            local current_wave = get_current_wave()
            if current_wave ~= current_wave_tracking.wave then
                current_wave_tracking.wave = current_wave
                current_wave_tracking.wave_start_time = tick()
                current_wave_tracking.skip_active = false
            end
            if not current_wave_tracking.skip_active and tick() - current_wave_tracking.wave_start_time > 10 then
                local health = get_total_enemy_health()
                local threshold = 2500
                for w, t in pairs(HEALTH_THRESHOLDS) do
                    if current_wave >= w then threshold = t end
                end
                if health < threshold then
                    current_wave_tracking.skip_active = true
                    task.spawn(function()
                        while current_wave_tracking.skip_active and _G.AutoSmartSkip do
                            if get_current_wave() > current_wave_tracking.wave then
                                current_wave_tracking.skip_active = false
                                break
                            end
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

function TDS:AutoSmartSkip(state)
    _G.AutoSmartSkip = state == true or state == "T" or state == "t"
    start_smart_auto_skip()
end

if _G.AutoSmartSkip then
    task.spawn(start_smart_auto_skip)
end

function TDS:MedicSelect(idx, val)
    local t = self.placed_towers[idx]
    local target = self.placed_towers[val]
    if t and target then
        local remote_func = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
        remote_func:InvokeServer("Troops", "TowerServerEvent", "ToggleSelectedTower", t, target)
        return true
    end
    return false
end

local function start_auto_mercenary()
    if auto_mercenary_running or not _G.AutoMercenary then return end
    auto_mercenary_running = true
    task.spawn(function()
        while _G.AutoMercenary do
            local towers_folder = workspace:FindFirstChild("Towers")
            if towers_folder then
                for _, towers in ipairs(towers_folder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Mercenary Base"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 5 then
                        local mercenary = towers.Parent
                        remote_func:InvokeServer("Troops", "Abilities", "Activate", {
                            Troop = mercenary,
                            Name = "Air-Drop",
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
        if _G.AutoPickups and not auto_pickups_running then start_auto_pickups() end
        if _G.AutoSmartSkip and not auto_smart_skip_running then start_smart_auto_skip() end
        if _G.AutoNecro and not auto_necro_running then start_auto_necro() end
        if _G.AutoSkip and not auto_skip_running then start_auto_skip() end
        if _G.AutoChain and not auto_chain_running then start_auto_chain() end
        if _G.AutoDJ and not auto_dj_running then start_auto_dj_booth() end
        if _G.AntiLag and not anti_lag_running then start_anti_lag() end
        if _G.AutoMercenary and not auto_mercenary_running then start_auto_mercenary() end
        if _G.AutoUber and not auto_uber_running then start_auto_uber() end
        if _G.AutoSupport and not auto_support_running then start_auto_support() end
        task.wait(1)
    end
end)

if _G.ClaimRewards and not auto_claim_rewards then
    start_claim_rewards()
end

start_back_to_lobby()
start_rejoin_on_disconnect()

local function create_buttons()
    local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    if playerGui:FindFirstChild("AutoRejoinButton") then return end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoRejoinButton"
    screenGui.Parent = playerGui
    screenGui.ResetOnSpawn = false

    local rejoinButton = Instance.new("TextButton")
    rejoinButton.Name = "ToggleButton"
    rejoinButton.Size = UDim2.new(0, 130, 0, 35)
    rejoinButton.Position = UDim2.new(0, 10, 0, 10)
    rejoinButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
    rejoinButton.BackgroundTransparency = 0.3
    rejoinButton.TextColor3 = Color3.new(1, 1, 1)
    rejoinButton.TextScaled = true
    rejoinButton.Font = Enum.Font.GothamBold
    rejoinButton.Text = "Auto Rejoin: ON"
    rejoinButton.Parent = screenGui

    local startMatchButton = Instance.new("TextButton")
    startMatchButton.Name = "StartMatchButton"
    startMatchButton.Size = UDim2.new(0, 130, 0, 35)
    startMatchButton.Position = UDim2.new(0, 10, 0, 50)
    startMatchButton.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
    startMatchButton.BackgroundTransparency = 0.3
    startMatchButton.TextColor3 = Color3.new(1, 1, 1)
    startMatchButton.TextScaled = true
    startMatchButton.Font = Enum.Font.GothamBold
    startMatchButton.Text = "Start Match"
    startMatchButton.Parent = screenGui

    local dragging = false
    local dragStart, startPos
    local function onDragStart(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = rejoinButton.Position
        end
    end
    local function onDragEnd(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end
    local function onDragMove(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            local newPos = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            rejoinButton.Position = newPos
            startMatchButton.Position = UDim2.new(newPos.X.Scale, newPos.X.Offset, newPos.Y.Scale, newPos.Y.Offset + 40)
        end
    end

    rejoinButton.InputBegan:Connect(onDragStart)
    rejoinButton.InputEnded:Connect(onDragEnd)
    rejoinButton.InputChanged:Connect(onDragMove)

    local function update_rejoin_button()
        if _G.AutoRejoin then
            rejoinButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
            rejoinButton.Text = "Auto Rejoin: ON"
        else
            rejoinButton.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
            rejoinButton.Text = "Auto Rejoin: OFF"
        end
        save_auto_rejoin_state(_G.AutoRejoin)
    end

    rejoinButton.MouseButton1Click:Connect(function()
        _G.AutoRejoin = not _G.AutoRejoin
        update_rejoin_button()
    end)

    startMatchButton.MouseButton1Click:Connect(function()
        if TDS.ReplayCallback then
            TDS.ReplayCallback()
        else
            warn("No replay callback set. Use TDS.ReplayCallback = function() ... end")
        end
    end)

    local function update_visibility()
        local inLobby = playerGui:FindFirstChild("ReactLobbyHud") ~= nil
        startMatchButton.Visible = inLobby
    end

    update_visibility()
    playerGui.ChildAdded:Connect(function(child)
        if child.Name == "ReactLobbyHud" then
            update_visibility()
        end
    end)
    playerGui.ChildRemoved:Connect(function(child)
        if child.Name == "ReactLobbyHud" then
            update_visibility()
        end
    end)

    update_rejoin_button()

    task.spawn(function()
        for _ = 1, 15 do
            local tdsUI = playerGui:FindFirstChild("TDS_UI")
            if tdsUI and tdsUI:IsA("ScreenGui") and tdsUI.Enabled then
                _G.AutoRejoin = false
                update_rejoin_button()
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