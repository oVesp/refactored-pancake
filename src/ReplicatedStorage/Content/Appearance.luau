--!strict

--[=[
	Character creator looks on the blocky R15 body (docs/systems/character-creation.md). Every
	id is a Marketplace asset applied through HumanoidDescription; ownership is not needed.
	Catalog hair and beards carry baked colours, so each style lists one asset per hair colour
	and the colour is a separate choice. Hair and beards share the hair colour. Outfits are a
	classic Shirt and Pants pair. Ids from third-party creators can be taken down; the audit
	list is in the systems doc.
]=]

export type GenderDef = {
	id: string,
	name: string,
	--[=[ Classic face decal (asset type Face). ]=]
	face: number,
	heightScale: number,
	widthScale: number,
	depthScale: number,
	headScale: number,
}

export type SkinToneDef = {
	id: string,
	name: string,
	--[=[ Body colour of every limb; also the creator swatch. ]=]
	color: Color3,
}

export type HairColorDef = {
	id: string,
	name: string,
	--[=[ Swatch shown in the creator. ]=]
	swatch: Color3,
}

export type StyleDef = {
	id: string,
	name: string,
	--[=[ Hair colour id -> accessory asset id. Empty for the bare style ("none"). ]=]
	assets: { [string]: number },
}

export type OutfitDef = {
	id: string,
	name: string,
	shirt: number,
	pants: number,
}

local GENDERS: { GenderDef } = {
	{
		id = "male",
		name = "Male",
		face = 86487700, -- Man Face (Roblox)
		heightScale = 1,
		widthScale = 1,
		depthScale = 1,
		headScale = 1,
	},
	{
		id = "female",
		name = "Female",
		face = 86487766, -- Woman Face (Roblox)
		heightScale = 0.96,
		widthScale = 0.9,
		depthScale = 0.92,
		headScale = 0.98,
	},
}

local SKIN_TONES: { SkinToneDef } = {
	{ id = "pale", name = "Pale", color = Color3.fromRGB(245, 218, 196) },
	{ id = "fair", name = "Fair", color = Color3.fromRGB(234, 184, 146) },
	{ id = "tan", name = "Tan", color = Color3.fromRGB(204, 148, 104) },
	{ id = "olive", name = "Olive", color = Color3.fromRGB(176, 128, 86) },
	{ id = "brown", name = "Brown", color = Color3.fromRGB(130, 87, 58) },
	{ id = "deep", name = "Deep", color = Color3.fromRGB(86, 58, 40) },
}

local HAIR_COLORS: { HairColorDef } = {
	{ id = "black", name = "Black", swatch = Color3.fromRGB(43, 38, 34) },
	{ id = "brown", name = "Brown", swatch = Color3.fromRGB(107, 74, 47) },
	{ id = "blonde", name = "Blonde", swatch = Color3.fromRGB(216, 180, 106) },
	{ id = "red", name = "Red", swatch = Color3.fromRGB(166, 69, 42) },
}

-- Free Roblox hair, one asset per colour.
local HAIR: { StyleDef } = {
	{ id = "none", name = "Shaved", assets = {} },
	{
		id = "short_sleek",
		name = "Short and Sleek",
		assets = { black = 9243992729, brown = 6993758617, blonde = 9243987340, red = 9243995099 },
	},
	{
		id = "short_fringe",
		name = "Short Fringe",
		assets = { black = 7193401217, brown = 9243976603, blonde = 7193397693, red = 9243983205 },
	},
	{
		id = "side_part",
		name = "Side Part",
		assets = { black = 9244021842, brown = 7193419595, blonde = 7193386173, red = 9244024443 },
	},
	{
		id = "short_curls",
		name = "Short Curls",
		assets = { black = 7193452166, brown = 9244137452, blonde = 9244134513, red = 9244145658 },
	},
	{
		id = "curly_fade",
		name = "Curly Fade",
		assets = { black = 7193405096, brown = 9244010432, blonde = 9244008307, red = 9244014391 },
	},
	{
		id = "top_knot",
		name = "Top Knot",
		assets = { black = 9174354743, brown = 9244060144, blonde = 9244057408, red = 9244064248 },
	},
	{
		id = "surfer",
		name = "Shoulder Length",
		assets = { black = 9174353649, brown = 9244033194, blonde = 9244029916, red = 9244038785 },
	},
	{
		id = "medium_middle",
		name = "Medium Middle Part",
		assets = { black = 9244089488, brown = 7193437847, blonde = 7193424874, red = 9244091757 },
	},
	{
		id = "wavy_middle",
		name = "Wavy Middle Part",
		assets = { black = 9244111257, brown = 7193448258, blonde = 7193445686, red = 9244114211 },
	},
	{
		id = "straight_bangs",
		name = "Straight Bangs",
		assets = { black = 6993754725, brown = 7193449810, blonde = 7193448988, red = 9244122897 },
	},
	{
		id = "ponytail",
		name = "Ponytail",
		assets = { black = 7193442167, brown = 9244097555, blonde = 9244095135, red = 7193444640 },
	},
}

-- Third-party UGC beards (Hairy Business, U8DEV), one asset per colour.
local FACIAL_HAIR: { StyleDef } = {
	{ id = "none", name = "Clean Shaven", assets = {} },
	{
		id = "stubble",
		name = "Stubble",
		assets = { black = 105531815232256, brown = 117472996736909, blonde = 81763820708373, red = 83988144477353 },
	},
	{
		id = "well_kept",
		name = "Well Kept",
		assets = { black = 97197321204898, brown = 83214730676773, blonde = 76244256918432, red = 94953973435148 },
	},
	{
		id = "gentleman",
		name = "Trimmed Full Beard",
		assets = { black = 106039417083967, brown = 95504368800777, blonde = 96223013735984, red = 136254240898607 },
	},
	{
		id = "great_beard",
		name = "Great Beard",
		assets = { black = 72775095656198, brown = 108705374974944, blonde = 72779660483881, red = 139023718435438 },
	},
}

-- Third-party UGC classic clothing (po_or, [ATF] The Ravagers), shirt and pants as a pair.
local OUTFITS: { OutfitDef } = {
	{ id = "farmhand", name = "Farmhand's Tunic", shirt = 102040885645455, pants = 102771493655192 },
	{ id = "woodsman", name = "Woodsman's Tunic", shirt = 92491115349196, pants = 75543452319439 },
	{ id = "river", name = "Riverfolk Tunic", shirt = 80240532692947, pants = 130299064771261 },
	{ id = "ember", name = "Ember Tunic", shirt = 77317482485147, pants = 111625671162502 },
	{ id = "nightwatch", name = "Nightwatch Tunic", shirt = 110028263310915, pants = 107269052225218 },
	{ id = "dusk", name = "Dusk Tunic", shirt = 120873388095008, pants = 76366414622687 },
	{ id = "villager", name = "Villager's Garb", shirt = 595225271, pants = 595223818 },
	{ id = "cloaked", name = "Cloaked Wanderer", shirt = 527443201, pants = 527441008 },
	{ id = "hunter", name = "Hunter's Leathers", shirt = 693099122, pants = 693090947 },
}

local function index(list: { any }): ({ [string]: any }, { string })
	local byId = {}
	local order = {}
	for _, def in list do
		byId[def.id] = table.freeze(def)
		table.insert(order, def.id)
	end
	return table.freeze(byId), table.freeze(order)
end

local gendersById: { [string]: GenderDef }, genderOrder = index(GENDERS)
local skinById: { [string]: SkinToneDef }, skinOrder = index(SKIN_TONES)
local colorsById: { [string]: HairColorDef }, colorOrder = index(HAIR_COLORS)
local hairById: { [string]: StyleDef }, hairOrder = index(HAIR)
local facialById: { [string]: StyleDef }, facialOrder = index(FACIAL_HAIR)
local outfitsById: { [string]: OutfitDef }, outfitOrder = index(OUTFITS)

return table.freeze({
	Genders = table.freeze({ ById = gendersById, Order = genderOrder }),
	SkinTones = table.freeze({ ById = skinById, Order = skinOrder }),
	HairColors = table.freeze({ ById = colorsById, Order = colorOrder }),
	Hair = table.freeze({ ById = hairById, Order = hairOrder }),
	FacialHair = table.freeze({ ById = facialById, Order = facialOrder }),
	Outfits = table.freeze({ ById = outfitsById, Order = outfitOrder }),
	Default = table.freeze({
		gender = "male",
		skinTone = "fair",
		hair = "short_fringe",
		hairColor = "brown",
		facialHair = "none",
		outfit = "farmhand",
	}),
})
