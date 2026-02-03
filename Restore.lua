--[[----------------------------------------------------------------------------
    Restore coordination and slot placement.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Restore = {}

local Restore = EBB.Restore
local Utils = EBB.Utils
local Settings = EBB.Settings
local ActionBar = EBB.ActionBar
local Profile = EBB.Profile
local Layout = EBB.Layout

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local isRestoring = false

function Restore:IsInProgress()
    return isRestoring
end

function Restore:ResetInProgress()
    isRestoring = false
end

--------------------------------------------------------------------------------
-- Spell Aliases
--------------------------------------------------------------------------------

local SPELL_ALIASES = {
    ["Attack"] = "Auto Attack",
    ["Shoot"] = "Auto Shot",
}

local function GetSpellbookName(tooltipName)
    if not tooltipName then return nil end
    return SPELL_ALIASES[tooltipName] or tooltipName
end

--------------------------------------------------------------------------------
-- Spellbook Search
--------------------------------------------------------------------------------

local function FindSpellInSpellbook(spellName)
    if not spellName then return nil, nil end
    
    local numTabs = GetNumSpellTabs()
    
    for tabIndex = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tabIndex)
        
        for spellIndex = offset + 1, offset + numSpells do
            local bookSpellName = GetSpellInfo(spellIndex, BOOKTYPE_SPELL)
            
            if bookSpellName and bookSpellName == spellName then
                local isPassive = IsPassiveSpell(spellIndex, BOOKTYPE_SPELL)
                return spellIndex, isPassive
            end
        end
    end
    
    return nil, nil
end

--------------------------------------------------------------------------------
-- Placement Functions
--------------------------------------------------------------------------------

local function PlaceSpell(slot, info)
    local spellName = info.name
    
    if not spellName then
        return false, "no name"
    end
    
    local currentName = ActionBar:GetSpellNameFromTooltip(slot)
    if currentName and currentName == spellName then
        return true, nil
    end
    
    local spellbookName = GetSpellbookName(spellName)
    local spellbookIndex, isPassive = FindSpellInSpellbook(spellbookName)
    
    if not spellbookIndex and spellbookName ~= spellName then
        spellbookIndex, isPassive = FindSpellInSpellbook(spellName)
    end
    
    if spellbookIndex then
        if isPassive then
            return false, "passive"
        end
        
        PickupSpell(spellbookIndex, BOOKTYPE_SPELL)
        if CursorHasSpell() then
            PlaceAction(slot)
            ClearCursor()
            return true, nil
        end
        ClearCursor()
    end
    
    return false, "not found"
end

local function PlaceItem(slot, info)
    local itemID = info.id
    if not itemID then return false, "no id" end
    
    PickupItem(itemID)
    if CursorHasItem() then
        PlaceAction(slot)
        ClearCursor()
        return true, nil
    end
    ClearCursor()
    return false, "not found"
end

local function PlaceMacro(slot, info)
    local macroName = info.name
    if not macroName then return false, "no name" end
    
    local macroIndex = GetMacroIndexByName(macroName)
    if macroIndex and macroIndex > 0 then
        PickupMacro(macroIndex)
        PlaceAction(slot)
        ClearCursor()
        return true, nil
    end
    return false, "not found"
end

local function PlaceCompanion(slot, info)
    local companionType = info.companionType or info.subType
    local companionID = info.id
    if not companionType or not companionID then return false, "missing info" end
    
    local numCompanions = GetNumCompanions(companionType)
    for i = 1, numCompanions do
        local creatureID = GetCompanionInfo(companionType, i)
        if creatureID == companionID then
            PickupCompanion(companionType, i)
            PlaceAction(slot)
            ClearCursor()
            return true, nil
        end
    end
    return false, "not found"
end

local function PlaceEquipmentSet(slot, info)
    local setName = info.setName or info.id
    if not setName then return false, "no name" end
    
    local numSets = GetNumEquipmentSets()
    for i = 1, numSets do
        local name = GetEquipmentSetInfo(i)
        if name == setName then
            PickupEquipmentSetByName(setName)
            PlaceAction(slot)
            ClearCursor()
            return true, nil
        end
    end
    return false, "not found"
end

--------------------------------------------------------------------------------
-- Single Slot Restore
--------------------------------------------------------------------------------

local function RestoreSlot(slot, info)
    if not info then
        ActionBar:ClearSlot(slot)
        return true, nil
    end
    
    local actionType = info.type
    
    if actionType == "empty" then
        ActionBar:ClearSlot(slot)
        return true, nil
    end
    
    ActionBar:ClearSlot(slot)
    
    local success, reason
    
    if actionType == "spell" then
        success, reason = PlaceSpell(slot, info)
    elseif actionType == "item" then
        success, reason = PlaceItem(slot, info)
    elseif actionType == "macro" then
        success, reason = PlaceMacro(slot, info)
    elseif actionType == "companion" then
        success, reason = PlaceCompanion(slot, info)
    elseif actionType == "equipmentset" then
        success, reason = PlaceEquipmentSet(slot, info)
    else
        return false, "unknown type"
    end
    
    ClearCursor()
    return success, reason
end

--------------------------------------------------------------------------------
-- Full Restore
--------------------------------------------------------------------------------

function Restore:FromSnapshot(snapshot)
    if not snapshot or not snapshot.slots then
        return 0, {}
    end
    
    local restored = 0
    local failures = {}
    
    for slot = 1, Settings.TOTAL_SLOTS do
        if Profile:IsSlotEnabled(slot) then
            local slotInfo = snapshot.slots[slot]
            
            if slotInfo then
                local success, reason = RestoreSlot(slot, slotInfo)
                
                if success then
                    if slotInfo.type ~= "empty" then
                        restored = restored + 1
                    end
                else
                    table.insert(failures, {
                        slot = slot,
                        type = slotInfo.type,
                        name = slotInfo.name or slotInfo.setName or ("id:" .. tostring(slotInfo.id)),
                        reason = reason or "unknown",
                    })
                end
            else
                ActionBar:ClearSlot(slot)
            end
        end
    end
    
    return restored, failures
end

--------------------------------------------------------------------------------
-- Restore Execution
--------------------------------------------------------------------------------

local function SummarizeFailures(failures)
    local byReason = {}
    for _, f in ipairs(failures) do
        local reason = f.reason
        if not byReason[reason] then
            byReason[reason] = { count = 0, examples = {} }
        end
        byReason[reason].count = byReason[reason].count + 1
        if #byReason[reason].examples < 2 then
            table.insert(byReason[reason].examples, f.name or "unknown")
        end
    end
    return byReason
end

local REASON_LABELS = {
    ["not found"] = "not in spellbook/bags",
    ["passive"] = "passive (can't place)",
    ["no name"] = "missing name data",
    ["no id"] = "missing ID data",
    ["missing info"] = "incomplete data",
    ["unknown type"] = "unsupported action type",
}

local function GetReasonLabel(reason)
    return REASON_LABELS[reason] or reason
end

function Restore:Perform(level)
    level = level or Utils:GetPlayerLevel()
    
    local layout, source = Layout:Get(level)
    
    if not layout then
        Utils:Print(string.format("Level %d: No saved layout found", level))
        return false
    end
    
    isRestoring = true
    
    local ok, restored, failures = pcall(function()
        return self:FromSnapshot(layout)
    end)
    
    isRestoring = false
    
    if not ok then
        Utils:PrintError("Restore error: " .. tostring(restored))
        return false
    end
    
    local failCount = #failures
    
    if failCount == 0 then
        Utils:Print(string.format("Level %d: %d slots restored", level, restored))
    else
        Utils:Print(string.format("Level %d: %d slots restored, %d failed", level, restored, failCount))
    end
    
    if failCount > 0 then
        local byReason = SummarizeFailures(failures)
        for reason, data in pairs(byReason) do
            local label = GetReasonLabel(reason)
            local examples = table.concat(data.examples, ", ")
            if data.count > #data.examples then
                examples = examples .. ", ..."
            end
            Utils:Print(string.format("  %d %s: %s", data.count, label, examples))
        end
    end
    
    return true
end

--------------------------------------------------------------------------------
-- Clear All Slots
--------------------------------------------------------------------------------

function Restore:ClearAllSlots()
    isRestoring = true
    
    local ok, cleared = pcall(function()
        local count = 0
        for slot = 1, Settings.TOTAL_SLOTS do
            if Profile:IsSlotEnabled(slot) then
                ActionBar:ClearSlot(slot)
                count = count + 1
            end
        end
        return count
    end)
    
    isRestoring = false
    
    if not ok then
        Utils:PrintError("Clear error: " .. tostring(cleared))
        return 0
    end
    
    return cleared
end
