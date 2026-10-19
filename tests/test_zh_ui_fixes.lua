local T=require("tests.testlib")
local bootstrap=require("tests.bootstrap")
bootstrap.load()
local I18N=require("localization")
local Fonts=require("fonts")
local ShopUI=require("shop_ui")
local suite=T.suite()
suite.test("Chinese roles sharing a baked height share the same face",function()
    local P=Fonts.build("native","zh_CN")
    T.assert_eq(P.MICRO,P.SMALL)
    T.assert_eq(P.FACES,5)
end)
suite.test("blind skip and shop exit draw the live binding",function()
    local g=bootstrap.new_game(731);G=g;I18N.set_language("zh_CN")
    T.assert_true(g:set_control_binding("cancel",1,"x"))
    T.assert_eq(g:get_button_for_role("cancel"),"x")
    g.current_blind_index=1;g.selected_blind_index=1;g:roll_skips()
    g.gamepad_focus_visible=function() return true end
    local seen={};g.draw_button_pip=function(_,b) seen[#seen+1]=b;return true end
    g.STATE=g.STATES.BLIND_SELECT;g:draw_bottom_blind_select()
    local found=false;for _,b in ipairs(seen) do if b=="x" then found=true end end
    T.assert_true(found,"skip uses the remapped cancel button")
    g.STATE=g.STATES.SHOP;g:init_shop_gamepad_nav();g:draw_bottom_shop()
    T.assert_eq(g._shop_ui_cache.continue.button,"x")
    T.assert_eq(g._shop_ui_cache.continue.parts[2].text,"长按")
    I18N.set_language("en")
end)
suite.test("Ectoplasm reports the next use's real hand-size penalty",function()
    local g=bootstrap.new_game(732);G=g;I18N.set_language("zh_CN")
    local card={def=CONSUMABLE_DEFS.spectral_ectoplasm}
    g.ectoplasm_used=0;T.assert_true(Consumable.get_tooltip_body_lines(card)[1]:find("-1",1,true)~=nil)
    g.ectoplasm_used=2;T.assert_true(Consumable.get_tooltip_body_lines(card)[1]:find("-3",1,true)~=nil)
    I18N.set_language("en")
end)
suite.test("HUD ratios use one line and scale inside their panel",function()
    local g=bootstrap.new_game(733);G=g
    local old_print,old_printf,old_scale=love.graphics.print,love.graphics.printf,love.graphics.scale
    local printed,wrapped,scale=0,0,nil
    love.graphics.print=function(t) if t=="1/8" then printed=printed+1 end end
    love.graphics.printf=function() wrapped=wrapped+1 end
    love.graphics.scale=function(x) scale=x end
    love.graphics.setFont(g.FONTS.PIXEL.MEDIUM)
    local font=love.graphics.getFont()
    TopUI.center_text_juiced("1/8",0,0,20,14,1.4)
    love.graphics.print,love.graphics.printf,love.graphics.scale=old_print,old_printf,old_scale
    T.assert_eq(printed,1);T.assert_eq(wrapped,0)
    T.assert_true(scale*font:getWidth("1/8")<=20)
    T.assert_true(scale*font:getHeight()<=14)
end)
suite.test("Chinese toast keeps upstream geometry with the maintained font and text",function()
    local g=bootstrap.new_game(734);G=g
    g.SETTINGS.REDUCED_MOTION=true
    g.FONTS.PIXEL=Fonts.build("native","zh_CN")
    g._milestone_active={title="新发现",detail="小盲注",age=0.5}
    for _,native in ipairs({0,5}) do
        g.FONTS.PIXEL.NATIVE_FACES=native
        local rects,labels={},{}
        local old_rectangle,old_printf=love.graphics.rectangle,love.graphics.printf
        love.graphics.rectangle=function(_,x,y,w,h) rects[#rects+1]={x=x,y=y,w=w,h=h} end
        love.graphics.printf=function(text) labels[#labels+1]={text=text,font=love.graphics.getFont()} end
        require("milestone_queue").draw(g)
        love.graphics.rectangle,love.graphics.printf=old_rectangle,old_printf
        T.assert_eq(rects[2].x,88);T.assert_eq(rects[2].y,5);T.assert_eq(rects[2].w,224)
        T.assert_eq(rects[2].h,native==0 and 48 or 46)
        T.assert_eq(labels[1].text,"新发现");T.assert_eq(labels[2].text,"小盲注")
        T.assert_eq(labels[1].font,g.FONTS.PIXEL.SMALL)
        T.assert_eq(labels[2].font,g.FONTS.PIXEL.MICRO)
    end
end)
suite.test("leftover hand cards cannot cover shop controls",function()
    local g=bootstrap.new_game(735);G=g;g.STATE=g.STATES.SHOP
    local drawn=0;g.hand={};g.hand.card_nodes={{selected=true,draw=function() drawn=drawn+1 end}}
    g.jokers_on_bottom=true
    g:draw()
    T.assert_eq(drawn,0)
end)
suite.test("Chinese boss text keeps commas and full stops off line starts",function()
    local Utf8=require("utf8_text")
    local font={getWidth=function(_,s) return Utf8.len(s)*13 end}
    local text="每次出牌后，随机弃掉 2 张手牌。"
    local lines=Utf8.wrap_lines(font,text,80)
    for _,line in ipairs(lines) do
        T.assert_true(font:getWidth(line)<=80)
        T.assert_false(line:sub(1,3)=="，" or line:sub(1,3)=="。")
    end
    T.assert_eq(table.concat(lines):gsub(" ",""),text:gsub(" ",""))
end)
suite.test("blind reward preview matches committed reward for stakes challenges and bosses",function()
    local cases={{1,3},{2,4},{3,5},{1,0,red=true},{2,4,red=true},
        {1,0,blocked="Small Blind"},{2,0,blocked="Big Blind"},
        {3,0,blocked="Boss Blind"},{3,9,boss_dollars=9}}
    for _,case in ipairs(cases) do
        local g=bootstrap.new_game(739);G=g
        if case.red then g:apply_stake_config("stake_red") end
        if case.blocked then g.challenge_modifiers={no_blind_reward={[case.blocked]=true}} end
        if case.boss_dollars then
            local proto={};for k,v in pairs(g:get_boss_blind_prototype()) do proto[k]=v end
            proto.dollars=case.boss_dollars
            g.get_boss_blind_prototype=function() return proto end
        end
        g.current_blind_index=case[1];g.selected_blind_index=case[1]
        local preview=g:get_blind_reward(case[1]);T.assert_eq(preview,case[2])
        T.assert_true(g:_commit_selected_blind())
        T.assert_eq(g.current_blind_reward,preview)
    end
end)
suite.test("reward pips count dollars without an extra currency prefix",function()
    local g=bootstrap.new_game(740);G=g
    local ui=g.topUI or TopUI(g)
    T.assert_eq(ui:cached_reward_pips(3),"$$$+")
    T.assert_eq(ui:cached_reward_pips(4),"$$$$+")
    T.assert_eq(ui:cached_reward_pips(5),"$$$$$+")
    T.assert_eq(ui:cached_reward_pips(0),"$0")
end)
return suite
