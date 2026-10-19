local Milestones = {}
local HOLD, SLIDE = 2.2, 0.22

local function is_safe(game)
    if not game or game.screenwipe then return false end
    if game.hand and (game.hand.is_scoring or game.hand.scoring) then return false end
    if game.joker_emit_busy and game:joker_emit_busy() then return false end
    return true
end

function Milestones.push(game, kind, title, detail)
    if not game or not title then return false end
    game._milestone_queue = game._milestone_queue or {}
    local key = tostring(kind or "milestone") .. ":" .. tostring(title) .. ":" .. tostring(detail or "")
    game._milestone_seen = game._milestone_seen or {}
    if game._milestone_seen[key] then return false end
    game._milestone_seen[key] = true
    game._milestone_queue[#game._milestone_queue + 1] = {
        kind = kind or "milestone", title = tostring(title), detail = tostring(detail or ""), key = key,
    }
    return true
end

function Milestones.update(game, dt)
    if not game then return end
    local active = game._milestone_active
    if not active then
        if not is_safe(game) or not game._milestone_queue or #game._milestone_queue == 0 then return end
        active = table.remove(game._milestone_queue, 1)
        active.age = 0
        game._milestone_active = active
        if Sfx and Sfx.play then
            Sfx.play("highlight1", 1, 0.45)
            Sfx.play("foil2", 1.1, 0.28)
        end
    end
    active.age = active.age + (tonumber(dt) or 0)
    if active.age >= HOLD then game._milestone_active = nil end
end

function Milestones.draw(game)
    local a = game and game._milestone_active
    if not a then return end
    local C = game.C
    local reduced = game.SETTINGS and game.SETTINGS.REDUCED_MOTION == true
    local Fonts = require("fonts")
    local label = a.title .. (a.detail ~= "" and (": " .. a.detail) or "")
    local width, height = 304, 14
    local font = Fonts.fit(game, game.FONTS.PIXEL.SMALL, label, width - 8)
    local rest_y, hidden_y = 226, 244
    local edge = math.max(0, math.min(a.age / SLIDE, (HOLD - a.age) / SLIDE, 1))
    local y = reduced and rest_y or (hidden_y + (rest_y - hidden_y) * edge)
    love.graphics.push()
    love.graphics.setColor(C.ORANGE)
    love.graphics.rectangle("fill", 48, y, width, height, 3, 3)
    love.graphics.setColor(C.BLACK or C.BLOCK.BACK)
    love.graphics.rectangle("fill", 49, y + 1, width - 2, height - 2, 3, 3)
    love.graphics.setFont(font)
    love.graphics.setColor(C.WHITE)
    local scale = math.min(1, (width - 8) / math.max(1, font:getWidth(label)), (height - 2) / font:getHeight())
    love.graphics.translate(48 + (width - font:getWidth(label) * scale) / 2, y + (height - font:getHeight() * scale) / 2)
    love.graphics.scale(scale, scale)
    love.graphics.print(label, 0, 0)
    love.graphics.pop()
end

return Milestones
