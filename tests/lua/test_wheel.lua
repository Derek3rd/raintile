-- The wheel (ScrollMode=Wheel): tiles on an arc, the selected one in the middle.
local R = require('rainmeter')
local t = require('t')

local T = {}

local function wheel(settings)
	settings = settings or {}
	settings.ScrollMode = 'Wheel'
	local s = R.new({ settings = settings }):start()
	t.clean(s)
	t.ok(s:upvalue('ready'), 'the launcher is not ready after loading')
	s:call('Show()')
	-- a category with tiles to turn
	local cats = s:upvalue('cats')
	local best, most = 1, 0
	for i, c in ipairs(cats) do
		if not c.virtual and #c.tiles > most then best, most = i, #c.tiles end
	end
	s:call('SetCategory(' .. best .. ')')
	t.clean(s)
	return s, cats[best]
end

local function num(m, key) return tonumber(m:opt(key, '0')) end

-- The slot of the tile at line k, and that slot
local function slotOf(s, k)
	local M = s:upvalue('M')
	for slot, e in pairs(M.wv) do
		if e.k == k then return slot, e end
	end
end

-- Everything a person does with it, in every mode; at rest afterwards
local function session(settings)
	local s = wheel(settings)
	for _ = 1, 3 do s:call('Scroll(1)') end
	s:call('Scroll(-1)')
	s:call('Nav(0, 1)')
	s:call('Nav(1, 0)')
	s:call('Nav(0, -1)')
	for slot = 1, 6 do
		s:call('HoverTile(' .. slot .. ')')
		s:call('LeaveTile(' .. slot .. ')')
	end
	s:call('NextCategory(1)')
	s:call('NextCategory(-1)')
	s:call('Hide()')
	t.clean(s)
	t.atRest(s)
end

function T.docked_left() session({ LauncherMode = 'Dock', DockSide = 'Left' }) end
function T.docked_right() session({ LauncherMode = 'Dock', DockSide = 'Right' }) end
function T.docked_top() session({ LauncherMode = 'Dock', DockSide = 'Top' }) end
function T.docked_bottom() session({ LauncherMode = 'Dock', DockSide = 'Bottom' }) end
function T.window() session({ LauncherMode = 'Window' }) end
function T.fullscreen() session({ LauncherMode = 'Fullscreen' }) end

-- Slots: the tiles shown plus one beyond each end; the middle tile in the last
-- slot (drawn on top), at the selection point, the others fainter
function T.middle_tile_on_top()
	local s, c = wheel({ LauncherMode = 'Dock', DockSide = 'Left', WheelVisible = 7 })
	local V, M = s:upvalue('V'), s:upvalue('M')
	t.eq(V.Slots, 9, 'slots')
	local offset = s:upvalue('offset')
	local slot, e = slotOf(s, offset)
	t.ok(slot, 'the selected tile is not in a slot')
	t.eq(slot, V.Slots, 'slot of the selected tile (the last: on top)')
	t.eq(e.a, 1, 'alpha of the selected tile')
	local m = s.meters['tile' .. slot]
	local f = M.wf
	-- docked left: the selection across at WheelAnchor from the left, in the middle along
	local cx = num(m, 'X') + V.TileW / 2
	local cy = num(m, 'Y') + V.TileH / 2
	local W, H = V.ClipW or V.AreaW, V.ClipH or V.AreaH
	t.ok(math.abs(cx - V.WheelAnchor / 100 * W) <= 1, 'selection across: ' .. cx)
	t.ok(math.abs(cy - H / 2) <= 1, 'selection along: ' .. cy)
	-- a side tile: fainter, nearer the docked edge (the arc bulges into the screen)
	local side = slotOf(s, offset + 1)
	if side and #c.tiles > 1 then
		local ms = s.meters['tile' .. side]
		t.ok(num(ms, 'ImageAlpha') < num(m, 'ImageAlpha') or ms:opt('ImageAlpha', '255') ~= '255', 'side tile not faded')
		t.ok(num(ms, 'X') < num(m, 'X'), 'side tile not nearer the docked edge')
		t.ok(num(ms, 'Y') > num(m, 'Y'), 'next tile not below the selected one')
	end
	t.ok(f and f.R > 0, 'no circle')
	t.clean(s)
end

-- Scrolling turns the wheel by one tile: the next tile ends in the middle
function T.scroll_turns()
	local s, c = wheel({ LauncherMode = 'Dock', DockSide = 'Left' })
	t.ok(#c.tiles > 2, 'too few tiles to turn')
	local before = s:upvalue('offset')
	s:call('Scroll(1)')
	t.eq(s:upvalue('offset'), before + 1, 'offset after one notch')
	t.eq(s:upvalue('pos'), before + 1, 'the turn did not end at the target')
	local slot = slotOf(s, before + 1)
	t.eq(slot, s:upvalue('V').Slots, 'the next tile is not on top after the turn')
	s:call('Hide()')
	t.atRest(s)
	t.clean(s)
end

-- Names: only on the middle tile (WheelLabels=Center)
function T.names_on_the_middle_tile()
	local s = wheel({ LauncherMode = 'Dock', DockSide = 'Left', WheelLabels = 'Center' })
	local V = s:upvalue('V')
	local shown = 0
	for slot = 1, V.Slots do
		local m = s.meters['tilelabel' .. slot]
		if m and not m.hidden then shown = shown + 1 end
	end
	t.ok(shown <= 1, 'names on ' .. shown .. ' tiles')
	t.clean(s)
end

-- A click on a side tile: WheelClick=Center turns it to the middle (no
-- launch); the mouse resting on one (WheelHover=Turn) turns it too
function T.click_and_hover_turn()
	local s, c = wheel({ LauncherMode = 'Dock', DockSide = 'Left', WheelClick = 'Center', WheelHover = 'Highlight' })
	t.ok(#c.tiles > 2, 'too few tiles')
	local start = s:upvalue('offset')
	local side = slotOf(s, start + 1)
	local before = #s.commands
	s:call('Launch(' .. side .. ')')
	t.eq(s:upvalue('offset'), start + 1, 'click on a side tile did not turn the wheel')
	t.ok(not s:upvalue('launching') and #s.commands == before, 'click on a side tile launched it')

	s = wheel({ LauncherMode = 'Dock', DockSide = 'Left', WheelHover = 'Turn' })
	start = s:upvalue('offset')
	side = slotOf(s, start + 1)
	s:call('HoverTile(' .. side .. ')')
	t.eq(s:upvalue('offset'), start + 1, 'resting on a side tile did not turn the wheel')
	s:call('Hide()')
	t.atRest(s)
	t.clean(s)
end

-- After a turn by the resting mouse, the tile that comes under the still
-- mouse does not turn the wheel again; once the mouse moves, it does
function T.still_mouse_turns_once()
	local s = wheel({ LauncherMode = 'Dock', DockSide = 'Left', WheelHover = 'Turn' })
	local start = s:upvalue('offset')
	s:call("HoverTile(" .. slotOf(s, start + 1) .. ", '200', '300')")
	t.eq(s:upvalue('offset'), start + 1, 'resting on a side tile did not turn the wheel')
	-- the next tile is now where the mouse is
	s:call("HoverTile(" .. slotOf(s, start + 2) .. ", '200', '300')")
	t.eq(s:upvalue('offset'), start + 1, 'the still mouse turned the wheel again')
	s:call("HoverTile(" .. slotOf(s, start + 2) .. ", '205', '330')")
	t.eq(s:upvalue('offset'), start + 2, 'the moved mouse did not turn the wheel')
	t.clean(s)
end

-- Size= is not used: every tile one cell
function T.one_cell_each()
	local s = wheel({ LauncherMode = 'Dock', DockSide = 'Left' })
	for _, c in ipairs(s:upvalue('cats')) do
		t.ok(not c.pack, 'category ' .. c.name .. ' packed in the wheel')
		for _, tile in ipairs(c.tiles) do
			t.ok((tile.cols or 1) == 1 and (tile.rows or 1) == 1, tile.name .. ' is not one cell')
		end
	end
	t.clean(s)
end

-- The inner ring (WheelMenu=Ring): a disc per category of the menu, the
-- active one in line with the selected tile; Q / E turn it, the menu at the
-- top no longer shows the categories
function T.inner_ring()
	local s = wheel({ LauncherMode = 'Dock', DockSide = 'Left', WheelMenu = 'Ring' })
	local cats, M, V = s:upvalue('cats'), s:upvalue('M'), s:upvalue('V')
	local active = s:upvalue('active')
	local dot = s.meters['ringdot' .. active]
	t.ok(dot and not dot.hidden, 'no disc for the active category')
	local name = s.meters['ringname']
	t.ok(name and not name.hidden, 'the name of the active category is not shown')
	-- in line with the selected tile: on the same horizontal (docked left), nearer the edge
	local slot = slotOf(s, s:upvalue('offset'))
	local tile = s.meters['tile' .. slot]
	local tileY = num(tile, 'Y') + V.GridY + V.TileH / 2
	local discY = num(dot, 'Y') + 0.5 * (V.TileW * V.WheelMenuSize / 100)
	t.ok(math.abs(discY - tileY) <= 2, 'disc not level with the selected tile: ' .. discY .. ' / ' .. tileY)
	t.ok(num(dot, 'X') < num(tile, 'X') + V.PadX, 'disc not nearer the docked edge than the tile')
	for i, c in ipairs(cats) do
		if not c.virtual then
			local m = s.meters['cathit' .. i]
			t.ok(not m or m.hidden, 'menu entry ' .. c.name .. ' still at the top')
		end
	end
	-- Q / E: the next category of the ring, the ring turns to it
	s:call('NextCategory(1)')
	t.ok(s:upvalue('active') ~= active, 'NextCategory did not change category')
	t.ok(not cats[s:upvalue('active')].virtual, 'NextCategory went to Favorites / Recent')
	t.eq(M.ring.pos, M.ring.to, 'the ring did not finish turning')
	s:call('Hide()')
	t.clean(s)
	t.atRest(s)
end

-- WheelMenu=Bar: the categories stay in the menu at the top, no ring
function T.menu_bar()
	local s = wheel({ LauncherMode = 'Dock', DockSide = 'Left', WheelMenu = 'Bar' })
	t.ok(not s.meters['ringname'], 'ring meters written with WheelMenu=Bar')
	t.clean(s)
end

return T
