-- The carousel (CenterSelection=1): the grid keeps the selected line in the
-- middle, and a wheel notch, the keys and the gamepad bring the previous or
-- next tile there.
local R = require('rainmeter')
local t = require('t')

local T = {}

-- The launcher with a category "Carousel" of n tiles (sizes[i]: Size= of the
-- i-th), shown and opened on it. Defaults: carousel on, 5 columns of one row
-- scrolled horizontally, no infinite scroll, no scroll animation.
local function carousel(settings, n, sizes, prepare)
	settings = settings or {}
	local defaults = { CenterSelection = 1, ScrollDir = 'H', NX = 5, NY = 1, InfiniteScroll = 0, AnimScroll = 0 }
	for k, v in pairs(defaults) do
		if settings[k] == nil then settings[k] = v end
	end
	local s = R.new({ settings = settings })
	-- (sizes.all: TileSize= of the category)
	local lines = { '[Category]', 'Name=Carousel', 'Order=0', sizes and sizes.all and 'TileSize=' .. sizes.all or '', '' }
	for i = 1, n or 9 do
		lines[#lines + 1] = '[T' .. i .. ']'
		lines[#lines + 1] = 'Command=notepad.exe'
		if sizes and sizes[i] then lines[#lines + 1] = 'Size=' .. sizes[i] end
	end
	R.writeFile(s.data .. 'Categories\\Carousel.ini', table.concat(lines, '\r\n') .. '\r\n')
	if prepare then prepare(s) end
	s:start()
	t.clean(s)
	t.ok(s:upvalue('ready'), 'the launcher is not ready after loading')
	s:call('Show()')
	local index
	for i, c in ipairs(s:upvalue('cats')) do
		if c.name == 'Carousel' then index = i end
	end
	t.ok(index, 'no Carousel category')
	s:call('SetCategory(' .. index .. ')')
	t.clean(s)
	return s, index
end

-- The highlighted tile (its number, T<n>) and the scroll position
local function state(s)
	local hover = s:upvalue('hover')
	local tile = hover.on and s:upvalue('cur')().tiles[hover.idx]
	return tile and tonumber(tile.name:match('^T(%d+)$')), s:upvalue('offset')
end

local function expect(s, tile, offset, what)
	local got, o = state(s)
	t.eq(got, tile, what .. ': tile in the middle')
	t.eq(o, offset, what .. ': offset')
	t.eq(s:upvalue('pos'), offset, what .. ': position on screen')
end

-- The first tile starts in the middle, with empty room on its left; a notch
-- moves by one tile whatever ScrollStep; the ends stay in the middle.
function T.one_tile_per_notch()
	local s = carousel({ ScrollStep = 3 })
	expect(s, 1, -2, 'opened')
	s:call('Scroll(1)')
	expect(s, 2, -1, 'one notch')
	s:call('Scroll(-1)')
	s:call('Scroll(-1)')
	expect(s, 1, -2, 'back past the first')
	for _ = 1, 12 do s:call('Nav(1, 0)') end
	expect(s, 9, 6, 'to the last with the keys')
	s:call('Scroll(1)')
	expect(s, 9, 6, 'past the last')
	-- the slots of the empty room beside the last tile are hidden
	local hidden = 0
	for slot = 1, s:upvalue('V').Slots do
		local m = s.meters['tile' .. slot]
		if m and m.hidden then hidden = hidden + 1 end
	end
	t.ok(hidden >= 2, 'the empty room after the last tile shows tiles')
	t.clean(s)
end

-- With more rows the whole column is in the middle: up and down move only
-- the highlight in it, and the row is kept from column to column.
function T.rows_of_the_middle_column()
	local s = carousel({ NY = 2 }, 9)
	expect(s, 1, -2, 'opened')
	s:call('Nav(0, 1)')
	expect(s, 2, -2, 'down')
	s:call('Scroll(1)')
	expect(s, 4, -1, 'next column, same row')
	for _ = 1, 6 do s:call('Nav(1, 0)') end
	-- the last column has one tile: the highlight stops on it
	expect(s, 9, 2, 'last column')
	t.clean(s)
end

-- The mouse highlights a tile beside the middle; the next notch still goes
-- on from the tile in the middle (and the grid is drawn even when that is
-- the tile already highlighted)
function T.mouse_beside_the_middle()
	local s = carousel({}, 9)
	-- slot 4: the column right of the middle (T2)
	s:call('HoverTile(4)')
	t.eq((state(s)), 2, 'tile under the mouse')
	local redraws = 0
	local before = #s.log
	s:call('Scroll(1)')
	for i = before + 1, #s.log do
		if s.log[i]:lower():find('!redraw', 1, true) then redraws = redraws + 1 end
	end
	expect(s, 2, -1, 'notch onto the tile under the mouse')
	t.ok(redraws > 0, 'the grid was not drawn after the notch')
	-- slot 5: two columns right of the middle (T4)
	s:call('HoverTile(5)')
	t.eq((state(s)), 4, 'tile under the mouse')
	s:call('Scroll(1)')
	expect(s, 3, 0, 'notch with the mouse two tiles away')
	t.clean(s)
end

-- Infinite scroll: the first tile in the middle with the last ones on its
-- left, and round past the ends
function T.infinite()
	local s = carousel({ InfiniteScroll = 1 }, 9)
	expect(s, 1, 7, 'opened')
	s:call('Scroll(-1)')
	expect(s, 9, 6, 'back from the first')
	s:call('Scroll(1)')
	s:call('Scroll(1)')
	expect(s, 2, 8, 'round again')
	t.clean(s)
end

-- Scrolling vertically the rows count: the selected row in the middle
function T.vertical()
	local s = carousel({ ScrollDir = 'V', NX = 2, NY = 3 }, 9)
	expect(s, 1, -1, 'opened')
	s:call('Scroll(1)')
	expect(s, 3, 0, 'one notch')
	s:call('Nav(1, 0)')
	expect(s, 4, 0, 'right, in the row')
	t.clean(s)
end

-- Tiles of more cells: an odd tile is centred on its middle column
function T.odd_tile_centred()
	local s = carousel({}, 9, { [4] = '3x1' })
	for _ = 1, 3 do s:call('Nav(1, 0)') end
	-- T4 takes the columns 3, 4 and 5: 4 in the middle
	expect(s, 4, 2, 'the wide tile')
	s:call('Scroll(1)')
	expect(s, 5, 4, 'the next one')
	s:call('Scroll(-1)')
	expect(s, 4, 2, 'back to the wide tile')
	t.clean(s)
end

-- TileSize= of the category: the size of every tile without a Size= of its own
function T.tile_size_of_the_category()
	local s = carousel({}, 5, { all = '3x1', [2] = '1x1' })
	local c = s:upvalue('cats')[s:upvalue('active')]
	t.eq(c.tiles[1].cols, 3, 'tile without its own size')
	t.eq(c.tiles[2].cols, 1, 'tile with its own size')
	t.ok(s:upvalue('M').carousel(), 'carousel off')
	-- T1 takes the columns 0-2, T2 the 3rd: one notch centres T2
	expect(s, 1, -1, 'opened on the wide tile')
	s:call('Scroll(1)')
	expect(s, 2, 1, 'the narrow one')
	s:call('Scroll(1)')
	expect(s, 3, 3, 'the next wide one')
	t.clean(s)
end

-- An even number of columns: the selected tile still in the middle of the
-- screen, the grid half a column off, a half column at each side
function T.even_columns()
	local s = carousel({ NX = 4 }, 9)
	t.ok(s:upvalue('M').carousel(), 'no carousel with 4 columns')
	-- the middle is between the 2nd and the 3rd column: 1.5 lines before it
	expect(s, 1, -1.5, 'opened')
	s:call('Scroll(1)')
	expect(s, 2, -0.5, 'a notch')
	s:call('Nav(1, 0)')
	expect(s, 3, 0.5, 'right')
	-- the tile in the middle of the grid area
	local V, M = s:upvalue('V'), s:upvalue('M')
	local hover = s:upvalue('hover')
	local x = s:upvalue('gridToPx')(hover.tx, hover.ty)
	local mid = x + V.TileW / 2
	t.ok(math.abs(mid - (V.ClipW or V.AreaW) / 2) <= V.Gap, string.format('the tile in the middle at %d, the area %d wide', mid, V.ClipW or V.AreaW))
	-- the half columns at the sides are drawn: a tile cut by each edge
	local cutLeft, cutRight
	for slot = 1, V.Slots do
		local m = s.meters['tile' .. slot]
		if m and not m.hidden then
			local mx = tonumber(m:opt('X', '0'))
			if mx < 0 then cutLeft = true end
			if mx + V.TileW > (V.ClipW or V.AreaW) then cutRight = true end
		end
	end
	t.ok(cutLeft and cutRight, 'no half column at the sides')
	t.clean(s)
end

-- A tile of an even width: its middle (between two columns) in the middle
function T.even_tile_centred()
	local s = carousel({}, 9, { [2] = '2x1' })
	t.ok(s:upvalue('M').carousel(), 'no carousel with a tile two columns wide')
	expect(s, 1, -2, 'opened')
	-- T2 takes the columns 1 and 2: its middle, 1.5, in the middle (2 lines in)
	s:call('Scroll(1)')
	expect(s, 2, -0.5, 'the wide tile')
	s:call('Scroll(1)')
	expect(s, 3, 1, 'the next one')
	s:call('Scroll(-1)')
	expect(s, 2, -0.5, 'back to the wide tile')
	t.clean(s)
end

-- The place kept in State.inc is the line in the middle: 0 is the start
-- with the carousel on or off, and a load comes back to it
function T.saved_place()
	local s, index = carousel({}, 9)
	s:call('Scroll(1)')
	s:call('Scroll(1)')
	-- to another category and back: the place is written and read again
	local before = #s.log
	s:call('SetCategory(' .. (index == 1 and 2 or 1) .. ')')
	local written
	for i = before + 1, #s.log do
		if s.log[i]:find('Scroll_Carousel', 1, true) then written = s.log[i] end
	end
	t.ok(written and written:find('Scroll_Carousel%W+2%f[%W]'), 'State.inc does not get the line in the middle: ' .. tostring(written))
	s:call('SetCategory(' .. index .. ')')
	expect(s, 3, 0, 'back to the category')
	t.clean(s)
	-- loaded with the place of a plain grid (the 4th line first): that line
	-- in the middle
	s = carousel({}, 9, nil, function(skin)
		local file = skin.data .. 'State.inc'
		R.writeFile(file, R.readFile(file) .. '\r\nScroll_Carousel=3\r\n')
	end)
	expect(s, 4, 1, 'loaded')
	t.clean(s)
end

return T
