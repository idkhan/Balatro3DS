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
    local parts=g._shop_ui_cache.continue.parts
    T.assert_eq(parts[#parts].text,"长按")
    I18N.set_language("en")
end)
suite.test("shop button captions stay inside their buttons in Chinese",function()
    local g=bootstrap.new_game(734);G=g;I18N.set_language("zh_CN")
    -- The hardware faces: Chinese letters fill their cell, so the exit's three lines overflowed.
    g.FONTS.PIXEL=Fonts.build("native","zh_CN");g._shop_ui_cache=nil
    local buttons,lines,inside={},{},false
    local real_button,real_print,real_draw=draw_button_with_shadow,love.graphics.print,ShopUI.draw_shop_button
    ShopUI.draw_shop_button=function(...) inside=true;real_draw(...);inside=false end
    draw_button_with_shadow=function(...)
        local ix,iy,iw,ih=real_button(...);buttons[#buttons+1]={y=iy,h=ih};return ix,iy,iw,ih
    end
    love.graphics.print=function(text,x,y,...)
        local top,ink=Fonts.ink(g,love.graphics.getFont())
        if inside then lines[#lines+1]={text=tostring(text),top=y+top,bottom=y+top+ink,button=#buttons} end
        return real_print(text,x,y,...)
    end
    g.STATE=g.STATES.SHOP;g:init_shop_gamepad_nav()
    local ok,err=pcall(function() g:draw_bottom_shop() end)
    draw_button_with_shadow,love.graphics.print,ShopUI.draw_shop_button=real_button,real_print,real_draw
    I18N.set_language("en")
    if not ok then error(err,0) end
    local checked=0
    for _,line in ipairs(lines) do
        local b=buttons[line.button]
        checked=checked+1
            T.assert_true(line.top>=b.y and line.bottom<=b.y+b.h,
                line.text.." spans rows "..line.top..".."..(line.bottom-1).." in a button of rows "..b.y..".."..(b.y+b.h-1))
    end
    T.assert_eq(checked,5,"three exit lines and two reroll lines")
end)
suite.test("the hand level sits on the hand name's baseline in Chinese",function()
    local g=bootstrap.new_game(735);G=g;g.STATE=g.STATES.SELECTING_HAND;I18N.set_language("zh_CN")
    -- The hardware faces: the Chinese name steps down to fit its row, so it is not the face it was set in.
    g.FONTS.PIXEL=Fonts.build("native","zh_CN")
    for i,h in ipairs(g.handlist) do if h=="Pair" then g.selectedHand=i end end
    local name,baseline=I18N.hand_name("Pair"),{}
    local real_print,real_printf=love.graphics.print,love.graphics.printf
    local function note(text,y)
        local top,ink=Fonts.ink(g,love.graphics.getFont())
        local t=tostring(text)
        if t==name then baseline.name=y+top+ink elseif t:find("^lvl") then baseline.level=y+top+ink end
    end
    love.graphics.print=function(text,x,y,...) note(text,y);return real_print(text,x,y,...) end
    love.graphics.printf=function(text,x,y,...) note(text,y);return real_printf(text,x,y,...) end
    local top=TopUI()
    local ok,err=pcall(top.draw,top,"top")
    love.graphics.print,love.graphics.printf=real_print,real_printf
    I18N.set_language("en")
    if not ok then error(err,0) end
    T.assert_not_nil(baseline.name,"the hand name is drawn")
    T.assert_eq(baseline.level,baseline.name,"the level's letters end on the name's bottom row")
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
    local old_print,old_printf=love.graphics.print,love.graphics.printf
    local printed,wrapped,drawn=0,0,nil
    -- The readout may step down the font ladder and pops through print's own scale argument, so
    -- record the face and scale the text is actually drawn with.
    love.graphics.print=function(t,_,_,_,sx)
        if t=="1/8" then printed=printed+1;drawn={font=love.graphics.getFont(),scale=sx or 1} end
    end
    love.graphics.printf=function() wrapped=wrapped+1 end
    love.graphics.setFont(g.FONTS.PIXEL.MEDIUM)
    TopUI.center_text_juiced("1/8",0,0,20,14,1.4)
    love.graphics.print,love.graphics.printf=old_print,old_printf
    T.assert_eq(printed,1);T.assert_eq(wrapped,0)
    T.assert_true(drawn.scale*drawn.font:getWidth("1/8")<=20)
    -- Inside the panel means the letters; the empty rows of the cell may overhang.
    local _,ink_h=Fonts.ink(g,drawn.font)
    T.assert_true(drawn.scale*ink_h<=14)
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
suite.test("the round score label stays inside its row in Chinese",function()
    local g=bootstrap.new_game(736);G=g;g.STATE=g.STATES.SELECTING_HAND;I18N.set_language("zh_CN")
    -- The hardware faces: two lines of the Chinese label face are taller than the row.
    g.FONTS.PIXEL=Fonts.build("native","zh_CN")
    local first,second=I18N.text("hud.round_score_1"),I18N.text("hud.round_score_2")
    local real_rect,real_print=draw_rounded_rect,love.graphics.print
    local row,spans
    draw_rounded_rect=function(...)
        local ix,iy,iw,ih=real_rect(...);row={y=iy,h=ih};return ix,iy,iw,ih
    end
    love.graphics.print=function(text,x,y,...)
        local t=tostring(text)
        if t==first or t==second or t==first..second then
            local top,ink=Fonts.ink(g,love.graphics.getFont())
            spans=spans or {}
            spans[#spans+1]={text=t,top=y+top,bottom=y+top+ink,row=row}
        end
        return real_print(text,x,y,...)
    end
    local top=TopUI()
    local ok,err=pcall(top.draw,top,"top")
    draw_rounded_rect,love.graphics.print=real_rect,real_print
    I18N.set_language("en")
    if not ok then error(err,0) end
    T.assert_not_nil(spans,"the label is drawn")
    for _,s in ipairs(spans) do
        T.assert_true(s.top>=s.row.y and s.bottom<=s.row.y+s.row.h,
            s.text.." spans rows "..s.top..".."..(s.bottom-1).." in a row of "..s.row.y..".."..(s.row.y+s.row.h-1))
    end
end)

return suite
