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
end

return T
