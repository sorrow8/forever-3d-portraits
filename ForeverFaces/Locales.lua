local _, ns = ...

-- English is the base; a locale file (Locales/*.lua) only overrides what it
-- translates. The game's language is used unless one is picked in the
-- window's language menu or with /ff lang.
local L = {
	TITLE = "Forever Faces",

	ENABLED = "Addon enabled",
	ENABLED_HELP = "Off: every portrait is a flat picture again.",

	SHOW_ON = "3D portraits on",
	UNITS = "Player, target, focus and pet",
	UNITS_HELP = "Your own frame, your target, focus, pet and the target of your target.",
	PARTY = "Party frames",
	PARTY_HELP = "The portraits of your party members.",
	NPC = "NPC windows",
	NPC_HELP = "Quest givers, gossip, merchants and trainers you talk to.",
	BACKGROUND = "Dark background",
	BACKGROUND_HELP = "A dark circle behind the model, so it stands out from the frame.",

	SIZE = "Portrait size",
	SIZE_HELP = "How much of the round frame the model fills. Bigger shows more of the face, smaller leaves a wider soft edge.",
	SIZE_PCT = "%d%%",

	RESET = "Reset settings",
	CMD_HINT = "Open this window:",
	LANG_AUTO = "Auto",

	MSG_WELCOME = "installed. Portraits now show living 3D models. Settings: type |cffebbd61/ff|r",
	MSG_LOADED = "loaded. Settings: |cffebbd61/ff|r",
	MSG_ON = "on.",
	MSG_OFF = "off, portraits are flat pictures again.",
	MSG_RESET = "settings reset.",
	MSG_HELP = "/ff: window, /ff on, /ff off, /ff reset, /ff lang auto/en/ru",

	OPTIONS_OPEN = "Open the settings window",
	OPTIONS_TEXT = "Every setting lives in the addon's own window.",
}

ns.LOCALES = {}

-- The language menu.
ns.LANGUAGES = {
	{ code = "enUS", short = "en", name = "English" },
	{ code = "ruRU", short = "ru", name = "Русский" },
}

function ns.LanguageAvailable(lang)
	return not lang.cjk or GetLocale() == lang.code
end

-- "ruRU" or "ru" -> "ruRU"; nil, "auto" or anything unknown -> nil.
function ns.LanguageCode(choice)
	if type(choice) ~= "string" then return nil end
	choice = choice:lower()
	for _, lang in ipairs(ns.LANGUAGES) do
		if choice == lang.short or choice == lang.code:lower() then return lang.code end
	end
end

local EN = {}
for k, v in pairs(L) do EN[k] = v end

-- The game's language as one of ns.LANGUAGES' codes.
function ns.ClientLocale()
	local code = GetLocale()
	if code == "enGB" then return "enUS" end
	return code
end

-- The table stays the same object, so every file holding ns.L sees the change.
function ns.ApplyLocale(choice)
	local code = ns.LanguageCode(choice) or ns.ClientLocale()
	for k, v in pairs(EN) do L[k] = v end
	local over = ns.LOCALES[code]
	if over then
		for k, v in pairs(over) do L[k] = v end
	end
	ns.activeLocale = over and code or "enUS"
end

ns.L = L
