-- The widget API (docs/Widgets.md): a custom widget in the data folder, with
-- settings of its own ([Option:Name], settings.inc) and a list (List=, ListY=).
local R = require('rainmeter')
local t = require('t')

local T = {}

local WIDGET = table.concat({
	'[Metadata]',
	'Name=Test widget',
	'[Option:Color]',
	'Label=Colour',
	'Default=255,0,0',
	'[Option:ApiKey]',
	'Kind=secret',
	'Default=not-in-the-skin',
	'[Option:Rows]',
	'Default=3',
	'[Raintile]',
	'List=list_#OPTION:Rows#.txt',
	'ListY=(#WIDGETH#/4)',
	'[Text]',
	'Meter=String',
	'FontColor=#OPTION:Color#',
	'Text=[#OPTION:ApiKey#] #OPTION:Rows# #OPTION:Unknown#',
	'',
}, '\r\n')

-- A skin whose Dashboard has one more tile: the test widget
local function skinWithWidget(settings, skin)
	local s = R.new({ settings = skin })
	local dir = s.data .. 'Widgets\\TestW\\'
	host_mkdir(s.data .. 'Widgets')
	host_mkdir(dir)
	R.writeFile(dir .. 'TestW.ini', WIDGET)
	if settings then R.writeFile(dir .. 'settings.inc', settings) end
	R.writeFile(dir .. 'list_3.txt', 'One|first|||\r\n')
	R.writeFile(dir .. 'list_7.txt', 'One|first|||\r\nTwo|second|||\r\n')
	local cat = s.data .. 'Categories\\Dashboard.ini'
	R.writeFile(cat, R.readFile(cat) .. '\r\n[Test widget]\r\nWidget=custom\r\nParam=TestW\r\n')
	return s:start(), dir
end

local function grid(s)
	return R.readFile(s.resources .. 'Generated\\Grid.inc') or ''
end

local function testWidget(s)
	for _, w in ipairs(s:upvalue('widgets')) do
		if w.widget.param == 'TestW' then return w end
	end
end

function T.options_defaults()
	local s = skinWithWidget(nil)
	t.clean(s)
	local g = grid(s)
	t.ok(g:find('FontColor=255,0,0', 1, true), 'the Default= of an option is not written in place of #OPTION:Color#')
	t.ok(g:find('Text=[] 3 #OPTION:Unknown#', 1, true), 'secret not left out, or an undeclared option changed')
	t.ok(not g:find('not-in-the-skin', 1, true), 'the default of a secret reached the skin')
	t.ok(not g:find('_Option:', 1, true), 'an [Option:] section was written to Grid.inc')
	t.ok(not g:find('Label=Colour', 1, true), 'the keys of an [Option:] section were written to Grid.inc')
end

function T.options_from_settings_file()
	local s = skinWithWidget('Color=1,2,3\r\nApiKey=dpapi:abc\r\nRows=7\r\n')
	t.clean(s)
	local g = grid(s)
	t.ok(g:find('FontColor=1,2,3', 1, true), 'the value of settings.inc is not used')
	t.ok(g:find('Text=[] 7 ', 1, true), 'secret not left out, or Rows not read')
	t.ok(not g:find('dpapi:', 1, true), 'a secret of settings.inc reached the skin')
	local w = testWidget(s)
	t.ok(w, 'the widget tile is missing')
	local api = s:upvalue('M').widgetInfo(w)
	t.ok(api.list and api.list:find('list_7.txt', 1, true), 'List= does not use #OPTION:Rows#: ' .. tostring(api.list))
end

-- A changed settings.inc writes Grid.inc again (it is part of its signature)
function T.options_change_rewrites_grid()
	local s, dir = skinWithWidget('Color=1,2,3\r\n')
	t.ok(grid(s):find('FontColor=1,2,3', 1, true), 'first value not written')
	R.writeFile(dir .. 'settings.inc', 'Color=4,5,6\r\n')
	s:settle()
	t.clean(s)
	t.ok(grid(s):find('FontColor=4,5,6', 1, true), 'Grid.inc kept the old value after settings.inc changed')
end

-- ListY= moves the rows down: the first row starts there, not at the top
function T.list_y()
	local s = skinWithWidget(nil)
	local cats = s:upvalue('cats')
	local w = testWidget(s)
	t.ok(w, 'the widget tile is missing')
	for i, c in ipairs(cats) do
		for _, tile in ipairs(c.tiles) do
			if tile == w then s:call('Show()') s:call('SetCategory(' .. i .. ')') end
		end
	end
	t.clean(s)
	local api = s:upvalue('M').widgetInfo(w)
	local V = s:upvalue('V')
	t.ok(api.listY and math.abs(api.listY - V.TileH / 4) < 1, 'ListY= not read as a formula of #WIDGETH#: ' .. tostring(api.listY))
	local hit = w.widget.partsAt['W' .. w.widget.idx .. 'RowHit1']
	t.ok(hit, 'the first row is not a part of the tile')
	t.eq(hit[2], math.floor(api.listY), 'the first row does not start at ListY=')
end

-- The wheel: the highlight goes onto a row of the list (a part of the tile),
-- in pixels from the tile (in the wheel a fraction of a line is a place on
-- the arc, not a distance in the tile)
function T.list_part_in_the_wheel()
	local s = skinWithWidget(nil, { ScrollMode = 'Wheel', LauncherMode = 'Dock', DockSide = 'Left' })
	local w = testWidget(s)
	for i, c in ipairs(s:upvalue('cats')) do
		for _, tile in ipairs(c.tiles) do
			if tile == w then s:call('Show()') s:call('SetCategory(' .. i .. ')') end
		end
	end
	t.clean(s)
	local name = 'W' .. w.widget.idx .. 'RowHit1'
	s:call('HoverPart(\'' .. name .. '\')')
	t.clean(s)
	local M, V = s:upvalue('M'), s:upvalue('V')
	local slot
	for sl, e in pairs(M.wv) do
		if s:upvalue('tileAt')(sl) == w and (not slot or math.abs(e.d) < math.abs(M.wv[slot].d)) then slot = sl end
	end
	t.ok(slot, 'the widget is not on the wheel')
	local hit = w.widget.partsAt[name]
	t.ok(hit, 'the first row is not a part of the tile')
	local box, hl = s.meters['tilebox' .. slot], s.meters['tilehover']
	local bx, by = tonumber(box:opt('X', '0')) - V.PadX, tonumber(box:opt('Y', '0')) - V.GridY
	local hx, hy = tonumber(hl:opt('X', '0')), tonumber(hl:opt('Y', '0'))
	t.ok(not hl.hidden, 'no highlight on the row')
	t.ok(math.abs(hx - (bx + hit[1])) <= 1 and math.abs(hy - (by + hit[2])) <= 1,
		string.format('highlight at %d,%d, the row at %d,%d', hx, hy, bx + hit[1], by + hit[2]))
end

-- The list widgets of the gallery (widgets/): a title of their own at the top,
-- the rows under it (ListY=, read with Clamp as Rainmeter does)
function T.gallery_titles()
	for _, id in ipairs({ 'Modrinth', 'SteamAchievements' }) do
		local s = R.new({})
		host_mkdir(s.data .. 'Widgets')
		host_copytree(s.repo .. '\\widgets\\' .. id, s.data .. 'Widgets\\' .. id, '')
		local cat = s.data .. 'Categories\\Dashboard.ini'
		R.writeFile(cat, R.readFile(cat) .. '\r\n[Gallery widget]\r\nWidget=custom\r\nParam=' .. id .. '\r\n')
		s:start()
		t.clean(s)
		local w
		for _, x in ipairs(s:upvalue('widgets')) do if x.widget.param == id then w = x end end
		t.ok(w, id .. ': the widget tile is missing')
		local api = s:upvalue('M').widgetInfo(w)
		-- (the title is 9 to 20 pt: the rows start two of its lines and 12 px down)
		t.ok(api.listY and api.listY >= 30 and api.listY <= 52, id .. ': ListY= not under the title: ' .. tostring(api.listY))
		t.ok(grid(s):find('Text=' .. (id == 'Modrinth' and 'Modrinth' or 'Steam achievements'), 1, true), id .. ': no title meter in Grid.inc')
	end
	-- its settings: another text, or no title (the rows from the top)
	for _, case in ipairs({ { 'ShowTitle=1\r\nTitle=My mods\r\n', true }, { 'ShowTitle=0\r\n', false } }) do
		local s = R.new({})
		host_mkdir(s.data .. 'Widgets')
		host_copytree(s.repo .. '\\widgets\\Modrinth', s.data .. 'Widgets\\Modrinth', '')
		R.writeFile(s.data .. 'Widgets\\Modrinth\\settings.inc', case[1])
		local cat = s.data .. 'Categories\\Dashboard.ini'
		R.writeFile(cat, R.readFile(cat) .. '\r\n[Gallery widget]\r\nWidget=custom\r\nParam=Modrinth\r\n')
		s:start()
		t.clean(s)
		local w
		for _, x in ipairs(s:upvalue('widgets')) do if x.widget.param == 'Modrinth' then w = x end end
		local api = s:upvalue('M').widgetInfo(w)
		if case[2] then
			t.ok(grid(s):find('Text=My mods', 1, true), 'the Title setting is not the title')
			t.ok(api.listY >= 30, 'with the title the rows start under it: ' .. tostring(api.listY))
		else
			t.ok(api.listY < 10, 'without the title the rows start at the top: ' .. tostring(api.listY))
			t.ok(grid(s):find('Hidden=(1-0)', 1, true), 'the title is not hidden with ShowTitle=0')
		end
	end
end

-- Audio control (widgets/AudioControl): its sizes written out (no variable of
-- its own left for Rainmeter), its rows the parts of the tile, the tile's
-- mode to its script, its OnShow starting it with a command file of its own
function T.gallery_audio_control()
	local s = R.new({})
	host_mkdir(s.data .. 'Widgets')
	host_copytree(s.repo .. '\\widgets\\AudioControl', s.data .. 'Widgets\\AudioControl', '')
	local cat = s.data .. 'Categories\\Dashboard.ini'
	R.writeFile(cat, R.readFile(cat) .. '\r\n[Audio]\r\nWidget=custom\r\nParam=AudioControl\r\nSize=1x2\r\nWidgetOption=Mixer\r\n')
	s:start()
	t.clean(s)
	local w
	for _, x in ipairs(s:upvalue('widgets')) do if x.widget.param == 'AudioControl' then w = x end end
	t.ok(w, 'the widget tile is missing')
	local g = grid(s)
	local own = g:match('#WIDGET[%w:]*#') or g:match('#OPTION:%w+#')
	for _, v in ipairs({ 'AP', 'AHF', 'ATop', 'AF', 'ANameH', 'AS', 'ABarH', 'ARowH', 'ACmd' }) do
		own = own or (g:find('#' .. v .. '#', 1, true) and v)
	end
	t.ok(not own, 'a variable of the widget left in Grid.inc: ' .. tostring(own))
	local i = w.widget.idx
	local p = 'CW' .. i .. '_'
	t.ok(g:find('[' .. p .. 'Hit8]', 1, true) and g:find('MeasureName=' .. p .. 'Vol1', 1, true), 'rows or their measures missing')
	t.ok(g:find('Hidden=(((' .. '[' .. p .. 'Count]<1)', 1, true), 'the rows are not hidden past [Count]')
	t.ok(g:find('-Mode "Mixer"', 1, true), 'the tile\'s widget setting does not reach the script')
	t.ok(g:find('AudioControl\\cmd_' .. p .. 'Server.ini" -Mode', 1, true), 'the command file is not in the widget\'s folder')
	local parts = s:upvalue('M').widgetParts(w)
	for _, name in ipairs({ 'Hit1', 'Hit2', 'Hit8' }) do
		t.ok(parts[p .. name], name .. ' is not a part of the tile')
	end
	for _, name in ipairs({ 'Minus1', 'Plus1', 'Track1', 'Bar1' }) do
		t.ok(not parts[p .. name], name .. ' is a part (the keys go from row to row only)')
	end
	t.ok(g:find('KeyRightAction=[!WriteKeyValue Cmd Do "up 1"', 1, true), 'right on a row does not turn its volume up')
	-- the highlight of a row takes its bar too
	local hit
	for _, r in ipairs(s:upvalue('M').partRects(w)) do if r[1] == p .. 'Hit1' then hit = r end end
	local track = s.meters[(p .. 'Track1'):lower()]
	local ty = s:number(track:opt('Y', '0'), 0)
	t.ok(hit and hit[3] + hit[5] >= ty + track:GetH(), 'the row\'s part ends above its bar')
	local api = s:upvalue('M').widgetInfo(w)
	t.ok(api.onShow and api.onShow:find('!CommandMeasure ' .. p .. 'Server "Run"', 1, true), 'OnShow does not start the script: ' .. tostring(api.onShow))
	t.ok(api.onShow:find('cmd_' .. p .. 'Server.ini', 1, true) and api.onHide:find('Do quit', 1, true), 'OnShow/OnHide do not use the command file')
	-- the keys on a row (KeyLeftAction= / KeyRightAction=): its volume, the
	-- highlight stays on it; up and down: the next row
	for k, c in ipairs(s:upvalue('cats')) do
		for _, tile in ipairs(c.tiles) do
			if tile == w then s:call('Show()') s:call('SetCategory(' .. k .. ')') end
		end
	end
	t.clean(s)
	local M, skin = s:upvalue('M'), s.skin or s
	s:call("HoverPart('" .. p .. "Hit1')")
	local function last()
		local list = skin.writes or {}
		local x = list[#list]
		return x and (x[2] .. '=' .. x[3]) or ''
	end
	s:call('Nav(1, 0)')
	t.eq(last(), 'Do=up 1', 'right on the first row')
	t.eq(M.kpart and M.kpart.name, p .. 'Hit1', 'right moved the highlight off the row')
	s:call('Nav(-1, 0)')
	t.eq(last(), 'Do=down 1', 'left on the first row')
	s:call('Nav(0, 1)')
	t.eq(M.kpart and M.kpart.name, p .. 'Hit2', 'down from the first row')
	t.clean(s)
end

-- Spotify (widgets/Spotify): its sizes written out, its controls parts of
-- the tile in a group of its own that OnFocus shows, the bar always a part
function T.gallery_spotify()
	local s = R.new({})
	host_mkdir(s.data .. 'Widgets')
	host_copytree(s.repo .. '\\widgets\\Spotify', s.data .. 'Widgets\\Spotify', '')
	local cat = s.data .. 'Categories\\Dashboard.ini'
	R.writeFile(cat, R.readFile(cat) .. '\r\n[Spotify]\r\nWidget=custom\r\nParam=Spotify\r\nSize=2x1\r\n')
	s:start()
	t.clean(s)
	local w
	for _, x in ipairs(s:upvalue('widgets')) do if x.widget.param == 'Spotify' then w = x end end
	t.ok(w, 'the widget tile is missing')
	local g = grid(s)
	local own = g:match('#WIDGET[%w:]*#') or g:match('#OPTION:%w+#')
	for _, v in ipairs({ 'S', 'IF', 'SB', 'SR', 'SL', 'SO', 'SF', 'SH', 'SCmd', 'SShow', 'SHide' }) do
		own = own or (g:find('#' .. v .. '#', 1, true) and v)
	end
	t.ok(not own, 'a variable of the widget left in Grid.inc: ' .. tostring(own))
	local p = 'CW' .. w.widget.idx .. '_'
	local api = s:upvalue('M').widgetInfo(w)
	t.ok(api.onFocus and api.onFocus:find('!ShowMeterGroup "' .. p .. 'CoverCtl"', 1, true), 'OnFocus does not show the controls: ' .. tostring(api.onFocus))
	t.ok(api.onHide:find('Do quit', 1, true) and api.onHide:find('!HideMeterGroup', 1, true), 'OnHide does not stop the script and hide the controls')
	local parts = s:upvalue('M').widgetParts(w)
	for _, name in ipairs({ 'Open', 'Previous', 'Play', 'Next', 'Like', 'Seek' }) do
		t.ok(parts[p .. name], name .. ' is not a part of the tile')
	end
	t.ok(g:find('-Port "8974"', 1, true), 'the Port setting does not reach the script')
	-- a wide tile: the cover a square as high as the tile, the title beside it
	local cover, info = s.meters[(p .. 'Cover'):lower()], s.meters[(p .. 'InfoTitle'):lower()]
	local cw, ch = s:number(cover:opt('W', '0'), 0), s:number(cover:opt('H', '0'), 0)
	t.ok(cw == ch and cw > 0, string.format('the cover is not a square: %sx%s', cw, ch))
	t.ok(not info.hidden and s:number(info:opt('X', '0'), 0) > cw, 'the title is not beside the cover')
end

-- OnFocus= / OnBlur=: the highlight of the keys or the pad comes onto the
-- widget's tile (before its parts are looked for: a part hidden until then,
-- shown by OnFocus, is reached), and leaves it with another category
function T.focus_shows_parts()
	local s = R.new({})
	local dir = s.data .. 'Widgets\\FocusW\\'
	host_mkdir(s.data .. 'Widgets')
	host_mkdir(dir)
	R.writeFile(dir .. 'FocusW.ini', table.concat({
		'[Raintile]',
		'OnFocus=[!SetVariable Foc on][!ShowMeterGroup FocusBtn]',
		'OnBlur=[!SetVariable Foc off][!HideMeterGroup FocusBtn]',
		'[Btn]',
		'Meter=Shape',
		'X=10',
		'Y=10',
		'Shape=Rectangle 0,0,40,40 | Fill Color 0,0,0,1 | StrokeWidth 0',
		'Part=1',
		'Group=FocusBtn',
		'Hidden=1',
		'LeftMouseUpAction=[!SetVariable Pressed yes]',
		'',
	}, '\r\n'))
	R.writeFile(s.data .. 'Categories\\Focus.ini', '[Category]\r\nName=Focus\r\n\r\n[Focus widget]\r\nWidget=custom\r\nParam=FocusW\r\n')
	s:start()
	t.clean(s)
	local target
	for i, c in ipairs(s:upvalue('cats')) do if c.name == 'Focus' then target = i end end
	t.ok(target, 'no Focus category')
	s:call('Show()')
	s:call('SetCategory(' .. target .. ')')
	t.eq(s.vars['foc'], nil, 'OnFocus before the keys came')
	s:call('Nav(0, 0)')
	t.clean(s)
	t.eq(s.vars['foc'], 'on', 'OnFocus did not run with the highlight of the keys on the tile')
	local kp = s:upvalue('M').kpart
	t.ok(kp and kp.name:match('_Btn$'), 'the part shown by OnFocus is not reached: ' .. tostring(kp and kp.name))
	s:call('Confirm()')
	t.eq(s.vars['pressed'], 'yes', 'Confirm did not press the part')
	s:call('SetCategory(' .. (target == 1 and 2 or 1) .. ')')
	t.eq(s.vars['foc'], 'off', 'OnBlur did not run with another category')
	t.clean(s)
end

-- Keyboard and pad inside a widget with parts (the rows of its list): from
-- row to row, out of the tile at the last one, back onto the nearest row
function T.parts_with_keys()
	local s = skinWithWidget('Rows=7\r\n')
	local w = testWidget(s)
	for i, c in ipairs(s:upvalue('cats')) do
		for _, tile in ipairs(c.tiles) do
			if tile == w then s:call('Show()') s:call('SetCategory(' .. i .. ')') end
		end
	end
	t.clean(s)
	local M, hover = s:upvalue('M'), s:upvalue('hover')
	local i = w.widget.idx
	local row1, row2 = 'W' .. i .. 'RowHit1', 'W' .. i .. 'RowHit2'
	t.ok(w.widget.partsAt[row1] and w.widget.partsAt[row2], 'the test widget has no two rows')
	s:call("HoverPart('" .. row1 .. "')")
	t.eq(M.kpart and M.kpart.name, row1, 'the mouse on a row: the keys go on from it')
	s:call('Nav(0, 1)')
	t.clean(s)
	t.eq(M.kpart and M.kpart.name, row2, 'down from the first row')
	t.eq(hover.toy, w.widget.partsAt[row2][2], 'the highlight on the second row')
	s:call('Nav(0, -1)')
	t.eq(M.kpart and M.kpart.name, row1, 'up from the second row')
	-- up from the first row: out of the tile (onto the one above, if any)
	local idx = hover.idx
	s:call('Nav(0, -1)')
	t.clean(s)
	t.ok(M.kpart == nil or M.kpart.t ~= w, 'still in the widget past its first row')
	if hover.idx ~= idx then
		-- and down again: onto its first row, not the whole tile
		s:call('Nav(0, 1)')
		t.clean(s)
		t.eq(M.kpart and M.kpart.name, row1, 'back down into the widget')
	end
	-- Confirm on a row: the row, not the tile (no launch animation)
	s:call('Confirm()')
	t.ok(not s:upvalue('launching'), 'Confirm on a row launched the tile')
end

-- The wheel: a custom widget (its own container, drawn after the tiles) is
-- cut by the tiles nearer the middle, as its tile is
function T.custom_widget_under_nearer_tiles()
	local s = skinWithWidget(nil, { ScrollMode = 'Wheel', LauncherMode = 'Dock', DockSide = 'Left' })
	local w = testWidget(s)
	for i, c in ipairs(s:upvalue('cats')) do
		for _, tile in ipairs(c.tiles) do
			if tile == w then s:call('Show()') s:call('SetCategory(' .. i .. ')') end
		end
	end
	t.clean(s)
	local M = s:upvalue('M')
	local slot = M.slotOfTile(w)
	t.ok(slot and M.wv[slot], 'the widget is not on the wheel')
	local box = s.meters['cw' .. w.widget.idx .. 'box']
	t.ok(box, 'no container of the custom widget')
	local shapes = {}
	for k = 1, 30 do
		local v = box:opt(k == 1 and 'Shape' or ('Shape' .. k), '')
		if v ~= '' then shapes[#shapes + 1] = v end
	end
	local text = table.concat(shapes, '\n')
	if math.abs(M.wv[slot].d) >= 0.5 then
		t.ok(text:find('Exclude', 1, true), 'a side widget not cut by the nearer tiles:\n' .. text)
	else
		t.ok(not text:find('Exclude', 1, true), 'the middle widget cut:\n' .. text)
	end
end

return T
