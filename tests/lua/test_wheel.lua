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

-- WheelLogoOn=Background: the selected tile's logo on the backdrop, where it
-- sits on the tile (centred by default), WheelBackdropLogoSize of the area's
-- height; not on its tile, still on the others. After a turn, the next one's.
function T.logo_on_the_backdrop()
	local s, c = wheel({ LauncherMode = 'Fullscreen', WheelLogoOn = 'Background', WheelBackdropLogoSize = 40, Thumbnails = 0 }, true)
	local M, V = s:upvalue('M'), s:upvalue('V')
	local function check(what)
		local L = #c.tiles
		local k = s:upvalue('offset')
		local tl = c.tiles[k % L + 1]
		t.ok(tl.logo, 'the selected tile has no logo (test images missing)')
		local slot = slotOf(s, k)
		t.ok(s.meters['tileicon' .. slot].hidden, what .. ': the logo is still on the selected tile')
		local logo = s.meters['backdroplogo']
		t.ok(not logo.hidden, what .. ': no logo on the backdrop')
		t.eq(logo:opt('ImageName', ''), tl.logoFull, what .. ': the image on the backdrop')
		local ax, ay, W, H = M.backdropArea()
		local size = num(logo, 'W')
		t.eq(size, math.floor(H * 40 / 100 * tl.logoScale + 0.5), what .. ': logo size')
		t.ok(math.abs(num(logo, 'X') + size / 2 - (ax + W / 2)) <= 1, what .. ': logo not centred across')
		t.ok(math.abs(num(logo, 'Y') + size / 2 - (ay + H / 2)) <= 1, what .. ': logo not centred down')
		-- the other tiles keep theirs
		local side = slotOf(s, k + 1)
		local st = side and c.tiles[(k + 1) % L + 1]
		if st and st.logo and st ~= tl then t.ok(not s.meters['tileicon' .. side].hidden, what .. ': a side tile lost its logo') end
	end
	check('at first')
	s:call('Scroll(1)')
	check('after a turn')
	s:call('Hide()')
	t.atRest(s)
	t.clean(s)
	-- on the tile (the default): nothing on the backdrop
	s = wheel({ LauncherMode = 'Fullscreen', Thumbnails = 0 }, true)
	t.ok(s.meters['backdroplogo'].hidden, 'a logo on the backdrop with WheelLogoOn=Tile')
	t.clean(s)
end

-- WheelInfoOn=Background: the selected tile's update line on the backdrop, at
-- the top left of the area under the top row (InfoPos 0,0); no tile of the
-- wheel shows its line, also with UpdateInfo=Always
function T.info_on_the_backdrop()
	local s, c = wheel({ LauncherMode = 'Fullscreen', WheelInfoOn = 'Background', UpdateInfo = 'Always' })
	local M, V = s:upvalue('M'), s:upvalue('V')
	local L = #c.tiles
	t.ok(L > 2, 'too few tiles')
	local k = s:upvalue('offset')
	local tl, next = c.tiles[k % L + 1], c.tiles[(k + 1) % L + 1]
	t.ok(not tl.widget and not next.widget, 'a widget where a game is wanted')
	-- the selected tile and the next one with an update
	tl.steamId, next.steamId = '480', '481'
	R.writeFile(s.resources .. 'Generated\\GameUpdates.txt',
		'480|5000000000|0|0|0|steamapps\\appmanifest_480.acf\n481|3000000000|0|0|0|steamapps\\appmanifest_481.acf\n')
	s:call('OnGameUpdates()')
	t.ok(s.meters['tileupd' .. slotOf(s, k)].hidden, 'the update line is still on the selected tile')
	t.ok(s.meters['tileupd' .. slotOf(s, k + 1)].hidden, 'an update line on a side tile')
	local upd = s.meters['backdropupd']
	t.ok(not upd.hidden, 'no update line on the backdrop')
	local ax, ay = M.backdropArea()
	t.eq(num(upd, 'X'), ax + V.LabelPad, 'update line across')
	t.eq(num(upd, 'Y'), ay + V.LabelPad, 'update line down')
	local text = upd:opt('Text', '')
	-- the selection moves on: the next tile's line on the backdrop, none on the
	-- tile that was selected
	s:call('Scroll(1)')
	t.ok(not upd.hidden, 'no update line on the backdrop after a turn')
	t.ok(upd:opt('Text', '') ~= text, 'the line of the tile selected before stayed')
	t.ok(s.meters['tileupd' .. slotOf(s, k)].hidden, 'an update line on the tile selected before')
	t.clean(s)
end

-- Logos only with the logo on the backdrop: the selected tile shows its art,
-- not an empty colour; the others their logo on a colour
function T.logos_only_with_the_logo_on_the_backdrop()
	local s, c = wheel({ LauncherMode = 'Fullscreen', WheelIconsOnly = 1, WheelLogoOn = 'Background', Thumbnails = 0 }, true)
	local L = #c.tiles
	local k = s:upvalue('offset')
	local tl = c.tiles[k % L + 1]
	t.ok(tl.logo and tl.background, 'the selected tile has no logo or background (test images missing)')
	t.eq(s.meters['tile' .. slotOf(s, k)]:opt('ImageName', ''), tl.background, 'image of the selected tile')
	local side = slotOf(s, k + 1)
	local st = c.tiles[(k + 1) % L + 1]
	if side and st.logo and st ~= tl then
		t.eq(s.meters['tile' .. side]:opt('ImageName', ''), '', 'a side tile shows its background with logos only')
	end
	-- turned: the tile that was selected goes back to its logo
	s:call('Scroll(1)')
	t.eq(s.meters['tile' .. slotOf(s, k)]:opt('ImageName', ''), '', 'the tile selected before kept its background')
	t.clean(s)
end

-- The logo on the backdrop: LogoPos= as on a tile, on the area (its centre
-- there, kept inside it; the tile editor shows that area in this mode), with
-- no grid tile or Size= in between
function T.logo_on_the_backdrop_where_logopos_puts_it()
	local s, c = wheel({ LauncherMode = 'Fullscreen', WheelLogoOn = 'Background', Thumbnails = 0 }, true)
	local M = s:upvalue('M')
	local L = #c.tiles
	local tl = c.tiles[s:upvalue('offset') % L + 1]
	t.ok(tl.logo, 'the selected tile has no logo (test images missing)')
	local logo = s.meters['backdroplogo']
	local ax, ay, W, H = M.backdropArea()
	-- the top left corner: kept inside, against it
	tl.logoX, tl.logoY, tl.logoScale, tl.logoRatio, tl.cols = 0, 0, 1.6, nil, 2
	M.backdropLogo()
	t.eq(num(logo, 'X'), ax, 'logo not against the left of the area')
	t.eq(num(logo, 'Y'), ay, 'logo not against the top of the area')
	-- 25,75: its centre there
	tl.logoX, tl.logoY = 0.25, 0.75
	M.backdropLogo()
	local size = num(logo, 'W')
	t.ok(math.abs(num(logo, 'X') + size / 2 - (ax + 0.25 * W)) <= 1, 'logo centre across')
	t.ok(math.abs(num(logo, 'Y') + size / 2 - (ay + 0.75 * H)) <= 1, 'logo centre down')
	t.clean(s)
end

-- Not in the wheel: the settings of the backdrop do nothing
function T.backdrop_settings_in_the_grid()
	local s = R.new({ settings = { WheelLogoOn = 'Background', WheelInfoOn = 'Background', Thumbnails = 0 } })
	withImages(s)
	s:start()
	s:call('Show()')
	local cats = s:upvalue('cats')
	local best, most = 1, 0
	for i, c in ipairs(cats) do
		if not c.virtual and #c.tiles > most then best, most = i, #c.tiles end
	end
	s:call('SetCategory(' .. best .. ')')
	t.ok(s.meters['backdroplogo'].hidden and s.meters['backdropupd'].hidden and s.meters['backdropinfo'].hidden, 'backdrop meters shown in the grid')
	local shown = 0
	for slot = 1, s:upvalue('V').Slots do
		local m = s.meters['tileicon' .. slot]
		if m and not m.hidden then shown = shown + 1 end
	end
	t.ok(shown > 0, 'no logo on the tiles of the grid (test images missing)')
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

-- Rainmeter draws a container meter with no meters in it as a plain shape:
-- every container shown has meters in it
local function noEmptyContainers(s, what)
	local used = {}
	for _, m in pairs(s.meters) do
		local c = m:opt('Container', '')
		if c ~= '' then used[c:lower()] = true end
	end
	for _, name in ipairs({ 'gridclip', 'hoverclip', 'widgetclip' }) do
		local m = s.meters[name]
		if m and not m.hidden then t.ok(used[name], what .. ': ' .. name .. ' shown with nothing in it (a black rectangle)') end
	end
end

-- Widgets: in their own container (WidgetClip), drawn after the tiles; each
-- seen only where its tile is (cut by the nearer tiles), faded like it
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
	noEmptyContainers(s, 'Dashboard')
	t.ok(not s.meters.widgetclip.hidden, 'WidgetClip hidden with widgets')
	t.ok(live > 1, 'only ' .. live .. ' widget drawn: the side ones too')
	-- the mask: a tile each, the side ones cut by the nearer tiles
	local mask = {}
	for k = 1, 200 do
		local v = s.meters.widgetclip:opt(k == 1 and 'Shape' or ('Shape' .. k), '')
		if v ~= '' then mask[#mask + 1] = v end
	end
	local text = table.concat(mask, '\n')
	t.ok(text:find('Exclude'), 'side widgets not cut by the nearer tiles:\n' .. text)
	-- a widget repeated (few tiles): its data on one copy, the others named
	local M = s:upvalue('M')
	local copies, named = {}, 0
	for slot in pairs(M.wv) do
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
	-- a category without widgets: nothing shown with nothing in it
	for i, c in ipairs(s:upvalue('cats')) do
		if c.name ~= 'Dashboard' and not c.virtual and #c.tiles > 0 and not c.widgets then
			s:call('SetCategory(' .. i .. ')')
			break
		end
	end
	t.clean(s)
	noEmptyContainers(s, 'no widgets')
	t.ok(s.meters.widgetclip.hidden, 'WidgetClip shown with no widget')
end

return T
