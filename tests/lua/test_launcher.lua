-- The launcher loaded in the fake Rainmeter and used as a person would.
local R = require('rainmeter')
local t = require('t')

local T = {}

-- Loads the skin with the default categories and the given settings, and
-- checks that it settles (no refresh loop) and is ready.
local function launcher(settings)
	local s = R.new({ settings = settings }):start()
	t.clean(s)
	t.ok(s:upvalue('ready'), 'the launcher is not ready after loading')
	t.ok(s.loads <= 4, 'too many loads before settling: ' .. s.loads)
	return s
end

-- Everything a person does in a session: categories, scrolling, hover,
-- keyboard, search, the power list, then hide.
local function session(s)
	-- loaded, the launcher is already shown: hidden first, so that Show()
	-- opens it (with its animation)
	s:call('Hide()')
	t.atRest(s)
	s:call('Show()')
	t.ok(s:upvalue('visible'), 'the launcher is not visible after Show()')
	local cats = s:upvalue('cats')
	for i = 1, #cats do
		s:call('SetCategory(' .. i .. ')')
		s:call('Scroll(1)')
		s:call('Scroll(-1)')
		for slot = 1, math.min(s:upvalue('slots'), 12) do
			s:call('HoverTile(' .. slot .. ')')
			s:call('LeaveTile(' .. slot .. ')')
		end
	end
	s:call('NextCategory(1)')
	s:call('NextCategory(-1)')
	s:call('Nav(1, 0)')
	s:call('Nav(0, 1)')
	s:call('Nav(-1, -1)')
	s:call('SearchOpen()')
	s:call("TypeKey('a')")
	s:call("TypeKey('ENTER')")
	s:call('Escape()')
	s:call('PowerMenu()')
	s:call('PowerHover(2)')
	s:call('Escape()')
	s:call('Hide()')
	t.clean(s)
	t.ok(not s:upvalue('visible'), 'the launcher is still visible after Hide()')
	t.atRest(s)
end

function T.fullscreen_session()
	local s = launcher({})
	session(s)
end

function T.window_session()
	local s = launcher({ LauncherMode = 'Window' })
	session(s)
end

-- A window never covers the taskbar: at 100% on the whole screen it fills the
-- work area; full screen still covers all of it.
function T.window_full_size_leaves_taskbar()
	local opts = { screen = { 0, 0, 1920, 1080 }, work = { 0, 0, 1920, 1032 } }
	opts.settings = { LauncherMode = 'Window', WindowW = '100%', WindowH = '100%' }
	local s = R.new(opts):start()
	t.clean(s)
	local V = s:upvalue('V')
	t.eq(V.ScreenX .. ',' .. V.ScreenY .. ',' .. V.ScreenW .. ',' .. V.ScreenH, '0,0,1920,1032', 'window rect')
	opts.settings = { LauncherMode = 'Fullscreen' }
	s = R.new(opts):start()
	t.clean(s)
	V = s:upvalue('V')
	t.eq(V.ScreenH, 1080, 'full screen height')
end

function T.docked_left_session()
	local s = launcher({ LauncherMode = 'Dock', DockSide = 'Left' })
	session(s)
end

function T.docked_top_session()
	local s = launcher({ LauncherMode = 'Dock', DockSide = 'Top' })
	session(s)
end

function T.horizontal_scroll_session()
	local s = launcher({ ScrollDir = 'H' })
	session(s)
end

-- Loaded again with nothing changed, the skin does not rewrite its
-- generated files (Grid.inc, Sizes.inc): no refresh.
function T.reload_is_stable()
	local s = launcher({ LauncherMode = 'Dock' })
	local before = s.loads
	s:settle()
	t.clean(s)
	t.eq(s.loads - before, 1, 'loads after a plain refresh')
end

-- Launching a tile: the animation runs to the end, the tile's command runs
-- and the launcher hides (CloseOnLaunch=1).
function T.launch_tile()
	local s = launcher({})
	s:call('Show()')
	local cats = s:upvalue('cats')
	local target
	for i, c in ipairs(cats) do
		if not c.virtual and #c.tiles > 0 and not c.tiles[1].widget then target = i break end
	end
	t.ok(target, 'no category with a tile to launch')
	s:call('SetCategory(' .. target .. ')')
	local before = #s.log
	s:call('Launch(1)')
	t.clean(s)
	t.ok(#s.log > before, 'nothing happened on Launch(1)')
	t.ok(not s:upvalue('launching'), 'the launch animation did not end')
	t.ok(not s:upvalue('visible'), 'the launcher did not hide after the launch')
	t.atRest(s)
end

-- Docked, the menu is compact: its first opening lists every entry, one
-- under the other (a hidden meter measures 0: they used to pile up on the
-- first one until the mouse moved).
function T.compact_menu_first_opening()
	local s = launcher({ LauncherMode = 'Dock', DockSide = 'Left' })
	s:call('Hide()')
	s:call('Show()')
	local M = s:upvalue('M')
	t.ok(M.compact, 'the docked menu is not compact')
	s:call('MoreMenu()')
	t.ok(M.more.open, 'the list did not open')
	local shown = {}
	for n = 0, 8 do
		local m = s.meters[('MeterMoreItem' .. n):lower()]
		if not m.hidden then shown[#shown + 1] = m end
	end
	t.eq(#shown, #M.more.items + 1, 'entries shown (the time and the entries)')
	for k = 2, #shown do
		local a, b = shown[k - 1], shown[k]
		t.ok(b:GetY() >= a:GetY() + a:GetH(), b.name .. ' overlaps ' .. a.name
			.. ' (y ' .. b:GetY() .. ' < ' .. a:GetY() .. ' + ' .. a:GetH() .. ')')
	end
	s:call('MoreMenu()')
	t.ok(not M.more.open, 'the list did not close')
	t.clean(s)
end

return T
