-- Raintile: logica del launcher.
--
-- La griglia ha un numero fisso di "slot" (NX * NY meter). Scorrendo o
-- cambiando categoria non si creano meter: si cambiano solo le opzioni degli
-- slot esistenti, e solo quelle il cui valore e' davvero cambiato.
-- I meter degli slot e del menu vengono scritti in Generated\Grid.inc, che
-- viene rigenerato (con un refresh della skin) quando cambiano NX, NY, la
-- modalita' del menu o le categorie.

local V = {}          -- impostazioni
local ready = false   -- categorie caricate e griglia pronta
local cats = {}       -- { { name, label, icon, parts, tiles = { ... } }, ... }
local active = 1      -- categoria attiva
local offset = 0      -- righe (V) o colonne (H) scorse: destinazione
local pos = 0         -- posizione di scorrimento mostrata (frazionaria durante l'animazione)
local base = -1       -- riga/colonna mostrata dal primo slot (-1 = contenuti da reimpostare)
local slots = 0
local cache = {}      -- ultimo valore impostato per meter/opzione
local hovered = 0     -- categoria sotto il mouse
local launching = nil -- animazione di avvio in corso: { tile, x, y, frame }
local laidOut = false -- menu gia' misurato e centrato
local appear = nil    -- passi dall'inizio della comparsa delle tile (nil = nessuna)
-- Evidenziazione della tile sotto il mouse, in unita' di griglia (colonna,
-- riga) cosi' segue le tile durante lo scorrimento; a = opacita' 0-1.
local hover = { idx = 0, on = false, gx = 0, gy = 0, tx = 0, ty = 0, a = 0 }
local pillPos = nil   -- { x, w } della pillola della categoria attiva
-- Tile il cui logo e' (o sta tornando) "acceso" dall'hover: [tile] = true.
-- tile.zoom (0-1) e' l'avanzamento, usato per ingrandimento e colore del logo.
local zooming = {}
local ticking = false -- orologio delle animazioni (ActionTimer) attivo
local visible = true  -- launcher mostrato (Show/Hide)
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

-- Parser INI minimale che mantiene l'ordine delle sezioni. Legge UTF-8 e,
-- in modo semplificato (solo caratteri ASCII), UTF-16 LE come Rainmeter.ini.
local function parseIni(path)
	local f = io.open(path, 'rb')
	if not f then return nil end
	local text = f:read('*a')
	f:close()
	if text:sub(1, 2) == '\255\254' then
		text = text:sub(3):gsub('%z', '') -- Lua 5.1: lo zero nei pattern e' %z
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

-- La durata della dissolvenza di apertura/chiusura e' un'impostazione della
-- skin in Rainmeter.ini, non un'opzione del file .ini della skin: la si
-- allinea a FadeDuration di Settings.inc. Vale dal caricamento successivo.
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

-- Cerca 'name' in 'dir' (o come percorso assoluto). Se il nome non ha
-- estensione prova le estensioni di IMAGE_EXTS.
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

local function fileSize(path)
	local f = io.open(path, 'rb')
	if not f then return nil end
	local size = f:seek('end')
	f:close()
	return size
end

-- Dimensioni in pixel di un'immagine PNG, JPEG, BMP o GIF leggendone
-- l'intestazione (nil se il formato non e' riconosciuto).
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
		if h >= 2147483648 then h = 4294967296 - h end -- bitmap dall'alto in basso
	elseif head:sub(1, 3) == 'GIF' then
		w, h = b(7) + b(8) * 256, b(9) + b(10) * 256
	elseif head:sub(1, 2) == '\255\216' then
		-- JPEG: scorre i segmenti fino al marcatore SOF con le dimensioni
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

-- Miniature ------------------------------------------------------------------
-- Rainmeter decodifica le immagini a piena risoluzione e le ridimensiona a ogni
-- disegno. Per questo sfondi e loghi vengono convertiti (in background, da
-- Thumbs.ps1) in miniature della misura esatta in cui vengono mostrati, in
-- Generated\Thumbs\. Il nome della miniatura contiene dimensione del file
-- originale e misura di destinazione: se cambia l'una o l'altra, viene rifatta.

local thumbJobs = {}  -- tutte le miniature desiderate, "src|dst|w|h|modo"
local pending = {}    -- miniature ancora da creare: { tile, field, dst }

local function safeName(s)
	return (s:gsub('[\\/:%*%?"<>|]', '_'))
end

-- Restituisce l'immagine da mostrare: la miniatura se esiste gia', altrimenti
-- l'originale (e la miniatura viene messa in coda).
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

-- Griglia di una categoria: NX x NY tile visibili (default quelli di
-- Settings.inc), dimensionate per riempire l'area della griglia.
local function categoryGeometry(c, nx, ny, iconSize)
	c.nx = math.max(1, math.floor(nx or V.DefNX))
	c.ny = math.max(1, math.floor(ny or V.DefNY))
	c.tw = math.floor((V.AreaW - (c.nx - 1) * V.Gap) / c.nx)
	c.th = math.floor((V.AreaH - (c.ny - 1) * V.Gap) / c.ny)
	-- una riga (o colonna) di slot in piu' per lo scorrimento fluido
	c.rows = c.ny + (V.Horizontal and 0 or 1)
	c.cols = c.nx + (V.Horizontal and 1 or 0)
	c.iconSize = math.floor(iconSize or V.DefIconSize)
	-- le miniature dei loghi sono create alla dimensione massima (zoom incluso)
	c.logoMax = math.floor(c.iconSize * V.HoverLogoScale + 0.5)
end

-- Rende "corrente" la griglia della categoria c: il resto dello script usa
-- V.NX, V.TileW, ... della categoria attiva.
local function applyGeometry(c)
	V.NX, V.NY, V.TileW, V.TileH = c.nx, c.ny, c.tw, c.th
	V.StepX, V.StepY = c.tw + V.Gap, c.th + V.Gap
	V.Rows, V.Cols = c.rows, c.cols
	V.Slots = c.rows * c.cols -- slot usati (gli altri restano nascosti)
	V.GridW = c.nx * c.tw + (c.nx - 1) * V.Gap
	V.GridH = c.ny * c.th + (c.ny - 1) * V.Gap
	V.IconSize = c.iconSize
end

-- Legge un file di categoria (Categories\<file>.ini).
local function loadCategory(file)
	local ini = parseIni(resources .. 'Categories\\' .. file)
	if not ini then return nil end

	local base = file:gsub('%.[iI][nN][iI]$', '')
	local images = resources .. 'Images\\' .. base .. '\\'
	local c = { file = file, name = base, label = base, order = math.huge, tiles = {} }

	-- [Category] per primo: la griglia della categoria serve gia' per le miniature
	local catKeys = {}
	for _, s in ipairs(ini) do
		if s.name:lower() == 'category' then catKeys = s.keys end
	end
	local catLabel = trim(catKeys.name or '')
	if catLabel ~= '' then c.label = catLabel end
	c.order = tonumber(catKeys.order or '') or math.huge
	local iconValue = catKeys.icon
	categoryGeometry(c, tonumber(catKeys.nx or ''), tonumber(catKeys.ny or ''),
		tonumber(catKeys.iconsize or ''))

	for _, s in ipairs(ini) do
		local k = s.keys
		if s.name:lower() ~= 'category' then
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
			-- originali, usati a schermo intero dall'animazione di avvio
			t.backgroundFull, t.logoFull = t.background, t.logo
			t.background = thumbnail(t.background, t, 'background', base .. '\\background', s.name,
				c.tw, c.th, V.BgThumbMode)
			t.logo = thumbnail(t.logo, t, 'logo', base .. '\\logo', s.name,
				c.logoMax, c.logoMax, 'contain')
			if label ~= '' then
				t.label = label
			elseif not t.background and not t.logo then
				t.label = s.name -- tile senza immagini: mostra almeno il nome
			end
			c.tiles[#c.tiles + 1] = t
		end
	end

	c.icon = findImage(iconValue, images, 'icon', base)
	if not c.icon and V.MenuMode ~= 'text' and trim(iconValue or '') == '' then
		print('Raintile: nessuna icona per la categoria "' .. base .. '": cercata ' .. images
			.. 'icon' .. '(' .. table.concat(IMAGE_EXTS, '|') .. ')')
	end
	return c
end

local function loadCategories(files)
	cats = {}
	thumbJobs, pending = {}, {}
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
		categoryGeometry(cats[1])
	end
	-- Slot da generare: quanti ne servono alla griglia piu' grande
	slots = 0
	for _, c in ipairs(cats) do slots = math.max(slots, c.rows * c.cols) end

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

-- Da incrementare quando cambia il formato dei meter scritti da writeGrid().
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

	-- Slot della griglia, dentro il contenitore GridClip: tanti quanti ne servono
	-- alla categoria con la griglia piu' grande. Posizione e misura di ogni slot
	-- le imposta lo script, secondo la griglia della categoria attiva.
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

-- Colore "R,G,B,A" con l'opacita' moltiplicata per f (0-1).
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

-- Sfondi "a finestra" (BgStyle diverso da Crop): l'immagine resta piu' grande
-- della tile (BgOverscan) e la tile ne mostra una parte con ImageCrop,
-- spostandola (Pan, Parallax) o restringendola (Zoom).
-- x, y = posizione della tile nella griglia. Restituisce "x,y,w,h" o nil.
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
		-- dal centro verso un'estremita', lungo l'asse con piu' margine
		local e = 0.5 * easeInOut(t.pan or 0)
		if (iw - cw) / iw >= (ih - ch) / ih then px = 0.5 + e else py = 0.5 + e end
	elseif V.BgStyle == 'parallax' then
		-- la parte mostrata dipende da dove si trova la tile nella griglia
		if V.Horizontal then
			px = math.min(1, math.max(0, (x + V.TileW / 2) / V.GridW))
		else
			py = math.min(1, math.max(0, (y + V.TileH / 2) / V.GridH))
		end
	end
	return string.format('%d,%d,%d,%d', math.floor((iw - cw) * px + 0.5), math.floor((ih - ch) * py + 0.5),
		math.floor(cw + 0.5), math.floor(ch + 0.5))
end

-- Numero >= 0 con 3 decimali e il punto come separatore, a prescindere dalla
-- lingua di sistema (string.format('%.3f') potrebbe usare la virgola).
local function dec(v)
	local n = math.floor(v * 1000 + 0.5)
	return string.format('%d.%03d', math.floor(n / 1000), n % 1000)
end

-- Matrice di colore (righe 1-3 di ColorMatrix) con saturazione sat: 0 = bianco
-- e nero (luminanza), 1 = colori originali.
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

-- Avvicina cur a target di una frazione per passo (k, default AnimSmooth);
-- restituisce il nuovo valore e true se non e' ancora arrivato.
local function approach(cur, target, eps, k)
	if math.abs(target - cur) <= eps then return target, false end
	return cur + (target - cur) * (k or V.AnimSmooth), true
end

-- Righe (V) o colonne (H) di tile della categoria attiva, e quante ne
-- stanno sullo schermo.
local function lineCount()
	return math.ceil(#cats[active].tiles / (V.Horizontal and V.NY or V.NX))
end

local function visibleLines()
	return V.Horizontal and V.NX or V.NY
end

local function maxOffset()
	return math.max(0, lineCount() - visibleLines())
end

-- Scroll infinito: dopo l'ultima riga ricomincia la prima. Solo se le tile
-- non stanno tutte sullo schermo (altrimenti si vedrebbero ripetute).
local function infinite()
	return V.InfiniteScroll and lineCount() > visibleLines()
end

-- Porta uno scorrimento salvato nei limiti della categoria attiva.
local function normalizeOffset(o)
	o = math.floor(o or 0)
	if infinite() then return o % lineCount() end
	return math.min(math.max(0, o), maxOffset())
end

local function slotRC(slot)
	local s = slot - 1
	return math.floor(s / V.Cols), s % V.Cols
end

-- Ricorda lo scorrimento della categoria attiva (anche in State.inc, cosi'
-- resta dopo un aggiornamento della skin).
local function saveScroll()
	local c = cats[active]
	local o = normalizeOffset(offset)
	if c.offset ~= o then
		c.offset = o
		SKIN:Bang('!WriteKeyValue', 'Variables', 'Scroll_' .. c.name, tostring(o), resources .. 'State.inc')
	end
end

-- Indice (in cats[active].tiles) della tile nello slot, con i contenuti attuali.
local function indexAt(slot)
	local r, c = slotRC(slot)
	local line = base + (V.Horizontal and c or r)
	if infinite() then line = line % lineCount() end
	if V.Horizontal then return line * V.NY + r + 1 end
	return line * V.NX + c + 1
end

local function tileAt(slot)
	return cats[active].tiles[indexAt(slot)]
end

-- Posizione in pixel (relativa alla griglia) di un punto in unita' di griglia
-- (colonna, riga), alla posizione di scorrimento corrente.
local function gridToPx(gx, gy)
	if V.Horizontal then gx = gx - pos else gy = gy - pos end
	return gx * V.StepX, gy * V.StepY
end

-- Coordinate di griglia (colonna, riga) dello slot con i contenuti attuali;
-- con lo scroll infinito la riga (o colonna) non viene riportata nel giro.
local function slotToGrid(slot)
	local r, c = slotRC(slot)
	if V.Horizontal then return base + c, r end
	return c, base + r
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

local function pillTarget(i)
	local c = cats[i]
	return c.l - V.MenuItemPad, c.r - c.l + 2 * V.MenuItemPad
end

local function drawPill(meter, x, w, color)
	rect(meter, math.floor(x + 0.5), V.PadY, math.floor(w + 0.5), V.MenuH, color)
	show(meter, true)
end

local startTicker -- definita piu' sotto

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

	-- Pillola attiva: scivola verso la nuova voce (Tick) o salta subito
	local x, w = pillTarget(active)
	if pillPos and V.AnimCategory and (pillPos.x ~= x or pillPos.w ~= w) then
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
	-- frazione di corsa del cursore (con lo scroll infinito: posizione nel giro)
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

-- Contenuti degli slot (immagini, testi) per la riga/colonna 'base'.
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

-- Posizione, opacita' e visibilita' degli slot (anche a ogni passo di animazione).
local function placeSlots()
	local frac = pos - base
	for slot = 1, slots do
		local inUse = slot <= V.Slots -- slot oltre la griglia della categoria: nascosti
		local t = inUse and tileAt(slot)
		local r, c = slotRC(slot)
		local extra = r >= V.NY or c >= V.NX -- riga/colonna in piu'
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

-- Applica lo stato corrente alla griglia e ridisegna.
local function frame()
	local b = math.floor(pos)
	if b ~= base then
		base = b
		fillSlots()
	end
	placeSlots()
	placeHover()
	renderScrollBar()
	SKIN:Bang('!UpdateMeterGroup', 'Tiles')
	SKIN:Bang('!Redraw')
end

-- Ridisegna tutto. 'menu' = aggiorna anche il menu (cambio categoria).
local function render(menu)
	if menu then
		if not laidOut then
			-- I meter del menu devono essere aggiornati per poterli misurare
			SKIN:Bang('!UpdateMeterGroup', 'Menu')
			layoutMenu()
		end
		renderCategories()
		SKIN:Bang('!UpdateMeterGroup', 'Menu')
	end
	frame()
end

-- Animazioni --------------------------------------------------------------------
-- Un solo "orologio" (ActionTimer, Tick ogni 16 ms) fa avanzare tutte le
-- animazioni e si ferma da solo quando nulla si muove piu'.

startTicker = function()
	if ticking then return end
	ticking = true
	SKIN:Bang('!CommandMeasure', 'MeasureAnim', 'Execute 1')
end

local function stopTicker()
	if not ticking then return end
	ticking = false
	SKIN:Bang('!CommandMeasure', 'MeasureAnim', 'Stop 1')
end

-- Fa avanzare tutte le animazioni di un passo; true se qualcosa si muove ancora.
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

	-- Zoom dei loghi: cresce sulla tile sotto il mouse, rientra sulle altre
	local tiles = cats[active].tiles
	for t in pairs(zooming) do
		local target = (hover.on and tiles[hover.idx] == t) and 1 or 0
		t.zoom, moving = approach(t.zoom or 0, target, 0.01, V.AnimLogoSmooth)
		busy = busy or moving
		if V.BgStyle == 'pan' then
			-- velocita' costante: lenta in andata, tre volte piu' rapida al ritorno
			local p = t.pan or 0
			local step = target == 1 and 1 / V.BgPanFrames or 3 / V.BgPanFrames
			p = target == 1 and math.min(1, p + step) or math.max(0, p - step)
			t.pan = p
			busy = busy or p ~= target
		end
		if t.zoom == 0 and (t.pan or 0) == 0 and target == 0 then zooming[t] = nil end
	end

	if pillPos and laidOut then
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

function Tick()
	if not ticking then return end -- passi rimasti in coda dopo lo stop
	if not ready or launching then
		stopTicker()
		return
	end
	local busy = advance()
	frame()
	if not busy then stopTicker() end
end

-- Ciclo di vita di Rainmeter --------------------------------------------------

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
	laidOut, pillPos = false, nil

	-- griglia di default; ogni categoria puo' avere la sua (NX/NY in [Category])
	V.DefNX = math.max(1, math.floor(num('NX', 4)))
	V.DefNY = math.max(1, math.floor(num('NY', 2)))
	V.Horizontal = SKIN:GetVariable('ScrollDir', 'V'):upper():sub(1, 1) == 'H'
	V.ScrollStep = math.max(1, math.floor(num('ScrollStep', 1)))
	V.ScreenW = num('ScreenW', 1920)
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
	V.ScreenH = num('ScreenH', 1080)
	V.CloseOnLaunch = num('CloseOnLaunch', 1) ~= 0
	V.CloseAction = SKIN:GetVariable('CloseAction', '[!CommandMeasure MeasureScript "Hide()"]')
	V.StartHidden = num('StartHidden', 0) ~= 0
	V.ShowZPos = SKIN:GetVariable('ShowZPos', '')
	V.HotKey = trim(SKIN:GetVariable('CloseHotKey', ''))
	-- La mini-skin del tasto di chiusura: attiva solo mentre il launcher e' visibile
	V.HotKeyConfig = SKIN:ReplaceVariables('#ROOTCONFIG#') .. '\\Hotkey'
	V.KeyboardNav = num('KeyboardNav', 1) ~= 0
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
	-- Morbidezza di ciascuna animazione; se vuota vale AnimSmooth
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
	-- miniature degli sfondi: ritagliate alla tile (Crop) oppure piu' grandi,
	-- con il margine per scivolare/ingrandire (percentuale nel nome del modo)
	if V.BgStyle == 'crop' then
		V.BgThumbMode = 'cover'
	else
		local over = V.BgOverscan * (V.BgStyle == 'zoom' and V.BgHoverZoom or 1)
		V.BgThumbMode = 'overscan' .. math.floor(over * 100 + 0.5)
	end
	V.HoverLogoScale = V.AnimLogoZoom and math.max(1, num('HoverLogoScale', 1.25)) or 1
	-- area disponibile per la griglia (le tile di ogni categoria la riempiono)
	V.AreaW = V.ScreenW - 2 * V.PadX
	V.AreaH = V.ScreenH - 2 * V.PadY - V.MenuH - V.Gap
	for _, name in ipairs({ 'TileColor', 'ActiveCategoryColor', 'HoverCategoryColor', 'TextColor',
			'TextDimColor', 'ScrollTrackColor', 'ScrollThumbColor', 'HoverColor', 'AccentColor' }) do
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

	applyFadeDuration()

	loadCategories(knownFiles)
	if regenerate(knownFiles) then return end

	active = math.min(math.max(1, math.floor(num('LastCategory', 1))), #cats)
	applyGeometry(cats[active])
	-- scorrimento salvato di ogni categoria
	for _, c in ipairs(cats) do
		c.offset = math.floor(num('Scroll_' .. c.name, 0))
	end
	offset = normalizeOffset(cats[active].offset)
	pos = offset
	ready = true
end

-- Accende o spegne la mini-skin che registra il tasto di chiusura (Esc).
-- Da spenta il tasto torna libero per le altre applicazioni.
local function hotKey(on)
	if V.HotKey ~= '' then
		if on then
			SKIN:Bang('!ActivateConfig', V.HotKeyConfig, 'Hotkey.ini')
		else
			SKIN:Bang('!DeactivateConfig', V.HotKeyConfig)
		end
	end
	-- tasti di navigazione (WASD, frecce, Spazio/Invio, Q/E): stessa logica
	if V.KeyboardNav then
		if on then
			SKIN:Bang('!ActivateConfig', V.NavConfig, 'Navigation.ini')
		else
			SKIN:Bang('!DeactivateConfig', V.NavConfig)
		end
	end
end

function Update()
	-- Con UpdateDivider=-1 viene chiamata una sola volta, al caricamento.
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

-- Mostra/nascondi ------------------------------------------------------------
-- Il launcher si carica una volta sola e poi resta in memoria: aprirlo e
-- chiuderlo lo mostra e lo nasconde, senza rileggere file ne' ricalcolare nulla.
-- Dalla riga di comando o da una scorciatoia:
--   Rainmeter.exe !CommandMeasure MeasureScript "Toggle()" "Raintile"

local function hideSplash()
	show('SplashBg', false)
	show('SplashLogo', false)
	show('SplashLabel', false)
end

function Show()
	if not ready or visible then return end
	visible = true
	-- riparte pulito: niente hover, zoom o avvio rimasti dalla volta prima
	launching = nil
	hideSplash()
	hover.on, hover.a = false, 0
	for t in pairs(zooming) do t.zoom, t.pan = 0, 0 end
	zooming = {}
	if V.AnimOpen then appear = 0 end
	frame() -- primo fotogramma disegnato prima di mostrare la finestra
	if V.ShowZPos ~= '' then SKIN:Bang('!ZPos', V.ShowZPos) end
	SKIN:Bang('!Show')
	hotKey(true)
	if appear then startTicker() end
end

function Hide()
	if not ready or not visible then return end
	visible = false
	stopTicker()
	pos = offset -- uno scorrimento a meta' riparte gia' concluso
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
	-- l'azione di default richiama Hide() di questo stesso script: la si
	-- chiama direttamente invece di passare da Rainmeter
	if V.CloseAction:match('MeasureScript%s+"Hide%(%)"') then
		Hide()
	else
		SKIN:Bang(V.CloseAction)
	end
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

-- Crea in background le miniature mancanti (chiamata da OnRefreshAction).
function BuildThumbnails()
	if not ready or #pending == 0 then return end
	local f = io.open(resources .. 'Generated\\Thumbs.txt', 'w')
	if not f then return end
	f:write(table.concat(thumbJobs, '\n'))
	f:close()
	SKIN:Bang('!CommandMeasure', 'MeasureThumbs', 'Run')
end

-- Fine di Thumbs.ps1: passa alle miniature appena create.
function OnThumbnails()
	if not ready then return end
	local changed = false
	for _, p in ipairs(pending) do
		if fileExists(p.dst) then
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

-- Evidenziazione della tile sotto il mouse: un solo riquadro, gestito dallo
-- script. Gli eventi ripetuti per la stessa tile non costano nulla; con
-- AnimHover scivola da una tile all'altra e compare/sparisce in dissolvenza.
-- Con AnimLogoZoom il logo della tile sotto il mouse si ingrandisce.
-- Porta l'evidenziazione (mouse o tastiera) sulla tile t, indice idx, alle
-- coordinate di griglia tx, ty.
local function focus(t, idx, tx, ty)
	if hover.on and hover.idx == idx and hover.tx == tx and hover.ty == ty then return end
	hover.tx, hover.ty = tx, ty
	if hover.a < 0.05 or not V.AnimHover then
		-- era spenta: compare direttamente sulla nuova tile
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
	if not ready or launching or i < 1 or i > #cats then return end
	if i == active then
		-- clic sulla categoria gia' aperta: torna all'inizio (con lo scroll
		-- infinito, all'inizio del giro piu' vicino)
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

-- Animazione di avvio ----------------------------------------------------------
-- La tile cliccata si espande fino a riempire lo schermo (LaunchAnimFrames
-- passi da 16 ms, scanditi dal plugin ActionTimer), resta visibile per
-- LaunchHold ms e poi il launcher si chiude.

local function drawSplash(p)
	local a = launching
	local e = 1 - (1 - p) ^ 3 -- ease-out cubica
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

-- Avvia la tile t; x, y = sua posizione (in pixel) nella griglia, da cui
-- parte l'espansione.
local function launchTile(t, x, y)
	if not t or not t.command then return end

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

-- Tastiera -------------------------------------------------------------------
-- WASD/frecce spostano l'evidenziazione (la stessa del mouse), Spazio/Invio
-- avviano la tile evidenziata, Q/E cambiano categoria. I tasti sono registrati
-- dalla mini-skin Raintile\Navigation, attiva solo a launcher visibile.

-- Sposta l'evidenziazione di dx colonne e dy righe, scorrendo la griglia
-- quanto basta perche' resti visibile.
function Nav(dx, dy)
	if not ready or launching or not visible then return end
	local tiles = cats[active].tiles
	if #tiles == 0 then return end
	local L, per, vis = lineCount(), (V.Horizontal and V.NY or V.NX), visibleLines()

	-- line = riga (o colonna, in orizzontale) nel senso dello scorrimento
	local line, cross
	if hover.idx ~= 0 then
		line = (V.Horizontal and hover.tx or hover.ty) + (V.Horizontal and dx or dy)
		cross = (V.Horizontal and hover.ty or hover.tx) + (V.Horizontal and dy or dx)
	else
		-- nessuna tile evidenziata: parte dalla prima visibile
		line, cross = offset, 0
	end
	cross = math.min(math.max(0, cross), per - 1)
	if not infinite() then line = math.min(math.max(0, line), L - 1) end
	-- ultima riga incompleta: si ferma sull'ultima tile presente
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

-- Avvia la tile evidenziata (o, se non ce n'e' una, evidenzia la prima).
function Confirm()
	if not ready or launching or not visible then return end
	if hover.idx == 0 or not hover.on then
		Nav(0, 0)
		return
	end
	local x, y = gridToPx(hover.tx, hover.ty)
	launchTile(cats[active].tiles[hover.idx], x, y)
end

-- Categoria precedente (-1) o successiva (+1), ricominciando dal fondo.
function NextCategory(delta)
	if not ready or launching or not visible then return end
	SetCategory((active - 1 + delta) % #cats + 1)
end

function LaunchStep()
	if not launching then return end
	launching.frame = launching.frame + 1
	drawSplash(math.min(1, launching.frame / math.max(1, V.LaunchAnimFrames)))
end

function LaunchFinish()
	if not launching then return end
	launching = nil
	if V.CloseOnLaunch then
		close()
	else
		hideSplash()
		SKIN:Bang('!Redraw')
	end
end
