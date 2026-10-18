local ADDON, ns = ...

-- The game draws a portrait by handing a texture and a unit to
-- SetPortraitTexture. That call is hooked: each portrait texture gets one
-- PlayerModel of its own, laid over the texture, and the flat picture is made
-- invisible while the model shows.
--
-- On Forever every portrait that matters is round: the unit frames, the party
-- frames and the portrait of a quest, gossip, merchant or trainer window are
-- all masked to a circle and framed by ring art. Models can't be masked: a
-- model is a square and would show a straight edge across the circle. So a
-- round portrait gets the model in the square that fits inside the circle, a
-- dark disc behind it and a soft dark fade over its edges (both textures,
-- which can be masked to the circle).
--
-- The flat picture comes back whenever the model can't be shown: the unit is
-- gone or out of sight, the model has not loaded, the game put a plain
-- picture on the texture (book icon, class icon), or the part is switched off.
-- State is kept in local tables keyed by texture, nothing is written onto
-- Blizzard frames.

local MIN_SIZE = 30     -- smaller portraits stay flat
local ROUND_FILL = 0.70 -- model size inside a round portrait: its corners stay inside the circle
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FADE = "Interface\\AddOns\\" .. ADDON .. "\\media\\fade"
local DARK = { 0.04, 0.04, 0.06, 1 }
local LOAD_CHECK = 0.25 -- seconds; a cached model may never fire OnModelLoaded

local entries = {} -- [texture] = { unit, alpha, round, model, backdrop, cover, dirty, shown }
local pending = {} -- [texture] = true, waiting for combat to end
local hooked = {}

local function DB() return ns.DB() end

local function Category(unit)
	unit = unit:lower()
	if unit == "npc" or unit == "questnpc" then return "npc" end
	if unit:find("^party") or unit:find("^raid") then return "party" end
	return "units"
end

local function BigEnough(texture)
	local w, h = texture:GetSize()
	return w and h and math.min(w, h) >= MIN_SIZE
end

local function Wanted(texture, e)
	local db = DB()
	if not db or not db.enabled or not e.unit then return false end
	if not db[Category(e.unit)] then return false end
	if not texture:IsShown() or not BigEnough(texture) then return false end
	return UnitExists(e.unit) and UnitIsVisible(e.unit)
end

local function Loaded(model)
	if not model.GetModelFileID then return true end
	local id = model:GetModelFileID()
	return id ~= nil and id ~= 0
end

-- Showing --------------------------------------------------------------------------

local function Flat(texture)
	local e = entries[texture]
	if not e then return end
	if e.model then
		e.model:SetAlpha(0)
		e.model:Hide()
		e.backdrop:Hide()
		if e.cover then e.cover:Hide() end
	end
	e.shown = false
	texture:SetAlpha(e.alpha)
end

local function Show3D(texture)
	local e = entries[texture]
	e.model:SetAlpha(1)
	e.backdrop:SetShown(DB().background)
	if e.cover then e.cover:SetShown(DB().background) end
	texture:SetAlpha(0)
	e.shown = true
end

local function Layout(texture, e)
	local model = e.model
	model:ClearAllPoints()
	if e.round then
		local w, h = texture:GetSize()
		local side = math.min(w, h) * ROUND_FILL
		model:SetPoint("CENTER", texture, "CENTER")
		model:SetSize(side, side)
	else
		model:SetAllPoints(texture)
	end
end

local function Build(texture, e)
	local parent = texture:GetParent()
	local model = CreateFrame("PlayerModel", nil, parent)
	model:SetAlpha(0)
	model:Hide()
	model:SetScript("OnModelLoaded", function()
		local entry = entries[texture]
		if entry and Wanted(texture, entry) then Show3D(texture) end
	end)

	local layer, sub = texture:GetDrawLayer()
	local backdrop = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
	backdrop:SetAllPoints(texture)
	backdrop:SetColorTexture(DARK[1], DARK[2], DARK[3], DARK[4])
	backdrop:Hide()
	if e.round then
		local mask = parent:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(texture)
		backdrop:AddMaskTexture(mask)

		-- above the model: fades its square edges into the dark disc
		local cover = CreateFrame("Frame", nil, model)
		cover:SetAllPoints(texture)
		cover:SetFrameLevel(model:GetFrameLevel() + 1)
		local fade = cover:CreateTexture(nil, "OVERLAY")
		fade:SetAllPoints()
		fade:SetTexture(FADE)
		fade:SetVertexColor(DARK[1], DARK[2], DARK[3], DARK[4])
		local coverMask = cover:CreateMaskTexture()
		coverMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		coverMask:SetAllPoints(texture)
		fade:AddMaskTexture(coverMask)
		cover:Hide()
		e.cover = cover
	end

	e.model, e.backdrop = model, backdrop
end

local function Refresh(texture)
	local e = entries[texture]
	if not e then return end
	if not Wanted(texture, e) then
		Flat(texture)
		return
	end

	if not e.model then
		local parent = texture:GetParent()
		if InCombatLockdown() and parent:IsProtected() then
			pending[texture] = true
			Flat(texture)
			return
		end
		Build(texture, e)
		e.dirty = true
	end

	Layout(texture, e)
	local model = e.model
	model:Show()
	if e.dirty then
		e.dirty = false
		model:SetUnit(e.unit)
		model:SetPortraitZoom(1)
		model:SetCamDistanceScale(1)
		model:SetPosition(0, 0, 0)
	end

	if Loaded(model) then
		Show3D(texture)
	elseif not e.shown then
		-- keep the flat picture until the model is there
		C_Timer.After(LOAD_CHECK, function()
			local entry = entries[texture]
			if entry and entry.model and Wanted(texture, entry) and Loaded(entry.model) then
				Show3D(texture)
			end
		end)
	end
end

-- Hooks ---------------------------------------------------------------------------------

local function Hook(texture)
	if hooked[texture] then return end
	hooked[texture] = true

	-- the game put a plain picture here (book, class or buyback icon)
	local function Picture()
		local e = entries[texture]
		if e then
			e.unit = nil
			Flat(texture)
		end
	end
	hooksecurefunc(texture, "SetTexture", Picture)
	hooksecurefunc(texture, "SetAtlas", Picture)

	local function Sync() Refresh(texture) end
	hooksecurefunc(texture, "Show", Sync)
	hooksecurefunc(texture, "Hide", Sync)
	hooksecurefunc(texture, "SetShown", Sync)
end

local function OnPortrait(texture, unit)
	if type(texture) ~= "table" or type(unit) ~= "string" or not texture.GetObjectType then return end
	if texture.IsForbidden and texture:IsForbidden() then return end
	-- the character button of the game menu draws your portrait too; a model
	-- there would not fade with a hidden menu bar
	if CharacterMicroButton and texture == CharacterMicroButton.Portrait then return end
	local e = entries[texture]
	if not e then
		if not BigEnough(texture) then return end
		e = {
			alpha = texture:GetAlpha(),
			round = (texture.GetNumMaskTextures and texture:GetNumMaskTextures() or 0) > 0,
		}
		entries[texture] = e
		Hook(texture)
	end
	e.unit = unit
	e.dirty = true
	Refresh(texture)
end
ns.OnPortrait = OnPortrait

function ns.ApplyAll()
	for texture, e in pairs(entries) do
		e.dirty = true
		Refresh(texture)
	end
end

local function UnitChanged(unit)
	for texture, e in pairs(entries) do
		if e.unit and unit and UnitIsUnit(e.unit, unit) then
			e.dirty = true
			Refresh(texture)
		end
	end
end

function ns.InitPortraits()
	hooksecurefunc("SetPortraitTexture", OnPortrait)

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("UNIT_MODEL_CHANGED")
	watcher:RegisterEvent("UNIT_PORTRAIT_UPDATE")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_REGEN_ENABLED" then
			for texture in pairs(pending) do
				pending[texture] = nil
				Refresh(texture)
			end
		else
			UnitChanged(unit)
		end
	end)
end
