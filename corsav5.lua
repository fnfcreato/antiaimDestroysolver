local vector = require("vector")

-- Configuration with expanded options
local CORSA = {
    NAME = "Corsa Resolver",
    VERSION = "4.0",
    DEBUG = true,
    COLORS = {
        PRIMARY = {149, 149, 201},
        SUCCESS = {100, 255, 100},
        WARNING = {255, 200, 0},
        ERROR = {255, 100, 100},
        DEBUG = {180, 180, 255} -- New debug color
    },
    RESOLVER = {
        MAX_DESYNC_ANGLE = 58,
        JITTER_THRESHOLD = 30,
        HISTORY_SIZE = 24, -- Increased from 16
        UPDATE_INTERVAL = 0.002,
        FAKE_DUCK_THRESHOLD = 0.1,
        FAKE_DUCK_HIGH_VALUE = 0.7,
        FAKE_DUCK_SPEED_THRESHOLD = 5,
        EXPLOIT_TIME_ANOMALY = 0.001,
        EXPLOIT_TIME_JUMP = 0.1,
        EXPLOIT_TIME_DIFF_THRESHOLD = 0.001,
        EXPECTED_TIME_DIFF = 1/64,
        BACKTRACK_MAX_TICKS = 16, -- Increased from 12
        DEFENSIVE_AA_YAW_THRESHOLD = 15, -- New: threshold for defensive AA detection
        DEFENSIVE_AA_VELOCITY_THRESHOLD = 5, -- New: velocity threshold for defensive AA
        DEFENSIVE_AA_CORRECTION_ANGLE = 60, -- New: correction angle for defensive AA
        DEFENSIVE_AA_SIM_TIME_THRESHOLD = 0.01, -- New: sim time threshold for break LC detection
        ADAPTIVE_LEARNING_RATE = 0.2, -- New: learning rate for adaptive resolver
        SHOT_HISTORY_SIZE = 16, -- New: size of shot history buffer
        MISS_CORRECTION_AMOUNT = 15, -- New: correction amount after miss
        HIT_CORRECTION_DECAY = 0.8, -- New: decay rate for correction after hit
        MAX_CORRECTION = 60 -- New: maximum correction angle
    },
    PERFORMANCE = {
        UPDATE_INTERVAL = 0.002,
        CLEANUP_INTERVAL = 300, -- Ticks between cleanup operations
        INDICATOR_UPDATE_INTERVAL = 0.03, -- Update interval for indicators
        STALE_DATA_THRESHOLD = 5.0 -- Seconds before data is considered stale
    }
}



-- Utility Functions (Enhanced)
-- Utility Functions (Enhanced)
local util = {}

-- Initialize _perf_data at the beginning before any functions
util._perf_data = {}

-- Property access with error handling
util.get_prop = function(entity_index, prop_name, default_value)
    if not entity_index or not entity.is_alive(entity_index) then return default_value end
    local success, value = pcall(entity.get_prop, entity_index, prop_name)
    return success and value or default_value
end

util.set_prop = function(entity_index, prop_name, value)
    if not entity_index or not entity.is_alive(entity_index) then return false end
    local success = pcall(entity.set_prop, entity_index, prop_name, value)
    return success
end

-- Math helpers
util.lerp = function(a, b, t)
    return a + (b - a) * t
end

util.clamp = function(val, min, max)
    return math.max(min, math.min(max, val))
end

util.normalize_angle = function(angle)
    angle = angle % 360
    if angle > 180 then 
        angle = angle - 360 
    end
    return angle
end

util.angle_diff = function(a, b)
    local diff = (a - b) % 360
    if diff > 180 then 
        diff = diff - 360 
    end
    return math.abs(diff)
end

-- Logging
util.log = function(r, g, b, message)
    client.color_log(r, g, b, string.format("[%s v%s] %s", CORSA.NAME, CORSA.VERSION, message))
end

util.debug = function(message)
    if CORSA.DEBUG then
        util.log(CORSA.COLORS.DEBUG[1], CORSA.COLORS.DEBUG[2], CORSA.COLORS.DEBUG[3], 
            "[DEBUG] " .. message)
    end
end

-- Performance monitoring
util.perf_start = function(name)
    if not CORSA.DEBUG then return end
    if not util._perf_data[name] then
        util._perf_data[name] = {calls = 0}
    end
    util._perf_data[name].start = globals.realtime()
    util._perf_data[name].calls = util._perf_data[name].calls + 1
end

util.perf_end = function(name)
    if not CORSA.DEBUG or not util._perf_data[name] then return end
    local duration = globals.realtime() - util._perf_data[name].start
    util._perf_data[name].last_duration = duration
    util._perf_data[name].total_duration = (util._perf_data[name].total_duration or 0) + duration
    util._perf_data[name].avg_duration = util._perf_data[name].total_duration / util._perf_data[name].calls
end

util.get_perf_data = function()
    return util._perf_data
end

-- Vector operations
util.vector_angles = function(forward)
    local yaw = math.deg(math.atan2(forward.y, forward.x))
    local pitch = math.deg(math.atan2(-forward.z, math.sqrt(forward.x * forward.x + forward.y * forward.y)))
    return {pitch = pitch, yaw = yaw}
end

-- Enhanced visibility check with trace line
util.is_visible = function(from_player, to_player)
    if not from_player or not to_player then return false end
    
    local from_eye = {client.eye_position()}
    local to_pos = {entity.hitbox_position(to_player, 0)} -- Head hitbox
    
    if not from_eye[1] or not to_pos[1] then return false end
    
    local fraction, entity_hit = client.trace_line(from_player, 
        from_eye[1], from_eye[2], from_eye[3],
        to_pos[1], to_pos[2], to_pos[3])
        
    return fraction > 0.99 or entity_hit == to_player
end

-- Deep copy function for tables
util.table_copy = function(orig)
    if type(orig) ~= 'table' then return orig end
    local copy = {}
    for orig_key, orig_value in pairs(orig) do
        copy[orig_key] = util.table_copy(orig_value)
    end
    return copy
end

-- Prediction helpers
util.predict_position = function(entity_index, time_delta)
    local vel_x = util.get_prop(entity_index, "m_vecVelocity[0]", 0)
    local vel_y = util.get_prop(entity_index, "m_vecVelocity[1]", 0)
    local vel_z = util.get_prop(entity_index, "m_vecVelocity[2]", 0)
    
    local pos_x = util.get_prop(entity_index, "m_vecOrigin[0]", 0)
    local pos_y = util.get_prop(entity_index, "m_vecOrigin[1]", 0)
    local pos_z = util.get_prop(entity_index, "m_vecOrigin[2]", 0)
    
    -- Simple linear prediction
    return {
        x = pos_x + vel_x * time_delta,
        y = pos_y + vel_y * time_delta,
        z = pos_z + vel_z * time_delta
    }
end

-- Get network channel info
util.get_net_channel_info = function()
    local latency = client.latency()
    return {
        latency = latency * 1000, -- Convert to ms
        incoming = latency * 500, -- Estimate incoming as half of total latency
        outgoing = latency * 500, -- Estimate outgoing as half of total latency
        loss = 0, -- We don't have direct access to packet loss
        choke = globals.chokedcommands()
    }
end

-- Get lerp time
util.get_lerp_time = function()
    local cl_updaterate = cvar.cl_updaterate:get_float()
    local cl_interp = cvar.cl_interp:get_float()
    local cl_interp_ratio = cvar.cl_interp_ratio:get_float()
    
    return math.max(cl_interp, cl_interp_ratio / cl_updaterate)
end

-- Create circular buffer
util.create_circular_buffer = function(max_size)
    return RingBuffer.new(max_size)
end

-- Initialization
local function init()
    client.exec("clear")
    util.log(CORSA.COLORS.PRIMARY[1], CORSA.COLORS.PRIMARY[2], CORSA.COLORS.PRIMARY[3], 
        "Initialized successfully")
    math.randomseed(globals.realtime() * 1000)
end

-- Hit Message System (Enhanced)
local hit_system = {
    messages = {
        "Corsa Resolver v4 by chet",
        "Resolved by Corsa by chet",
        "Corsa Resolver owns you",
        "Corsa fork by chet lol",
        "Corsa resolver fork by chet - aa destroyer",
        "Corsa lmao - RESOLVED",
        "Get good lol",
        "Corsa by chet > Your Anti-Aim"
    },
    last_hit_time = 0,
    cooldown = 2.5,
    hit_count = 0,
    headshot_count = 0,

    on_hit = function(self, event)
        local current_time = globals.realtime()
        if current_time - self.last_hit_time < self.cooldown then return end

        local attacker = client.userid_to_entindex(event.attacker)
        if attacker ~= entity.get_local_player() then return end

        local target = client.userid_to_entindex(event.userid)
        if not target or not entity.is_enemy(target) or util.get_prop(target, "m_iHealth", 1) > 0 then return end

        -- Update statistics
        self.hit_count = self.hit_count + 1
        if event.hitgroup == 1 then -- Headshot
            self.headshot_count = self.headshot_count + 1
        end

        -- Select message based on hit type
        local message
        if event.hitgroup == 1 then
            message = "Corsa v4 - Headshot Machine"
        else
            message = self.messages[math.random(1, #self.messages)]
        end

        client.exec("say " .. message)
        self.last_hit_time = current_time

        if CORSA.DEBUG then
            util.debug(string.format("Hit %s in hitgroup %d for %d damage", 
                entity.get_player_name(target), event.hitgroup, event.dmg_health))
        end
    end
}

-- UI Elements (Enhanced)
local ui_elements = {
    menu_color = ui.reference("MISC", "Settings", "Menu color"),
    resolver = {
        enabled = ui.new_checkbox("RAGE", "Other", "Enable Corsa Resolver v4"),
        debug_mode = ui.new_checkbox("RAGE", "Other", "Debug Mode"),
        backtrack_enabled = ui.new_checkbox("RAGE", "Other", "Enable Backtrack"),
        backtrack_time = ui.new_slider("RAGE", "Other", "Backtrack Time", 0, 400, 200, true, "ms"),
        history_size = ui.new_slider("RAGE", "Other", "History Size", 8, 32, 24, true),
        
        jitter = {
            enabled = ui.new_checkbox("RAGE", "Other", "Jitter Correction"),
            mode = ui.new_combobox("RAGE", "Other", "Jitter Mode", {"Adaptive", "Static", "Predictive", "Pattern-Based"}),
            strength = ui.new_slider("RAGE", "Other", "Jitter Strength", 0, 100, 60, true, "%")
        },
        
        desync = {
            enabled = ui.new_checkbox("RAGE", "Other", "Desync Resolver"),
            mode = ui.new_combobox("RAGE", "Other", "Desync Mode", {"History-based", "Brute Force", "Adaptive", "Velocity-Based"})
        },
        
        fake_duck = {
            enabled = ui.new_checkbox("RAGE", "Other", "Fake Duck Resolver"),
            use_velocity = ui.new_checkbox("RAGE", "Other", "Velocity-Based Fake Duck"),
            detection_threshold = ui.new_slider("RAGE", "Other", "FD Detection Sensitivity", 1, 100, 70, true, "%")
        },
        
        exploit = {
            enabled = ui.new_checkbox("RAGE", "Other", "Exploit Resolver"),
            mode = ui.new_combobox("RAGE", "Other", "Exploit Mode", {"Conservative", "Aggressive", "Adaptive", "Defensive-AA"})
        },
        
        defensive_aa = { -- New section for defensive AA
            enabled = ui.new_checkbox("RAGE", "Other", "Defensive AA Resolver"),
            detection_threshold = ui.new_slider("RAGE", "Other", "Detection Sensitivity", 1, 100, 70, true, "%"),
            correction_angle = ui.new_slider("RAGE", "Other", "Correction Angle", 30, 90, 60, true, "°"),
            break_lc_detection = ui.new_checkbox("RAGE", "Other", "Break LC Detection")
        },
        
        adaptive = { -- New section for adaptive learning
            enabled = ui.new_checkbox("RAGE", "Other", "Adaptive Learning"),
            learning_rate = ui.new_slider("RAGE", "Other", "Learning Rate", 1, 100, 20, true, "%"),
            reset_data = ui.new_button("RAGE", "Other", "Reset Learning Data", function()
            end)
        }
    },
    
    prediction = {
        enabled = ui.new_checkbox("RAGE", "Other", "Enable Prediction"),
        ping_based = ui.new_checkbox("RAGE", "Other", "Adaptive Ping Settings"),
        ping_threshold = ui.new_slider("RAGE", "Other", "Ping Threshold", 30, 120, 60, true, "ms"),
        interp_ratio = ui.new_slider("RAGE", "Other", "Interp Ratio", 1, 4, 2, true),
        velocity_extrapolation = ui.new_checkbox("RAGE", "Other", "Velocity Extrapolation"), -- New
        extrapolation_factor = ui.new_slider("RAGE", "Other", "Extrapolation Factor", 0, 100, 50, true, "%") -- New
    },
    
    visuals = {
    enabled = ui.new_checkbox("VISUALS", "Other ESP", "Corsa Resolver Indicators"),
    style = ui.new_combobox("VISUALS", "Other ESP", "Indicator Style", {"Minimal", "Standard", "Detailed", "Modern", "Animated"}),
    position = ui.new_combobox("VISUALS", "Other ESP", "Indicator Position", {"Center", "Left", "Right", "Bottom", "Custom"}),
    custom_x = ui.new_slider("VISUALS", "Other ESP", "Custom X Position", 0, 100, 50, true, "%"),
    custom_y = ui.new_slider("VISUALS", "Other ESP", "Custom Y Position", 0, 100, 50, true, "%"),
    color_scheme = ui.new_combobox("VISUALS", "Other ESP", "Color Scheme", {"Default", "Rainbow", "Gradient", "Dynamic", "Team-Based"}),
    show_statistics = ui.new_checkbox("VISUALS", "Other ESP", "Show Statistics"),
    show_resolver_info = ui.new_checkbox("VISUALS", "Other ESP", "Show Resolver Info"),
    show_backtrack = ui.new_checkbox("VISUALS", "Other ESP", "Show Backtrack Points"),
    backtrack_style = ui.new_combobox("VISUALS", "Other ESP", "Backtrack Style", {"Dots", "Line", "Skeleton", "3D Box"}),
    show_defensive_aa = ui.new_checkbox("VISUALS", "Other ESP", "Show Defensive AA Detection"),
    show_prediction = ui.new_checkbox("VISUALS", "Other ESP", "Show Prediction Lines"),
    show_hitboxes = ui.new_checkbox("VISUALS", "Other ESP", "Show Resolved Hitboxes"),
    hitbox_time = ui.new_slider("VISUALS", "Other ESP", "Hitbox Display Time", 1, 10, 3, true, "s"),
    hit_marker = ui.new_checkbox("VISUALS", "Other ESP", "Enhanced Hit Markers"),
    hit_marker_style = ui.new_combobox("VISUALS", "Other ESP", "Hit Marker Style", {"Cross", "Circle", "Square", "3D", "Animated"}),
    hit_marker_color = ui.new_color_picker("VISUALS", "Other ESP", "Hit Marker Color", 255, 255, 255, 255),
    hit_marker_size = ui.new_slider("VISUALS", "Other ESP", "Hit Marker Size", 1, 20, 8, true, "px"),
    hit_marker_duration = ui.new_slider("VISUALS", "Other ESP", "Hit Marker Duration", 0.1, 2.0, 0.5, true, "s"),
    tracer_enabled = ui.new_checkbox("VISUALS", "Other ESP", "Bullet Tracers"),
    tracer_color = ui.new_color_picker("VISUALS", "Other ESP", "Tracer Color", 255, 255, 255, 150),
    tracer_duration = ui.new_slider("VISUALS", "Other ESP", "Tracer Duration", 1, 10, 3, true, "s"),
    sound_enabled = ui.new_checkbox("VISUALS", "Other ESP", "Hit Sounds"),
    sound_type = ui.new_combobox("VISUALS", "Other ESP", "Sound Type", {"Default", "Headshot", "Skeet", "Custom"})
},

-- Advanced Network Settings
network = {
    adaptive_interp = ui.new_checkbox("RAGE", "Other", "Adaptive Interp Ratio"),
    interp_min = ui.new_slider("RAGE", "Other", "Min Interp Ratio", 1, 3, 1, true),
    interp_max = ui.new_slider("RAGE", "Other", "Max Interp Ratio", 2, 5, 3, true),
    ping_compensation = ui.new_checkbox("RAGE", "Other", "Ping Compensation"),
    ping_factor = ui.new_slider("RAGE", "Other", "Ping Factor", 0, 100, 50, true, "%"),
    backtrack_ping_based = ui.new_checkbox("RAGE", "Other", "Ping-Based Backtrack"),
    backtrack_ping_factor = ui.new_slider("RAGE", "Other", "Backtrack Ping Factor", 0, 200, 100, true, "%"),
    packet_loss_detection = ui.new_checkbox("RAGE", "Other", "Packet Loss Detection"),
    packet_loss_threshold = ui.new_slider("RAGE", "Other", "Packet Loss Threshold", 1, 10, 5, true, "%"),
    packet_loss_compensation = ui.new_checkbox("RAGE", "Other", "Packet Loss Compensation")
},

-- Player-specific settings
player_specific = {
    enabled = ui.new_checkbox("RAGE", "Other", "Player-Specific Settings"),
    player_list = ui.new_listbox("RAGE", "Other", "Player List", {}),
    override_settings = ui.new_checkbox("RAGE", "Other", "Override Global Settings"),
    resolver_mode = ui.new_combobox("RAGE", "Other", "Resolver Mode", {"Auto", "Jitter", "Desync", "Defensive AA", "Fake Duck", "Exploit"}),
    correction_strength = ui.new_slider("RAGE", "Other", "Correction Strength", 0, 100, 50, true, "%"),
    backtrack_override = ui.new_checkbox("RAGE", "Other", "Override Backtrack"),
    backtrack_time_override = ui.new_slider("RAGE", "Other", "Backtrack Time", 0, 400, 200, true, "ms"),
    save_settings = ui.new_button("RAGE", "Other", "Save Player Settings", function() 
        -- Save player-specific settings
    end)
}
}

-- RingBuffer implementation (enhanced)
RingBuffer = {
    new = function(max_size)
        return {
            buffer = {},
            max_size = max_size,
            head = 1,
            tail = 1,
            size = 0,
            
            push = function(self, value)
                self.buffer[self.tail] = value
                self.tail = (self.tail % self.max_size) + 1
                
                if self.size < self.max_size then
                    self.size = self.size + 1
                else
                    self.head = (self.head % self.max_size) + 1
                end
            end,
            
            get = function(self, index)
                if index < 1 or index > self.size then
                    return nil
                end
                
                local actual_index = ((self.head - 1) + (index - 1)) % self.max_size + 1
                return self.buffer[actual_index]
            end,
            
            get_latest = function(self)
                if self.size == 0 then
                    return nil
                end
                
                local latest_index = (self.tail - 2) % self.max_size + 1
                return self.buffer[latest_index]
            end,
            
            count = function(self)
                return self.size
            end,
            
            clear = function(self)
                self.buffer = {}
                self.head = 1
                self.tail = 1
                self.size = 0
            end,
            
            to_array = function(self)
                local result = {}
                for i = 1, self.size do
                    result[i] = self:get(i)
                end
                return result
            end
        }
    end
}

-- Player data tracking (enhanced)
local player_data = {
    cache = {},
    
    get = function(self, player_index)
        if not player_index or player_index <= 0 then 
            return nil 
        end

        if not self.cache[player_index] then
            self.cache[player_index] = {
                last_update_time = 0,
                eye_angles_history = RingBuffer.new(CORSA.RESOLVER.HISTORY_SIZE),
                simulation_time_history = RingBuffer.new(CORSA.RESOLVER.HISTORY_SIZE),
                duck_amount_history = RingBuffer.new(CORSA.RESOLVER.HISTORY_SIZE),
                velocity_history = RingBuffer.new(CORSA.RESOLVER.HISTORY_SIZE),
                position_history = RingBuffer.new(CORSA.RESOLVER.HISTORY_SIZE),
                shot_history = RingBuffer.new(CORSA.RESOLVER.SHOT_HISTORY_SIZE),
                animation_layers = RingBuffer.new(CORSA.RESOLVER.HISTORY_SIZE),
                resolved_angles = {pitch = 0, yaw = 0},
                last_resolved_angles = {pitch = 0, yaw = 0},
                correction_factor = {pitch = 0, yaw = 0},
                hit_count = 0,
                miss_count = 0,
                is_fake_ducking = false,
                using_exploit = false,
                last_visible_time = 0,
                ping = 0, -- Track player's ping
                packet_loss = 0, -- Track player's packet loss
                jitter_data = {
                    detected = false,
                    range = 0,
                    frequency = 0,
                    last_flip_time = 0,
                    pattern = nil,
                    confidence = 0.5
                },
                desync_data = {
                    side = 0, -- -1 left, 0 unknown, 1 right
                    amount = 0,
                    last_update = 0,
                    confidence = 0.5,
                    history = {} -- Track desync history for pattern recognition
                },
                exploit_data = {
                    type = "none", -- "none", "dt", "hs", "fd", "unknown"
                    confidence = 0,
                    last_detection = 0,
                    detection_count = 0,
                    last_tick_count = 0,
                    tick_intervals = {} -- Track intervals between ticks for DT detection
                },
                player_state = {
                    in_air = false,
                    crouching = false,
                    running = false,
                    walking = false,
                    standing = false,
                    fake_ducking = false,
                    slow_walking = false
                },
                defensive_aa = {
                    detected = false,
                    animation_breaking = false,
                    rapid_angle_changes = false,
                    sim_time_anomaly = false,
                    break_lc_detected = false,
                    last_detection = 0,
                    confidence = 0.5,
                    correction_angle = CORSA.RESOLVER.DEFENSIVE_AA_CORRECTION_ANGLE
                },
                accuracy = 0, -- 0-1 confidence in resolver accuracy
                last_hit_time = 0,
                last_miss_time = 0,
                last_shot_time = 0,
                last_shot_target = nil,
                last_shot_hitgroup = nil,
                adaptive_correction = {
                    yaw_offset = 0,
                    pitch_offset = 0,
                    success_count = 0,
                    fail_count = 0,
                    last_update = 0,
                    learning_data = {} -- Store learning data for different scenarios
                },
                backtrack_data = {
                    best_tick = 0,
                    best_simulation_time = 0,
                    records = {} -- Store backtrack records
                },
                network_data = {
                    ping = 0,
                    packet_loss = 0,
                    choke = 0,
                    interp_ratio = 2,
                    optimal_backtrack_time = 200 -- Default value, will be adjusted based on ping
                }
            }
        end
        return self.cache[player_index]
    end,

    update = function(self, player_index)
        util.perf_start("player_data:update")
        
        if not entity.is_alive(player_index) and not CORSA.DEBUG then 
            util.perf_end("player_data:update")
            return 
        end
    
        local data = self:get(player_index)
        if not data then 
            util.perf_end("player_data:update")
            return 
        end
    
        local current_time = globals.realtime()
        local current_tick = globals.tickcount()
        if (current_time - data.last_update_time < CORSA.RESOLVER.UPDATE_INTERVAL) and (not CORSA.DEBUG) then 
            util.perf_end("player_data:update")
            return 
        end

        -- Batch property reads for performance
        local pitch = util.get_prop(player_index, "m_angEyeAngles[0]", 0)
        local yaw = util.get_prop(player_index, "m_angEyeAngles[1]", 0)
        local sim_time = util.get_prop(player_index, "m_flSimulationTime", 0)
        local old_sim_time = util.get_prop(player_index, "m_flOldSimulationTime", 0)
        local duck_amount = util.get_prop(player_index, "m_flDuckAmount", 0)
        local vel_x = util.get_prop(player_index, "m_vecVelocity[0]", 0)
        local vel_y = util.get_prop(player_index, "m_vecVelocity[1]", 0)
        local vel_z = util.get_prop(player_index, "m_vecVelocity[2]", 0)
        local pos_x = util.get_prop(player_index, "m_vecOrigin[0]", 0)
        local pos_y = util.get_prop(player_index, "m_vecOrigin[1]", 0)
        local pos_z = util.get_prop(player_index, "m_vecOrigin[2]", 0)
        local flags = util.get_prop(player_index, "m_fFlags", 0)
        local health = util.get_prop(player_index, "m_iHealth", 0)
        
        -- Get player ping and packet loss
        local ping = entity.get_prop(player_index, "m_iPing", 0)
        data.ping = ping
        
        -- Calculate velocity magnitude
        local vel_speed = math.sqrt(vel_x * vel_x + vel_y * vel_y + vel_z * vel_z)

        -- Store data in history buffers
        data.eye_angles_history:push({pitch = pitch, yaw = yaw, time = current_time})
        data.simulation_time_history:push({current = sim_time, old = old_sim_time, time = current_time, tick = current_tick})
        data.duck_amount_history:push(duck_amount)
        data.position_history:push({x = pos_x, y = pos_y, z = pos_z, time = current_time})
        data.velocity_history:push({x = vel_x, y = vel_y, z = vel_z, speed = vel_speed, time = current_time})
        
        -- Store animation layers if available
        local anim_layers = {}
        for i = 0, 13 do -- CS:GO has 13 animation layers
            local weight = entity.get_prop(player_index, "m_flWeight", i)
            local cycle = entity.get_prop(player_index, "m_flCycle", i)
            local sequence = entity.get_prop(player_index, "m_nSequence", i)
            
            if weight and cycle and sequence then
                table.insert(anim_layers, {
                    weight = weight,
                    cycle = cycle,
                    sequence = sequence,
                    layer_index = i
                })
            end
        end
        
        if #anim_layers > 0 then
            data.animation_layers:push({
               layers = anim_layers,
time = current_time
})
end

-- Update network data
data.network_data.ping = ping
data.network_data.choke = globals.chokedcommands()

-- Calculate optimal backtrack time based on ping
if ui.get(ui_elements.network.backtrack_ping_based) then
    local ping_factor = ui.get(ui_elements.network.backtrack_ping_factor) / 100
    data.network_data.optimal_backtrack_time = math.min(400, 100 + ping * ping_factor)
end

-- Calculate optimal interp ratio based on ping
if ui.get(ui_elements.network.adaptive_interp) then
    local min_interp = ui.get(ui_elements.network.interp_min)
    local max_interp = ui.get(ui_elements.network.interp_max)
    local ping_threshold = ui.get(ui_elements.prediction.ping_threshold)
    
    -- Scale interp ratio based on ping
    if ping < ping_threshold then
        data.network_data.interp_ratio = min_interp
    else
        local scale_factor = math.min(1, (ping - ping_threshold) / 100)
        data.network_data.interp_ratio = min_interp + (max_interp - min_interp) * scale_factor
    end
end

-- Update player state
self:update_player_state(player_index, data, flags, vel_speed, duck_amount)

-- Check if player is visible
local local_player = entity.get_local_player()
if util.is_visible(local_player, player_index) then
    data.last_visible_time = current_time
end

-- Enhanced exploit detection
self:detect_exploit(player_index, data, current_time, current_tick)

-- Enhanced fake duck detection
self:enhance_fake_duck_detection(player_index, data)

-- Detect defensive anti-aim with improved detection
self:detect_defensive_aa(player_index, data)

-- Analyze jitter patterns with enhanced detection
self:analyze_jitter_patterns(player_index, data)

-- Analyze desync behavior with improved accuracy
self:analyze_desync(player_index, data)

-- Update adaptive correction based on hit/miss history
self:update_adaptive_correction(player_index, data)

-- Update last update time
data.last_update_time = current_time

util.perf_end("player_data:update")
end,

update_player_state = function(self, player_index, data, flags, vel_speed, duck_amount)
    -- Determine player state based on flags and velocity
    local on_ground = bit.band(flags, 1) == 1
    
    data.player_state.in_air = not on_ground
    data.player_state.crouching = duck_amount > 0.5
    data.player_state.running = on_ground and vel_speed > 150
    data.player_state.walking = on_ground and vel_speed > 5 and vel_speed <= 150
    data.player_state.standing = on_ground and vel_speed <= 5
    data.player_state.fake_ducking = data.is_fake_ducking
    data.player_state.slow_walking = on_ground and vel_speed > 5 and vel_speed < 100 and duck_amount < 0.5
end,

detect_exploit = function(self, player_index, data, current_time, current_tick)
    -- Track tick intervals for more accurate DT detection
    if data.exploit_data.last_tick_count > 0 then
        local tick_diff = current_tick - data.exploit_data.last_tick_count
        if tick_diff > 0 and tick_diff < 10 then -- Reasonable tick difference
            table.insert(data.exploit_data.tick_intervals, tick_diff)
            -- Keep only the last 10 intervals
            if #data.exploit_data.tick_intervals > 10 then
                table.remove(data.exploit_data.tick_intervals, 1)
            end
        end
    end
    data.exploit_data.last_tick_count = current_tick
    
    -- Get simulation time data
    local sim_time = data.simulation_time_history:get_latest()
    local prev_sim = data.simulation_time_history:get(2)
    
    if not sim_time or not prev_sim then
        return false
    end
    
    -- Calculate time deltas
    local sim_delta = sim_time.current - prev_sim.current
    local real_delta = sim_time.time - prev_sim.time
    
    -- Multiple detection methods for exploits
    local exploit_detected = false
    local exploit_type = "none"
    local confidence = 0
    
    -- Method 1: Simulation time anomalies
    if sim_delta > 0 and real_delta > 0 then
        local ratio = sim_delta / real_delta
        
        -- Double tap typically has very low sim/real ratio
        if ratio < 0.3 or sim_delta < CORSA.RESOLVER.EXPLOIT_TIME_ANOMALY then
            exploit_detected = true
            exploit_type = ratio < 0.2 and "dt" or "hs"
            confidence = confidence + 0.4
        end
    end
    
    -- Method 2: Tick interval analysis
    if #data.exploit_data.tick_intervals >= 3 then
        -- Calculate average and variance of tick intervals
        local sum = 0
        for _, interval in ipairs(data.exploit_data.tick_intervals) do
            sum = sum + interval
        end
        local avg_interval = sum / #data.exploit_data.tick_intervals
        
        -- Double tap often has irregular tick intervals
        if avg_interval < 0.8 then
            exploit_detected = true
            exploit_type = "dt"
            confidence = confidence + 0.3
        end
    end
    
    -- Method 3: Position teleporting (common with DT)
    if data.position_history:count() >= 3 then
        local pos1 = data.position_history:get(1)
        local pos2 = data.position_history:get(2)
        
        if pos1 and pos2 and pos1.time and pos2.time then
            local time_diff = pos1.time - pos2.time
            if time_diff > 0 then
                local dist = math.sqrt(
                    (pos1.x - pos2.x)^2 + 
                    (pos1.y - pos2.y)^2 + 
                    (pos1.z - pos2.z)^2
                )
                
                local speed = dist / time_diff
                -- Detect abnormal movement speed (teleporting)
                if speed > 500 and dist > 20 then
                    exploit_detected = true
                    exploit_type = "dt"
                    confidence = confidence + 0.3
                end
            end
        end
    end
    
    -- Method 4: Animation layer analysis
    if data.animation_layers:count() >= 2 then
        local current_anim = data.animation_layers:get(1)
        local prev_anim = data.animation_layers:get(2)
        
        if current_anim and prev_anim and current_anim.layers and prev_anim.layers then
            -- Check for animation anomalies in specific layers
            for i, current_layer in ipairs(current_anim.layers) do
                for j, prev_layer in ipairs(prev_anim.layers) do
                    if current_layer.layer_index == prev_layer.layer_index then
                        -- Check for abnormal cycle changes in movement layers (0, 3, 6)
                        if current_layer.layer_index == 0 or current_layer.layer_index == 3 or current_layer.layer_index == 6 then
                            local cycle_diff = math.abs(current_layer.cycle - prev_layer.cycle)
                            if cycle_diff > 0.5 and cycle_diff < 0.9 then
                                exploit_detected = true
                                exploit_type = "dt"
                                confidence = confidence + 0.2
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Update exploit data
    if exploit_detected then
        data.using_exploit = true
        data.exploit_data.type = exploit_type
        data.exploit_data.confidence = math.min(data.exploit_data.confidence + 0.15, 1.0)
        data.exploit_data.last_detection = current_time
        data.exploit_data.detection_count = data.exploit_data.detection_count + 1
    elseif current_time - data.exploit_data.last_detection > 1.0 then
        -- Decay exploit detection over time
        data.exploit_data.confidence = math.max(data.exploit_data.confidence - 0.05, 0)
        if data.exploit_data.confidence < 0.2 then
            data.using_exploit = false
            data.exploit_data.type = "none"
            data.exploit_data.detection_count = math.max(0, data.exploit_data.detection_count - 1)
        end
    end
    
    return exploit_detected
end,

enhance_fake_duck_detection = function(self, player_index, data)
    local duck_amount = data.duck_amount_history:get_latest() or 0
    local prev_duck = data.duck_amount_history:get(2) or 0
    local flags = util.get_prop(player_index, "m_fFlags", 0)
    
    -- Check for classic fake duck pattern (duck amount stays in a specific range)
    local classic_fd = duck_amount > CORSA.RESOLVER.FAKE_DUCK_THRESHOLD and 
                       duck_amount < CORSA.RESOLVER.FAKE_DUCK_HIGH_VALUE and
                       math.abs(duck_amount - prev_duck) < 0.01
    
    -- Check for animation-breaking fake duck (inconsistent hitbox positions)
    local head_pos = {entity.hitbox_position(player_index, 0)} -- Head hitbox
    local pelvis_pos = {entity.hitbox_position(player_index, 2)} -- Pelvis hitbox
    
    local animation_breaking_fd = false
    if head_pos[1] and pelvis_pos[1] then
        local height_diff = head_pos[3] - pelvis_pos[3]
        local expected_diff = 64 - (duck_amount * 32) -- Approximate height difference
        
        animation_breaking_fd = math.abs(height_diff - expected_diff) > 8 and duck_amount > 0.1
    end
    
    -- Check for micro-movements while ducking (common in fake duck)
    local vel = data.velocity_history:get_latest()
    local micro_movement_fd = vel and vel.speed < CORSA.RESOLVER.FAKE_DUCK_SPEED_THRESHOLD and 
                              vel.speed > 0.1 and duck_amount > 0.1
    
    -- Check animation layers for fake duck patterns
    local anim_layer_fd = false
    if data.animation_layers:count() >= 2 then
        local current_anim = data.animation_layers:get(1)
        local prev_anim = data.animation_layers:get(2)
        
        if current_anim and prev_anim and current_anim.layers and prev_anim.layers then
            -- Look for specific patterns in crouch-related animation layers
            for i, current_layer in ipairs(current_anim.layers) do
                for j, prev_layer in ipairs(prev_anim.layers) do
                    if current_layer.layer_index == prev_layer.layer_index then
                        -- Layer 3 is often related to crouching
                        if current_layer.layer_index == 3 then
                            -- Fake duck often has inconsistent weight changes in this layer
                            local weight_diff = math.abs(current_layer.weight - prev_layer.weight)
                            if weight_diff < 0.05 and duck_amount > 0.1 and duck_amount < 0.9 then
                                anim_layer_fd = true
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Combine detection methods with sensitivity adjustment
    local detection_threshold = ui.get(ui_elements.resolver.fake_duck.detection_threshold) / 100
    local is_fake_ducking = classic_fd or animation_breaking_fd or 
                           (micro_movement_fd and anim_layer_fd) or
                           (classic_fd and micro_movement_fd and detection_threshold > 0.5)
    
    -- Update fake duck data
    data.is_fake_ducking = is_fake_ducking
    data.fake_duck_data = {
        detected = is_fake_ducking,
        classic = classic_fd,
        animation_breaking = animation_breaking_fd,
        micro_movement = micro_movement_fd,
        anim_layer = anim_layer_fd,
        duck_amount = duck_amount,
        confidence = is_fake_ducking and 0.8 or 0.2
    }
    
    -- Update player state
    if data.player_state then
        data.player_state.fake_ducking = is_fake_ducking
    end
    
    return is_fake_ducking
end,

detect_defensive_aa = function(self, player_index, data)
    -- Enhanced defensive AA detection based on Hysteria's methods
    local current_time = globals.realtime()
    
    -- Get current yaw and velocity
    local current_angles = data.eye_angles_history:get_latest()
    local velocity = data.velocity_history:get_latest()
    
    if not current_angles or not velocity then
        return false
    end
    
    local yaw = current_angles.yaw
    local vel_speed = velocity.speed
    
    -- Check for small yaw changes with low velocity (Hysteria's method)
    local is_defensive_static = false
    if data.eye_angles_history:count() >= 3 then
        local prev_angles = data.eye_angles_history:get(2)
        if prev_angles then
            local yaw_diff = math.abs(util.normalize_angle(yaw - prev_angles.yaw))
            if yaw_diff < CORSA.RESOLVER.DEFENSIVE_AA_YAW_THRESHOLD and 
               vel_speed < CORSA.RESOLVER.DEFENSIVE_AA_VELOCITY_THRESHOLD then
                is_defensive_static = true
            end
        end
    end
    
    -- Check for animation inconsistencies
    local eye_pos = {entity.hitbox_position(player_index, 0)} -- Head hitbox
    local pelvis_pos = {entity.hitbox_position(player_index, 2)} -- Pelvis hitbox
    
    if not eye_pos[1] or not pelvis_pos[1] then
        return false
    end
    
    -- Calculate expected head height based on duck amount and player height
    local duck_amount = data.duck_amount_history:get_latest() or 0
    local expected_height_diff = 64 - (duck_amount * 32) -- Approximate height difference between head and pelvis
    local actual_height_diff = eye_pos[3] - pelvis_pos[3]
    
    -- Check for animation breaking (head position inconsistent with body)
    local animation_breaking = math.abs(actual_height_diff - expected_height_diff) > 10
    
    -- Check for rapid angle changes (defensive often uses rapid flicks)
    local rapid_angle_changes = false
    if data.eye_angles_history:count() >= 3 then
        local angles = {}
        for i = 1, 3 do
            table.insert(angles, data.eye_angles_history:get(i))
        end
        
        if angles[1] and angles[2] and angles[3] then
            local diff1 = util.angle_diff(angles[1].yaw, angles[2].yaw)
            local diff2 = util.angle_diff(angles[2].yaw, angles[3].yaw)
            
            -- Defensive AA often has large angle changes followed by small ones
rapid_angle_changes = (diff1 > 50 and diff2 < 10) or (diff1 < 10 and diff2 > 50)
end
end

-- Check for simulation time anomalies (common in defensive)
local sim_time_anomaly = false
if data.simulation_time_history:count() >= 3 then
    local times = {}
    for i = 1, 3 do
        table.insert(times, data.simulation_time_history:get(i))
    end
    
    if times[1] and times[2] and times[3] then
        local diff1 = times[1].current - times[2].current
        local diff2 = times[2].current - times[3].current
        
        -- Defensive often has irregular simulation time updates
        sim_time_anomaly = math.abs(diff1 - diff2) > CORSA.RESOLVER.DEFENSIVE_AA_SIM_TIME_THRESHOLD
    end
end

-- Check for Break LC (Lag Compensation Abuse)
local break_lc_detected = false
if ui.get(ui_elements.resolver.defensive_aa.break_lc_detection) then
    local sim_time = data.simulation_time_history:get_latest()
    local old_sim_time = data.simulation_time_history:get(2)
    
    if sim_time and old_sim_time then
        local sim_diff = math.abs(sim_time.current - old_sim_time.current)
        if sim_diff < CORSA.RESOLVER.DEFENSIVE_AA_SIM_TIME_THRESHOLD then
            break_lc_detected = true
        end
    end
end

-- Check animation layers for defensive patterns
local anim_layer_defensive = false
if data.animation_layers:count() >= 2 then
    local current_anim = data.animation_layers:get(1)
    local prev_anim = data.animation_layers:get(2)
    
    if current_anim and prev_anim and current_anim.layers and prev_anim.layers then
        for i, current_layer in ipairs(current_anim.layers) do
            for j, prev_layer in ipairs(prev_anim.layers) do
                if current_layer.layer_index == prev_layer.layer_index then
                    -- Check upper body and aim layers (5, 6, 8)
                    if current_layer.layer_index == 5 or current_layer.layer_index == 6 or current_layer.layer_index == 8 then
                        local weight_diff = math.abs(current_layer.weight - prev_layer.weight)
                        local cycle_diff = math.abs(current_layer.cycle - prev_layer.cycle)
                        
                        -- Defensive AA often has sudden changes in these layers
                        if (weight_diff > 0.7 or cycle_diff > 0.7) and cycle_diff < 0.95 then
                            anim_layer_defensive = true
                        end
                    end
                end
            end
        end
    end
end

-- Combine factors to determine if defensive AA is being used
local detection_threshold = ui.get(ui_elements.resolver.defensive_aa.detection_threshold) / 100
local is_defensive = (is_defensive_static and (animation_breaking or sim_time_anomaly)) or
                     (rapid_angle_changes and (animation_breaking or sim_time_anomaly)) or
                     (anim_layer_defensive and (rapid_angle_changes or sim_time_anomaly)) or
                     break_lc_detected

-- Apply confidence based on detection strength
local confidence = 0.5
if is_defensive then
    confidence = 0.7
    if break_lc_detected then
        confidence = 0.9 -- Very high confidence if break LC is detected
    elseif is_defensive_static and animation_breaking and sim_time_anomaly then
        confidence = 0.85 -- High confidence if multiple indicators
    end
end

-- Store defensive AA data
data.defensive_aa = {
    detected = is_defensive,
    animation_breaking = animation_breaking,
    rapid_angle_changes = rapid_angle_changes,
    sim_time_anomaly = sim_time_anomaly,
    break_lc_detected = break_lc_detected,
    last_detection = is_defensive and current_time or data.defensive_aa.last_detection or 0,
    confidence = confidence,
    correction_angle = ui.get(ui_elements.resolver.defensive_aa.correction_angle)
}

-- Update player state
if data.player_state then
    data.player_state.defensive = is_defensive
end

return is_defensive
end,

analyze_jitter_patterns = function(self, player_index, data)
    util.perf_start("analyze_jitter_patterns")
    
    if not data.eye_angles_history or data.eye_angles_history:count() < 4 then
        util.perf_end("analyze_jitter_patterns")
        return
    end
    
    local angles = {}
    for i = 1, math.min(10, data.eye_angles_history:count()) do
        local angle = data.eye_angles_history:get(i)
        if angle and angle.yaw then
            table.insert(angles, angle.yaw)
        end
    end
    
    if #angles < 4 then
        util.perf_end("analyze_jitter_patterns")
        return
    end
    
    -- Calculate angle differences
    local diffs = {}
    for i = 2, #angles do
        table.insert(diffs, util.normalize_angle(angles[i-1] - angles[i]))
    end
    
    -- Detect jitter based on angle changes
    local is_jittering = false
    local jitter_range = 0
    local max_diff = 0
    
    for _, diff in ipairs(diffs) do
        max_diff = math.max(max_diff, math.abs(diff))
        if math.abs(diff) > CORSA.RESOLVER.JITTER_THRESHOLD then
            is_jittering = true
        end
    end
    
    -- Calculate jitter range
    if is_jittering then
        local sorted_angles = {}
        for _, angle in ipairs(angles) do
            table.insert(sorted_angles, angle)
        end
        table.sort(sorted_angles)
        jitter_range = sorted_angles[#sorted_angles] - sorted_angles[1]
        
        -- Normalize jitter range to be within 0-180
        if jitter_range > 180 then
            jitter_range = 360 - jitter_range
        end
    end
    
    -- Detect jitter frequency
    local current_time = globals.realtime()
    local jitter_frequency = 0
    
    if is_jittering and #diffs >= 2 then
        local direction_changes = 0
        local last_sign = nil
        
        for i, diff in ipairs(diffs) do
            local sign = diff > 0 and 1 or -1
            if last_sign and sign ~= last_sign then
                direction_changes = direction_changes + 1
            end
            last_sign = sign
        end
        
        -- Calculate frequency based on direction changes and time span
        local time_span = 0
        local first_angle = data.eye_angles_history:get(1)
        local last_angle = data.eye_angles_history:get(math.min(#angles, data.eye_angles_history:count()))
        
        if first_angle and last_angle and first_angle.time and last_angle.time then
            time_span = first_angle.time - last_angle.time
        end
        
        if time_span > 0 then
            jitter_frequency = direction_changes / time_span
        end
        
        -- Update last flip time if we detected a direction change
        if direction_changes > 0 then
            if not data.jitter_data then
                data.jitter_data = {}
            end
            data.jitter_data.last_flip_time = current_time
        end
    end
    
    -- Detect jitter pattern
    local pattern = "unknown"
    
    -- Check for switch pattern (alternating between two angles)
    local is_switch = true
    for i = 3, #angles do
        if math.abs(util.normalize_angle(angles[i] - angles[i-2])) > 10 then
            is_switch = false
            break
        end
    end
    
    -- Check for random pattern
    local is_random = true
    local sorted_diffs = {}
    for _, diff in ipairs(diffs) do
        table.insert(sorted_diffs, math.abs(diff))
    end
    table.sort(sorted_diffs)
    
    -- Random pattern has varied differences
    if #sorted_diffs >= 3 and sorted_diffs[#sorted_diffs] - sorted_diffs[1] < 15 then
        is_random = false
    end
    
    -- Check for cycle pattern (repeating sequence)
    local is_cycle = false
    local cycle_length = 0
    
    for len = 2, math.min(4, math.floor(#angles / 2)) do
        local matches = true
        for i = 1, len do
            if i+len <= #angles and math.abs(util.normalize_angle(angles[i] - angles[i+len])) > 10 then
                matches = false
                break
            end
        end
        if matches then
            is_cycle = true
            cycle_length = len
            break
        end
    end
    
    -- Check for spin pattern
    local is_spin = true
    local spin_direction = 0
    
    if #diffs >= 3 then
        local first_diff_sign = diffs[1] > 0 and 1 or -1
        for i = 2, #diffs do
            local diff_sign = diffs[i] > 0 and 1 or -1
            if diff_sign ~= first_diff_sign or math.abs(diffs[i]) < 10 then
                is_spin = false
                break
            end
        end
        if is_spin then
            spin_direction = first_diff_sign
        end
    end
    
    -- Determine pattern
    if is_switch then
        pattern = "switch"
    elseif is_cycle then
        pattern = "cycle-" .. cycle_length
    elseif is_spin then
        pattern = "spin-" .. (spin_direction > 0 and "right" or "left")
    elseif is_random and is_jittering then
        pattern = "random"
    elseif max_diff < CORSA.RESOLVER.JITTER_THRESHOLD then
        pattern = "static"
    end
    
    -- Calculate confidence based on pattern consistency
    local confidence = 0.5
    if is_switch or is_cycle then
        confidence = 0.8 -- High confidence for predictable patterns
    elseif is_spin then
        confidence = 0.7 -- Good confidence for spin
    elseif is_random then
        confidence = 0.4 -- Lower confidence for random patterns
    elseif pattern == "static" then
        confidence = 0.9 -- Very high confidence for static angles
    end
    
    -- Initialize jitter_data if it doesn't exist
    if not data.jitter_data then
        data.jitter_data = {
            last_flip_time = current_time
        }
    end
    
    -- Update jitter data
    data.jitter_data = {
        detected = is_jittering,
        range = jitter_range,
        frequency = jitter_frequency,
        last_flip_time = data.jitter_data.last_flip_time or current_time,
        pattern = pattern,
        max_diff = max_diff,
        confidence = confidence
    }
    
    util.perf_end("analyze_jitter_patterns")
    return is_jittering
end,

analyze_desync = function(self, player_index, data)
    util.perf_start("analyze_desync")
    
    local current_time = globals.realtime()
    if current_time - (data.desync_data.last_update or 0) < 0.03 then
        util.perf_end("analyze_desync")
        return
    end
    
    -- Get player's eye position and angles
    local eye_pos = {entity.hitbox_position(player_index, 0)} -- Head hitbox
    if not eye_pos[1] then
        util.perf_end("analyze_desync")
        return
    end
    
    local current_angles = data.eye_angles_history:get_latest()
    if not current_angles then
        util.perf_end("analyze_desync")
        return
    end
    
    -- Calculate forward vector based on player's yaw
    local rad_yaw = math.rad(current_angles.yaw)
    local forward_x = math.cos(rad_yaw)
    local forward_y = math.sin(rad_yaw)
    
    -- Check for visibility on both sides of the player with multiple points
    local local_player = entity.get_local_player()
    local left_visible_count = 0
    local right_visible_count = 0
    local total_checks = 3 -- Check multiple points along the side
    
    -- Check multiple points on left side
    for i = 1, total_checks do
        local offset_multiplier = 15 + (i * 5) -- Increasing distance from center
        local left_pos = {
            eye_pos[1] + forward_y * offset_multiplier,
            eye_pos[2] - forward_x * offset_multiplier,
            eye_pos[3] - (i == 1 and 0 or 5) -- Check different heights
        }
        
        local left_fraction, left_entity = client.trace_line(local_player, 
            eye_pos[1], eye_pos[2], eye_pos[3],
            left_pos[1], left_pos[2], left_pos[3])
        
        if left_fraction > 0.95 or left_entity == player_index then
            left_visible_count = left_visible_count + 1
        end
    end
    
    -- Check multiple points on right side
    for i = 1, total_checks do
        local offset_multiplier = 15 + (i * 5)
        local right_pos = {
            eye_pos[1] - forward_y * offset_multiplier,
            eye_pos[2] + forward_x * offset_multiplier,
            eye_pos[3] - (i == 1 and 0 or 5)
        }
        
        local right_fraction, right_entity = client.trace_line(local_player, 
            eye_pos[1], eye_pos[2], eye_pos[3],
            right_pos[1], right_pos[2], right_pos[3])
        
        if right_fraction > 0.95 or right_entity == player_index then
            right_visible_count = right_visible_count + 1
        end
    end
    
    -- Calculate visibility ratios
    local left_visibility = left_visible_count / total_checks
    local right_visibility = right_visible_count / total_checks
    
    -- Determine desync side based on visibility with more aggressive thresholds
    local desync_side = 0
    local desync_amount = 0
    local confidence = 0.5
    
    if left_visibility > 0.5 and left_visibility > right_visibility * 1.5 then
        -- Left side much more visible, desync to right
        desync_side = -1
        desync_amount = CORSA.RESOLVER.MAX_DESYNC_ANGLE * (0.8 + (left_visibility - right_visibility) * 0.4)
        confidence = 0.7 + (left_visibility - right_visibility) * 0.3
    elseif right_visibility > 0.5 and right_visibility > left_visibility * 1.5 then
        -- Right side much more visible, desync to left
        desync_side = 1
        desync_amount = CORSA.RESOLVER.MAX_DESYNC_ANGLE * (0.8 + (right_visibility - left_visibility) * 0.4)
confidence = 0.7 + (right_visibility - left_visibility) * 0.3
else
    -- Use additional heuristics for more aggressive detection
    
    -- 1. Check player animations (duck/crouch state changes)
    local duck_amount = data.duck_amount_history:get_latest() or 0
    local prev_duck = data.duck_amount_history:get(2) or 0
    local duck_changing = math.abs(duck_amount - prev_duck) > 0.05
    
    -- 2. Check recent angle changes for micro-adjustments (common in anti-aim)
    local angle_history_size = math.min(5, data.eye_angles_history:count())
    local has_micro_adjustments = false
    local last_angle = nil
    
    for i = 1, angle_history_size do
        local angle = data.eye_angles_history:get(i)
        if angle and last_angle then
            local diff = util.angle_diff(angle.yaw, last_angle.yaw)
            if diff > 0.5 and diff < 15 then
                has_micro_adjustments = true
                break
            end
        end
        last_angle = angle
    end
    
    -- 3. Check velocity for strafing patterns
    local vel = data.velocity_history:get_latest()
    local prev_vel = data.velocity_history:get(2)
    local strafing = false
    
    if vel and prev_vel and vel.speed > 1.0 then
        local vel_angle_current = math.deg(math.atan2(vel.y, vel.x))
        local vel_angle_prev = math.deg(math.atan2(prev_vel.y, prev_vel.x))
        local vel_angle_diff = util.angle_diff(vel_angle_current, vel_angle_prev)
        strafing = vel_angle_diff > 15
    end
    
    -- 4. Check animation layers for desync clues
    local anim_layer_desync_side = 0
    if data.animation_layers:count() >= 2 then
        local current_anim = data.animation_layers:get(1)
        
        if current_anim and current_anim.layers then
            for _, layer in ipairs(current_anim.layers) do
                -- Layer 2 often indicates desync side
                if layer.layer_index == 2 then
                    -- Weight > 0.55 often indicates right desync
                    if layer.weight > 0.55 then
                        anim_layer_desync_side = 1
                    -- Weight < 0.45 often indicates left desync
                    elseif layer.weight < 0.45 then
                        anim_layer_desync_side = -1
                    end
                end
            end
        end
    end
    
    -- Combine heuristics for more aggressive detection
    if vel and vel.speed > 1.0 then
        -- Moving players: use velocity direction as primary indicator
        local movement_yaw = math.deg(math.atan2(vel.y, vel.x))
        local angle_diff = util.normalize_angle(movement_yaw - current_angles.yaw)
        
        -- More aggressive side detection for moving players
        if angle_diff > 0 then
            desync_side = 1 -- Moving right relative to view, likely desync left
        else
            desync_side = -1 -- Moving left relative to view, likely desync right
        end
        
        -- Adjust desync amount based on speed and strafing
        local speed_factor = math.min(1.0, vel.speed / 250)
        local base_amount = CORSA.RESOLVER.MAX_DESYNC_ANGLE * (1 - speed_factor * 0.2) -- Less reduction for speed
        
        -- Increase amount for strafing players (they often use max desync)
        if strafing then
            base_amount = math.min(CORSA.RESOLVER.MAX_DESYNC_ANGLE, base_amount * 1.2)
        end
        
        desync_amount = base_amount
        confidence = 0.6 - (speed_factor * 0.2) + (strafing and 0.2 or 0)
        
        -- If animation layer suggests a different side with high confidence, consider it
        if anim_layer_desync_side ~= 0 and anim_layer_desync_side ~= desync_side then
            -- Blend the two predictions
            if math.random() > 0.7 then  -- 30% chance to use animation layer prediction
                desync_side = anim_layer_desync_side
                confidence = 0.65
            end
        end
    else
        -- Standing players: use micro-adjustments and duck state
        
        -- If we have previous side data, maintain it with higher confidence
        if data.desync_data.side ~= 0 then
            -- Keep the side but potentially flip if we see evidence
            desync_side = data.desync_data.side
            
            -- Micro-adjustments often indicate real angle vs. fake
            if has_micro_adjustments then
                -- Increase confidence and amount for detected micro-adjustments
                desync_amount = math.min(CORSA.RESOLVER.MAX_DESYNC_ANGLE * 1.1, 60)
                confidence = 0.75
            else
                -- Maintain previous data with slight decay
                desync_amount = math.min(data.desync_data.amount, CORSA.RESOLVER.MAX_DESYNC_ANGLE)
                confidence = math.max(0.4, (data.desync_data.confidence or 0.5) * 0.95)
            end
            
            -- Duck changing often indicates desync flip
            if duck_changing then
                -- Potentially flip the side if duck state is changing
                if math.random() > 0.5 then -- 50% chance to flip on duck change
                    desync_side = desync_side * -1
                end
                confidence = 0.6 -- Medium confidence on duck change
            end
            
            -- Animation layer can provide additional evidence
            if anim_layer_desync_side ~= 0 then
                if anim_layer_desync_side == desync_side then
                    -- Animation confirms our prediction, increase confidence
                    confidence = math.min(0.9, confidence + 0.15)
                else 
                    if math.random() > 0.7 then
                        -- Animation contradicts, occasionally flip
                        desync_side = anim_layer_desync_side
                        confidence = 0.65
                    end
                end
            end
        else
            -- No previous data, make an aggressive guess
            if anim_layer_desync_side ~= 0 then
                desync_side = anim_layer_desync_side
                confidence = 0.6
            else
                desync_side = math.random() > 0.5 and 1 or -1
                confidence = 0.4 -- Lower confidence for initial guess
            end
            desync_amount = CORSA.RESOLVER.MAX_DESYNC_ANGLE * 0.9
        end
    end
    
    -- If player is using exploits, be more aggressive
    if data.using_exploit then
        desync_amount = CORSA.RESOLVER.MAX_DESYNC_ANGLE * 1.1
        confidence = 0.8
    end
end

-- Apply correction based on hit/miss history
if data.shot_history:count() > 0 then
    local hit_count = 0
    local miss_count = 0
    local recent_shots = math.min(5, data.shot_history:count())
    
    for i = 1, recent_shots do
        local shot = data.shot_history:get(i)
        if shot then
            if shot.hit then
                hit_count = hit_count + 1
            else
                miss_count = miss_count + 1
            end
        end
    end
    
    -- If we're missing a lot, try flipping the desync side
    if miss_count >= 3 and hit_count == 0 and math.random() > 0.7 then
        desync_side = desync_side * -1
        confidence = 0.5 -- Medium confidence after flip
    end
    
    -- If we're hitting consistently, increase confidence
    if hit_count > miss_count then
        confidence = math.min(0.9, confidence + 0.1)
    end
end

-- Store desync history for pattern recognition
if desync_side ~= 0 then
    table.insert(data.desync_data.history, {
        side = desync_side,
        time = current_time
    })
    
    -- Keep history at a reasonable size
    if #data.desync_data.history > 10 then
        table.remove(data.desync_data.history, 1)
    end
    
    -- Check for patterns in desync side changes
    if #data.desync_data.history >= 3 then
        local pattern_detected = true
        local first_side = data.desync_data.history[1].side
        
        for i = 3, #data.desync_data.history, 2 do
            if data.desync_data.history[i].side ~= first_side then
                pattern_detected = false
                break
            end
        end
        
        if pattern_detected then
            -- If we detect a pattern, increase confidence
            confidence = math.min(0.95, confidence + 0.1)
        end
    end
end

-- Ensure desync amount is within reasonable bounds
desync_amount = util.clamp(desync_amount, 0, 60)

-- Update desync data
data.desync_data = {
    side = desync_side,
    amount = desync_amount,
    last_update = current_time,
    confidence = confidence,
    left_visibility = left_visibility,
    right_visibility = right_visibility,
    history = data.desync_data.history or {}
}

util.perf_end("analyze_desync")
return desync_side ~= 0
end,

update_adaptive_correction = function(self, player_index, data)
    local current_time = globals.realtime()
    
    -- Only update periodically
    if current_time - (data.adaptive_correction.last_update or 0) < 0.5 then
        return
    end
    
    -- Need shot history to adapt
    if not data.shot_history or data.shot_history:count() < 2 then
        return
    end
    
    -- Analyze recent shots to determine if our corrections are working
    local recent_shots = math.min(5, data.shot_history:count())
    local hit_count = 0
    local miss_count = 0
    
    for i = 1, recent_shots do
        local shot = data.shot_history:get(i)
        if shot then
            if shot.hit then
                hit_count = hit_count + 1
            else
                miss_count = miss_count + 1
            end
        end
    end
    
    -- Calculate hit ratio
    local total_shots = hit_count + miss_count
    local hit_ratio = total_shots > 0 and hit_count / total_shots or 0
    
    -- Update accuracy metric
    data.accuracy = hit_ratio
    
    -- Get learning rate from UI
    local learning_rate = ui.get(ui_elements.resolver.adaptive.learning_rate) / 100
    
    -- Adjust correction based on hit ratio
    if hit_ratio > 0.7 then
        -- High success rate, maintain current correction
        data.adaptive_correction.success_count = (data.adaptive_correction.success_count or 0) + 1
        data.adaptive_correction.fail_count = 0
        
        -- Store successful settings for this player state
        local state_key = self:get_player_state_key(data.player_state)
        data.adaptive_correction.learning_data[state_key] = {
            desync_side = data.desync_data.side,
            desync_amount = data.desync_data.amount,
            yaw_offset = data.adaptive_correction.yaw_offset,
            pitch_offset = data.adaptive_correction.pitch_offset,
            hit_ratio = hit_ratio,
            last_update = current_time
        }
    elseif hit_ratio < 0.3 then
        -- Low success rate, adjust correction
        data.adaptive_correction.fail_count = (data.adaptive_correction.fail_count or 0) + 1
        data.adaptive_correction.success_count = 0
        
        -- After multiple failures, try a different approach
        if (data.adaptive_correction.fail_count or 0) >= 3 then
            -- Try to load successful settings for this player state
            local state_key = self:get_player_state_key(data.player_state)
            local learned_data = data.adaptive_correction.learning_data[state_key]
            
            if learned_data and learned_data.hit_ratio > 0.7 and current_time - learned_data.last_update < 30 then
                -- Use previously successful settings
                data.desync_data.side = learned_data.desync_side
                data.desync_data.amount = learned_data.desync_amount
                data.adaptive_correction.yaw_offset = learned_data.yaw_offset
                data.adaptive_correction.pitch_offset = learned_data.pitch_offset
            else
                -- Flip desync side if we're consistently missing
                if data.desync_data.side ~= 0 then
                    data.desync_data.side = data.desync_data.side * -1
                    data.desync_data.confidence = 0.5 -- Reset confidence after flip
                end
                
                -- Try a different yaw offset
                local current_offset = data.adaptive_correction.yaw_offset or 0
                local new_offset = 0
                
                if current_offset == 0 then
                    new_offset = 35 -- Try a significant offset
                elseif current_offset > 0 then
                    new_offset = -current_offset -- Try the opposite direction
                else
                    new_offset = -current_offset * 0.5 -- Try a smaller offset in the opposite direction
                end
                
                data.adaptive_correction.yaw_offset = new_offset
            end
            
            data.adaptive_correction.fail_count = 0
        end
    else
        -- Medium success rate, make minor adjustments
        if (data.adaptive_correction.yaw_offset or 0) ~= 0 then
            -- Gradually reduce offset if we're having moderate success
            data.adaptive_correction.yaw_offset = (data.adaptive_correction.yaw_offset or 0) * 0.9
        end
    end
    
    -- Also adjust pitch correction if needed
    if hit_ratio < 0.3 and (data.adaptive_correction.fail_count or 0) >= 2 then
        -- Try a small pitch correction if we're missing a lot
        if (data.adaptive_correction.pitch_offset or 0) == 0 then
            data.adaptive_correction.pitch_offset = math.random() > 0.5 and 5 or -5
        else
            data.adaptive_correction.pitch_offset = -(data.adaptive_correction.pitch_offset or 0)
        end
    elseif hit_ratio > 0.7 then
        -- Reset pitch correction if we're hitting well
        data.adaptive_correction.pitch_offset = 0
    end
    
    -- Apply the adaptive corrections to the correction factor
    data.correction_factor.yaw = (data.adaptive_correction.yaw_offset or 0)
    data.correction_factor.pitch = (data.adaptive_correction.pitch_offset or 0)
    
    -- Update timestamp
    data.adaptive_correction.last_update = current_time
end,

get_player_state_key = function(self, player_state)
    -- Create a unique key based on player state
    local key = ""
    if player_state.in_air then
        key = key .. "air_"
    else
        key = key .. "ground_"
    end
    
    if player_state.crouching then
        key = key .. "crouch_"
    elseif player_state.fake_ducking then
        key = key .. "fakeduck_"
    else
        key = key .. "stand_"
    end
    
    if player_state.running then
        key = key .. "run"
    elseif player_state.walking then
        key = key .. "walk"
    elseif player_state.slow_walking then
        key = key .. "slowwalk"
    else
        key = key .. "still"
    end
    
    if player_state.defensive then
        key = key .. "_defensive"
    end
    
    return key
end,

reset = function(self)
    self.cache = {}
    util.log(CORSA.COLORS.SUCCESS[1], CORSA.COLORS.SUCCESS[2], CORSA.COLORS.SUCCESS[3], 
        "Player data cache reset")
end,

cleanup = function(self)
    local current_time = globals.realtime()
    local removed = 0
    
    for player_index, data in pairs(self.cache) do
        if current_time - data.last_update_time > CORSA.PERFORMANCE.STALE_DATA_THRESHOLD then
            self.cache[player_index] = nil
            removed = removed + 1
        end
    end
    
    if removed > 0 and CORSA.DEBUG then
        util.debug(string.format("Cleaned up %d stale player data entries", removed))
    end
end
}

-- Resolver implementation (enhanced)
local resolver = {
    last_update_time = 0,
    last_visual_update_time = 0,
    active_players = {},
    hit_markers = {},
    tracers = {},
    resolved_hitboxes = {},
    
    update = function(self)
        util.perf_start("resolver:update")
        
        local current_time = globals.realtime()
        if current_time - self.last_update_time < CORSA.RESOLVER.UPDATE_INTERVAL then
            util.perf_end("resolver:update")
            return
        end
        
        -- Only run if enabled
        if not ui.get(ui_elements.resolver.enabled) then
            util.perf_end("resolver:update")
            return
        end
        
        -- Update debug mode
        CORSA.DEBUG = ui.get(ui_elements.resolver.debug_mode)
        
        -- Get all players
        local players = entity.get_players(true) -- Only enemies
        self.active_players = {}
        
        -- Update player data
        for _, player_index in ipairs(players) do
            if entity.is_alive(player_index) then
                table.insert(self.active_players, player_index)
                player_data:update(player_index)
            end
        end
        
        -- Apply resolver logic
        for _, player_index in ipairs(self.active_players) do
            self:resolve_player(player_index)
        end
        
        -- Update backtrack data if enabled
        if ui.get(ui_elements.resolver.backtrack_enabled) then
            self:update_backtrack()
        end
        
        -- Cleanup stale data periodically
        if globals.tickcount() % CORSA.PERFORMANCE.CLEANUP_INTERVAL == 0 then
            player_data:cleanup()
        end
        
        -- Update network settings
        self:update_network_settings()
        
        self.last_update_time = current_time
        util.perf_end("resolver:update")
    end,
    
    resolve_player = function(self, player_index)
        util.perf_start("resolver:resolve_player")
        
        local data = player_data:get(player_index)
        if not data then
            util.perf_end("resolver:resolve_player")
            return
        end
        
        -- Store previous resolved angles for comparison
        data.last_resolved_angles = util.table_copy(data.resolved_angles or {pitch = 0, yaw = 0})
        
        -- Get current angles
        local current_angles = data.eye_angles_history:get_latest()
        if not current_angles then
            util.perf_end("resolver:resolve_player")
            return
        end
        
        -- Initialize resolved angles with current angles
        local resolved_angles = {
            pitch = current_angles.pitch,
            yaw = current_angles.yaw
        }
        
        -- Apply player-specific settings if enabled
        local use_player_specific = false
        local player_specific_mode = "Auto"
        local correction_strength = 1.0
        
        if ui.get(ui_elements.player_specific.enabled) then
            -- TODO: Implement player-specific settings lookup
            -- This would check if we have custom settings for this player
        end
        
        -- Determine which resolver methods to use
        local use_jitter = ui.get(ui_elements.resolver.jitter.enabled) and (player_specific_mode == "Auto" or player_specific_mode == "Jitter")
        local use_desync = ui.get(ui_elements.resolver.desync.enabled) and (player_specific_mode == "Auto" or player_specific_mode == "Desync")
        local use_fake_duck = ui.get(ui_elements.resolver.fake_duck.enabled) and (player_specific_mode == "Auto" or player_specific_mode == "Fake Duck")
        local use_exploit = ui.get(ui_elements.resolver.exploit.enabled) and (player_specific_mode == "Auto" or player_specific_mode == "Exploit")
        local use_defensive = ui.get(ui_elements.resolver.defensive_aa.enabled) and (player_specific_mode == "Auto" or player_specific_mode == "Defensive AA")
        local use_adaptive = ui.get(ui_elements.resolver.adaptive.enabled)
        
        -- Apply correction based on player state and detected anti-aim
        local applied_correction = false
        local correction_confidence = 0.5
        local correction_source = "none"
        
        -- 1. Handle defensive anti-aim (highest priority)
        if use_defensive and data.defensive_aa and data.defensive_aa.detected then
            -- Apply defensive AA correction
            local correction_angle = data.defensive_aa.correction_angle or CORSA.RESOLVER.DEFENSIVE_AA_CORRECTION_ANGLE
            
            -- Determine correction direction based on detection confidence
            local correction_dir = 1
            if data.desync_data and data.desync_data.side ~= 0 then
                correction_dir = data.desync_data.side
            else
                correction_dir = math.random() > 0.5 and 1 or -1
            end
            
            resolved_angles.yaw = resolved_angles.yaw + (correction_angle * correction_dir * correction_strength)
            applied_correction = true
            correction_confidence = data.defensive_aa.confidence or 0.7
            correction_source = "defensive"
        end
        
        -- 2. Handle fake duck
        if not applied_correction and use_fake_duck and data.is_fake_ducking then
            -- Apply fake duck correction
            local correction_dir = 1
            if data.desync_data and data.desync_data.side ~= 0 then
                correction_dir = data.desync_data.side
            else
                correction_dir = math.random() > 0.5 and 1 or -1
            end
            
            resolved_angles.yaw = resolved_angles.yaw + (45 * correction_dir * correction_strength)
            applied_correction = true
            correction_confidence = data.fake_duck_data and data.fake_duck_data.confidence or 0.6
            correction_source = "fake_duck"
        end
        
        -- 3. Handle exploits
        if not applied_correction and use_exploit and data.using_exploit then
            -- Apply exploit correction
            local exploit_mode = ui.get(ui_elements.resolver.exploit.mode)
            local correction_angle = 35 -- Default
            
            if exploit_mode == "Aggressive" then
                correction_angle = 58
            elseif exploit_mode == "Conservative" then
                correction_angle = 25
            elseif exploit_mode == "Defensive-AA" then
                correction_angle = 60
            end
            
            -- Determine correction direction
            local correction_dir = 1
            if data.desync_data and data.desync_data.side ~= 0 then
                correction_dir = data.desync_data.side
            else
                correction_dir = math.random() > 0.5 and 1 or -1
            end
            
            resolved_angles.yaw = resolved_angles.yaw + (correction_angle * correction_dir * correction_strength)
            applied_correction = true
            correction_confidence = data.exploit_data and data.exploit_data.confidence or 0.6
            correction_source = "exploit"
        end
        
        -- 4. Handle jitter
        if not applied_correction and use_jitter and data.jitter_data and data.jitter_data.detected then
            -- Apply jitter correction based on pattern
            local jitter_mode = ui.get(ui_elements.resolver.jitter.mode)
            local jitter_strength = ui.get(ui_elements.resolver.jitter.strength) / 100
            local pattern = data.jitter_data.pattern or "unknown"
            local range = data.jitter_data.range or 0
            
            if pattern == "switch" then
                -- For switch pattern, predict the next angle
                local last_flip_time = data.jitter_data.last_flip_time or 0
                local current_time = globals.realtime()
                local time_since_flip = current_time - last_flip_time
                local frequency = data.jitter_data.frequency or 1
                
                -- Predict if we're due for a flip
                if frequency > 0 and time_since_flip > (1 / frequency) * 0.8 then
                    -- Likely to flip soon, use opposite of current
                    resolved_angles.yaw = resolved_angles.yaw + (range * jitter_strength * correction_strength)
                end
            elseif pattern == "random" then
                -- For random pattern, use a statistical approach
                resolved_angles.yaw = resolved_angles.yaw + (range * 0.5 * jitter_strength * correction_strength)
            elseif pattern:find("cycle") then
                -- For cycle pattern, try to predict the next in sequence
                -- This is simplified; a real implementation would track the full cycle
                resolved_angles.yaw = resolved_angles.yaw + (range * 0.5 * jitter_strength * correction_strength)
            elseif pattern:find("spin") then
                -- For spin pattern, predict continued rotation
                local spin_dir = pattern:find("right") and 1 or -1
                resolved_angles.yaw = resolved_angles.yaw + (30 * spin_dir * jitter_strength * correction_strength)
            end
            
            applied_correction = true
            correction_confidence = data.jitter_data.confidence or 0.5
            correction_source = "jitter"
        end
        
        -- 5. Handle desync
        if not applied_correction and use_desync and data.desync_data and data.desync_data.side ~= 0 then
            -- Apply desync correction
            local desync_mode = ui.get(ui_elements.resolver.desync.mode)
            local side = data.desync_data.side
            local amount = data.desync_data.amount or CORSA.RESOLVER.MAX_DESYNC_ANGLE
            
            if desync_mode == "Brute Force" then
                -- Alternate between max left and right
                side = globals.tickcount() % 2 == 0 and 1 or -1
                amount = CORSA.RESOLVER.MAX_DESYNC_ANGLE
            elseif desync_mode == "Velocity-Based" then
                -- Adjust amount based on velocity
                local vel = data.velocity_history:get_latest()
                if vel and vel.speed > 0 then
                    amount = amount * (1 - math.min(1, vel.speed / 250) * 0.3)
                end
            end
            
            resolved_angles.yaw = resolved_angles.yaw + (amount * side * correction_strength)
            applied_correction = true
            correction_confidence = data.desync_data.confidence or 0.5
            correction_source = "desync"
        end
        
        -- 6. Apply adaptive corrections
        if use_adaptive then
            -- Apply learned corrections from hit/miss history
            if data.correction_factor then
                resolved_angles.yaw = resolved_angles.yaw + (data.correction_factor.yaw or 0)
                resolved_angles.pitch = resolved_angles.pitch + (data.correction_factor.pitch or 0)
                
                if not applied_correction then
                    applied_correction = (data.correction_factor.yaw or 0) ~= 0 or (data.correction_factor.pitch or 0) ~= 0
                    correction_source = "adaptive"
                    correction_confidence = data.accuracy or 0.5
                end
            end
        end
        
        -- Normalize angles
        resolved_angles.yaw = util.normalize_angle(resolved_angles.yaw)
        resolved_angles.pitch = util.clamp(resolved_angles.pitch, -89, 89)
        
        -- Store resolved angles and metadata
        data.resolved_angles = resolved_angles
        data.resolver_metadata = {
            applied_correction = applied_correction,
            correction_source = correction_source,
            confidence = correction_confidence,
            original_yaw = current_angles.yaw,
            correction_amount = util.angle_diff(resolved_angles.yaw, current_angles.yaw)
        }
        
        -- Apply the resolved angles
        self:apply_resolved_angles(player_index, resolved_angles)
        
        util.perf_end("resolver:resolve_player")
        return resolved_angles
    end,
    
    apply_resolved_angles = function(self, player_index, resolved_angles)
        -- Apply the resolved angles to the player
        -- This is where we would hook into the game's angle processing
        
        -- In some CS:GO cheats, this might involve setting a global variable
        -- or calling a native function that the cheat's aim assistance will use
        
        -- For demonstration, we'll just log the resolved angles
        if CORSA.DEBUG then
            util.debug(string.format("Applied resolved angles to player %d: pitch=%.1f, yaw=%.1f", 
                player_index, resolved_angles.pitch, resolved_angles.yaw))
        end
    end,
    



update_backtrack = function(self)
    util.perf_start("resolver:update_backtrack")
    
    local backtrack_time = ui.get(ui_elements.resolver.backtrack_time)
    
    for _, player_index in ipairs(self.active_players) do
        local data = player_data:get(player_index)
        if not data then goto continue end
        
        -- Use ping-based backtrack time if enabled
        if ui.get(ui_elements.network.backtrack_ping_based) then
            backtrack_time = data.network_data.optimal_backtrack_time or backtrack_time
        end
        
        -- Calculate optimal backtrack ticks with network compensation
        local server_tick_rate = 64 -- Assume 64 tick
        local lerp_time = util.get_lerp_time() * 1000 -- Convert to ms
        local latency = client.latency() * 1000 -- Convert to ms
        
        -- Adjust backtrack window based on network conditions
        local effective_backtrack = math.min(backtrack_time, 200) -- Cap at 200ms for stability
        local max_ticks = math.min(CORSA.RESOLVER.BACKTRACK_MAX_TICKS, math.floor(effective_backtrack / (1000 / server_tick_rate)))
        
        -- Clear old records
        data.backtrack_data.records = {}
        
        -- Store current record
        local current_time = globals.realtime()
        local current_tick = globals.tickcount()
        
        -- Create backtrack records with improved validation
        for i = 1, math.min(data.simulation_time_history:count(), max_ticks) do
            local record = data.simulation_time_history:get(i)
            if not record then goto continue_inner end
            
            local position = data.position_history:get(i)
            if not position then goto continue_inner end
            
            -- Calculate time difference with network compensation
            local time_diff = current_time - record.time
            if time_diff > effective_backtrack / 1000 then goto continue_inner end
            
            -- Validate record (check if position is reasonable)
            if position.x == 0 and position.y == 0 and position.z == 0 then
                goto continue_inner -- Skip invalid positions
            end
            
            -- Store record with additional data for better backtracking
            table.insert(data.backtrack_data.records, {
                tick = record.tick,
                simulation_time = record.current,
                old_simulation_time = record.old,
                position = {x = position.x, y = position.y, z = position.z},
                time_diff = time_diff,
                resolved_angles = util.table_copy(data.resolved_angles),
                network_valid = true -- Mark as valid for networking
            })
            
            ::continue_inner::
        end
        
        -- Find best backtrack tick with improved selection criteria
        local best_tick = 0
        local best_sim_time = 0
        local min_time_diff = math.huge
        
        for _, record in ipairs(data.backtrack_data.records) do
            -- Prioritize records that are within optimal backtrack window
            local optimal_time = (latency + lerp_time) / 1000
            local score = math.abs(record.time_diff - optimal_time)
            
            if score < min_time_diff then
                min_time_diff = score
                best_tick = record.tick
                best_sim_time = record.simulation_time
            end
        end
        
        data.backtrack_data.best_tick = best_tick
        data.backtrack_data.best_simulation_time = best_sim_time
        
        -- Apply backtrack to game (this is where you need to hook into gamesense)
        if best_tick > 0 and best_sim_time > 0 then
            -- This is where you'd typically call a native function to set the backtrack time
            -- For gamesense, you might use something like:
            -- plist.set(player_index, "force_safe_point", true) -- Force safe point for backtracked shots
            -- Or set a global variable that your rage aimbot will use
            
            if CORSA.DEBUG then
                util.debug(string.format("Applied backtrack to player %d: tick=%d, sim_time=%.6f", 
                    player_index, best_tick, best_sim_time))
            end
        end
        
        ::continue::
    end
    
    util.perf_end("resolver:update_backtrack")
end,
    
update_network_settings = function(self)
    -- Apply network settings based on UI elements
    if ui.get(ui_elements.network.adaptive_interp) then
        local min_interp = ui.get(ui_elements.network.interp_min)
        local max_interp = ui.get(ui_elements.network.interp_max)
        local ping_threshold = ui.get(ui_elements.prediction.ping_threshold)
        
        -- Get local player ping with better error handling
        local local_player = entity.get_local_player()
        if not local_player then return end
        
        -- Try multiple methods to get a valid ping
        local ping = entity.get_prop(local_player, "m_iPing", 0)
        
        -- If ping is 0 or nil, try alternative methods
        if not ping or ping <= 0 then
            -- Method 1: Use client.latency() which returns server latency
            local latency = client.latency()
            if latency and latency > 0 then
                ping = math.floor(latency * 1000) -- Convert to ms
            end
            
            -- Method 2: If still 0, try getting it from scoreboard
            if not ping or ping <= 0 then
                local players = entity.get_players(false) -- Include all players
                for _, player in ipairs(players) do
                    if player == local_player then
                        local score_ping = entity.get_prop(player, "m_iPing")
                        if score_ping and score_ping > 0 then
                            ping = score_ping
                            break
                        end
                    end
                end
            end
            
            -- Method 3: If still 0, use network channel info
            if not ping or ping <= 0 then
                local net_info = util.get_net_channel_info()
                if net_info and net_info.latency and net_info.latency > 0 then
                    ping = net_info.latency
                end
            end
            
            -- If all methods fail, use a reasonable default based on game type
            if not ping or ping <= 0 then
                -- Check if we're in a local game
                local is_local_game = false
                local sv_lan = cvar.sv_lan
                if sv_lan and sv_lan:get_int() == 1 then
                    is_local_game = true
                end
                
                if is_local_game then
                    ping = 5 -- Very low ping for local games
                else
                    ping = 30 -- Default to 30ms as a reasonable value for online games
                end
            end
        end
        
        -- Ensure ping is a number at this point
        ping = tonumber(ping) or 30
        
        -- Scale interp ratio based on ping
        local interp_ratio
        if ping < ping_threshold then
            interp_ratio = min_interp
        else
            local scale_factor = math.min(1, (ping - ping_threshold) / 100)
            interp_ratio = min_interp + (max_interp - min_interp) * scale_factor
        end
        
        -- Store the calculated value for resolver calculations
        self.optimal_interp_ratio = interp_ratio
        
        if CORSA.DEBUG then
            util.debug(string.format("Calculated optimal interp ratio: %d (ping: %d)", interp_ratio, ping))
        end
        
        -- Inform the user about the limitation
        if not self.interp_warning_shown then
            client.color_log(CORSA.COLORS.WARNING[1], CORSA.COLORS.WARNING[2], CORSA.COLORS.WARNING[3],
                "Note: CS:GO doesn't allow changing cl_interp_ratio while connected to a server.")
            client.color_log(CORSA.COLORS.WARNING[1], CORSA.COLORS.WARNING[2], CORSA.COLORS.WARNING[3],
                "The optimal value has been calculated and will be used for resolver calculations.")
            client.color_log(CORSA.COLORS.WARNING[1], CORSA.COLORS.WARNING[2], CORSA.COLORS.WARNING[3],
                "To apply this value, disconnect from the server or switch to spectators first.")
            self.interp_warning_shown = true
        end
    end
end,

   draw_visuals = function(self)
    util.perf_start("resolver:draw_visuals")
    
    local current_time = globals.realtime()
    -- Reduce update frequency to prevent flashing
    if current_time - (self.last_visual_update_time or 0) < CORSA.PERFORMANCE.INDICATOR_UPDATE_INTERVAL then
        util.perf_end("resolver:draw_visuals")
        return
    end
    
    -- Only draw if enabled
    if not ui.get(ui_elements.visuals.enabled) then
        util.perf_end("resolver:draw_visuals")
        return
    end
    
    -- Get screen size
    local screen_width, screen_height = client.screen_size()
    
    -- Draw resolver indicators
    self:draw_resolver_indicators(screen_width, screen_height)
    
    -- Draw backtrack points if enabled
    if ui.get(ui_elements.visuals.show_backtrack) then
        self:draw_backtrack_points()
    end
    
    -- Draw hit markers
    self:draw_hit_markers()
    
    -- Draw bullet tracers
    self:draw_tracers()
    
    -- Draw resolved hitboxes
    self:draw_resolved_hitboxes()
    
    self.last_visual_update_time = current_time
    util.perf_end("resolver:draw_visuals")
end,

draw_resolver_indicators = function(self, screen_width, screen_height)
    -- Initialize if not already done
    if not self.active_players then self.active_players = {} end
    
    -- Get indicator style and position
    local style = ui.get(ui_elements.visuals.style)
    local position = ui.get(ui_elements.visuals.position)
    local color_scheme = ui.get(ui_elements.visuals.color_scheme)
    
    -- Determine position coordinates
    local x, y
    if position == "Center" then
        x = screen_width / 2
        y = screen_height / 2 + 50
    elseif position == "Left" then
        x = 100
        y = screen_height / 2
    elseif position == "Right" then
        x = screen_width - 100
        y = screen_height / 2
    elseif position == "Bottom" then
        x = screen_width / 2
        y = screen_height - 100
    elseif position == "Custom" then
        local custom_x_pct = ui.get(ui_elements.visuals.custom_x) / 100
        local custom_y_pct = ui.get(ui_elements.visuals.custom_y) / 100
        x = screen_width * custom_x_pct
        y = screen_height * custom_y_pct
    else
        -- Default fallback
        x = screen_width / 2
        y = screen_height / 2 + 50
    end
    
    -- Get color based on scheme
    local r, g, b, a = 255, 255, 255, 255
    if color_scheme == "Default" then
        r, g, b = CORSA.COLORS.PRIMARY[1], CORSA.COLORS.PRIMARY[2], CORSA.COLORS.PRIMARY[3]
    elseif color_scheme == "Rainbow" then
        local hue = (globals.realtime() * 0.5) % 1
        r, g, b = self:hsv_to_rgb(hue, 1, 1)
    elseif color_scheme == "Dynamic" then
        -- Color based on resolver confidence
        local avg_confidence = self:get_average_resolver_confidence()
        if avg_confidence > 0.7 then
            r, g, b = 100, 255, 100 -- Green for high confidence
        elseif avg_confidence > 0.4 then
            r, g, b = 255, 200, 0 -- Yellow for medium confidence
        else
            r, g, b = 255, 100, 100 -- Red for low confidence
        end
    end
    
    -- Draw based on style
    if style == "Minimal" then
        renderer.text(x, y, r, g, b, a, "c", 0, "CORSA")
    elseif style == "Standard" then
        renderer.text(x, y, r, g, b, a, "c", 0, "CORSA RESOLVER")
        renderer.text(x, y + 15, r, g, b, a, "c", 0, string.format("Active: %d players", #self.active_players))
    elseif style == "Detailed" then
        renderer.text(x, y, r, g, b, a, "c", 0, "CORSA RESOLVER v4")
        renderer.text(x, y + 15, r, g, b, a, "c", 0, string.format("Active: %d players", #self.active_players))
        
        -- Show statistics if enabled
        if ui.get(ui_elements.visuals.show_statistics) then
            local hit_count, miss_count = self:get_hit_miss_stats()
            local hit_ratio = hit_count + miss_count > 0 and hit_count / (hit_count + miss_count) * 100 or 0
            renderer.text(x, y + 30, r, g, b, a, "c", 0, string.format("Hit: %d | Miss: %d (%.1f%%)", 
                hit_count, miss_count, hit_ratio))
        end
        
        -- Show resolver info if enabled
        if ui.get(ui_elements.visuals.show_resolver_info) then
            local y_offset = ui.get(ui_elements.visuals.show_statistics) and 45 or 30
            
            -- Count active resolver methods
            local methods = {}
            for _, player_index in ipairs(self.active_players) do
                local data = player_data:get(player_index)
                if data and data.resolver_metadata and data.resolver_metadata.correction_source then
                    local source = data.resolver_metadata.correction_source
                    methods[source] = (methods[source] or 0) + 1
                end
            end
            
            -- Display active methods
            local method_text = "Methods: "
            local has_methods = false
            for source, count in pairs(methods) do
                if source ~= "none" then
                    method_text = method_text .. string.format("%s(%d) ", source, count)
                    has_methods = true
                end
            end
            
            if has_methods then
                renderer.text(x, y + y_offset, r, g, b, a, "c", 0, method_text)
            else
                renderer.text(x, y + y_offset, r, g, b, a, "c", 0, "No active corrections")
            end
        end
    elseif style == "Modern" then
    -- Draw modern style with sleek design and subtle animations
    local width = 160
    local height = 24
    local padding = 6
    local corner_radius = 5
    local pulse = (math.sin(globals.realtime() * 1.5) + 1) / 2 * 0.2 -- Subtle pulse
    
    -- Background with gradient and rounded corners
    local bg_alpha = 220 + (pulse * 35)
    renderer.rectangle(x - width/2, y - height/2, width, height, 15, 15, 20, bg_alpha) -- Base
    renderer.gradient(x - width/2, y - height/2, width, height, 20, 20, 30, 0, 30, 30, 45, bg_alpha, true) -- Gradient overlay
    
    -- Accent line at top
    local accent_width = width * (0.5 + pulse * 0.5)
    renderer.rectangle(x - accent_width/2, y - height/2, accent_width, 2, r, g, b, 200 + (pulse * 55))
    
    -- Title with subtle glow
    local title_y = y - height/2 + padding
    renderer.text(x, title_y + 1, 0, 0, 0, 100, "c", 0, "CORSA v4") -- Shadow
    renderer.text(x, title_y, r, g, b, 255, "c", 0, "CORSA v4")
    
    -- Progress bar with animated fill
    local avg_confidence = self:get_average_resolver_confidence()
    local bar_width = width - padding * 2
    local fill_width = bar_width * avg_confidence
    
    -- Bar background with depth effect
    renderer.rectangle(x - bar_width/2, y + padding, bar_width, 4, 20, 20, 25, 180)
    renderer.rectangle(x - bar_width/2 + 1, y + padding + 1, bar_width - 2, 2, 10, 10, 15, 100)
    
    -- Animated fill with gradient
    local fill_r1, fill_g1, fill_b1 = r, g, b
    local fill_r2, fill_g2, fill_b2 = r * 0.7, g * 0.7, b * 0.7
    
    if avg_confidence > 0.7 then
        fill_r1, fill_g1, fill_b1 = 100, 255, 100 -- Green for high confidence
        fill_r2, fill_g2, fill_b2 = 70, 200, 70
    elseif avg_confidence > 0.4 then
        fill_r1, fill_g1, fill_b1 = 255, 200, 0 -- Yellow for medium confidence
        fill_r2, fill_g2, fill_b2 = 200, 160, 0
    else
        fill_r1, fill_g1, fill_b1 = 255, 100, 100 -- Red for low confidence
        fill_r2, fill_g2, fill_b2 = 200, 70, 70
    end
    
    -- Animated fill effect
    local fill_pulse = (math.sin(globals.realtime() * 3) + 1) / 2 * 0.2
    local fill_alpha = 220 + (fill_pulse * 35)
    
    renderer.gradient(x - bar_width/2, y + padding, fill_width, 4, 
        fill_r1, fill_g1, fill_b1, fill_alpha, 
        fill_r2, fill_g2, fill_b2, fill_alpha, true)
    
    -- Show additional info if enabled
    if ui.get(ui_elements.visuals.show_statistics) or ui.get(ui_elements.visuals.show_resolver_info) then
        local info_y = y + height/2 + padding
        local info_height = 0
        
        if ui.get(ui_elements.visuals.show_statistics) then
            local hit_count, miss_count = self:get_hit_miss_stats()
            local hit_ratio = hit_count + miss_count > 0 and hit_count / (hit_count + miss_count) * 100 or 0
            
            -- Stats panel with subtle animation
            local stats_height = 22
            local stats_alpha = 180 + (pulse * 40)
            renderer.rectangle(x - width/2, info_y, width, stats_height, 15, 15, 20, stats_alpha)
            renderer.gradient(x - width/2, info_y, width, stats_height, 20, 20, 30, 0, 30, 30, 45, stats_alpha, true)
            
            -- Hit/miss stats with colored indicators
            local hit_color_r, hit_color_g, hit_color_b = 100, 255, 100
            local miss_color_r, miss_color_g, miss_color_b = 255, 100, 100
            
            renderer.text(x - 40, info_y + padding, hit_color_r, hit_color_g, hit_color_b, 255, "r", 0, string.format("%d", hit_count))
            renderer.text(x - 25, info_y + padding, 255, 255, 255, 255, "c", 0, "|")
            renderer.text(x - 10, info_y + padding, miss_color_r, miss_color_g, miss_color_b, 255, "l", 0, string.format("%d", miss_count))
            renderer.text(x + 30, info_y + padding, 255, 255, 255, 255, "c", 0, string.format("(%.1f%%)", hit_ratio))
            
            info_height = info_height + stats_height + 2
        end
        
        if ui.get(ui_elements.visuals.show_resolver_info) then
            -- Count active resolver methods
            local methods = {}
            for _, player_index in ipairs(self.active_players) do
                local data = player_data:get(player_index)
                if data and data.resolver_metadata and data.resolver_metadata.correction_source then
                    local source = data.resolver_metadata.correction_source
                    methods[source] = (methods[source] or 0) + 1
                end
            end
            
            -- Display active methods
            local method_text = ""
            local has_methods = false
            local method_count = 0
            
            for source, count in pairs(methods) do
                if source ~= "none" then
                    method_count = method_count + 1
                    has_methods = true
                end
            end
            
            if has_methods then
                -- Methods panel with subtle animation
                local methods_height = 22
                local methods_alpha = 180 + (pulse * 40)
                renderer.rectangle(x - width/2, info_y + info_height, width, methods_height, 15, 15, 20, methods_alpha)
                renderer.gradient(x - width/2, info_y + info_height, width, methods_height, 20, 20, 30, 0, 30, 30, 45, methods_alpha, true)
                
                -- Draw method indicators with unique colors
                local method_x = x - width/2 + padding
                local method_y = info_y + info_height + padding
                local method_spacing = (width - padding*2) / math.max(4, method_count)
                local method_index = 0
                
                for source, count in pairs(methods) do
                    if source ~= "none" then
                        local method_color_r, method_color_g, method_color_b = 255, 255, 255
                        
                        if source == "defensive" then
                            method_color_r, method_color_g, method_color_b = 255, 100, 100 -- Red
                        elseif source == "jitter" then
                            method_color_r, method_color_g, method_color_b = 100, 100, 255 -- Blue
                        elseif source == "desync" then
                            method_color_r, method_color_g, method_color_b = 255, 200, 0 -- Yellow
                        elseif source == "exploit" then
                            method_color_r, method_color_g, method_color_b = 255, 0, 255 -- Purple
                        elseif source == "fake_duck" then
                            method_color_r, method_color_g, method_color_b = 0, 255, 255 -- Cyan
                        elseif source == "adaptive" then
                            method_color_r, method_color_g, method_color_b = 0, 255, 0 -- Green
                        end
                        
                        local dot_x = method_x + method_index * method_spacing
                        renderer.circle(dot_x, method_y + 3, method_color_r, method_color_g, method_color_b, 255, 3, 0, 1)
                        renderer.text(dot_x + 8, method_y, 255, 255, 255, 255, "l", 0, string.format("%s", source:sub(1,3)))
                        renderer.text(dot_x + 25, method_y, method_color_r, method_color_g, method_color_b, 255, "l", 0, string.format("%d", count))
                        
                        method_index = method_index + 1
                    end
                end
            end
        end
    end
elseif style == "Animated" then
    -- Enhanced animated style with particle effects and smooth transitions
    local time = globals.realtime()
    local pulse = (math.sin(time * 3) + 1) / 2
    local alpha = 180 + pulse * 75
    local size = 16 + pulse * 4
    
    -- Draw glowing text with shadow
    renderer.text(x+1, y+1, 0, 0, 0, 100, "c+", size, "CORSA")
    renderer.text(x, y, r, g, b, alpha, "c+", size, "CORSA")
    
    -- Draw particle effect around text
    local particle_count = 12
    local base_radius = 30 + pulse * 10
    local particle_size = 2 + pulse * 1.5
    
    for i = 1, particle_count do
        local particle_angle = time * 0.5 + (i / particle_count) * math.pi * 2
        local distance = base_radius + math.sin(time * 2 + i) * 5
        
        local particle_x = x + math.cos(particle_angle) * distance
        local particle_y = y + math.sin(particle_angle) * distance
        
        -- Particle color based on position
        local particle_hue = (i / particle_count + time * 0.1) % 1
        local particle_r, particle_g, particle_b = self:hsv_to_rgb(particle_hue, 0.7, 1)
        local particle_alpha = 150 + pulse * 105
        
        renderer.circle(particle_x, particle_y, particle_r, particle_g, particle_b, particle_alpha, particle_size, 0, 1)
    end
    
    -- Draw rotating ring with gradient
    local ring_segments = 24
    local ring_radius = 40 + pulse * 5
    local ring_thickness = 1.5
    local rotation = time * 0.7
    
    for i = 1, ring_segments do
        local angle1 = rotation + (i-1) * (math.pi * 2) / ring_segments
        local angle2 = rotation + i * (math.pi * 2) / ring_segments
        
        local x1 = x + math.cos(angle1) * ring_radius
        local y1 = y + math.sin(angle1) * ring_radius
        local x2 = x + math.cos(angle2) * ring_radius
        local y2 = y + math.sin(angle2) * ring_radius
        
        -- Color gradient around the ring
        local segment_hue = ((i / ring_segments) + time * 0.1) % 1
        local r1, g1, b1 = self:hsv_to_rgb(segment_hue, 0.8, 1)
        local r2, g2, b2 = self:hsv_to_rgb((segment_hue + 0.05) % 1, 0.8, 1)
        
        renderer.line(x1, y1, x2, y2, r1, g1, b1, alpha)
    end
    
    -- Show active players with enhanced animated indicators
    if #self.active_players > 0 then
        local indicator_y = y + 50
        local indicator_height = 24
        local indicator_width = math.min(300, #self.active_players * 30)
        local indicator_alpha = 150 + pulse * 50
        
        -- Draw indicator background
        renderer.rectangle(x - indicator_width/2, indicator_y, indicator_width, indicator_height, 15, 15, 20, indicator_alpha)
        renderer.gradient(x - indicator_width/2, indicator_y, indicator_width, indicator_height, 20, 20, 30, 0, 30, 30, 45, indicator_alpha, true)
        
        -- Draw player indicators
        local player_spacing = indicator_width / #self.active_players
        local player_x_start = x - indicator_width/2 + player_spacing/2
        
        for i, player_index in ipairs(self.active_players) do
            local data = player_data:get(player_index)
            local player_x = player_x_start + (i-1) * player_spacing
            
            -- Default colors
            local indicator_r, indicator_g, indicator_b = r, g, b
            local confidence = 0.5
            local source = "none"
            
            if data and data.resolver_metadata then
                source = data.resolver_metadata.correction_source or "none"
                confidence = data.resolver_metadata.confidence or 0.5
                
                -- Color based on correction source
                if source == "defensive" then
                    indicator_r, indicator_g, indicator_b = 255, 100, 100 -- Red for defensive AA
                elseif source == "jitter" then
                    indicator_r, indicator_g, indicator_b = 100, 100, 255 -- Blue for jitter
                elseif source == "desync" then
                    indicator_r, indicator_g, indicator_b = 255, 200, 0 -- Yellow for desync
                elseif source == "exploit" then
                    indicator_r, indicator_g, indicator_b = 255, 0, 255 -- Purple for exploit
                elseif source == "fake_duck" then
                    indicator_r, indicator_g, indicator_b = 0, 255, 255 -- Cyan for fake duck
                elseif source == "adaptive" then
                    indicator_r, indicator_g, indicator_b = 0, 255, 0 -- Green for adaptive
                end
            end
            
            -- Player-specific pulse effect
            local player_pulse = (math.sin(time * 2 + i) + 1) / 2
            local indicator_size = 4 + (confidence * 4) + (player_pulse * 2)
            local indicator_alpha = 150 + (confidence * 105)
            
            -- Draw player indicator with glow effect
            renderer.circle_outline(player_x, indicator_y + indicator_height/2, 
                indicator_r, indicator_g, indicator_b, indicator_alpha * 0.5, 
                indicator_size + 2, 0, 1, 1)
                
            -- Draw main indicator
            renderer.circle(player_x, indicator_y + indicator_height/2, 
                indicator_r, indicator_g, indicator_b, indicator_alpha, 
                indicator_size, 0, 1)
                
            -- Draw source indicator text
            if source ~= "none" then
                local source_text = source:sub(1, 1):upper()
                renderer.text(player_x, indicator_y + indicator_height/2, 
                    0, 0, 0, 255, "c", 0, source_text)
            end
        end
        
        -- Draw player count indicator
        local count_text = string.format("%d", #self.active_players)
        local count_x = x - indicator_width/2 - 15
        local count_y = indicator_y + indicator_height/2
        
        -- Draw count background
        renderer.circle(count_x, count_y, 30, 30, 40, 200 + (pulse * 55), 12, 0, 1)
        
        -- Draw count text with glow
        renderer.text(count_x, count_y+1, 0, 0, 0, 150, "c", 0, count_text)
        renderer.text(count_x, count_y, 255, 255, 255, 255, "c", 0, count_text)
    end
    
    -- Draw performance stats if debug mode is enabled
    if CORSA.DEBUG and ui.get(ui_elements.resolver.debug_mode) then
        local debug_y = y + 80
        local hit_count, miss_count = self:get_hit_miss_stats()
        local hit_ratio = hit_count + miss_count > 0 and hit_count / (hit_count + miss_count) * 100 or 0
        local avg_confidence = self:get_average_resolver_confidence() * 100
        
        -- Create debug text with performance info
        local debug_text = string.format("Hit: %d | Miss: %d (%.1f%%) | Conf: %.1f%%", 
            hit_count, miss_count, hit_ratio, avg_confidence)
            
        -- Draw debug text with shadow
        renderer.text(x+1, debug_y+1, 0, 0, 0, 150, "c", 0, debug_text)
        renderer.text(x, debug_y, 200, 200, 200, 255, "c", 0, debug_text)
        
        -- Draw FPS indicator
        local fps = 1 / globals.frametime()
        local fps_color_r, fps_color_g, fps_color_b = 255, 255, 255
        
        if fps < 60 then
            fps_color_r, fps_color_g, fps_color_b = 255, 100, 100 -- Red for low FPS
        elseif fps < 120 then
            fps_color_r, fps_color_g, fps_color_b = 255, 200, 0 -- Yellow for medium FPS
        else
            fps_color_r, fps_color_g, fps_color_b = 100, 255, 100 -- Green for high FPS
        end
        
        renderer.text(x, debug_y + 15, fps_color_r, fps_color_g, fps_color_b, 255, "c", 0, 
            string.format("FPS: %.1f", fps))
    end
end

draw_backtrack_points = function(self)
    -- Only draw if enabled
    if not ui.get(ui_elements.visuals.show_backtrack) then
        return
    end
    
    -- Initialize if needed
    if not self.active_players then self.active_players = {} end
    
    local style = ui.get(ui_elements.visuals.backtrack_style)
    local r, g, b, a = 255, 255, 255, 200 -- Default color if menu_color is not available
    
    -- Try to get color from menu
    local menu_color_success, menu_r, menu_g, menu_b, menu_a = pcall(ui.get, ui_elements.menu_color)
    if menu_color_success then
        r, g, b, a = menu_r, menu_g, menu_b, menu_a
    end
    
    local backtrack_time = ui.get(ui_elements.resolver.backtrack_time)
    if not backtrack_time or backtrack_time <= 0 then
        backtrack_time = 200 -- Default value
    end
    
    -- Debug counter for records
    local total_records = 0
    local current_time = globals.realtime()
    
    for _, player_index in ipairs(self.active_players) do
        local data = player_data:get(player_index)
        if not data or not data.backtrack_data then
            goto continue
        end
        
        -- Initialize records array if it doesn't exist
        if not data.backtrack_data.records then
            data.backtrack_data.records = {}
        end
        
        -- Count records for debugging
        total_records = total_records + #data.backtrack_data.records
        
        -- If no records, try to create some basic ones for visualization
        if #data.backtrack_data.records == 0 and data.position_history and data.position_history:count() > 0 then
            for i = 1, math.min(10, data.position_history:count()) do
                local pos = data.position_history:get(i)
                if pos then
                    table.insert(data.backtrack_data.records, {
                        position = {x = pos.x, y = pos.y, z = pos.z},
                        time_diff = (current_time - (pos.time or current_time)) or 0.1,
                        simulation_time = 0,
                        tick = 0
                    })
                end
            end
        end
        
        -- Enhanced visualization with better performance
        local max_points_to_render = 15 -- Limit points for performance
        local points_to_render = math.min(max_points_to_render, #data.backtrack_data.records)
        local step = math.max(1, math.floor(#data.backtrack_data.records / points_to_render))
        
        local rendered_positions = {}
        
        -- Collect positions to render with step size for better performance
        for i = 1, #data.backtrack_data.records, step do
            local record = data.backtrack_data.records[i]
            if record and record.position then
                table.insert(rendered_positions, {
                    pos = record.position,
                    time_diff = record.time_diff or 0.1,
                    index = i
                })
            end
            
            if #rendered_positions >= max_points_to_render then
                break
            end
        end
        
        -- Sort by time difference for proper rendering order
        table.sort(rendered_positions, function(a, b)
            return a.time_diff < b.time_diff
        end)
        
        -- Render the collected positions
        for i, point_data in ipairs(rendered_positions) do
            local pos = point_data.pos
            if not pos or not pos.x then goto continue_inner end
            
            local w2s_x, w2s_y = client.world_to_screen(pos.x, pos.y, pos.z)
            
            if not w2s_x or not w2s_y then
                goto continue_inner
            end
            
            -- Calculate alpha based on time difference (newer = more visible)
            local alpha_factor = 1 - (point_data.time_diff / (backtrack_time / 1000))
            alpha_factor = math.max(0.2, alpha_factor) -- Ensure minimum visibility
            local point_alpha = math.max(50, a * alpha_factor)
            
            -- Enhanced visualization based on style
            if style == "Dots" then
                -- Simple dot with pulse effect
                local pulse = (math.sin(current_time * 3 + i * 0.5) + 1) / 2 * 0.3
                local dot_size = 3 + pulse * 2
                
                -- Draw glow effect for newest points
                if i <= 3 then
                    renderer.circle(w2s_x, w2s_y, r, g, b, point_alpha * 0.5, dot_size * 1.5, 0, 1)
                end
                
                renderer.circle(w2s_x, w2s_y, r, g, b, point_alpha, dot_size, 0, 1)
            elseif style == "Line" then
                -- Connect dots with lines and add pulse effect
                if i > 1 then
                    local prev_point = rendered_positions[i-1]
                    if prev_point and prev_point.pos then
                        local prev_pos = prev_point.pos
                        local prev_x, prev_y = client.world_to_screen(prev_pos.x, prev_pos.y, prev_pos.z)
                        
                        if prev_x and prev_y then
                            -- Gradient line based on time
                            local prev_alpha = math.max(50, a * math.max(0.2, 1 - (prev_point.time_diff / (backtrack_time / 1000))))
                            renderer.gradient(w2s_x, w2s_y, prev_x - w2s_x, prev_y - w2s_y, 
                                r, g, b, point_alpha, r, g, b, prev_alpha, false)
                        end
                    end
                end
                
                -- Draw point
                local pulse = (math.sin(current_time * 3 + i * 0.5) + 1) / 2 * 0.3
                local dot_size = 2 + pulse * 1.5
                renderer.circle(w2s_x, w2s_y, r, g, b, point_alpha, dot_size, 0, 1)
            elseif style == "Skeleton" then
                -- Draw simplified skeleton with enhanced visuals
                local pulse = (math.sin(current_time * 2 + i * 0.3) + 1) / 2 * 0.3
                local outline_size = 5 + pulse * 2
                local outline_thickness = 1 + pulse
                
                -- Draw outer glow for newest points
                if i <= 3 then
                    renderer.circle_outline(w2s_x, w2s_y, r, g, b, point_alpha * 0.4, 
                        outline_size * 1.3, 0, 1, outline_thickness)
                end
                
                renderer.circle_outline(w2s_x, w2s_y, r, g, b, point_alpha, 
                    outline_size, 0, 1, outline_thickness)
                
                -- Draw center dot
                renderer.circle(w2s_x, w2s_y, r, g, b, point_alpha, 2, 0, 1)
            elseif style == "3D Box" then
                -- Draw 3D box with enhanced visuals
                local pulse = (math.sin(current_time * 2 + i * 0.3) + 1) / 2 * 0.3
                local box_size = 16 * (1 + pulse * 0.3)
                local half_size = box_size / 2
                
                -- Draw box outline with glow effect for newest points
                if i <= 3 then
                    renderer.rectangle(w2s_x - half_size - 2, w2s_y - half_size - 2, 
                        box_size + 4, box_size + 4, 0, 0, 0, 0, 1, r, g, b, point_alpha * 0.3)
                end
                
                -- Draw box outline
                renderer.rectangle(w2s_x - half_size, w2s_y - half_size, 
                    box_size, box_size, 0, 0, 0, 0, 1, r, g, b, point_alpha)
                
                -- Draw center dot
                renderer.circle(w2s_x, w2s_y, r, g, b, point_alpha, 2, 0, 1)
                
                -- Draw diagonal lines for 3D effect
                local corner_size = half_size * 0.3
                
                -- Top-left corner
                renderer.line(w2s_x - half_size, w2s_y - half_size, 
                    w2s_x - half_size + corner_size, w2s_y - half_size, r, g, b, point_alpha)
                renderer.line(w2s_x - half_size, w2s_y - half_size, 
                    w2s_x - half_size, w2s_y - half_size + corner_size, r, g, b, point_alpha)
                
                -- Top-right corner
                renderer.line(w2s_x + half_size, w2s_y - half_size, 
                    w2s_x + half_size - corner_size, w2s_y - half_size, r, g, b, point_alpha)
                renderer.line(w2s_x + half_size, w2s_y - half_size, 
                    w2s_x + half_size, w2s_y - half_size + corner_size, r, g, b, point_alpha)
                
                -- Bottom-left corner
                renderer.line(w2s_x - half_size, w2s_y + half_size, 
                    w2s_x - half_size + corner_size, w2s_y + half_size, r, g, b, point_alpha)
                renderer.line(w2s_x - half_size, w2s_y + half_size, 
                    w2s_x - half_size, w2s_y + half_size - corner_size, r, g, b, point_alpha)
                
                -- Bottom-right corner
                renderer.line(w2s_x + half_size, w2s_y + half_size, 
                    w2s_x + half_size - corner_size, w2s_y + half_size, r, g, b, point_alpha)
                renderer.line(w2s_x + half_size, w2s_y + half_size, 
                    w2s_x + half_size, w2s_y + half_size - corner_size, r, g, b, point_alpha)
            end
            
            ::continue_inner::
        end
        
        ::continue::
    end
    
    -- Debug info for backtrack records
    if CORSA.DEBUG and ui.get(ui_elements.resolver.debug_mode) then
        renderer.text(10, 10, 255, 255, 255, 255, "", 0, string.format("Backtrack records: %d", total_records))
    end
end
end,

draw_backtrack_points = function(self)
    -- Only draw if enabled
    if not ui.get(ui_elements.visuals.show_backtrack) then
        return
    end
    
    -- Initialize if needed
    if not self.active_players then self.active_players = {} end
    
    local style = ui.get(ui_elements.visuals.backtrack_style)
    local r, g, b, a = 255, 255, 255, 200 -- Default color if menu_color is not available
    
    -- Try to get color from menu
    local menu_color_success, menu_r, menu_g, menu_b, menu_a = pcall(ui.get, ui_elements.menu_color)
    if menu_color_success then
        r, g, b, a = menu_r, menu_g, menu_b, menu_a
    end
    
    local backtrack_time = ui.get(ui_elements.resolver.backtrack_time)
    if not backtrack_time or backtrack_time <= 0 then
        backtrack_time = 200 -- Default value
    end
    
    -- Debug counter for records
    local total_records = 0
    
    for _, player_index in ipairs(self.active_players) do
        local data = player_data:get(player_index)
        if not data or not data.backtrack_data or not data.backtrack_data.records then
            goto continue
        end
        
        -- Count records for debugging
        total_records = total_records + #data.backtrack_data.records
        
        -- If no records, try to create some basic ones for visualization
        if #data.backtrack_data.records == 0 and data.position_history and data.position_history:count() > 0 then
            data.backtrack_data.records = {}
            
            for i = 1, math.min(10, data.position_history:count()) do
                local pos = data.position_history:get(i)
                if pos then
                   table.insert(data.backtrack_data.records, {
                        position = {x = pos.x, y = pos.y, z = pos.z},
                        time_diff = (globals.realtime() - pos.time) or 0.1,
                        simulation_time = 0,
                        tick = 0
                    })
                end
            end
        end
        
        for i, record in ipairs(data.backtrack_data.records) do
            local pos = record.position
            if not pos or not pos.x then goto continue_inner end
            
            local w2s_x, w2s_y = client.world_to_screen(pos.x, pos.y, pos.z)
            
            if not w2s_x or not w2s_y then
                goto continue_inner
            end
            
            -- Calculate alpha based on time difference (newer = more visible)
            local alpha_factor = 1 - (record.time_diff / (backtrack_time / 1000))
            alpha_factor = math.max(0.2, alpha_factor) -- Ensure minimum visibility
            local point_alpha = math.max(50, a * alpha_factor)
            
            -- Draw based on style
            if style == "Dots" then
                -- Simple dot
                renderer.circle(w2s_x, w2s_y, r, g, b, point_alpha, 3, 0, 1)
            elseif style == "Line" then
                -- Connect dots with lines
                if i > 1 then
                    local prev_record = data.backtrack_data.records[i-1]
                    if prev_record and prev_record.position then
                        local prev_pos = prev_record.position
                        local prev_x, prev_y = client.world_to_screen(prev_pos.x, prev_pos.y, prev_pos.z)
                        
                        if prev_x and prev_y then
                            renderer.line(w2s_x, w2s_y, prev_x, prev_y, r, g, b, point_alpha)
                        end
                    end
                end
                renderer.circle(w2s_x, w2s_y, r, g, b, point_alpha, 2, 0, 1)
            elseif style == "Skeleton" then
                -- Draw simplified skeleton
                renderer.circle_outline(w2s_x, w2s_y, r, g, b, point_alpha, 5, 0, 1, 2)
            elseif style == "3D Box" then
                -- Draw 3D box (simplified)
                local box_size = 16
                local half_size = box_size / 2
                
                -- Draw box center
                renderer.circle(w2s_x, w2s_y, r, g, b, point_alpha, 2, 0, 1)
                
                -- Draw box outline
                renderer.rectangle(w2s_x - half_size, w2s_y - half_size, box_size, box_size, 0, 0, 0, 0, 1, r, g, b, point_alpha)
            end
            
            ::continue_inner::
        end
        
        ::continue::
    end
    
    -- Debug info for backtrack records
    if CORSA.DEBUG and ui.get(ui_elements.resolver.debug_mode) then
        renderer.text(10, 10, 255, 255, 255, 255, "", 0, string.format("Backtrack records: %d", total_records))
    end
end,

draw_hit_markers = function(self)
    -- Only draw if enabled
    if not ui.get(ui_elements.visuals.hit_marker) then
        return
    end
    
    -- Initialize if needed
    if not self.hit_markers then self.hit_markers = {} end
    
    local current_time = globals.realtime()
    local style = ui.get(ui_elements.visuals.hit_marker_style) or "Cross"
    local size = ui.get(ui_elements.visuals.hit_marker_size) or 8
    local duration = ui.get(ui_elements.visuals.hit_marker_duration) or 0.5
    
    -- Get color with error handling
    local r, g, b, a = 255, 255, 255, 255
    local color_success, color_r, color_g, color_b, color_a = pcall(ui.get, ui_elements.visuals.hit_marker_color)
    if color_success then
        r, g, b, a = color_r, color_g, color_b, color_a
    end
    
    -- Process hit markers
    for i = #self.hit_markers, 1, -1 do
        local marker = self.hit_markers[i]
        if not marker or not marker.time then goto continue end
        
        local time_alive = current_time - marker.time
        
        -- Remove old markers
        if time_alive > duration then
            table.remove(self.hit_markers, i)
            goto continue
        end
        
        -- Calculate alpha based on time alive
        local alpha_factor = 1 - (time_alive / duration)
        local marker_alpha = a * alpha_factor
        
        -- Get screen position
        local x, y = client.world_to_screen(marker.x, marker.y, marker.z)
        if not x or not y then
            goto continue
        end
        
        -- Draw based on style
        if style == "Cross" then
            -- Simple cross
            local line_size = size * (1 + alpha_factor)
            renderer.line(x - line_size, y - line_size, x + line_size, y + line_size, r, g, b, marker_alpha)
            renderer.line(x - line_size, y + line_size, x + line_size, y - line_size, r, g, b, marker_alpha)
        elseif style == "Circle" then
            -- Circle that expands
            local circle_size = size * (1 + time_alive * 2)
            renderer.circle_outline(x, y, r, g, b, marker_alpha, circle_size, 0, 1, 1)
        elseif style == "Square" then
            -- Square
            local square_size = size * (1 + alpha_factor)
            renderer.rectangle(x - square_size, y - square_size, square_size * 2, square_size * 2, 0, 0, 0, 0, 1, r, g, b, marker_alpha)
        elseif style == "3D" then
            -- 3D marker (simplified)
            local line_size = size * (1 + alpha_factor)
            
            -- Draw cross
            renderer.line(x - line_size, y - line_size, x + line_size, y + line_size, r, g, b, marker_alpha)
            renderer.line(x - line_size, y + line_size, x + line_size, y - line_size, r, g, b, marker_alpha)
            
            -- Draw circle
            renderer.circle_outline(x, y, r, g, b, marker_alpha, line_size * 1.5, 0, 1, 1)
        elseif style == "Animated" then
            -- Animated marker
            local pulse = (math.sin(current_time * 10) + 1) / 2
            local line_size = size * (1 + alpha_factor * (1 + pulse * 0.5))
            
            -- Draw expanding cross
            renderer.line(x - line_size, y - line_size, x + line_size, y + line_size, r, g, b, marker_alpha)
            renderer.line(x - line_size, y + line_size, x + line_size, y - line_size, r, g, b, marker_alpha)
            
            -- Draw pulsing circle
            local circle_size = size * (1 + time_alive * 2) * (1 + pulse * 0.3)
            renderer.circle_outline(x, y, r, g, b, marker_alpha * (1 - pulse * 0.5), circle_size, 0, 1, 1)
        end
        
        ::continue::
    end
end,

draw_tracers = function(self)
    -- Only draw if enabled
    if not ui.get(ui_elements.visuals.tracer_enabled) then
        return
    end
    
    -- Initialize if needed
    if not self.tracers then self.tracers = {} end
    
    local current_time = globals.realtime()
    local duration = ui.get(ui_elements.visuals.tracer_duration) or 3
    
    -- Get color with error handling
    local r, g, b, a = 255, 255, 255, 150
    local color_success, color_r, color_g, color_b, color_a = pcall(ui.get, ui_elements.visuals.tracer_color)
    if color_success then
        r, g, b, a = color_r, color_g, color_b, color_a
    end
    
    -- Process tracers
    for i = #self.tracers, 1, -1 do
        local tracer = self.tracers[i]
        if not tracer or not tracer.time then goto continue end
        
        local time_alive = current_time - tracer.time
        
        -- Remove old tracers
        if time_alive > duration then
            table.remove(self.tracers, i)
            goto continue
        end
        
        -- Calculate alpha based on time alive
        local alpha_factor = 1 - (time_alive / duration)
        local tracer_alpha = a * alpha_factor
        
        -- Get screen positions
        local start_x, start_y = client.world_to_screen(tracer.start_x, tracer.start_y, tracer.start_z)
        local end_x, end_y = client.world_to_screen(tracer.end_x, tracer.end_y, tracer.end_z)
        
        if not start_x or not start_y or not end_x or not end_y then
            goto continue
        end
        
        -- Draw tracer line
        renderer.line(start_x, start_y, end_x, end_y, r, g, b, tracer_alpha)
        
        -- Draw impact point
        renderer.circle(end_x, end_y, r, g, b, tracer_alpha, 3, 0, 1)
        
        ::continue::
    end
end,

draw_resolved_hitboxes = function(self)
    -- Only draw if enabled
    if not ui.get(ui_elements.visuals.show_hitboxes) then
        return
    end
    
    -- Initialize if needed
    if not self.resolved_hitboxes then self.resolved_hitboxes = {} end
    
    local current_time = globals.realtime()
    local hitbox_time = ui.get(ui_elements.visuals.hitbox_time) or 3
    
    -- Get color with error handling
    local r, g, b = 255, 255, 255
    local menu_color_success, menu_r, menu_g, menu_b = pcall(ui.get, ui_elements.menu_color)
    if menu_color_success then
        r, g, b = menu_r, menu_g, menu_b
    end
    
    -- Process hitboxes
    for i = #self.resolved_hitboxes, 1, -1 do
        local hitbox = self.resolved_hitboxes[i]
        if not hitbox or not hitbox.time then goto continue end
        
        local time_alive = current_time - hitbox.time
        
        -- Remove old hitboxes
        if time_alive > hitbox_time then
            table.remove(self.resolved_hitboxes, i)
            goto continue
        end
        
        -- Calculate alpha based on time alive
        local alpha_factor = 1 - (time_alive / hitbox_time)
        local hitbox_alpha = 255 * alpha_factor
        
        -- Get screen position
        local x, y = client.world_to_screen(hitbox.x, hitbox.y, hitbox.z)
        if not x or not y then
            goto continue
        end
        
        -- Draw hitbox
        local size = (hitbox.size or 6) * (1 + alpha_factor * 0.5)
        renderer.circle_outline(x, y, r, g, b, hitbox_alpha, size, 0, 1, 1)
        
        -- Draw hitbox info
        if hitbox.confidence and hitbox.confidence > 0 then
            local confidence_text = string.format("%.0f%%", hitbox.confidence * 100)
            renderer.text(x, y + size + 5, r, g, b, hitbox_alpha, "c", 0, confidence_text)
        end
        
        ::continue::
    end
end,
    
    get_average_resolver_confidence = function(self)
        local total_confidence = 0
        local count = 0
        
        for _, player_index in ipairs(self.active_players) do
            local data = player_data:get(player_index)
            if data and data.resolver_metadata and data.resolver_metadata.confidence then
                total_confidence = total_confidence + data.resolver_metadata.confidence
                count = count + 1
            end
        end
        
        return count > 0 and total_confidence / count or 0.5
    end,
    
    get_hit_miss_stats = function(self)
        local hit_count = 0
        local miss_count = 0
        
        for _, player_index in ipairs(self.active_players) do
            local data = player_data:get(player_index)
            if data then
                hit_count = hit_count + (data.hit_count or 0)
                miss_count = miss_count + (data.miss_count or 0)
            end
        end
        
        return hit_count, miss_count
    end,
    
    hsv_to_rgb = function(self, h, s, v)
        local r, g, b
        
        local i = math.floor(h * 6)
        local f = h * 6 - i
        local p = v * (1 - s)
        local q = v * (1 - f * s)
        local t = v * (1 - (1 - f) * s)
        
        i = i % 6
        
        if i == 0 then r, g, b = v, t, p
        elseif i == 1 then r, g, b = q, v, p
        elseif i == 2 then r, g, b = p, v, t
        elseif i == 3 then r, g, b = p, q, v
        elseif i == 4 then r, g, b = t, p, v
        elseif i == 5 then r, g, b = v, p, q
        end
        
        return r * 255, g * 255, b * 255
    end,
    
    on_player_hurt = function(self, event)
        -- Process player hurt event
        local attacker = client.userid_to_entindex(event.attacker)
        local victim = client.userid_to_entindex(event.userid)
        
        -- Only process if we're the attacker and victim is an enemy
        if attacker ~= entity.get_local_player() or not entity.is_enemy(victim) then
            return
        end
        
        -- Get player data
        local data = player_data:get(victim)
        if not data then
            return
        end
        
        -- Update hit count
        data.hit_count = (data.hit_count or 0) + 1
        data.last_hit_time = globals.realtime()
        
        -- Add to shot history
        data.shot_history:push({
            hit = true,
            damage = event.dmg_health,
            hitgroup = event.hitgroup,
            time = globals.realtime()
        })
        
        -- Add hit marker
        local pos = {entity.hitbox_position(victim, event.hitgroup)}
        if pos[1] then
            table.insert(self.hit_markers, {
                x = pos[1],
                y = pos[2],
                z = pos[3],
                time = globals.realtime(),
                damage = event.dmg_health,
                hitgroup = event.hitgroup
            })
        end
        
        -- Play hit sound if enabled
        if ui.get(ui_elements.visuals.sound_enabled) then
            local sound_type = ui.get(ui_elements.visuals.sound_type)
            local sound_file = "buttons\\arena_switch_press_02.wav" -- Default
            
            if sound_type == "Headshot" and event.hitgroup == 1 then
                sound_file = "survival\\death_confirmed.wav"
            elseif sound_type == "Skeet" then
                sound_file = "training\\bell_normal.wav"
            end
            
            client.exec(string.format("play %s", sound_file))
        end
        
        -- Update adaptive correction
        player_data:update_adaptive_correction(victim, data)
        
        -- Send hit message
        hit_system:on_hit(event)
        
        if CORSA.DEBUG then
            util.debug(string.format("Hit player %d in hitgroup %d for %d damage", 
                victim, event.hitgroup, event.dmg_health))
        end
    end,
    
    on_bullet_impact = function(self, event)
        -- Process bullet impact event
        local shooter = client.userid_to_entindex(event.userid)
        
        -- Only process if we're the shooter
        if shooter ~= entity.get_local_player() then
            return
        end
        
        -- Add tracer if enabled
        if ui.get(ui_elements.visuals.tracer_enabled) then
            local eye_pos = {client.eye_position()}
            
            if eye_pos[1] then
                table.insert(self.tracers, {
                    start_x = eye_pos[1],
                    start_y = eye_pos[2],
                    start_z = eye_pos[3],
                    end_x = event.x,
                    end_y = event.y,
                    end_z = event.z,
                    time = globals.realtime()
                })
            end
        end
    end,
    
    on_aim_fire = function(self, event)
        -- Process aim fire event
        local target = event.target
        
        -- Get player data
        local data = player_data:get(target)
        if not data then
            return
        end
        
        -- Store shot data for miss detection
        data.last_shot_time = globals.realtime()
        data.last_shot_target = target
        data.last_shot_hitgroup = event.hitgroup
        
        -- Add resolved hitbox
        local pos = {entity.hitbox_position(target, event.hitgroup)}
        if pos[1] then
            table.insert(self.resolved_hitboxes, {
                x = pos[1],
                y = pos[2],
                z = pos[3],
                time = globals.realtime(),
                hitgroup = event.hitgroup,
                size = event.hitgroup == 1 and 8 or 6, -- Head is larger
                confidence = data.resolver_metadata and data.resolver_metadata.confidence or 0
            })
        end
        
        if CORSA.DEBUG then
            util.debug(string.format("Fired at player %d, hitgroup %d, hitchance %.1f%%", 
                target, event.hitgroup, event.hit_chance))
        end
    end,
    
    on_aim_miss = function(self, event)
        -- Process aim miss event
        local target = event.target
        
        -- Get player data
        local data = player_data:get(target)
        if not data then
            return
        end
        
        -- Update miss count
        data.miss_count = (data.miss_count or 0) + 1
        data.last_miss_time = globals.realtime()
        
        -- Add to shot history
        data.shot_history:push({
            hit = false,
            reason = event.reason,
            hitgroup = event.hitgroup,
            time = globals.realtime()
        })
        
        -- Update adaptive correction
        player_data:update_adaptive_correction(target, data)
        
        if CORSA.DEBUG then
            util.debug(string.format("Missed player %d, hitgroup %d, reason: %s", 
                target, event.hitgroup, event.reason))
        end
    end
}

-- Event callbacks
local function on_player_hurt(event)
    resolver:on_player_hurt(event)
end

local function on_bullet_impact(event)
    resolver:on_bullet_impact(event)
end

local function on_aim_fire(event)
    resolver:on_aim_fire(event)
end

local function on_aim_miss(event)
    resolver:on_aim_miss(event)
end

-- Main update function
local function on_paint()
    resolver:update()
    resolver:draw_visuals()
end

-- Set up the reset_data button callback now that player_data is defined
ui.set_callback(ui_elements.resolver.adaptive.reset_data, function()
    -- Reset adaptive learning data
    player_data:reset()
    util.log(CORSA.COLORS.SUCCESS[1], CORSA.COLORS.SUCCESS[2], CORSA.COLORS.SUCCESS[3], 
        "Adaptive learning data reset")
end)

-- UI visibility handling
local function handle_ui_visibility()
    local resolver_enabled = ui.get(ui_elements.resolver.enabled)
    
    -- Main resolver settings
    ui.set_visible(ui_elements.resolver.debug_mode, resolver_enabled)
    ui.set_visible(ui_elements.resolver.backtrack_enabled, resolver_enabled)
    ui.set_visible(ui_elements.resolver.backtrack_time, resolver_enabled and ui.get(ui_elements.resolver.backtrack_enabled))
    ui.set_visible(ui_elements.resolver.history_size, resolver_enabled)
    
    -- Jitter settings
    ui.set_visible(ui_elements.resolver.jitter.enabled, resolver_enabled)
    ui.set_visible(ui_elements.resolver.jitter.mode, resolver_enabled and ui.get(ui_elements.resolver.jitter.enabled))
    ui.set_visible(ui_elements.resolver.jitter.strength, resolver_enabled and ui.get(ui_elements.resolver.jitter.enabled))
    
    -- Desync settings
    ui.set_visible(ui_elements.resolver.desync.enabled, resolver_enabled)
    ui.set_visible(ui_elements.resolver.desync.mode, resolver_enabled and ui.get(ui_elements.resolver.desync.enabled))
    
    -- Fake duck settings
    ui.set_visible(ui_elements.resolver.fake_duck.enabled, resolver_enabled)
    ui.set_visible(ui_elements.resolver.fake_duck.use_velocity, resolver_enabled and ui.get(ui_elements.resolver.fake_duck.enabled))
    ui.set_visible(ui_elements.resolver.fake_duck.detection_threshold, resolver_enabled and ui.get(ui_elements.resolver.fake_duck.enabled))
    
    -- Exploit settings
    ui.set_visible(ui_elements.resolver.exploit.enabled, resolver_enabled)
    ui.set_visible(ui_elements.resolver.exploit.mode, resolver_enabled and ui.get(ui_elements.resolver.exploit.enabled))
    
    -- Defensive AA settings
    ui.set_visible(ui_elements.resolver.defensive_aa.enabled, resolver_enabled)
    ui.set_visible(ui_elements.resolver.defensive_aa.detection_threshold, resolver_enabled and ui.get(ui_elements.resolver.defensive_aa.enabled))
    ui.set_visible(ui_elements.resolver.defensive_aa.correction_angle, resolver_enabled and ui.get(ui_elements.resolver.defensive_aa.enabled))
    ui.set_visible(ui_elements.resolver.defensive_aa.break_lc_detection, resolver_enabled and ui.get(ui_elements.resolver.defensive_aa.enabled))
    
    -- Adaptive settings
    ui.set_visible(ui_elements.resolver.adaptive.enabled, resolver_enabled)
    ui.set_visible(ui_elements.resolver.adaptive.learning_rate, resolver_enabled and ui.get(ui_elements.resolver.adaptive.enabled))
    ui.set_visible(ui_elements.resolver.adaptive.reset_data, resolver_enabled and ui.get(ui_elements.resolver.adaptive.enabled))
    
    -- Prediction settings
    local prediction_enabled = ui.get(ui_elements.prediction.enabled)
    ui.set_visible(ui_elements.prediction.ping_based, prediction_enabled)
    ui.set_visible(ui_elements.prediction.ping_threshold, prediction_enabled and ui.get(ui_elements.prediction.ping_based))
    ui.set_visible(ui_elements.prediction.interp_ratio, prediction_enabled)
    ui.set_visible(ui_elements.prediction.velocity_extrapolation, prediction_enabled)
    ui.set_visible(ui_elements.prediction.extrapolation_factor, prediction_enabled and ui.get(ui_elements.prediction.velocity_extrapolation))
    
    -- Network settings
    ui.set_visible(ui_elements.network.adaptive_interp, resolver_enabled)
    ui.set_visible(ui_elements.network.interp_min, resolver_enabled and ui.get(ui_elements.network.adaptive_interp))
    ui.set_visible(ui_elements.network.interp_max, resolver_enabled and ui.get(ui_elements.network.adaptive_interp))
    ui.set_visible(ui_elements.network.ping_compensation, resolver_enabled)
    ui.set_visible(ui_elements.network.ping_factor, resolver_enabled and ui.get(ui_elements.network.ping_compensation))
    ui.set_visible(ui_elements.network.backtrack_ping_based, resolver_enabled and ui.get(ui_elements.resolver.backtrack_enabled))
    ui.set_visible(ui_elements.network.backtrack_ping_factor, resolver_enabled and ui.get(ui_elements.resolver.backtrack_enabled) and ui.get(ui_elements.network.backtrack_ping_based))
    ui.set_visible(ui_elements.network.packet_loss_detection, resolver_enabled)
    ui.set_visible(ui_elements.network.packet_loss_threshold, resolver_enabled and ui.get(ui_elements.network.packet_loss_detection))
    ui.set_visible(ui_elements.network.packet_loss_compensation, resolver_enabled and ui.get(ui_elements.network.packet_loss_detection))
    
    -- Visual settings
    local visuals_enabled = ui.get(ui_elements.visuals.enabled)
    ui.set_visible(ui_elements.visuals.style, visuals_enabled)
    ui.set_visible(ui_elements.visuals.position, visuals_enabled)
    ui.set_visible(ui_elements.visuals.custom_x, visuals_enabled and ui.get(ui_elements.visuals.position) == "Custom")
    ui.set_visible(ui_elements.visuals.custom_y, visuals_enabled and ui.get(ui_elements.visuals.position) == "Custom")
    ui.set_visible(ui_elements.visuals.color_scheme, visuals_enabled)
    ui.set_visible(ui_elements.visuals.show_statistics, visuals_enabled)
    ui.set_visible(ui_elements.visuals.show_resolver_info, visuals_enabled)
    ui.set_visible(ui_elements.visuals.show_backtrack, visuals_enabled)
    ui.set_visible(ui_elements.visuals.backtrack_style, visuals_enabled and ui.get(ui_elements.visuals.show_backtrack))
    ui.set_visible(ui_elements.visuals.show_defensive_aa, visuals_enabled)
    ui.set_visible(ui_elements.visuals.show_prediction, visuals_enabled)
    ui.set_visible(ui_elements.visuals.show_hitboxes, visuals_enabled)
    ui.set_visible(ui_elements.visuals.hitbox_time, visuals_enabled and ui.get(ui_elements.visuals.show_hitboxes))
    ui.set_visible(ui_elements.visuals.hit_marker, visuals_enabled)
    ui.set_visible(ui_elements.visuals.hit_marker_style, visuals_enabled and ui.get(ui_elements.visuals.hit_marker))
    ui.set_visible(ui_elements.visuals.hit_marker_color, visuals_enabled and ui.get(ui_elements.visuals.hit_marker))
    ui.set_visible(ui_elements.visuals.hit_marker_size, visuals_enabled and ui.get(ui_elements.visuals.hit_marker))
    ui.set_visible(ui_elements.visuals.hit_marker_duration, visuals_enabled and ui.get(ui_elements.visuals.hit_marker))
    ui.set_visible(ui_elements.visuals.tracer_enabled, visuals_enabled)
    ui.set_visible(ui_elements.visuals.tracer_color, visuals_enabled and ui.get(ui_elements.visuals.tracer_enabled))
    ui.set_visible(ui_elements.visuals.tracer_duration, visuals_enabled and ui.get(ui_elements.visuals.tracer_enabled))
    ui.set_visible(ui_elements.visuals.sound_enabled, visuals_enabled)
    ui.set_visible(ui_elements.visuals.sound_type, visuals_enabled and ui.get(ui_elements.visuals.sound_enabled))
    
    -- Player-specific settings
    local player_specific_enabled = ui.get(ui_elements.player_specific.enabled)
    ui.set_visible(ui_elements.player_specific.player_list, player_specific_enabled)
    ui.set_visible(ui_elements.player_specific.override_settings, player_specific_enabled)
    ui.set_visible(ui_elements.player_specific.resolver_mode, player_specific_enabled and ui.get(ui_elements.player_specific.override_settings))
    ui.set_visible(ui_elements.player_specific.correction_strength, player_specific_enabled and ui.get(ui_elements.player_specific.override_settings))
    ui.set_visible(ui_elements.player_specific.backtrack_override, player_specific_enabled and ui.get(ui_elements.player_specific.override_settings))
    ui.set_visible(ui_elements.player_specific.backtrack_time_override, player_specific_enabled and ui.get(ui_elements.player_specific.override_settings) and ui.get(ui_elements.player_specific.backtrack_override))
    ui.set_visible(ui_elements.player_specific.save_settings, player_specific_enabled)
end

-- Update player list for player-specific settings
local function update_player_list()
    if not ui.get(ui_elements.player_specific.enabled) then
        return
    end
    
    local players = entity.get_players(true) -- Only enemies
    local player_names = {}
    
    for _, player_index in ipairs(players) do
        local name = entity.get_player_name(player_index)
        if name then
            table.insert(player_names, string.format("%s (%d)", name, player_index))
        end
    end
    
    -- Update the player list
    ui.update(ui_elements.player_specific.player_list, player_names)
end

-- Register callbacks
local function register_callbacks()
    client.set_event_callback("paint", on_paint)
    client.set_event_callback("player_hurt", on_player_hurt)
    client.set_event_callback("bullet_impact", on_bullet_impact)
    client.set_event_callback("aim_fire", on_aim_fire)
    client.set_event_callback("aim_miss", on_aim_miss)
    
    -- UI callbacks
    ui.set_callback(ui_elements.resolver.enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.resolver.backtrack_enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.resolver.jitter.enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.resolver.desync.enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.resolver.fake_duck.enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.resolver.exploit.enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.resolver.defensive_aa.enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.resolver.adaptive.enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.prediction.enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.prediction.ping_based, handle_ui_visibility)
    ui.set_callback(ui_elements.prediction.velocity_extrapolation, handle_ui_visibility)
    ui.set_callback(ui_elements.network.adaptive_interp, handle_ui_visibility)
    ui.set_callback(ui_elements.network.ping_compensation, handle_ui_visibility)
    ui.set_callback(ui_elements.network.backtrack_ping_based, handle_ui_visibility)
    ui.set_callback(ui_elements.network.packet_loss_detection, handle_ui_visibility)
    ui.set_callback(ui_elements.visuals.enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.visuals.position, handle_ui_visibility)
    ui.set_callback(ui_elements.visuals.show_backtrack, handle_ui_visibility)
    ui.set_callback(ui_elements.visuals.show_hitboxes, handle_ui_visibility)
    ui.set_callback(ui_elements.visuals.hit_marker, handle_ui_visibility)
    ui.set_callback(ui_elements.visuals.tracer_enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.visuals.sound_enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.player_specific.enabled, handle_ui_visibility)
    ui.set_callback(ui_elements.player_specific.override_settings, handle_ui_visibility)
    ui.set_callback(ui_elements.player_specific.backtrack_override, handle_ui_visibility)
    
    -- Update player list periodically
    client.set_event_callback("net_update_end", update_player_list)
    
    -- Set initial UI visibility
    handle_ui_visibility()
    
    -- Log successful registration
    util.log(CORSA.COLORS.SUCCESS[1], CORSA.COLORS.SUCCESS[2], CORSA.COLORS.SUCCESS[3], 
        "Callbacks registered successfully")
end

-- Unregister callbacks on script unload
local function unregister_callbacks()
    client.unset_event_callback("paint", on_paint)
    client.unset_event_callback("player_hurt", on_player_hurt)
    client.unset_event_callback("bullet_impact", on_bullet_impact)
    client.unset_event_callback("aim_fire", on_aim_fire)
    client.unset_event_callback("aim_miss", on_aim_miss)
    client.unset_event_callback("net_update_end", update_player_list)
    
    util.log(CORSA.COLORS.PRIMARY[1], CORSA.COLORS.PRIMARY[2], CORSA.COLORS.PRIMARY[3], 
        "Unloaded successfully")
end

-- Main initialization
local function main()
    -- Initialize
    init()
    
    -- Register callbacks
    register_callbacks()
    
    -- Set up unload callback
    client.set_event_callback("shutdown", unregister_callbacks)
    
    -- Welcome message
    client.color_log(CORSA.COLORS.PRIMARY[1], CORSA.COLORS.PRIMARY[2], CORSA.COLORS.PRIMARY[3], 
        string.format("=== %s v%s ===", CORSA.NAME, CORSA.VERSION))
    client.color_log(CORSA.COLORS.PRIMARY[1], CORSA.COLORS.PRIMARY[2], CORSA.COLORS.PRIMARY[3], 
        "Advanced resolver with defensive AA detection")
    client.color_log(CORSA.COLORS.PRIMARY[1], CORSA.COLORS.PRIMARY[2], CORSA.COLORS.PRIMARY[3], 
        "Created by thj")
    client.color_log(CORSA.COLORS.PRIMARY[1], CORSA.COLORS.PRIMARY[2], CORSA.COLORS.PRIMARY[3], 
        "====================")
end

-- Run main
main()