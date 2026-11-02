--!strict

-- 3 x 5 bitmap font for map preview labels.
local Font = {}

local GLYPHS: { [string]: string } = {
	a = "010101111101101",
	b = "110101110101110",
	c = "011100100100011",
	d = "110101101101110",
	e = "111100110100111",
	f = "111100110100100",
	g = "011100101101011",
	h = "101101111101101",
	i = "111010010010111",
	j = "001001001101010",
	k = "101101110101101",
	l = "100100100100111",
	m = "101111111101101",
	n = "110101101101101",
	o = "010101101101010",
	p = "110101110100100",
	q = "010101101110011",
	r = "110101110101101",
	s = "011100010001110",
	t = "111010010010010",
	u = "101101101101111",
	v = "101101101101010",
	w = "101101111111101",
	x = "101101010101101",
	y = "101101010010010",
	z = "111001010100111",
	["-"] = "000000111000000",
	["0"] = "111101101101111",
	["1"] = "010110010010111",
	["2"] = "110001010100111",
	["3"] = "110001010001110",
	["4"] = "101101111001001",
	["5"] = "111100110001110",
	["6"] = "011100111101111",
	["7"] = "111001010010010",
	["8"] = "111101111101111",
	["9"] = "111101111001110",
	["+"] = "000010111010000",
}

export type Put = (x: number, y: number, color: { number }, alpha: number?) -> ()

--[=[ Draws `text` centred on `cx` with its top at `cy`, two pixels per font pixel. ]=]
function Font.label(put: Put, text: string, cx: number, cy: number, color: { number })
	local size = 2
	local x = cx - (#text * 4 * size) // 2
	for n = 1, #text do
		local glyph = GLYPHS[string.sub(text, n, n)]
		if glyph then
			for gy = 0, 4 do
				for gx = 0, 2 do
					if string.sub(glyph, gy * 3 + gx + 1, gy * 3 + gx + 1) == "1" then
						for sy = 0, size - 1 do
							for sx = 0, size - 1 do
								put(x + gx * size + sx, cy + gy * size + sy, color)
							end
						end
					end
				end
			end
		end
		x += 4 * size
	end
end

return Font
