--!strict

-- Minimal RGB PNG encoder for the world map preview (zlib from @lune/serde).
local serde = require("@lune/serde")

local Png = {}

local CRC_TABLE: { number } = {}
for n = 0, 255 do
	local c = n
	for _ = 1, 8 do
		if bit32.band(c, 1) == 1 then
			c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
		else
			c = bit32.rshift(c, 1)
		end
	end
	CRC_TABLE[n + 1] = c
end

local function crc32(data: string): number
	local c = 0xFFFFFFFF
	for i = 1, #data do
		c = bit32.bxor(CRC_TABLE[bit32.band(bit32.bxor(c, string.byte(data, i)), 0xFF) + 1], bit32.rshift(c, 8))
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end

local function chunk(kind: string, data: string): string
	return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
end

--[=[ Encodes `pixels` (a buffer of width * height * 3 bytes, row-major RGB) as a PNG file. ]=]
function Png.encode(width: number, height: number, pixels: buffer): string
	local rows = buffer.create((width * 3 + 1) * height)
	for y = 0, height - 1 do
		local o = y * (width * 3 + 1)
		buffer.writeu8(rows, o, 0)
		buffer.copy(rows, o + 1, pixels, y * width * 3, width * 3)
	end
	local header = string.pack(">I4I4BBBBB", width, height, 8, 2, 0, 0, 0)
	return "\137PNG\r\n\26\n"
		.. chunk("IHDR", header)
		.. chunk("IDAT", serde.compress("zlib", buffer.tostring(rows)))
		.. chunk("IEND", "")
end

return Png
