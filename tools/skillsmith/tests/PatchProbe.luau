--!strict
local fs = require("@lune/fs")
local Patcher = require("../core/Patcher")

local src = fs.readFile("src/ReplicatedStorage/Content/Skills.luau")

local ok1, out1 = pcall(Patcher.applyOne, src, { patchKind = "setKey", dataset = "Skills", entry = "strike", field = "windup", valueText = "0.2" })
print("setKey:", ok1, if ok1 then (out1 :: string):find("windup = 0.2", 1, true) ~= nil else out1)

local ok2, out2 = pcall(Patcher.applyOne, src, { patchKind = "setKey", dataset = "Skills", entry = "strike", field = "poiseDamage", valueText = "1.2", anchor = "range" })
print("insert:", ok2, if ok2 then (out2 :: string):find("poiseDamage = 1.2", 1, true) ~= nil else out2)

local ok3, out3 = pcall(Patcher.applyOne, src, { patchKind = "clearKey", dataset = "Skills", entry = "strike", field = "lunge" })
print("clear:", ok3, if ok3 then (out3 :: string):find("lunge = 1.5", 1, true) == nil else out3)

local ok4, out4 = pcall(Patcher.applyOne, src, { patchKind = "appendEntry", dataset = "Skills", entry = "test_new", fields = {
{ key = "id", valueText = '"test_new"' },
{ key = "name", valueText = '"Test New"' },
{ key = "kind", valueText = '"Active"' },
{ key = "source", valueText = '"Dev"' },
{ key = "description", valueText = '"Probe."' },
}})
print("append:", ok4, if ok4 then (out4 :: string):find('id = "test_new"', 1, true) ~= nil else out4)

local sounds = fs.readFile("src/ReplicatedStorage/Content/SkillSounds.luau")
local ok5, out5 = pcall(Patcher.applyOne, sounds, { patchKind = "appendMapEntry", dataset = "SkillSounds", entry = "flame_fan", valueText = "{ swing = \"Fire\" }" })
print("map append new key:", ok5, if ok5 then ((out5 :: string):find("\tflame_fan =", 1, true) ~= nil) else out5)
local ok6, out6 = pcall(Patcher.applyOne, sounds, { patchKind = "setMapValue", dataset = "SkillSounds", entry = "mend", valueText = "{ resolve = \"Heal\" }" })
print("map set:", ok6, if ok6 then ((out6 :: string) ~= "") else out6)

if ok1 then fs.writeFile("/tmp/out_setkey.luau", out1 :: string) end
if ok2 then fs.writeFile("/tmp/out_insert.luau", out2 :: string) end
if ok3 then fs.writeFile("/tmp/out_clear.luau", out3 :: string) end
if ok4 then fs.writeFile("/tmp/out_append.luau", out4 :: string) end
if ok5 then fs.writeFile("/tmp/out_mapappend.luau", out5 :: string) end
if ok6 then fs.writeFile("/tmp/out_mapset.luau", out6 :: string) end
