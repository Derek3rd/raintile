-- Raintile: logica del launcher.
--
-- La griglia ha un numero fisso di "slot" (NX * NY meter). Scorrendo o
-- cambiando categoria non si creano meter: si cambiano solo le opzioni degli
-- slot esistenti, e solo quelle il cui valore e' davvero cambiato.
-- I meter degli slot e del menu vengono scritti in Generated\Grid.inc, che
-- viene rigenerato (con un refresh della skin) quando cambiano NX, NY o le
-- categorie.

local V = {}          -- impostazioni numeriche
local cats = {}       -- { { name = 'Giochi', tiles = { ... } }, ... }
local active = 1      -- categoria attiva
local offset = 0      -- righe (V) o colonne (H) scorse
local slots = 0
local cache = {}      -- ultimo valore impostato per meter/opzione
local hovered = 0     -- categoria sotto il mouse
local resources

local function trim(s)
	return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function unquote(s)
	return (s:gsub('^"(.*)"$', '%1'))
end

local function num(name, default)
	return tonumber(SKIN:GetVariable(name, '')) or default
end

local function fileExists(path)
	local f = io.open(path, 'r')
	if f then f:close() return true end
	return false
end

-- Parser INI minimale che mantiene l'ordine delle sezioni.
local function parseIni(path)
	local f = io.open(path, 'r')
	if not f then return nil end
	local list, cur = {}, nil
	for line in f:lines() do
		line = trim((line:gsub('^\239\187\191', '')))
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
	f:close()
	return list
end

local function resolveImage(value, tileName)
	if not value or value == '' then return nil end
	local path = unquote(SKIN:ReplaceVariables(value))
	if not (path:match('^%a:[\\/]') or path:match('^\\\\')) then
		path = resources .. 'Images\\' .. path
	end
	if not fileExists(path) then
		print('Raintile: immagine non trovata per [' .. tileName .. ']: ' .. path)
		return nil
	end
	return path
end

local function loadTiles()
	cats = {}
	local index = {}
	local function category(name)
		local key = name:lower()
		if not index[key] then
			cats[#cats + 1] = { name = name, tiles = {} }
			index[key] = #cats
		end
		return cats[index[key]]
	end

	local ini = parseIni(resources .. 'Tiles.ini')
	if not ini then
		print('Raintile: impossibile leggere ' .. resources .. 'Tiles.ini')
		ini = {}
	end

	for _, s in ipairs(ini) do
		if s.name:lower() == 'raintile' then
			for name in (s.keys.categories or ''):gmatch('[^|]+') do
				name = trim(name)
				if name ~= '' then category(name) end
			end
		end
	end

	for _, s in ipairs(ini) do
		local k = s.keys
		if s.name:lower() ~= 'raintile' then
			local cat = trim(k.category or '')
			if cat == '' then
				print('Raintile: la tile [' .. s.name .. '] non ha Category, ignorata')
			else
				local tiles = category(cat).tiles
				local label = k.label and trim(k.label) or ''
				local command = k.command and trim(SKIN:ReplaceVariables(k.command)) or ''
				tiles[#tiles + 1] = {
					background = resolveImage(k.background, s.name),
					icon = resolveImage(k.icon, s.name),
					label = label ~= '' and label or nil,
					color = (k.color and k.color ~= '') and k.color or V.TileColor,
					command = command ~= '' and command or nil,
				}
			end
		end
	end

	if #cats == 0 then category('Vuoto') end
end

-- Generazione di Grid.inc ---------------------------------------------------

local function signature()
	local names = {}
	for i, c in ipairs(cats) do names[i] = c.name end
	return V.NX .. 'x' .. V.NY .. '|' .. table.concat(names, '|')
end

local function writeGrid(path, sig)
	local o = {}
	local function w(s) o[#o + 1] = s end

	w('; GENERATO AUTOMATICAMENTE da Raintile.lua: non modificare a mano.')
	w('[Variables]')
	w('GridSignature=' .. sig)
	w('')

	for i, c in ipairs(cats) do
		w('[Cat' .. i .. ']')
		w('Meter=String')
		w('MeterStyle=StyleCategory')
		w(i == 1 and 'X=#PadX#' or 'X=#MenuGap#R')
		w('Y=(#PadY#+#MenuH#/2)')
		w('Text=' .. c.name)
		w('LeftMouseUpAction=[!CommandMeasure MeasureScript "SetCategory(' .. i .. ')"]')
		w('MouseOverAction=[!CommandMeasure MeasureScript "HoverCategory(' .. i .. ')"]')
		w('MouseLeaveAction=[!CommandMeasure MeasureScript "HoverCategory(0)"]')
		w('')
	end

	local slot = 0
	for r = 0, V.NY - 1 do
		for c = 0, V.NX - 1 do
			slot = slot + 1
			local x = '#PadX#+' .. c .. '*(#TileW#+#Gap#)'
			local y = '#PadY#+#MenuH#+#Gap#+' .. r .. '*(#TileH#+#Gap#)'

			w('[Tile' .. slot .. ']')
			w('Meter=Image')
			w('MeterStyle=StyleTile')
			w('X=(' .. x .. ')')
			w('Y=(' .. y .. ')')
			w('LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(' .. slot .. ')"]')
			w('MouseOverAction=[!ShowMeter TileHover' .. slot .. '][!Redraw]')
			w('MouseLeaveAction=[!HideMeter TileHover' .. slot .. '][!Redraw]')
			w('')
			w('[TileIcon' .. slot .. ']')
			w('Meter=Image')
			w('MeterStyle=StyleTileIcon')
			w('X=(' .. x .. '+(#TileW#-#IconSize#)/2)')
			w('Y=(' .. y .. '+(#TileH#-#IconSize#)/2)')
			w('')
			w('[TileLabel' .. slot .. ']')
			w('Meter=String')
			w('MeterStyle=StyleTileLabel')
			w('X=(' .. x .. '+#LabelPad#)')
			w('Y=(' .. y .. '+#TileH#-#LabelPad#)')
			w('')
			w('[TileHover' .. slot .. ']')
			w('Meter=Shape')
			w('MeterStyle=StyleTileHover')
			w('X=(' .. x .. ')')
			w('Y=(' .. y .. ')')
			w('')
		end
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

local function lines(count, perLine)
	return math.ceil(count / perLine)
end

local function maxOffset()
	local n = #cats[active].tiles
	if V.Horizontal then
		return math.max(0, lines(n, V.NY) - V.NX)
	end
	return math.max(0, lines(n, V.NX) - V.NY)
end

-- Indice (in cats[active].tiles) della tile mostrata nello slot (1-based).
local function tileAt(slot)
	local s = slot - 1
	local r, c = math.floor(s / V.NX), s % V.NX
	local i
	if V.Horizontal then
		i = (offset + c) * V.NY + r + 1
	else
		i = (offset + r) * V.NX + c + 1
	end
	return cats[active].tiles[i]
end

local function renderCategories()
	for i = 1, #cats do
		local meter = 'Cat' .. i
		if i == active then
			set(meter, 'FontColor', V.TextColor)
			set(meter, 'SolidColor', V.ActiveCategoryColor)
		else
			set(meter, 'FontColor', i == hovered and V.AccentColor or V.TextDimColor)
			set(meter, 'SolidColor', '0,0,0,1')
		end
	end
end

local function renderScrollBar()
	local maxOff = maxOffset()
	if maxOff == 0 then
		show('MeterScrollBar', false)
		return
	end

	local total = maxOff + (V.Horizontal and V.NX or V.NY)
	local size = V.ScrollBarSize
	local x, y, w, h, tx, ty, tw, th
	if V.Horizontal then
		x = V.PadX
		y = V.GridY + V.GridH + math.floor((V.PadY - size) / 2)
		w, h = V.GridW, size
		tw = math.floor(w * V.NX / total)
		th = h
		tx = math.floor((w - tw) * offset / maxOff)
		ty = 0
	else
		x = V.PadX + V.GridW + math.floor((V.PadX - size) / 2)
		y = V.GridY
		w, h = size, V.GridH
		tw = w
		th = math.floor(h * V.NY / total)
		tx = 0
		ty = math.floor((h - th) * offset / maxOff)
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

local function render()
	for slot = 1, slots do
		local t = tileAt(slot)
		local tile, icon, label = 'Tile' .. slot, 'TileIcon' .. slot, 'TileLabel' .. slot
		if t then
			set(tile, 'ImageName', t.background or '')
			set(tile, 'SolidColor', t.color)
			show(tile, true)
			if t.icon then set(icon, 'ImageName', t.icon) end
			show(icon, t.icon ~= nil)
			local hasLabel = V.ShowLabels and t.label ~= nil
			if hasLabel then set(label, 'Text', t.label) end
			show(label, hasLabel)
		else
			show(tile, false)
			show(icon, false)
			show(label, false)
			-- l'hover e' gestito dai MouseOver/LeaveAction: qui lo si spegne
			-- solo quando lo slot si svuota
			SKIN:Bang('!HideMeter', 'TileHover' .. slot)
		end
	end
	renderCategories()
	renderScrollBar()
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	SKIN:Bang('!UpdateMeterGroup', 'Tiles')
	SKIN:Bang('!Redraw')
end

-- Ciclo di vita di Rainmeter --------------------------------------------------

local ready = false

function Initialize()
	resources = SKIN:ReplaceVariables('#@#')

	V.NX = math.max(1, math.floor(num('NX', 4)))
	V.NY = math.max(1, math.floor(num('NY', 2)))
	V.Horizontal = SKIN:GetVariable('ScrollDir', 'V'):upper():sub(1, 1) == 'H'
	V.ScrollStep = math.max(1, math.floor(num('ScrollStep', 1)))
	V.TileW = num('TileW', 320)
	V.TileH = num('TileH', 250)
	V.Gap = num('Gap', 16)
	V.PadX = num('PadX', 20)
	V.PadY = num('PadY', 14)
	V.MenuH = num('MenuH', 40)
	V.ScrollBarSize = num('ScrollBarSize', 4)
	V.ShowLabels = num('ShowLabels', 1) ~= 0
	V.GridY = V.PadY + V.MenuH + V.Gap
	V.GridW = V.NX * V.TileW + (V.NX - 1) * V.Gap
	V.GridH = V.NY * V.TileH + (V.NY - 1) * V.Gap
	for _, name in ipairs({ 'TileColor', 'AccentColor', 'ActiveCategoryColor', 'TextColor',
			'TextDimColor', 'ScrollTrackColor', 'ScrollThumbColor' }) do
		V[name] = SKIN:GetVariable(name, '255,255,255,255')
	end

	loadTiles()

	local sig = signature()
	if SKIN:GetVariable('GridSignature', '') ~= sig then
		if writeGrid(resources .. 'Generated\\Grid.inc', sig) then
			SKIN:Bang('!Refresh')
		else
			print('Raintile: impossibile scrivere Generated\\Grid.inc')
		end
		return
	end

	slots = V.NX * V.NY
	active = math.min(math.max(1, math.floor(num('LastCategory', 1))), #cats)
	ready = true
end

function Update()
	-- Con UpdateDivider=-1 viene chiamata una sola volta, al caricamento.
	if ready then render() end
	return active
end

-- Funzioni chiamate dai meter con !CommandMeasure ----------------------------

function SetCategory(i)
	if not ready or i < 1 or i > #cats then return end
	if i ~= active then
		active = i
		SKIN:Bang('!WriteKeyValue', 'Variables', 'LastCategory', tostring(i), resources .. 'State.inc')
	end
	offset = 0
	render()
end

function HoverCategory(i)
	if not ready then return end
	hovered = i
	renderCategories()
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	SKIN:Bang('!Redraw')
end

function Scroll(delta)
	if not ready then return end
	local new = math.min(math.max(0, offset + delta * V.ScrollStep), maxOffset())
	if new ~= offset then
		offset = new
		render()
	end
end

function Launch(slot)
	if not ready then return end
	local t = tileAt(slot)
	if t and t.command then SKIN:Bang(t.command) end
end
