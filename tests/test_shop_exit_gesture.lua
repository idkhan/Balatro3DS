local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")
bootstrap.load()
dofile("main.lua")
local suite = T.suite()

local function cancel_hold(start_in_pack, swept, dragging, button)
    local g=bootstrap.new_game(738);G=g;g.STATE=start_in_pack and g.STATES.OPEN_BOOSTER or g.STATES.SHOP
    g.scene_transition_active=function() return false end
    g.get_gamepad_focus_layer=function() return "shop" end
    local left,skipped=0,0
    g.continue_from_shop=function() left=left+1 end
    g.handle_gamepad_booster=function() return false end
    g.skip_booster_pack=function() skipped=skipped+1;g.STATE=g.STATES.SHOP end
    button=button or "b"
    T.assert_true(g:set_control_binding("cancel",1,button))
    T.assert_eq(g:get_button_for_role("cancel"),button)
    local original=love.timer.getTime;local now=100
    love.timer.getTime=function() return now end
    local ok,err=pcall(function()
        love.gamepadpressed(nil,button)
        g._sweep_seeded=swept or false;g.dragging=dragging and {} or nil
        now=100.6;love.gamepadreleased(nil,button)
    end)
    love.timer.getTime=original
    T.assert_true(ok,tostring(err))
    T.assert_nil(g._cancel_press_state)
    return left,skipped
end
suite.test("2.0.5 B that skips a pack cannot also leave the shop",function()
    local left,skipped=cancel_hold(true)
    T.assert_eq(skipped,1);T.assert_eq(left,0)
end)
suite.test("long cancel can still leave from shop focus with live bindings",function()
    T.assert_eq(cancel_hold(false),1)
    T.assert_eq(cancel_hold(false,false,false,"x"),1)
end)
suite.test("shop cancel cannot leave during sweep selection or dragging",function()
    T.assert_eq(cancel_hold(false,true,false),0)
    T.assert_eq(cancel_hold(false,false,true),0)
end)
return suite
