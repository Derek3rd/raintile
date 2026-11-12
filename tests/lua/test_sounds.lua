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
		-- (Rainmeter's Play command, run as given: no "!")
		local f = s.log[k]:match('^run: Play "(.+)"$')
		if f then
			-- (the event whose file it is)
			local event = f
			for name, file in pairs(s:upvalue('M').soundFile or {}) do
				if file == f then event = name end
			end
			list[#list + 1] = event
		end
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
	local s = opened({ Sounds = 1, SoundMove = '' })
	s:call('Nav(0, 0)')
	s:call('Nav(1, 0)')
	t.eq(played(s), '', 'a move with SoundMove empty')
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

-- Raintile's sounds are there (the defaults of Settings.inc and of the
-- script agree); the user's own of the same name instead; a
-- sound of the user's for another event; a name that is not there: none
function T.files()
	local s = R.new({ settings = { Sounds = 1, SoundKey = 'mine.wav', SoundBack = 'gone.wav', SoundMenu = '..\\..\\x.wav' } })
	host_mkdir(s.data .. 'Sounds')
	R.writeFile(s.data .. 'Sounds\\rollover2.wav', 'RIFF')
	R.writeFile(s.data .. 'Sounds\\mine.wav', 'RIFF')
	s:start()
	local M = s:upvalue('M')
	for _, name in ipairs(M.SOUNDS) do
		local f = M.soundFile[name]
		if name == 'move' then
			t.eq(f, s.data .. 'Sounds\\rollover2.wav', 'not the user\'s rollover2.wav, the default name of move')
		elseif name == 'key' then
			t.eq(f, s.data .. 'Sounds\\mine.wav', 'not the user\'s sound picked for a key')
		elseif name == 'back' then
			t.eq(f, nil, 'a sound for a file that is not there')
		elseif name == 'menu' then
			t.eq(f, nil, 'a path out of the sounds folders taken')
		else
			t.eq(f, s.resources .. 'Sounds\\' .. M.SOUND_DEFAULT[name], 'not Raintile\'s ' .. M.SOUND_DEFAULT[name])
			t.ok(R.readFile(f), 'Raintile has no ' .. M.SOUND_DEFAULT[name])
		end
	end
	-- the defaults of Settings.inc are the script's
	for _, name in ipairs(M.SOUNDS) do
		if name ~= 'key' and name ~= 'back' and name ~= 'menu' then
			t.eq(s.vars['sound' .. name], M.SOUND_DEFAULT[name], 'Settings.inc and the script differ on Sound' .. name)
		end
	end
	t.clean(s)
end

-- Opening or changing category places the highlight (the carousel: on the
-- tile in the middle): no move sound right after, which would cut theirs
-- short (Rainmeter plays one at a time)
function T.no_move_after_open()
	local s = opened({ Sounds = 1, CenterSelection = 1 })
	s:call('Hide()')
	played(s)
	s:call('Show()')
	t.eq(played(s), 'open', 'another sound after the opening one')
	s:call('NextCategory(1)')
	t.eq(played(s), 'category', 'another sound after the category one')
	t.clean(s)
end

return T
