-- The wheel (ScrollMode=Wheel): tiles on an arc, the selected one in the middle.
local R = require('rainmeter')
local t = require('t')

local T = {}

-- Background and logo files for every tile of every category (empty files:
-- the launcher only needs them to exist), before the skin loads
local function withImages(s)
	for file in (host_listdir(s.data .. 'Categories') .. '\n'):gmatch('([^\n]+)\n') do
		local base = file:match('^(.+)%.[iI][nN][iI]$')
		local text = base and R.readFile(s.data .. 'Categories\\' .. file)
		if text then
			host_mkdir(s.data .. 'Images\\' .. base)
			for _, kind in ipairs({ 'background', 'logo' }) do
				host_mkdir(s.data .. 'Images\\' .. base .. '\\' .. kind)
				for name in ('\n' .. text):gmatch('\n%[([^%]\r\n]+)%]') do
					if name:lower() ~= 'category' then
						R.writeFile(s.data .. 'Images\\' .. base .. '\\' .. kind .. '\\' .. name .. '.png', '')
					end
				end
			end
		end
	end
end

local function wheel(settings, images)
	settings = settings or {}
	settings.ScrollMode = 'Wheel'
	local s = R.new({ settings = settings })
	if images then withImages(s) end
	s:start()
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

-- Where the tile of a slot is in the grid: its container (TileBox) in the skin
local function tileXY(s, slot)
	local V = s:upvalue('V')
	local box = s.meters['tilebox' .. slot]
	return num(box, 'X') - V.PadX, num(box, 'Y') - V.GridY
end

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
	local mx, my = tileXY(s, slot)
	local cx = mx + V.TileW / 2
	local cy = my + V.TileH / 2
	local W, H = V.ClipW or V.AreaW, V.ClipH or V.AreaH
	t.ok(math.abs(cx - V.WheelAnchor / 100 * W) <= 1, 'selection across: ' .. cx)
	t.ok(math.abs(cy - H / 2) <= 1, 'selection along: ' .. cy)
	-- a side tile: fainter, nearer the docked edge (the arc bulges into the screen)
	local side = slotOf(s, offset + 1)
	if side and #c.tiles > 1 then
		local ms = s.meters['tile' .. side]
		t.ok(num(ms, 'ImageAlpha') < num(m, 'ImageAlpha') or ms:opt('ImageAlpha', '255') ~= '255', 'side tile not faded')
		local sx, sy = tileXY(s, side)
		t.ok(sx < mx, 'side tile not nearer the docked edge')
		t.ok(sy > my, 'next tile not below the selected one')
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

-- WheelBackdrop: the launcher's background takes the selected tile's
-- background image; after a turn, the next tile's, faded in
function T.backdrop_follows_the_selection()
	local s, c = wheel({ LauncherMode = 'Dock', DockSide = 'Left', WheelBackdrop = 1, Thumbnails = 0 }, true)
	local M = s:upvalue('M')
	local function selected()
		local L = #c.tiles
		local tl = c.tiles[s:upvalue('offset') % L + 1]
		return tl.backgroundFull or tl.background or ''
	end
	local function shown()
		local m = s.meters['meterbackdrop' .. M.backdrop.front]
		return m:opt('ImageName', '')
	end
	t.ok(selected() ~= '', 'the selected tile has no background (test images missing)')
	t.eq(M.backdrop.img, selected(), 'backdrop of the selected tile')
	t.eq(shown(), selected(), 'backdrop meter image')
	s:call('Scroll(1)')
	t.eq(M.backdrop.img, selected(), 'backdrop after a turn')
	t.ok(not s.meters['metertopbar'].hidden, 'no band behind the top row with the backdrop')
	t.eq(M.backdrop.f, 1, 'the fade did not finish')
	s:call('Hide()')
	t.atRest(s)
	t.clean(s)
	-- off: nothing over the background colour
	s = wheel({ LauncherMode = 'Dock', DockSide = 'Left', WheelBackdrop = 0 })
	t.ok(s.meters['meterbackdrop1'].hidden and s.meters['meterbackdrop2'].hidden, 'backdrop shown with WheelBackdrop=0')
	t.ok(s.meters['metertopbar'].hidden, 'band behind the top row without the backdrop')
	t.clean(s)
end

-- WheelIconsOnly: tiles with a logo show no background image
function T.logos_only()
	local s = wheel({ LauncherMode = 'Dock', DockSide = 'Left', WheelIconsOnly = 1, Thumbnails = 0 }, true)
	local M, V = s:upvalue('M'), s:upvalue('V')
	local tiles = s:upvalue('cur')().tiles
	local checked = 0
	for slot = 1, V.Slots do
		local e = M.wv[slot]
		if e and tiles[e.idx].logo then
			t.eq(s.meters['tile' .. slot]:opt('ImageName', ''), '', 'background shown on ' .. tiles[e.idx].name)
			checked = checked + 1
		end
	end
	t.ok(checked > 0, 'no tile with a logo was checked (test images missing)')
	t.clean(s)
end

-- The mouse wheel turns it: the highlight goes with the selection
function T.highlight_follows_the_mouse_wheel()
	local s = wheel({ LauncherMode = 'Dock', DockSide = 'Left' })
	s:call('Scroll(1)')
	local hover, offset = s:upvalue('hover'), s:upvalue('offset')
	local c = s:upvalue('cur')()
	t.ok(hover.on, 'no highlight after the mouse wheel')
	t.eq(hover.idx, offset % #c.tiles + 1, 'the highlight is not on the selected tile')
	t.clean(s)
end

-- Rounded tiles: each slot in a rounded container of its own (one shape for
-- all, overlapping, squared the corners that fell on a neighbour)
function T.rounded_corners_each()
	local s = wheel({ LauncherMode = 'Dock', DockSide = 'Left', TileRadius = 12 })
	local M, V = s:upvalue('M'), s:upvalue('V')
	local n = 0
	for slot = 1, V.Slots do
		if M.wv[slot] and M.wv[slot].a > 0.01 then
			local box = s.meters['tilebox' .. slot]
			t.ok(box and not box.hidden, 'no container for slot ' .. slot)
			t.ok(box:opt('Shape', ''):match('^Rectangle 0,0,%d+,%d+,12 '), 'slot ' .. slot .. ' not rounded: ' .. box:opt('Shape', ''))
			t.eq(s.meters['tile' .. slot]:opt('Container', ''), 'TileBox' .. slot, 'tile not in its container')
			t.eq(s.meters['tile' .. slot]:opt('X', ''), '0', 'tile not at the corner of its container')
			n = n + 1
		end
	end
	t.ok(n > 1, 'too few tiles shown')
	t.clean(s)
end

-- Infinite scroll with few tiles (fewer than shown): they repeat, and it turns round
local function fewest(s)
	local best, n
	for i, c in ipairs(s:upvalue('cats')) do
		if not c.virtual and #c.tiles > 1 and (not n or #c.tiles < n) then best, n = i, #c.tiles end
	end
	return best, n
end

function T.few_tiles_repeat()
	local s = wheel({ LauncherMode = 'Dock', DockSide = 'Left', InfiniteScroll = 1, WheelVisible = 11 })
	local i, n = fewest(s)
	t.ok(n and n < 13, 'no category with few tiles')
	s:call('SetCategory(' .. i .. ')')
	s:call('Scroll(-1)')
	t.eq(s:upvalue('offset'), -1, 'did not turn back past the first tile')
	local M, V, seen = s:upvalue('M'), s:upvalue('V'), 0
	for slot = 1, V.Slots do if M.wv[slot] then seen = seen + 1 end end
	t.ok(seen > n, 'tiles not repeated: ' .. seen .. ' shown of ' .. n)
	t.clean(s)
end

function T.few_tiles_repeat_in_the_grid()
	local s = R.new({ settings = { InfiniteScroll = 1, NX = 4, NY = 3 } }):start()
	s:call('Show()')
	local i = fewest(s)
	s:call('SetCategory(' .. i .. ')')
	s:call('Scroll(1)')
	t.eq(s:upvalue('offset'), 1, 'the grid with few tiles does not scroll round')
	s:call('Scroll(-2)')
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
	local tx, ty = tileXY(s, slot)
	local tileY = ty + V.GridY + V.TileH / 2
	local discY = num(dot, 'Y') + 0.5 * (V.TileW * V.WheelMenuSize / 100)
	t.ok(math.abs(discY - tileY) <= 2, 'disc not level with the selected tile: ' .. discY .. ' / ' .. tileY)
	t.ok(num(dot, 'X') < tx + V.PadX, 'disc not nearer the docked edge than the tile')
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

-- Widgets: in their own container, drawn over the tiles (in GridClip they
-- were under every tile, so the one in the middle was covered); live in the
-- middle, a plain tile with its name at the sides, where tiles overlap
local function dashboard(settings)
	settings.LauncherMode, settings.DockSide = 'Dock', 'Left'
	local s = wheel(settings)
	for i, c in ipairs(s:upvalue('cats')) do
		if c.name == 'Dashboard' then s:call('SetCategory(' .. i .. ')') end
	end
	t.clean(s)
	local live = 0
	for name, m in pairs(s.meters) do
		if name:match('^w%d+title$') and not m.hidden then
			live = live + 1
			t.eq(m:opt('Container', ''), 'WidgetClip', 'container of ' .. name)
		end
	end
	return s, live
end

function T.widgets_over_the_tiles()
	local s, live = dashboard({})
	t.ok(s.meters.widgetclip, 'no WidgetClip container in the wheel')
	t.ok(not s.meters.widgetclip.hidden, 'WidgetClip hidden with a widget in the middle')
	-- with no widget in it Rainmeter draws the container: a black rectangle
	for i, c in ipairs(s:upvalue('cats')) do
		if c.name ~= 'Dashboard' and not c.virtual and #c.tiles > 0 and not c.widgets then
			s:call('SetCategory(' .. i .. ')')
			break
		end
	end
	t.clean(s)
	t.ok(s.meters.widgetclip.hidden, 'WidgetClip shown with no widget: a black rectangle')
	s = dashboard({})
	t.eq(live, 1, 'widgets drawn (only the one in the middle)')
	local pos = s:upvalue('pos')
	local mid, side = slotOf(s, pos), slotOf(s, pos + 1)
	t.eq(s.meters['tilelabel' .. mid].hidden, true, 'name of the widget in the middle')
	t.eq(s.meters['tilelabel' .. side].hidden, false, 'name of the widget beside it')
	-- tiles apart: every widget is live
	s, live = dashboard({ WheelSpacing = 110 })
	t.ok(live > 1, 'tiles apart: only ' .. live .. ' widget drawn')
	-- a widget repeated (few tiles): its meters with one copy, the others named
	local M = s:upvalue('M')
	local copies, named = {}, 0
	for slot, e in pairs(M.wv) do
		local tile = s:upvalue('tileAt')(slot)
		if tile and tile.widget and not s.meters['tile' .. slot].hidden and num(s.meters['tile' .. slot], 'ImageAlpha') ~= 0 then
			copies[tile.widget.idx] = (copies[tile.widget.idx] or 0) + 1
			if not s.meters['tilelabel' .. slot].hidden then named = named + 1 end
		end
	end
	local extra = 0
	for _, n in pairs(copies) do extra = extra + n - 1 end
	t.ok(extra > 0, 'no widget repeated in the test')
	t.ok(named >= extra, 'repeated widgets without their name: ' .. named .. ' of ' .. extra)
end

return T
