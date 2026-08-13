--- Lightweight per-glyph headline animation.
---
--- This keeps the reference's value-change and sine-driven letter feel
--- (`reference/Balatro/engine/text.lua:69-120, 215-235`) without its UI-node
--- machinery. The 3DS has no fragment shaders, so every enabled glyph is a CPU
--- transform and draw; callers must keep it to short, static headlines.
local DynaText = {}

local PI = math.pi
local TWO_PI = PI * 2

local function now()
    return love.timer.getTime()
end

--- Create state for one explicitly animated string.
--- All configuration is immutable after construction so update and draw allocate
--- no per-frame tables.
function DynaText.new(config)
    config = config or {}
    local float_amount = tonumber(config.float_amount) or 0
    local rotation_amount = tonumber(config.rotation_amount) or 0
    local bump_amount = tonumber(config.bump_amount) or 0
    local bump_duration = tonumber(config.bump_duration) or 0.18
    return {
        float_amount = float_amount,
        float_speed = tonumber(config.float_speed) or 2.666,
        float_phase = tonumber(config.float_phase) or 1.7,
        rotation_amount = rotation_amount,
        rotation_speed = tonumber(config.rotation_speed) or 2.666,
        rotation_phase = tonumber(config.rotation_phase) or 1.7,
        bump_amount = bump_amount,
        bump_duration = bump_duration,
        rainbow = config.rainbow == true,
        rainbow_speed = tonumber(config.rainbow_speed) or 0.12,
        rainbow_phase = tonumber(config.rainbow_phase) or 0.12,
        -- Per-letter pop-in on value change: each glyph scales up from nothing 0.045 s
        -- after the last, with a paper1 chirp as it appears — the reference's text
        -- reveal (`reference/Balatro/engine/text.lua:156-208`), one of the game's most
        -- recognisable sounds.
        pop_on_change = config.pop_on_change == true,
        pop_stagger = 0.045,
        pop_rise = 0.12,
        animated = float_amount ~= 0 or rotation_amount ~= 0 or bump_amount ~= 0
            or config.rainbow == true or config.pop_on_change == true,
        value = nil,
        bump_start = nil,
        pop_start = nil,
        pop_played = 0,
    }
end

--- Start (or restart) the letter-by-letter reveal.
function DynaText.pop_in(state, time)
    state.pop_start = time or now()
    state.pop_played = 0
end

--- Remember a displayed value and begin its bump only after the initial value.
--- @return string text
function DynaText.update(state, value, time)
    local text = tostring(value or "")
    if state.value == nil then
        state.value = text
        if state.pop_on_change and text ~= "" then DynaText.pop_in(state, time) end
    elseif state.value ~= text then
        state.value = text
        state.bump_start = time or now()
        if state.pop_on_change and text ~= "" then DynaText.pop_in(state, time) end
    end
    return text
end

--- Pop-in scale for a one-based glyph index, 0 (hidden) to 1 (landed). 1 when no
--- reveal is running.
function DynaText.pop_scale(state, index, time)
    local start = state.pop_start
    if not start then return 1 end
    local p = ((time or now()) - start - (index - 1) * state.pop_stagger) / state.pop_rise
    if p < 0 then return 0 end
    if p > 1 then return 1 end
    return p
end

--- Return the vertical offset, rotation, and scale for a one-based glyph index.
function DynaText.letter_transform(state, index, time)
    time = time or now()
    local phase = index - 1
    local y = state.float_amount * math.sin(state.float_speed * time + phase * state.float_phase)
    local rotation = state.rotation_amount
        * math.sin(state.rotation_speed * time + phase * state.rotation_phase)
    local scale = 1
    local bump_start = state.bump_start
    if bump_start then
        local elapsed = time - bump_start
        if elapsed >= 0 and elapsed < state.bump_duration then
            scale = scale + state.bump_amount * math.sin(PI * elapsed / state.bump_duration)
        end
    end
    return y, rotation, scale
end

local function hue_rgb(hue)
    hue = hue - math.floor(hue)
    local sector = hue * 6
    local x = 1 - math.abs(sector % 2 - 1)
    if sector < 1 then return 1, x, 0 end
    if sector < 2 then return x, 1, 0 end
    if sector < 3 then return 0, 1, x end
    if sector < 4 then return 0, x, 1 end
    if sector < 5 then return x, 0, 1 end
    return 1, 0, x
end

--- Draw text in an existing font. Unanimated state deliberately keeps the usual
--- printf path, so adding this helper cannot perturb ordinary UI text. On the
--- 268 MHz Old 3DS, the glyph loop is intentionally reserved for short headlines.
function DynaText.draw(state, value, x, y, width, align, time)
    time = time or now()
    local text = DynaText.update(state, value, time)
    align = align or "left"
    if not state.animated then
        love.graphics.printf(text, x, y, width, align)
        return
    end

    local font = love.graphics.getFont()
    local text_width = font:getWidth(text)
    local pen_x = x
    if align == "center" then
        pen_x = x + (width - text_width) * 0.5
    elseif align == "right" then
        pen_x = x + width - text_width
    end

    local old_r, old_g, old_b, old_a = love.graphics.getColor()
    local glyph_height = font:getHeight()
    for i = 1, #text do
        local glyph = text:sub(i, i)
        local glyph_width = font:getWidth(glyph)
        local offset_y, rotation, scale = DynaText.letter_transform(state, i, time)
        if state.pop_start then
            local p = DynaText.pop_scale(state, i, time)
            scale = scale * p
            if p > 0 and i > state.pop_played then
                state.pop_played = i
                -- Rising chirp per appearing letter (`text.lua:195-203`); long strings
                -- chirp every other letter so a sentence doesn't buzz.
                if Sfx and Sfx.play and (#text < 10 or i % 2 == 0) then
                    Sfx.play("paper1", 0.5 + 0.4 * (i / #text), 0.3)
                end
            end
            if i == #text and p >= 1 then
                state.pop_start = nil
            end
        end
        if state.rainbow then
            local r, g, b = hue_rgb(time * state.rainbow_speed + (i - 1) * state.rainbow_phase)
            love.graphics.setColor(r, g, b, old_a)
        end
        love.graphics.print(glyph, pen_x + glyph_width * 0.5, y + glyph_height * 0.5 + offset_y,
            rotation, scale, scale, glyph_width * 0.5, glyph_height * 0.5)
        pen_x = pen_x + glyph_width
    end
    if state.rainbow then
        love.graphics.setColor(old_r, old_g, old_b, old_a)
    end
end

return DynaText
