if not game:IsLoaded() then game.Loaded:Wait() end

-- Basic runtime flags
local back_to_lobby_running = false
local auto_pickups_running = false
local auto_skip_running = false
local anti_lag_running = false
local auto_chain_running = false
local auto_dj_running = false
local auto_claim_rewards = false
local postmatch_manager_running = false

local hasSentLobbyWebhook = false
local hasSentMatchStartWebhook = false

-- // services & main refs
local teleport_service = game:GetService("TeleportService")
local marketplace_service = game:GetService("MarketplaceService")
local replicated_storage = game:GetService("ReplicatedStorage")
local remote_func = replicated_storage:WaitForChild("RemoteFunction")
local remote_event = replicated_storage:WaitForChild("RemoteEvent")
local players_service = game:GetService("Players")
local local_player = players_service.LocalPlayer or players_service.PlayerAdded:Wait()
local player_gui = local_player:WaitForChild("PlayerGui")

local send_request = request or http_request or httprequest
    or (GetDevice and GetDevice().request)

if not send_request then 
    warn("failure: no http function") 
    -- continue, webhook functions will be no-ops
end

-- // icon item ids ill add more soon arghh
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

-- // tower management core
local TDS = {
    placed_towers = {},
    active_strat = true,
    matchmaking_map = {
        ["Hardcore"] = "hardcore",
        ["Pizza Party"] = "halloween",
        ["Badlands"] = "badlands",
        ["Polluted"] = "polluted"
    }
}

local upgrade_history = {}

-- // shared for addons
shared.TDS_Table = TDS

-- // currency tracking
local start_coins, current_total_coins, start_gems, current_total_gems = 0, 0, 0, 0
local current_level = 0

-- // detect LOBBY/GAME
local function identify_game_state()
    local players = game:GetService("Players")
    local temp_player = players.LocalPlayer or players.PlayerAdded:Wait()
    local temp_gui = temp_player:WaitForChild("PlayerGui")
    
    while true do
        if temp_gui:FindFirstChild("LobbyGui") then
            return "LOBBY"
        elseif temp_gui:FindFirstChild("GameGui") then
            return "GAME"
        end
        task.wait(1)
    end
end

local game_state = identify_game_state()

if game_state == "LOBBY" then
    pcall(function()
        -- Get current level (this works in lobby)
        local levelObject = local_player.PlayerGui.ReactLobbyBattlepass.Frame.scaled.battlepass.content.progress.level
        if levelObject:IsA("TextLabel") or levelObject:IsA("TextButton") or levelObject:IsA("TextBox") then
            current_level = tonumber(levelObject.Text) or 0
        else
            current_level = levelObject.Value or 0
        end
        print("Level " .. tostring(current_level))
    end)
elseif game_state == "GAME" then
    pcall(function()
        -- Wait for coins and gems (these only exist in game)
        repeat task.wait(1) until local_player:FindFirstChild("Coins")
        start_coins = local_player.Coins.Value
        current_total_coins = start_coins
        start_gems = local_player.Gems.Value
        current_total_gems = start_gems
    end)
end

-- // helpers
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

-- Safe caller to avoid "attempt to call nil value"
local function safe_call(fn, ...)
    if type(fn) ~= "function" then
        warn("safe_call: not a function:", tostring(fn))
        return false
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("safe_call: function error:", tostring(err))
        return false
    end
    return true
end

-- forward declarations (functions used earlier/later)
local trigger_restart, restart_macros, start_postmatch_manager, handle_post_match

-- Replace send_to_lobby to be a client-side restart (no server teleport)
local function send_to_lobby()
    -- Previously fired server "RE:backToLobby". Now we call a safe restart instead.
    if type(trigger_restart) == "function" then
        pcall(trigger_restart)
    else
        warn("send_to_lobby: trigger_restart not available")
    end
end

-- // timescale logic, unlock, etc (unchanged)
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
        replicated_storage.RemoteFunction:InvokeServer(
            "TicketsManager",
            "CycleTimeScale"
        )
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

-- // ingame control (trigger_restart is used by handle_post_match)
trigger_restart = function()
    -- Wait briefly for reward UI (best-effort). If not present, proceed anyway.
    local ok, ui_root = pcall(function()
        return player_gui:FindFirstChild("ReactGameNewRewards")
    end)

    if ui_root == nil then
        -- proceed, we might be in a different state
        warn("trigger_restart: ReactGameNewRewards not found; proceeding with restart")
    end

    -- Attempt to perform in-game restart: run vote skip if available
    if type(run_vote_skip) == "function" then
        pcall(run_vote_skip)
    else
        -- fallback behaviour: attempt to invoke any server API for restart if known
        -- otherwise just proceed to restart macros locally
        warn("trigger_restart: run_vote_skip not available, relying on server flows or client-only restart")
    end

    -- give server a moment to process the skip/restart
    task.wait(1)

    -- restart macros (wait for match to start)
    if type(restart_macros) == "function" then
        pcall(restart_macros, true)
    end
end

-- restart_macros resets internal guard flags and restarts enabled macros
restart_macros = function(wait_for_ingame)
    auto_pickups_running   = false
    auto_skip_running      = false
    auto_chain_running     = false
    auto_dj_running        = false
    anti_lag_running       = false
    back_to_lobby_running  = false

    -- allow existing loops to exit
    task.wait(0.5)

    -- optionally wait until next match UI is present before restarting macros
    if wait_for_ingame then
        local max_wait = 30
        local waited = 0
        while waited < max_wait do
            if player_gui:FindFirstChild("ReactIngameHud")
               or player_gui:FindFirstChild("ReactGameTopGameDisplay") then
                break
            end
            task.wait(0.5)
            waited = waited + 0.5
        end
    end

    -- restart macros that the user enabled
    if _G.AutoPickups and type(start_auto_pickups) == "function" then safe_call(start_auto_pickups) end
    if _G.AutoSkip    and type(start_auto_skip)    == "function" then safe_call(start_auto_skip)    end
    if _G.AutoChain   and type(start_auto_chain)   == "function" then safe_call(start_auto_chain)   end
    if _G.AutoDJ      and type(start_auto_dj_booth)== "function" then safe_call(start_auto_dj_booth)  end
    if _G.AntiLag     and type(start_anti_lag)     == "function" then safe_call(start_anti_lag)     end

    if _G.ClaimRewards and not auto_claim_rewards and game_state == "LOBBY"
       and type(start_claim_rewards) == "function" then
        safe_call(start_claim_rewards)
    end
end

-- // scrap ui for match data
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

-- // lobby / teleporting (send_to_lobby now safe)
local function handle_post_match()
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
        -- fallback to restarting behavior
        if type(trigger_restart) == "function" then pcall(trigger_restart) end
        return
    end

    -- If webhooks disabled, still restart the run instead of teleporting
    if not _G.SendWebhook then
        if type(trigger_restart) == "function" then pcall(trigger_restart) end
        return
    end

    local match = get_all_rewards()

    current_total_coins = current_total_coins + (match.Coins or 0)
    current_total_gems = current_total_gems + (match.Gems or 0)

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
            description =
                "### 📋 Match Overview\n" ..
                "> **Status:** `" .. match.Status .. "`\n" ..
                "> **Time:** `" .. match.Time .. "`\n" ..
                "> **Current Level:** `" .. match.Level .. "`\n" ..
                "> **Wave:** `" .. match.Wave .. "`\n",
                
            fields = {
                {
                    name = "✨ Rewards",
                    value = "```ansi\n" ..
                            "[2;33mCoins:[0m +" .. (match.Coins or 0) .. "\n" ..
                            "[2;34mGems: [0m +" .. (match.Gems or 0) .. "\n" ..
                            "[2;32mXP:   [0m +" .. (match.XP or 0) .. "```",
                    inline = false
                },
                {
                    name = "🎁 Bonus Items",
                    value = bonus_string,
                    inline = true
                },
                {
                    name = "📊 Session Totals",
                    value = "```py\n# Total Amount\nCoins: " .. current_total_coins .. "\nGems:  " .. current_total_gems .. "```",
                    inline = true
                }
            },
            footer = { text = "Logged for " .. local_player.Name .. " • TDS AutoStrat" },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }

    pcall(function()
        send_request({
            Url = _G.Webhook,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(post_data)
        })
    end)

    task.wait(1.5)

    -- restart run instead of sending to lobby
    if type(trigger_restart) == "function" then pcall(trigger_restart) end
end

-- 1. Define BOTH functions first (log webhook / lobby webhook) (unchanged)
local function log_match_start()
    if hasSentMatchStartWebhook then 
        return 
    end
    
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
                {
                    name = "🪙 Starting Coins",
                    value = "```" .. tostring(start_coins) .. " Coins```",
                    inline = true
                },
                {
                    name = "💎 Starting Gems",
                    value = "```" .. tostring(start_gems) .. " Gems```",
                    inline = true
                },
                {
                    name = "Status",
                    value = "🟢 Running Script",
                    inline = false
                }
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
    if hasSentLobbyWebhook then 
        return 
    end
    
    if not _G.SendWebhook then return end
    if type(_G.Webhook) ~= "string" or _G.Webhook == "" then return end
    if _G.Webhook:find("YOUR%-WEBHOOK") then return end

    hasSentLobbyWebhook = true
    
    -- Wait for battlepass GUI to load with multiple attempts
    local maxAttempts = 10
    local battlepassLevel = "0"
    
    for attempt = 1, maxAttempts do
        local success, result = pcall(function()
            -- Check if the GUI path exists
            local gui = local_player.PlayerGui:WaitForChild("ReactLobbyBattlepass", 2)
            local frame = gui:WaitForChild("Frame", 1)
            local scaled = frame:WaitForChild("scaled", 1)
            local battlepass = scaled:WaitForChild("battlepass", 1)
            local content = battlepass:WaitForChild("content", 1)
            local progress = content:WaitForChild("progress", 1)
            local levelObj = progress:WaitForChild("level", 1)
            
            -- Try to get the value
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
    
    -- Send webhook
    local lobby_payload = {
        username = "TDS AutoStrat",
        embeds = {{
            title = "📋 **Inside Lobby**",
            description = "Script loaded successfully. Waiting in lobby for battlepass level to load.",
            color = 16776960,
            fields = {
                {
                    name = "📊 Battlepass Level",
                    value = "```Level " .. battlepassLevel .. "```",
                    inline = false
                },
                {
                    name = "🎮 Game Status",
                    value = "🟡 **In Lobby** - Ready to start match",
                    inline = false
                }
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

-- 2. THEN check game state and call appropriate function
if game_state == "LOBBY" then
    send_lobby_webhook()
elseif game_state == "GAME" then
    log_match_start()
end

-- // voting & map selection
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
    local player_gui_local = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    
    local ui_overrides = player_gui_local:WaitForChild("ReactOverridesVote", 30)
    local main_frame = ui_overrides and ui_overrides:WaitForChild("Frame", 30)
    
    if not main_frame then
        return
    end

    local vote_ready = nil

    while not vote_ready do
        local vote_node = main_frame:FindFirstChild("votes")
        
        if vote_node then
            local container = vote_node:FindFirstChild("container")
            if container then
                local ready = container:FindFirstChild("ready")
                if ready then
                    vote_ready = ready
                end
            end
        end
        
        if not vote_ready then
            task.wait(0.5) 
        end
    end

    repeat task.wait(0.1) until vote_ready.Visible == true

    run_vote_skip()
    log_match_start()
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

    task.wait(3)
    cast_map_vote(map_id, Vector3.new(12.59, 10.64, 52.01))
    task.wait(1)
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
    -- First check if map is already available
    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local t = g:FindFirstChild("Title")
            if t and t.Text == name then
                return true
            end
        end
    end

    -- If not available, try to veto and wait for new maps
    local total_players = #players_service:GetPlayers()
    
    -- Send veto vote once
    remote_event:FireServer("LobbyVoting", "Veto")
    
    -- Wait for veto UI to update
    local veto_ui = player_gui:WaitForChild("ReactGameIntermission", 5)
    if not veto_ui then return false end
    
    local frame = veto_ui:WaitForChild("Frame", 5)
    if not frame then return false end
    
    local buttons = frame:WaitForChild("buttons", 5)
    if not buttons then return false end
    
    local veto_button = buttons:WaitForChild("veto", 5)
    if not veto_button then return false end
    
    local veto_value = veto_button:WaitForChild("value", 5)
    if not veto_value then return false end
    
    -- Wait for veto to complete (all players voted)
    local max_wait_time = 2  
    local start_time = os.time()
    
    while os.time() - start_time < max_wait_time do
        if veto_value.Text == "Veto ("..total_players.."/"..total_players..")" then
            break
        end
        task.wait(1)
    end
    
    -- Wait for new maps to load after veto
    task.wait(3)
    
    -- Check for the map again
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

-- // ingame actions (do_place_tower, upgrades, etc) unchanged
local function set_current_wave_label()
    local label = player_gui:WaitForChild("ReactGameTopGameDisplay").Frame.wave.container.value
    local wave_num = label.Text:match("^(%d+)")
    return tonumber(wave_num) or 0
end

local function do_place_tower(t_name, t_pos)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Pl\208\176ce", {
                Rotation = CFrame.new(),
                Position = t_pos
            }, t_name)
        end)

        if ok and check_res_ok(res) then return true end
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
        task.wait(0.25)
    end
end

local function do_set_option(t_obj, opt_name, opt_val, req_wave)
    if req_wave then
        repeat task.wait(0.3) until set_current_wave_label() >= req_wave
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

    local clone_idx = ab_data and ab_data.towerToClone
    local target_idx = ab_data and ab_data.towerTarget

    local function attempt()
        while true do
            local ok, res = pcall(function()
                local data

                if ab_data then
                    data = table.clone(ab_data)

                    -- 🎯 RANDOMIZE HERE (every attempt)
                    if positions and #positions > 0 then
                        data.towerPosition = positions[math.random(#positions)]
                    end

                    if type(clone_idx) == "number" then
                        data.towerToClone = TDS.placed_towers[clone_idx]
                    end

                    if type(target_idx) == "number" then
                        data.towerTarget = TDS.placed_towers[target_idx]
                    end
                end

                return remote_func:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    {
                        Troop = t_obj,
                        Name = ab_name,
                        Data = data
                    }
                )
            end)

            if ok and check_res_ok(res) then
                return true
            end

            task.wait(0.25)
        end
    end

    if is_looping then
        local active = true
        task.spawn(function()
            while active do
                attempt()
                task.wait(1)
            end
        end)
        return function() active = false end
    end

    return attempt()
end

-- // public api
function TDS:Mode(difficulty)
    if game_state ~= "LOBBY" then 
        return false 
    end

    local lobby_hud = player_gui:WaitForChild("ReactLobbyHud", 30)
    local frame = lobby_hud and lobby_hud:WaitForChild("Frame", 30)
    local match_making = frame and frame:WaitForChild("matchmaking", 30)

    if match_making then
    local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
    local success = false
    local res
        repeat
            local ok, result = pcall(function()
                local mode = TDS.matchmaking_map[difficulty]

                local payload

                if mode then
                    payload = {
                        mode = mode,
                        count = 1
                    }
                else
                    payload = {
                        difficulty = difficulty,
                        mode = "survival",
                        count = 1
                    }
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
    local towers = {}
    if #raw_args == 1 and type(raw_args[1]) == "table" then
        towers = raw_args[1]
    else
        towers = raw_args
    end

    if #towers == 0 then
        return false, "no towers provided"
    end

    local state = nil
    if type(game_state) == "string" then
        state = game_state
    end

    if state ~= "LOBBY" and state ~= "GAME" then
        local player = game:GetService("Players").LocalPlayer
        if player and player:FindFirstChild("PlayerGui") then
            local pg = player.PlayerGui
            if pg:FindFirstChild("ReactLobbyHud") then
                state = "LOBBY"
            elseif pg:FindFirstChild("ReactIngameHud") or pg:FindFirstChild("GameGui") then
                state = "GAME"
            end
        end
    end

    if state ~= "LOBBY" and state ~= "GAME" then
        return false, ("unsupported or unknown game state: %s"):format(tostring(state))
    end

    local replicated = game:GetService("ReplicatedStorage")
    local remote = nil
    local ok, res = pcall(function()
        return replicated:WaitForChild("RemoteFunction", 5)
    end)
    if ok then
        remote = res
    else
        remote = replicated:FindFirstChild("RemoteFunction")
    end

    if not remote then
        return false, "RemoteFunction not found in ReplicatedStorage"
    end

    if state == "LOBBY" then
        local player = game:GetService("Players").LocalPlayer
        if player then
            local player_gui_local = player:FindFirstChild("PlayerGui")
            if player_gui_local then
                local lobby_hud = player_gui_local:FindFirstChild("ReactLobbyHud")
                if lobby_hud then
                    local frame = lobby_hud:FindFirstChild("Frame")
                    if frame then
                        local matchmaking = frame:FindFirstChild("matchmaking")
                        if not matchmaking then
                            pcall(function()
                                frame:WaitForChild("matchmaking", 2)
                            end)
                        end
                    end
                end
            end
        end
    end

    for _, tower_name in ipairs(towers) do
        if tower_name and tower_name ~= "" then
            local ok, err = pcall(function()
                remote:InvokeServer("Inventory", "Equip", "tower", tower_name)
            end)
            if not ok then
                warn(("TDS:Loadout - failed to equip %s: %s"):format(tostring(tower_name), tostring(err)))
            end
            task.wait(0.5)
        end
    end

    return true
end

function TDS:VoteSkip(start_wave, end_wave)
    task.spawn(function()
        local current_wave = get_all_rewards and get_all_rewards().Wave or get_current_wave()
        start_wave = current_wave or start_wave
        end_wave = end_wave or start_wave

        for wave = start_wave, end_wave do
            repeat
                task.wait(0.5)
            until set_current_wave_label() >= wave

            local skip_done = false
            while not skip_done do
                local skip_visible = player_gui:FindFirstChild("ReactOverridesVote")
                    and player_gui.ReactOverridesVote:FindFirstChild("Frame")
                    and player_gui.ReactOverridesVote.Frame:FindFirstChild("votes")
                    and player_gui.ReactOverridesVote.Frame.votes:FindFirstChild("vote", true)

                if skip_visible and skip_visible.Position == UDim2.new(0.5, 0, 0.5, 0) then
                    run_vote_skip()
                    skip_done = true
                else
                    task.wait(0.2)
                end
            end
        end
    end)
end

function TDS:GameInfo(name, list)
    list = list or {}
    if game_state ~= "GAME" then 
        warn("Not in game state for GameInfo")
        return false 
    end
    
    local vote_gui = player_gui:WaitForChild("ReactGameIntermission", 30)
    if not (vote_gui and vote_gui.Enabled) then 
        warn("Vote GUI not found or not enabled")
        -- Don't teleport; restart instead
        if type(trigger_restart) == "function" then pcall(trigger_restart) end
        return false
    end
    
    local frame = vote_gui:WaitForChild("Frame", 5)
    if not frame then
        warn("Vote GUI Frame not found")
        if type(trigger_restart) == "function" then pcall(trigger_restart) end
        return false
    end

    cast_modifier_vote(list)
    
    task.wait(2)  -- Wait for modifier votes to process
    
    if marketplace_service:UserOwnsGamePassAsync(local_player.UserId, 10518590) then
        select_map_override(name, "vip")
        return true
    end
    
    -- Try to get the map via veto
    if is_map_available(name) then
        select_map_override(name)
        return true
    end
    
    -- If we get here, veto didn't give us the right map
    warn("Map '" .. tostring(name) .. "' not available after veto, restarting instead of teleporting to lobby")
    
    task.wait(1)
    if type(trigger_restart) == "function" then pcall(trigger_restart) end
    return false
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
    return set_current_wave_label()
end

function TDS:RestartGame()
    -- Public API: trigger a restart and ensure macros re-enable
    if type(trigger_restart) == "function" then
        pcall(trigger_restart)
        -- ensure macros get restarted shortly after
        task.spawn(function()
            task.wait(1.2)
            if type(restart_macros) == "function" then pcall(restart_macros, true) end
        end)
        return true
    else
        warn("TDS:RestartGame - trigger_restart not available")
        return false
    end
end

function TDS:RestartGameImmediate()
    -- Immediate restart without waiting for UI: mainly for direct use
    if type(run_vote_skip) == "function" then
        pcall(run_vote_skip)
    end
    if type(restart_macros) == "function" then
        pcall(restart_macros, true)
    end
end

function TDS:RestartGameOnlyMacros()
    if type(restart_macros) == "function" then
        pcall(restart_macros, true)
    end
end

function TDS:RestartGameLocal()
    -- compatibility alias
    return self:RestartGame()
end

function TDS:Restart()
    return self:RestartGame()
end

function TDS:RestartGameAndWait()
    if type(trigger_restart) == "function" then
        pcall(trigger_restart)
        if type(restart_macros) == "function" then
            restart_macros(true)
        end
    end
end

function TDS:RestartGameNoMacro()
    if type(trigger_restart) == "function" then
        pcall(trigger_restart)
    end
end

function TDS:RestartGameSilent()
    if type(trigger_restart) == "function" then
        pcall(trigger_restart)
    end
end

function TDS:RestartGameAndLog()
    if type(trigger_restart) == "function" then
        pcall(trigger_restart)
        warn("TDS:RestartGame triggered")
    end
end

-- other public API functions (Place, Upgrade, Sell, Ability, etc.)
function TDS:StartGameLobbyReady()
    lobby_ready_up()
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
    
    local existing = {}
    for _, child in ipairs(workspace.Towers:GetChildren()) do
        for _, sub_child in ipairs(child:GetChildren()) do
            if sub_child.Name == "Owner" and sub_child.Value == local_player.UserId then
                existing[child] = true
                break
            end
        end
    end

    do_place_tower(t_name, Vector3.new(px, py, pz))

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
        repeat task.wait(0.5) until set_current_wave_label() >= req_wave
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
        repeat task.wait(0.5) until set_current_wave_label() >= req_wave
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
            repeat task.wait(0.5) until set_current_wave_label() >= req_wave
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

            i += 1
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

-- // misc utility
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

                    if item:IsA("MeshPart") and (item.Name == "SnowCharm" or item.Name == "Lorebook") then
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
            local skip_visible =
                player_gui:FindFirstChild("ReactOverridesVote")
                and player_gui.ReactOverridesVote:FindFirstChild("Frame")
                and player_gui.ReactOverridesVote.Frame:FindFirstChild("votes")
                and player_gui.ReactOverridesVote.Frame.votes:FindFirstChild("vote")

            if skip_visible and skip_visible.Position == UDim2.new(0.5, 0, 0.5, 0) then
                run_vote_skip()
            end

            task.wait(0.1)
        end

        auto_skip_running = false
    end)
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
    -- kept for legacy compat; replaced by postmatch manager
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
            local enemies = workspace:FindFirstChild("NPCs")

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
            if enemies then
                for _, npc in ipairs(enemies:GetChildren()) do
                    npc:Destroy()
                end
            end
            task.wait(0.5)
        end
        anti_lag_running = false
    end)
end

local function start_anti_afk()
    local Players = game:GetService("Players")
    local GC = getconnections and getconnections or get_signal_cons

    if GC then
        for i, v in pairs(GC(Players.LocalPlayer.Idled)) do
            if v.Disable then
                v:Disable()
            elseif v.Disconnect then
                v:Disconnect()
            end
        end
    else
        Players.LocalPlayer.Idled:Connect(function()
            local VirtualUser = game:GetService("VirtualUser")
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end

    local ANTIAFK = Players.LocalPlayer.Idled:Connect(function()
        local VirtualUser = game:GetService("VirtualUser")
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end

local function start_rejoin_on_disconnect()
    task.spawn(function()
        game.Players.PlayerRemoving:connect(function (plr)
            if plr == game.Players.LocalPlayer then
                game:GetService('TeleportService'):Teleport(3260590327, plr)
            end
        end)
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

                remote_func:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { Troop = commander[idx], Name = "Call Of Arms", Data = {} }
                )

                idx += 1

                local hotbar = player_gui.ReactUniversalHotbar.Frame
                local timescale = hotbar and hotbar:FindFirstChild("timescale")
                if timescale then
                    if timescale:FindFirstChild("Lock") then
                        task.wait(11)
                    else
                        task.wait(5.5)
                    end
                else
                    task.wait(11)
                end
            end

            task.wait(1)
        end

        auto_chain_running = false
    end)
end

local function start_auto_dj_booth()
    if auto_dj_running or not _G.AutoDJ then return end
    auto_dj_running = true

    task.spawn(function()
        while _G.AutoDJ do
            local towers_folder = workspace:FindFirstChild("Towers")
            local DJ = nil

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

                local hotbar = player_gui.ReactUniversalHotbar.Frame
                local timescale = hotbar and hotbar:FindFirstChild("timescale")
                if timescale then
                    if timescale:FindFirstChild("Lock") then
                        task.wait(28)
                    else
                        task.wait(14)
                    end
                else
                    task.wait(28)
                end
            end

            task.wait(1)
        end

        auto_dj_running = false
    end)
end

-- persistent macro manager to start desired macros when enabled
task.spawn(function()
    while true do
        if _G.AutoPickups and not auto_pickups_running then
            start_auto_pickups()
        end
        
        if _G.AutoSkip and not auto_skip_running then
            start_auto_skip()
        end

        if _G.AutoChain and not auto_chain_running then
            start_auto_chain()
        end

        if _G.AutoDJ and not auto_dj_running then
            start_auto_dj_booth()
        end
        
        if _G.AntiLag and not anti_lag_running then
            start_anti_lag()
        end
        
        task.wait(1)
    end
end)

if _G.ClaimRewards and not auto_claim_rewards then
    start_claim_rewards()
end

-- post-match manager: watches for rewards every match and restarts
start_postmatch_manager = function()
    if postmatch_manager_running then return end
    postmatch_manager_running = true

    task.spawn(function()
        while true do
            -- wait for rewards UI to appear
            local root = player_gui:FindFirstChild("ReactGameNewRewards")
            while not root do
                task.wait(1)
                root = player_gui:FindFirstChild("ReactGameNewRewards")
            end

            -- wait until RewardsSection exists
            local rewards_section
            repeat
                local frame = root and root:FindFirstChild("Frame")
                local gameOver = frame and frame:FindFirstChild("gameOver")
                local rewards_screen = gameOver and gameOver:FindFirstChild("RewardsScreen")
                rewards_section = rewards_screen and rewards_screen:FindFirstChild("RewardsSection")
                if not rewards_section then task.wait(0.5) end
            until rewards_section

            print("postmatch_manager: rewards detected; running handle_post_match")
            -- handle the match end (send webhooks & restart)
            local ok, err = pcall(function()
                if type(handle_post_match) == "function" then
                    handle_post_match()
                else
                    warn("postmatch_manager: handle_post_match not defined; calling trigger_restart instead")
                    trigger_restart()
                end
            end)
            if not ok then
                warn("postmatch_manager: handle_post_match error:", tostring(err))
            end

            -- wait for rewards screen to disappear or until in-game HUD shows up (indicating new match)
            local watchdog = 0
            repeat
                task.wait(0.5)
                watchdog = watchdog + 0.5
                root = player_gui:FindFirstChild("ReactGameNewRewards")
                local ingame = player_gui:FindFirstChild("ReactIngameHud") or player_gui:FindFirstChild("ReactGameTopGameDisplay")
                if not root and ingame then
                    print("postmatch_manager: rewards gone and in-game HUD detected; proceeding")
                    break
                end
                -- safety cap: after 45s move on and still try to restart macros
            until watchdog >= 45

            -- Ensure macros restart for next match
            pcall(restart_macros, true)

            -- small delay to avoid tight loops
            task.wait(2)
        end
    end)
end

-- start (call replacement manager)
start_postmatch_manager() 
