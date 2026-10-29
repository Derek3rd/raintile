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
local typing = false  -- search text field open (until shortly after it closes)
local leaveSearch     -- defined in the Search section

-- Category shown in the grid: the search results or the active one.
local function cur()
	return searchCat or cats[active]
end
local resources

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
-- the original (and the thumbnail is queued).
local function thumbnail(src, tile, field, dir, name, w, h, mode)
	if not src or not V.Thumbnails then return src end
	local ext = src:lower():match('%.png$') and '.png' or '.jpg'
	local tag = (mode == 'cover' or mode == 'contain') and '' or ('_' .. mode)
	local dst = string.format('%sGenerated\\Thumbs\\%s\\%s_%d_%dx%d%s%s',
		resources, dir, safeName(name), fileSize(src) or 0, w, h, tag, ext)
	thumbJobs[#thumbJobs + 1] = table.concat({ src, dst, w, h, mode }, '|')
	if fileExists(dst) then return dst end
	pending[#pending + 1] = { tile = tile, field = field, dst = dst }
	return src
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
	-- logo thumbnails are made at the largest size (zoom included)
	c.logoMax = math.floor(c.iconSize * V.HoverLogoScale + 0.5)
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

-- Reads a category file (Categories\<file>.ini).
local function loadCategory(file)
	local ini = parseIni(resources .. 'Categories\\' .. file)
	if not ini then return nil end

	local base = file:gsub('%.[iI][nN][iI]$', '')
	local images = resources .. 'Images\\' .. base .. '\\'
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
			t.background = thumbnail(t.background, t, 'background', base .. '\\background', s.name,
				c.tw, c.th, V.BgThumbMode)
			t.logo = thumbnail(t.logo, t, 'logo', base .. '\\logo', s.name,
				c.logoMax, c.logoMax, 'contain')
			if label ~= '' then
				t.label = label
			elseif not t.background and not t.logo then
				t.label = s.name -- tile without images: show at least its name
			end
			t.name, t.catLabel = s.name, c.label -- for search
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
	end
	-- Slots to generate: as many as the largest grid needs
	slots = 0
	for _, c in ipairs(cats) do slots = math.max(slots, c.rows * c.cols) end
	local default = {} -- default grid, used by search results
	categoryGeometry(default)
	slots = math.max(slots, default.rows * default.cols)

	-- Meters making up each menu entry, according to MenuMode
	for i, c in ipairs(cats) do
		c.showIcon = V.MenuMode ~= 'text' and c.icon ~= nil
		c.showText = V.MenuMode ~= 'icon' or c.icon == nil
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
local GRID_VERSION = 4

local function signature()
	local s = { 'v' .. GRID_VERSION, slots, V.MenuMode }
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
	for i, c in ipairs(cats) do
		local x = i == 1 and '#PadX#' or '(#MenuGap#+2*#MenuItemPad#)R'
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

	-- Clickable areas of the entries (placed by the script)
	for i = 1, #cats do
		w('[CatHit' .. i .. ']')
		w('Meter=Shape')
		w('MeterStyle=StyleCategoryHit')
		w('LeftMouseUpAction=[!CommandMeasure MeasureScript "SetCategory(' .. i .. ')"]')
		w('MouseOverAction=[!CommandMeasure MeasureScript "HoverCategory(' .. i .. ')"]')
		w('MouseLeaveAction=[!CommandMeasure MeasureScript "HoverCategory(0)"]')
		w('')
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
-- it (Pan, Parallax) or shrinking it (Zoom).
-- x, y = tile position in the grid. Returns "x,y,w,h" or nil.
local function bgWindow(t, x, y)
	if t.bgSize == nil then t.bgSize = imageSize(t.background) or false end
	local d = t.bgSize
	if not d then return nil end
	local iw, ih = d[1], d[2]
	local scale = math.max(V.TileW / iw, V.TileH / ih) * V.BgOverscan
	if V.BgStyle == 'zoom' then
		scale = scale * (1 + (V.BgHoverZoom - 1) * (t.zoom or 0))
	end
	local cw, ch = V.TileW / scale, V.TileH / scale
	local px, py = 0.5, 0.5
	if V.BgStyle == 'pan' then
		-- from the centre towards one end, along the axis with more room
		local e = 0.5 * easeInOut(t.pan or 0)
		if (iw - cw) / iw >= (ih - ch) / ih then px = 0.5 + e else py = 0.5 + e end
	elseif V.BgStyle == 'parallax' then
		-- the visible part depends on where the tile is in the grid
		if V.Horizontal then
			px = math.min(1, math.max(0, (x + V.TileW / 2) / V.GridW))
		else
			py = math.min(1, math.max(0, (y + V.TileH / 2) / V.GridH))
		end
	end
	return string.format('%d,%d,%d,%d', math.floor((iw - cw) * px + 0.5), math.floor((ih - ch) * py + 0.5),
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
		SKIN:Bang('!WriteKeyValue', 'Variables', 'Scroll_' .. c.name, tostring(o), resources .. 'State.inc')
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
	for _, c in ipairs(cats) do
		c.l, c.r = nil, nil
		for _, name in ipairs(c.parts) do
			local m = SKIN:GetMeter(name)
			local x, w = m:GetX(), m:GetW()
			c.l = c.l and math.min(c.l, x) or x
			c.r = c.r and math.max(c.r, x + w) or x + w
		end
	end

	local origin = cats[1].l
	local total = cats[#cats].r - origin
	if total <= 0 then return end

	local start = math.floor((V.ScreenW - total) / 2)
	local shift = start - origin
	set(cats[1].parts[1], 'X', tostring(start))
	for i, c in ipairs(cats) do
		c.l, c.r = c.l + shift, c.r + shift
		rect('CatHit' .. i, c.l - V.MenuItemPad, V.PadY,
			c.r - c.l + 2 * V.MenuItemPad, V.MenuH, '0,0,0,1')
		show('CatHit' .. i, true)
	end
	laidOut = true
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
	-- No category is active during a search.
	local x, w = pillTarget(active)
	if searchCat then
		show('CatPillActive', false)
	elseif pillPos and V.AnimCategory and (pillPos.x ~= x or pillPos.w ~= w) then
		startTicker()
	else
		pillPos = { x = x, w = w }
		drawPill('CatPillActive', x, w, V.ActiveCategoryColor)
	end

	if hovered ~= 0 and hovered ~= active then
		local hx, hw = pillTarget(hovered)
		drawPill('CatPillHover', hx, hw, V.HoverCategoryColor)
	else
		show('CatPillHover', false)
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
			set(tile, 'ImageAlpha', alpha)
			set(tile, 'SolidColor', fade(t.color, f))
			local crop = V.BgStyle ~= 'crop' and t.background and bgWindow(t, x, y)
			set(tile, 'PreserveAspectRatio', crop and '0' or '2')
			set(tile, 'ImageCrop', crop or '')
			if t.logo then
				local size = math.floor(V.IconSize * (1 + (V.HoverLogoScale - 1) * (t.zoom or 0)) + 0.5)
				set(icon, 'X', tostring(x + math.floor((V.TileW - size) / 2)))
				set(icon, 'Y', tostring(y + math.floor((V.TileH - size) / 2)))
				set(icon, 'W', tostring(size))
				set(icon, 'H', tostring(size))
				set(icon, 'ImageAlpha', alpha)
				if V.LogoGreyscale then
					local rows = saturationRows(t.zoom or 0)
					set(icon, 'ColorMatrix1', rows[1])
					set(icon, 'ColorMatrix2', rows[2])
					set(icon, 'ColorMatrix3', rows[3])
				end
			end
			local hasLabel = V.ShowLabels and t.label ~= nil
			if hasLabel then
				set(label, 'W', tostring(V.TileW - 2 * V.LabelPad))
				set(label, 'X', tostring(x + V.LabelPad))
				set(label, 'Y', tostring(y + V.TileH - V.LabelPad))
				set(label, 'FontColor', fade(V.TextColor, f))
				set(label, 'FontEffectColor', fade('0,0,0,200', f))
			end
			show(tile, true)
			show(icon, t.logo ~= nil)
			show(label, hasLabel)
		else
			show(tile, false)
			show(icon, false)
			show(label, false)
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
		SKIN:Bang('!UpdateMeterGroup', 'Menu')
	end
	frame()
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

	if pillPos and laidOut and not searchCat then
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
	for _, s in ipairs(parseIni(resources .. 'Settings.inc') or {}) do
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

function Initialize()
	resources = SKIN:ReplaceVariables('#@#')
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
	V.ImportOnStart = num('ImportOnStart', 0) ~= 0
	V.SearchW = math.floor(num('SearchW', 320))
	V.SearchPlaceholder = SKIN:GetVariable('SearchPlaceholder', 'Search')
	V.NavConfig = SKIN:ReplaceVariables('#ROOTCONFIG#') .. '\\Navigation'
	V.GridY = V.PadY + V.MenuH + V.Gap
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
		if fileExists(resources .. 'Categories\\' .. file) then knownFiles[#knownFiles + 1] = file end
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
		if V.AnimOpen and not V.StartHidden then appear = 0 end
		render(true)
		if V.StartHidden then
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
	if V.AnimOpen then appear = 0 end
	frame() -- first frame drawn before showing the window
	if V.ShowZPos ~= '' then SKIN:Bang('!ZPos', V.ShowZPos) end
	SKIN:Bang('!Show')
	hotKey(true)
	if appear then startTicker() end
end

function Hide()
	dbg('Hide: visible=' .. tostring(visible) .. ' launching=' .. tostring(launching ~= nil))
	if not ready or not visible then return end
	visible = false
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

-- Automatic background import on every load (ImportOnStart=1). If it finds
-- something new the skin refreshes and the import runs again, but the second
-- time nothing changes and so nothing refreshes: no loops.
function AutoImport()
	if not ready or not V.ImportOnStart then return end
	SKIN:Bang('!CommandMeasure', 'MeasureImport', 'Run')
end

-- End of Import.ps1: logs the result and refreshes if something changed.
function OnImport()
	local output = SKIN:GetMeasure('MeasureImport'):GetStringValue()
	local changed = false
	for line in output:gmatch('[^\r\n]+') do
		if line:match('^RESULT:CHANGED') then
			changed = true
		elseif not line:match('^RESULT:') then
			print('Raintile: import: ' .. line)
		end
	end
	if changed then SKIN:Bang('!Refresh') end
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
	local tx, ty = slotToGrid(slot)
	focus(t, indexAt(slot), tx, ty)
end

function LeaveTile(slot)
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
	renderCategories()
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	SKIN:Bang('!Redraw')
end

function SetCategory(i)
	if not ready or launching or i < 1 or i > #cats then return end
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
	applyGeometry(cats[i])
	SKIN:Bang('!WriteKeyValue', 'Variables', 'LastCategory', tostring(i), resources .. 'State.inc')
	offset = normalizeOffset(cats[i].offset)
	pos, base = offset, -1
	hover.idx, hover.on, hover.a = 0, false, 0
	for t in pairs(zooming) do t.zoom, t.pan = 0, 0 end
	zooming = {}
	if V.AnimCategory then
		appear = 0
		startTicker()
	end
	render(true)
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
		local size = lerp(V.IconSize, V.LaunchLogoSize)
		set('SplashLogo', 'X', tostring(cx - math.floor(size / 2)))
		set('SplashLogo', 'Y', tostring(cy - math.floor(size / 2)))
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
	dbg('launch: ' .. t.command)

	SKIN:Bang(t.command)
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
-- The bar at the top left (or the NavSearch key) opens a text field (InputText
-- plugin). On Enter the grid shows the tiles of every category that contain
-- all the searched words (tile name, label or category); Esc, a click on a
-- category or an empty search go back to the category. While typing, the
-- navigation and Esc keys are off, and they come back shortly after
-- (MeasureKeysDelay) so the Enter release is not picked up.

local function updateSearchBar()
	set('SearchText', 'Text', query ~= '' and query or V.SearchPlaceholder)
	set('SearchText', 'FontColor', query ~= '' and V.TextColor or V.TextDimColor)
	set('SearchPill', 'Shape', string.format(
		'Rectangle 0,0,%d,%d,%d | Fill Color %s | StrokeWidth 0', V.SearchW, V.MenuH,
		math.min(V.MenuRadius, math.floor(V.MenuH / 2)),
		searchCat and V.ActiveCategoryColor or V.HoverCategoryColor))
end

-- Goes back from the search to the active category (without redrawing).
leaveSearch = function()
	if not searchCat then return false end
	searchCat, query = nil, ''
	applyGeometry(cats[active])
	offset = normalizeOffset(cats[active].offset)
	pos, base = offset, -1
	hover.idx, hover.on, hover.a = 0, false, 0
	for t in pairs(zooming) do t.zoom, t.pan = 0, 0 end
	zooming = {}
	updateSearchBar()
	show('SearchEmpty', false)
	return true
end

local function runSearch(text)
	local words = {}
	for w in trim(text or ''):lower():gmatch('%S+') do words[#words + 1] = w end
	if #words == 0 then
		if leaveSearch() then
			if V.AnimCategory then appear = 0 startTicker() end
			render(true)
		end
		return
	end

	local results = {}
	for _, c in ipairs(cats) do
		for _, t in ipairs(c.tiles) do
			local hay = (t.name .. ' ' .. (t.label or '') .. ' ' .. t.catLabel):lower()
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
	searchCat = { name = '', label = '', tiles = results }
	categoryGeometry(searchCat)
	applyGeometry(searchCat)
	offset, pos, base = 0, 0, -1
	hover.idx, hover.on, hover.a = 0, false, 0
	for t in pairs(zooming) do t.zoom, t.pan = 0, 0 end
	zooming = {}
	updateSearchBar()
	show('SearchEmpty', #results == 0)
	if V.AnimCategory then
		appear = 0
		startTicker()
	end
	render(true)
	-- the first result is already highlighted: Enter/Space launches it
	if #results > 0 then Nav(0, 0) end
end

function SearchOpen()
	if not ready or launching or not visible then return end
	typing = true
	hotKey(false) -- the keys are needed by the text field
	SKIN:Bang('!SetOption', 'MeasureSearchInput', 'DefaultValue', query)
	SKIN:Bang('!UpdateMeasure', 'MeasureSearchInput')
	SKIN:Bang('!CommandMeasure', 'MeasureSearchInput', 'ExecuteBatch 1')
end

function SearchSubmit(text)
	dbg('search: ' .. tostring(text))
	if ready and visible then runSearch(text) end
	SKIN:Bang('!CommandMeasure', 'MeasureKeysDelay', 'Execute 1')
end

function SearchDismiss()
	SKIN:Bang('!CommandMeasure', 'MeasureKeysDelay', 'Execute 1')
end

-- Turns the keys back on after the search (called by MeasureKeysDelay).
function KeysReady()
	typing = false
	if ready and visible then hotKey(true) end
end

-- The launcher lost focus (from Helper.ps1, AutoHide=1). Ignored during the
-- launch animation: the game window, or its launcher's, popping up must not
-- interrupt it. Also ignored around the search: when the text field closes,
-- Windows hands the foreground back to the program that had it before.
function FocusLost()
	dbg('focus lost: visible=' .. tostring(visible) .. ' launching=' .. tostring(launching ~= nil)
		.. ' typing=' .. tostring(typing))
	if not ready or not visible or launching or typing then return end
	Hide()
end

-- Esc: closes the search if open, otherwise hides the launcher.
function Escape()
	if not ready then return end
	if searchCat and not launching then
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
