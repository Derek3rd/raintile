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

local IMAGE_EXTS = { '.png', '.jpg', '.jpeg', '.bmp' }

local function isAbsolute(path)
	return path:match('^%a:[\\/]') ~= nil or path:match('^\\\\') ~= nil
end

-- Cerca 'name' in 'dir' (o come percorso assoluto). Se il nome non ha
-- estensione prova .png, .jpg, .jpeg e .bmp.
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

-- Immagine di una tile/categoria: 'value' se indicato (errore nel log se
-- manca), altrimenti il nome di default, che puo' semplicemente non esserci.
local function findImage(value, dir, defaultName, owner)
	value = value and trim(value) or ''
	if value == '' then return lookupImage(dir, defaultName) end
	local path = lookupImage(dir, value)
	if not path then
		print('Raintile: immagine "' .. value .. '" non trovata in ' .. dir .. ' per [' .. owner .. ']')
	end
	return path
end

-- Legge un file di categoria (Categories\<file>.ini).
local function loadCategory(file)
	local ini = parseIni(resources .. 'Categories\\' .. file)
	if not ini then return nil end

	local base = file:gsub('%.[iI][nN][iI]$', '')
	local images = resources .. 'Images\\' .. base .. '\\'
	local c = { file = file, name = base, label = base, order = math.huge, tiles = {} }
	local iconValue

	for _, s in ipairs(ini) do
		local k = s.keys
		if s.name:lower() == 'category' then
			local label = trim(k.name or '')
			if label ~= '' then c.label = label end
			c.order = tonumber(k.order or '') or math.huge
			iconValue = k.icon
		else
			local label = trim(k.label or '')
			local command = trim(SKIN:ReplaceVariables(k.command or ''))
			-- Nome di default delle immagini: Image= oppure il nome della tile
			local image = trim(k.image or '') ~= '' and trim(k.image) or s.name
			local t = {
				background = findImage(k.background, images .. 'background\\', image, s.name),
				logo = findImage(k.logo, images .. 'logo\\', image, s.name),
				color = trim(k.color or '') ~= '' and trim(k.color) or V.TileColor,
				command = command ~= '' and command or nil,
			}
			if label ~= '' then
				t.label = label
			elseif not t.background and not t.logo then
				t.label = s.name -- tile senza immagini: mostra almeno il nome
			end
			c.tiles[#c.tiles + 1] = t
		end
	end

	c.icon = findImage(iconValue, images, 'icon', base)
	return c
end

local function loadCategories(files)
	cats = {}
	for _, file in ipairs(files) do
		local c = loadCategory(file)
		if c then cats[#cats + 1] = c end
	end
	table.sort(cats, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name:lower() < b.name:lower()
	end)
	if #cats == 0 then
		cats[1] = { file = '', name = 'Vuoto', label = 'Nessuna categoria', order = 0, tiles = {} }
	end

	-- Meter che compongono ogni voce del menu, secondo MenuMode
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

-- Generazione di Grid.inc ---------------------------------------------------

local function signature()
	local s = { V.NX .. 'x' .. V.NY, V.MenuMode }
	for _, c in ipairs(cats) do
		s[#s + 1] = c.name .. ':' .. c.label .. ':' .. (c.icon or '')
	end
	return table.concat(s, '|')
end

local function writeGrid(path, sig, files)
	local o = {}
	local function w(s) o[#o + 1] = s end

	w('; GENERATO AUTOMATICAMENTE da Raintile.lua: non modificare a mano.')
	w('[Variables]')
	w('GridSignature=' .. sig)
	-- Elenco dei file di categoria visto l'ultima volta: permette di disegnare
	-- subito al caricamento, mentre la cartella viene ricontrollata in background.
	w('CategoryFiles=' .. table.concat(files, '|'))
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
			if t.logo then set(icon, 'ImageName', t.logo) end
			show(icon, t.logo ~= nil)
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
local knownFiles = {}

-- Riscrive Grid.inc e ricarica la skin se menu, griglia o file sono cambiati.
local function regenerate(files)
	local sig = signature()
	if SKIN:GetVariable('GridSignature', '') == sig
			and table.concat(files, '|') == SKIN:GetVariable('CategoryFiles', '') then
		return false
	end
	if writeGrid(resources .. 'Generated\\Grid.inc', sig, files) then
		SKIN:Bang('!Refresh')
	else
		print('Raintile: impossibile scrivere Generated\\Grid.inc')
	end
	return true
end

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

	-- Parte dall'elenco di file memorizzato; OnCategoryList() lo ricontrolla.
	knownFiles = {}
	for _, file in ipairs(splitList(SKIN:GetVariable('CategoryFiles', ''))) do
		if fileExists(resources .. 'Categories\\' .. file) then knownFiles[#knownFiles + 1] = file end
	end
	if #knownFiles == 0 then return end -- primo avvio: si aspetta l'elenco

	loadCategories(knownFiles)
	if regenerate(knownFiles) then return end

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

-- Riceve l'elenco dei file in Categories\ (dal plugin RunCommand).
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
