--[[----------------------------------------------------------------------------
    Low-level action bar slot operations.
    Handles reading slot info and detecting capture context.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.ActionBar = {}

local ActionBar = EBB.ActionBar
local Settings = EBB.Settings

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_ACCOUNT_MACROS = 36

--------------------------------------------------------------------------------
-- Tooltip Scanner (for getting spell names)
--------------------------------------------------------------------------------

local tooltipFrame = nil

function ActionBar:GetSpellNameFromTooltip(slot)
    if not tooltipFrame then
        tooltipFrame = CreateFrame("GameTooltip", "EBBScanTooltip", nil, "GameTooltipTemplate")
        tooltipFrame:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    
    tooltipFrame:ClearLines()
    tooltipFrame:SetAction(slot)
    
    local nameText = _G["EBBScanTooltipTextLeft1"]
    if nameText then
        local name = nameText:GetText()
        if name and name ~= "" then
            return name
        end
    end
    
    return nil
end

--------------------------------------------------------------------------------
-- Context Detection
--------------------------------------------------------------------------------

function ActionBar:GetCaptureContext()
    if UnitInVehicle and UnitInVehicle("player") then
        return "vehicle"
    end
    
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then
        return "vehicle"
    end
    
    local bonusBar = GetBonusBarOffset and GetBonusBarOffset() or 0
    if bonusBar and bonusBar > 0 then
        return "bonus:" .. bonusBar
    end
    
    if IsPossessBarVisible and IsPossessBarVisible() then
        return "possess"
    end
    
    return "normal"
end

--------------------------------------------------------------------------------
-- Stance Helpers
--------------------------------------------------------------------------------

function ActionBar:GetStanceIndex()
    return GetBonusBarOffset and GetBonusBarOffset() or 0
end

function ActionBar:IsFullyBlocked()
    local context = self:GetCaptureContext()
    return context == "vehicle" or context == "possess"
end

function ActionBar:GetBarForStance(stanceIndex)
    if stanceIndex and stanceIndex >= 1 and stanceIndex <= 4 then
        return stanceIndex + 6
    end
    return nil
end

--------------------------------------------------------------------------------
-- Slot Information
--------------------------------------------------------------------------------

function ActionBar:GetSlotInfo(slot)
    if not slot or slot < 1 or slot > Settings.TOTAL_SLOTS then
        return nil
    end
    
    local actionType, id, subType = GetActionInfo(slot)
    
    if not actionType then
        return { type = "empty", slot = slot }
    end
    
    local info = {
        type = actionType,
        id = id,
        subType = subType,
        slot = slot,
    }
    
    local iconTexture = GetActionTexture(slot)
    if iconTexture then
        info.icon = iconTexture
    end
    
    if actionType == "spell" then
        info.name = self:GetSpellNameFromTooltip(slot)
        if not info.name and id then
            info.name = GetSpellInfo(id)
        end

        info.rank = ""
        if id then
            local spellName, spellRank = GetSpellName(id, BOOKTYPE_SPELL)
            if spellRank then
                info.rank = spellRank
            end
        end
        
    elseif actionType == "item" then
        info.name = GetItemInfo(id)
        
    elseif actionType == "macro" then
        local macroName, macroIcon, macroBody = GetMacroInfo(id)
        info.name = macroName
        info.body = macroBody
        
    elseif actionType == "companion" then
        info.companionType = subType
        
    elseif actionType == "equipmentset" then
        info.setName = id
    end
    
    return info
end

--------------------------------------------------------------------------------
-- Slot Clearing
--------------------------------------------------------------------------------

function ActionBar:ClearSlot(slot)
    PickupAction(slot)
    ClearCursor()
end

--------------------------------------------------------------------------------
-- Macro Duplicate Detection
--------------------------------------------------------------------------------

function ActionBar:GetMacroDuplicates()
    local counts = {}
    local duplicates = {}
    local numGlobal, numChar = GetNumMacros()
    
    for i = 1, numGlobal or 0 do
        local name = GetMacroInfo(i)
        if name then
            counts[name] = (counts[name] or 0) + 1
        end
    end
    
    for i = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + (numChar or 0) do
        local name = GetMacroInfo(i)
        if name then
            counts[name] = (counts[name] or 0) + 1
        end
    end
    
    for name, count in pairs(counts) do
        if count > 1 then
            duplicates[name] = count
        end
    end
    
    return duplicates
end

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

function ActionBar:GetBarFromSlot(slot)
    return math.ceil(slot / Settings.SLOTS_PER_BAR)
end

function ActionBar:GetPositionInBar(slot)
    local pos = slot % Settings.SLOTS_PER_BAR
    return pos == 0 and Settings.SLOTS_PER_BAR or pos
end

function ActionBar:GetSlotFromBarPosition(bar, position)
    if bar < 1 or bar > Settings.TOTAL_BARS then
        return nil
    end
    if position < 1 or position > Settings.SLOTS_PER_BAR then
        return nil
    end
    return ((bar - 1) * Settings.SLOTS_PER_BAR) + position
end
