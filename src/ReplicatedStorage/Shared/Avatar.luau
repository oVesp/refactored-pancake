--!strict

local Content = script.Parent.Parent.Content
local Appearance = require(Content.Appearance)
local Classes = require(Content.Classes)
local Heritages = require(Content.Heritages)
local Names = require(Content.Names)
local Skills = require(Content.Skills)
local Tuning = require(Content.Tuning)
local Formulas = require(script.Parent.Formulas)

--[=[
	Character creation rules shared by the creator screen and the server
	(docs/systems/character-creation.md). Validation is pure, so Lune tests cover it; only
	`Build` touches the engine.
]=]
local Avatar = {}

export type Look = {
	gender: string,
	hair: string,
	hairColor: string,
	facialHair: string,
	outfit: string,
}

--[=[ Everything the creator sends. `spellId` is `""` for a class with no spell pick. ]=]
export type Creation = {
	name: string,
	heritage: string,
	gender: string,
	hair: string,
	hairColor: string,
	facialHair: string,
	outfit: string,
	classId: string,
	spellId: string,
}

--[=[ Plain HumanoidDescription fields for a look; blocky R15 body parts stay at 0. ]=]
export type Fields = {
	Face: number,
	HairAccessory: string,
	FaceAccessory: string,
	Shirt: number,
	Pants: number,
	HeightScale: number,
	WidthScale: number,
	DepthScale: number,
	HeadScale: number,
}

local LOOK_KEYS = { "gender", "hair", "hairColor", "facialHair", "outfit" }
local CREATION_KEYS = { "name", "heritage", "classId", "spellId" }
local MAX_FIELD_LENGTH = 40

local function isField(value: any): boolean
	return type(value) == "string" and #value <= MAX_FIELD_LENGTH
end

--[=[ True when every look field names existing content. Returns a reason code otherwise. ]=]
function Avatar.ValidateLook(look: any): (boolean, string?)
	if type(look) ~= "table" then
		return false, "BadLook"
	end
	for _, key in LOOK_KEYS do
		if not isField(look[key]) then
			return false, "BadLook"
		end
	end
	if
		not Appearance.Genders.ById[look.gender]
		or not Appearance.Hair.ById[look.hair]
		or not Appearance.HairColors.ById[look.hairColor]
		or not Appearance.FacialHair.ById[look.facialHair]
		or not Appearance.Outfits.ById[look.outfit]
	then
		return false, "BadLook"
	end
	return true, nil
end

--[=[ Copies only the look fields out of a creation or a stored appearance. ]=]
function Avatar.LookOf(source: { [string]: any }): Look
	return {
		gender = source.gender,
		hair = source.hair,
		hairColor = source.hairColor,
		facialHair = source.facialHair,
		outfit = source.outfit,
	}
end

local function styleAsset(style: Appearance.StyleDef, color: string): string
	local id = style.assets[color]
	return if id then tostring(id) else ""
end

--[=[ Resolves a valid look to HumanoidDescription field values. ]=]
function Avatar.Fields(look: Look): Fields
	local gender = Appearance.Genders.ById[look.gender]
	local outfit = Appearance.Outfits.ById[look.outfit]
	return {
		Face = gender.face,
		HairAccessory = styleAsset(Appearance.Hair.ById[look.hair], look.hairColor),
		FaceAccessory = styleAsset(Appearance.FacialHair.ById[look.facialHair], look.hairColor),
		Shirt = outfit.shirt,
		Pants = outfit.pants,
		HeightScale = gender.heightScale,
		WidthScale = gender.widthScale,
		DepthScale = gender.depthScale,
		HeadScale = gender.headScale,
	}
end

--[=[ Builds a HumanoidDescription for a valid look, with the shared skin tone. ]=]
function Avatar.Build(look: Look): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	for key, value in Avatar.Fields(look) :: { [string]: any } do
		(description :: any)[key] = value
	end
	local skin = Appearance.SkinColor
	description.HeadColor = skin
	description.TorsoColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.LeftLegColor = skin
	description.RightLegColor = skin
	return description
end

--[=[ The would-be build path of a new character that starts in `classId`. ]=]
local function starterPath(classId: string): { Formulas.ClassEntry }
	return { { id = classId, level = 1 } }
end

--[=[ Spells a new character of this class may pick at level 1, in class list order. ]=]
function Avatar.StarterSpells(classId: string): { string }
	local def = Classes.ById[classId]
	local spells = {}
	if not def then
		return spells
	end
	local path = starterPath(classId)
	for _, spellId in def.spellList do
		if Formulas.CanLearnSpell(path, {}, spellId, Classes.ById, Skills.ById, Tuning.Magic) then
			table.insert(spells, spellId)
		end
	end
	return spells
end

--[=[
	Checks a creation sent by a client: known playable heritage, valid look, a name from the
	placeholder list for that gender, a starter class, and exactly one starter spell when the
	class has any. Returns false and a reason code otherwise.
]=]
function Avatar.ValidateCreation(creation: any): (boolean, string?)
	if type(creation) ~= "table" then
		return false, "BadCreation"
	end
	for _, key in CREATION_KEYS do
		if not isField(creation[key]) then
			return false, "BadCreation"
		end
	end
	local lookOk, lookReason = Avatar.ValidateLook(creation)
	if not lookOk then
		return false, lookReason
	end
	local heritage = Heritages.ById[creation.heritage]
	if not heritage or not heritage.playable then
		return false, "HeritageLocked"
	end
	local names = (Names :: any)[creation.gender]
	if not names or not table.find(names, creation.name) then
		return false, "BadName"
	end
	if not table.find(Classes.Order, creation.classId) then
		return false, "UnknownClass"
	end
	local spells = Avatar.StarterSpells(creation.classId)
	if #spells == 0 then
		return creation.spellId == "", if creation.spellId == "" then nil else "NotOnClassList"
	end
	if not table.find(spells, creation.spellId) then
		return false, "NeedSpell"
	end
	return true, nil
end

--[=[ A complete valid creation: the default look, the first name and the first class and spell. ]=]
function Avatar.DefaultCreation(classId: string?): Creation
	local look = Appearance.Default
	local class = classId or Classes.Order[1]
	local names = (Names :: any)[look.gender]
	return {
		name = names[1],
		heritage = Heritages.Default,
		gender = look.gender,
		hair = look.hair,
		hairColor = look.hairColor,
		facialHair = look.facialHair,
		outfit = look.outfit,
		classId = class,
		spellId = Avatar.StarterSpells(class)[1] or "",
	}
end

return table.freeze(Avatar)
