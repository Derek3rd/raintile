-- The animation clock (Tick): a step sends Rainmeter only what changed.
local R = require('rainmeter')
local t = require('t')

local T = {}

-- No animation left running (the clock of the top row, every minute, is not one)
local function atRest(s)
	local running = s:running()
	t.ok(#running == 0, 'animations still running: ' .. table.concat(running, ', '))
end

-- The launcher shown, at rest (its opening animation over)
local function shown(settings)
	local s = R.new({ settings = settings }):start()
	t.clean(s)
	t.ok(s:upvalue('ready'), 'the launcher is not ready after loading')
	s:call('Hide()')
	s:call('Show()')
	atRest(s)
	return s
end

-- The bangs sent from log entry 'from' on, one list per step of the clock
-- (what came before the first step, the event that started it, is left out)
local function steps(s, from)
	local list, cur = {}, nil
	for i = from + 1, #s.log do
		local line = s.log[i]
		if line:find('MeasureScript Tick(', 1, true) then
			cur = {}
			list[#list + 1] = cur
		elseif cur then
			cur[#cur + 1] = line
		end
	end
	return list
end

local function count(step, bang)
	local n = 0
	for _, line in ipairs(step) do
		if line == bang or line:sub(1, #bang + 1) == bang .. ' ' then n = n + 1 end
	end
	return n
end

-- Bangs of a step that change what is on screen
local function changes(step)
	local n = 0
	for _, bang in ipairs({ '!SetOption', '!ShowMeter', '!HideMeter', '!UpdateMeter', '!UpdateMeterGroup', '!Move', '!SetTransparency' }) do
		n = n + count(step, bang)
	end
	return n
end

-- A category of the menu (with its pill) with tiles, not the active one
local function otherCategory(s)
	local cats, active = s:upvalue('cats'), s:upvalue('active')
	for i, c in ipairs(cats) do
		if i ~= active and c.l and #c.tiles > 2 and not c.widgets then return i end
	end
	error('no other category in the menu')
end

-- The launcher shown on such a category, at rest
local function onCategory(settings)
	local s = shown(settings)
	s:call('SetCategory(' .. otherCategory(s) .. ')')
	atRest(s)
	return s
end

-- The pill of the active category is updated only when it moves: the
-- highlight sliding to a tile leaves it alone (it was updated on every step
-- of any animation, and twice when it moved)
function T.pill_updated_only_when_it_moves()
	local s = onCategory({})
	local cats = s:upvalue('cats')
	t.ok(s:upvalue('pillPos') and cats[s:upvalue('active')].l, 'the active category has no pill')
	local before = #s.log
	s:call('HoverTile(2)')
	local list = steps(s, before)
	t.ok(#list > 1, 'the highlight did not animate')
	for k, step in ipairs(list) do
		t.eq(count(step, '!UpdateMeter CatPillActive'), 0, 'pill updated in step ' .. k .. ' of the highlight')
	end
	-- another category: it slides there, updated once per step, and ends
	-- where the category is
	local other = otherCategory(s)
	before = #s.log
	s:call('SetCategory(' .. other .. ')')
	list = steps(s, before)
	local moved = 0
	for k, step in ipairs(list) do
		local n = count(step, '!UpdateMeter CatPillActive')
		t.ok(n <= 1, 'pill updated ' .. n .. ' times in step ' .. k)
		moved = moved + n
	end
	t.ok(moved > 1, 'the pill did not slide to the new category')
	local pill, V = s.meters['catpillactive'], s:upvalue('V')
	t.eq(pill:GetX(), math.floor(cats[other].l - V.MenuItemPad + 0.5), 'where the pill stopped')
	t.drawn(s, 'category change')
	t.clean(s)
	atRest(s)
end

-- A step that changed nothing draws nothing; one that did still redraws. The
-- clock is kept running with nothing to move (the borders of the Steam
-- updates turning, with no such tile) while the highlight slides and stops.
function T.step_without_changes_does_not_redraw()
	local s = onCategory({})
	local M = s:upvalue('M')
	M.dl.anim, M.dl.f, M.dl.glowFrames = true, 0, 200
	local before = #s.log
	s:call('HoverTile(2)')
	local list = steps(s, before)
	local still, drawn = 0, 0
	for k, step in ipairs(list) do
		if changes(step) == 0 then
			still = still + 1
			t.eq(count(step, '!Redraw'), 0, 'redraws of step ' .. k .. ', which changed nothing')
		else
			drawn = drawn + 1
			t.eq(count(step, '!Redraw'), 1, 'redraws of step ' .. k .. ', which changed something')
		end
	end
	t.ok(drawn > 1, 'the highlight did not animate')
	t.ok(still > 1, 'no step without changes: the test shows nothing')
	t.drawn(s, 'highlight')
	t.clean(s)
	atRest(s)
end

-- Whatever animates, the last thing changed is drawn: scrolling, another
-- category, the highlight coming and going, the keys
local function session(s, what)
	local function did(code)
		s:call(code)
		t.drawn(s, what .. ' ' .. code)
	end
	did('Scroll(1)')
	did('Scroll(-1)')
	did('HoverTile(2)')
	did('HoverTile(3)')
	did('LeaveTile(3)')
	did('Nav(1, 0)')
	did('Nav(0, 1)')
	local cats = s:upvalue('cats')
	for i = 1, #cats do
		did('SetCategory(' .. i .. ')')
		did('Scroll(1)')
		did('HoverTile(1)')
		did('LeaveTile(1)')
	end
	did('NextCategory(1)')
	did('NextCategory(-1)')
	t.clean(s)
	atRest(s)
end

function T.everything_changed_is_drawn_grid()
	session(shown({}), 'grid')
end

function T.everything_changed_is_drawn_without_animations()
	session(shown({ AnimOpen = 0, AnimCategory = 0, AnimHover = 0, AnimScroll = 0 }), 'no animations')
end

function T.everything_changed_is_drawn_carousel()
	session(shown({ ScrollMode = 'Carousel' }), 'carousel')
end

function T.everything_changed_is_drawn_wheel()
	session(shown({ ScrollMode = 'Wheel' }), 'wheel')
	session(shown({ ScrollMode = 'Wheel', WheelMenu = 'Ring' }), 'wheel with the ring')
end

function T.everything_changed_is_drawn_docked()
	session(shown({ LauncherMode = 'Dock', DockSide = 'Left' }), 'docked')
end

-- The play time line of a tile is worked out once, and again when its data
-- changes: a launch, the play time read again
function T.play_time_line_kept_until_its_data_changes()
	local s = shown({ TileInfo = 'Always' })
	local M, cats = s:upvalue('M'), s:upvalue('cats')
	local target
	for i, c in ipairs(cats) do
		if not c.virtual and #c.tiles > 1 and not c.tiles[1].widget then target = i break end
	end
	t.ok(target, 'no category with tiles')
	s:call('SetCategory(' .. target .. ')')
	local tile = cats[target].tiles[1]
	local info = s.meters['tileinfo1']
	t.ok(info.hidden, 'a play time line on a tile never played')
	-- worked out once however many frames are drawn
	local calls, line = 0, M.infoLine
	M.infoLine = function(x)
		calls = calls + 1
		return line(x)
	end
	M.infoReset()
	s:call('HoverTile(1)')
	s:call('HoverTile(2)')
	s:call('LeaveTile(2)')
	local visible = 0
	for slot = 1, s:upvalue('slots') do
		if not s.meters['tile' .. slot].hidden then visible = visible + 1 end
	end
	t.ok(calls > 0 and calls <= visible, 'play time lines worked out ' .. calls .. ' times for ' .. visible .. ' tiles')
	-- Steam's play time arrives (Playtime.ps1): the line is there
	tile.steamId = '480'
	R.writeFile(s.resources .. 'Generated\\Playtime.txt', '480|90|0\n')
	s:call('OnPlaytime()')
	t.ok(not info.hidden, 'no play time line after OnPlaytime()')
	t.eq(info:opt('Text', ''), '1.5 h played', 'play time line')
	R.writeFile(s.resources .. 'Generated\\Playtime.txt', '480|120|0\n')
	s:call('OnPlaytime()')
	t.eq(info:opt('Text', ''), '2 h played', 'play time line after more play')
	t.clean(s)
end

return T
