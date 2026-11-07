-- Opening the Options program from the launcher.
local R = require('rainmeter')
local t = require('t')

local T = {}

local function ran(s, before, pattern)
	for k = before + 1, #s.commands do
		if s.commands[k]:find(pattern) then return true end
	end
	return false
end

-- A copy of the repository has no RaintileOptions.exe: the gear says so
-- (instead of opening nothing), and the tile menu's Remove leaves the tile
-- file alone.
function T.options_program_missing()
	local s = R.new({}):start()
	s:call('Show()')
	local before = #s.commands
	s:call("OpenOptions('')")
	t.ok(ran(s, before, 'Popup%('), 'no message that the Options program is missing')
	t.ok(not ran(s, before, 'RaintileOptions%.exe"%s+%-Resources'), 'the missing program was started')
	t.ok(not s:upvalue('visible'), 'the launcher did not hide')
	s:call('Show()')
	local cats = s:upvalue('cats')
	local tile
	for _, c in ipairs(cats) do
		if not c.virtual and c.tiles[1] and not c.tiles[1].widget then tile = c.tiles[1] break end
	end
	t.ok(tile, 'no tile to try the menu on')
	s:upvalue('setPointed')(tile)
	s:call("TileMenu('remove')")
	t.ok(not R.readFile(s.resources .. 'Generated\\TileAction.txt'), 'TileAction.txt written for a program that is not there')
	t.clean(s)
end

-- With the program, the gear starts it with the skin's folders
function T.options_program_present()
	local s = R.new({})
	host_mkdir(s.resources .. 'Bin')
	R.writeFile(s.resources .. 'Bin\\RaintileOptions.exe', '')
	s:start()
	local before = #s.commands
	s:call("OpenOptions('info')")
	t.ok(ran(s, before, 'RaintileOptions%.exe".-%-Page info'), 'the Options program was not started on Info')
	t.clean(s)
end

return T
