--- Role-based 3DS gamepad bindings (A/B/X/Y/L/R/ZL/ZR).
local InputBindings = {}

InputBindings.SLOTS_PER_ROLE = 2

InputBindings.ROLES = {
    "confirm",
    "cancel",
    "use",
    "sort",
    "shoulder_l",
    "shoulder_r",
}

InputBindings.REBINDABLE_BUTTONS = {
    a = true,
    b = true,
    x = true,
    y = true,
    leftshoulder = true,
    rightshoulder = true,
}

InputBindings._triggers_enabled = false

InputBindings.DEFAULT_BINDINGS = {
    confirm = "a",
    cancel = "b",
    use = "x",
    sort = "y",
    shoulder_l = "leftshoulder",
    shoulder_r = "rightshoulder",
}

InputBindings.GESTURES = {
    sort_tap_max_ms = 250,
    shop_exit_hold_ms = 400,
    sweep_seed_hold_ms = 250,
}

InputBindings.HOLD_ROLES = {
    confirm = true,
    cancel = true,
    sort = true,
}

local ROLE_LABELS = {
    confirm = "Confirm",
    cancel = "Cancel",
    use = "Use",
    sort = "Sort",
    shoulder_l = "Show Jokers",
    shoulder_r = "Show Consumables",
}

local BUTTON_LABELS = {
    a = "A",
    b = "B",
    x = "X",
    y = "Y",
    leftshoulder = "L",
    rightshoulder = "R",
    righttrigger = "ZR",
    lefttrigger = "ZL",
}

local ROLE_HINTS = {
    confirm = "Tap: Select; Hold+D-pad: Reorder",
    cancel = "Tap: Discard/Sell; Hold: Exit shop",
    use = "Tap: Play / Buy & Use",
    sort = "Tap: Sort; Hold+D-pad: Sweep",
    shoulder_l = "Toggle jokers panel",
    shoulder_r = "Toggle consumables panel",
}

local function normalize_role_bindings(data, fallback_single)
    local out = {}
    if type(data) == "string" then
        data = { data }
    elseif type(data) ~= "table" then
        if type(fallback_single) == "string" then
            data = { fallback_single }
        else
            return out
        end
    end
    for i = 1, InputBindings.SLOTS_PER_ROLE do
        local btn = data[i]
        if type(btn) == "string" and InputBindings.REBINDABLE_BUTTONS[btn] then
            out[i] = btn
        end
    end
    return out
end

local function copy_bindings(bindings)
    local out = {}
    for _, role in ipairs(InputBindings.ROLES) do
        local src = bindings and bindings[role]
        local fb = InputBindings.DEFAULT_BINDINGS[role]
        out[role] = normalize_role_bindings(src, fb)
        if not next(out[role]) and type(fb) == "string" then
            out[role] = { [1] = fb }
        end
    end
    return out
end

function InputBindings.default_settings()
    return {
        bindings = copy_bindings(InputBindings.DEFAULT_BINDINGS),
    }
end

function InputBindings.normalize_bindings(data)
    local out = copy_bindings(InputBindings.DEFAULT_BINDINGS)
    if type(data) ~= "table" then return out end

    for _, role in ipairs(InputBindings.ROLES) do
        local normalized = normalize_role_bindings(data[role], InputBindings.DEFAULT_BINDINGS[role])
        if next(normalized) then
            out[role] = normalized
        end
    end
    return out
end

function InputBindings.normalize_controls(data)
    local out = InputBindings.default_settings()
    if type(data) ~= "table" then return out end
    out.bindings = InputBindings.normalize_bindings(data.bindings)
    return out
end

function InputBindings.get_bindings(game)
    local controls = game and game.SETTINGS and game.SETTINGS.CONTROLS
    if controls and type(controls.bindings) == "table" then
        return controls.bindings
    end
    return copy_bindings(InputBindings.DEFAULT_BINDINGS)
end

function InputBindings.get_role_buttons(role, bindings)
    if type(role) ~= "string" then return {} end
    bindings = bindings or copy_bindings(InputBindings.DEFAULT_BINDINGS)
    local out = {}
    for i = 1, InputBindings.SLOTS_PER_ROLE do
        local btn = InputBindings.get_role_slot_button(role, i, bindings)
        if btn then
            out[#out + 1] = btn
        end
    end
    return out
end

function InputBindings.get_role_slot_button(role, slot, bindings)
    slot = math.floor(tonumber(slot) or 0)
    if slot < 1 or slot > InputBindings.SLOTS_PER_ROLE then return nil end
    bindings = bindings or copy_bindings(InputBindings.DEFAULT_BINDINGS)
    local data = bindings[role]
    if type(data) == "string" then
        return slot == 1 and data or nil
    end
    if type(data) ~= "table" then return nil end
    local btn = data[slot]
    if type(btn) == "string" and InputBindings.REBINDABLE_BUTTONS[btn] then
        return btn
    end
    return nil
end

function InputBindings.get_role_for_button(button, bindings)
    if type(button) ~= "string" or button == "" then return nil end
    bindings = bindings or copy_bindings(InputBindings.DEFAULT_BINDINGS)
    for _, role in ipairs(InputBindings.ROLES) do
        for _, btn in ipairs(InputBindings.get_role_buttons(role, bindings)) do
            if btn == button then
                return role
            end
        end
    end
    return nil
end

function InputBindings.get_button_for_role(role, bindings)
    return InputBindings.get_role_slot_button(role, 1, bindings)
end

function InputBindings.is_role(button, role, bindings)
    if type(role) ~= "string" then return false end
    for _, btn in ipairs(InputBindings.get_role_buttons(role, bindings)) do
        if btn == button then return true end
    end
    return false
end

function InputBindings.is_menu_activate(button, bindings)
    return InputBindings.is_role(button, "confirm", bindings)
        or InputBindings.is_role(button, "sort", bindings)
end

function InputBindings.is_menu_back(button, bindings)
    return InputBindings.is_role(button, "cancel", bindings)
        or InputBindings.is_role(button, "use", bindings)
end

function InputBindings.set_role_slot_binding(bindings, role, slot, button)
    if type(role) ~= "string" then return false end
    slot = math.floor(tonumber(slot) or 0)
    if slot < 1 or slot > InputBindings.SLOTS_PER_ROLE then return false end
    if button ~= nil and not InputBindings.REBINDABLE_BUTTONS[button] then
        return false
    end
    bindings = bindings or copy_bindings(InputBindings.DEFAULT_BINDINGS)
    local slots = { nil, nil }
    for i = 1, InputBindings.SLOTS_PER_ROLE do
        slots[i] = InputBindings.get_role_slot_button(role, i, bindings)
    end
    if button == nil then
        slots[slot] = nil
    else
        slots[slot] = button
        for i = 1, InputBindings.SLOTS_PER_ROLE do
            if i ~= slot and slots[i] == button then
                slots[i] = nil
            end
        end
    end
    bindings[role] = {}
    for i = 1, InputBindings.SLOTS_PER_ROLE do
        if slots[i] then
            bindings[role][i] = slots[i]
        end
    end
    return true
end

function InputBindings.set_role_binding(bindings, role, button)
    return InputBindings.set_role_slot_binding(bindings, role, 1, button)
end

function InputBindings.reset_bindings(bindings)
    local defaults = copy_bindings(InputBindings.DEFAULT_BINDINGS)
    for _, role in ipairs(InputBindings.ROLES) do
        bindings[role] = {}
        for i = 1, InputBindings.SLOTS_PER_ROLE do
            local btn = defaults[role][i]
            if btn then
                bindings[role][i] = btn
            end
        end
    end
    return bindings
end

function InputBindings.role_label(role)
    return ROLE_LABELS[role] or tostring(role or "?")
end

function InputBindings.button_label(button)
    if button == nil or button == "" then return "-" end
    return BUTTON_LABELS[button] or tostring(button)
end

function InputBindings.slot_label(role, slot, bindings)
    local btn = InputBindings.get_role_slot_button(role, slot, bindings)
    if not btn then return "-" end
    return InputBindings.button_label(btn)
end

function InputBindings.role_hint(role)
    return ROLE_HINTS[role] or ""
end

function InputBindings.apply_to_game(game)
    if not game then return end
    if type(game.SETTINGS) ~= "table" then return end
    game.SETTINGS.CONTROLS = InputBindings.normalize_controls(game.SETTINGS.CONTROLS)
end

InputBindings.N3DS_ONLY_BUTTONS = {
    lefttrigger = true,
    righttrigger = true,
}

InputBindings.TRIGGER_AXIS_THRESHOLD = 0.5

--- LovePotion reports ZL/ZR as axes (`lefttrigger` / `righttrigger`, sometimes `triggerleft` / `triggerright`).
InputBindings.AXIS_TO_TRIGGER_BUTTON = {
    lefttrigger = "lefttrigger",
    righttrigger = "righttrigger",
    triggerleft = "lefttrigger",
    triggerright = "righttrigger",
}

function InputBindings.is_trigger_button(button)
    return type(button) == "string" and InputBindings.N3DS_ONLY_BUTTONS[button] == true
end

function InputBindings.axis_to_trigger_button(axis)
    if type(axis) ~= "string" then return nil end
    return InputBindings.AXIS_TO_TRIGGER_BUTTON[axis]
end

--- Map alternate ZL/ZR names to stored/rebindable ids (`lefttrigger` / `righttrigger`).
function InputBindings.normalize_gamepad_button(button)
    if type(button) ~= "string" then return button end
    return InputBindings.AXIS_TO_TRIGGER_BUTTON[button] or button
end

function InputBindings.triggers_enabled()
    return InputBindings._triggers_enabled == true
end

function InputBindings.refresh_rebindable_buttons()
    InputBindings.REBINDABLE_BUTTONS = {
        a = true,
        b = true,
        x = true,
        y = true,
        leftshoulder = true,
        rightshoulder = true,
    }
    if InputBindings._triggers_enabled then
        InputBindings.REBINDABLE_BUTTONS.lefttrigger = true
        InputBindings.REBINDABLE_BUTTONS.righttrigger = true
    end
end

--- O3DS has 2 ARM11 cores; New 3DS has more (LovePotion on 3DS only).
function InputBindings.detect_console_capabilities()
    InputBindings._triggers_enabled = false

    if love and love._console and love._console == "3ds" then
        if love.system and love.system.getProcessorCount then
            local count = love.system.getProcessorCount()
            if count ~= 2 then
                InputBindings._triggers_enabled = true
            end
        end
    else
        -- Desktop / non-3DS: allow ZL/ZR for keyboard testing.
        InputBindings._triggers_enabled = true
    end

    InputBindings.refresh_rebindable_buttons()
    return InputBindings._triggers_enabled
end

function InputBindings.safe_is_trigger_down(joy, button)
    if not InputBindings.is_trigger_button(button) then return false end
    if not joy or not joy.getGamepadAxis then return false end
    local axes = { button }
    if button == "lefttrigger" then
        axes = { "lefttrigger", "triggerleft" }
    elseif button == "righttrigger" then
        axes = { "righttrigger", "triggerright" }
    end
    local threshold = InputBindings.TRIGGER_AXIS_THRESHOLD
    for _, axis in ipairs(axes) do
        local ok, value = pcall(function()
            return joy:getGamepadAxis(axis)
        end)
        if ok and (tonumber(value) or 0) > threshold then
            return true
        end
    end
    return false
end

function InputBindings.safe_is_gamepad_down(joy, button)
    if InputBindings.is_trigger_button(button) then
        return InputBindings.safe_is_trigger_down(joy, button)
    end
    if not joy or not joy.isGamepad or not joy:isGamepad() then return false end
    if type(button) ~= "string" or button == "" then return false end
    local ok, pressed = pcall(function()
        return joy:isGamepadDown(button) == true
    end)
    return ok and pressed == true
end

--- Build a map of pressed buttons; skips unsupported names (e.g. ZL/ZR on O3DS).
function InputBindings.build_gamepad_down_map(joy, button_set)
    local down = {}
    if not joy or not joy.isGamepad or not joy:isGamepad() then return down end
    local set = button_set or InputBindings.REBINDABLE_BUTTONS
    for btn in pairs(set) do
        if InputBindings.safe_is_gamepad_down(joy, btn) then
            down[btn] = true
        end
    end
    return down
end

function InputBindings.is_rebindable_button(button)
    return type(button) == "string" and InputBindings.REBINDABLE_BUTTONS[button] == true
end

return InputBindings
