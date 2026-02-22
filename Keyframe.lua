--[[----------------------------------------------------------------------------
    Keyframe (Breakpoint) management system.
    Keyframes are milestone levels where layouts are manually defined.
    Intermediate levels derive their layouts from the nearest keyframe below,
    with spell ranks auto-adjusted via SpellCache.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Keyframe = {}

local Keyframe = EBB.Keyframe
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile
local SpellCache = EBB.SpellCache

--------------------------------------------------------------------------------
-- Storage Access
--------------------------------------------------------------------------------

local function GetSpecData(specIndex)
    specIndex = specIndex or Profile:GetActive()
    local spec = EBB_CharDB.specs[specIndex]
    if not spec then return nil end
    return spec
end

local function GetKeyframeTable(specIndex)
    local spec = GetSpecData(specIndex)
    if not spec then return {} end

    if not spec.keyframes then
        spec.keyframes = {}
    end

    return spec.keyframes
end

--------------------------------------------------------------------------------
-- Keyframe CRUD
--------------------------------------------------------------------------------

function Keyframe:Set(level, specIndex)
    local kf = GetKeyframeTable(specIndex)
    kf[level] = true
end

function Keyframe:Remove(level, specIndex)
    local kf = GetKeyframeTable(specIndex)
    kf[level] = nil
end

function Keyframe:Toggle(level, specIndex)
    if self:IsKeyframe(level, specIndex) then
        self:Remove(level, specIndex)
        return false
    else
        self:Set(level, specIndex)
        return true
    end
end

function Keyframe:IsKeyframe(level, specIndex)
    local kf = GetKeyframeTable(specIndex)
    return kf[level] == true
end

--------------------------------------------------------------------------------
-- Keyframe Queries
--------------------------------------------------------------------------------

function Keyframe:GetAll(specIndex)
    local kf = GetKeyframeTable(specIndex)
    local levels = {}

    for level in pairs(kf) do
        if kf[level] == true then
            table.insert(levels, level)
        end
    end

    table.sort(levels)
    return levels
end

function Keyframe:GetCount(specIndex)
    local kf = GetKeyframeTable(specIndex)
    local count = 0
    for level, v in pairs(kf) do
        if v == true then
            count = count + 1
        end
    end
    return count
end

function Keyframe:GetNearestBelow(level, specIndex)
    local all = self:GetAll(specIndex)
    local best = nil

    for _, kfLevel in ipairs(all) do
        if kfLevel <= level then
            best = kfLevel
        else
            break
        end
    end

    return best
end

function Keyframe:GetNearestAbove(level, specIndex)
    local all = self:GetAll(specIndex)

    for _, kfLevel in ipairs(all) do
        if kfLevel > level then
            return kfLevel
        end
    end

    return nil
end

function Keyframe:GetRange(level, specIndex)
    local lower = self:GetNearestBelow(level, specIndex)
    local upper = self:GetNearestAbove(level, specIndex)
    return lower, upper
end

--------------------------------------------------------------------------------
-- Layout Derivation
--------------------------------------------------------------------------------

function Keyframe:DeriveLayout(sourceLayout, targetLevel)
    if not sourceLayout or not sourceLayout.slots then
        return nil
    end

    if not SpellCache then
        return Utils:DeepCopy(sourceLayout)
    end

    local derived = {
        timestamp = sourceLayout.timestamp,
        playerLevel = targetLevel,
        slots = {},
        configuredSlots = 0,
        isDerived = true,
        sourceLevel = sourceLayout.playerLevel,
    }

    for slot = 1, Settings.TOTAL_SLOTS do
        local srcSlot = sourceLayout.slots[slot]

        if not srcSlot or srcSlot.type == "empty" then
            derived.slots[slot] = srcSlot and Utils:DeepCopy(srcSlot) or nil
        elseif srcSlot.type == "spell" and srcSlot.name then
            local adjustedSlot = self:AdjustSpellRank(srcSlot, targetLevel)
            derived.slots[slot] = adjustedSlot
            if adjustedSlot and adjustedSlot.type ~= "empty" then
                derived.configuredSlots = derived.configuredSlots + 1
            end
        else
            derived.slots[slot] = Utils:DeepCopy(srcSlot)
            if srcSlot.type ~= "empty" then
                derived.configuredSlots = derived.configuredSlots + 1
            end
        end
    end

    return derived
end

function Keyframe:AdjustSpellRank(slotInfo, targetLevel)
    if not slotInfo or slotInfo.type ~= "spell" or not slotInfo.name then
        return Utils:DeepCopy(slotInfo)
    end

    local cache = SpellCache:GetClassCache()
    local spellName = slotInfo.name

    if not cache[spellName] then
        return Utils:DeepCopy(slotInfo)
    end

    local ranks = {}
    for rank, entry in pairs(cache[spellName]) do
        local learnLevel = SpellCache:ReadEntryLevel(entry)
        if learnLevel then
            table.insert(ranks, {
                rank = rank,
                learnLevel = learnLevel,
                icon = SpellCache:ReadEntryIcon(entry),
            })
        end
    end

    table.sort(ranks, function(a, b)
        return a.learnLevel > b.learnLevel
    end)

    local bestRank = nil
    for _, r in ipairs(ranks) do
        if r.learnLevel <= targetLevel then
            bestRank = r
            break
        end
    end

    if not bestRank then
        return {
            type = "empty",
            slot = slotInfo.slot,
            _unavailableSpell = spellName,
        }
    end

    local adjusted = Utils:DeepCopy(slotInfo)
    adjusted.rank = bestRank.rank
    if bestRank.icon then
        adjusted.icon = bestRank.icon
    end

    if bestRank.rank and bestRank.rank ~= "" then
        adjusted.displayName = spellName .. " (" .. bestRank.rank .. ")"
    else
        adjusted.displayName = spellName
    end

    return adjusted
end

--------------------------------------------------------------------------------
-- Integration Queries
--------------------------------------------------------------------------------

function Keyframe:GetEffectiveLayout(level, specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout

    local saved, savedSource = Layout:Get(level, specIndex)

    if self:IsKeyframe(level, specIndex) and saved then
        return saved, "keyframe"
    end

    local nearestKF = self:GetNearestBelow(level, specIndex)
    if nearestKF then
        local kfLayout = Layout:Get(nearestKF, specIndex)
        if kfLayout then
            if nearestKF == level then
                return kfLayout, "keyframe"
            end
            local derived = self:DeriveLayout(kfLayout, level)
            if derived then
                return derived, "derived"
            end
        end
    end

    if saved then
        return saved, savedSource
    end

    return nil, nil
end

function Keyframe:IsDerived(level, specIndex)
    if self:IsKeyframe(level, specIndex) then
        return false
    end

    local nearestKF = self:GetNearestBelow(level, specIndex)
    if nearestKF and nearestKF ~= level then
        local Layout = EBB.Layout
        local kfLayout = Layout:Get(nearestKF, specIndex)
        if kfLayout then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- Empty Layout Scaffold
--------------------------------------------------------------------------------

function Keyframe:CreateAtLevel(level, specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout
    local Utils = EBB.Utils
    local Settings = EBB.Settings

    self:Set(level, specIndex)

    if Layout:Has(level, specIndex) then
        return true, "existing"
    end

    local scaffold = {
        timestamp = Utils:GetTimestamp(),
        playerLevel = level,
        slots = {},
        configuredSlots = 0,
        capturedSlots = 0,
        isScaffold = true,  
    }

    for slot = 1, Settings.TOTAL_SLOTS do
        scaffold.slots[slot] = { type = "empty", slot = slot }
    end

    Layout:Save(level, scaffold, specIndex)
    return true, "created"
end

function Keyframe:StoreAsBreakpoint(level, specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout

    if not Layout:Has(level, specIndex) then
        return false, "no layout"
    end

    self:Set(level, specIndex)
    return true
end

--------------------------------------------------------------------------------
-- Batch Operations
--------------------------------------------------------------------------------

function Keyframe:ClearAll(specIndex)
    local spec = GetSpecData(specIndex)
    if spec then
        spec.keyframes = {}
    end
end

function Keyframe:AutoCreate(interval, specIndex)
    interval = interval or 10
    local Layout = EBB.Layout
    local levels = Layout:GetSavedLevels(specIndex)

    for _, level in ipairs(levels) do
        if level % interval == 0 or level == 1 then
            self:Set(level, specIndex)
        end
    end
end
