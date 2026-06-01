local json = {}

local function parse_error(str, pos, msg)
	error(string.format("json parse error at byte %d: %s", pos, msg), 0)
end

local function skip_space(str, pos)
	while true do
		local char = str:sub(pos, pos)
		if char ~= " " and char ~= "\n" and char ~= "\r" and char ~= "\t" then
			return pos
		end
		pos = pos + 1
	end
end

local parse_value

local escapes = {
	['"'] = '"',
	["\\"] = "\\",
	["/"] = "/",
	b = "\b",
	f = "\f",
	n = "\n",
	r = "\r",
	t = "\t",
}

local function parse_string(str, pos)
	pos = pos + 1
	local out = {}

	while pos <= #str do
		local char = str:sub(pos, pos)
		if char == '"' then
			return table.concat(out), pos + 1
		end

		if char == "\\" then
			local next_char = str:sub(pos + 1, pos + 1)
			if next_char == "u" then
				parse_error(str, pos, "unicode escapes are not supported")
			end
			local escaped = escapes[next_char]
			if not escaped then
				parse_error(str, pos, "invalid string escape")
			end
			table.insert(out, escaped)
			pos = pos + 2
		else
			table.insert(out, char)
			pos = pos + 1
		end
	end

	parse_error(str, pos, "unterminated string")
end

local function parse_number(str, pos)
	local start = pos
	local char = str:sub(pos, pos)

	if char == "-" then
		pos = pos + 1
	end

	while str:sub(pos, pos):match("%d") do
		pos = pos + 1
	end

	if str:sub(pos, pos) == "." then
		pos = pos + 1
		while str:sub(pos, pos):match("%d") do
			pos = pos + 1
		end
	end

	char = str:sub(pos, pos)
	if char == "e" or char == "E" then
		pos = pos + 1
		char = str:sub(pos, pos)
		if char == "+" or char == "-" then
			pos = pos + 1
		end
		while str:sub(pos, pos):match("%d") do
			pos = pos + 1
		end
	end

	local value = tonumber(str:sub(start, pos - 1))
	if value == nil then
		parse_error(str, start, "invalid number")
	end

	return value, pos
end

local function parse_array(str, pos)
	pos = skip_space(str, pos + 1)
	local out = {}

	if str:sub(pos, pos) == "]" then
		return out, pos + 1
	end

	while true do
		local value
		value, pos = parse_value(str, pos)
		table.insert(out, value)

		pos = skip_space(str, pos)
		local char = str:sub(pos, pos)
		if char == "]" then
			return out, pos + 1
		end
		if char ~= "," then
			parse_error(str, pos, "expected ',' or ']'")
		end
		pos = skip_space(str, pos + 1)
	end
end

local function parse_object(str, pos)
	pos = skip_space(str, pos + 1)
	local out = {}

	if str:sub(pos, pos) == "}" then
		return out, pos + 1
	end

	while true do
		if str:sub(pos, pos) ~= '"' then
			parse_error(str, pos, "expected object key")
		end

		local key
		key, pos = parse_string(str, pos)
		pos = skip_space(str, pos)

		if str:sub(pos, pos) ~= ":" then
			parse_error(str, pos, "expected ':'")
		end

		out[key], pos = parse_value(str, skip_space(str, pos + 1))
		pos = skip_space(str, pos)

		local char = str:sub(pos, pos)
		if char == "}" then
			return out, pos + 1
		end
		if char ~= "," then
			parse_error(str, pos, "expected ',' or '}'")
		end
		pos = skip_space(str, pos + 1)
	end
end

function parse_value(str, pos)
	pos = skip_space(str, pos)
	local char = str:sub(pos, pos)

	if char == '"' then
		return parse_string(str, pos)
	end
	if char == "{" then
		return parse_object(str, pos)
	end
	if char == "[" then
		return parse_array(str, pos)
	end
	if char == "-" or char:match("%d") then
		return parse_number(str, pos)
	end
	if str:sub(pos, pos + 3) == "true" then
		return true, pos + 4
	end
	if str:sub(pos, pos + 4) == "false" then
		return false, pos + 5
	end
	if str:sub(pos, pos + 3) == "null" then
		return nil, pos + 4
	end

	parse_error(str, pos, "unexpected value")
end

function json.decode(str)
	local value, pos = parse_value(str, 1)
	pos = skip_space(str, pos)
	if pos <= #str then
		parse_error(str, pos, "trailing content")
	end
	return value
end

return json
