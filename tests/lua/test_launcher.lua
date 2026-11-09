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

-- Focus ---------------------------------------------------------------------------

-- Whether a key mini-skin (Navigation, Hotkey, Typing) is on: the last
-- !ActivateConfig or !DeactivateConfig the launcher sent for it.
local function keysOn(s, name)
	local target = 'raintile\\' .. name:lower()
	for k = #s.log, 1, -1 do
		local e = s.log[k]:lower() .. ' '
		if e:find('!activateconfig ' .. target .. ' ', 1, true) == 1 then return true end
		if e:find('!deactivateconfig ' .. target .. ' ', 1, true) == 1 then return false end
	end
	return false
end

-- Shown again (from hidden), as by the shortcut
local function opened(settings)
	local s = launcher(settings)
	s:call('Hide()')
	s:call('Show()')
	t.ok(keysOn(s, 'Navigation') and keysOn(s, 'Hotkey'), 'the keys are off after Show()')
	return s
end

-- As a window the launcher stays open beside the program that took the
-- focus, but its keys and the gamepad stop until a click on it gives the
-- focus back (they used to keep working while typing in the other program).
function T.window_focus_frees_keys()
	local s = opened({ LauncherMode = 'Window' })
	local before = s:upvalue('active')
	s:call("Pad('NextCategory',1)")
	t.ok(s:upvalue('active') ~= before, 'the gamepad does not switch category')
	s:call('FocusLost()')
	t.ok(s:upvalue('visible'), 'the window hid on focus loss')
	t.ok(not keysOn(s, 'Navigation') and not keysOn(s, 'Hotkey'), 'the keys are still on without the focus')
	before = s:upvalue('active')
	s:call("Pad('NextCategory',1)")
	t.eq(s:upvalue('active'), before, 'category after a gamepad button without the focus')
	s:call('FocusGained()')
	t.ok(keysOn(s, 'Navigation') and keysOn(s, 'Hotkey'), 'a click on it did not give the keys back')
	s:call("Pad('NextCategory',1)")
	t.ok(s:upvalue('active') ~= before, 'the gamepad does not switch category with the focus back')
	t.clean(s)
end

-- A search being typed stops with the focus: the letters are free again, and
-- the other keys do not come back after it (KeysReady).
function T.focus_loss_stops_typing()
	local s = opened({ LauncherMode = 'Window' })
	s:call('SearchOpen()')
	t.ok(s:upvalue('typing') and keysOn(s, 'Typing'), 'SearchOpen() did not start typing')
	s:call("TypeKey('a')")
	s:call('FocusLost()')
	t.ok(not s:upvalue('typing'), 'still typing without the focus')
	t.ok(not keysOn(s, 'Typing'), 'the Typing mini-skin is still on')
	t.ok(not keysOn(s, 'Navigation'), 'the keys came back after the search without the focus')
	t.eq(#s:running(), 0, 'animations still running')
	t.clean(s)
end

-- The shortcut on a launcher left open without the focus brings it back with
-- its keys; pressed again it closes it.
function T.toggle_gives_focus_back()
	local s = opened({ LauncherMode = 'Window' })
	s:call('FocusLost()')
	s:call('Toggle()')
	t.ok(s:upvalue('visible'), 'Toggle() hid the launcher left open without the focus')
	t.ok(keysOn(s, 'Navigation'), 'Toggle() did not give the keys back')
	s:call('Toggle()')
	t.ok(not s:upvalue('visible'), 'the second Toggle() did not hide it')
	t.clean(s)
	t.atRest(s)
end

-- The last window level the launcher asked for (!ZPos)
local function zpos(s)
	for k = #s.log, 1, -1 do
		local level = s.log[k]:lower():match('^!zpos%s+(%S+)')
		if level then return level end
	end
end

-- ShowZPos=0 (Normal): Rainmeter keeps a normal skin under every window, so
-- the launcher is on top while in use and Normal once the focus goes; the
-- shortcut brings it back on top (it used to stay under the other windows).
function T.normal_level_on_top_while_in_use()
	local s = opened({ LauncherMode = 'Window', ShowZPos = '0' })
	t.eq(zpos(s), '1', 'window level when opened')
	s:call('FocusLost()')
	t.eq(zpos(s), '0', 'window level without the focus')
	s:call('Toggle()')
	t.eq(zpos(s), '1', 'window level after the shortcut')
	s:call('FocusLost()')
	s:call('FocusGained()')
	t.eq(zpos(s), '1', 'window level after a click on it')
	t.clean(s)
end

-- Full screen hides on focus loss (AutoHide=1); with AutoHide=0 it stays,
-- without its keys.
function T.autohide_on_focus_loss()
	local s = opened({})
	s:call('FocusLost()')
	t.ok(not s:upvalue('visible'), 'full screen did not hide on focus loss')
	s = opened({ AutoHide = '0' })
	s:call('FocusLost()')
	t.ok(s:upvalue('visible'), 'hidden on focus loss with AutoHide=0')
	t.ok(not keysOn(s, 'Navigation'), 'the keys are still on without the focus (AutoHide=0)')
	t.clean(s)
end

-- Opened by the mouse on the docked edge it does not take the keys of the
-- program in front; a click on it does.
function T.dock_edge_opens_without_keys()
	local s = launcher({ LauncherMode = 'Dock', DockSide = 'Left' })
	s:call('Hide()')
	s:call("Show('edge')")
	t.ok(s:upvalue('visible'), "Show('edge') did not open it")
	t.ok(not keysOn(s, 'Navigation'), 'opened from the edge with the keys')
	s:call('FocusGained()')
	t.ok(keysOn(s, 'Navigation'), 'a click on it did not give the keys')
	t.clean(s)
end

-- CloseOnLaunch=0: the game comes in front during the launch animation; the
-- launcher stays open behind it, without its keys (WASD and Space used to
-- move and launch tiles from inside the game).
function T.launch_keeps_keys_off_behind_the_game()
	local s = opened({ CloseOnLaunch = '0' })
	local target
	for i, c in ipairs(s:upvalue('cats')) do
		if not c.virtual and #c.tiles > 0 and not c.tiles[1].widget then target = i break end
	end
	t.ok(target, 'no category with a tile to launch')
	s:call('SetCategory(' .. target .. ')')
	s:run('[!CommandMeasure MeasureScript """Launch(1)"""]')
	t.ok(s:upvalue('launching'), 'no launch animation')
	s:call('FocusLost()')
	t.ok(not s:upvalue('launching'), 'the launch animation did not end')
	t.ok(s:upvalue('visible'), 'hidden although CloseOnLaunch=0')
	t.ok(not keysOn(s, 'Navigation'), 'the keys are still on with the game in front')
	t.clean(s)
end

return T
