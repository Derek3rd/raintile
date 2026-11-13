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

-- A skin with the Options program, after its search (OnScan)
local function scanned(settings, patch)
	local s = R.new({ settings = settings })
	host_mkdir(s.resources .. 'Bin')
	R.writeFile(s.resources .. 'Bin\\RaintileOptions.exe', '')
	if patch then patch(s) end
	s:start()
	local before = #s.commands
	s.measures.measurescan.value = 'RESULT:MISSING=0\r\nRESULT:NEW=0'
	s:call('OnScan()')
	return s, before
end

-- AutoAddGames=1: the search hands the games found to the Options program,
-- without its window; not with the setting off, nor while the window is open
-- (it adds them itself, on its unsaved changes)
function T.auto_add_after_scan()
	local s, before = scanned({ AutoAddGames = 1 })
	t.ok(ran(s, before, 'RaintileOptions%.exe".-%-Action autoadd'), 'the games found were not handed to the Options program')
	t.clean(s)
	s, before = scanned({})
	t.ok(not ran(s, before, '%-Action autoadd'), 'games added with AutoAddGames=0')
	t.clean(s)
	s, before = scanned({ AutoAddGames = 1 }, function(sk)
		R.writeFile(sk.resources .. 'Generated\\OptionsOpen.txt', tostring(os.time()))
	end)
	t.ok(not ran(s, before, '%-Action autoadd'), 'games added by the skin while the Options window is open')
	t.clean(s)
end

-- The games added by themselves (Generated\AutoAddedNames.txt): the dot on the
-- gear lists them, also after the refresh that shows their tiles, until Found
-- has shown them
function T.auto_added_notice()
	local s = R.new({ settings = { AutoAddGames = 1 } }):start()
	s:call('Hide()')
	R.writeFile(s.resources .. 'Generated\\AutoAddedNames.txt', 'Portal 2\r\nCaf\195\169 Story\r\n')
	local loads = s.loads
	s:call('OnAutoAdded()')
	t.ok(s.loads > loads, 'no refresh for the tiles added, with the launcher hidden')
	local notice = s.meters.meternotice
	t.ok(not notice.hidden, 'no dot on the gear after games were added')
	local tip = notice.set.tooltiptext or ''
	t.ok(tip:find('2 games added by themselves: Portal 2, Caf[\\xE9] Story', 1, true), 'the dot does not list the games added: ' .. tip)
	s:call('OnFoundSeen()')
	t.ok(notice.hidden, 'the dot stays after Found showed the games added')
	t.clean(s)
end

-- Not under the hands of whoever uses the launcher: the refresh waits for it
-- to hide
function T.auto_added_refresh_waits()
	local s = R.new({ settings = { AutoAddGames = 1 } }):start()
	s:call('Show()')
	R.writeFile(s.resources .. 'Generated\\AutoAddedNames.txt', 'Portal 2\r\n')
	local loads = s.loads
	s:call('OnAutoAdded()')
	t.eq(s.loads, loads, 'the skin refreshed while the launcher is in use')
	s:call('Hide()')
	t.ok(s.loads > loads, 'no refresh once the launcher hid')
	t.clean(s)
end

return T
