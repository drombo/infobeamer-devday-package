gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

sys.set_flag("slow_gc")

local json = require "json"
local schedule
local current_room

local best_width = 1920
local best_height = 1200
local scale_width = WIDTH / best_width
local scale_height = HEIGHT / best_height

local font_size_header = 100 * scale_height
local font_size_top_line = font_size_header * 0.8
local font_size_text = font_size_top_line * 0.75
local line_spacing = font_size_header * 0.2

local line1_y = line_spacing/2
local line2_y = line1_y + font_size_header
local line3_y = line2_y + font_size_top_line + line_spacing * 2
local spacer_y = line3_y + font_size_top_line
local line4_y = spacer_y + line_spacing

local col1_x = 30 * scale_width
local col2_x = 300 * scale_width
local col3_x = WIDTH - 1000 * scale_width

util.resource_loader {
    "progress.frag",
}

local white = resource.create_colored_texture(1, 1, 1)

util.file_watch("schedule.json", function(content)
    print("reloading schedule")
    schedule = json.decode(content)
end)

local rooms
local spacer = white

node.event("config_update", function(config)
    rooms = {}
    for idx, room in ipairs(config.rooms) do
        if room.serial == sys.get_env("SERIAL") then
            print("found my room")
            current_room = room
        end
        rooms[room.name] = room
    end
    spacer = resource.create_colored_texture(CONFIG.foreground_color.rgba())
end)

hosted_init()

local base_time = N.base_time or 0
local current_talk
local all_talks = {}
local day = 0

function get_now()
    return base_time + sys.now()
end

function check_next_talk()
    local now = get_now()
    local room_next = {}
    for idx, talk in ipairs(schedule) do
        if rooms[talk.place] and not room_next[talk.place] and talk.start_unix + 45 * 60 > now then
            room_next[talk.place] = talk
        end
    end

    for room, talk in pairs(room_next) do
        talk.slide_lines = wrap(talk.title, 50)

        if #talk.title > 17 then
            talk.lines = wrap(talk.title, 50)
            if #talk.lines == 1 then
                talk.lines[2] = table.concat(talk.speakers, ", ")
            end
        end

        talk.slide_abstract = wrap(talk.abstract, 80)
    end

    if room_next[current_room.name] then
        current_talk = room_next[current_room.name]
    else
        current_talk = nil
    end

    all_talks = {}
    for room, talk in pairs(room_next) do
        if current_talk and room ~= current_talk.place then
            all_talks[#all_talks + 1] = talk
        end
    end
    table.sort(all_talks, function(a, b)
        if a.start_unix < b.start_unix then
            return true
        elseif a.start_unix > b.start_unix then
            return false
        else
            return a.place < b.place
        end
    end)
end

-- wrap talk titles
function wrap(str, limit, indent, indent1)
    limit = limit or 72
    local here = 1
    local wrapped = str:gsub("(%s+)()(%S+)()", function(sp, st, word, fi)
        if fi - here > limit then
            here = st
            return "\n" .. word
        end
    end)
    local splitted = {}
    for token in string.gmatch(wrapped, "[^\n]+") do
        splitted[#splitted + 1] = token
    end
    return splitted
end

local clock = (function()
    local base_time = N.base_time or 0

    local function set(time)
        base_time = tonumber(time) - sys.now()
    end

    util.data_mapper {
        ["clock/midnight"] = function(since_midnight)
            print("NEW midnight", since_midnight)
            set(since_midnight)
        end;
    }

    local function get()
        local time = (base_time + sys.now()) % 86400
        return string.format("%d:%02d", math.floor(time / 3600), math.floor(time % 3600 / 60))
    end

    return {
        get = get;
        set = set;
    }
end)()

util.data_mapper {
    ["clock/set"] = function(time)
        base_time = tonumber(time) - sys.now()
        N.base_time = base_time
        check_next_talk()
        print("UPDATED TIME", base_time)
    end;
    ["clock/day"] = function(new_day)
        day = new_day
        print("UPDATED DAY", new_day)
    end;
}

function switcher(get_screens)
    local current_idx = 0
    local current
    local current_state

    local switch = sys.now()
    local switched = sys.now()

    local blend = 0.8
    local mode = "switch"

    local old_screen
    local current_screen

    local screens = get_screens()

    local function prepare()
        local now = sys.now()
        if now > switch and mode == "show" then
            mode = "switch"
            switched = now

            -- snapshot old screen
            gl.clear(CONFIG.background_color.rgb_with_a(0.0))
            if current then
                current.draw(current_state)
            end
            old_screen = resource.create_snapshot()

            -- find next screen
            current_idx = current_idx + 1
            if current_idx > #screens then
                screens = get_screens()
                current_idx = 1
            end
            current = screens[current_idx]
            switch = now + current.time
            current_state = current.prepare()

            -- snapshot next screen
            gl.clear(CONFIG.background_color.rgb_with_a(0.0))
            current.draw(current_state)
            current_screen = resource.create_snapshot()
        elseif now - switched > blend and mode == "switch" then
            if current_screen then
                current_screen:dispose()
            end
            if old_screen then
                old_screen:dispose()
            end
            current_screen = nil
            old_screen = nil
            mode = "show"
        end
    end

    local function draw()
        local now = sys.now()

        local percent = ((now - switched) / (switch - switched)) * 3.14129 * 2 - 3.14129
        progress:use { percent = percent }
        white:draw(WIDTH - 50, HEIGHT - 50, WIDTH - 10, HEIGHT - 10)
        progress:deactivate()

        if mode == "switch" then
            local progress = (now - switched) / blend
            gl.pushMatrix()
            gl.translate(WIDTH / 2, 0)
            if progress < 0.5 then
                gl.rotate(180 * progress, 0, 1, 0)
                gl.translate(-WIDTH / 2, 0)
                old_screen:draw(0, 0, WIDTH, HEIGHT)
            else
                gl.rotate(180 + 180 * progress, 0, 1, 0)
                gl.translate(-WIDTH / 2, 0)
                current_screen:draw(0, 0, WIDTH, HEIGHT)
            end
            gl.popMatrix()
        else
            current.draw(current_state)
        end
    end

    return {
        prepare = prepare;
        draw = draw;
    }
end

local content = switcher(function()
    return {
        {
            time = CONFIG.other_rooms,
            prepare = function()
                local content = {}

                local function add_content(func)
                    content[#content + 1] = func
                end

                local function mk_spacer(y)
                    return function()
                        spacer:draw(0, y, WIDTH, y + 2, 0.6)
                    end
                end

                -- multi line
                local function mk_talkmulti(y, talk, is_running)
                    local alpha
                    if is_running then
                        alpha = 0.5
                    else
                        alpha = 1.0
                    end

                    local line_idx = 999999
                    local top_line
                    local bottom_line
                    local function next_line()
                        line_idx = line_idx + 1
                        if line_idx > #talk.lines then
                            line_idx = 2
                            top_line = talk.lines[1]
                            bottom_line = talk.lines[2] or ""
                        else
                            top_line = bottom_line
                            bottom_line = talk.lines[line_idx]
                        end
                    end

                    next_line()

                    local switch = sys.now() + 3

                    return function()
                        CONFIG.font:write(col1_x, y, talk.start_str, font_size_text, CONFIG.foreground_color.rgb_with_a(alpha))
                        CONFIG.font:write(col2_x, y, rooms[talk.place].name_short, font_size_text, CONFIG.foreground_color.rgb_with_a(alpha))
                        CONFIG.font:write(col3_x, y, top_line, font_size_text / 2, CONFIG.foreground_color.rgb_with_a(alpha))
                        CONFIG.font:write(col3_x, y + (font_size_text / 2) + 2, bottom_line, font_size_text / 2, CONFIG.foreground_color.rgb_with_a(alpha * 0.8))

                        if sys.now() > switch then
                            next_line()
                            switch = sys.now() + 1
                        end
                    end
                end

                -- single line
                local function mk_talk(y, talk, is_running)
                    local alpha
                    if is_running then
                        alpha = 0.5
                    else
                        alpha = 1.0
                    end

                    return function()
                        CONFIG.font:write(col1_x, y, talk.start_str, font_size_text, CONFIG.foreground_color.rgb_with_a(alpha))
                        CONFIG.font:write(col2_x, y, rooms[talk.place].name_short, font_size_text, CONFIG.foreground_color.rgb_with_a(alpha))
                        CONFIG.font:write(col3_x, y, talk.title, font_size_text, CONFIG.foreground_color.rgb_with_a(alpha))
                    end
                end

                local y = line4_y
                local time_sep = false
                if #all_talks > 0 then
                    for idx, talk in ipairs(all_talks) do
                        if not time_sep and talk.start_unix > get_now() then
                            if idx > 1 then
                                y = y + 5
                                add_content(mk_spacer(y))
                                y = y + 20
                            end
                            time_sep = true
                        end
                        if talk.lines then
                            add_content(mk_talkmulti(y, talk, not time_sep))
                        else
                            add_content(mk_talk(y, talk, not time_sep))
                        end
                        -- abstand 'other talks' zeilen
                        y = y + 80
                    end
                end

                return content
            end;
            
            draw = function(content)
                CONFIG.font:write(col2_x, line3_y, "Other talks", font_size_top_line, CONFIG.foreground_color.rgba())
                spacer:draw(0, spacer_y, WIDTH, spacer_y + 2, 0.6)
                if #all_talks > 0 then
                    for _, func in ipairs(content) do
                        func()
                    end
                else
                    CONFIG.font:write(col2_x, line4_y, "No other talks.", font_size_text, CONFIG.foreground_color.rgba())
                end
            end
        }, {
            time = CONFIG.current_room,
            prepare = function()
            end;
            draw = function()
                if not current_talk then
                    CONFIG.font:write(col2_x, line3_y, "Next talk", font_size_top_line, CONFIG.foreground_color.rgba())
                    spacer:draw(0, spacer_y, WIDTH, spacer_y + 2, 0.6)
                    CONFIG.font:write(col2_x, line4_y, "Nope. That's it.", font_size_text, CONFIG.foreground_color.rgba())
                else
                    local delta = current_talk.start_unix - get_now()
                    if delta > 0 then
                        CONFIG.font:write(col2_x, line3_y, "Next talk", font_size_top_line, CONFIG.foreground_color.rgba())
                    else
                        CONFIG.font:write(col2_x, line3_y, "This talk", font_size_top_line, CONFIG.foreground_color.rgba())
                    end
                    spacer:draw(0, spacer_y, WIDTH, spacer_y + 2, 0.6)

                    CONFIG.font:write(col1_x, line4_y, current_talk.start_str, font_size_text, CONFIG.foreground_color.rgba())

                    if delta > 180 * 60 then
                        CONFIG.font:write(col1_x, line4_y + font_size_text, string.format("in %d h", math.floor(delta / 3660) + 1), font_size_text, CONFIG.foreground_color.rgb_with_a(0.8))
                    elseif delta > 0 then
                        CONFIG.font:write(col1_x, line4_y + font_size_text, string.format("in %d min", math.floor(delta / 60) + 1), font_size_text, CONFIG.foreground_color.rgb_with_a(0.8))
                    end

                    -- Talk im aktuellen Raum
                    for idx, line in ipairs(current_talk.slide_lines) do
                        if idx >= 5 then
                            break
                        end
                        CONFIG.font:write(col2_x, line4_y - font_size_text + font_size_text * idx, line, font_size_text, CONFIG.foreground_color.rgba())
                    end

                    for idx, abstract in ipairs(current_talk.slide_abstract) do
                        if idx >= 15 then
                            break
                        end
                        CONFIG.font:write(col2_x, 150+line4_y - 32 + 32 * idx, abstract, 30, CONFIG.foreground_color.rgba())
                    end

                    for i, speaker in ipairs(current_talk.speakers) do
                        CONFIG.font:write(col2_x, HEIGHT - 200 + 50 * i, speaker, font_size_text, CONFIG.foreground_color.rgb_with_a(0.8))
                    end
                end
            end
        },
    }
end)

function node.render()
    if base_time == 0 then
        return
    end

    content.prepare()

    CONFIG.background_color.clear()
    util.draw_correct(CONFIG.background.ensure_loaded(), 0, 0, WIDTH, HEIGHT)

    -- zeichne Logo (302x80)
    util.draw_correct(CONFIG.logo.ensure_loaded(), 20, line1_y, 350, font_size_header))

    -- zeichne Uhrzeit
    clock_width = CONFIG.font:width(clock.get(), font_size_header)
    CONFIG.font:write(WIDTH - clock_width - 10 , line1_y, clock.get(), font_size_header, CONFIG.foreground_color.rgba())

    -- Zeichne Raumname
    CONFIG.font:write(col2_x, line2_y, current_room.name_short, font_size_header, CONFIG.foreground_color.rgba())


    local fov = math.atan2(HEIGHT, WIDTH * 2) * 360 / math.pi
    gl.perspective(fov, WIDTH / 2, HEIGHT / 2, -WIDTH, WIDTH / 2, HEIGHT / 2, 0)

    content.draw()
end
