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

-- Options reads the launcher's own size from Area.txt (after the grid area):
-- the window's size in window mode, the whole screen in full screen.
function T.area_file_has_launcher_size()
	local opts = { screen = { 0, 0, 1920, 1080 }, work = { 0, 0, 1920, 1032 } }
	opts.settings = { LauncherMode = 'Window', WindowW = '1280', WindowH = '720' }
	local s = R.new(opts):start()
	t.clean(s)
	local area = R.readFile(s.resources .. 'Generated\\Area.txt') or ''
	t.ok(area:match(',1280,720\n$'), 'window size not in Area.txt: ' .. area)
	opts.settings = { LauncherMode = 'Fullscreen' }
	s = R.new(opts):start()
	t.clean(s)
	area = R.readFile(s.resources .. 'Generated\\Area.txt') or ''
	t.ok(area:match('^%d+,%d+,%d+,1920,1080\n$'), 'screen size not in Area.txt: ' .. area)
end

-- The screens changed (Helper.ps1: DisplayChanged), as when a game streaming
-- host matches its client or adds a virtual display: the launcher in use is
-- laid out again at once, a hidden one when it opens (never under a game),
-- and nothing reloads when its monitor did not change.
function T.follows_display_changes()
	local s = launcher({})
	local function size()
		local V = s:upvalue('V')
		return V.ScreenW .. 'x' .. V.ScreenH
	end
	local loads = s.loads
	s:call('DisplayChanged()')
	t.eq(s.loads, loads, 'reloaded although its monitor did not change')
	-- in use: at once, and still shown
	s:setScreen({ 0, 0, 3840, 2160 })
	s:call('DisplayChanged()')
	t.clean(s)
	t.eq(size(), '3840x2160', 'not laid out again in use')
	t.ok(s:upvalue('visible'), 'not shown after the new layout')
	t.eq(R.readFile(s.resources .. 'Generated\\ShowOnLoad'), nil, 'ShowOnLoad left behind')
	-- hidden: when it opens
	s:call('Hide()')
	loads = s.loads
	s:setScreen({ 0, 0, 1920, 1080 })
	s:call('DisplayChanged()')
	t.eq(s.loads, loads, 'reloaded while hidden')
	s:call('Show()')
	t.clean(s)
	t.eq(size(), '1920x1080', 'opened at the old size')
	t.ok(s:upvalue('visible'), 'not shown after the new layout')
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

-- The keys the helper hooks now (Generated\\HotKeys.txt), one line each
local function keyLines(s)
	local lines = {}
	for line in (R.readFile(s.resources .. 'Generated\\HotKeys.txt') or ''):gmatch('[^\r\n]+') do lines[#lines + 1] = line end
	return lines
end

-- Whether a set of keys is on: Navigation (the arrows), Close (Esc), Typing
-- (the letters of the search)
local KEY_SETS = { Navigation = 'UP|down|Raintile|Nav(0,-1)', Close = 'ESCAPE|down|Raintile|Escape()', Typing = "A|down|Raintile|TypeKey('a')" }
local function keysOn(s, name)
	for _, line in ipairs(keyLines(s)) do
		if line == KEY_SETS[name] then return true end
	end
	return false
end

-- Shown again (from hidden), as by the shortcut
local function opened(settings)
	local s = launcher(settings)
	s:call('Hide()')
	s:call('Show()')
	t.ok(keysOn(s, 'Navigation') and keysOn(s, 'Close'), 'the keys are off after Show()')
	return s
end

-- The list for the helper: complete, the keys as in Settings.inc, Confirm
-- and Search on release; hidden, only the open/close key
function T.keys_for_the_helper()
	local s = opened()
	local lines = keyLines(s)
	t.eq(lines[#lines], 'end', 'the list does not end with "end"')
	local has = {}
	for _, line in ipairs(lines) do has[line] = true end
	for _, want in ipairs({ 'CTRL ALT G|down|Raintile|Toggle()', 'ESCAPE|down|Raintile|Escape()', 'W|down|Raintile|Nav(0,-1)',
		'ENTER|up|Raintile|Confirm()', 'SPACE|up|Raintile|Confirm()', 'Q|down|Raintile|NextCategory(-1)', 'F|up|Raintile|SearchOpen()' }) do
		t.ok(has[want], 'missing: ' .. want)
	end
	t.ok(not keysOn(s, 'Typing'), 'the letters of the search are on without typing')
	t.ok(not has['log'], 'the keys logged without DebugLog')
	s:call('Hide()')
	lines = keyLines(s)
	t.eq(table.concat(lines, ' / '), 'CTRL ALT G|down|Raintile|Toggle() / end', 'hidden: more than the open/close key')
	t.clean(s)
	-- no keyboard navigation: Esc only
	s = launcher({ KeyboardNav = 0, CloseHotKey = '' })
	s:call('Hide()')
	s:call('Show()')
	t.ok(not keysOn(s, 'Navigation') and not keysOn(s, 'Close'), 'keys on with KeyboardNav=0 and no close key')
	t.clean(s)
	-- DebugLog: the keys are logged only while the launcher has them
	s = opened({ DebugLog = 1 })
	has = {}
	for _, line in ipairs(keyLines(s)) do has[line] = true end
	t.ok(has['log'], 'DebugLog: the keys not logged')
	s:call('Hide()')
	has = {}
	for _, line in ipairs(keyLines(s)) do has[line] = true end
	t.ok(not has['log'], 'DebugLog: the keys logged with the launcher hidden')
	t.clean(s)
end

-- The tiles' hot keys: always listed (TileKeysWhen=Always), or only while the
-- launcher has the focus (Open); none in Grid.inc (no plugin)
function T.tile_hot_keys()
	for _, when in ipairs({ 'Always', 'Open' }) do
		local s = R.new({ settings = { TileKeysWhen = when } })
		local cat = s.data .. 'Categories\\Apps.ini'
		R.writeFile(cat, R.readFile(cat):gsub('(%[Calculator%]\r?\n)', '%1HotKey=CTRL ALT 1\r\n', 1))
		s:start()
		local function listed()
			for _, line in ipairs(keyLines(s)) do
				if line == 'CTRL ALT 1|down|Raintile|TileHotKey(1)' then return true end
			end
			return false
		end
		s:call('Hide()')
		t.eq(listed(), when == 'Always', when .. ': the tile key with the launcher hidden')
		s:call('Show()')
		t.ok(listed(), when .. ': no tile key with the launcher open')
		s:call('FocusLost()')
		t.eq(listed(), when == 'Always', when .. ': the tile key without the focus')
		t.ok(not (R.readFile(s.resources .. 'Generated\\Grid.inc') or ''):find('Plugin=HotKey', 1, true), 'a HotKey measure in Grid.inc')
		t.clean(s)
	end
end

-- An update that copied the new files over the old ones left the key
-- mini-skins of the HotKey plugin: unloaded (one still loaded would fire its
-- keys twice) and deleted
function T.old_key_skins_removed()
	local s = R.new({})
	local ini = s.tmp .. '\\Skins\\Raintile\\Navigation\\Navigation.ini'
	host_mkdir(s.tmp .. '\\Skins\\Raintile\\Navigation')
	R.writeFile(ini, '[Rainmeter]\r\nUpdate=-1\r\n')
	s:start()
	local unloaded = false
	for _, line in ipairs(s.log) do
		if line:find('!DeactivateConfig Raintile\\Navigation', 1, true) then unloaded = true end
	end
	t.ok(unloaded, 'the old Navigation mini-skin was not unloaded')
	t.eq(R.readFile(ini), nil, 'the old Navigation mini-skin is still there')
	t.clean(s)
end

-- On unload (OnCloseAction) no key is left
function T.keys_off_on_unload()
	local s = opened()
	s:call('KeysOff()')
	t.eq(table.concat(keyLines(s), ' / '), 'end', 'keys left after the launcher closed')
	t.clean(s)
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
	t.ok(not keysOn(s, 'Navigation') and not keysOn(s, 'Close'), 'the keys are still on without the focus')
	before = s:upvalue('active')
	s:call("Pad('NextCategory',1)")
	t.eq(s:upvalue('active'), before, 'category after a gamepad button without the focus')
	s:call('FocusGained()')
	t.ok(keysOn(s, 'Navigation') and keysOn(s, 'Close'), 'a click on it did not give the keys back')
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
	t.ok(not keysOn(s, 'Typing'), 'the letters of the search are still on')
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

-- Pad shortcuts of the tiles (PadKey=): written for the helper, one
-- combination per line (the same buttons written two ways: one), and started
-- by Pad('PadTile', <line>) only while the launcher is open with the focus
function T.tile_pad_keys()
	local s = R.new({})
	local cat = s.data .. 'Categories\\Apps.ini'
	R.writeFile(cat, R.readFile(cat) .. '\r\n[Pad one]\r\nCommand=[!SetVariable PadRan one]\r\nPadKey=lb + a\r\n'
		.. '\r\n[Pad two]\r\nCommand=[!SetVariable PadRan two]\r\nPadKey=A LB\r\n'
		.. '\r\n[Pad three]\r\nCommand=[!SetVariable PadRan three]\r\nPadKey=Y X\r\n')
	s:start()
	t.clean(s)
	t.eq(R.readFile(s.resources .. 'Generated\\PadKeys.txt'), 'A LB\r\nX Y\r\n', 'the combinations for the helper')
	s:call('Hide()')
	s:call("Pad('PadTile',2)")
	t.eq(s.vars['padran'], nil, 'a pad shortcut started a tile with the launcher hidden')
	s:call('Show()')
	s:call("Pad('PadTile',2)")
	t.eq(s.vars['padran'], 'three', 'the second combination is not the third tile')
	t.ok(not s:upvalue('visible'), 'the launcher did not hide after the shortcut')
	s:call('Show()')
	s:call("Pad('PadTile',1)")
	t.eq(s.vars['padran'], 'one', 'the first tile with the combination is not the one started')
	-- the Options window open (its flag file): no shortcut acts
	R.writeFile(s.resources .. 'Generated\\OptionsOpen.txt', tostring(os.time()))
	s.vars['padran'] = nil
	s:call('Show()')
	s:call("Pad('PadTile',1)")
	t.eq(s.vars['padran'], nil, 'a pad shortcut acted with Options open')
	s:call('Hide()')
	s:call('Toggle()')
	t.ok(not s:upvalue('visible'), 'the open key opened the launcher with Options open')
	-- one left by a program killed a day ago: ignored
	R.writeFile(s.resources .. 'Generated\\OptionsOpen.txt', tostring(os.time() - 90000))
	s:call('Toggle()')
	t.ok(s:upvalue('visible'), 'an old flag of Options kept the open key off')
	t.clean(s)
end

-- The gamepad's legend (GamepadLegend): it shows with a button of the pad,
-- with the buttons of the settings, what they do there (the keyboard's
-- buttons with it open), and goes with a key or the mouse moving
function T.pad_legend()
	local function legend(s)
		local bg = s.meters['padlegendbg']
		if bg.hidden then return nil end
		local list = {}
		for i = 1, 6 do
			local k = s.meters['padlegendkey' .. i]
			if not k.hidden then list[#list + 1] = k:opt('Text', '') .. '=' .. s.meters['padlegendtext' .. i]:opt('Text', '') end
		end
		return table.concat(list, ' ')
	end
	local s = opened({ GamepadSearch = 'LB Y', GamepadOptions = '' })
	t.eq(legend(s), nil, 'a legend before any button of the pad')
	s:call("Pad('Nav',1,0)")
	t.eq(legend(s), 'A=Launch LB+Y=Search LB / RB=Category B=Close', 'the legend of the grid')
	-- the mouse still (the grid scrolled under it): it stays; moved: it goes
	s:call("HoverTile(1, '10', '10')")
	s:call("Pad('Nav',1,0)")
	s:call("HoverTile(2, '10', '10')")
	t.ok(legend(s) ~= nil, 'a tile coming under the still mouse took the legend away')
	s:call("HoverTile(2, '40', '10')")
	t.eq(legend(s), nil, 'the mouse moved and the legend stayed')
	s:call("Pad('PadSearch')")
	t.eq(legend(s), 'A=Type X=Delete Start=Done B=Close', 'the legend of the on-screen keyboard')
	t.ok(tonumber(s.meters['padlegendbg']:opt('Y', '0')) < tonumber(s.meters['oskbg']:opt('Y', '0')), 'the legend is not over the keyboard')
	s:call("Pad('PadStart')")
	s:call("Pad('Escape')")
	s:call('Nav(1,0)')
	t.eq(legend(s), nil, 'a key of the keyboard and the legend stayed')
	t.clean(s)
	s = opened({ GamepadLegend = '0' })
	s:call("Pad('Nav',1,0)")
	t.eq(legend(s), nil, 'a legend with GamepadLegend=0')
	t.clean(s)
end

-- The tile's menu for the pad (Start on a tile): the entries of the
-- right-click menu, up / down in it, Confirm picks, Back closes it (the
-- launcher stays), another button closes it and acts
function T.pad_tile_menu()
	local s = opened({})
	for i, c in ipairs(s:upvalue('cats')) do
		if c.file == 'Apps.ini' then s:call('SetCategory(' .. i .. ')') end
	end
	s:call("Pad('Nav',0,0)")
	t.clean(s)
	local M, hover = s:upvalue('M'), s:upvalue('hover')
	t.ok(hover.on and hover.idx ~= 0, 'no tile highlighted')
	local tile = s:upvalue('cur')().tiles[hover.idx]
	local function shown()
		local list = {}
		for i = 1, 6 do
			local m = s.meters['metertilemenuitem' .. i]
			if not m.hidden then list[#list + 1] = m:opt('Text', '') end
		end
		return list
	end
	local function legend()
		local out = {}
		for i = 1, 6 do
			local k = s.meters['padlegendkey' .. i]
			if not k.hidden then out[#out + 1] = k:opt('Text', '') .. '=' .. s.meters['padlegendtext' .. i]:opt('Text', '') end
		end
		return table.concat(out, ' ')
	end
	t.eq(#shown(), 0, 'the menu shown before Start')
	t.ok(legend():find('Start=Menu', 1, true), 'the legend without the menu: ' .. legend())
	s:call("Pad('PadStart')")
	t.eq(legend(), 'A=Choose B=Close', 'the legend of the menu')
	local list = shown()
	t.ok(#list >= 2, 'the menu did not open: ' .. #list .. ' entries')
	t.ok(list[1]:find('Edit ' .. tile.name, 1, true), 'the first entry is not Edit: ' .. tostring(list[1]))
	t.eq(#list, #M.tileMenuItems(tile), 'not the entries of the right-click menu')
	t.eq(M.tmenu.sel, 1, 'the first entry not selected')
	s:call("Pad('Nav',0,1)")
	t.eq(M.tmenu.sel, 2, 'down did not move in the menu')
	t.eq(s:upvalue('cur')().tiles[hover.idx], tile, 'down moved the highlight under the menu')
	s:call("Pad('Nav',0,-1)")
	s:call("Pad('Nav',0,-1)")
	t.eq(M.tmenu.sel, #list, 'up from the first entry does not go to the last')
	-- Back: closed, the launcher open
	s:call("Pad('Escape')")
	t.eq(#shown(), 0, 'Back did not close the menu')
	t.ok(s:upvalue('visible'), 'Back on the menu closed the launcher')
	-- Start twice: open and closed
	s:call("Pad('PadStart')")
	s:call("Pad('PadStart')")
	t.eq(#shown(), 0, 'Start again did not close the menu')
	-- another button: closed, and it acts
	local active = s:upvalue('active')
	s:call("Pad('PadStart')")
	s:call("Pad('NextCategory',1)")
	t.eq(#shown(), 0, 'the next category kept the menu')
	t.ok(s:upvalue('active') ~= active, 'the next category did not move')
	-- Confirm on Edit: the tile goes to Options, nothing launched
	s:call("Pad('NextCategory',-1)")
	s:call("Pad('Nav',0,0)")
	tile = s:upvalue('cur')().tiles[hover.idx]
	os.remove(s.resources .. 'Generated\\EditTile.txt')
	s:call("Pad('PadStart')")
	s:call("Pad('Confirm')")
	t.eq(#shown(), 0, 'the menu stayed after a pick')
	t.ok(not s:upvalue('launching'), 'Confirm on the menu launched the tile')
	t.eq(R.readFile(s.resources .. 'Generated\\EditTile.txt'), tile.file .. '|' .. tile.name, 'Edit did not reach Options')
	t.clean(s)
end

return T
