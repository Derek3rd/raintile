-- Steam updates waiting (UpdateInfo): the line on the tile, its border.
local R = require('rainmeter')
local t = require('t')

local T = {}

-- The launcher shown on a category whose first tile is a Steam game with an
-- update waiting (Generated\GameUpdates.txt, as GameUpdates.ps1 writes it)
local function withUpdate(settings, patch)
	local s = R.new({ settings = settings })
	if patch then patch(s) end
	s:start()
	t.clean(s)
	s:call('Show()')
	local cats = s:upvalue('cats')
	local target
	for i, c in ipairs(cats) do
		if not c.virtual and #c.tiles > 1 and not c.tiles[1].widget then target = i break end
	end
	t.ok(target, 'no category with tiles')
	s:call('SetCategory(' .. target .. ')')
	cats[target].tiles[1].steamId = '480'
	R.writeFile(s.resources .. 'Generated\\GameUpdates.txt', '480|5000000000|0|0|0|steamapps\\appmanifest_480.acf\n')
	s:call('OnGameUpdates()')
	t.clean(s)
	return s
end

local function shown(s, name)
	local m = s.meters[name:lower()]
	return m ~= nil and not m.hidden
end

-- Always (the default): the line on the tile at rest, with its border
function T.update_line_always()
	local s = withUpdate({})
	t.eq(s:upvalue('V').UpdateInfo, 'always', 'default UpdateInfo')
	t.ok(shown(s, 'TileUpd1'), 'the update line is not shown at rest')
	t.ok(shown(s, 'TileGlow1'), 'no border on the tile with an update')
	s:call('Hide()')
	t.atRest(s)
end

-- Hover: the line only on the highlighted tile; the border always
function T.update_line_hover()
	local s = withUpdate({ UpdateInfo = 'Hover' })
	t.ok(not shown(s, 'TileUpd1'), 'the update line is shown without the highlight')
	t.ok(shown(s, 'TileGlow1'), 'no border on the tile with an update')
	s:call('HoverTile(1)')
	t.ok(shown(s, 'TileUpd1'), 'the update line is not shown on the highlighted tile')
	s:call('LeaveTile(1)')
	s:call('HoverTile(2)')
	t.ok(not shown(s, 'TileUpd1'), 'the update line stays after the highlight moved')
	t.clean(s)
end

-- Never: no line, no border
function T.update_line_never()
	local s = withUpdate({ UpdateInfo = 'Never' })
	s:call('HoverTile(1)')
	t.ok(not shown(s, 'TileUpd1'), 'the update line is shown with Never')
	t.ok(not shown(s, 'TileGlow1'), 'a border with Never')
	t.clean(s)
end

-- A settings file from before UpdateInfo (not yet merged by Data.ps1):
-- GameUpdates=0 still turns it off
function T.update_line_old_setting()
	local s = withUpdate({}, function(s)
		local file = s.data .. 'Settings.inc'
		local text = R.readFile(file):gsub('\nUpdateInfo=[^\r\n]*', '\nGameUpdates=0')
		R.writeFile(file, text)
	end)
	t.ok(not shown(s, 'TileUpd1'), 'GameUpdates=0 shows the line')
	t.ok(not shown(s, 'TileGlow1'), 'GameUpdates=0 shows the border')
	t.clean(s)
end

return T
