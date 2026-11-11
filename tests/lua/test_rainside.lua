-- The Rainside (RainsideCategory): one category on a side of the screen, a
-- skin of its own (Rainside\Rainside.ini) run by the same script, and what
-- the launcher does for it.
local R = require('rainmeter')
local t = require('t')

local T = {}

local function rainside(settings)
	settings = settings or {}
	settings.Rainside = 1
	local s = R.new({ skin = 'Rainside', settings = settings }):start()
	t.clean(s)
	t.ok(s:upvalue('ready'), 'the Rainside is not ready after loading')
	return s
end

local function logged(s, text)
	for _, line in ipairs(s.log) do
		if line:find(text, 1, true) then return true end
	end
	return false
end

-- The Rainside: its category alone, docked on its side, narrow, no top row
function T.its_category_on_its_side()
	local s = rainside({ RainsideSide = 'Right', RainsideSize = '200' })
	local cats, V = s:upvalue('cats'), s:upvalue('V')
	t.eq(#cats, 1, 'the Rainside has more than its category')
	t.eq(cats[1].file, 'Apps.ini', 'not the category of RainsideCategory')
	t.eq(V.ScreenW, 200, 'not RainsideSize wide')
	t.eq(V.ScreenX, 1920 - 200, 'not on the right edge')
	t.eq(V.ScreenH, 1040, 'not as tall as the screen')
	-- one column of about square tiles (Apps has no NX / NY of its own)
	t.eq(cats[1].nx, 1, 'not one column along a vertical bar')
	t.ok(cats[1].ny >= 4, 'too few rows: ' .. cats[1].ny)
	-- its own generated files, not the launcher's
	t.ok(R.readFile(s.resources .. 'Generated\\RainsideGrid.inc'), 'no RainsideGrid.inc')
	t.ok(R.readFile(s.resources .. 'Generated\\RainsideSizes.inc'), 'no RainsideSizes.inc')
	t.eq(R.readFile(s.resources .. 'Generated\\Grid.inc'), nil, 'the Rainside wrote the launcher\'s Grid.inc')
	-- no top row: menu, search, buttons hidden
	for _, name in ipairs({ 'searchpill', 'metersearch', 'meteroptions', 'meterclose', 'cattext1', 'metertopbar' }) do
		local m = s.meters[name]
		if m then t.ok(m.hidden, '[' .. name .. '] shown on the Rainside') end
	end
	-- the tiles are there
	t.ok(not s.meters['tile1'].hidden, 'no tile shown')
	-- it does none of the launcher's jobs
	t.ok(not logged(s, 'MeasureSetup Run'), 'the Rainside ran the setup')
	t.ok(not logged(s, 'MeasureHelper Run'), 'the Rainside started the helper')
	t.ok(not logged(s, 'MeasureScan Run'), 'the Rainside ran the scan')
	t.ok(not logged(s, 'MeasureThumbs Run'), 'the Rainside made thumbnails')
	t.clean(s)
end

-- At the top: a row of tiles, as tall as RainsideSize
function T.along_the_top()
	local s = rainside({ RainsideSide = 'Top', RainsideSize = '160' })
	local cats, V = s:upvalue('cats'), s:upvalue('V')
	t.eq(V.ScreenH, 160, 'not RainsideSize tall')
	t.eq(V.ScreenY, 0, 'not at the top')
	t.ok(V.Horizontal, 'a bar along the top does not scroll sideways')
	t.eq(cats[1].ny, 1, 'not one row along a horizontal bar')
	t.clean(s)
end

-- Fixed: shown on load, without the keys; its keys give them, and back
function T.fixed_keys()
	local s = rainside({ RainsideMode = 'Fixed' })
	t.ok(s:upvalue('visible'), 'the fixed Rainside is hidden on load')
	local M = s:upvalue('M')
	t.ok(not M.focused, 'the fixed Rainside took the keys on load')
	s:call('Toggle()')
	t.ok(M.focused, 'its key did not give it the keys')
	t.ok(logged(s, 'RainsideFocus(1) Raintile'), 'the launcher was not told it has the keys')
	s:call('Escape()')
	t.ok(s:upvalue('visible'), 'Esc hid the fixed Rainside')
	t.ok(not M.focused, 'Esc did not take the keys back')
	t.ok(logged(s, 'RainsideFocus(0) Raintile'), 'the launcher was not told it gave them back')
	s:call('Toggle()')
	s:call('Toggle()')
	t.ok(s:upvalue('visible') and not M.focused, 'its key again did not take them back')
	t.clean(s)
end

-- Edge: hidden on load, out of its edge for the mouse, back in a moment
-- after the mouse leaves it; its keys open it with the keys
function T.edge()
	local s = rainside({ RainsideMode = 'Edge' })
	t.ok(not s:upvalue('visible'), 'the Rainside on its edge is shown on load')
	local edge = R.readFile(s.resources .. 'Generated\\RainsideDockEdge.txt') or ''
	t.ok(edge:match('^right|'), 'no edge for the helper: ' .. edge)
	s:call("Show('edge')")
	t.ok(s:upvalue('visible'), 'the edge did not open it')
	t.ok(not s:upvalue('M').focused, 'opened by the mouse with the keys')
	s:call('MouseInSkin(1)')
	s:call('MouseInSkin(0)')
	t.ok(not s:upvalue('visible'), 'still out after the mouse left it')
	-- its keys: open with the keys; the mouse leaving does not close it
	s:call('Toggle()')
	t.ok(s:upvalue('visible') and s:upvalue('M').focused, 'its key did not open it with the keys')
	s:call('MouseInSkin(1)')
	s:call('MouseInSkin(0)')
	t.ok(s:upvalue('visible'), 'opened with its keys, the mouse leaving closed it')
	s:call('Escape()')
	t.ok(not s:upvalue('visible'), 'Esc did not take it back in')
	t.clean(s)
end

-- The launcher: the Rainside's category out of its menu, in search; it
-- loads the Rainside
function T.launcher_side()
	local s = R.new({ settings = { Rainside = 1, RainsideCategory = 'Apps' } }):start()
	t.clean(s)
	for _, c in ipairs(s:upvalue('cats')) do
		t.ok(c.file ~= 'Apps.ini', 'the Rainside\'s category is in the launcher\'s menu')
	end
	local M = s:upvalue('M')
	t.ok(M.sideCat and M.sideCat.file == 'Apps.ini', 'the Rainside\'s category not kept for search')
	t.ok(logged(s, '!ActivateConfig Raintile\\Rainside Rainside.ini'), 'the launcher did not load the Rainside')
	-- search finds its tiles
	s:call("SearchOpen()")
	s:call("TypeKey('C')")
	s:call("TypeKey('A')")
	s:call("TypeKey('L')")
	local found = false
	for _, x in ipairs(s:upvalue('searchCat') and s:upvalue('searchCat').tiles or {}) do
		if x.name == 'Calculator' then found = true end
	end
	t.ok(found, 'search does not find the tiles of the Rainside')
	t.clean(s)
	-- without a category: no Rainside, Apps back in the menu
	s = R.new({ settings = { Rainside = 0 } }):start()
	local apps = false
	for _, c in ipairs(s:upvalue('cats')) do if c.file == 'Apps.ini' then apps = true end end
	t.ok(apps, 'Apps not in the menu without a Rainside')
	t.ok(not logged(s, 'Rainside.ini'), 'the Rainside loaded without a category')
	t.clean(s)
end

-- The launcher hidden, the Rainside with the keys: the arrows, Esc and the
-- buttons go to the Rainside; opening the launcher takes them back
function T.keys_to_the_rainside()
	local s = R.new({ settings = { Rainside = 1, RainsideCategory = 'Apps' } }):start()
	s:call('Hide()')
	s:call('RainsideFocus(1)')
	t.ok(logged(s, '!ActivateConfig Raintile\\Navigation'), 'the arrows are off while the Rainside has the keys')
	s:call('Nav(0, 1)')
	t.ok(logged(s, '!CommandMeasure MeasureScript Nav(0,1) Raintile\\Rainside'), 'the arrow did not go to the Rainside')
	s:call("Pad('Confirm')")
	t.ok(logged(s, "Pad('Confirm',nil,nil) Raintile\\Rainside"), 'the button did not go to the Rainside')
	s:call('Escape()')
	t.ok(logged(s, '!CommandMeasure MeasureScript Escape() Raintile\\Rainside'), 'Esc did not go to the Rainside')
	t.ok(not s:upvalue('visible'), 'the launcher opened')
	s:call('Show()')
	t.ok(logged(s, '!CommandMeasure MeasureScript FocusLost() Raintile\\Rainside'), 'opening the launcher did not take the keys back')
	t.ok(not s:upvalue('M').sideFocused, 'the Rainside kept the keys with the launcher open')
	t.clean(s)
end

return T
