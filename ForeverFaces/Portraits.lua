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
-- model gets a dark disc behind it and a soft dark fade over its edges
-- (textures, which can be masked to the circle). On a unit frame it is also
-- slid under the ring art (see Levels); in a window it stays small enough for
-- its corners to stay inside the circle.
--
-- The flat picture comes back whenever the model can't be shown: the unit is
-- gone or out of sight, the model has not loaded, the game put a plain
-- picture on the texture (book icon, class icon), or the part is switched off.
-- State is kept in local tables keyed by texture, nothing is written onto
-- Blizzard frames.

local MIN_SIZE = 30     -- smaller portraits stay flat
local SIZE_MIN, SIZE_MAX, SIZE_DEFAULT = 0.70, 0.85, 80 -- model size in a round portrait
local FADE_EDGE = 0.70  -- media/fade.tga is fully opaque from this share of its radius out
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FADE = "Interface\\AddOns\\" .. ADDON .. "\\media\\fade"
local DARK = { 0.04, 0.04, 0.06, 1 }
local LOAD_CHECK = 0.25 -- seconds; a cached model may never fire OnModelLoaded

local entries = {} -- [texture] = { unit, guid, alpha, round, framed, model, back, cover, fade, dirty, shown, hiding, tinted }
local Swapped -- defined with the events below
local pending = {} -- [texture] = true, waiting for combat to end
local hooked = {}

local function DB() return ns.DB() end

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

-- A test on a unit that may come back secret: a secret answer counts as no.
local function Is(fn, unit)
	if not fn then return false end
	local v = fn(unit)
	if Secret(v) then return false end
	return v and true or false
end

-- The game tints the flat picture for these (grey, blue, desaturated); a
-- model would hide that, so the picture stays.
local function Tinted(unit)
	return Is(UnitIsDeadOrGhost, unit) or Is(UnitIsTapDenied, unit)
		or (Is(UnitIsPlayer, unit) and UnitIsConnected and not Is(UnitIsConnected, unit))
end

local function Category(unit)
	unit = unit:lower()
	if unit == "npc" or unit == "questnpc" then return "npc" end
	if unit:find("^party") or unit:find("^raid") then return "party" end
	return "units"
end

-- the saved portrait size, kept inside the range that looks right
function ns.Size()
	local size = tonumber(DB().size) or SIZE_DEFAULT
	return math.min(SIZE_MAX * 100, math.max(SIZE_MIN * 100, size))
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
	-- the game's own tint on the picture (grey dead, blue ghost, red low health,
	-- desaturated offline) or a state the game leaves untinted (a dead mob)
	e.tinted = e.gameTint or Tinted(e.unit)
	return UnitExists(e.unit) and UnitIsVisible(e.unit) and not e.tinted
end

-- A unit frame (player, target, focus, pet, party ...) is a secure unit button
-- that carries a "unit" attribute; its portrait sits one or two frames below
-- it. Windows that also draw a unit's portrait (character, talents, inspect,
-- NPC dialogues) have no such attribute.
local function OnUnitFrame(texture)
	local frame = texture:GetParent()
	for _ = 1, 3 do
		if not frame or (frame.IsForbidden and frame:IsForbidden()) then return false end
		if frame.GetAttribute and frame:GetAttribute("unit") then return true end
		frame = frame:GetParent()
	end
	return false
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
	if e.showing then return end
	-- showing a model can fire its OnModelLoaded at once, which comes back here
	e.showing = true
	if not e.model:IsShown() then e.model:Show() end
	e.showing = false
	e.model:SetAlpha(1)
	e.back:SetShown(DB().background)
	e.cover:SetShown(e.round and DB().background)
	e.shown = true
	e.hiding = true
	texture:SetAlpha(0)
	e.hiding = false
end

-- The portrait's own frame holds the ring art, and on a unit frame the level
-- badge and the bars sit in sibling frames. Our frames go under all of that,
-- so the ring and the badge are drawn over the model:
--   back (dark disc) < model < cover (soft fade) < the unit frame's parts.
-- A unit frame lives in its own strata (LOW); one strata down is under every
-- part of it whatever their levels are (the player frame sits at level 1-2,
-- with no room below). A window (character, talents, NPC dialogues) keeps our
-- frames on top of its portrait: one strata down would put them under the
-- window's own background.
local STRATA_BELOW = {
	LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
	FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG",
}

local function Levels(texture, e)
	local host = texture:GetParent()
	local level = host:GetFrameLevel()
	local below = STRATA_BELOW[host:GetFrameStrata()]
	if below and e.framed then
		e.back:SetFrameStrata(below)
		e.model:SetFrameStrata(below)
		e.cover:SetFrameStrata(below)
		e.back:SetFrameLevel(1)
		e.model:SetFrameLevel(2)
		e.cover:SetFrameLevel(3)
		return
	end
	e.back:SetFrameLevel(level + 1)
	e.model:SetFrameLevel(level + 2)
	e.cover:SetFrameLevel(level + 3)
end

local function Layout(texture, e)
	local model = e.model
	model:ClearAllPoints()
	if e.round then
		local w, h = texture:GetSize()
		local d = math.min(w, h)
		local fill = ns.Size() / 100
		-- on top of a window's ring the model's corners must stay inside the circle
		if not e.framed then fill = SIZE_MIN end
		model:SetPoint("CENTER", texture, "CENTER")
		model:SetSize(d * fill, d * fill)
		-- The fade picture is opaque from FADE_EDGE of its radius out. It stays the
		-- size of the portrait (a bigger picture runs past the game's mask, whose
		-- edge pixels then smear outward as dark streaks) and is zoomed with
		-- texture coordinates so its opaque edge lands on the model's edge.
		local half = 0.5 * FADE_EDGE / fill
		e.fade:SetTexCoord(0.5 - half, 0.5 + half, 0.5 - half, 0.5 + half)
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
	-- hidden (the target cleared, the frame closed): the unit may look different
	-- by the time it is back, so its model is loaded again then
	model:SetScript("OnHide", function()
		local entry = entries[texture]
		if entry then entry.dirty = true end
	end)

	-- above the model: fades its square edges into the dark disc
	local cover = CreateFrame("Frame", nil, host)
	cover:SetAllPoints(texture)
	local fade = cover:CreateTexture(nil, "OVERLAY")
	fade:SetAllPoints(texture)
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

	-- the game tints the picture to show a state; the flat picture then shows it
	local function Tint()
		local e = entries[texture]
		-- only unit frames tint their portrait to show a state
		if not e or not e.framed then return end
		local tinted = false
		if texture.IsDesaturated then
			local d = texture:IsDesaturated()
			if not Secret(d) and d then tinted = true end
		end
		if not tinted and texture.GetVertexColor then
			local r, g, b = texture:GetVertexColor()
			if not (Secret(r) or Secret(g) or Secret(b)) and r and g and b then
				tinted = r < 0.99 or g < 0.99 or b < 0.99
			end
		end
		if tinted ~= (e.gameTint or false) then
			e.gameTint = tinted
			Refresh(texture)
		end
	end
	hooksecurefunc(texture, "SetVertexColor", Tint)
	if texture.SetDesaturated then hooksecurefunc(texture, "SetDesaturated", Tint) end
	if texture.SetDesaturation then hooksecurefunc(texture, "SetDesaturation", Tint) end

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
	-- nor on the side tabs of the character and inspect windows, which are buttons
	local parent = texture:GetParent()
	if parent and parent.InitializeIconAnchoring then return end
	if PaperDollSidebarTab1 and texture == PaperDollSidebarTab1.Icon then return end
	local e = entries[texture]
	if not e then
		if not BigEnough(texture) then return end
		e = {
			alpha = texture:GetAlpha(),
			round = (texture.GetNumMaskTextures and texture:GetNumMaskTextures() or 0) > 0,
			framed = OnUnitFrame(texture),
		}
		entries[texture] = e
		Hook(texture)
	end
	-- the game redraws portraits all the time; load a model only for a new unit.
	-- Until the new one is there the game's fresh flat picture shows, not the
	-- previous unit's model.
	local guid = UnitGUID(unit)
	-- a hidden identity can't be compared; a new unit is then told by the
	-- target / focus / group events instead (see Swapped)
	if Secret(guid) then guid = nil end
	if e.unit ~= unit or e.guid ~= guid then
		Flat(texture)
		e.unit, e.guid = unit, guid
		e.dirty = true
	end
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

-- settings change the look; a part switched off and on again loads its models anew
function ns.ApplyAll()
	for texture in pairs(entries) do
		Refresh(texture)
	end
end

-- new gear or shape: load the model again; a portrait update needs no reload
local function Same(a, b)
	if a == b then return true end
	local same = UnitIsUnit(a, b)
	return not Secret(same) and same and true or false
end

local function UnitChanged(unit, reload)
	if not unit then return end
	for texture, e in pairs(entries) do
		if e.unit and Same(e.unit, unit) then
			if reload then e.dirty = true end
			Refresh(texture)
		end
	end
end

-- Another unit on a portrait whose identity is hidden (no GUID to compare):
-- the flat picture first, then the new model.
Swapped = function(pattern)
	for texture, e in pairs(entries) do
		if e.unit and e.guid == nil and e.unit:find(pattern) then
			Flat(texture)
			e.dirty = true
			Refresh(texture)
		end
	end
end

-- Died, released, came back, went offline, got tapped: only a change of that
-- look refreshes the portrait (health events come often).
local function StateChanged(unit)
	if not unit then return end
	for texture, e in pairs(entries) do
		if e.unit and texture:IsVisible() and Same(e.unit, unit) then
			local tinted = e.gameTint or Tinted(e.unit)
			if tinted ~= e.tinted then
				e.tinted = tinted
				Refresh(texture)
			end
		end
	end
end

function ns.InitPortraits()
	hooksecurefunc("SetPortraitTexture", OnPortrait)

	-- The Edit Mode party background sits at level 1 of the party frames'
	-- strata, where the models (one strata down) would be under it. It is a
	-- plain backdrop, so it moves to the bottom instead, after the game has
	-- placed it each time it shows.
	local bg = PartyFrame and PartyFrame.Background
	if bg and not (bg.IsProtected and bg:IsProtected()) then
		bg:HookScript("OnShow", function(self)
			self:SetFrameStrata("BACKGROUND")
			self:SetFrameLevel(0)
		end)
		if bg:IsShown() then
			bg:SetFrameStrata("BACKGROUND")
			bg:SetFrameLevel(0)
		end
	end

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("UNIT_MODEL_CHANGED")
	watcher:RegisterEvent("UNIT_PORTRAIT_UPDATE")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	for _, event in ipairs({ "UNIT_HEALTH", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_FACTION",
		"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_TARGET", "UNIT_PET", "GROUP_ROSTER_UPDATE" }) do
		watcher:RegisterEvent(event)
	end
	watcher:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" or event == "UNIT_CONNECTION" or event == "UNIT_FACTION" then
			StateChanged(unit)
		elseif event == "PLAYER_TARGET_CHANGED" then
			Swapped("^target")
		elseif event == "PLAYER_FOCUS_CHANGED" then
			Swapped("^focus")
		elseif event == "UNIT_TARGET" then
			if unit == "target" then Swapped("^targettarget$") end
		elseif event == "UNIT_PET" then
			if unit == "player" then Swapped("^pet$") end
		elseif event == "GROUP_ROSTER_UPDATE" then
			Swapped("^party")
		elseif event == "PLAYER_REGEN_ENABLED" then
			for texture in pairs(pending) do
				pending[texture] = nil
				Refresh(texture)
			end
		else
			UnitChanged(unit, event == "UNIT_MODEL_CHANGED")
		end
	end)
end
