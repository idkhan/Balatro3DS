---@class Game
Game = Object:extend()

---@param seed number|nil Optional seed for the RNG. If nil, a seed is generated (os.time()).
function Game:init(seed)
    G = self
    -- core containers/state
    self.nodes = {}
    self.dragging = nil
    self.touch_start_x = 0
    self.touch_start_y = 0
    self.pending_discard = {}
    self.discard_timer = 0
    self.selectedHand = -1
    self.selectedHandLevel = 1
    self.selectedHandChips = 0
    self.selectedHandMult = 0
    self.active_tooltip_card = nil
    self.round_score = 0
    self.last_hand_score = 0
    --- Run currency
    self.money = 0
    -- Run Discards
    self.discards = 5
    -- Run Hands
    self.hands = 5
    -- Round Count
    self.round = 1
    -- Ante Count
    self.ante = 1
    self._collidables_buf = {}
    self._gc_timer = 0
    self._gc_discarded_nodes = 0
    --- Staggered joker resolution (left-to-right); see `begin_joker_emit` / `_update_joker_emit_queue`.
    self._joker_emit_queue = nil
    self._joker_emit_next = 1
    self._joker_emit_timer = 0
    self.JOKER_EMIT_INTERVAL = 0.5

    -- Pull all shared globals from globals.lua
    if self.set_globals then
        self:set_globals()
    end

    if seed ~= nil then
        self.SEED = seed
    end
    math.randomseed(self.SEED)
    collectgarbage("setpause", 110)
    collectgarbage("setstepmul", 200)

    -- set filters and load atlases
    self:set_render_settings()

    -- Create joker slots + initial joker instances.
    -- (Top-screen rendering is handled by `TopUI.draw()`)
    self:init_jokers()
end

function Game:add(node)
    table.insert(self.nodes, node)
    return node
end

function Game:remove(node)
    for i, n in ipairs(self.nodes) do
        if n == node then
            table.remove(self.nodes, i)
            return true
        end
    end
    return false
end

function Game:draw()
    -- Dark panel behind the entire joker row (bottom screen).
    if self.jokers_on_bottom == true and self.jokers then
        local slot_count = self.joker_capacity or self.joker_slot_count or #self.jokers
        local slot_w = self.joker_slot_w or 71
        local slot_h = self.joker_slot_h or 95
        local slot_gap = self.joker_slot_gap or 8
        local s = self.joker_slot_scale_bottom or 1

        local total_w_base = slot_count * slot_w + (slot_count - 1) * slot_gap
        local panel_x = self.joker_slot_start_x_bottom or 0
        local panel_y = self.joker_slot_y_bottom or 20
        local panel_w = total_w_base * s
        local panel_h = slot_h * s

        -- Extra padding so jokers don't touch the panel edges.
        local panel_pad = 4
        local panel_pad_scaled = panel_pad * s
        panel_x = panel_x - panel_pad_scaled
        panel_y = panel_y - panel_pad_scaled
        panel_w = panel_w + (panel_pad_scaled * 2)
        panel_h = panel_h + (panel_pad_scaled * 2)

        local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
        if _G.draw_rect_with_shadow then
            draw_rect_with_shadow(
                panel_x, panel_y, panel_w, panel_h,
                4, 2,
                G and G.C and G.C.BLOCK and G.C.BLOCK.BACK or { 0, 0, 0, 1 },
                G and G.C and G.C.BLOCK and G.C.BLOCK.SHADOW or { 0, 0, 0, 1 },
                2
            )
        else
            love.graphics.setColor(G and G.C and G.C.PANEL or { 0.2, 0.2, 0.2, 1 })
            love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
        end
        love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
    end

    for _, node in ipairs(self.nodes) do
        node:draw()
    end
end

function Game:update(dt)
    self:_update_joker_emit_queue(dt)
    for _, node in ipairs(self.nodes) do
        if node.update then
            node:update(dt)
        end
    end
    if self.hand and self.hand.update then
        self.hand:update(dt)
    end
    self:check_collisions(dt)

    -- Determine whether the joker slide animation is still running.
    -- While sliding, guides should move with jokers; afterward, guides lock to slot geometry.
    if self.jokers_sliding == true then
        self.jokers_slide_time_left = (self.jokers_slide_time_left or 0) - dt
        local all_snapped = true
        if self.jokers then
            for _, j in ipairs(self.jokers) do
                if j and j.VT and j.T then
                    local dx = math.abs((j.VT.x or 0) - (j.T.x or 0))
                    local dy = math.abs((j.VT.y or 0) - (j.T.y or 0))
                    local ds = math.abs((j.VT.scale or 0) - (j.T.scale or 0))
                    if dx > 0.6 or dy > 0.6 or ds > 0.02 then
                        all_snapped = false
                        break
                    end
                end
            end
        end

        if all_snapped == true or (self.jokers_slide_time_left or 0) <= 0 then
            self.jokers_sliding = false
            self.jokers_slide_time_left = 0
        end
    end

    local removed_nodes = 0
    self.discard_timer = self.discard_timer + dt
    for i = #self.pending_discard, 1, -1 do
        local entry = self.pending_discard[i]
        if self.discard_timer >= entry.remove_after then
            self:remove(entry.node)
            table.remove(self.pending_discard, i)
            removed_nodes = removed_nodes + 1
        end
    end

    if removed_nodes > 0 then
        self._gc_discarded_nodes = self._gc_discarded_nodes + removed_nodes
        if self._gc_discarded_nodes >= 24 then
            self._gc_discarded_nodes = 0
            collectgarbage("collect")
        end
    end

    -- Small periodic incremental GC step to smooth frame spikes on 3DS.
    self._gc_timer = self._gc_timer + dt
    if self._gc_timer >= 0.2 then
        self._gc_timer = 0
        collectgarbage("step", 96)
    end
end

function Game:rects_overlap(a, b)
    return a.x < b.x + b.w and
           a.x + a.w > b.x and
           a.y < b.y + b.h and
           a.y + a.h > b.y
end

function Game:get_overlap(a, b)
    local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
    local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
    return ox, oy
end

function Game:check_collisions(dt)
    if not self.dragging then
        for _, node in ipairs(self.nodes) do
            if node.states then
                node.states.collide.is = false
            end
        end
        return
    end
    
    local collidables = self._collidables_buf
    for i = #collidables, 1, -1 do
        collidables[i] = nil
    end
    for _, node in ipairs(self.nodes) do
        if node.states and node.states.collide.can then
            table.insert(collidables, node)
        end
    end
    
    local nudge_strength = 200 * dt
    local deadzone = 3
    local max_overlap = 40

    local held = self.dragging
    local rect_held = held:get_collision_rect()

    for _, other in ipairs(collidables) do
        if other ~= held then
            local rect_other = other:get_collision_rect()

            if self:rects_overlap(rect_held, rect_other) then
                local ox, oy = self:get_overlap(rect_held, rect_other)
                local min_overlap = math.min(ox, oy)

                if min_overlap > max_overlap then
                    other.states.collide.is = false
                elseif min_overlap < deadzone then
                    other.states.collide.is = true
                else
                    other.states.collide.is = true

                    local center_hx = rect_held.x + rect_held.w / 2
                    local center_hy = rect_held.y + rect_held.h / 2
                    local center_ox = rect_other.x + rect_other.w / 2
                    local center_oy = rect_other.y + rect_other.h / 2

                    local dx = center_ox - center_hx
                    local dy = center_oy - center_hy

                    if ox < oy then
                        local nudge = (dx > 0 and 1 or -1) * nudge_strength
                        other.collision_offset.x = other.collision_offset.x + nudge
                    else
                        local nudge = (dy > 0 and 1 or -1) * nudge_strength
                        other.collision_offset.y = other.collision_offset.y + nudge
                    end
                end
            else
                other.states.collide.is = false
            end
        end
    end

    -- Decay offset so cards return to original position when collision ends
    for _, node in ipairs(collidables) do
        local decay = 5 * dt
        node.collision_offset.x = node.collision_offset.x * (1 - decay)
        node.collision_offset.y = node.collision_offset.y * (1 - decay)
    end
end

function Game:point_in_rect(px, py, node)
    local r = node.get_collision_rect and node:get_collision_rect() or nil
    if not r then
        local t = node.VT or node.T
        r = { x = t.x, y = t.y, w = t.w * t.scale, h = t.h * t.scale }
    end
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

function Game:get_node_at(x, y)
    for i = #self.nodes, 1, -1 do
        local node = self.nodes[i]
        if node.states and node.states.click.can and self:point_in_rect(x, y, node) then
            return node
        end
    end
    return nil
end

function Game:init_jokers()
    -- Owned Jokers live in `self.jokers` (packed left-to-right).
    -- `self.joker_capacity` defines the fixed UI slot count (panel size),
    -- and does NOT change the number of owned nodes.
    self.jokers = {}

    if not Joker then return end

    -- Capacity-first: start at 5 (you can modify later via gameplay).
    self.joker_capacity = self.joker_capacity or 5

    self.jokers_on_bottom = false
    self.jokers_sliding = false
    self.jokers_slide_time_left = 0

    -- Slot geometry is shared by both top- and bottom-screen placements.
    self.joker_slot_w, self.joker_slot_h = 71, 95
    self.joker_slot_gap = 8
    self.joker_slot_y_top = 124 -- under top HUD panel
    self.joker_slot_y_bottom = 20 -- above the hand fan on bottom screen

    -- Bottom screen is narrower than top in this project (hand uses 320 wide).
    local BOTTOM_SCREEN_W = 320
    local TOP_SCREEN_W = 400

    local slot_count = self.joker_capacity
    local base_total_w = slot_count * self.joker_slot_w + (slot_count - 1) * self.joker_slot_gap

    -- Top layout uses full scale (1.0) and centers within the top-screen width.
    local top_start_x = math.floor((TOP_SCREEN_W - base_total_w) * 0.5 + 0.5)
    if top_start_x < 0 then top_start_x = 0 end
    self.joker_slot_start_x = top_start_x

    -- Bottom layout centers and scales down to fit within the bottom-screen width.
    local bottom_scale = math.min(1, (BOTTOM_SCREEN_W or 320) / math.max(1, base_total_w))
    self.joker_slot_scale_bottom = bottom_scale

    local bottom_total_w = base_total_w * bottom_scale
    local bottom_start_x = math.floor((BOTTOM_SCREEN_W - bottom_total_w) * 0.5 + 0.5)
    if bottom_start_x < 0 then bottom_start_x = 0 end
    self.joker_slot_start_x_bottom = bottom_start_x

    -- Demo-owned jokers (randomized for testing).
    -- Replace this with your shop/buy system later.
    local pool = {}
    if JOKER_DEFS and type(JOKER_DEFS) == "table" then
        for def_id, _ in pairs(JOKER_DEFS) do
            pool[#pool + 1] = def_id
        end
    end

    -- -- Fisher–Yates shuffle
    -- for i = #pool, 2, -1 do
    --     local j = math.random(i)
    --     pool[i], pool[j] = pool[j], pool[i]
    -- end

    -- local want = math.min(self.joker_capacity or 0, #pool)
    -- for i = 1, want do
    --     self:add_joker_by_def(pool[i])
    -- end
    self:add_joker_by_def("j_mime")
    self:add_joker_by_def("j_banner")
    self:add_joker_by_def("j_mystic_summit")
    self:add_joker_by_def("j_clever")
    self:add_joker_by_def("j_gluttenous_joker")
end

---Add an owned Joker by definition id.
---Owned Jokers are packed left-to-right and never exceed `self.joker_capacity`.
---@param def_id string
---@return boolean
function Game:add_joker_by_def(def_id)
    if type(def_id) ~= "string" or def_id == "" then return false end
    if not JOKER_DEFS or type(JOKER_DEFS) ~= "table" then return false end
    local def = JOKER_DEFS[def_id]
    if type(def) ~= "table" then return false end

    if not self.joker_capacity then self.joker_capacity = 5 end
    if not self.jokers then self.jokers = {} end
    if #self.jokers >= self.joker_capacity then return false end

    -- Create at an arbitrary location; `_apply_joker_layout()` will position it.
    local j = Joker(0, 0, self.joker_slot_w, self.joker_slot_h, def, { face_up = true })
    table.insert(self.jokers, j)
    self:add(j)

    self:_apply_joker_layout()
    self:sync_jokers_interactivity()

    -- Snap immediately if we're not in a DPAD slide transition.
    if self.jokers_sliding ~= true then
        for _, jj in ipairs(self.jokers) do
            if jj and jj.VT and jj.T then
                jj.VT.x = jj.T.x
                jj.VT.y = jj.T.y
                jj.VT.scale = jj.T.scale
            end
        end
    end

    return true
end

function Game:_apply_joker_layout()
    if not self.jokers then return end

    if self.jokers_on_bottom == true then
        local s = self.joker_slot_scale_bottom or 1
        local start_x = self.joker_slot_start_x_bottom or 0
        local y = self.joker_slot_y_bottom

        -- Compensation because Joker scales around its center, which shifts
        -- the visible top-left when s != 1.
        local slot_w = self.joker_slot_w or 71
        local slot_h = self.joker_slot_h or 95
        local delta_x = (slot_w * s * (1 - s)) / 2
        local delta_y = (slot_h * s * (1 - s)) / 2

        -- We want the effective visible left/top edges to match:
        --   desired_left = start_x + (i-1)*step
        -- So set T.x/T.y to the draw coordinates that counteract that shift.

        for i, j in ipairs(self.jokers) do
            if j and j.T then
                local step = (slot_w + (self.joker_slot_gap or 0)) * s
                local desired_left = start_x + (i - 1) * step
                j.T.x = desired_left - delta_x
                j.T.y = y - delta_y
                j.T.scale = s
            end
        end
    else
        local s = 1
        local start_x = self.joker_slot_start_x or 0
        local y = self.joker_slot_y_top

        for i, j in ipairs(self.jokers) do
            if j and j.T then
                local step = (self.joker_slot_w + self.joker_slot_gap) * s
                j.T.x = start_x + (i - 1) * step
                j.T.y = y
                j.T.scale = s
            end
        end
    end
end

function Game:sync_jokers_interactivity()
    local on_bottom = self.jokers_on_bottom == true
    if not self.jokers then return end
    for _, j in ipairs(self.jokers) do
        if j and j.states then
            j.states.click.can = on_bottom
            j.states.drag.can = on_bottom
            -- Bottom screen draw path uses `j:draw()`, which checks `states.visible`.
            -- Top screen draw is handled by `TopUI.draw()` which temporarily overrides visibility.
            j.states.visible = on_bottom
        end
    end
end

--- Jokers in slot order (left-to-right) that match `event_name` and have `apply_effect`.
---@param event_name string
---@param ctx table
---@return table[]
function Game:collect_matching_jokers(event_name, ctx)
    local out = {}
    if not self.jokers or type(self.jokers) ~= "table" then return out end
    if type(event_name) ~= "string" or event_name == "" then return out end
    if type(ctx) ~= "table" then ctx = {} end

    for _, j in ipairs(self.jokers) do
        if j and j.matches_trigger and j:matches_trigger(event_name, ctx) and j.apply_effect then
            table.insert(out, j)
        end
    end
    -- Resolve left-to-right on screen (array order can diverge after drag-reorder).
    table.sort(out, function(a, b)
        local ax = (a.T and a.T.x) or (a.VT and a.VT.x) or 0
        local bx = (b.T and b.T.x) or (b.VT and b.VT.x) or 0
        return ax < bx
    end)
    return out
end

---Emit a joker event to all jokers and apply their effects to the context.
---`ctx` is a mutable table that joker effects can update (e.g. ctx.chips/ctx.mult).
---@param event_name string
---@param ctx table|nil
function Game:emit_joker_event(event_name, ctx)
    if not self.jokers or type(self.jokers) ~= "table" then return end
    if type(event_name) ~= "string" or event_name == "" then return end
    if type(ctx) ~= "table" then ctx = {} end

    for _, j in ipairs(self.jokers) do
        if j and j.matches_trigger and j:matches_trigger(event_name, ctx) then
            if j.apply_effect then
                j:apply_effect(ctx)
            end
        end
    end
end

function Game:_sync_joker_ctx(ctx)
    if type(ctx) ~= "table" then return end
    self.selectedHandChips = tonumber(ctx.chips) or self.selectedHandChips
    self.selectedHandMult = tonumber(ctx.mult) or self.selectedHandMult
end

--- True while a staggered joker batch (from `begin_joker_emit`) is still resolving.
function Game:joker_emit_busy()
    return self._joker_emit_queue ~= nil
end

--- Apply one joker from the stagger queue and sync chips/mult to `G`.
function Game:_apply_one_joker_emit()
    local q = self._joker_emit_queue
    if not q or type(q.list) ~= "table" then
        self._joker_emit_queue = nil
        self._joker_emit_timer = 0
        return
    end
    local j = q.list[self._joker_emit_next]
    if j and j.apply_effect then
        j:apply_effect(q.ctx)
    end
    self:_sync_joker_ctx(q.ctx)
    self._joker_emit_next = self._joker_emit_next + 1
    if self._joker_emit_next > #q.list then
        self._joker_emit_queue = nil
        self._joker_emit_timer = 0
    end
end

--- Resolve matching jokers left-to-right with a delay between each trigger (first applies immediately).
--- Returns true if any joker was queued (caller should wait until `joker_emit_busy()` is false).
---@param event_name string
---@param ctx table|nil
---@return boolean
function Game:begin_joker_emit(event_name, ctx)
    local list = self:collect_matching_jokers(event_name, ctx)
    if #list == 0 then return false end
    if type(ctx) ~= "table" then ctx = {} end
    self._joker_emit_queue = { list = list, ctx = ctx }
    self._joker_emit_next = 1
    self._joker_emit_timer = 0
    self:_apply_one_joker_emit()
    return true
end

function Game:_update_joker_emit_queue(dt)
    if not self._joker_emit_queue then return end
    self._joker_emit_timer = self._joker_emit_timer + dt
    local interval = tonumber(self.JOKER_EMIT_INTERVAL) or 0.18
    if self._joker_emit_timer >= interval then
        self._joker_emit_timer = 0
        self:_apply_one_joker_emit()
    end
end

--- End Round — call once when the current round finishes (e.g. blind beaten).
--- Shuffles the discard pile into the draw pile so the next round draws from a full recycled deck.
function Game:end_round()
    local deck = self.deck
    if deck and deck.end_round then
        deck:end_round()
    end
    if self.hand and self.hand.fill_from_deck then
        self.hand:fill_from_deck()
    end
end

function Game:set_jokers_location(on_bottom)
    if self.jokers_on_bottom == (on_bottom == true) then return end
    local from_bottom = self.jokers_on_bottom == true
    local to_bottom = on_bottom == true

    self.jokers_on_bottom = to_bottom
    self:sync_jokers_interactivity()

    -- Update target transforms first.
    self:_apply_joker_layout()

    -- Guide rectangles should move with jokers during this transition.
    -- They'll lock back to stationary slot geometry once the jokers snap.
    self.jokers_sliding = true
    self.jokers_slide_time_left = 0.6

    -- Then force VT to the previous layout so the slide always starts
    -- from a consistent top/bottom position (independent of prior VT drift).
    if self.jokers then
        local start_y
        if to_bottom then
            -- Start above the bottom screen so it feels like sliding down from the top.
            local s = self.joker_slot_scale_bottom or 1
            local slot_h = self.joker_slot_h or 95
            local h = slot_h * s
            local delta_y = (slot_h * s * (1 - s)) / 2
            start_y = -(h + 60) - delta_y -- guaranteed < 0 (effective visible)
        else
            -- Start below the bottom slots so it feels like sliding up.
            local s = self.joker_slot_scale_bottom or 1
            local slot_h = self.joker_slot_h or 95
            local h = slot_h * s
            local delta_y = (slot_h * s * (1 - s)) / 2
            start_y = (self.joker_slot_y_bottom or 20) + h + 60 - delta_y
        end

        for i, j in ipairs(self.jokers) do
            if j and j.VT then
                -- Keep VT centered and sized like the final slot;
                -- this prevents extra horizontal/scale drift during the slide.
                if j.T then
                    j.VT.x = j.T.x
                    j.VT.scale = j.T.scale
                end
                j.VT.y = start_y
            end
        end
    end
end

function Game:_joker_nearest_slot_idx(release_x)
    local owned_count = self.jokers and #self.jokers or 0
    if owned_count <= 0 then return 1 end

    if self.jokers_on_bottom == true then
        local s = self.joker_slot_scale_bottom or 1
        local start_x = self.joker_slot_start_x_bottom or 0
        local step = (self.joker_slot_w + self.joker_slot_gap) * s
        local slot_w_scaled = self.joker_slot_w * s
        local best_i, best_d = 1, 1e9
        for i = 1, owned_count do
            local cx = start_x + (i - 1) * step + slot_w_scaled / 2
            local d = math.abs(release_x - cx)
            if d < best_d then
                best_d = d
                best_i = i
            end
        end
        return best_i
    end

    local best_i, best_d = 1, 1e9
    for i = 1, owned_count do
        local cx = self.joker_slot_start_x + (i - 1) * (self.joker_slot_w + self.joker_slot_gap) + self.joker_slot_w / 2
        local d = math.abs(release_x - cx)
        if d < best_d then
            best_d = d
            best_i = i
        end
    end
    return best_i
end

function Game:try_reorder_joker_after_drag(joker_node, release_x)
    if not joker_node or not self.jokers or not self.jokers_on_bottom then return false end

    local from_idx
    for i, j in ipairs(self.jokers) do
        if j == joker_node then
            from_idx = i
            break
        end
    end
    if not from_idx then return false end

    local to_idx = self:_joker_nearest_slot_idx(release_x)
    if to_idx == from_idx then return false end

    local reordered = false
    local node = table.remove(self.jokers, from_idx)
    table.insert(self.jokers, to_idx, node)
    reordered = true

    -- Update target positions to reflect new slot order.
    self:_apply_joker_layout()

    -- Snap immediately to avoid visible overshoot beyond the bottom screen.
    -- We only do this when the slide transition is not active.
    if self.jokers_sliding ~= true then
        for _, j in ipairs(self.jokers) do
            if j and j.VT and j.T then
                j.VT.x = j.T.x
                j.VT.y = j.T.y
                j.VT.scale = j.T.scale
            end
        end
    end
    return reordered
end

function Game:move_to_front(node)
    for i, n in ipairs(self.nodes) do
        if n == node then
            table.remove(self.nodes, i)
            table.insert(self.nodes, node)
            return
        end
    end
end

local TAP_THRESHOLD = 15

function Game:touchpressed(id, x, y)
    if self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then return end
    self.touch_start_x = x
    self.touch_start_y = y
    local node = self:get_node_at(x, y)
    if node and node.touchpressed then
        node:touchpressed(id, x, y)
        self.dragging = node
        self:move_to_front(node)
    end
end

function Game:touchmoved(id, x, y, dx, dy)
    if self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then return end
    if self.dragging and self.dragging.touchmoved then
        self.dragging:touchmoved(id, x, y, dx, dy)
    end
end

function Game:touchreleased(id, x, y)
    if self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then
        self.dragging = nil
        return
    end
    local released = self.dragging
    if released and released.touchreleased then
        released:touchreleased(id, x, y)
    end
    local dx = x - self.touch_start_x
    local dy = y - self.touch_start_y
    local dist = math.sqrt(dx * dx + dy * dy)
    local reordered = false

    -- Joker reordering (bottom screen only).
    if released and self.jokers and self.jokers_on_bottom then
        local rmin = self.joker_reorder_drag_threshold and self.joker_reorder_drag_threshold() or 22
        if dist >= rmin then
            reordered = self:try_reorder_joker_after_drag(released, x) or false
        end
    end

    if released and self.hand and self.hand.try_reorder_card_after_drag then
        local rmin = self.hand.reorder_drag_threshold and self.hand:reorder_drag_threshold() or 22
        if dist >= rmin then
            for _, node in ipairs(self.hand.card_nodes) do
                if node == released then
                    reordered = self.hand:try_reorder_card_after_drag(node, x)
                    break
                end
            end
        end
    end
    if released and self.hand and not reordered and dist < TAP_THRESHOLD then
        for _, node in ipairs(self.hand.card_nodes) do
            if node == released then
                self.hand:toggle_selection(node)
                break
            end
        end
    end
    if not released and dist < TAP_THRESHOLD then
        self.active_tooltip_card = nil
    end
    self.dragging = nil
    if released and self.hand then
        for _, node in ipairs(self.hand.card_nodes) do
            if node == released then
                self:restore_hand_draw_order()
                break
            end
        end
    end
end

function Game:restore_hand_draw_order()
    if not self.hand or #self.hand.card_nodes == 0 then return end
    local hand_set = {}
    for _, node in ipairs(self.hand.card_nodes) do
        hand_set[node] = true
    end
    local ordered = {}
    for _, node in ipairs(self.nodes) do
        if not hand_set[node] then
            table.insert(ordered, node)
        end
    end
    for _, node in ipairs(self.hand.card_nodes) do
        table.insert(ordered, node)
    end
    self.nodes = ordered
end

--- Puts selected hand cards at the end of the draw list so they render on top.
function Game:move_selected_hand_cards_to_front()
    if not self.hand or #self.hand.selected == 0 then return end
    local sel = {}
    for _, n in ipairs(self.hand.selected) do sel[n] = true end
    local ordered = {}
    for _, node in ipairs(self.nodes) do
        if not sel[node] then
            table.insert(ordered, node)
        end
    end
    for _, node in ipairs(self.hand.selected) do
        table.insert(ordered, node)
    end
    self.nodes = ordered
end

function Game:ensure_asset_atlas_loaded(name)
    if not name or not self.ASSET_ATLAS then return nil end
    local atlas = self.ASSET_ATLAS[name]
    if not atlas then return nil end
    if atlas.image then return atlas end
    if not atlas.path then return atlas end

    local ok, img = pcall(love.graphics.newImage, atlas.path, { dpiscale = atlas.dpiscale or self.SETTINGS.GRAPHICS.texture_scaling })
    if not ok then
        ok, img = pcall(love.graphics.newImage, atlas.path, {})
    end
    atlas.image = ok and img or nil
    return atlas
end

function Game:set_render_settings()
    self.SETTINGS.GRAPHICS.texture_scaling = self.SETTINGS.GRAPHICS.texture_scaling or 1

    love.graphics.setDefaultFilter(
        self.SETTINGS.GRAPHICS.texture_scaling == 1 and 'nearest' or 'linear',
        self.SETTINGS.GRAPHICS.texture_scaling == 1 and 'nearest' or 'linear', 1
    )
    love.graphics.setLineStyle("rough")

        --spritesheets
        self.animation_atli = {
            {name = "blind_chips", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/BlindChips.png",px=36,py=36, frames = 21},
            {name = "shop_sign", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/ShopSignAnimation.png",px=113,py=60, frames = 4}
        }
        self.asset_atli = {
            {name = "cards_1", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/8BitDeck.png",px=72,py=95},
            {name = "cards_2", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/8BitDeck_opt2.png",px=72,py=95},
            {name = "centers", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/Enhancers.png",px=72,py=95},
            {name = "Joker1", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/Jokers1.png",px=71,py=95},
            {name = "Joker2", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/Jokers2.png",px=71,py=95},
            {name = "Tarot", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/Tarots.png",px=72,py=95},
            {name = "Voucher", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/Vouchers.png",px=72,py=95},
            {name = "Booster", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/boosters.png",px=72,py=95},
            {name = "ui_1", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/ui_assets.png",px=18,py=18},
            {name = "ui_2", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/ui_assets_opt2.png",px=18,py=18},
            {name = "balatro", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/balatro.png",px=336,py=216},        
            {name = 'gamepad_ui', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/gamepad_ui.png",px=32,py=32},
            {name = 'icons', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/icons.png",px=66,py=66},
            {name = 'tags', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/tags.png",px=34,py=34},
            {name = 'stickers', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/stickers.png",px=72,py=95},
            {name = 'chips', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/chips.png",px=30,py=30},
    
            --[[ {name = 'collab_AU_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_AU_1.png",px=71,py=95},
            {name = 'collab_AU_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_AU_2.png",px=71,py=95},
            {name = 'collab_TW_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_TW_1.png",px=71,py=95},
            {name = 'collab_TW_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_TW_2.png",px=71,py=95},
            {name = 'collab_VS_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_VS_1.png",px=71,py=95},
            {name = 'collab_VS_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_VS_2.png",px=71,py=95},
            {name = 'collab_DTD_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DTD_1.png",px=71,py=95},
            {name = 'collab_DTD_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DTD_2.png",px=71,py=95},
    
            {name = 'collab_CYP_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CYP_1.png",px=71,py=95},
            {name = 'collab_CYP_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CYP_2.png",px=71,py=95},
            {name = 'collab_STS_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_STS_1.png",px=71,py=95},
            {name = 'collab_STS_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_STS_2.png",px=71,py=95},
            {name = 'collab_TBoI_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_TBoI_1.png",px=71,py=95},
            {name = 'collab_TBoI_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_TBoI_2.png",px=71,py=95},
            {name = 'collab_SV_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_SV_1.png",px=71,py=95},
            {name = 'collab_SV_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_SV_2.png",px=71,py=95},
            
            {name = 'collab_SK_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_SK_1.png",px=71,py=95},
            {name = 'collab_SK_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_SK_2.png",px=71,py=95},
            {name = 'collab_DS_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DS_1.png",px=71,py=95},
            {name = 'collab_DS_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DS_2.png",px=71,py=95},
            {name = 'collab_CL_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CL_1.png",px=71,py=95},
            {name = 'collab_CL_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CL_2.png",px=71,py=95},
            {name = 'collab_D2_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_D2_1.png",px=71,py=95},
            {name = 'collab_D2_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_D2_2.png",px=71,py=95},
            {name = 'collab_PC_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_PC_1.png",px=71,py=95},
            {name = 'collab_PC_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_PC_2.png",px=71,py=95},
            {name = 'collab_WF_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_WF_1.png",px=71,py=95},
            {name = 'collab_WF_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_WF_2.png",px=71,py=95},
            {name = 'collab_EG_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_EG_1.png",px=71,py=95},
            {name = 'collab_EG_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_EG_2.png",px=71,py=95},
            {name = 'collab_XR_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_XR_1.png",px=71,py=95},
            {name = 'collab_XR_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_XR_2.png",px=71,py=95},
    
            {name = 'collab_CR_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CR_1.png",px=71,py=95},
            {name = 'collab_CR_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CR_2.png",px=71,py=95},
            {name = 'collab_BUG_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_BUG_1.png",px=71,py=95},
            {name = 'collab_BUG_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_BUG_2.png",px=71,py=95},
            {name = 'collab_FO_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_FO_1.png",px=71,py=95},
            {name = 'collab_FO_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_FO_2.png",px=71,py=95},
            {name = 'collab_DBD_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DBD_1.png",px=71,py=95},
            {name = 'collab_DBD_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DBD_2.png",px=71,py=95},
            {name = 'collab_C7_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_C7_1.png",px=71,py=95},
            {name = 'collab_C7_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_C7_2.png",px=71,py=95},
            {name = 'collab_R_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_R_1.png",px=71,py=95},
            {name = 'collab_R_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_R_2.png",px=71,py=95},
            {name = 'collab_AC_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_AC_1.png",px=71,py=95},
            {name = 'collab_AC_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_AC_2.png",px=71,py=95},
            {name = 'collab_STP_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_STP_1.png",px=71,py=95},
            {name = 'collab_STP_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_STP_2.png",px=71,py=95}, ]]
        }
        self.asset_images = {
            {name = "playstack_logo", path = "resources/textures/1x/playstack-logo.png", px=1416,py=1416},
            {name = "localthunk_logo", path = "resources/textures/1x/localthunk-logo.png", px=1390,py=560}
        }
    
        -- Helper: load image with no mipmaps for pixel-art memory savings.
        local function load_image(path, options)
            local ok, img = pcall(love.graphics.newImage, path, options or {})
            if not ok and options and options.dpiscale then
                ok, img = pcall(love.graphics.newImage, path, {})
            end
            return ok and img or nil
        end

        -- Animation atlases are small; load eagerly (no mipmaps).
        for i=1, #self.animation_atli do
            self.ANIMATION_ATLAS[self.animation_atli[i].name] = {}
            self.ANIMATION_ATLAS[self.animation_atli[i].name].name = self.animation_atli[i].name
            self.ANIMATION_ATLAS[self.animation_atli[i].name].path = self.animation_atli[i].path
            self.ANIMATION_ATLAS[self.animation_atli[i].name].image = load_image(self.animation_atli[i].path, {dpiscale = self.SETTINGS.GRAPHICS.texture_scaling})
            self.ANIMATION_ATLAS[self.animation_atli[i].name].px = self.animation_atli[i].px
            self.ANIMATION_ATLAS[self.animation_atli[i].name].py = self.animation_atli[i].py
            self.ANIMATION_ATLAS[self.animation_atli[i].name].frames = self.animation_atli[i].frames
        end

        -- Register all asset atlases, lazy-load textures on first use.
        for i=1, #self.asset_atli do
            self.ASSET_ATLAS[self.asset_atli[i].name] = {}
            self.ASSET_ATLAS[self.asset_atli[i].name].name = self.asset_atli[i].name
            self.ASSET_ATLAS[self.asset_atli[i].name].path = self.asset_atli[i].path
            self.ASSET_ATLAS[self.asset_atli[i].name].dpiscale = self.SETTINGS.GRAPHICS.texture_scaling
            self.ASSET_ATLAS[self.asset_atli[i].name].image = nil
            self.ASSET_ATLAS[self.asset_atli[i].name].type = self.asset_atli[i].type
            self.ASSET_ATLAS[self.asset_atli[i].name].px = self.asset_atli[i].px
            self.ASSET_ATLAS[self.asset_atli[i].name].py = self.asset_atli[i].py
        end
        for i=1, #self.asset_images do
            self.ASSET_ATLAS[self.asset_images[i].name] = {}
            self.ASSET_ATLAS[self.asset_images[i].name].name = self.asset_images[i].name
            self.ASSET_ATLAS[self.asset_images[i].name].path = self.asset_images[i].path
            self.ASSET_ATLAS[self.asset_images[i].name].dpiscale = 1
            self.ASSET_ATLAS[self.asset_images[i].name].image = nil
            self.ASSET_ATLAS[self.asset_images[i].name].type = self.asset_images[i].type
            self.ASSET_ATLAS[self.asset_images[i].name].px = self.asset_images[i].px
            self.ASSET_ATLAS[self.asset_images[i].name].py = self.asset_images[i].py
        end

        -- Preload only the atlases needed for the current core gameplay path.
        local preload_atlases = {
            "cards_1", "cards_2", "centers", "ui_1", "ui_2", "chips", "balatro"
        }
        for i = 1, #preload_atlases do
            self:ensure_asset_atlas_loaded(preload_atlases[i])
        end

        -- Aliases (point at same table; lazy loading still applies).
        self.ASSET_ATLAS.Planet = self.ASSET_ATLAS.Tarot
        self.ASSET_ATLAS.Spectral = self.ASSET_ATLAS.Tarot

        for _, v in pairs(G.I.SPRITE) do
            v:reset()
        end
end
