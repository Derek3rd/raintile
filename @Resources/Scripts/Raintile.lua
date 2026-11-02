-- Raintile: launcher logic.
--
-- The grid has a fixed number of "slots" (meters). Scrolling or switching
-- category never creates meters: only the options of the existing slots
-- change, and only those whose value actually changed.
-- Slot and menu meters are written to Generated\Grid.inc, which is
-- regenerated (with a skin refresh) when the grids, the menu mode or the
-- categories change.

local V = {}          -- settings
local ready = false   -- categories loaded and grid ready
local cats = {}       -- { { name, label, icon, parts, tiles = { ... } }, ... }
local active = 1      -- active category
local offset = 0      -- rows (V) or columns (H) scrolled: target
local pos = 0         -- displayed scroll position (fractional while animating)
local base = -1       -- row/column shown by the first slot (-1 = contents must be reset)
local slots = 0
local cache = {}      -- last value set per meter/option
local dirty = {}      -- meters with changed options, updated on the next draw
local hovered = 0     -- category under the mouse
local launching = nil -- launch animation in progress: { tile, x, y, frame }
local laidOut = false -- menu already measured and centred
local appear = nil    -- steps since the tiles started appearing (nil = none)
-- Highlight of the tile under the mouse, in grid units (column, row) so it
-- follows the tiles while scrolling; a = opacity 0-1.
local hover = { idx = 0, on = false, gx = 0, gy = 0, tx = 0, ty = 0, a = 0 }
local pillPos = nil   -- { x, w } of the active category pill
-- Tiles whose logo is (or is going back from being) lit by hover: [tile] = true.
-- tile.zoom (0-1) is the progress, used for the logo's zoom and colour.
local zooming = {}
local ticking = false -- animation clock (ActionTimer) running
local visible = true  -- launcher shown (Show/Hide)
local searchCat = nil -- search results, shown instead of the active category
local query = ''      -- searched text
local typing = false  -- the search bar is being typed in (Typing mini-skin on)
local typed = ''      -- text typed so far
local leaveSearch     -- defined in the Search section
local stopTyping      -- defined in the Search section
-- Dot on the gear: an update, new games or apps found, tiles of games no
-- longer installed (see showNotice)
local notice = { found = 0, update = nil, missing = 0 }
local showNotice      -- defined with OpenNotice
-- Filter bar under the menu, shown only with the search results: chips =
-- { { kind = 'all' | 'store' | 'tag', key, label }, ... }; the results shown
-- must have one of the selected stores (if any) and all the selected tags.
-- ver changes at every change (the filtered view is rebuilt).
local filter = { chips = {}, stores = {}, tags = {}, n = 0, ver = 0, hovered = 0 }

local function matchesFilter(t)
	if filter.n == 0 then return true end
	if next(filter.stores) and not (t.store and filter.stores[t.store]) then return false end
	for tag in pairs(filter.tags) do
		if not (t.tagSet and t.tagSet[tag]) then return false end
	end
	return true
end

-- Category shown in the grid: the search results (only those that pass the
-- filter) or the active one. The filtered view reads everything else from
-- the results themselves.
local function cur()
	local c = searchCat or cats[active]
	if filter.n == 0 or not searchCat then return c end
	if c._fview and c._fver == filter.ver and c._ftiles == c.tiles then return c._fview end
	local list = {}
	for _, t in ipairs(c.tiles) do
		if matchesFilter(t) then list[#list + 1] = t end
	end
	c._fview = setmetatable({ tiles = list }, { __index = c })
	c._fver, c._ftiles = filter.ver, c.tiles
	return c._fview
end
local resources
-- Folder with your data (Settings.inc, Categories\, Images\, State.inc):
-- #SETTINGSPATH#Raintile\, which installing an update never touches. Until
-- Data.ps1 has prepared it, the skin's own files (resources) are used.
local data

-- Diagnostic messages in the Rainmeter log (DebugLog=1 in Settings.inc).
local function dbg(msg)
	if V.DebugLog then print('Raintile: ' .. msg) end
end

local function trim(s)
	return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Colour as "R,G,B,A" from R,G,B, R,G,B,A or hex RRGGBB / RRGGBBAA (with or
-- without # or 0x in front); nil if it is not a colour.
local function parseColor(s)
	s = trim(s or '')
	local r, g, b, a = s:match('^(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%d*)$')
	if r then
		return string.format('%d,%d,%d,%d', tonumber(r), tonumber(g), tonumber(b), tonumber(a) or 255)
	end
	local hex = s:gsub('^#', ''):gsub('^0[xX]', '')
	if hex:match('^%x+$') and (#hex == 6 or #hex == 8) then
		local c = {}
		for i = 1, #hex, 2 do c[#c + 1] = tonumber(hex:sub(i, i + 1), 16) end
		return string.format('%d,%d,%d,%d', c[1], c[2], c[3], c[4] or 255)
	end
	return nil
end

local function unquote(s)
	return (s:gsub('^"(.*)"$', '%1'))
end

-- Number from a text; formulas like (Floor(#ScreenW#/4)) are accepted too.
local function toNumber(raw)
	raw = trim(SKIN:ReplaceVariables(raw or ''))
	local n = tonumber(raw)
	if not n and raw ~= '' then
		if raw:sub(1, 1) ~= '(' then raw = '(' .. raw .. ')' end
		n = tonumber(SKIN:ParseFormula(raw))
	end
	return n
end

-- Sizes that can also be written as a percentage of the screen (e.g. 3%):
-- 'W' = of the width, 'H' = of the height.
local SIZE_AXIS = {
	PadX = 'W', SearchW = 'W', MenuItemPad = 'W', MenuGap = 'W', MenuIconGap = 'W',
	PadY = 'H', Gap = 'H', MenuH = 'H', MenuIconSize = 'H', MenuRadius = 'H', IconSize = 'H',
	LabelPad = 'H', ScrollBarSize = 'H', LaunchLogoSize = 'H',
	FilterH = 'H', FilterGap = 'W', FilterPad = 'W',
}

-- Pixels of a size: a number, a formula or a percentage of the screen.
local function size(raw, axis)
	local pct = trim(raw or ''):match('^([%d%.]+)%s*%%$')
	if pct then
		local total = axis == 'W' and V.ScreenW or V.ScreenH
		return math.floor((toNumber(pct) or 0) * total / 100 + 0.5)
	end
	return toNumber(raw)
end

-- Reads a numeric variable (SIZE_AXIS sizes may also be percentages).
local function num(name, default)
	local raw = SKIN:GetVariable(name, '')
	local n
	if SIZE_AXIS[name] and V.ScreenW then n = size(raw, SIZE_AXIS[name]) else n = toNumber(raw) end
	return n or default
end

local function fileExists(path)
	local f = io.open(path, 'r')
	if f then f:close() return true end
	return false
end

-- Minimal INI parser that keeps the section order. Reads UTF-8 and, in a
-- simplified way (ASCII characters only), UTF-16 LE like Rainmeter.ini.
local function parseIni(path)
	local f = io.open(path, 'rb')
	if not f then return nil end
	local text = f:read('*a')
	f:close()
	if text:sub(1, 2) == '\255\254' then
		text = text:sub(3):gsub('%z', '') -- Lua 5.1: NUL in patterns is %z
	end
	text = text:gsub('^\239\187\191', '')

	local list, cur = {}, nil
	for line in text:gmatch('[^\r\n]+') do
		line = trim(line)
		if line ~= '' and line:sub(1, 1) ~= ';' then
			local section = line:match('^%[(.-)%]$')
			if section then
				cur = { name = trim(section), keys = {} }
				list[#list + 1] = cur
			elseif cur then
				local k, v = line:match('^([^=]-)%s*=%s*(.*)$')
				if k then cur.keys[trim(k):lower()] = v end
			end
		end
	end
	return list
end

-- The open/close fade duration is a per-skin setting in Rainmeter.ini, not an
-- option of the skin's .ini file: it is synced with FadeDuration from
-- Settings.inc. It applies from the next load.
local function applyFadeDuration()
	local want = tostring(math.max(0, math.floor(num('FadeDuration', 0))))
	local path = SKIN:ReplaceVariables('#SETTINGSPATH#') .. 'Rainmeter.ini'
	local config = SKIN:ReplaceVariables('#CURRENTCONFIG#'):lower()
	local current
	for _, s in ipairs(parseIni(path) or {}) do
		if s.name:lower() == config then current = s.keys.fadeduration end
	end
	if current and trim(current) == want then return end
	SKIN:Bang('!WriteKeyValue', SKIN:ReplaceVariables('#CURRENTCONFIG#'), 'FadeDuration', want, path)
end

local IMAGE_EXTS = { '.png', '.jpg', '.jpeg', '.bmp', '.ico', '.gif' }

local function isAbsolute(path)
	return path:match('^%a:[\\/]') ~= nil or path:match('^\\\\') ~= nil
end

-- Looks for 'name' in 'dir' (or as an absolute path). If the name has no
-- extension, the IMAGE_EXTS extensions are tried.
local function lookupImage(dir, name)
	local path = unquote(trim(SKIN:ReplaceVariables(name)))
	if not isAbsolute(path) then path = dir .. path end
	if path:match('%.%w+$') then
		return fileExists(path) and path or nil
	end
	for _, ext in ipairs(IMAGE_EXTS) do
		if fileExists(path .. ext) then return path .. ext end
	end
	return nil
end

-- Image of a tile/category: 'value' if given (logged if missing), otherwise
-- the default name, which may simply not exist.
local function findImage(value, dir, defaultName, owner)
	value = value and trim(value) or ''
	if value == '' then return lookupImage(dir, defaultName) end
	local path = lookupImage(dir, value)
	if not path then
		print('Raintile: image "' .. value .. '" not found in ' .. dir .. ' for [' .. owner .. ']')
	end
	return path
end

local function fileSize(path)
	local f = io.open(path, 'rb')
	if not f then return nil end
	local size = f:seek('end')
	f:close()
	return size
end

-- Pixel size of a PNG, JPEG, BMP or GIF image, read from its header (nil if
-- the format is not recognised).
local function imageSize(path)
	local f = io.open(path, 'rb')
	if not f then return nil end
	local head = f:read(32) or ''
	local function b(i) return head:byte(i) or 0 end
	local w, h
	if head:sub(1, 8) == '\137PNG\r\n\26\n' then
		w = ((b(17) * 256 + b(18)) * 256 + b(19)) * 256 + b(20)
		h = ((b(21) * 256 + b(22)) * 256 + b(23)) * 256 + b(24)
	elseif head:sub(1, 2) == 'BM' then
		w = b(19) + b(20) * 256 + b(21) * 65536 + b(22) * 16777216
		h = b(23) + b(24) * 256 + b(25) * 65536 + b(26) * 16777216
		if h >= 2147483648 then h = 4294967296 - h end -- top-down bitmap
	elseif head:sub(1, 3) == 'GIF' then
		w, h = b(7) + b(8) * 256, b(9) + b(10) * 256
	elseif head:sub(1, 2) == '\255\216' then
		-- JPEG: walk the segments up to the SOF marker holding the size
		f:seek('set', 2)
		while true do
			local marker = f:read(2)
			if not marker or #marker < 2 or marker:byte(1) ~= 255 then break end
			local m = marker:byte(2)
			if m ~= 216 and m ~= 1 and not (m >= 208 and m <= 215) then
				local len = f:read(2)
				if not len or #len < 2 then break end
				len = len:byte(1) * 256 + len:byte(2)
				if m >= 192 and m <= 207 and m ~= 196 and m ~= 200 and m ~= 204 then
					local d = f:read(5) or ''
					if #d == 5 then
						h = d:byte(2) * 256 + d:byte(3)
						w = d:byte(4) * 256 + d:byte(5)
					end
					break
				end
				f:seek('cur', len - 2)
			end
		end
	end
	f:close()
	if w and h and w > 0 and h > 0 then return { w, h } end
	return nil
end

-- Thumbnails -----------------------------------------------------------------
-- Rainmeter decodes images at full resolution and rescales them on every draw.
-- That is why backgrounds and logos are converted (in the background, by
-- Thumbs.ps1) into thumbnails of the exact size they are shown at, in
-- Generated\Thumbs\. The thumbnail name holds the source file size and the
-- target size: if either changes, it is rebuilt.

local thumbJobs = {}  -- every wanted thumbnail, "src|dst|w|h|mode"
local pending = {}    -- thumbnails still to create: { tile, field, dst }

local function safeName(s)
	return (s:gsub('[\\/:%*%?"<>|]', '_'))
end

-- Returns the image to show: the thumbnail if it already exists, otherwise
-- the original (and the thumbnail is queued). rect (optional, framed
-- backgrounds): the part of src to use, {x, y, w, h}.
local function thumbnail(src, tile, field, dir, name, w, h, mode, rect)
	if not src or not V.Thumbnails then return src end
	local ext = src:lower():match('%.png$') and '.png' or '.jpg'
	local tag = (mode == 'cover' or mode == 'contain') and '' or ('_' .. mode)
	if rect then tag = tag .. '_f' .. table.concat(rect, '-') end
	local dst = string.format('%sGenerated\\Thumbs\\%s\\%s_%d_%dx%d%s%s',
		resources, dir, safeName(name), fileSize(src) or 0, w, h, tag, ext)
	local job = table.concat({ src, dst, w, h, mode }, '|')
	if rect then job = job .. '|' .. table.concat(rect, ',') end
	thumbJobs[#thumbJobs + 1] = job
	if fileExists(dst) then return dst end
	pending[#pending + 1] = { tile = tile, field = field, dst = dst }
	return src
end

-- Framing of a background (tile keys): BgFocus=X,Y is the point of the image,
-- in % of its width and height, kept at the centre of the tile; BgZoom (1-4)
-- enlarges the image beyond filling the tile. Both are relative, so the
-- framing holds at any resolution and grid. Returns the part of the original
-- the tile works with, {x, y, w, h} in pixels: the window the tile shows,
-- plus BgOverscan of room around it where the image allows (sliding
-- backgrounds); .px, .py = where the window sits in that part at rest (0-1,
-- as in bgWindow). nil if the tile is not framed or the size is unknown.
local function frameRect(path, focus, zoom, tw, th)
	if not path then return nil end
	local fx, fy = trim(focus or ''):match('^([%d%.]+)%s*,%s*([%d%.]+)$')
	fx, fy, zoom = tonumber(fx) or 50, tonumber(fy) or 50, tonumber(trim(zoom or '')) or 1
	if fx == 50 and fy == 50 and zoom <= 1 then return nil end
	local d = imageSize(path)
	if not d then return nil end
	local iw, ih = d[1], d[2]
	fx, fy = math.min(100, math.max(0, fx)) / 100, math.min(100, math.max(0, fy)) / 100
	local scale = math.max(tw / iw, th / ih) * math.min(4, math.max(1, zoom))
	local over = V.BgStyle == 'crop' and 1 or V.BgOverscan
	-- start of a span of length n centred on c, kept inside 0..total
	local function place(c, n, total) return math.min(total - n, math.max(0, c - n / 2)) end
	local w = math.max(1, math.min(iw, math.floor(tw / scale * over + 0.5)))
	local h = math.max(1, math.min(ih, math.floor(th / scale * over + 0.5)))
	local x = math.floor(place(fx * iw, w, iw) + 0.5)
	local y = math.floor(place(fy * ih, h, ih) + 0.5)
	local r = { x, y, w, h, px = 0.5, py = 0.5 }
	-- the window at rest stays where the framing put it, also near an edge
	local ww, wh = math.min(w, tw / scale), math.min(h, th / scale)
	if w - ww >= 1 then r.px = (place(fx * iw, ww, iw) - x) / (w - ww) end
	if h - wh >= 1 then r.py = (place(fy * ih, wh, ih) - y) / (h - wh) end
	r.px, r.py = math.min(1, math.max(0, r.px)), math.min(1, math.max(0, r.py))
	return r
end

-- Placement of a logo (tile keys), independent of the background framing:
-- LogoPos=X,Y is where the centre of the logo goes, in % of the tile's width
-- and height; LogoScale (0.25-3) multiplies the category's logo size. Both are
-- relative, so they hold at any resolution and grid. Sets t.logoX, t.logoY
-- (0-1), t.logoScale and, for a moved logo, t.logoRatio (width / height of
-- the image, to keep what is visible of it inside the tile).
local function logoPlacement(t, pos, scale)
	local x, y = trim(pos or ''):match('^([%d%.]+)%s*,%s*([%d%.]+)$')
	t.logoX = math.min(100, math.max(0, tonumber(x) or 50)) / 100
	t.logoY = math.min(100, math.max(0, tonumber(y) or 50)) / 100
	t.logoScale = math.min(3, math.max(0.25, tonumber(trim(scale or '')) or 1))
	if t.logo and (t.logoX ~= 0.5 or t.logoY ~= 0.5) then
		local d = imageSize(t.logo)
		if d then t.logoRatio = d[1] / d[2] end
	end
end

-- Centre of tile t's logo in the tile, in pixels, for a logo box of the
-- given size. The box is square and the image fits inside it, so the
-- visible part is what has to stay in the tile: the slots are clipped by the
-- grid, not by the tile, and the logo would spill onto the next one. A
-- centred logo stays centred, also when larger than the tile.
local function logoCentre(t, size)
	local vw, vh = size, size
	if t.logoRatio then
		if t.logoRatio >= 1 then vh = size / t.logoRatio else vw = size * t.logoRatio end
	end
	local function place(p, n, total)
		if n >= total then return total / 2 end
		return math.min(total - n / 2, math.max(n / 2, p * total))
	end
	return place(t.logoX, vw, V.TileW), place(t.logoY, vh, V.TileH)
end

-- Automatic tile colour (AutoTileColor=1): a tile without a background image
-- and without Color= gets a dark colour taken from its logo. Thumbs.ps1
-- computes it in the background and keeps the results in
-- Generated\Colors.txt, one "size|R,G,B,A|logo path" line per logo (the size
-- of the logo file: if it changes, the colour is computed again).
local logoColors = {} -- "size|logo path" -> colour

local function readLogoColors()
	logoColors = {}
	local f = io.open(resources .. 'Generated\\Colors.txt', 'r')
	if not f then return end
	for line in f:lines() do
		local sz, color, src = line:gsub('\r$', ''):match('^(%d+)|([^|]*)|(.+)$')
		if sz then logoColors[sz .. '|' .. src:lower()] = color end
	end
	f:close()
end

-- Colour of tile t from its logo: the cached one, otherwise the tile keeps
-- the default colour until Thumbs.ps1 has computed it.
local function autoColor(t, logo)
	local sz = fileSize(logo) or 0
	local key = sz .. '|' .. logo
	thumbJobs[#thumbJobs + 1] = table.concat({ logo, sz, 0, 0, 'color' }, '|')
	local color = logoColors[key:lower()]
	if color then
		if color ~= '' then t.color = color end
		return
	end
	pending[#pending + 1] = { tile = t, field = 'color', key = key:lower() }
end

-- Grid of a category: NX x NY visible tiles (Settings.inc by default), sized
-- to fill the grid area.
local function categoryGeometry(c, nx, ny, iconSize)
	c.nx = math.max(1, math.floor(nx or V.DefNX))
	c.ny = math.max(1, math.floor(ny or V.DefNY))
	c.tw = math.floor((V.AreaW - (c.nx - 1) * V.Gap) / c.nx)
	c.th = math.floor((V.AreaH - (c.ny - 1) * V.Gap) / c.ny)
	-- one extra row (or column) of slots for smooth scrolling
	c.rows = c.ny + (V.Horizontal and 0 or 1)
	c.cols = c.nx + (V.Horizontal and 1 or 0)
	c.iconSize = math.floor(iconSize or V.DefIconSize)
end

-- Makes category c's grid the "current" one: the rest of the script uses
-- V.NX, V.TileW, ... of the active category.
local function applyGeometry(c)
	V.NX, V.NY, V.TileW, V.TileH = c.nx, c.ny, c.tw, c.th
	V.StepX, V.StepY = c.tw + V.Gap, c.th + V.Gap
	V.Rows, V.Cols = c.rows, c.cols
	V.Slots = c.rows * c.cols -- slots in use (the others stay hidden)
	V.GridW = c.nx * c.tw + (c.nx - 1) * V.Gap
	V.GridH = c.ny * c.th + (c.ny - 1) * V.Gap
	V.IconSize = c.iconSize
end

-- Store of a tile, for the filter bar, and its Steam app id (for the play
-- time): from Store= or Source= (written when added from Import, e.g.
-- Steam:570) or from the command. nil for programs and apps.
local STORE_NAMES = {
	steam = 'Steam', epic = 'Epic Games', gog = 'GOG', ubisoft = 'Ubisoft', ['battle.net'] = 'Battle.net',
	battlenet = 'Battle.net', ea = 'EA', xbox = 'Xbox',
}
local function tileStore(command, store, source)
	local low = command:lower()
	local steamId = low:match('^steam://rungameid/(%d+)') or low:match('^steam://run/(%d+)')
		or low:match('^steam://launch/(%d+)')
	if steamId and #steamId > 10 then steamId = nil end -- non-Steam shortcuts
	local src, srcId = source:match('^([^:]+):(.*)$')
	if src and src:lower() == 'steam' and srcId:match('^%d+$') then steamId = steamId or srcId end
	local name = STORE_NAMES[store:lower()] or (store ~= '' and store) or (src and STORE_NAMES[src:lower()])
	if not name then
		if low:find('^steam://') then name = 'Steam'
		elseif low:find('^com%.epicgames%.launcher://') then name = 'Epic Games'
		elseif low:find('galaxyclient%.exe') or low:find('^goggalaxy://') then name = 'GOG'
		elseif low:find('^uplay://') or low:find('^ubisoft://') then name = 'Ubisoft'
		elseif low:find('battle%.net') or low:find('^battlenet://') then name = 'Battle.net'
		elseif low:find('^origin2?://') or low:find('^link2ea://') or low:find('^ea://') then name = 'EA'
		end
	end
	return name, steamId
end

-- Reads a category file (Categories\<file>.ini).
local function loadCategory(file)
	local ini = parseIni(data .. 'Categories\\' .. file)
	if not ini then return nil end

	local base = file:gsub('%.[iI][nN][iI]$', '')
	local images = data .. 'Images\\' .. base .. '\\'
	local c = { file = file, name = base, label = base, order = math.huge, tiles = {} }

	-- [Category] first: the category grid is already needed for the thumbnails
	local catKeys = {}
	for _, s in ipairs(ini) do
		if s.name:lower() == 'category' then catKeys = s.keys end
	end
	local catLabel = trim(catKeys.name or '')
	if catLabel ~= '' then c.label = catLabel end
	c.order = tonumber(catKeys.order or '') or math.huge
	local iconValue = catKeys.icon
	categoryGeometry(c, tonumber(catKeys.nx or ''), tonumber(catKeys.ny or ''),
		size(catKeys.iconsize, 'H'))

	for _, s in ipairs(ini) do
		local k = s.keys
		if s.name:lower() ~= 'category' then
			local label = trim(k.label or '')
			local command = trim(SKIN:ReplaceVariables(k.command or ''))
			-- Default image name: Image= or the tile name
			local image = trim(k.image or '') ~= '' and trim(k.image) or s.name
			local color = parseColor(k.color)
			if not color and trim(k.color or '') ~= '' then
				print('Raintile: colour "' .. k.color .. '" of [' .. s.name .. '] not recognised (R,G,B,A or #RRGGBBAA)')
			end
			local t = {
				background = findImage(k.background, images .. 'background\\', image, s.name),
				logo = findImage(k.logo, images .. 'logo\\', image, s.name),
				color = color or V.TileColor,
				command = command ~= '' and command or nil,
			}
			if V.AutoTileColor and not color and t.logo and not t.background then
				autoColor(t, t.logo)
			end
			-- originals, used full screen by the launch animation
			t.backgroundFull, t.logoFull = t.background, t.logo
			t.frame = frameRect(t.background, k.bgfocus, k.bgzoom, c.tw, c.th)
			t.background = thumbnail(t.background, t, 'background', base .. '\\background', s.name,
				c.tw, c.th, V.BgThumbMode, t.frame)
			logoPlacement(t, k.logopos, k.logoscale)
			-- logo thumbnails are made at the largest size (zoom included)
			local logoMax = math.floor(c.iconSize * t.logoScale * V.HoverLogoScale + 0.5)
			t.logo = thumbnail(t.logo, t, 'logo', base .. '\\logo', s.name,
				logoMax, logoMax, 'contain')
			if label ~= '' then
				t.label = label
			elseif not t.background and not t.logo then
				t.label = s.name -- tile without images: show at least its name
			end
			t.name, t.catLabel = s.name, c.label -- for search
			t.file = file -- for "Edit this tile"
			t.store, t.steamId = tileStore(command, trim(k.store or ''), trim(k.source or ''))
			t.tags, t.tagSet = {}, {}
			for tag in (k.tags or ''):gmatch('[^,;]+') do
				tag = trim(tag)
				if tag ~= '' and not t.tagSet[tag:lower()] then
					t.tags[#t.tags + 1] = tag
					t.tagSet[tag:lower()] = true
				end
			end
			c.tiles[#c.tiles + 1] = t
		end
	end

	c.icon = findImage(iconValue, images, 'icon', base)
	if not c.icon and V.MenuMode ~= 'text' and trim(iconValue or '') == '' then
		print('Raintile: no icon for category "' .. base .. '": looked for ' .. images
			.. 'icon' .. '(' .. table.concat(IMAGE_EXTS, '|') .. ')')
	end
	return c
end

-- Favorites and Recent ---------------------------------------------------------
-- Two categories made of the tiles of the others, first in the menu. Their
-- data, in the data folder, one tile per line ("<file>|<tile name>"):
-- Favorites.txt (in the order they were added) and Usage.txt (with the number
-- of launches and the time of the last one: "<file>|<name>|<count>|<time>").

local favorites = { list = {}, set = {} }
local usage = {}        -- id -> { count, last }
local virtualDirty = false

local function tileId(t)
	return (t.file or '') .. '|' .. t.name
end

local function readLines(path)
	local lines = {}
	local f = io.open(path, 'r')
	if not f then return lines end
	for line in f:lines() do
		line = line:gsub('\r$', '')
		if line ~= '' then lines[#lines + 1] = line end
	end
	f:close()
	return lines
end

local function writeLines(path, lines)
	local f = io.open(path, 'wb')
	if not f then return end
	f:write(table.concat(lines, '\r\n'), #lines > 0 and '\r\n' or '')
	f:close()
end

local function readFavorites()
	favorites = { list = {}, set = {} }
	for _, id in ipairs(readLines(data .. 'Favorites.txt')) do
		if not favorites.set[id] then
			favorites.set[id] = true
			favorites.list[#favorites.list + 1] = id
		end
	end
end

local function readUsage()
	usage = {}
	for _, line in ipairs(readLines(data .. 'Usage.txt')) do
		local id, count, last = line:match('^(.*)|(%d+)|(%d+)$')
		if id then usage[id] = { count = tonumber(count), last = tonumber(last) } end
	end
end

local function writeUsage()
	local lines = {}
	for id, u in pairs(usage) do lines[#lines + 1] = id .. '|' .. u.count .. '|' .. u.last end
	table.sort(lines)
	writeLines(data .. 'Usage.txt', lines)
end

-- Tiles of games no longer installed -------------------------------------------
-- Scan.ps1 lists them in Generated\Missing.txt ("<file>|<tile name>", the
-- kept ones left out): they are greyed out, do not start (a click opens
-- Options > Import, where they can be removed or kept) and light the dot.
local function readMissing()
	local set, n = {}, 0
	for _, id in ipairs(readLines(resources .. 'Generated\\Missing.txt')) do set[id:lower()] = true end
	for _, c in ipairs(cats) do
		if not c.virtual then
			for _, t in ipairs(c.tiles) do
				t.missing = set[tileId(t):lower()] or nil
				if t.missing then n = n + 1 end
			end
		end
	end
	notice.missing = n
end

-- Play time ------------------------------------------------------------------------
-- Steam keeps the play time and the last launch of each game: Playtime.ps1
-- copies them, in the background, to Generated\Playtime.txt
-- ("<appid>|<minutes>|<last played, unix time>"). For the other tiles the
-- last launch is the one counted by Raintile (Usage.txt).
local playtime = {}   -- steam app id -> { minutes, last }

local function readPlaytime()
	playtime = {}
	for _, line in ipairs(readLines(resources .. 'Generated\\Playtime.txt')) do
		local id, minutes, last = line:match('^(%d+)|(%d+)|(%d+)$')
		if id then playtime[id] = { minutes = tonumber(minutes), last = tonumber(last) } end
	end
end

local function ago(time)
	local today = os.date('*t')
	today.hour, today.min, today.sec = 0, 0, 0
	local midnight = os.time(today)
	if time >= midnight then return 'today' end
	local days = math.floor((midnight - time) / 86400) + 1
	if days == 1 then return 'yesterday' end
	if days < 30 then return days .. ' days ago' end
	return os.date('%d %b %Y', time)
end

-- Line shown on the tile (TileInfo): play time and last launch
local function tileInfo(t)
	if t.missing then return 'Not installed' end
	local p = t.steamId and playtime[t.steamId]
	local u = usage[tileId(t)]
	local last = math.max(p and p.last or 0, u and u.last or 0)
	local played
	if p and p.minutes > 0 then
		if p.minutes < 60 then played = p.minutes .. ' min'
		elseif p.minutes < 600 then played = string.format('%.1f h', p.minutes / 60):gsub('%.0 h$', ' h')
		else played = math.floor(p.minutes / 60 + 0.5) .. ' h' end
	end
	if played and last > 0 then return played .. ' played - ' .. ago(last) end
	if played then return played .. ' played' end
	if last > 0 then return 'Last played ' .. ago(last) end
	return nil
end

local function makeVirtual(kind)
	local c = {
		virtual = kind, file = '', name = '_' .. kind, order = -1, tiles = {},
		label = kind == 'favorites' and 'Favorites' or 'Recent',
	}
	local icon = resources .. 'Icons\\' .. kind .. '.png'
	if fileExists(icon) then c.icon = icon end
	categoryGeometry(c)
	return c
end

-- Tiles of Favorites and Recent, from the tiles of the other categories
local function fillVirtual()
	local byId, all = {}, {}
	for _, c in ipairs(cats) do
		if not c.virtual then
			for _, t in ipairs(c.tiles) do
				byId[tileId(t)] = t
				all[#all + 1] = t
			end
		end
	end
	for _, c in ipairs(cats) do
		if c.virtual == 'favorites' then
			c.tiles = {}
			for _, id in ipairs(favorites.list) do
				if byId[id] then c.tiles[#c.tiles + 1] = byId[id] end
			end
		elseif c.virtual == 'recent' then
			local list = {}
			for _, t in ipairs(all) do
				local u = usage[tileId(t)]
				if u then list[#list + 1] = { t = t, u = u } end
			end
			table.sort(list, function(a, b)
				if V.RecentMostUsed and a.u.count ~= b.u.count then return a.u.count > b.u.count end
				if a.u.last ~= b.u.last then return a.u.last > b.u.last end
				return a.t.name:lower() < b.t.name:lower()
			end)
			c.tiles = {}
			for i = 1, math.min(#list, V.RecentCount) do c.tiles[i] = list[i].t end
		end
	end
	virtualDirty = false
end

local function loadCategories(files)
	cats = {}
	thumbJobs, pending = {}, {}
	readLogoColors()
	for _, file in ipairs(files) do
		local c = loadCategory(file)
		if c then cats[#cats + 1] = c end
	end
	table.sort(cats, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name:lower() < b.name:lower()
	end)
	if #cats == 0 then
		cats[1] = { file = '', name = 'Empty', label = 'No categories', order = 0, tiles = {} }
		categoryGeometry(cats[1])
	else
		local virtual = {}
		if V.ShowFavorites then virtual[#virtual + 1] = makeVirtual('favorites') end
		if V.ShowRecent then virtual[#virtual + 1] = makeVirtual('recent') end
		for i = #virtual, 1, -1 do table.insert(cats, 1, virtual[i]) end
		readFavorites()
		readUsage()
		fillVirtual()
		readMissing()
		readPlaytime()
	end
	-- Filter bar: stores (when there are at least two) and tags of the tiles
	filter.chips = {}
	if V.FilterBar then
		local stores, tags, storeList, tagList = {}, {}, {}, {}
		for _, c in ipairs(cats) do
			for _, t in ipairs(c.virtual and {} or c.tiles) do
				if t.store and not stores[t.store] then
					stores[t.store] = true
					storeList[#storeList + 1] = t.store
				end
				for _, tag in ipairs(t.tags or {}) do
					if not tags[tag:lower()] then
						tags[tag:lower()] = tag
						tagList[#tagList + 1] = tag:lower()
					end
				end
			end
		end
		table.sort(storeList)
		table.sort(tagList)
		if V.FilterStores and #storeList >= 2 then
			for _, st in ipairs(storeList) do filter.chips[#filter.chips + 1] = { kind = 'store', key = st, label = st } end
		end
		for _, tag in ipairs(tagList) do filter.chips[#filter.chips + 1] = { kind = 'tag', key = tag, label = '#' .. tags[tag] } end
		if #filter.chips > 0 then table.insert(filter.chips, 1, { kind = 'all', label = 'All' }) end
	end
	-- the stored selection is dropped: the chips may have changed
	filter.stores, filter.tags, filter.n = {}, {}, 0
	filter.ver = filter.ver + 1
	-- Slots to generate: as many as the largest grid needs
	slots = 0
	for _, c in ipairs(cats) do slots = math.max(slots, c.rows * c.cols) end
	local default = {} -- default grid, used by search results
	categoryGeometry(default)
	slots = math.max(slots, default.rows * default.cols)

	-- Meters making up each menu entry, according to MenuMode. Favorites and
	-- Recent are not in the menu: they are the buttons next to the search bar.
	for i, c in ipairs(cats) do
		c.showIcon = not c.virtual and V.MenuMode ~= 'text' and c.icon ~= nil
		c.showText = not c.virtual and (V.MenuMode ~= 'icon' or c.icon == nil)
		c.parts = {}
		if c.showIcon then c.parts[#c.parts + 1] = 'CatIcon' .. i end
		if c.showText then c.parts[#c.parts + 1] = 'CatText' .. i end
	end
end

local function splitList(s)
	local list = {}
	for item in (s or ''):gmatch('[^|\r\n]+') do
		item = trim(item)
		if item ~= '' then list[#list + 1] = item end
	end
	return list
end

-- Grid.inc generation ------------------------------------------------------

-- Bump when the format of the meters written by writeGrid() changes.
local GRID_VERSION = 7

-- Space taken by the filter bar while the search results are shown: the grid
-- moves down by as much
local function filterSpace()
	return #filter.chips > 0 and math.floor(V.FilterH + V.Gap) or 0
end

local function signature()
	local s = { 'v' .. GRID_VERSION, slots, V.MenuMode }
	for _, chip in ipairs(filter.chips) do s[#s + 1] = 'chip:' .. chip.label end
	for _, c in ipairs(cats) do
		s[#s + 1] = c.name .. ':' .. c.label .. ':' .. (c.icon or '')
	end
	return table.concat(s, '|')
end

local function writeGrid(path, sig, files)
	local o = {}
	local function w(s) o[#o + 1] = s end

	w('; GENERATED BY Raintile.lua: do not edit by hand.')
	w('[Variables]')
	w('GridSignature=' .. sig)
	-- Category files seen last time: lets the skin draw right away on load,
	-- while the folder is checked again in the background.
	w('CategoryFiles=' .. table.concat(files, '|'))
	w('')

	-- Menu entries: a chain of meters with relative X. After measuring them the
	-- script only moves the first one to centre the whole chain.
	local firstEntry = true
	for i, c in ipairs(cats) do
		local x = firstEntry and '#PadX#' or '(#MenuGap#+2*#MenuItemPad#)R'
		if not c.virtual then firstEntry = false end
		if c.showIcon then
			w('[CatIcon' .. i .. ']')
			w('Meter=Image')
			w('MeterStyle=StyleCategoryIcon')
			w('ImageName=' .. c.icon)
			w('X=' .. x)
			w('Y=(#PadY#+(#MenuH#-#MenuIconSize#)/2)')
			w('')
			x = '#MenuIconGap#R'
		end
		if c.showText then
			w('[CatText' .. i .. ']')
			w('Meter=String')
			w('MeterStyle=StyleCategory')
			w('X=' .. x)
			w('Y=(#PadY#+#MenuH#/2)')
			w('Text=' .. c.label)
			w('')
		end
	end

	-- Filter bar: the pills first (drawn below), then the texts, a chain like
	-- the menu, centred by the script
	for i = 1, #filter.chips do
		w('[FilterPill' .. i .. ']')
		w('Meter=Shape')
		w('MeterStyle=StyleFilterPill')
		w('')
	end
	for i, chip in ipairs(filter.chips) do
		w('[FilterText' .. i .. ']')
		w('Meter=String')
		w('MeterStyle=StyleFilter')
		w('X=' .. (i == 1 and '#PadX#' or '#FilterGap#R'))
		w('Text=' .. chip.label)
		w('LeftMouseUpAction=[!CommandMeasure MeasureScript "ToggleFilter(' .. i .. ')"]')
		w('MouseOverAction=[!CommandMeasure MeasureScript "HoverFilter(' .. i .. ')"]')
		w('MouseLeaveAction=[!CommandMeasure MeasureScript "HoverFilter(0)"]')
		w('')
	end

	-- Clickable areas of the entries (placed by the script)
	for i = 1, #cats do
		if not cats[i].virtual then
			w('[CatHit' .. i .. ']')
			w('Meter=Shape')
			w('MeterStyle=StyleCategoryHit')
			w('LeftMouseUpAction=[!CommandMeasure MeasureScript "SetCategory(' .. i .. ')"]')
			w('MouseOverAction=[!CommandMeasure MeasureScript "HoverCategory(' .. i .. ')"]')
			w('MouseLeaveAction=[!CommandMeasure MeasureScript "HoverCategory(0)"]')
			w('')
		end
	end

	-- Grid slots, inside the GridClip container: as many as the category with
	-- the largest grid needs. The script sets each slot's position and size
	-- according to the active category's grid.
	for slot = 1, slots do
		w('[Tile' .. slot .. ']')
		w('Meter=Image')
		w('MeterStyle=StyleTile')
		w('LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(' .. slot .. ')"]')
		w('MouseOverAction=[!CommandMeasure MeasureScript "HoverTile(' .. slot .. ')"]')
		w('MouseLeaveAction=[!CommandMeasure MeasureScript "LeaveTile(' .. slot .. ')"]')
		w('')
		w('[TileIcon' .. slot .. ']')
		w('Meter=Image')
		w('MeterStyle=StyleTileIcon')
		w('')
		w('[TileLabel' .. slot .. ']')
		w('Meter=String')
		w('MeterStyle=StyleTileLabel')
		w('')
		w('[TileInfo' .. slot .. ']')
		w('Meter=String')
		w('MeterStyle=StyleTileInfo')
		w('')
	end

	local f = io.open(path, 'w')
	if not f then return false end
	f:write(table.concat(o, '\n'))
	f:close()
	return true
end

-- Rendering -----------------------------------------------------------------

local function set(meter, option, value)
	local key = meter .. '|' .. option
	if cache[key] ~= value then
		cache[key] = value
		dirty[meter] = true
		SKIN:Bang('!SetOption', meter, option, value)
	end
end


local function show(meter, visible)
	local key = meter .. '|Hidden'
	if cache[key] ~= visible then
		cache[key] = visible
		SKIN:Bang(visible and '!ShowMeter' or '!HideMeter', meter)
	end
end

-- Text in the middle of an empty grid: no search results, no favorites yet,
-- nothing launched yet
local function updateEmptyHint()
	local c, text = cur(), nil
	if searchCat then
		if #c.tiles == 0 then
			text = (filter.n > 0 and #searchCat.tiles > 0) and 'No results with this filter: click All to see them all'
				or 'No results'
		end
	elseif c and #c.tiles == 0 then
		if c.virtual == 'favorites' then text = 'No favorites yet: right click a tile > Add to Favorites'
		elseif c.virtual == 'recent' then text = 'Nothing launched yet' end
	end
	if text then set('SearchEmpty', 'Text', text) end
	show('SearchEmpty', text ~= nil)
end


local function rect(meter, x, y, w, h, color)
	set(meter, 'X', tostring(x))
	set(meter, 'Y', tostring(y))
	set(meter, 'Shape', string.format('Rectangle 0,0,%d,%d,%d | Fill Color %s | StrokeWidth 0',
		w, h, math.min(V.MenuRadius, math.floor(h / 2)), color))
end

-- "R,G,B,A" colour with the opacity multiplied by f (0-1).
local function fade(color, f)
	local r, g, b, a = color:match('(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%d*)')
	if not r then return color end
	a = tonumber(a) or 255
	return string.format('%s,%s,%s,%d', r, g, b, math.floor(a * f + 0.5))
end

local function easeOut(p)
	return 1 - (1 - p) ^ 3
end

local function easeInOut(p)
	if p < 0.5 then return 4 * p ^ 3 end
	return 1 - (-2 * p + 2) ^ 3 / 2
end

-- "Window" backgrounds (BgStyle other than Crop): the image stays larger than
-- the tile (BgOverscan) and the tile shows part of it with ImageCrop, moving
-- it (Pan, Parallax) or shrinking it (Zoom). A framed tile still showing its
-- original (thumbnail not made yet, or Thumbnails=0) works on the framed part
-- only, as its thumbnail would; with Crop that part is shown as it is.
-- x, y = tile position in the grid. Returns "x,y,w,h" or nil.
local function bgWindow(t, x, y)
	if t.bgSize == nil then t.bgSize = imageSize(t.background) or false end
	local d = t.bgSize
	if not d then return nil end
	local ox, oy, iw, ih = 0, 0, d[1], d[2]
	if t.frame and t.background == t.backgroundFull then
		ox, oy, iw, ih = t.frame[1], t.frame[2], t.frame[3], t.frame[4]
	end
	local scale = math.max(V.TileW / iw, V.TileH / ih) * (V.BgStyle == 'crop' and 1 or V.BgOverscan)
	if V.BgStyle == 'zoom' then
		scale = scale * (1 + (V.BgHoverZoom - 1) * (t.zoom or 0))
	end
	local cw, ch = V.TileW / scale, V.TileH / scale
	-- at rest: centred, or where the framing put it
	local px, py = 0.5, 0.5
	if t.frame then px, py = t.frame.px, t.frame.py end
	if V.BgStyle == 'pan' then
		-- from the rest position towards the end with more room, along the
		-- axis with more room
		local e = easeInOut(t.pan or 0)
		if (iw - cw) / iw >= (ih - ch) / ih then
			px = px + ((px <= 0.5 and 1 or 0) - px) * e
		else
			py = py + ((py <= 0.5 and 1 or 0) - py) * e
		end
	elseif V.BgStyle == 'parallax' then
		-- the visible part depends on where the tile is in the grid
		if V.Horizontal then
			px = math.min(1, math.max(0, (x + V.TileW / 2) / V.GridW))
		else
			py = math.min(1, math.max(0, (y + V.TileH / 2) / V.GridH))
		end
	end
	return string.format('%d,%d,%d,%d', ox + math.floor((iw - cw) * px + 0.5), oy + math.floor((ih - ch) * py + 0.5),
		math.floor(cw + 0.5), math.floor(ch + 0.5))
end

-- Number >= 0 with 3 decimals and a dot separator, whatever the system
-- language (string.format('%.3f') could use a comma).
local function dec(v)
	local n = math.floor(v * 1000 + 0.5)
	return string.format('%d.%03d', math.floor(n / 1000), n % 1000)
end

-- Colour matrix (ColorMatrix rows 1-3) with saturation sat: 0 = greyscale
-- (luminance), 1 = original colours.
local LUMA = { 0.299, 0.587, 0.114 }
local function saturationRows(sat)
	local rows = {}
	for i = 1, 3 do
		local k = LUMA[i] * (1 - sat)
		local v = { k, k, k }
		v[i] = k + sat
		rows[i] = dec(v[1]) .. ';' .. dec(v[2]) .. ';' .. dec(v[3]) .. ';0;0'
	end
	return rows
end

-- Moves cur towards target by a fraction per step (k, default AnimSmooth);
-- returns the new value and true if it has not arrived yet.
local function approach(cur, target, eps, k)
	if math.abs(target - cur) <= eps then return target, false end
	return cur + (target - cur) * (k or V.AnimSmooth), true
end

-- Rows (V) or columns (H) of tiles of the active category, and how many fit
-- on screen.
local function lineCount()
	return math.ceil(#cur().tiles / (V.Horizontal and V.NY or V.NX))
end

local function visibleLines()
	return V.Horizontal and V.NX or V.NY
end

local function maxOffset()
	return math.max(0, lineCount() - visibleLines())
end

-- Infinite scroll: after the last row the first one comes back. Only if the
-- tiles don't all fit on screen (otherwise they would show up twice).
local function infinite()
	return V.InfiniteScroll and lineCount() > visibleLines()
end

-- Brings a saved scroll position within the active category's limits.
local function normalizeOffset(o)
	o = math.floor(o or 0)
	if infinite() then return o % lineCount() end
	return math.min(math.max(0, o), maxOffset())
end

local function slotRC(slot)
	local s = slot - 1
	return math.floor(s / V.Cols), s % V.Cols
end

-- Remembers the active category's scroll position (in State.inc too, so it
-- survives a skin refresh).
local function saveScroll()
	if searchCat then return end -- search results are not remembered
	local c = cats[active]
	local o = normalizeOffset(offset)
	if c.offset ~= o then
		c.offset = o
		SKIN:Bang('!WriteKeyValue', 'Variables', 'Scroll_' .. c.name, tostring(o), data .. 'State.inc')
	end
end

-- Index (in cur().tiles) of the tile in the slot, with the current contents.
local function indexAt(slot)
	local r, c = slotRC(slot)
	local line = base + (V.Horizontal and c or r)
	if infinite() then line = line % lineCount() end
	if V.Horizontal then return line * V.NY + r + 1 end
	return line * V.NX + c + 1
end

local function tileAt(slot)
	return cur().tiles[indexAt(slot)]
end

-- Pixel position (relative to the grid) of a point in grid units (column,
-- row), at the current scroll position.
local function gridToPx(gx, gy)
	if V.Horizontal then gx = gx - pos else gy = gy - pos end
	return gx * V.StepX, gy * V.StepY
end

-- Grid coordinates (column, row) of the slot with the current contents; with
-- infinite scroll the row (or column) is not wrapped back.
local function slotToGrid(slot)
	local r, c = slotRC(slot)
	if V.Horizontal then return base + c, r end
	return c, base + r
end

-- Measures the (already updated) menu entries and centres the chain horizontally.
local function layoutMenu()
	local first, last
	for _, c in ipairs(cats) do
		c.l, c.r = nil, nil
		for _, name in ipairs(c.parts) do
			local m = SKIN:GetMeter(name)
			local x, w = m:GetX(), m:GetW()
			c.l = c.l and math.min(c.l, x) or x
			c.r = c.r and math.max(c.r, x + w) or x + w
		end
		if c.l then
			first = first or c
			last = c
		end
	end
	if not first then return end

	local origin = first.l
	local total = last.r - origin
	if total <= 0 then return end

	local start = math.floor((V.ScreenW - total) / 2)
	local shift = start - origin
	set(first.parts[1], 'X', tostring(start))
	for i, c in ipairs(cats) do
		if c.l then
			c.l, c.r = c.l + shift, c.r + shift
			rect('CatHit' .. i, c.l - V.MenuItemPad, V.PadY,
				c.r - c.l + 2 * V.MenuItemPad, V.MenuH, '0,0,0,1')
			show('CatHit' .. i, true)
		end
	end
	laidOut = true
end

-- Favorites and Recent buttons, right of the search bar: icon only, the label
-- shows below on hover. The active one is lit like a menu pill.
local side = { hovered = '' }

local function sideIndex(kind)
	for i, c in ipairs(cats) do
		if c.virtual == kind then return i end
	end
	return nil
end

local function renderSide()
	local size = math.floor(V.MenuH)
	local gap = math.max(8, math.floor(num('MenuGap', 6)))
	local x = math.floor(V.PadX + V.SearchW + gap)
	local iconSize = math.floor(num('MenuIconSize', 24))
	for _, kind in ipairs({ 'favorites', 'recent' }) do
		local name = kind == 'favorites' and 'Favorites' or 'Recent'
		local i = sideIndex(kind)
		if i then
			local on = not searchCat and i == active
			local hot = side.hovered == kind
			if on or hot then
				rect('SidePill' .. name, x, V.PadY, size, size, on and V.ActiveCategoryColor or V.HoverCategoryColor)
				show('SidePill' .. name, true)
			else
				show('SidePill' .. name, false)
			end
			set('SideIcon' .. name, 'X', tostring(x + math.floor((size - iconSize) / 2)))
			set('SideIcon' .. name, 'Y', tostring(math.floor(V.PadY + (size - iconSize) / 2)))
			set('SideIcon' .. name, 'ImageAlpha', (on or hot) and '255' or tostring(V.MenuIconDimAlpha))
			show('SideIcon' .. name, true)
			rect('SideHit' .. name, x, V.PadY, size, size, '0,0,0,1')
			show('SideHit' .. name, true)
			if hot then
				set('SideLabel', 'Text', cats[i].label)
				set('SideLabel', 'X', tostring(x + math.floor(size / 2)))
				set('SideLabel', 'Y', tostring(math.floor(V.PadY + size + 6)))
			end
			x = x + size + gap
		else
			show('SidePill' .. name, false)
			show('SideIcon' .. name, false)
			show('SideHit' .. name, false)
		end
	end
	show('SideLabel', side.hovered ~= '' and sideIndex(side.hovered) ~= nil)
end

local function pillTarget(i)
	local c = cats[i]
	return c.l - V.MenuItemPad, c.r - c.l + 2 * V.MenuItemPad
end

local function drawPill(meter, x, w, color)
	rect(meter, math.floor(x + 0.5), V.PadY, math.floor(w + 0.5), V.MenuH, color)
	show(meter, true)
end

local startTicker -- defined further down

local function renderCategories()
	renderSide()
	for i, c in ipairs(cats) do
		local on = i == active or i == hovered
		if c.showText then
			set('CatText' .. i, 'FontColor', on and V.TextColor or V.TextDimColor)
		end
		if c.showIcon then
			set('CatIcon' .. i, 'ImageAlpha', on and '255' or tostring(V.MenuIconDimAlpha))
		end
	end
	if not laidOut then
		show('CatPillActive', false)
		show('CatPillHover', false)
		return
	end

	-- Active pill: slides to the new entry (Tick) or jumps straight there.
	-- No category is active during a search; Favorites and Recent are lit on
	-- their own button (the pill appears again without sliding).
	local x, w
	if cats[active].l then x, w = pillTarget(active) end
	if not x then
		show('CatPillActive', false)
		pillPos = nil
	elseif searchCat then
		show('CatPillActive', false)
	elseif pillPos and V.AnimCategory and (pillPos.x ~= x or pillPos.w ~= w) then
		startTicker()
	else
		pillPos = { x = x, w = w }
		drawPill('CatPillActive', x, w, V.ActiveCategoryColor)
	end

	if hovered ~= 0 and hovered ~= active and cats[hovered] and cats[hovered].l then
		local hx, hw = pillTarget(hovered)
		drawPill('CatPillHover', hx, hw, V.HoverCategoryColor)
	else
		show('CatPillHover', false)
	end
end

-- Filter bar ---------------------------------------------------------------------
-- Only with the search results: the grid (GridClip) moves down to make room
-- for it, and goes back when the search ends.
local function setGridArea(withFilter)
	local fs = withFilter and filterSpace() or 0
	V.GridY = V.GridTop + fs
	set('GridClip', 'Y', tostring(math.floor(V.GridY)))
	set('GridClip', 'Shape', string.format('Rectangle 0,0,%d,%d | Fill Color 0,0,0,255 | StrokeWidth 0',
		math.floor(V.AreaW), math.floor(V.AreaH - fs)))
	for i = 1, #filter.chips do show('FilterText' .. i, withFilter) end
	if fs == 0 then
		for i = 1, #filter.chips do show('FilterPill' .. i, false) end
	end
	filter.shown = withFilter and #filter.chips > 0
end

-- Measures the chips (a chain of texts like the menu), centres them under the
-- menu and hides those that do not fit.
local function layoutFilters()
	local n = #filter.chips
	if n == 0 then return end
	local first, last = SKIN:GetMeter('FilterText1'), SKIN:GetMeter('FilterText' .. n)
	if not first or not last then return end
	local origin = first:GetX()
	local total = last:GetX() + last:GetW() - origin
	local start = math.max(V.PadX, math.floor((V.ScreenW - total) / 2))
	local shift = start - origin
	set('FilterText1', 'X', tostring(start))
	for i, chip in ipairs(filter.chips) do
		local m = SKIN:GetMeter('FilterText' .. i)
		chip.x, chip.w = m:GetX() + shift, m:GetW()
		chip.fits = chip.x + chip.w <= V.ScreenW - V.PadX
	end
end

local function chipOn(chip)
	if chip.kind == 'all' then return filter.n == 0 end
	if chip.kind == 'store' then return filter.stores[chip.key] == true end
	return filter.tags[chip.key] == true
end

local function renderFilters()
	if not filter.shown then return end
	if not filter.laidOut then
		SKIN:Bang('!UpdateMeterGroup', 'Menu')
		layoutFilters()
		filter.laidOut = true
	end
	local y = math.floor(V.PadY + V.MenuH + V.Gap)
	for i, chip in ipairs(filter.chips) do
		local on, hot = chipOn(chip), i == filter.hovered
		local visible = chip.x ~= nil and chip.fits ~= false
		set('FilterText' .. i, 'FontColor', (on or hot) and V.TextColor or V.TextDimColor)
		show('FilterText' .. i, chip.fits ~= false)
		if visible and (on or hot) then
			rect('FilterPill' .. i, math.floor(chip.x), y, math.floor(chip.w), math.floor(V.FilterH),
				on and V.ActiveCategoryColor or V.HoverCategoryColor)
			show('FilterPill' .. i, true)
		else
			show('FilterPill' .. i, false)
		end
	end
end

local function renderScrollBar()
	local maxOff = maxOffset()
	if maxOff == 0 then
		show('MeterScrollBar', false)
		return
	end

	local total = lineCount()
	-- fraction of the thumb travel (with infinite scroll: position within the loop)
	local at = infinite() and (pos % total) / maxOff or pos / maxOff
	at = math.min(1, math.max(0, at))
	local size = V.ScrollBarSize
	local x, y, w, h, tx, ty, tw, th
	if V.Horizontal then
		x = V.PadX
		y = V.GridY + V.GridH + math.floor((V.PadY - size) / 2)
		w, h = V.GridW, size
		tw, th = math.floor(w * V.NX / total), h
		tx, ty = math.floor((w - tw) * at), 0
	else
		x = V.PadX + V.GridW + math.floor((V.PadX - size) / 2)
		y = V.GridY
		w, h = size, V.GridH
		tw, th = w, math.floor(h * V.NY / total)
		tx, ty = 0, math.floor((h - th) * at)
	end

	local radius = math.floor(size / 2)
	set('MeterScrollBar', 'X', tostring(x))
	set('MeterScrollBar', 'Y', tostring(y))
	set('MeterScrollBar', 'Shape', string.format(
		'Rectangle 0,0,%d,%d,%d | Fill Color %s | StrokeWidth 0', w, h, radius, V.ScrollTrackColor))
	set('MeterScrollBar', 'Shape2', string.format(
		'Rectangle %d,%d,%d,%d,%d | Fill Color %s | StrokeWidth 0', tx, ty, tw, th, radius, V.ScrollThumbColor))
	show('MeterScrollBar', true)
end

-- Slot contents (images, texts) for the 'base' row/column.
local function fillSlots()
	for slot = 1, V.Slots do
		local t = tileAt(slot)
		if t then
			set('Tile' .. slot, 'ImageName', t.background or '')
			if t.logo then set('TileIcon' .. slot, 'ImageName', t.logo) end
			if t.label then set('TileLabel' .. slot, 'Text', t.label) end
		end
	end
end

-- Colour matrices (rows 1-3) of a normal image and of a greyed-out one
local IDENTITY_ROWS = { '1;0;0;0;0', '0;1;0;0;0', '0;0;1;0;0' }
local GREY_ROWS = { '0.3;0.3;0.3;0;0', '0.59;0.59;0.59;0;0', '0.11;0.11;0.11;0;0' }

-- Position, opacity and visibility of the slots (also on every animation step).
local function placeSlots()
	local frac = pos - base
	for slot = 1, slots do
		local inUse = slot <= V.Slots -- slots beyond the category grid: hidden
		local t = inUse and tileAt(slot)
		local r, c = slotRC(slot)
		local extra = r >= V.NY or c >= V.NX -- extra row/column
		local visible = t and (not extra or frac > 0)
		local tile, icon, label = 'Tile' .. slot, 'TileIcon' .. slot, 'TileLabel' .. slot
		local infoMeter = 'TileInfo' .. slot

		if visible then
			local x, y = c * V.StepX, r * V.StepY
			if V.Horizontal then x = x - frac * V.StepX else y = y - frac * V.StepY end

			local f = 1
			if appear then
				local p = (appear - (slot - 1) * V.AnimStagger) / V.AnimAppearFrames
				f = easeOut(math.min(1, math.max(0, p)))
				y = y + (1 - f) * V.AnimSlide
			end
			x, y = math.floor(x + 0.5), math.floor(y + 0.5)
			local alpha = tostring(math.floor(255 * f + 0.5))

			set(tile, 'X', tostring(x))
			set(tile, 'Y', tostring(y))
			set(tile, 'W', tostring(V.TileW))
			set(tile, 'H', tostring(V.TileH))
			-- a game no longer installed: greyed out and dimmed
			local dim = t.missing and 0.45 or 1
			set(tile, 'ImageAlpha', tostring(math.floor(255 * f * dim + 0.5)))
			set(tile, 'SolidColor', fade(t.color, f * dim))
			local tileRows = t.missing and GREY_ROWS or IDENTITY_ROWS
			set(tile, 'ColorMatrix1', tileRows[1])
			set(tile, 'ColorMatrix2', tileRows[2])
			set(tile, 'ColorMatrix3', tileRows[3])
			local framedOriginal = t.frame and t.background == t.backgroundFull
			local crop = (V.BgStyle ~= 'crop' or framedOriginal) and t.background and bgWindow(t, x, y)
			set(tile, 'PreserveAspectRatio', crop and '0' or '2')
			set(tile, 'ImageCrop', crop or '')
			if t.logo then
				local size = math.floor(V.IconSize * t.logoScale * (1 + (V.HoverLogoScale - 1) * (t.zoom or 0)) + 0.5)
				local lx, ly = logoCentre(t, size)
				set(icon, 'X', tostring(x + math.floor(lx - size / 2)))
				set(icon, 'Y', tostring(y + math.floor(ly - size / 2)))
				set(icon, 'W', tostring(size))
				set(icon, 'H', tostring(size))
				set(icon, 'ImageAlpha', tostring(math.floor(255 * f * dim + 0.5)))
				local rows = t.missing and GREY_ROWS or (V.LogoGreyscale and saturationRows(t.zoom or 0)) or IDENTITY_ROWS
				set(icon, 'ColorMatrix1', rows[1])
				set(icon, 'ColorMatrix2', rows[2])
				set(icon, 'ColorMatrix3', rows[3])
			end
			local hasLabel = V.ShowLabels and t.label ~= nil
			if hasLabel then
				set(label, 'W', tostring(V.TileW - 2 * V.LabelPad))
				set(label, 'X', tostring(x + V.LabelPad))
				set(label, 'Y', tostring(y + V.TileH - V.LabelPad))
				set(label, 'FontColor', fade(V.TextColor, f))
				set(label, 'FontEffectColor', fade('0,0,0,200', f))
			end
			-- play time / last launch: always, only on the highlighted tile
			-- (fading with the highlight) or never; "Not installed" always
			local infoText, infoAlpha = nil, f
			if t.missing or V.TileInfo ~= 'never' then infoText = tileInfo(t) end
			if infoText and not t.missing and V.TileInfo == 'hover' then
				local idx = indexAt(slot)
				if idx == hover.idx and (hover.on or hover.a > 0) then
					infoAlpha = f * (V.TileHover and hover.a or (hover.on and 1 or 0))
				else
					infoText = nil
				end
			end
			if infoText and infoAlpha > 0.01 then
				set(infoMeter, 'Text', infoText)
				set(infoMeter, 'X', tostring(x + V.LabelPad))
				set(infoMeter, 'Y', tostring(y + V.LabelPad))
				set(infoMeter, 'FontColor', fade(V.TextColor, infoAlpha))
				set(infoMeter, 'SolidColor', fade('0,0,0,150', infoAlpha))
			end
			show(tile, true)
			show(icon, t.logo ~= nil)
			show(label, hasLabel)
			show(infoMeter, infoText ~= nil and infoAlpha > 0.01)
		else
			show(tile, false)
			show(icon, false)
			show(label, false)
			show(infoMeter, false)
		end
	end
end

local function placeHover()
	if not V.TileHover or hover.a <= 0 or hover.idx == 0 then
		show('TileHover', false)
		return
	end
	local x, y = gridToPx(hover.gx, hover.gy)
	set('TileHover', 'X', tostring(math.floor(x + 0.5)))
	set('TileHover', 'Y', tostring(math.floor(y + 0.5)))
	set('TileHover', 'Shape', string.format(
		'Rectangle 1,1,%d,%d | Fill Color %s | StrokeWidth 2 | Stroke Color %s',
		V.TileW - 2, V.TileH - 2, fade(V.HoverColor, hover.a), fade(V.AccentColor, hover.a)))
	show('TileHover', true)
end

-- Applies the current state to the grid and redraws.
local function frame()
	local b = math.floor(pos)
	if b ~= base then
		base = b
		fillSlots()
	end
	placeSlots()
	placeHover()
	renderScrollBar()
	-- only changed meters are updated (e.g. a single one during Pan)
	for meter in pairs(dirty) do SKIN:Bang('!UpdateMeter', meter) end
	dirty = {}
	SKIN:Bang('!Redraw')
end

-- Redraws everything. 'menu' = update the menu too (category change).
local function render(menu)
	if menu then
		if not laidOut then
			-- Menu meters must be updated before they can be measured
			SKIN:Bang('!UpdateMeterGroup', 'Menu')
			layoutMenu()
		end
		renderCategories()
		renderFilters()
		SKIN:Bang('!UpdateMeterGroup', 'Menu')
	end
	frame()
end

-- Click on a chip: All clears the filter, the others turn on and off. The
-- grid starts again from the top, with the appear animation.
function ToggleFilter(i)
	local chip = filter.chips[i]
	if not ready or launching or not chip or not searchCat then return end
	if chip.kind == 'all' then
		filter.stores, filter.tags = {}, {}
	elseif chip.kind == 'store' then
		filter.stores[chip.key] = (not filter.stores[chip.key]) or nil
	else
		filter.tags[chip.key] = (not filter.tags[chip.key]) or nil
	end
	local n = 0
	for _ in pairs(filter.stores) do n = n + 1 end
	for _ in pairs(filter.tags) do n = n + 1 end
	filter.n, filter.ver = n, filter.ver + 1
	offset, pos, base = 0, 0, -1
	hover.idx, hover.on, hover.a = 0, false, 0
	for t in pairs(zooming) do t.zoom, t.pan = 0, 0 end
	zooming = {}
	updateEmptyHint()
	if V.AnimCategory then appear = 0 startTicker() end
	render(true)
end

function HoverFilter(i)
	if not ready or filter.hovered == i then return end
	filter.hovered = i
	renderFilters()
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	SKIN:Bang('!Redraw')
end

-- Animations ---------------------------------------------------------------------
-- A single "clock" advances every animation and stops by itself when nothing
-- moves any more. Each step schedules the next one (16 ms later) only after it
-- has finished drawing: a slow step slows the animation down, but steps never
-- queue up and mouse and keyboard stay responsive. MeasureAnim's two lists
-- alternate, because a list cannot be restarted while it is still running its
-- last action.
local tickList = 1

startTicker = function()
	if ticking then return end
	ticking = true
	tickList = 1
	SKIN:Bang('!CommandMeasure', 'MeasureAnim', 'Execute 1')
end

local function stopTicker()
	if not ticking then return end
	ticking = false
	SKIN:Bang('!CommandMeasure', 'MeasureAnim', 'Stop 1')
	SKIN:Bang('!CommandMeasure', 'MeasureAnim', 'Stop 2')
end

-- Advances every animation by one step; true if something is still moving.
local function advance()
	local busy, moving = false, false

	pos, moving = approach(pos, offset, 0.002, V.AnimScrollSmooth)
	busy = busy or moving

	if appear then
		appear = appear + 1
		if appear >= (V.Slots - 1) * V.AnimStagger + V.AnimAppearFrames then appear = nil end
		busy = busy or appear ~= nil
	end

	if hover.idx ~= 0 then
		hover.gx, moving = approach(hover.gx, hover.tx, 0.002, V.AnimHoverSmooth)
		busy = busy or moving
		hover.gy, moving = approach(hover.gy, hover.ty, 0.002, V.AnimHoverSmooth)
		busy = busy or moving
		hover.a, moving = approach(hover.a, hover.on and 1 or 0, 0.02, V.AnimHoverSmooth)
		busy = busy or moving
	end

	-- Logo zoom: grows on the tile under the mouse, shrinks back on the others
	local tiles = cur().tiles
	for t in pairs(zooming) do
		local target = (hover.on and tiles[hover.idx] == t) and 1 or 0
		t.zoom, moving = approach(t.zoom or 0, target, 0.01, V.AnimLogoSmooth)
		busy = busy or moving
		if V.BgStyle == 'pan' then
			-- constant speed: slow on the way out, three times faster on the way back
			local p = t.pan or 0
			local step = target == 1 and 1 / V.BgPanFrames or 3 / V.BgPanFrames
			p = target == 1 and math.min(1, p + step) or math.max(0, p - step)
			t.pan = p
			busy = busy or p ~= target
		end
		if t.zoom == 0 and (t.pan or 0) == 0 and target == 0 then zooming[t] = nil end
	end

	if pillPos and laidOut and not searchCat and cats[active].l then
		local x, w = pillTarget(active)
		pillPos.x, moving = approach(pillPos.x, x, 0.5, V.AnimPillSmooth)
		busy = busy or moving
		pillPos.w, moving = approach(pillPos.w, w, 0.5, V.AnimPillSmooth)
		busy = busy or moving
		drawPill('CatPillActive', pillPos.x, pillPos.w, V.ActiveCategoryColor)
		SKIN:Bang('!UpdateMeter', 'CatPillActive')
	end

	return busy
end

function Tick(list)
	-- steps arriving after the stop, or from a list no longer current
	if not ticking or (list and list ~= tickList) then return end
	if not ready or launching then
		stopTicker()
		return
	end
	local busy = advance()
	frame()
	if busy then
		tickList = 3 - tickList
		SKIN:Bang('!CommandMeasure', 'MeasureAnim', 'Execute ' .. tickList)
	else
		ticking = false
	end
end

-- Rainmeter lifecycle --------------------------------------------------------

local knownFiles = {}

-- Percentage sizes, converted to pixels, also go to the skin (which uses
-- #PadX#, #MenuH#, ... in formulas and does not understand "3%"), and so do
-- colours written as #RRGGBBAA (Rainmeter reads hex colours only without #):
-- Generated\Sizes.inc is included after Settings.inc and takes precedence. It
-- is only rewritten (and the skin refreshed) when something changes: a
-- percentage or the screen resolution.
local function writeSizes()
	local values = {}
	for _, s in ipairs(parseIni(data .. 'Settings.inc') or {}) do
		for key, value in pairs(s.keys) do values[key] = value end -- lower-case keys
	end
	local names = {}
	for name in pairs(SIZE_AXIS) do names[#names + 1] = name end
	table.sort(names)
	local lines = {
		'; GENERATED BY Raintile.lua: percentage sizes and #hex colours from',
		'; Settings.inc converted for Rainmeter. Do not edit by hand.',
		'[Variables]',
	}
	for _, name in ipairs(names) do
		local raw = values[name:lower()]
		if raw and raw:match('%%%s*$') then
			lines[#lines + 1] = name .. '=' .. size(raw, SIZE_AXIS[name])
		end
	end
	local colors = {}
	for key, raw in pairs(values) do
		if key:match('color$') and trim(raw):match('^#') and parseColor(raw) then colors[#colors + 1] = key end
	end
	table.sort(colors)
	for _, key in ipairs(colors) do lines[#lines + 1] = key .. '=' .. parseColor(values[key]) end
	local text = table.concat(lines, '\n') .. '\n'

	local path = resources .. 'Generated\\Sizes.inc'
	local f = io.open(path, 'rb')
	local old = f and f:read('*a') or ''
	if f then f:close() end
	if old == text then return false end
	f = io.open(path, 'wb')
	if not f then
		print('Raintile: cannot write Generated\\Sizes.inc')
		return false
	end
	f:write(text)
	f:close()
	SKIN:Bang('!Refresh')
	return true
end

-- Grid area in pixels for the framing editor of the Options window, which
-- cannot work out the layout by itself: "width,height,gap" in
-- Generated\Area.txt, rewritten only when it changes.
local function writeArea()
	local text = string.format('%d,%d,%d\n', math.floor(V.AreaW), math.floor(V.AreaH), math.floor(V.Gap))
	local path = resources .. 'Generated\\Area.txt'
	local f = io.open(path, 'rb')
	local old = f and f:read('*a') or ''
	if f then f:close() end
	if old == text then return end
	f = io.open(path, 'wb')
	if not f then return end
	f:write(text)
	f:close()
end

-- Rewrites Grid.inc and refreshes the skin if menu, grid or files changed.
local function regenerate(files)
	local sig = signature()
	if SKIN:GetVariable('GridSignature', '') == sig
			and table.concat(files, '|') == SKIN:GetVariable('CategoryFiles', '') then
		return false
	end
	if writeGrid(resources .. 'Generated\\Grid.inc', sig, files) then
		SKIN:Bang('!Refresh')
	else
		print('Raintile: cannot write Generated\\Grid.inc')
	end
	return true
end

-- True if the skin's Settings.inc has keys that yours does not (an update
-- added settings): Data.ps1 adds them.
local function settingsOutdated(userFile)
	local have = {}
	for _, s in ipairs(parseIni(userFile) or {}) do
		for key in pairs(s.keys) do have[key] = true end
	end
	for _, s in ipairs(parseIni(resources .. 'Settings.inc') or {}) do
		for key in pairs(s.keys) do
			if not have[key] then return true end
		end
	end
	return false
end

function Initialize()
	resources = SKIN:ReplaceVariables('#@#')
	local userData = SKIN:ReplaceVariables('#SETTINGSPATH#') .. 'Raintile\\'
	data = fileExists(userData .. 'Settings.inc') and userData or resources
	V.NeedsSetup = data ~= userData or settingsOutdated(userData .. 'Settings.inc')
	-- the background listing of the category files looks in the data folder
	SKIN:Bang('!SetOption', 'MeasureCategoryList', 'Parameter', '/c dir /b /a-d "' .. data .. 'Categories\\*.ini"')
	SKIN:Bang('!UpdateMeasure', 'MeasureCategoryList')
	laidOut, pillPos = false, nil

	-- default grid; each category can have its own (NX/NY in [Category])
	V.DefNX = math.max(1, math.floor(num('NX', 4)))
	V.DefNY = math.max(1, math.floor(num('NY', 2)))
	V.Horizontal = SKIN:GetVariable('ScrollDir', 'V'):upper():sub(1, 1) == 'H'
	V.ScrollStep = math.max(1, math.floor(num('ScrollStep', 1)))
	V.ScreenW = num('ScreenW', 1920)
	V.ScreenH = num('ScreenH', 1080) -- before the sizes: percentages need it
	V.Gap = num('Gap', 16)
	V.PadX = num('PadX', 40)
	V.PadY = num('PadY', 24)
	V.MenuH = num('MenuH', 44)
	V.MenuItemPad = num('MenuItemPad', 16)
	V.MenuRadius = num('MenuRadius', 22)
	V.MenuIconDimAlpha = math.floor(num('MenuIconDimAlpha', 150))
	V.ScrollBarSize = num('ScrollBarSize', 4)
	V.ShowLabels = num('ShowLabels', 1) ~= 0
	V.DefIconSize = math.floor(num('IconSize', 96))
	V.Thumbnails = num('Thumbnails', 1) ~= 0
	V.TileHover = num('TileHover', 1) ~= 0
	V.LaunchAnimation = num('LaunchAnimation', 1) ~= 0
	V.LaunchAnimFrames = math.max(0, math.floor(num('LaunchAnimFrames', 15)))
	V.LaunchLogoSize = math.floor(num('LaunchLogoSize', 400))
	V.CloseOnLaunch = num('CloseOnLaunch', 1) ~= 0
	V.CloseAction = SKIN:GetVariable('CloseAction', '[!CommandMeasure MeasureScript "Hide()"]')
	V.StartHidden = num('StartHidden', 0) ~= 0
	V.ShowZPos = SKIN:GetVariable('ShowZPos', '')
	V.HotKey = trim(SKIN:GetVariable('CloseHotKey', ''))
	-- The close key mini-skin: only active while the launcher is visible
	V.HotKeyConfig = SKIN:ReplaceVariables('#ROOTCONFIG#') .. '\\Hotkey'
	V.KeyboardNav = num('KeyboardNav', 1) ~= 0
	V.DebugLog = num('DebugLog', 0) ~= 0
	V.ScanOnStart = num('ScanOnStart', 1) ~= 0
	V.ShowFavorites = num('ShowFavorites', 1) ~= 0
	V.ShowRecent = num('ShowRecent', 1) ~= 0
	V.RecentMostUsed = SKIN:GetVariable('RecentOrder', 'Recent'):lower() == 'mostused'
	V.RecentCount = math.max(1, math.floor(num('RecentCount', 12)))
	V.CheckUpdates = num('CheckUpdates', 1) ~= 0
	V.SearchW = math.floor(num('SearchW', 320))
	V.SearchPlaceholder = SKIN:GetVariable('SearchPlaceholder', 'Search')
	V.NavConfig = SKIN:ReplaceVariables('#ROOTCONFIG#') .. '\\Navigation'
	V.TypingConfig = SKIN:ReplaceVariables('#ROOTCONFIG#') .. '\\Typing'
	V.FilterBar = num('FilterBar', 1) ~= 0
	V.FilterStores = num('FilterStores', 1) ~= 0
	V.FilterH = num('FilterH', 30)
	local info = SKIN:GetVariable('TileInfo', 'Hover'):lower()
	V.TileInfo = (info == 'always' or info == 'never') and info or 'hover'
	V.GridY = V.PadY + V.MenuH + V.Gap
	V.GridTop = V.GridY -- without the filter bar (see setGridArea)
	V.LabelPad = num('LabelPad', 14)
	V.AnimOpen = num('AnimOpen', 1) ~= 0
	V.AnimCategory = num('AnimCategory', 1) ~= 0
	V.AnimHover = num('AnimHover', 1) ~= 0
	V.AnimScroll = num('AnimScroll', 1) ~= 0
	V.AnimAppearFrames = math.max(1, math.floor(num('AnimAppearFrames', 12)))
	V.AnimStagger = math.max(0, num('AnimStagger', 2))
	V.AnimSlide = num('AnimSlide', 30)
	V.AnimSmooth = math.min(1, math.max(0.05, num('AnimSmooth', 0.3)))
	V.InfiniteScroll = num('InfiniteScroll', 1) ~= 0
	-- Smoothing of each animation; AnimSmooth if empty
	local function smooth(name)
		return math.min(1, math.max(0.02, num(name, V.AnimSmooth)))
	end
	V.AnimScrollSmooth = smooth('AnimScrollSmooth')
	V.AnimHoverSmooth = smooth('AnimHoverSmooth')
	V.AnimPillSmooth = smooth('AnimPillSmooth')
	V.AnimLogoSmooth = smooth('AnimLogoSmooth')
	V.AnimLogoZoom = num('AnimLogoZoom', 1) ~= 0
	V.LogoGreyscale = num('LogoGreyscale', 1) ~= 0
	local bg = SKIN:GetVariable('BgStyle', 'Crop'):lower()
	V.BgStyle = (bg == 'pan' or bg == 'parallax' or bg == 'zoom') and bg or 'crop'
	V.BgOverscan = math.max(1, num('BgOverscan', 1.15))
	V.BgPanFrames = math.max(1, math.floor(num('BgPanFrames', 180)))
	V.BgHoverZoom = math.max(1, num('BgHoverZoom', 1.08))
	-- background thumbnails: cropped to the tile (Crop) or larger, with room to
	-- slide/zoom (percentage in the mode name)
	if V.BgStyle == 'crop' then
		V.BgThumbMode = 'cover'
	else
		local over = V.BgOverscan * (V.BgStyle == 'zoom' and V.BgHoverZoom or 1)
		V.BgThumbMode = 'overscan' .. math.floor(over * 100 + 0.5)
	end
	V.HoverLogoScale = V.AnimLogoZoom and math.max(1, num('HoverLogoScale', 1.25)) or 1
	-- area available for the grid (each category's tiles fill it)
	V.AreaW = V.ScreenW - 2 * V.PadX
	V.AreaH = V.ScreenH - 2 * V.PadY - V.MenuH - V.Gap
	writeArea()
	for _, name in ipairs({ 'TileColor', 'ActiveCategoryColor', 'HoverCategoryColor', 'TextColor',
			'TextDimColor', 'ScrollTrackColor', 'ScrollThumbColor', 'HoverColor', 'AccentColor' }) do
		V[name] = parseColor(SKIN:GetVariable(name, '')) or '255,255,255,255'
	end
	V.AutoTileColor = num('AutoTileColor', 1) ~= 0
	local mode = SKIN:GetVariable('MenuMode', 'IconText'):lower()
	V.MenuMode = (mode == 'icon' or mode == 'text') and mode or 'icontext'

	-- Starts from the stored file list; OnCategoryList() checks it again.
	knownFiles = {}
	for _, file in ipairs(splitList(SKIN:GetVariable('CategoryFiles', ''))) do
		if fileExists(data .. 'Categories\\' .. file) then knownFiles[#knownFiles + 1] = file end
	end
	if #knownFiles == 0 then return end -- first run: wait for the list

	applyFadeDuration()
	if writeSizes() then return end

	loadCategories(knownFiles)
	if regenerate(knownFiles) then return end

	active = math.min(math.max(1, math.floor(num('LastCategory', 1))), #cats)
	applyGeometry(cats[active])
	-- saved scroll position of each category
	for _, c in ipairs(cats) do
		c.offset = math.floor(num('Scroll_' .. c.name, 0))
	end
	offset = normalizeOffset(cats[active].offset)
	pos = offset
	ready = true
end

-- Turns on or off the mini-skin that registers the close key (Esc). When it
-- is off the key is free again for other applications.
local function hotKey(on)
	if V.HotKey ~= '' then
		if on then
			SKIN:Bang('!ActivateConfig', V.HotKeyConfig, 'Hotkey.ini')
		else
			SKIN:Bang('!DeactivateConfig', V.HotKeyConfig)
		end
	end
	-- navigation keys (WASD, arrows, Space/Enter, Q/E): same logic
	if V.KeyboardNav then
		if on then
			SKIN:Bang('!ActivateConfig', V.NavConfig, 'Navigation.ini')
		else
			SKIN:Bang('!DeactivateConfig', V.NavConfig)
		end
	end
end

function Update()
	-- With UpdateDivider=-1 this is only called once, on load.
	if ready then
		-- left by the Options window ("Save and refresh"): show the launcher
		-- once loaded, also if it was hidden before the refresh
		local flag = resources .. 'Generated\\ShowOnLoad'
		local showNow = fileExists(flag)
		if showNow then os.remove(flag) end
		local startHidden = V.StartHidden and not showNow
		if V.AnimOpen and not startHidden then appear = 0 end
		updateEmptyHint()
		render(true)
		if notice.missing > 0 then showNotice() end
		if showNow then
			if V.ShowZPos ~= '' then SKIN:Bang('!ZPos', V.ShowZPos) end
			SKIN:Bang('!Show')
		end
		if startHidden then
			visible = false
			SKIN:Bang('!Hide')
			hotKey(false)
		else
			hotKey(true)
			if appear then startTicker() end
		end
	end
	return active
end

-- Show/hide ------------------------------------------------------------------
-- The launcher loads only once and then stays in memory: opening and closing
-- it shows and hides it, without re-reading files or recomputing anything.
-- From the command line or a shortcut:
--   Rainmeter.exe !CommandMeasure MeasureScript "Toggle()" "Raintile"

local function hideSplash()
	show('SplashBg', false)
	show('SplashLogo', false)
	show('SplashLabel', false)
end

function Show()
	dbg('Show: visible=' .. tostring(visible))
	if not ready then return end
	if visible then
		-- a refresh while hidden (e.g. saving in the Options window) leaves
		-- the window hidden although the script starts as visible: show it
		if V.ShowZPos ~= '' then SKIN:Bang('!ZPos', V.ShowZPos) end
		SKIN:Bang('!Show')
		return
	end
	visible = true
	-- start clean: no hover, zoom or launch left over from last time
	launching = nil
	typing = false
	hideSplash()
	hover.on, hover.a = false, 0
	for t in pairs(zooming) do t.zoom, t.pan = 0, 0 end
	zooming = {}
	if virtualDirty then
		fillVirtual()
		if cats[active].virtual then
			applyGeometry(cats[active])
			offset = normalizeOffset(offset)
			pos, base = offset, -1
			hover.idx = 0
		end
	end
	updateEmptyHint()
	if V.AnimOpen then appear = 0 end
	frame() -- first frame drawn before showing the window
	if V.ShowZPos ~= '' then SKIN:Bang('!ZPos', V.ShowZPos) end
	SKIN:Bang('!Show')
	hotKey(true)
	if appear then startTicker() end
	ReadPlaytime(60)
end

function Hide()
	dbg('Hide: visible=' .. tostring(visible) .. ' launching=' .. tostring(launching ~= nil))
	if not ready or not visible then return end
	visible = false
	stopTyping()
	stopTicker()
	leaveSearch() -- next time it opens on the category
	pos = offset -- a half-done scroll restarts already finished
	saveScroll()
	if launching then
		SKIN:Bang('!CommandMeasure', 'MeasureLaunchAnim', 'Stop 1')
		launching = nil
	end
	SKIN:Bang('!Hide')
	hotKey(false)
end

function Toggle()
	if visible then Hide() else Show() end
end

local function close()
	-- the default action calls this same script's Hide(): call it directly
	-- instead of going through Rainmeter
	if V.CloseAction:match('MeasureScript%s+"Hide%(%)"') then
		Hide()
	else
		SKIN:Bang(V.CloseAction)
	end
end

-- Functions called with !CommandMeasure -------------------------------------

-- Receives the list of files in Categories\ (from the RunCommand plugin).
function OnCategoryList()
	local files = {}
	local output = SKIN:GetMeasure('MeasureCategoryList'):GetStringValue()
	for line in output:gmatch('[^\r\n]+') do
		line = trim(line)
		if line:lower():match('%.ini$') then files[#files + 1] = line end
	end
	table.sort(files, function(a, b) return a:lower() < b:lower() end)
	if table.concat(files, '|') ~= table.concat(knownFiles, '|') then
		knownFiles = files
		loadCategories(files)
		regenerate(files)
	end
end

-- Prepares the data folder when needed (first run, settings added by an
-- update): Data.ps1, then a refresh to use it. Called by OnRefreshAction.
function Setup()
	if V.NeedsSetup then SKIN:Bang('!CommandMeasure', 'MeasureSetup', 'Run') end
end

function OnSetup()
	local output = SKIN:GetMeasure('MeasureSetup'):GetStringValue()
	local ok = false
	for line in output:gmatch('[^\r\n]+') do
		if line == 'RESULT:OK' then ok = true
		elseif not line:match('^RESULT:') then print('Raintile: ' .. line) end
	end
	-- the skin reloads with the data folder; on errors it keeps its own files
	if ok then SKIN:Bang('!Refresh') end
end

-- Background search of the installed games and apps on every load
-- (ScanOnStart=1). Nothing is added: new ones light the dot on the gear, and
-- are added from the Options window.
function AutoScan()
	if not ready or not V.ScanOnStart then return end
	SKIN:Bang('!CommandMeasure', 'MeasureScan', 'Run')
end

-- Dot on the gear: an update, new games or apps found, or tiles of games no
-- longer installed. A click opens the Options window where they are (Info or
-- Import).
showNotice = function()
	local tip
	if notice.update then
		tip = 'Raintile ' .. notice.update .. ' is available: click for details'
	elseif notice.found > 0 then
		tip = 'New games or apps found: click to add them'
	elseif notice.missing > 0 then
		tip = notice.missing == 1 and '1 game is no longer installed: click to remove or keep its tile'
			or (notice.missing .. ' games are no longer installed: click to remove or keep their tiles')
	end
	if tip then SKIN:Bang('!SetOption', 'MeterNotice', 'ToolTipText', tip) end
	show('MeterNotice', tip ~= nil)
	SKIN:Bang('!UpdateMeter', 'MeterNotice')
	SKIN:Bang('!Redraw')
end

function OpenNotice()
	SKIN:Bang(SKIN:GetVariable(notice.update and 'OptionsInfoAction' or 'OptionsImportAction'))
end

-- Context menu > Edit this tile: the Options window opens on the tile the
-- menu was opened on. Any right-click action on a meter (press or release)
-- would replace Rainmeter's menu, so the tile is the one under the mouse:
-- set by HoverTile, cleared by LeaveTile. Opening the menu also takes the
-- mouse off the tile, but then it leaves the whole skin too (MouseInSkin(0)),
-- before or right after LeaveTile: in that case the tile is kept. The tile
-- reaches Options through Generated\EditTile.txt ("file|name"), not the
-- command line: a tile name can hold any character.
-- Rainmeter reads the menu entries each time it opens the menu (before the
-- mouse leaves), and cannot grey one out: the entry is the last one and,
-- without a tile, gets an empty action, which hides it (the list of entries
-- ends there). With a tile it shows its name.
local pointed = nil  -- tile under the mouse
local left = nil     -- tile just left: { t, at = os.time() }
local inSkin = true

-- Program (and its arguments) a command starts: "C:\x\app.exe" -a, app.exe,
-- C:\x\Game.lnk. nil for URLs, bangs and empty commands.
local function commandTarget(cmd)
	cmd = trim(cmd or '')
	if cmd == '' or cmd:sub(1, 1) == '[' or cmd:find('://', 1, true) then return nil end
	local path, args = cmd:match('^"([^"]+)"%s*(.*)$')
	if not path then path, args = cmd:match('^(%S+)%s*(.*)$') end
	return path, args or ''
end

-- Programs that can be run as administrator: exe, shortcuts, scripts (not
-- Store apps, which go through explorer.exe "shell:AppsFolder\...")
local function isProgram(path, args)
	local ext = (path or ''):lower():match('%.(%w+)$')
	if ext ~= 'exe' and ext ~= 'lnk' and ext ~= 'bat' and ext ~= 'cmd' and ext ~= 'com' then return false end
	return not (args or ''):lower():find('shell:', 1, true)
end

-- Context menu entries for tile t, in the order shown (Rainmeter stops at the
-- first empty one, so only those that apply are listed)
local TILE_MENU_SLOTS = 5
local function setPointed(t)
	if pointed == t then return end
	pointed = t
	local items = {}
	if t then
		-- & would underline the next letter in a menu
		items[#items + 1] = { 'Edit ' .. t.name:gsub('&', '&&') .. '...', 'edit' }
		if V.ShowFavorites and t.file and t.file ~= '' then
			items[#items + 1] = { favorites.set[tileId(t)] and 'Remove from Favorites' or 'Add to Favorites', 'favorite' }
		end
		local path, args = commandTarget(t.command)
		if path and path:match('^%a:[\\/]') and fileExists(path) then items[#items + 1] = { 'Open file location', 'folder' } end
		if path and isProgram(path, args) then items[#items + 1] = { 'Run as administrator', 'admin' } end
		if t.file and t.file ~= '' then
			items[#items + 1] = { 'Remove from ' .. (t.catLabel or ''):gsub('&', '&&') .. '...', 'remove' }
		end
	end
	for i = 1, TILE_MENU_SLOTS do
		local it = items[i]
		SKIN:Bang('!SetVariable', 'TileMenuTitle' .. i, it and it[1] or '')
		SKIN:Bang('!SetVariable', 'TileMenuAction' .. i, it and ('[!CommandMeasure MeasureScript "TileMenu(\'' .. it[2] .. '\')"]') or '')
	end
end

local function leavePointed(t)
	if not t or pointed ~= t then return end
	if inSkin then
		left = { t = t, at = os.time() }
		setPointed(nil)
	end
end

function MouseInSkin(on)
	inSkin = on == 1
	-- left the skin in the same moment as a tile: the menu opening on it
	if not inSkin and not pointed and left and os.time() - left.at <= 1 then setPointed(left.t) end
	left = nil
end

-- Favorites: add or remove; the category shows the change at once
local function toggleFavorite(t)
	local id = tileId(t)
	if favorites.set[id] then
		favorites.set[id] = nil
		for i, v in ipairs(favorites.list) do
			if v == id then table.remove(favorites.list, i) break end
		end
	else
		favorites.set[id] = true
		favorites.list[#favorites.list + 1] = id
	end
	writeLines(data .. 'Favorites.txt', favorites.list)
	fillVirtual()
	if not searchCat and cats[active].virtual then
		applyGeometry(cats[active])
		offset = normalizeOffset(offset)
		pos, base = offset, -1
		hover.idx, hover.on, hover.a = 0, false, 0
		updateEmptyHint()
		render(true)
	end
end

-- The tile the menu was opened on, for the PowerShell scripts: written to a
-- file, not the command line, because a tile name can hold any character
local function writeTileFile(name, t)
	local f = io.open(resources .. 'Generated\\' .. name, 'wb')
	if not f then return false end
	f:write(t.file .. '|' .. t.name)
	f:close()
	return true
end

function TileMenu(kind)
	local t = pointed
	setPointed(nil)
	if not t then return end
	if kind == 'edit' then
		if writeTileFile('EditTile.txt', t) then SKIN:Bang(SKIN:GetVariable('OptionsTileAction')) end
	elseif kind == 'favorite' then
		toggleFavorite(t)
	elseif kind == 'folder' then
		local path = commandTarget(t.command)
		if path then SKIN:Bang('explorer.exe /select,"' .. path .. '"') end
	elseif kind == 'admin' or kind == 'remove' then
		-- TileAction.ps1: run as administrator (UAC asks), or remove the tile
		-- from its category file (after a confirmation)
		if writeTileFile('TileAction.txt', t) then
			SKIN:Bang(SKIN:GetVariable(kind == 'admin' and 'TileRunAsAction' or 'TileRemoveAction'))
		end
	end
end

-- Older name of the "Edit" entry
function EditTile()
	TileMenu('edit')
end

-- Update check on every load (CheckUpdates=1); Update.ps1 asks GitHub at
-- most once a day.
function AutoUpdateCheck()
	if not ready or not V.CheckUpdates then return end
	SKIN:Bang('!CommandMeasure', 'MeasureUpdate', 'Run')
end

function OnUpdateCheck()
	local output = SKIN:GetMeasure('MeasureUpdate'):GetStringValue()
	notice.update = nil
	for line in output:gmatch('[^\r\n]+') do
		local v = line:match('^RESULT:UPDATE=(.+)$')
		if v then notice.update = v
		elseif not line:match('^RESULT:') then dbg('update: ' .. line) end
	end
	showNotice()
end

-- End of Scan.ps1: logs the result and shows the dot if something is new.
function OnScan()
	local output = SKIN:GetMeasure('MeasureScan'):GetStringValue()
	local new = 0
	for line in output:gmatch('[^\r\n]+') do
		local n = line:match('^RESULT:NEW=(%d+)')
		if n then
			new = tonumber(n)
		elseif not line:match('^RESULT:') then
			dbg('scan: ' .. line)
		end
	end
	notice.found = new
	-- tiles of games no longer installed: Missing.txt was written again
	readMissing()
	showNotice()
	base = -1
	render(false)
end

-- The Options window removed or kept tiles of games no longer installed
function OnMissing()
	if not ready then return end
	readMissing()
	showNotice()
	base = -1
	render(false)
end

-- Play time (Playtime.ps1, in the background on load) ------------------------------
-- On load, and when the launcher opens (minAge: seconds since the last
-- reading, the play time changes when a game is closed)
local playtimeRead = nil -- os.time() of the last reading
function ReadPlaytime(minAge)
	if not ready or V.TileInfo == 'never' then return end
	if minAge and playtimeRead and os.time() - playtimeRead < minAge then return end
	playtimeRead = os.time()
	for _, c in ipairs(cats) do
		for _, t in ipairs(c.tiles) do
			if t.steamId then
				SKIN:Bang('!CommandMeasure', 'MeasurePlaytime', 'Run')
				return
			end
		end
	end
end

function OnPlaytime()
	readPlaytime()
	base = -1
	render(false)
end

-- The Options window showed the list: nothing is new any more
function OnFoundSeen()
	notice.found = 0
	showNotice()
end

-- The Options window checked again and found no update
function OnUpdateSeen()
	notice.update = nil
	showNotice()
end

-- Creates the missing thumbnails in the background (called by OnRefreshAction).
function BuildThumbnails()
	if not ready or #pending == 0 then return end
	local f = io.open(resources .. 'Generated\\Thumbs.txt', 'w')
	if not f then return end
	f:write(table.concat(thumbJobs, '\n'))
	f:close()
	SKIN:Bang('!CommandMeasure', 'MeasureThumbs', 'Run')
end

-- End of Thumbs.ps1: switch to the thumbnails just created.
function OnThumbnails()
	if not ready then return end
	local changed = false
	readLogoColors()
	for _, p in ipairs(pending) do
		if p.field == 'color' then
			local color = logoColors[p.key]
			if color and color ~= '' then
				p.tile.color = color
				changed = true
			end
		elseif fileExists(p.dst) then
			p.tile[p.field] = p.dst
			if p.field == 'background' then p.tile.bgSize = nil end
			changed = true
		end
	end
	pending = {}
	if changed then
		base = -1
		frame()
	end
end

-- Highlight of the tile under the mouse: a single box, handled by the script.
-- Repeated events for the same tile cost nothing; with AnimHover it slides
-- from one tile to the next and fades in/out. With AnimLogoZoom the logo of
-- the tile under the mouse grows.
-- Moves the highlight (mouse or keyboard) to tile t, index idx, at grid
-- coordinates tx, ty.
local function focus(t, idx, tx, ty)
	if hover.on and hover.idx == idx and hover.tx == tx and hover.ty == ty then return end
	hover.tx, hover.ty = tx, ty
	if hover.a < 0.05 or not V.AnimHover then
		-- it was off: appear directly on the new tile
		hover.gx, hover.gy = hover.tx, hover.ty
	end
	hover.idx, hover.on = idx, true

	local animate = false
	if V.TileHover then
		if V.AnimHover then animate = true else hover.a = 1 end
	end
	if (t.logo and (V.AnimLogoZoom or V.LogoGreyscale))
			or (t.background and (V.BgStyle == 'pan' or V.BgStyle == 'zoom')) then
		zooming[t] = true
		animate = true
	end
	if animate then startTicker() else frame() end
end

function HoverTile(slot)
	local t = ready and not launching and tileAt(slot)
	if not t then return end
	setPointed(t)
	local tx, ty = slotToGrid(slot)
	focus(t, indexAt(slot), tx, ty)
end

function LeaveTile(slot)
	if ready then leavePointed(tileAt(slot)) end
	if not ready or not tileAt(slot) or indexAt(slot) ~= hover.idx or not hover.on then return end
	hover.on = false
	local animate = next(zooming) ~= nil
	if V.TileHover then
		if V.AnimHover then animate = true else hover.a = 0 end
	end
	if animate then startTicker() else frame() end
end

-- Re-centres the menu (also called by OnRefreshAction, once the skin is drawn).
function Layout()
	if not ready then return end
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	layoutMenu()
	filter.laidOut = false
	renderCategories()
	renderFilters()
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	SKIN:Bang('!Redraw')
end

function SetCategory(i)
	if not ready or launching or i < 1 or i > #cats then return end
	stopTyping()
	if leaveSearch() and i == active then
		-- click on the category the search started from: go back there
		if V.AnimCategory then appear = 0 startTicker() end
		render(true)
		return
	end
	if i == active then
		-- click on the category already open: back to the start (with infinite
		-- scroll, to the nearest start of the loop)
		local target = 0
		if infinite() then
			local L, o = lineCount(), offset % lineCount()
			target = o <= L / 2 and offset - o or offset + L - o
		end
		if target ~= offset then
			offset = target
			if V.AnimScroll then startTicker() else pos = offset frame() end
		end
		return
	end
	saveScroll()
	active = i
	if virtualDirty then fillVirtual() end
	applyGeometry(cats[i])
	SKIN:Bang('!WriteKeyValue', 'Variables', 'LastCategory', tostring(i), data .. 'State.inc')
	offset = normalizeOffset(cats[i].offset)
	pos, base = offset, -1
	hover.idx, hover.on, hover.a = 0, false, 0
	for t in pairs(zooming) do t.zoom, t.pan = 0, 0 end
	zooming = {}
	updateEmptyHint()
	if V.AnimCategory then
		appear = 0
		startTicker()
	end
	render(true)
end

function SideCategory(kind)
	local i = sideIndex(kind)
	if i then SetCategory(i) end
end

function HoverSide(kind)
	if not ready or side.hovered == kind then return end
	side.hovered = kind
	renderSide()
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	SKIN:Bang('!Redraw')
end

function HoverCategory(i)
	if not ready then return end
	hovered = i
	renderCategories()
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	SKIN:Bang('!Redraw')
end

function Scroll(delta)
	if not ready or launching then return end
	local new = offset + delta * V.ScrollStep
	if not infinite() then new = math.min(math.max(0, new), maxOffset()) end
	if new ~= offset then
		offset = new
		if V.AnimScroll then
			startTicker()
		else
			pos = offset
			frame()
		end
	end
end

-- Launch animation -----------------------------------------------------------
-- The clicked tile expands to fill the screen (LaunchAnimFrames steps of 16 ms,
-- paced by the ActionTimer plugin), stays visible for LaunchHold ms and then
-- the launcher closes.

local function drawSplash(p)
	local a = launching
	local e = 1 - (1 - p) ^ 3 -- cubic ease-out
	local function lerp(from, to) return math.floor(from + (to - from) * e + 0.5) end
	local x, y = lerp(a.x, 0), lerp(a.y, 0)
	local w, h = lerp(V.TileW, V.ScreenW), lerp(V.TileH, V.ScreenH)

	set('SplashBg', 'X', tostring(x))
	set('SplashBg', 'Y', tostring(y))
	set('SplashBg', 'W', tostring(w))
	set('SplashBg', 'H', tostring(h))
	local cx, cy = x + math.floor(w / 2), y + math.floor(h / 2)
	if a.tile.logoFull then
		local t = a.tile
		local size = lerp(V.IconSize * t.logoScale, V.LaunchLogoSize)
		-- the logo starts where it sits in the tile and ends at the centre
		local lx, ly = logoCentre(t, V.IconSize * t.logoScale)
		local fx = lx / V.TileW + (0.5 - lx / V.TileW) * e
		local fy = ly / V.TileH + (0.5 - ly / V.TileH) * e
		set('SplashLogo', 'X', tostring(x + math.floor(w * fx - size / 2)))
		set('SplashLogo', 'Y', tostring(y + math.floor(h * fy - size / 2)))
		set('SplashLogo', 'W', tostring(size))
		set('SplashLogo', 'H', tostring(size))
	elseif a.tile.label then
		set('SplashLabel', 'X', tostring(cx))
		set('SplashLabel', 'Y', tostring(cy))
	end
	SKIN:Bang('!UpdateMeterGroup', 'Splash')
	SKIN:Bang('!Redraw')
end

-- Launches tile t; x, y = its position (in pixels) in the grid, where the
-- expansion starts.
local function launchTile(t, x, y)
	if not t or not t.command then
		dbg('launch ignored: tile without Command')
		return
	end
	if t.missing then
		-- no longer installed: Options > Import, where it can be removed or kept
		dbg('launch ignored: ' .. t.name .. ' is no longer installed')
		SKIN:Bang(SKIN:GetVariable('OptionsImportAction'))
		return
	end
	dbg('launch: ' .. t.command)

	SKIN:Bang(t.command)
	-- counted for Recent; its tiles change the next time it is shown
	if t.file and t.file ~= '' then
		local id = tileId(t)
		local u = usage[id] or { count = 0, last = 0 }
		usage[id] = { count = u.count + 1, last = os.time() }
		writeUsage()
		virtualDirty = true
	end
	if not V.LaunchAnimation then
		if V.CloseOnLaunch then close() end
		return
	end

	stopTicker()
	launching = { tile = t, x = V.PadX + math.floor(x), y = V.GridY + math.floor(y), frame = 0 }
	hover.on, hover.a = false, 0
	show('TileHover', false)

	set('SplashBg', 'ImageName', t.backgroundFull or '')
	set('SplashBg', 'SolidColor', t.color)
	show('SplashBg', true)
	if t.logoFull then set('SplashLogo', 'ImageName', t.logoFull) end
	show('SplashLogo', t.logoFull ~= nil)
	local label = not t.logoFull and t.label
	if label then set('SplashLabel', 'Text', label) end
	show('SplashLabel', label and true or false)

	drawSplash(V.LaunchAnimFrames > 0 and 0 or 1)
	SKIN:Bang('!CommandMeasure', 'MeasureLaunchAnim', 'Execute 1')
end

function Launch(slot)
	if not ready or launching then return end
	local r, c = slotRC(slot)
	local x, y = c * V.StepX, r * V.StepY
	if V.Horizontal then x = x - (pos - base) * V.StepX else y = y - (pos - base) * V.StepY end
	launchTile(tileAt(slot), x, y)
end

-- Keyboard -------------------------------------------------------------------
-- WASD/arrows move the highlight (the same one as the mouse), Space/Enter
-- launch the highlighted tile, Q/E switch category. The keys are registered by
-- the Raintile\Navigation mini-skin, only active while the launcher is visible.

-- Moves the highlight by dx columns and dy rows, scrolling the grid just
-- enough to keep it visible.
function Nav(dx, dy)
	if not ready or launching or not visible then return end
	local tiles = cur().tiles
	if #tiles == 0 then return end
	local L, per, vis = lineCount(), (V.Horizontal and V.NY or V.NX), visibleLines()

	-- line = row (or column, when horizontal) along the scroll direction
	local line, cross
	if hover.idx ~= 0 then
		line = (V.Horizontal and hover.tx or hover.ty) + (V.Horizontal and dx or dy)
		cross = (V.Horizontal and hover.ty or hover.tx) + (V.Horizontal and dy or dx)
	else
		-- no highlighted tile: start from the first visible one
		line, cross = offset, 0
	end
	cross = math.min(math.max(0, cross), per - 1)
	if not infinite() then line = math.min(math.max(0, line), L - 1) end
	-- incomplete last row: stop on the last existing tile
	local wrapped = line % L
	cross = math.min(cross, #tiles - wrapped * per - 1)

	if line < offset then
		offset = line
	elseif line > offset + vis - 1 then
		offset = line - vis + 1
	end
	if pos ~= offset then
		if V.AnimScroll then startTicker() else pos = offset end
	end

	local idx = wrapped * per + cross + 1
	if V.Horizontal then
		focus(tiles[idx], idx, line, cross)
	else
		focus(tiles[idx], idx, cross, line)
	end
end

-- Launches the highlighted tile (or, if there is none, highlights the first).
function Confirm()
	dbg(string.format('Confirm: ready=%s launching=%s visible=%s hover=%d on=%s', tostring(ready),
		tostring(launching ~= nil), tostring(visible), hover.idx, tostring(hover.on)))
	if not ready or launching or not visible then return end
	if hover.idx == 0 or not hover.on then
		Nav(0, 0)
		return
	end
	local x, y = gridToPx(hover.tx, hover.ty)
	launchTile(cur().tiles[hover.idx], x, y)
end

-- Previous (-1) or next (+1) category, wrapping around.
function NextCategory(delta)
	if not ready or launching or not visible then return end
	SetCategory((active - 1 + delta) % #cats + 1)
end

-- Search -----------------------------------------------------------------------
-- A click on the bar at the top left (or the NavSearch key) starts typing: the
-- Raintile\Typing mini-skin takes the letters, digits, space, Backspace,
-- Enter and Esc (TypeKey), and the grid shows, at every key, the tiles of
-- every category that contain all the typed words (tile name, label or
-- category). Enter stops typing and keeps the results (the first one is
-- highlighted: Space/Enter launches it); Esc, a click on a category or an
-- empty search go back to the category. While typing, the navigation and Esc
-- keys are off; they come back shortly after (MeasureKeysDelay), so the
-- release of Enter is not picked up.

local function updateSearchBar()
	local text = typing and (typed .. '|') or query
	set('SearchText', 'Text', text ~= '' and text or V.SearchPlaceholder)
	set('SearchText', 'FontColor', text ~= '' and V.TextColor or V.TextDimColor)
	set('SearchPill', 'Shape', string.format(
		'Rectangle 0,0,%d,%d,%d | Fill Color %s | StrokeWidth 0', V.SearchW, V.MenuH,
		math.min(V.MenuRadius, math.floor(V.MenuH / 2)),
		(searchCat or typing) and V.ActiveCategoryColor or V.HoverCategoryColor))
end

-- Goes back from the search to the active category (without redrawing).
leaveSearch = function()
	if not searchCat then return false end
	searchCat, query = nil, ''
	filter.stores, filter.tags, filter.n = {}, {}, 0
	setGridArea(false)
	applyGeometry(cats[active])
	offset = normalizeOffset(cats[active].offset)
	pos, base = offset, -1
	hover.idx, hover.on, hover.a = 0, false, 0
	for t in pairs(zooming) do t.zoom, t.pan = 0, 0 end
	zooming = {}
	updateSearchBar()
	updateEmptyHint()
	return true
end

local function runSearch(text)
	local words = {}
	for w in trim(text or ''):lower():gmatch('%S+') do words[#words + 1] = w end
	if #words == 0 then
		if leaveSearch() then
			if V.AnimCategory and not typing then appear = 0 startTicker() end
			render(true)
		end
		updateSearchBar()
		return
	end

	local results = {}
	for _, c in ipairs(cats) do
		for _, t in ipairs(c.virtual and {} or c.tiles) do
			local hay = (t.name .. ' ' .. (t.label or '') .. ' ' .. t.catLabel .. ' ' .. (t.store or '')
				.. ' #' .. table.concat(t.tags or {}, ' #')):lower()
			local ok = true
			for _, w in ipairs(words) do
				if not hay:find(w, 1, true) then ok = false break end
			end
			if ok then results[#results + 1] = t end
		end
	end
	-- names starting with the first word first, then alphabetically
	local first = words[1]
	table.sort(results, function(a, b)
		local na, nb = a.name:lower(), b.name:lower()
		local pa, pb = na:sub(1, #first) == first, nb:sub(1, #first) == first
		if pa ~= pb then return pa end
		return na < nb
	end)

	saveScroll() -- remember the position of the category being left
	query = trim(text)
	local starting = searchCat == nil
	searchCat = { name = '', label = '', tiles = results }
	-- the filter bar takes room above the results
	local fullH = V.AreaH
	V.AreaH = fullH - filterSpace()
	categoryGeometry(searchCat)
	V.AreaH = fullH
	if starting then filter.stores, filter.tags, filter.n = {}, {}, 0 end
	filter.ver = filter.ver + 1
	setGridArea(true)
	applyGeometry(searchCat)
	offset, pos, base = 0, 0, -1
	hover.idx, hover.on, hover.a = 0, false, 0
	for t in pairs(zooming) do t.zoom, t.pan = 0, 0 end
	zooming = {}
	updateSearchBar()
	updateEmptyHint()
	if V.AnimCategory and not typing then
		appear = 0
		startTicker()
	end
	render(true)
	-- the first result is already highlighted: Enter/Space launches it
	if #results > 0 then Nav(0, 0) end
end

function SearchOpen()
	if not ready or launching or not visible or typing then return end
	typing = true
	typed = query
	hotKey(false) -- the letters (WASD, Q, E, F...) are typed now
	SKIN:Bang('!ActivateConfig', V.TypingConfig, 'Typing.ini')
	updateSearchBar()
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	SKIN:Bang('!Redraw')
end

-- Stops typing; the other keys come back shortly after (KeysReady)
stopTyping = function()
	if not typing then return end
	typing = false
	SKIN:Bang('!DeactivateConfig', V.TypingConfig)
	updateSearchBar()
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	SKIN:Bang('!Redraw')
	if visible then SKIN:Bang('!CommandMeasure', 'MeasureKeysDelay', 'Execute 1') end
end

-- A key from the Typing mini-skin: a character, or BACK, ENTER, ESC
function TypeKey(key)
	if not ready or not visible or not typing then return end
	if key == 'ENTER' then
		stopTyping()
		return
	elseif key == 'ESC' then
		typed = ''
		stopTyping()
		if leaveSearch() then
			if V.AnimCategory then appear = 0 startTicker() end
			render(true)
		end
		return
	elseif key == 'BACK' then
		typed = typed:sub(1, -2)
	elseif #typed < 60 then
		typed = typed .. key
	end
	dbg('search: ' .. typed)
	runSearch(typed)
	updateSearchBar()
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	SKIN:Bang('!Redraw')
end

-- Turns the keys back on after the search (called by MeasureKeysDelay).
function KeysReady()
	if ready and visible and not typing then hotKey(true) end
end

-- The launcher lost focus (from Helper.ps1, AutoHide=1). Ignored during the
-- launch animation: the game window, or its launcher's, popping up must not
-- interrupt it.
function FocusLost()
	dbg('focus lost: visible=' .. tostring(visible) .. ' launching=' .. tostring(launching ~= nil))
	if not ready or not visible or launching then return end
	Hide()
end

-- Esc: closes the search if open, otherwise hides the launcher.
function Escape()
	if not ready then return end
	if typing then
		TypeKey('ESC')
	elseif searchCat and not launching then
		leaveSearch()
		if V.AnimCategory then appear = 0 startTicker() end
		render(true)
	else
		Hide()
	end
end

function LaunchStep()
	if not launching then return end
	launching.frame = launching.frame + 1
	drawSplash(math.min(1, launching.frame / math.max(1, V.LaunchAnimFrames)))
end

function LaunchFinish()
	dbg('end of launch animation: launching=' .. tostring(launching ~= nil) .. ' visible=' .. tostring(visible))
	if not launching then return end
	launching = nil
	if V.CloseOnLaunch then
		close()
	else
		hideSplash()
		SKIN:Bang('!Redraw')
	end
end
