-- A small fake of Rainmeter, enough to run Raintile.lua outside of it.
--
-- It reads Raintile.ini with its @Include files, keeps the meters, measures
-- and variables, runs the bangs the script sends and the ActionTimer lists it
-- starts, and reloads the skin on !Refresh. It does not draw: sizes are
-- estimated (text from the font size, shapes from their rectangles), close
-- enough to check layouts, not pixels.
--
-- It also follows the rules of Rainmeter that the script must respect: a
-- hidden meter measures 0 (GetW/GetH), options set with !SetOption apply on
-- the next update of the meter, a relative position (r/R) is taken from the
-- previous meter. Whatever the skin would log as an error (a bang on a meter
-- that does not exist, a script error) goes to skin.errors, as do the
-- project's own rules on what reaches Rainmeter: ASCII only, one line per
-- value, no timer left running at rest.
--
-- The host (tests/run.py) gives the file functions Lua does not have:
-- host_mkdtemp(), host_copytree(src, dst), host_listdir(dir), host_rmtree(dir).

local R = {}

local SEP = package.config:sub(1, 1)

local function native(path)
	if SEP == '/' then return (path:gsub('\\', '/')) end
	return path
end
R.native = native

local function trim(s)
	return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function readFile(path)
	local f = io.open(native(path), 'rb')
	if not f then return nil end
	local text = f:read('*a')
	f:close()
	return text
end
R.readFile = readFile

local function writeFile(path, text)
	local f = assert(io.open(native(path), 'wb'))
	f:write(text)
	f:close()
end
R.writeFile = writeFile

-- Formulas ------------------------------------------------------------------
-- Rainmeter's formula syntax: numbers, + - * / % ^, parentheses, the
-- comparisons, && || and ? :, and its functions.
local FUNCS = {
	floor = math.floor, ceil = math.ceil, abs = math.abs, sqrt = math.sqrt,
	min = math.min, max = math.max, exp = math.exp, log = math.log,
	round = function(x, p)
		local m = 10 ^ (p or 0)
		return math.floor(x * m + 0.5) / m
	end,
	trunc = function(x) return x < 0 and math.ceil(x) or math.floor(x) end,
	frac = function(x) return x - (x < 0 and math.ceil(x) or math.floor(x)) end,
	sgn = function(x) return x > 0 and 1 or (x < 0 and -1 or 0) end,
	clamp = function(x, a, b) return math.min(math.max(x, a), b) end,
}

local function parseFormula(text)
	local s, i = text, 1
	local function skip() i = s:find('[^%s]', i) or (#s + 1) end
	local function peek(n) skip() return s:sub(i, i + (n or 1) - 1) end
	local expr
	local function primary()
		skip()
		local c = s:sub(i, i)
		if c == '(' then
			i = i + 1
			local v = expr()
			if peek() ~= ')' then error('missing ) in ' .. text) end
			i = i + 1
			return v
		elseif c == '-' then i = i + 1 return -primary()
		elseif c == '+' then i = i + 1 return primary()
		elseif c == '!' then i = i + 1 return primary() == 0 and 1 or 0
		end
		local hex = s:match('^0[xX]%x+', i)
		if hex then i = i + #hex return tonumber(hex) end
		local n = s:match('^%d*%.?%d+', i)
		if n then i = i + #n return tonumber(n) end
		local name = s:match('^%a%w*', i)
		if name then
			i = i + #name
			local lname = name:lower()
			if lname == 'pi' then return math.pi end
			local f = FUNCS[lname]
			if not f or peek() ~= '(' then error('unknown name ' .. name .. ' in ' .. text) end
			i = i + 1
			local args = { expr() }
			while peek() == ',' do i = i + 1 args[#args + 1] = expr() end
			if peek() ~= ')' then error('missing ) in ' .. text) end
			i = i + 1
			return f(unpack(args))
		end
		error('cannot read "' .. s:sub(i) .. '" in ' .. text)
	end
	local function power()
		local v = primary()
		if peek() == '^' then i = i + 1 return v ^ power() end
		return v
	end
	local function product()
		local v = power()
		while true do
			local c = peek()
			if c == '*' then i = i + 1 v = v * power()
			elseif c == '/' then i = i + 1 local d = power() v = d == 0 and 0 or v / d
			elseif c == '%' then i = i + 1 v = v % power()
			else return v end
		end
	end
	local function sum()
		local v = product()
		while true do
			local c = peek()
			if c == '+' then i = i + 1 v = v + product()
			elseif c == '-' then i = i + 1 v = v - product()
			else return v end
		end
	end
	local function compare()
		local v = sum()
		while true do
			local two = peek(2)
			local c = two:sub(1, 1)
			local w
			if two == '<=' then i = i + 2 w = sum() v = (v <= w) and 1 or 0
			elseif two == '>=' then i = i + 2 w = sum() v = (v >= w) and 1 or 0
			elseif two == '<>' or two == '!=' then i = i + 2 w = sum() v = (v ~= w) and 1 or 0
			elseif c == '<' then i = i + 1 w = sum() v = (v < w) and 1 or 0
			elseif c == '>' then i = i + 1 w = sum() v = (v > w) and 1 or 0
			elseif c == '=' then i = i + (two == '==' and 2 or 1) w = sum() v = (v == w) and 1 or 0
			else return v end
		end
	end
	local function logic()
		local v = compare()
		while true do
			local two = peek(2)
			if two == '&&' then i = i + 2 local w = compare() v = (v ~= 0 and w ~= 0) and 1 or 0
			elseif two == '||' then i = i + 2 local w = compare() v = (v ~= 0 or w ~= 0) and 1 or 0
			else return v end
		end
	end
	expr = function()
		local v = logic()
		if peek() == '?' then
			i = i + 1
			local a = expr()
			if peek() ~= ':' then error('missing : in ' .. text) end
			i = i + 1
			local b = expr()
			return v ~= 0 and a or b
		end
		return v
	end
	local v = expr()
	if peek() ~= '' then error('unexpected "' .. s:sub(i) .. '" in ' .. text) end
	return v
end
R.parseFormula = parseFormula

-- Bang strings: "[!A x y][!B "a b"]", one bang "!A x", or a program to run
-- ("[\"notepad.exe\" file]"). Arguments are split on spaces, "..." and
-- """...""" keep them together.
local function tokens(text)
	local out, i = {}, 1
	while true do
		i = text:find('%S', i)
		if not i then break end
		if text:sub(i, i + 2) == '"""' then
			local j = text:find('"""', i + 3, true) or (#text + 1)
			out[#out + 1] = text:sub(i + 3, j - 1)
			i = j + 3
		elseif text:sub(i, i) == '"' then
			local j = text:find('"', i + 1, true) or (#text + 1)
			out[#out + 1] = text:sub(i + 1, j - 1)
			i = j + 1
		else
			local j = text:find('%s', i) or (#text + 1)
			out[#out + 1] = text:sub(i, j - 1)
			i = j
		end
	end
	return out
end

local function splitBangs(text)
	text = trim(text)
	if text:sub(1, 1) ~= '[' then return { text } end
	local list, depth, start, quote = {}, 0, nil, false
	for k = 1, #text do
		local c = text:sub(k, k)
		if c == '"' then quote = not quote
		elseif not quote and c == '[' then
			if depth == 0 then start = k + 1 end
			depth = depth + 1
		elseif not quote and c == ']' then
			depth = depth - 1
			if depth == 0 and start then list[#list + 1] = text:sub(start, k - 1) start = nil end
		end
	end
	return list
end

-- Skin ----------------------------------------------------------------------

local Skin = {}
Skin.__index = Skin

-- Bangs that change nothing the tests look at: only recorded.
local RECORDED = {
	['!redraw'] = true, ['!show'] = true, ['!hide'] = true, ['!move'] = true, ['!zpos'] = true,
	['!settransparency'] = true, ['!draggable'] = true, ['!keeponscreen'] = true,
	['!activateconfig'] = true, ['!deactivateconfig'] = true, ['!writekeyvalue'] = true,
	['!clickthrough'] = true, ['!setwindowposition'] = true, ['!log'] = true, ['!update'] = true,
	['!fadeduration'] = true, ['!showfade'] = true, ['!hidefade'] = true, ['!togglefade'] = true,
	['!snapedges'] = true, ['!autoselectscreen'] = true, ['!setclip'] = true,
}

-- Options of a skin: data folders, settings, screen.
--   settings = { Key = value }  written to the user's Settings.inc
--   screen = { x, y, w, h }      the screen (#SCREENAREA...#)
--   work = { x, y, w, h }        its work area (#WORKAREA...#), the screen if not given
--   skin = 'Rainside'            the Rainside (Rainside\Rainside.ini, config
--                                Raintile\Rainside) instead of the launcher
function R.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Skin)
	self.repo = opts.repo or REPO
	self.tmp = host_mkdtemp()
	self.side = opts.skin == 'Rainside'
	-- the skin's own files, where Rainmeter has them (the Rainside includes
	-- Raintile.ini from there)
	host_copytree(self.repo .. '\\Raintile.ini', self.tmp .. '\\Skins\\Raintile\\Raintile.ini', '')
	host_copytree(self.repo .. '\\Instance.inc', self.tmp .. '\\Skins\\Raintile\\Instance.inc', '')
	host_copytree(self.repo .. '\\Rainside', self.tmp .. '\\Skins\\Raintile\\Rainside', '')
	self.resources = self.tmp .. '\\Skins\\Raintile\\@Resources\\'
	self.settingsPath = self.tmp .. '\\Settings\\'
	self.data = self.settingsPath .. 'Raintile\\'
	local res = self.repo .. '\\@Resources\\'
	host_copytree(res, self.resources, 'Generated|Bin')
	host_mkdir(self.resources .. 'Generated')
	if opts.data ~= false then
		host_copytree(res .. 'Categories', self.data .. 'Categories', '')
		host_copytree(res .. 'Images', self.data .. 'Images', '')
		host_copytree(res .. 'State.inc', self.data .. 'State.inc', '')
		local text = readFile(res .. 'Settings.inc')
		for key, value in pairs(opts.settings or {}) do
			local n
			text, n = text:gsub('\n(' .. key .. ')=[^\r\n]*', '\n%1=' .. tostring(value):gsub('%%', '%%%%'))
			if n == 0 then error('no setting ' .. key .. ' in Settings.inc') end
		end
		writeFile(self.data .. 'Settings.inc', text)
	end
	local sc = opts.screen or { 0, 0, 1920, 1040 }
	local wa = opts.work or sc
	self.builtins = {
		['@'] = self.resources,
		settingspath = self.settingsPath,
		skinspath = self.tmp .. '\\Skins\\',
		currentpath = self.tmp .. '\\Skins\\Raintile\\' .. (self.side and 'Rainside\\' or ''),
		rootconfigpath = self.tmp .. '\\Skins\\Raintile\\',
		currentconfig = self.side and 'Raintile\\Rainside' or 'Raintile', rootconfig = 'Raintile',
		currentfile = self.side and 'Rainside.ini' or 'Raintile.ini',
		programpath = 'C:\\Program Files\\Rainmeter\\',
		screenareax = tostring(sc[1]), screenareay = tostring(sc[2]),
		screenareawidth = tostring(sc[3]), screenareaheight = tostring(sc[4]),
		workareax = tostring(wa[1]), workareay = tostring(wa[2]),
		workareawidth = tostring(wa[3]), workareaheight = tostring(wa[4]),
		virtualscreenx = '0', virtualscreeny = '0',
		virtualscreenwidth = tostring(sc[3]), virtualscreenheight = tostring(sc[4]),
		pscreenareawidth = tostring(sc[3]), pscreenareaheight = tostring(sc[4]),
		crlf = '\n',
	}
	self.errors = {}
	self.log = {}       -- every bang and program, as text
	self.commands = {}  -- programs run (tile commands, scripts)
	self.loads = 0
	self.timers = {}    -- ActionTimer lists running: { measure, list }
	self.maxSteps = opts.maxSteps or 5000
	return self
end

function Skin:error(msg)
	self.errors[#self.errors + 1] = msg
end

function Skin:cleanup()
	host_rmtree(self.tmp)
end

-- INI reading ---------------------------------------------------------------

function Skin:section(name)
	local l = name:lower()
	local s = self.byName[l]
	if not s then
		s = { name = name, keys = {}, order = {} }
		self.byName[l] = s
		self.sections[#self.sections + 1] = s
	end
	return s
end

function Skin:parseFile(path, current, depth)
	if depth > 10 then return current end
	local text = readFile(path)
	-- (Rainmeter logs "Unable to read file": kept for the tests)
	if not text then
		self.unread = self.unread or {}
		self.unread[#self.unread + 1] = path
		return current
	end
	text = text:gsub('^\239\187\191', '')
	for line in text:gmatch('[^\r\n]+') do
		local t = trim(line)
		if t ~= '' and t:sub(1, 1) ~= ';' then
			local sec = t:match('^%[(.-)%]$')
			if sec then
				current = self:section(trim(sec))
			elseif current then
				local k, v = t:match('^([^=]-)%s*=%s*(.*)$')
				if k then
					k = trim(k)
					local lk = k:lower()
					if lk:match('^@include') then
						current = self:parseFile(self:replace(v), current, depth + 1)
					else
						if current.keys[lk] == nil then current.order[#current.order + 1] = lk end
						current.keys[lk] = v
						if current.name:lower() == 'variables' then self.vars[lk] = v end
					end
				end
			end
		end
	end
	return current
end

-- #Variables#, built-in or from [Variables], resolved again until none is
-- left (a variable may hold others).
function Skin:replace(text)
	text = tostring(text or '')
	for _ = 1, 10 do
		local changed = false
		text = text:gsub('#([^#%s]+)#', function(name)
			local l = name:lower()
			local v = self.builtins[l] or self.vars[l]
			if v == nil then return nil end
			changed = true
			return v
		end)
		if not changed then break end
	end
	return text
end

function Skin:number(text, default)
	local t = trim(self:replace(text or ''))
	if t == '' then return default end
	local n = tonumber(t)
	if n then return n end
	local ok, v = pcall(parseFormula, t)
	if ok then return v end
	self:error('formula: ' .. tostring(v))
	return default
end

-- Meters and measures ---------------------------------------------------------

local Meter = {}
Meter.__index = Meter

function Meter:opt(key, default)
	local l = key:lower()
	local v = self.set[l]
	if v == nil then v = self.sec.keys[l] end
	if v == nil then
		for k = #self.styles, 1, -1 do
			v = self.styles[k].keys[l]
			if v ~= nil then break end
		end
	end
	if v == nil then return default end
	v = self.skin:replace(v)
	-- DynamicVariables=1: [Measure] is that measure's value
	if l ~= 'dynamicvariables' and trim(self:opt('DynamicVariables', '0')) == '1' then
		v = v:gsub('%[([%w_]+)%]', function(name)
			local ms = self.skin.measures[name:lower()]
			if ms then return tostring(ms:GetValue()) end
		end)
	end
	return v
end

local function padding(m)
	local p = {}
	for n in (m:opt('Padding', '0,0,0,0')):gmatch('[^,]+') do p[#p + 1] = m.skin:number(n, 0) end
	return p[1] or 0, p[2] or 0, p[3] or 0, p[4] or 0
end

-- Splits "a,b,(c,d)" on the commas outside parentheses.
local function args(text)
	local out, depth, cur = {}, 0, ''
	for k = 1, #text do
		local c = text:sub(k, k)
		if c == '(' then depth = depth + 1 elseif c == ')' then depth = depth - 1 end
		if c == ',' and depth == 0 then out[#out + 1] = cur cur = '' else cur = cur .. c end
	end
	out[#out + 1] = cur
	return out
end

-- Size of the meter as Rainmeter would compute it (estimated for text).
function Meter:measure()
	local kind = (self.sec.keys.meter or ''):lower()
	local pl, pt, pr, pb = padding(self)
	local w = self.skin:number(self:opt('W', ''), nil)
	local h = self.skin:number(self:opt('H', ''), nil)
	if kind == 'string' then
		local size = self.skin:number(self:opt('FontSize', '10'), 10)
		local text = self:opt('Text', '')
		text = text:gsub('%[\\x%x+%]', 'W')
		local lines, longest = 0, 0
		for line in (text .. '\n'):gmatch('([^\n]*)\n') do
			lines = lines + 1
			longest = math.max(longest, #line)
		end
		local clip = self:opt('ClipString', '0')
		if w and clip == '2' then
			lines = math.max(1, math.ceil(longest * size * 0.62 / math.max(1, w)))
		elseif w and clip == '1' then
			lines = 1
		end
		w = w or math.floor(longest * size * 0.62 + 0.5)
		h = h or math.floor(lines * size * 1.77 + 0.5)
	elseif kind == 'shape' and not (w and h) then
		local right, bottom = 0, 0
		for _, key in ipairs(self:shapeKeys()) do
			local def = self:opt(key, '')
			local name, rest = def:match('^%s*(%a+)%s+([^|]*)')
			-- Combine joins shapes defined in other keys: no size of its own
			if name and name:lower() ~= 'combine' then
				local a = args(rest)
				local n = {}
				for k = 1, #a do n[k] = self.skin:number(a[k], 0) or 0 end
				name = name:lower()
				if name == 'rectangle' and #n >= 4 then
					right, bottom = math.max(right, n[1] + n[3]), math.max(bottom, n[2] + n[4])
				elseif name == 'ellipse' and #n >= 3 then
					right, bottom = math.max(right, n[1] + n[3]), math.max(bottom, n[2] + (n[4] or n[3]))
				elseif name == 'line' and #n >= 4 then
					right, bottom = math.max(right, n[1], n[3]), math.max(bottom, n[2], n[4])
				end
			end
		end
		w, h = w or right, h or bottom
	else
		w, h = w or 0, h or w or 0
	end
	self.w, self.h = math.floor(w + pl + pr), math.floor(h + pt + pb)
end

function Meter:shapeKeys()
	local keys = { 'Shape' }
	for k = 2, 64 do keys[#keys + 1] = 'Shape' .. k end
	return keys
end

-- X or Y option: offset and r/R (relative to the previous meter)
local function position(m, key)
	local raw = trim(m:opt(key, '0'))
	local rel = raw:match('[rR]$')
	if rel then raw = raw:sub(1, -2) end
	return m.skin:number(raw, 0) or 0, rel
end

-- An update of the meter: options read again, size and position computed.
function Meter:update()
	if self.set.hidden ~= nil then self.hidden = trim(self:opt('Hidden', '0')) == '1' end
	self:measure()
	self.x, self.xrel = position(self, 'X')
	self.y, self.yrel = position(self, 'Y')
end

-- As in Rainmeter, a relative position is worked out when it is asked for:
-- moving the first meter of a chain moves the others.
function Meter:rawX()
	local prev = self.skin.meterList[self.index - 1]
	if not self.xrel or not prev then return self.x end
	return prev:rawX() + (self.xrel == 'R' and prev:GetW() or 0) + self.x
end

function Meter:rawY()
	local prev = self.skin.meterList[self.index - 1]
	if not self.yrel or not prev then return self.y end
	return prev:rawY() + (self.yrel == 'R' and prev:GetH() or 0) + self.y
end

function Meter:align()
	return (self:opt('StringAlign', 'Left')):lower()
end

-- The Lua API of a meter
function Meter:GetName() return self.name end
function Meter:GetOption(key, default) return self:opt(key, default or '') end
function Meter:GetX()
	local x = self:rawX()
	local a = (self.sec.keys.meter or ''):lower() == 'string' and self:align() or ''
	if a:match('^center') then return x - math.floor(self.w / 2) end
	if a:match('^right') then return x - self.w end
	return x
end
function Meter:GetY()
	local y = self:rawY()
	local a = (self.sec.keys.meter or ''):lower() == 'string' and self:align() or ''
	if a:match('center$') and a ~= 'center' then return y - math.floor(self.h / 2) end
	if a:match('bottom$') then return y - self.h end
	return y
end
-- Rainmeter: a hidden meter is 0 wide and 0 high
function Meter:GetW() return self.hidden and 0 or self.w end
function Meter:GetH() return self.hidden and 0 or self.h end
function Meter:SetX(v) self.x, self.xrel = v, nil end
function Meter:SetY(v) self.y, self.yrel = v, nil end
function Meter:SetW(v) self.w = v end
function Meter:SetH(v) self.h = v end
function Meter:Show() self.hidden = false end
function Meter:Hide() self.hidden = true end

local Measure = {}
Measure.__index = Measure

function Measure:opt(key, default)
	local l = key:lower()
	local v = self.set[l]
	if v == nil then v = self.sec.keys[l] end
	if v == nil then return default end
	return self.skin:replace(v)
end
function Measure:GetName() return self.name end
function Measure:GetOption(key, default) return self:opt(key, default or '') end
function Measure:GetNumberOption(key, default) return self.skin:number(self:opt(key, ''), default or 0) end
function Measure:GetStringValue()
	if self.value ~= nil then return self.value end
	-- a fixed time: os.date with a format it does not know can stop the
	-- process on Windows
	if (self.sec.keys.measure or ''):lower() == 'time' then
		return self.name:lower():match('date') and 'Saturday 7 November' or '18:24'
	end
	return ''
end
function Measure:GetValue()
	-- (a Calc measure without a value of its own: its Formula)
	if self.value == nil and (self.sec.keys.measure or ''):lower() == 'calc' then return self.skin:number(self:opt('Formula', '0'), 0) or 0 end
	return tonumber(self:GetStringValue()) or 0
end
function Measure:Enable() end
function Measure:Disable() end

-- Loading ---------------------------------------------------------------------

function Skin:build()
	self.sections, self.byName, self.vars = {}, {}, {}
	self:parseFile(self.side and (self.tmp .. '\\Skins\\Raintile\\Rainside\\Rainside.ini') or (self.repo .. '\\Raintile.ini'), nil, 0)
	self.meters, self.meterList, self.measures, self.groups = {}, {}, {}, {}
	for _, s in ipairs(self.sections) do
		if s.keys.meter then
			local m = setmetatable({ skin = self, name = s.name, sec = s, set = {}, styles = {},
				x = 0, y = 0, w = 0, h = 0 }, Meter)
			for style in (s.keys.meterstyle or ''):gmatch('[^|]+') do
				local st = self.byName[trim(self:replace(style)):lower()]
				if st then m.styles[#m.styles + 1] = st
				else self:error('meter [' .. s.name .. ']: no style ' .. style) end
			end
			m.hidden = trim(m:opt('Hidden', '0')) == '1'
			m.index = #self.meterList + 1
			self.meterList[m.index] = m
			self.meters[s.name:lower()] = m
			for g in (m:opt('Group', '')):gmatch('[^|]+') do
				g = trim(g):lower()
				self.groups[g] = self.groups[g] or {}
				table.insert(self.groups[g], m)
			end
		elseif s.keys.measure then
			self.measures[s.name:lower()] = setmetatable({ skin = self, name = s.name, sec = s, set = {} }, Measure)
		end
	end
end

-- The Lua script in a fresh environment, as at each load of the skin
function Skin:loadScript()
	local env = setmetatable({}, { __index = _G })
	env._G = env
	env.SKIN = self:api()
	env.print = function(...)
		local parts = {}
		for k = 1, select('#', ...) do parts[k] = tostring((select(k, ...))) end
		self.log[#self.log + 1] = 'print: ' .. table.concat(parts, ' ')
	end
	env.io = setmetatable({ open = function(p, mode) return io.open(native(p), mode) end }, { __index = io })
	env.os = setmetatable({ remove = function(p) return os.remove(native(p)) end }, { __index = os })
	local path = self.resources .. 'Scripts\\Raintile.lua'
	self.env = env
	local chunk, err = loadfile(native(path))
	if not chunk then self:error('the script does not compile: ' .. tostring(err)) return end
	setfenv(chunk, env)
	self:protect('loading the script', chunk)
end

function Skin:protect(what, fn, ...)
	local packed = { ... }
	local ok, err = xpcall(function() return fn(unpack(packed)) end, debug.traceback)
	if not ok then self:error('script error in ' .. what .. ': ' .. tostring(err)) end
	return ok
end

-- One load: read the skin, run Initialize, the first update (measures, then
-- every meter in order), then OnRefreshAction.
function Skin:loadOnce()
	self.loads = self.loads + 1
	self.refresh = false
	self.timers = {}
	self.pendingFinish = {}
	self:build()
	self:loadScript()
	if self.env.Initialize then self:protect('Initialize', self.env.Initialize) end
	if self.env.Update then self:protect('Update', self.env.Update) end
	for _, m in ipairs(self.meterList) do m:update() end
	local rm = self.byName['rainmeter']
	local action = rm and rm.keys.onrefreshaction
	-- !Refresh takes effect after the current action: nothing more runs on
	-- this load once it was asked for
	if action and not self.refresh then self:run(self:replace(action)) end
	if not self.refresh then self:pump() end
end

-- Loads the skin and follows its refreshes until it settles; then runs the
-- background jobs it would wait for (the list of category files).
function Skin:start()
	self:settle()
	return self
end

function Skin:settle()
	for _ = 1, 8 do
		self:loadOnce()
		if not self.refresh then return end
	end
	self:error('the skin keeps refreshing itself (' .. self.loads .. ' loads)')
end

-- Runs code as a bang from the skin ([!CommandMeasure MeasureScript "..."]),
-- then whatever it started: animations, refreshes.
function Skin:call(code)
	self:run('[!CommandMeasure MeasureScript """' .. code .. '"""]')
	self:pump()
	if self.refresh then self:settle() end
end

-- Bangs ------------------------------------------------------------------------

local function ascii(s)
	return not tostring(s):find('[\128-\255]')
end

function Skin:run(text)
	for _, b in ipairs(splitBangs(text)) do
		b = trim(b)
		if b:sub(1, 1) == '!' then
			self:bang(tokens(b))
		elseif b ~= '' then
			self.commands[#self.commands + 1] = b
			self.log[#self.log + 1] = 'run: ' .. b
			if not ascii(b) then self:error('non-ASCII text in a command: ' .. b) end
		end
	end
end

function Skin:meter(name, bang)
	local m = self.meters[tostring(name):lower()]
	if not m then self:error(bang .. ': no meter [' .. tostring(name) .. ']') end
	return m
end

function Skin:measureNamed(name, bang)
	local m = self.measures[tostring(name):lower()]
	if not m then self:error(bang .. ': no measure [' .. tostring(name) .. ']') end
	return m
end

local function group(self, name)
	return self.groups[trim(tostring(name)):lower()] or {}
end

-- a bang aimed at another skin (the config is the last argument)
local OWN = 'raintile' -- the config of the skin running the bang
local function elsewhere(t, n)
	local config = t[n]
	return config ~= nil and config ~= '' and config:lower() ~= OWN and config ~= '#CURRENTCONFIG#'
end

function Skin:bang(t)
	OWN = self.builtins.currentconfig:lower()
	local name = (t[1] or ''):lower()
	self.log[#self.log + 1] = table.concat(t, ' ')
	for k = 2, #t do
		if not ascii(t[k]) then self:error('non-ASCII text sent to Rainmeter: ' .. table.concat(t, ' ')) break end
	end
	if name == '!setoption' then
		if elsewhere(t, 5) then return end
		if tostring(t[4] or ''):find('[\r\n]') then self:error('value on more than one line: ' .. table.concat(t, ' ')) end
		local target = self.meters[tostring(t[2]):lower()] or self.measures[tostring(t[2]):lower()]
		if not target then self:error('!SetOption: no meter or measure [' .. tostring(t[2]) .. ']') return end
		local v = t[4] or ''
		target.set[tostring(t[3]):lower()] = v ~= '' and v or nil
	elseif name == '!setoptiongroup' then
		if elsewhere(t, 5) then return end
		for _, m in ipairs(group(self, t[2])) do m.set[tostring(t[3]):lower()] = t[4] ~= '' and t[4] or nil end
	elseif name == '!updatemeter' then
		if elsewhere(t, 3) then return end
		if t[2] == '*' then
			for _, m in ipairs(self.meterList) do m:update() end
		else
			local m = self:meter(t[2], '!UpdateMeter')
			if m then m:update() end
		end
	elseif name == '!updatemetergroup' then
		if elsewhere(t, 3) then return end
		for _, m in ipairs(group(self, t[2])) do m:update() end
	elseif name == '!showmeter' or name == '!hidemeter' or name == '!togglemeter' then
		if elsewhere(t, 3) then return end
		local m = self:meter(t[2], t[1])
		if m then
			if name == '!togglemeter' then m.hidden = not m.hidden else m.hidden = name == '!hidemeter' end
		end
	elseif name == '!showmetergroup' or name == '!hidemetergroup' then
		if elsewhere(t, 3) then return end
		for _, m in ipairs(group(self, t[2])) do m.hidden = name == '!hidemetergroup' end
	elseif name == '!updatemeasure' or name == '!updatemeasuregroup' then
		if name == '!updatemeasure' and not elsewhere(t, 3) and t[2] ~= '*' then self:measureNamed(t[2], '!UpdateMeasure') end
	elseif name == '!setvariable' then
		if elsewhere(t, 4) then return end
		if tostring(t[3] or ''):find('[\r\n]') then self:error('value on more than one line: ' .. table.concat(t, ' ')) end
		self.vars[tostring(t[2]):lower()] = t[3] or ''
	elseif name == '!writekeyvalue' then
		if tostring(t[4] or ''):find('[\r\n]') then self:error('value on more than one line: ' .. table.concat(t, ' ')) end
		-- (not written: kept for the tests, { section, key, value, file })
		self.writes = self.writes or {}
		self.writes[#self.writes + 1] = { t[2], t[3], t[4], t[5] }
	elseif name == '!refresh' then
		if elsewhere(t, 2) then return end
		self.refresh = true
	elseif name == '!commandmeasure' then
		if elsewhere(t, 4) then return end
		self:command(t[2], t[3] or '')
	elseif not RECORDED[name] then
		self:error('bang the fake Rainmeter does not know: ' .. table.concat(t, ' '))
	end
end

function Skin:command(measureName, arg)
	local m = self:measureNamed(measureName, '!CommandMeasure')
	if not m then return end
	local kind = (m.sec.keys.measure or ''):lower()
	local plugin = (m.sec.keys.plugin or ''):lower()
	if kind == 'script' then
		local code, err = loadstring(arg, '=' .. arg)
		if not code then self:error('bad script command "' .. arg .. '": ' .. err) return end
		setfenv(code, self.env)
		self:protect(arg, code)
	elseif plugin == 'actiontimer' then
		local verb, n = arg:match('^(%a+)%s+(%d+)$')
		verb = (verb or ''):lower()
		if verb == 'execute' then
			self.timers[#self.timers + 1] = { measure = m, list = tonumber(n) }
		elseif verb == 'stop' then
			for k = #self.timers, 1, -1 do
				if self.timers[k].measure == m and self.timers[k].list == tonumber(n) then table.remove(self.timers, k) end
			end
		else
			self:error('ActionTimer command not understood: ' .. arg)
		end
	elseif plugin == 'runcommand' then
		if arg:lower() == 'run' then self:runCommand(m) end
	end
end

-- RunCommand: only the list of category files is answered (as cmd's dir
-- would); the PowerShell jobs never run in the tests.
function Skin:runCommand(m)
	if m.name:lower() ~= 'measurecategorylist' then return end
	local dir = (m:opt('Parameter', '')):match('"(.-)\\%*%.ini"')
	if not dir then return end
	local names = {}
	for line in (host_listdir(dir) .. '\n'):gmatch('([^\n]*)\n') do
		if line:lower():match('%.ini$') then names[#names + 1] = line end
	end
	m.value = table.concat(names, '\r\n')
	self.pendingFinish[#self.pendingFinish + 1] = m
end

-- Runs the background jobs that finished and the ActionTimer lists that were
-- started, step by step, until none is left (or a refresh was asked for).
-- Lists that only wait a long time (the clock, every minute) stay running:
-- they are not steps of an animation.
function Skin:pump()
	local steps = 0
	while not self.refresh do
		if #self.pendingFinish > 0 then
			local m = table.remove(self.pendingFinish, 1)
			self:run(m:opt('FinishAction', ''))
		else
			local k = 1
			while self.timers[k] and self:slow(self.timers[k]) do k = k + 1 end
			local timer = self.timers[k]
			if not timer then break end
			table.remove(self.timers, k)
			steps = steps + 1
			if steps > self.maxSteps then
				self:error('an animation never stops (' .. self.maxSteps .. ' steps of ' .. timer.measure.name .. ')')
				self.timers = {}
				break
			end
			self:runList(timer)
		end
	end
end

-- The clock wakes up every minute while the launcher is shown: not an
-- animation, it is never run here (but must be stopped on hide).
function Skin:slow(timer)
	return timer.measure.name:lower() == 'measureclock'
end

function Skin:runList(timer)
	local m = timer.measure
	local list = m:opt('ActionList' .. timer.list, '')
	for item in list:gmatch('[^|]+') do
		item = trim(item)
		local action, count = item:match('^[Rr]epeat%s+([^,]+),%s*[^,]+,%s*(.+)$')
		if action then
			for _ = 1, math.floor(self:number(count, 1) or 1) do self:run(m:opt(trim(action), '')) end
		elseif not item:lower():match('^wait') then
			self:run(m:opt(item, ''))
		end
	end
end

-- The SKIN object the script sees
function Skin:api()
	local skin = self
	local api = {}
	function api:Bang(...)
		local n = select('#', ...)
		if n == 1 then skin:run((...)) else
			local t = { ... }
			for k = 1, n do t[k] = tostring(t[k]) end
			skin:bang(t)
		end
	end
	function api:GetVariable(name, default)
		local v = skin.builtins[name:lower()] or skin.vars[name:lower()]
		if v == nil then return default end
		return skin:replace(v)
	end
	function api:ReplaceVariables(text) return skin:replace(text) end
	function api:ParseFormula(text)
		local ok, v = pcall(parseFormula, skin:replace(text))
		if ok then return v end
		return nil
	end
	function api:GetMeter(name) return skin.meters[tostring(name):lower()] end
	function api:GetMeasure(name) return skin.measures[tostring(name):lower()] end
	function api:GetX() return 0 end
	function api:GetY() return 0 end
	function api:GetW() return skin:number('#ScreenW#', 0) end
	function api:GetH() return skin:number('#ScreenH#', 0) end
	function api:MakePathAbsolute(p) return p end
	return api
end

-- Helpers for the tests ----------------------------------------------------------

-- A local of Raintile.lua, found among the upvalues of its functions.
function Skin:upvalue(name)
	local seen = {}
	local function search(fn, depth)
		if seen[fn] or depth > 4 then return end
		seen[fn] = true
		for k = 1, 255 do
			local n, v = debug.getupvalue(fn, k)
			if not n then break end
			if n == name then return true, v end
			if type(v) == 'function' then
				local found, value = search(v, depth + 1)
				if found then return found, value end
			end
		end
	end
	for _, v in pairs(self.env) do
		if type(v) == 'function' then
			local found, value = search(v, 0)
			if found then return value end
		end
	end
	error('no local ' .. name .. ' in Raintile.lua')
end

-- Timers still running that are animations (not the slow clock)
function Skin:running()
	local list = {}
	for _, t in ipairs(self.timers) do
		if not self:slow(t) then list[#list + 1] = t.measure.name .. ' ' .. t.list end
	end
	return list
end

R.Skin = Skin
R.tokens, R.splitBangs = tokens, splitBangs
return R
