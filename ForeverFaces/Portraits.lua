local ADDON, ns = ...

-- The game draws a portrait by handing a texture and a unit to
-- SetPortraitTexture. That call is hooked: each portrait texture gets one
-- PlayerModel of its own, laid over the texture, and the flat picture is made
-- invisible while the model shows.
--
-- On Forever every portrait that matters is round: the unit frames, the party
-- frames and the portrait of a quest, gossip, merchant or trainer window are
-- all masked to a circle and framed by ring art. Models can't be masked: a
-- model is a square and would show a straight edge across the circle. So the
-- model is slid under the ring art (see Levels), has a dark disc behind it and
-- a soft dark fade over its edges (textures, which can be masked to the circle).
--
-- The flat picture comes back whenever the model can't be shown: the unit is
-- gone or out of sight, the model has not loaded, the game put a plain
-- picture on the texture (book icon, class icon), or the part is switched off.
-- State is kept in local tables keyed by texture, nothing is written onto
-- Blizzard frames.

local MIN_SIZE = 30     -- smaller portraits stay flat
local SIZE_MIN, SIZE_MAX, SIZE_DEFAULT = 0.70, 0.90, 80 -- model size in a round portrait
local FADE_EDGE = 0.70  -- media/fade.tga is fully opaque from this share of its radius out
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FADE = "Interface\\AddOns\\" .. ADDON .. "\\media\\fade"
local DARK = { 0.04, 0.04, 0.06, 1 }
local LOAD_CHECK = 0.25 -- seconds; a cached model may never fire OnModelLoaded

local entries = {} -- [texture] = { unit, alpha, round, model, back, cover, fade, dirty, shown, hiding }
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
		e.back:Hide()
		e.cover:Hide()
	end
	e.shown = false
	e.hiding = true
	texture:SetAlpha(e.alpha)
	e.hiding = false
end

local function Show3D(texture)
	local e = entries[texture]
	e.model:SetAlpha(1)
	e.back:SetShown(DB().background)
	e.cover:SetShown(e.round and DB().background)
	e.shown = true
	e.hiding = true
	texture:SetAlpha(0)
	e.hiding = false
end

-- The portrait's own frame holds the ring art. Our frames sit just below it,
-- so the ring is drawn over the model and hides its square corners:
--   back (dark disc) < model < cover (soft fade) < the frame with the ring.
-- A frame too low to fit three levels under it keeps everything on top.
local function Levels(texture, e)
	local host = texture:GetParent()
	local level = host:GetFrameLevel()
	-- On a unit frame the level badge and the bars live in sibling frames of the
	-- ring's frame, which may sit lower than it: slide under all of them.
	local unitFrame = host:GetParent()
	if unitFrame and e.unit and Category(e.unit) ~= "npc" then
		for _, child in ipairs({ unitFrame:GetChildren() }) do
			if not (child.IsForbidden and child:IsForbidden()) and child ~= e.back and child ~= e.model and child ~= e.cover then
				level = math.min(level, child:GetFrameLevel())
			end
		end
	end
	if level >= 3 then
		e.back:SetFrameLevel(level - 3)
		e.model:SetFrameLevel(level - 2)
		e.cover:SetFrameLevel(level - 1)
	else
		e.back:SetFrameLevel(level + 1)
		e.model:SetFrameLevel(level + 2)
		e.cover:SetFrameLevel(level + 3)
	end
end

local function Layout(texture, e)
	local model = e.model
	model:ClearAllPoints()
	if e.round then
		local w, h = texture:GetSize()
		local d = math.min(w, h)
		local fill = math.min(SIZE_MAX, math.max(SIZE_MIN, (DB().size or SIZE_DEFAULT) / 100))
		model:SetPoint("CENTER", texture, "CENTER")
		model:SetSize(d * fill, d * fill)
		-- the fade picture is opaque from FADE_EDGE of its radius out; scale it
		-- so that point lands on the model's edge
		e.fade:SetSize(d * fill / FADE_EDGE, d * fill / FADE_EDGE)
	else
		model:SetAllPoints(texture)
	end
	Levels(texture, e)
end

local function Build(texture, e)
	local host = texture:GetParent()

	local back = CreateFrame("Frame", nil, host)
	back:SetAllPoints(texture)
	local disc = back:CreateTexture(nil, "BACKGROUND")
	disc:SetAllPoints()
	disc:SetColorTexture(DARK[1], DARK[2], DARK[3], DARK[4])
	back:Hide()

	local model = CreateFrame("PlayerModel", nil, host)
	model:SetAlpha(0)
	model:Hide()
	model:SetScript("OnModelLoaded", function()
		local entry = entries[texture]
		if entry and Wanted(texture, entry) then Show3D(texture) end
	end)

	-- above the model: fades its square edges into the dark disc
	local cover = CreateFrame("Frame", nil, host)
	cover:SetAllPoints(texture)
	local fade = cover:CreateTexture(nil, "OVERLAY")
	fade:SetPoint("CENTER", texture, "CENTER")
	fade:SetTexture(FADE)
	fade:SetVertexColor(DARK[1], DARK[2], DARK[3], DARK[4])
	cover:Hide()

	-- the same shape the game cuts the portrait with: its own mask, copied
	if e.round then
		local own = texture.GetMaskTexture and texture:GetMaskTexture(1)
		for _, region in ipairs({ disc, fade }) do
			local mask = region:GetParent():CreateMaskTexture()
			local atlas = own and own.GetAtlas and own:GetAtlas()
			if atlas then
				mask:SetAtlas(atlas)
			else
				mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			end
			if own and own:GetNumPoints() > 0 then
				for i = 1, own:GetNumPoints() do mask:SetPoint(own:GetPoint(i)) end
				mask:SetSize(own:GetSize())
			else
				mask:SetAllPoints(texture)
			end
			region:AddMaskTexture(mask)
		end
	end

	e.model, e.back, e.cover, e.fade = model, back, cover, fade
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

	-- the game sets the portrait's alpha now and then; keep it hidden under a model
	hooksecurefunc(texture, "SetAlpha", function()
		local e = entries[texture]
		if e and e.shown and not e.hiding then
			e.hiding = true
			texture:SetAlpha(0)
			e.hiding = false
		end
	end)

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

-- /ff debug: the real numbers of every portrait, so the look can be tuned to
-- the game's frames instead of guessed.
function ns.Debug()
	local function name(f) return f and (f.GetDebugName and f:GetDebugName() or f:GetName()) or "-" end
	local function lvl(f) return f and (f:GetFrameStrata() .. " " .. f:GetFrameLevel()) or "-" end
	local count = 0
	for texture, e in pairs(entries) do
		if e.unit and texture:IsVisible() then
			count = count + 1
			local w, h = texture:GetSize()
			ns.Print(("%s [%s] %.1fx%.1f round=%s shown=%s"):format(name(texture), e.unit, w, h, tostring(e.round), tostring(e.shown)))
			local own = texture.GetMaskTexture and texture:GetMaskTexture(1)
			if own then
				local mw, mh = own:GetSize()
				ns.Print(("  mask %s %.1fx%.1f"):format(own.GetAtlas and own:GetAtlas() or "file", mw, mh))
			end
			local host = texture:GetParent()
			local unitFrame = host:GetParent()
			ns.Print(("  host %s %s, unit frame %s %s"):format(name(host), lvl(host), name(unitFrame), lvl(unitFrame)))
			if unitFrame then
				for _, child in ipairs({ unitFrame:GetChildren() }) do
					if not (child.IsForbidden and child:IsForbidden()) then
						ns.Print(("    sibling %s %s"):format(name(child), lvl(child)))
					end
				end
			end
			if e.model then
				local mw = e.model:GetWidth()
				ns.Print(("  ours: back %s, model %s (%.1f), cover %s"):format(lvl(e.back), lvl(e.model), mw, lvl(e.cover)))
			end
		end
	end
	if count == 0 then ns.Print("no 3D portraits on screen") end
end

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
