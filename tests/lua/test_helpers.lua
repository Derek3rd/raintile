-- Small functions of Raintile.lua, reached through the loaded skin.
local R = require('rainmeter')
local t = require('t')

local T = {}

local skin
local function fn(name)
	skin = skin or R.new({}):start()
	return skin:upvalue(name)
end

function T.parse_color()
	local parseColor = fn('parseColor')
	t.eq(parseColor('10,20,30'), '10,20,30,255', 'R,G,B')
	t.eq(parseColor(' 10 , 20 , 30 , 40 '), '10,20,30,40', 'R,G,B,A with spaces')
	t.eq(parseColor('#FF8000'), '255,128,0,255', '#RRGGBB')
	t.eq(parseColor('0x10141CC8'), '16,20,28,200', '0xRRGGBBAA')
	t.eq(parseColor('10141CC8'), '16,20,28,200', 'RRGGBBAA')
	t.eq(parseColor('red'), nil, 'a name')
	t.eq(parseColor('#FFF'), nil, 'short hex')
	t.eq(parseColor(''), nil, 'empty')
end

-- Thumbnail names come from tile names: nothing that leaves the folder
function T.safe_name()
	local safeName = fn('safeName')
	t.eq(safeName('Battle.net'), 'Battle.net', 'a dot is kept')
	t.eq(safeName('a\\b/c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j', 'reserved characters')
	t.ok(not safeName('..\\..\\x'):find('[\\/]'), 'no path separator')
end

function T.split_list()
	local splitList = fn('splitList')
	local list = splitList('Games.ini|Apps.ini||Links.ini')
	t.ok(type(list) == 'table', 'a table')
	t.eq(list[1], 'Games.ini', 'first')
	t.eq(list[#list], 'Links.ini', 'last')
end

function T.formula_fake()
	-- the fake's formulas, which the layout tests rely on
	t.eq(R.parseFormula('(Floor((1920-2*40-(4-1)*16)/4))'), 448, 'tile width')
	t.eq(R.parseFormula('(1 > 0 ? 5 : 6)'), 5, 'conditional')
	t.eq(R.parseFormula('Max(2, Min(9, 4))'), 4, 'functions')
end

function T.zz_cleanup()
	if skin then t.clean(skin) end
	skin = nil
end

return T
