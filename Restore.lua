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
local restoreCompleteTime = 0
local pendingCombatRestore = nil

function Restore:IsInProgress()
    return isRestoring
end

function Restore:ResetInProgress()
    isRestoring = false
end

function Restore:IsRecentlyFinished()
    if restoreCompleteTime == 0 then return false end
    return (GetTime() - restoreCompleteTime) < (Settings.DEBOUNCE_TIME + 0.5)
end

function Restore:HasPendingCombatRestore()
    return pendingCombatRestore ~= nil
end

--------------------------------------------------------------------------------
-- Combat Deferral
-- Protected functions (PickupSpell, PlaceAction, etc.) cannot be called
--------------------------------------------------------------------------------

local combatFrame = CreateFrame("Frame")

combatFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if not pendingCombatRestore then return end
        local level = pendingCombatRestore
        pendingCombatRestore = nil
        Restore:Perform(level)
    end
end)

function Restore:PerformWhenSafe(level)
    if InCombatLockdown and InCombatLockdown() then
        level = level or Utils:GetPlayerLevel()
        pendingCombatRestore = level
        combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        Utils:Print(string.format("Level %d: Restore pending (in combat)", level))
        return true
    end
    return self:Perform(level)
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
    local bestMatch = nil
    local lowerName = string.lower(spellName)
    local lowerMatch = nil
    
    for tabIndex = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tabIndex)
        
        for spellIndex = offset + 1, offset + numSpells do
            local bookSpellName = GetSpellName(spellIndex, BOOKTYPE_SPELL)
            
            if bookSpellName then
                if bookSpellName == spellName then
                    bestMatch = spellIndex
                elseif string.lower(bookSpellName) == lowerName then
                    lowerMatch = spellIndex
                end
            end
        end
    end
    
    local match = bestMatch or lowerMatch
    if match then
        local isPassive = IsPassiveSpell(match, BOOKTYPE_SPELL)
        return match, isPassive
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

local function FindItemInBags(itemID)
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        for bagSlot = 1, numSlots do
            local link = GetContainerItemLink(bag, bagSlot)
            if link then
                local linkID = link:match("item:(%d+)")
                if linkID and tonumber(linkID) == itemID then
                    return bag, bagSlot
                end
            end
        end
    end
    return nil, nil
end

local function FindItemEquipped(itemID)
    for equipSlot = 1, 19 do
        local link = GetInventoryItemLink("player", equipSlot)
        if link then
            local linkID = link:match("item:(%d+)")
            if linkID and tonumber(linkID) == itemID then
                return equipSlot
            end
        end
    end
    return nil
end

local function PlaceItem(slot, info)
    local itemID = info.id
    if not itemID then return false, "no id" end

    local bag, bagSlot = FindItemInBags(itemID)
    if bag then
        PickupContainerItem(bag, bagSlot)
        if CursorHasItem() then
            PlaceAction(slot)
            ClearCursor()
            return true, nil
        end
        ClearCursor()
    end
    
    local equipSlot = FindItemEquipped(itemID)
    if equipSlot then
        PickupInventoryItem(equipSlot)
        if CursorHasItem() then
            PlaceAction(slot)
            ClearCursor()
            return true, nil
        end
        ClearCursor()
    end
    
    PickupItem(itemID)
    if CursorHasItem() then
        PlaceAction(slot)
        ClearCursor()
        return true, nil
    end
    ClearCursor()
    
    return false, "not in bags"
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
    
    local numCompanions = GetNumCompanions(companionType) or 0
    if numCompanions == 0 then return false, "no companions" end
    
    if companionID >= 1 and companionID <= numCompanions then
        PickupCompanion(companionType, companionID)
        PlaceAction(slot)
        ClearCursor()
        return true, nil
    end
    
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
    ["not in bags"] = "not in bags or equipped",
    ["no companions"] = "no companions of this type",
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
    
    return self:PerformFromLayout(layout, level)
end

--- Restore from a given layout object directly (used by breakpoint mode
--- to restore derived layouts without saving them to storage).
function Restore:PerformFromLayout(layout, level)
    level = level or Utils:GetPlayerLevel()
    
    if not layout then
        Utils:Print(string.format("Level %d: No layout provided", level))
        return false
    end
    
    isRestoring = true
    
    local ok, restored, failures = pcall(function()
        return self:FromSnapshot(layout)
    end)
    
    isRestoring = false
    restoreCompleteTime = GetTime()
    
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
    restoreCompleteTime = GetTime()
    
    if not ok then
        Utils:PrintError("Clear error: " .. tostring(cleared))
        return 0
    end
    
    return cleared
end