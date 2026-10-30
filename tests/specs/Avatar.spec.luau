--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Avatar = Loader.load("src/ReplicatedStorage/Shared/Avatar")
local Appearance = Loader.load("src/ReplicatedStorage/Content/Appearance")
local Classes = Loader.load("src/ReplicatedStorage/Content/Classes")
local Heritages = Loader.load("src/ReplicatedStorage/Content/Heritages")
local Names = Loader.load("src/ReplicatedStorage/Content/Names")
local Skills = Loader.load("src/ReplicatedStorage/Content/Skills").ById

local function with(changes: { [string]: string }): { [string]: string }
	local creation = Avatar.DefaultCreation("mage")
	for key, value in changes do
		creation[key] = value
	end
	return creation
end

return {
	["every hair and beard style has an asset for every hair colour"] = function()
		for _, list in { Appearance.Hair, Appearance.FacialHair } do
			for _, id in list.Order do
				local style = list.ById[id]
				for _, color in Appearance.HairColors.Order do
					local asset = style.assets[color]
					if id == "none" then
						Expect.equal(asset, nil, `{id} has no assets`)
					else
						Expect.truthy(type(asset) == "number" and asset > 0, `{id} {color}`)
					end
				end
			end
		end
	end,
	["outfits are shirt and pants pairs and genders have a face"] = function()
		for _, id in Appearance.Outfits.Order do
			local outfit = Appearance.Outfits.ById[id]
			Expect.truthy(outfit.shirt > 0 and outfit.pants > 0, id)
		end
		Expect.truthy(#Appearance.SkinTones.Order > 1, "skin tones")
		for _, id in Appearance.Genders.Order do
			Expect.truthy(Appearance.Genders.ById[id].face > 0, id)
			Expect.truthy(#Names[id] > 0, `{id} names`)
		end
	end,
	["the default look and creation are valid for every class"] = function()
		Expect.truthy(Avatar.ValidateLook(Appearance.Default))
		for _, classId in Classes.Order do
			local ok, reason = Avatar.ValidateCreation(Avatar.DefaultCreation(classId))
			Expect.truthy(ok, `{classId}: {reason}`)
		end
	end,
	["fields resolve the hair colour for both hair and beard"] = function()
		local fields = Avatar.Fields({
			gender = "female",
			skinTone = "deep",
			hair = "ponytail",
			hairColor = "red",
			facialHair = "stubble",
			outfit = "hunter",
		})
		Expect.equal(fields.HairAccessory, tostring(Appearance.Hair.ById.ponytail.assets.red))
		Expect.equal(fields.FaceAccessory, tostring(Appearance.FacialHair.ById.stubble.assets.red))
		Expect.equal(fields.Face, Appearance.Genders.ById.female.face)
		Expect.equal(fields.Shirt, Appearance.Outfits.ById.hunter.shirt)
		local bare = Avatar.Fields(Appearance.Default)
		Expect.equal(bare.FaceAccessory, "")
	end,
	["starter spells are Tier 0 or 1 from the class list and martial classes have none"] = function()
		Expect.equal(#Avatar.StarterSpells("fighter"), 0)
		for _, classId in { "mage", "healer" } do
			local spells = Avatar.StarterSpells(classId)
			Expect.truthy(#spells > 0, classId)
			for _, spellId in spells do
				Expect.truthy(table.find(Classes.ById[classId].spellList, spellId), spellId)
				Expect.truthy((Skills[spellId].tier or 0) <= 1, spellId)
			end
		end
	end,
	["rejects locked heritages, foreign names, unknown looks and wrong spells"] = function()
		local locked
		for _, id in Heritages.Order do
			if not Heritages.ById[id].playable then
				locked = id
				break
			end
		end
		Expect.equal(select(2, Avatar.ValidateCreation(with({ heritage = locked }))), "HeritageLocked")
		Expect.equal(select(2, Avatar.ValidateCreation(with({ name = "Nobody" }))), "BadName")
		Expect.equal(select(2, Avatar.ValidateCreation(with({ name = Names.female[1] }))), "BadName")
		Expect.equal(select(2, Avatar.ValidateCreation(with({ hair = "mohawk" }))), "BadLook")
		Expect.equal(select(2, Avatar.ValidateCreation(with({ skinTone = "green" }))), "BadLook")
		Expect.equal(select(2, Avatar.ValidateCreation(with({ classId = "paladin" }))), "UnknownClass")
		Expect.equal(select(2, Avatar.ValidateCreation(with({ spellId = "" }))), "NeedSpell")
		Expect.equal(select(2, Avatar.ValidateCreation(with({ spellId = "mend" }))), "NeedSpell")
		local fighter = Avatar.DefaultCreation("fighter")
		fighter.spellId = "light"
		Expect.equal(select(2, Avatar.ValidateCreation(fighter)), "NotOnClassList")
	end,
	["rejects non-table and non-string input"] = function()
		Expect.equal(Avatar.ValidateCreation(nil), false)
		Expect.equal(Avatar.ValidateCreation("mage"), false)
		local bad: any = with({})
		bad.gender = 5
		Expect.equal(Avatar.ValidateCreation(bad), false)
	end,
}
