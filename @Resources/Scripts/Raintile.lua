-- Raintile: logica del launcher.
--
-- La griglia ha un numero fisso di "slot" (NX * NY meter). Scorrendo o
-- cambiando categoria non si creano meter: si cambiano solo le opzioni degli
-- slot esistenti, e solo quelle il cui valore e' davvero cambiato.
-- I meter degli slot e del menu vengono scritti in Generated\Grid.inc, che
-- viene rigenerato (con un refresh della skin) quando cambiano NX, NY, la
-- modalita' del menu o le categorie.

local V = {}          -- impostazioni
local cats = {}       -- { { name, label, icon, parts, tiles = { ... } }, ... }
local active = 1      -- categoria attiva
local offset = 0      -- righe (V) o colonne (H) scorse
local slots = 0
local cache = {}      -- ultimo valore impostato per meter/opzione
local hovered = 0     -- categoria sotto il mouse
local laidOut = false -- menu gia' misurato e centrato
local resources

local function trim(s)
	return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function unquote(s)
	return (s:gsub('^"(.*)"$', '%1'))
end

-- Legge una variabile numerica; accetta anche formule come (Floor(#ScreenW#/4)).
local function num(name, default)
	local raw = trim(SKIN:ReplaceVariables(SKIN:GetVariable(name, '')))
	local n = tonumber(raw)
	if not n and raw ~= '' then
		if raw:sub(1, 1) ~= '(' then raw = '(' .. raw .. ')' end
		n = tonumber(SKIN:ParseFormula(raw))
	end
	return n or default
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

local function resolveImage(value, owner)
	if not value or trim(value) == '' then return nil end
	local path = unquote(trim(SKIN:ReplaceVariables(value)))
	if not (path:match('^%a:[\\/]') or path:match('^\\\\')) then
		path = resources .. 'Images\\' .. path
	end
	if not fileExists(path) then
		print('Raintile: immagine non trovata per [' .. owner .. ']: ' .. path)
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
			cats[#cats + 1] = { name = name, label = name, tiles = {} }
			index[key] = #cats
		end
		return cats[index[key]]
	end

	local ini = parseIni(resources .. 'Tiles.ini')
	if not ini then
		print('Raintile: impossibile leggere ' .. resources .. 'Tiles.ini')
		ini = {}
	end

	-- Prima passata: ordine e aspetto delle categorie
	for _, s in ipairs(ini) do
		local lower = s.name:lower()
		if lower == 'raintile' then
			for name in (s.keys.categories or ''):gmatch('[^|]+') do
				name = trim(name)
				if name ~= '' then category(name) end
			end
		end
	end
	for _, s in ipairs(ini) do
		local name = s.name:match('^[Cc]ategory:(.+)$')
		if name then
			local c = category(trim(name))
			c.icon = resolveImage(s.keys.icon, s.name)
			local label = trim(s.keys.label or '')
			if label ~= '' then c.label = label end
		end
	end

	-- Seconda passata: tile
	for _, s in ipairs(ini) do
		local k = s.keys
		local lower = s.name:lower()
		if lower ~= 'raintile' and not lower:match('^category:') then
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
					color = (k.color and trim(k.color) ~= '') and trim(k.color) or V.TileColor,
					command = command ~= '' and command or nil,
				}
			end
		end
	end

	if #cats == 0 then category('Vuoto') end

	-- Meter che compongono ogni voce del menu, secondo MenuMode
	for i, c in ipairs(cats) do
		c.showIcon = V.MenuMode ~= 'text' and c.icon ~= nil
		c.showText = V.MenuMode ~= 'icon' or c.icon == nil
		c.parts = {}
		if c.showIcon then c.parts[#c.parts + 1] = 'CatIcon' .. i end
		if c.showText then c.parts[#c.parts + 1] = 'CatText' .. i end
	end
end

-- Generazione di Grid.inc ---------------------------------------------------

local function signature()
	local s = { V.NX .. 'x' .. V.NY, V.MenuMode }
	for _, c in ipairs(cats) do
		s[#s + 1] = c.name .. ':' .. c.label .. ':' .. (c.icon or '')
	end
	return table.concat(s, '|')
end

local function writeGrid(path, sig)
	local o = {}
	local function w(s) o[#o + 1] = s end

	w('; GENERATO AUTOMATICAMENTE da Raintile.lua: non modificare a mano.')
	w('[Variables]')
	w('GridSignature=' .. sig)
	w('')

	-- Voci del menu: una catena di meter con X relativa. Lo script, dopo averli
	-- misurati, sposta solo il primo per centrare tutta la catena.
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

	-- Aree cliccabili delle voci (posizionate dallo script)
	for i = 1, #cats do
		w('[CatHit' .. i .. ']')
		w('Meter=Shape')
		w('MeterStyle=StyleCategoryHit')
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

local function rect(meter, x, y, w, h, color)
	set(meter, 'X', tostring(x))
	set(meter, 'Y', tostring(y))
	set(meter, 'Shape', string.format('Rectangle 0,0,%d,%d,%d | Fill Color %s | StrokeWidth 0',
		w, h, math.min(V.MenuRadius, math.floor(h / 2)), color))
end

local function maxOffset()
	local n = #cats[active].tiles
	if V.Horizontal then
		return math.max(0, math.ceil(n / V.NY) - V.NX)
	end
	return math.max(0, math.ceil(n / V.NX) - V.NY)
end

-- Tile mostrata nello slot (1-based) con l'offset corrente.
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

-- Misura le voci del menu (gia' aggiornate) e centra la catena orizzontalmente.
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

local function pill(meter, i, color)
	local c = cats[i]
	if not laidOut or not c then
		show(meter, false)
		return
	end
	rect(meter, c.l - V.MenuItemPad, V.PadY, c.r - c.l + 2 * V.MenuItemPad, V.MenuH, color)
	show(meter, true)
end

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
	pill('CatPillActive', active, V.ActiveCategoryColor)
	pill('CatPillHover', hovered ~= active and hovered or 0, V.HoverCategoryColor)
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
		tw, th = math.floor(w * V.NX / total), h
		tx, ty = math.floor((w - tw) * offset / maxOff), 0
	else
		x = V.PadX + V.GridW + math.floor((V.PadX - size) / 2)
		y = V.GridY
		w, h = size, V.GridH
		tw, th = w, math.floor(h * V.NY / total)
		tx, ty = 0, math.floor((h - th) * offset / maxOff)
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

	if not laidOut then
		-- I meter del menu devono essere aggiornati per poterli misurare
		SKIN:Bang('!UpdateMeterGroup', 'Menu')
		layoutMenu()
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
	V.ScreenW = num('ScreenW', 1920)
	V.TileW = math.floor(num('TileW', 320))
	V.TileH = math.floor(num('TileH', 250))
	V.Gap = num('Gap', 16)
	V.PadX = num('PadX', 40)
	V.PadY = num('PadY', 24)
	V.MenuH = num('MenuH', 44)
	V.MenuItemPad = num('MenuItemPad', 16)
	V.MenuRadius = num('MenuRadius', 22)
	V.MenuIconDimAlpha = math.floor(num('MenuIconDimAlpha', 150))
	V.ScrollBarSize = num('ScrollBarSize', 4)
	V.ShowLabels = num('ShowLabels', 1) ~= 0
	V.CloseOnLaunch = num('CloseOnLaunch', 1) ~= 0
	V.CloseAction = SKIN:GetVariable('CloseAction', '[!DeactivateConfig]')
	V.GridY = V.PadY + V.MenuH + V.Gap
	V.GridW = V.NX * V.TileW + (V.NX - 1) * V.Gap
	V.GridH = V.NY * V.TileH + (V.NY - 1) * V.Gap
	for _, name in ipairs({ 'TileColor', 'ActiveCategoryColor', 'HoverCategoryColor', 'TextColor',
			'TextDimColor', 'ScrollTrackColor', 'ScrollThumbColor' }) do
		V[name] = SKIN:GetVariable(name, '255,255,255,255')
	end
	local mode = SKIN:GetVariable('MenuMode', 'IconText'):lower()
	V.MenuMode = (mode == 'icon' or mode == 'text') and mode or 'icontext'

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

-- Funzioni chiamate con !CommandMeasure ---------------------------------------

-- Ricentra il menu (chiamata anche da OnRefreshAction, a skin gia' disegnata).
function Layout()
	if not ready then return end
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	layoutMenu()
	renderCategories()
	SKIN:Bang('!UpdateMeterGroup', 'Menu')
	SKIN:Bang('!Redraw')
end

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
	if t and t.command then
		SKIN:Bang(t.command)
		if V.CloseOnLaunch then SKIN:Bang(V.CloseAction) end
	end
end
