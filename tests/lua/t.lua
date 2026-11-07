-- Assertions for the Lua tests.
local t = {}

local function show(v)
	if type(v) == 'string' then return string.format('%q', v) end
	return tostring(v)
end

function t.eq(actual, expected, what)
	if actual ~= expected then
		error((what or 'value') .. ': expected ' .. show(expected) .. ', got ' .. show(actual), 2)
	end
end

function t.ok(cond, what)
	if not cond then error(what or 'condition not met', 2) end
end

-- The skin logged nothing Rainmeter would call an error, and broke none of
-- the project's rules (see rainmeter.lua).
function t.clean(skin)
	if #skin.errors > 0 then
		local list = {}
		for k = 1, math.min(#skin.errors, 8) do list[k] = '  ' .. skin.errors[k] end
		if #skin.errors > 8 then list[#list + 1] = '  ... and ' .. (#skin.errors - 8) .. ' more' end
		error(#skin.errors .. ' error(s):\n' .. table.concat(list, '\n'), 2)
	end
end

-- No timer left running: at rest the skin uses no CPU.
function t.atRest(skin)
	local list = {}
	for _, timer in ipairs(skin.timers) do list[#list + 1] = timer.measure.name .. ' ' .. timer.list end
	if #list > 0 then error('timers still running: ' .. table.concat(list, ', '), 2) end
end

return t
