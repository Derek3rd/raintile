-- Sounds (Sounds=1): Rainmeter's !Play for what happens on screen, each
-- event with its switch; Raintile's own .wav or the user's in Sounds\ of
-- the data folder.
local R = require('rainmeter')
local t = require('t')

local T = {}

-- the sounds played since the last call: { 'open', 'move', ... }
local function played(s)
	local list = {}
	for k = (s.heard or 0) + 1, #s.log do
		local f = s.log[k]:match('^!Play (.+)$')
		if f then list[#list + 1] = f:match('([%w]+)%.wav$') or f end
	end
	s.heard = #s.log
	return table.concat(list, ' ')
end

-- open, on a category with tiles (Apps)
local function opened(settings)
	local s = R.new({ settings = settings }):start()
	t.clean(s)
	s:call('Hide()')
	s:call('Show()')
	for i, c in ipairs(s:upvalue('cats')) do
		if c.file == 'Apps.ini' then s:call('SetCategory(' .. i .. ')') end
	end
	played(s)
	return s
end

function T.silent_by_default()
	local s = opened({})
	s:call('Nav(1, 0)')
	s:call('Hide()')
	t.eq(played(s), '', 'a sound with Sounds=0')
	t.clean(s)
end

function T.the_events()
	local s = opened({ Sounds = 1, CloseOnLaunch = 1, LaunchAnimation = 0 })
	s:call('NextCategory(1)')
	t.eq(played(s), 'category', 'another category')
	s:call('NextCategory(-1)')
	played(s)
	s:call('Nav(0, 0)')
	s:call('Nav(0, 1)')
	t.ok(played(s):find('move', 1, true), 'the highlight moved without a sound')
	s:call("Pad('PadStart')")
	t.eq(played(s), 'menu', 'the tile menu')
	s:call("Pad('Nav',0,1)")
	t.eq(played(s), 'move', 'a move in the menu')
	s:call('Escape()')
	t.eq(played(s), 'back', 'the menu closed')
	t.ok(s:upvalue('visible'), 'Esc on the menu closed the launcher')
	s:call('Escape()')
	t.eq(played(s), 'close', 'the launcher closed')
	s:call('Show()')
	t.eq(played(s), 'open', 'the launcher opened')
	-- a tile started: its sound, not the closing one after it
	s:call('Nav(0, 0)')
	played(s)
	s:call('Confirm()')
	t.eq(played(s), 'launch', 'a tile started')
	t.clean(s)
end

-- an event off; the mouse only with SoundMouse=1
function T.switches()
	local s = opened({ Sounds = 1, SoundMove = 0 })
	s:call('Nav(0, 0)')
	s:call('Nav(1, 0)')
	t.eq(played(s), '', 'a move with SoundMove=0')
	t.clean(s)
	s = opened({ Sounds = 1 })
	s:call("HoverTile(1, '10', '10')")
	s:call("HoverTile(2, '40', '10')")
	t.eq(played(s), '', 'the mouse moved with a sound, SoundMouse=0')
	t.clean(s)
	s = opened({ Sounds = 1, SoundMouse = 1 })
	s:call("HoverTile(1, '10', '10')")
	s:call("HoverTile(2, '40', '10')")
	t.eq(played(s), 'move move', 'the mouse moved without a sound, SoundMouse=1')
	t.clean(s)
end

-- Raintile's sounds are there; the user's own of the same name instead
function T.files()
	local s = R.new({ settings = { Sounds = 1 } })
	host_mkdir(s.data .. 'Sounds')
	R.writeFile(s.data .. 'Sounds\\move.wav', 'RIFF')
	s:start()
	local M = s:upvalue('M')
	for _, name in ipairs(M.SOUNDS) do
		local f = M.soundFile[name]
		t.ok(f, 'no file for ' .. name)
		if name == 'move' then
			t.eq(f, s.data .. 'Sounds\\move.wav', 'not the user\'s move.wav')
		else
			t.eq(f, s.resources .. 'Sounds\\' .. name .. '.wav', 'not Raintile\'s ' .. name .. '.wav')
			t.ok(R.readFile(f), 'Raintile has no ' .. name .. '.wav')
		end
	end
	t.clean(s)
end

return T
