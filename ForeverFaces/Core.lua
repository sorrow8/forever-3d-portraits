local ADDON, ns = ...
local L = ns.L

-- Forever Faces: living 3D portraits instead of flat pictures.
--
-- The models themselves live in Portraits.lua. This file keeps the settings,
-- answers the slash command and tells the portraits and the window when
-- something changes.

local DEFAULTS = {
	enabled = true,
	units = true,      -- player, target, focus, pet, target of target
	party = true,
	npc = true,        -- quest, gossip, merchant and trainer windows
	background = true, -- dark circle behind the model
	size = 80,         -- model size in a round portrait, percent (70-85)
}

local PREFIX = "|cffebbd61Forever Faces|r: "

local db
local listeners = {}

function ns.Print(msg)
	print(PREFIX .. msg)
end

function ns.OnChange(fn)
	listeners[#listeners + 1] = fn
end

local function Notify()
	for _, fn in ipairs(listeners) do fn() end
end

function ns.DB() return db end
ns.DEFAULTS = DEFAULTS

function ns.SetEnabled(on)
	on = on and true or false
	if db.enabled == on then return end
	db.enabled = on
	ns.Print(on and L.MSG_ON or L.MSG_OFF)
	Notify()
end

function ns.Set(key, value)
	if db[key] == value then return end
	db[key] = value
	Notify()
end

function ns.SetLanguage(code)
	db.language = code
	ns.ApplyLocale(code)
	if ns.RebuildWindow then ns.RebuildWindow() end
end

function ns.Reset()
	local keep = { win = db.win, language = db.language, welcomed = db.welcomed }
	wipe(db)
	for k, v in pairs(DEFAULTS) do db[k] = v end
	for k, v in pairs(keep) do db[k] = v end
	ns.Print(L.MSG_RESET)
	Notify()
end

-- Events ---------------------------------------------------------------------

local frame = CreateFrame("Frame")
local events = {}

function events.ADDON_LOADED(name)
	if name ~= ADDON then return end
	ForeverFacesDB = ForeverFacesDB or {}
	db = ForeverFacesDB
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then db[k] = v end
	end
	ns.ApplyLocale(db.language)
	frame:UnregisterEvent("ADDON_LOADED")
end

function events.PLAYER_LOGIN()
	ns.InitPortraits()
	if ns.InitUI then ns.InitUI() end
	ns.OnChange(ns.ApplyAll)
	-- the first login explains what changed, every later one says how to open the settings
	if not db.welcomed then
		db.welcomed = true
		ns.Print(L.MSG_WELCOME)
	else
		ns.Print(L.MSG_LOADED)
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	local fn = events[event]
	if fn then fn(...) end
end)
for event in pairs(events) do
	frame:RegisterEvent(event)
end

-- Slash command, addon compartment -----------------------------------------

local function Command(msg)
	local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
	if cmd == "" then
		if ns.ToggleWindow then ns.ToggleWindow() end
	elseif cmd == "on" then
		ns.SetEnabled(true)
	elseif cmd == "off" then
		ns.SetEnabled(false)
	elseif cmd == "toggle" then
		ns.SetEnabled(not db.enabled)
	elseif cmd == "lang" and (arg == "auto" or ns.LanguageCode(arg)) then
		ns.SetLanguage(arg ~= "auto" and ns.LanguageCode(arg) or nil)
	elseif cmd == "debug" then
		ns.Debug()
	elseif cmd == "reset" then
		ns.Reset()
	else
		ns.Print(L.MSG_HELP)
	end
end

SLASH_FOREVERFACES1 = "/ff"
SLASH_FOREVERFACES2 = "/foreverfaces"
SlashCmdList.FOREVERFACES = Command

function ForeverFaces_OnCompartmentClick()
	if ns.ToggleWindow then ns.ToggleWindow() end
end
