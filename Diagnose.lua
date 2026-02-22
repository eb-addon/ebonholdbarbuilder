--[[----------------------------------------------------------------------------
    Diagnostics for troubleshooting save/restore issues
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Diagnose = {}

local Diagnose = EBB.Diagnose
local Utils = EBB.Utils
local Settings = EBB.Settings
local ActionBar = EBB.ActionBar
local Profile = EBB.Profile
local Layout = EBB.Layout

--------------------------------------------------------------------------------
-- Output Helpers
--------------------------------------------------------------------------------

local function Out(msg)
    Utils:Print(msg)
end

local function OutDetail(msg)
    Utils:Print("  " .. msg)
end

local function OutWarn(msg)
    Utils:Print("  |cFFFFAA00" .. msg .. "|r")
end

local function OutError(msg)
    Utils:Print("  |cFFFF4444" .. msg .. "|r")
end

local function OutOK(msg)
    Utils:Print("  |cFF44FF44" .. msg .. "|r")
end

local function SafeStr(val)
    if val == nil then return "nil" end
    return tostring(val)
end

--------------------------------------------------------------------------------
-- Scan a bar (or all bars) and print raw API output
--------------------------------------------------------------------------------

function Diagnose:ScanBar(barNumber)
    if barNumber then
        if barNumber < 1 or barNumber > Settings.TOTAL_BARS then
            Out("Invalid bar number (1-" .. Settings.TOTAL_BARS .. ")")
            return
        end
        self:ScanBarRange(barNumber, barNumber)
    else
        Out("Scanning Bar 1 (use '/ebb diagnose <1-10>' for a specific bar, or '/ebb diagnose all')")
        self:ScanBarRange(1, 1)
    end
end

function Diagnose:ScanAll()
    Out("Scanning all " .. Settings.TOTAL_BARS .. " bars...")
    self:ScanBarRange(1, Settings.TOTAL_BARS)
end

function Diagnose:ScanBarRange(startBar, endBar)
    local context = ActionBar:GetCaptureContext()
    local stanceIndex = ActionBar:GetStanceIndex()
    Out(string.format("Context: %s | Stance: %d", context, stanceIndex))
    Out("---")

    for bar = startBar, endBar do
        local startSlot = ((bar - 1) * Settings.SLOTS_PER_BAR) + 1
        local endSlot = startSlot + Settings.SLOTS_PER_BAR - 1
        local hasContent = false

        for slot = startSlot, endSlot do
            local actionType, id, subType = GetActionInfo(slot)
            if actionType then
                if not hasContent then
                    Out(string.format("=== Bar %d (slots %d-%d) ===", bar, startSlot, endSlot))
                    hasContent = true
                end

                local pos = ActionBar:GetPositionInBar(slot)
                local icon = GetActionTexture(slot) or "none"
                local enabled = Profile:IsSlotEnabled(slot) and "yes" or "NO"

                OutDetail(string.format(
                    "Slot %d (#%d) | type=%s | id=%s | sub=%s | icon=%s | tracked=%s",
                    slot, pos,
                    SafeStr(actionType),
                    SafeStr(id),
                    SafeStr(subType),
                    SafeStr(icon),
                    enabled
                ))

                self:InspectSlotDetail(slot, actionType, id, subType)
            end
        end

        if not hasContent and startBar == endBar then
            Out(string.format("Bar %d: All slots empty", bar))
        end
    end
end

--------------------------------------------------------------------------------
-- Type-Specific Detail Inspection
--------------------------------------------------------------------------------

function Diagnose:InspectSlotDetail(slot, actionType, id, subType)
    if actionType == "spell" then
        self:InspectSpell(slot, id)
    elseif actionType == "item" then
        self:InspectItem(slot, id)
    elseif actionType == "macro" then
        self:InspectMacro(slot, id)
    elseif actionType == "companion" then
        self:InspectCompanion(slot, id, subType)
    elseif actionType == "equipmentset" then
        OutDetail(string.format("    EquipSet: setName=%s", SafeStr(id)))
    else
        OutWarn(string.format("    Unknown action type: %s", SafeStr(actionType)))
    end
end

function Diagnose:InspectSpell(slot, id)
    local tooltipName = ActionBar:GetSpellNameFromTooltip(slot)
    local apiName = id and GetSpellInfo(id) or nil
    local rank = ""
    if id then
        local _, spellRank = GetSpellName(id, BOOKTYPE_SPELL)
        rank = spellRank or ""
    end

    OutDetail(string.format(
        "    Spell: tooltip=%s | GetSpellInfo=%s | rank=%s",
        SafeStr(tooltipName),
        SafeStr(apiName),
        SafeStr(rank)
    ))

    local spellName = tooltipName or apiName
    if spellName then
        local found = self:FindInSpellbook(spellName)
        if found then
            OutOK(string.format("    Spellbook: FOUND at index %d", found))
        else
            OutWarn("    Spellbook: NOT FOUND")
        end
    end
end

function Diagnose:InspectItem(slot, id)
    local itemName = id and GetItemInfo(id) or nil
    OutDetail(string.format("    Item: name=%s | itemID=%s", SafeStr(itemName), SafeStr(id)))

    if id then
        local foundBag, foundSlot = nil, nil
        for bag = 0, 4 do
            local numSlots = GetContainerNumSlots(bag) or 0
            for bagSlot = 1, numSlots do
                local link = GetContainerItemLink(bag, bagSlot)
                if link then
                    local linkID = link:match("item:(%d+)")
                    if linkID and tonumber(linkID) == id then
                        foundBag, foundSlot = bag, bagSlot
                        break
                    end
                end
            end
            if foundBag then break end
        end

        if foundBag then
            OutOK(string.format("    Bag scan: FOUND in bag %d slot %d -- restore should work", foundBag, foundSlot))
        else
            OutWarn("    Bag scan: Not found in bags")
        end

        local foundEquip = nil
        for equipSlot = 1, 19 do
            local link = GetInventoryItemLink("player", equipSlot)
            if link then
                local linkID = link:match("item:(%d+)")
                if linkID and tonumber(linkID) == id then
                    foundEquip = equipSlot
                    break
                end
            end
        end

        if foundEquip then
            OutOK(string.format("    Equipped: FOUND in slot %d -- restore should work", foundEquip))
        elseif not foundBag then
            OutError("    Not in bags or equipped -- restore will fail")
        end

        PickupItem(id)
        local hasItem = CursorHasItem()
        ClearCursor()
        OutDetail(string.format("    PickupItem(id) test: %s", hasItem and "works" or "fails (expected on 3.3.5)"))
    end
end

function Diagnose:InspectMacro(slot, id)
    local macroName, macroIcon, macroBody
    if id then
        macroName, macroIcon, macroBody = GetMacroInfo(id)
    end

    OutDetail(string.format(
        "    Macro: index=%s | name=%s | icon=%s",
        SafeStr(id),
        SafeStr(macroName),
        SafeStr(macroIcon)
    ))

    if macroBody then
        local preview = macroBody:gsub("\n", " "):sub(1, 80)
        OutDetail(string.format("    Body: %s", preview))
    else
        OutError("    GetMacroInfo returned nil body")
    end

    if macroName then
        local foundIndex = GetMacroIndexByName(macroName)
        if foundIndex and foundIndex > 0 then
            OutOK(string.format("    GetMacroIndexByName: FOUND at index %d (saved as %s)",
                foundIndex, SafeStr(id)))
            if foundIndex ~= id then
                OutWarn("    Index mismatch! Save stores index " .. SafeStr(id)
                    .. " but name lookup returns " .. foundIndex)
            end
        else
            OutError("    GetMacroIndexByName: NOT FOUND (restore will fail)")
        end
    else
        OutError("    No macro name -- cannot restore by name")
    end
end

function Diagnose:InspectCompanion(slot, id, subType)
    OutDetail(string.format(
        "    Companion: listIndex=%s | companionType=%s",
        SafeStr(id), SafeStr(subType)
    ))

    if subType and id then
        local numCompanions = GetNumCompanions(subType) or 0
        OutDetail(string.format("    Total %s companions: %d", subType, numCompanions))

        if id >= 1 and id <= numCompanions then
            local creatureID, creatureName, creatureSpellID = GetCompanionInfo(subType, id)
            OutOK(string.format(
                "    Index %d resolves to: name=%s creatureID=%s spellID=%s",
                id, SafeStr(creatureName), SafeStr(creatureID), SafeStr(creatureSpellID)
            ))
        else
            OutError(string.format("    Index %d out of range (1-%d)", id, numCompanions))
            OutDetail("    Available companions:")
            for i = 1, math.min(numCompanions, 5) do
                local creatureID, creatureName = GetCompanionInfo(subType, i)
                OutDetail(string.format("      [%d] creatureID=%s name=%s",
                    i, SafeStr(creatureID), SafeStr(creatureName)))
            end
        end
    else
        OutError("    Missing subType or id -- cannot look up")
    end
end

--------------------------------------------------------------------------------
-- Spellbook Search Helper
--------------------------------------------------------------------------------

function Diagnose:FindInSpellbook(spellName)
    local numTabs = GetNumSpellTabs()
    for tabIndex = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tabIndex)
        for spellIndex = offset + 1, offset + numSpells do
            local bookName = GetSpellName(spellIndex, BOOKTYPE_SPELL)
            if bookName and bookName == spellName then
                return spellIndex
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- TestSlot: Attempt restore of a single saved slot with verbose output
--------------------------------------------------------------------------------

function Diagnose:TestSlot(slot)
    if not slot or slot < 1 or slot > Settings.TOTAL_SLOTS then
        Out("Usage: /ebb testslot <1-" .. Settings.TOTAL_SLOTS .. ">")
        return
    end

    local level = Utils:GetPlayerLevel()
    local layout, source = Layout:Get(level)

    if not layout then
        Out(string.format("No saved layout for level %d", level))
        return
    end

    local savedInfo = layout.slots and layout.slots[slot]
    local bar = ActionBar:GetBarFromSlot(slot)
    local pos = ActionBar:GetPositionInBar(slot)

    Out(string.format("=== Test Restore: Slot %d (Bar %d, #%d) ===", slot, bar, pos))
    Out(string.format("Source: %s layout for level %d", source or "unknown", level))

    if not savedInfo then
        OutDetail("Saved data: nil (slot was empty or not tracked)")
        return
    end

    Out("Saved data:")
    for k, v in pairs(savedInfo) do
        if k ~= "slot" then
            if type(v) == "string" and #v > 80 then
                OutDetail(string.format("  %s = %s...", k, v:sub(1, 80)))
            else
                OutDetail(string.format("  %s = %s", k, SafeStr(v)))
            end
        end
    end

    Out("Current live slot:")
    local liveType, liveId, liveSub = GetActionInfo(slot)
    if liveType then
        OutDetail(string.format("  type=%s | id=%s | sub=%s",
            SafeStr(liveType), SafeStr(liveId), SafeStr(liveSub)))
    else
        OutDetail("  (empty)")
    end

    Out("Restore dry-run:")
    local actionType = savedInfo.type

    if actionType == "empty" then
        OutDetail("Would clear slot (saved as empty)")
        return
    end

    if actionType == "spell" then
        self:DryRunSpell(slot, savedInfo)
    elseif actionType == "item" then
        self:DryRunItem(slot, savedInfo)
    elseif actionType == "macro" then
        self:DryRunMacro(slot, savedInfo)
    elseif actionType == "companion" then
        self:DryRunCompanion(slot, savedInfo)
    elseif actionType == "equipmentset" then
        self:DryRunEquipmentSet(slot, savedInfo)
    else
        OutError("Unknown action type: " .. SafeStr(actionType))
    end
end

--------------------------------------------------------------------------------
-- Dry-Run Helpers (test without actually placing)
--------------------------------------------------------------------------------

function Diagnose:DryRunSpell(slot, info)
    local name = info.name
    local rank = info.rank
    OutDetail(string.format("Type: spell | name=%s | rank=%s", SafeStr(name), SafeStr(rank)))

    if not name then
        OutError("FAIL: No spell name saved")
        return
    end

    local currentName = ActionBar:GetSpellNameFromTooltip(slot)
    if currentName and currentName == name then
        OutOK("Already in slot (tooltip matches) -- restore would skip")
        return
    end

    local found = self:FindInSpellbook(name)
    if found then
        local isPassive = IsPassiveSpell(found, BOOKTYPE_SPELL)
        if isPassive then
            OutWarn("Found in spellbook but PASSIVE -- cannot place")
        else
            OutOK(string.format("Found in spellbook at index %d -- restore should succeed", found))
        end
    else
        OutError("NOT in spellbook -- restore will fail with 'not found'")
    end
end

function Diagnose:DryRunItem(slot, info)
    local itemID = info.id
    local name = info.name
    OutDetail(string.format("Type: item | id=%s | name=%s", SafeStr(itemID), SafeStr(name)))

    if not itemID then
        OutError("FAIL: No item ID saved")
        return
    end

    PickupItem(itemID)
    local hasItem = CursorHasItem()
    ClearCursor()

    if hasItem then
        OutOK("PickupItem succeeded -- restore should work")
    else
        OutError("PickupItem FAILED -- cursor was empty after PickupItem(" .. itemID .. ")")
        OutDetail("This item may need a different restore method (bag scan, equipped check, etc)")

        self:SearchBagsForItem(itemID, name)
    end
end

function Diagnose:DryRunMacro(slot, info)
    local name = info.name
    local savedIndex = info.id
    OutDetail(string.format("Type: macro | name=%s | savedIndex=%s", SafeStr(name), SafeStr(savedIndex)))

    if not name then
        OutError("FAIL: No macro name saved")

        if savedIndex then
            local mName, mIcon, mBody = GetMacroInfo(savedIndex)
            OutDetail(string.format("GetMacroInfo(%s) returns: name=%s icon=%s body=%s",
                SafeStr(savedIndex), SafeStr(mName), SafeStr(mIcon),
                SafeStr(mBody and mBody:sub(1, 40))))
        end
        return
    end

    local foundIndex = GetMacroIndexByName(name)
    if foundIndex and foundIndex > 0 then
        OutOK(string.format("GetMacroIndexByName('%s') = %d -- restore should work", name, foundIndex))
    else
        OutError(string.format("GetMacroIndexByName('%s') = nil/0 -- restore will fail", name))

        OutDetail("Existing macros:")
        local numGlobal = GetNumMacros()
        for i = 1, numGlobal do
            local mName = GetMacroInfo(i)
            if mName then
                OutDetail(string.format("  [%d] %s", i, mName))
            end
        end
    end
end

function Diagnose:DryRunCompanion(slot, info)
    local companionType = info.companionType or info.subType
    local companionID = info.id
    OutDetail(string.format("Type: companion | companionType=%s | listIndex=%s",
        SafeStr(companionType), SafeStr(companionID)))

    if not companionType or not companionID then
        OutError("FAIL: Missing companionType or id")
        return
    end

    local numCompanions = GetNumCompanions(companionType) or 0
    OutDetail(string.format("Total %s companions available: %d", companionType, numCompanions))

    if companionID >= 1 and companionID <= numCompanions then
        local creatureID, creatureName = GetCompanionInfo(companionType, companionID)
        OutOK(string.format("Index %d valid (name=%s) -- restore should work",
            companionID, SafeStr(creatureName)))
    else
        OutError(string.format("Index %d out of range (1-%d) -- restore will fail", companionID, numCompanions))
        OutDetail("All available companions:")
        for i = 1, numCompanions do
            local creatureID, creatureName = GetCompanionInfo(companionType, i)
            OutDetail(string.format("  [%d] creatureID=%s name=%s", i, SafeStr(creatureID), SafeStr(creatureName)))
        end
    end
end

function Diagnose:DryRunEquipmentSet(slot, info)
    local setName = info.setName or info.id
    OutDetail(string.format("Type: equipmentset | name=%s", SafeStr(setName)))

    if not setName then
        OutError("FAIL: No set name")
        return
    end

    local numSets = GetNumEquipmentSets()
    for i = 1, numSets do
        local name = GetEquipmentSetInfo(i)
        if name == setName then
            OutOK(string.format("FOUND set '%s' -- restore should work", setName))
            return
        end
    end
    OutError(string.format("Equipment set '%s' not found", setName))
end

--------------------------------------------------------------------------------
-- Bag Search (for diagnosing item restore failures)
--------------------------------------------------------------------------------

function Diagnose:SearchBagsForItem(itemID, itemName)
    OutDetail("Searching bags for itemID " .. SafeStr(itemID) .. ":")
    local found = false

    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        for bagSlot = 1, numSlots do
            local link = GetContainerItemLink(bag, bagSlot)
            if link then
                local linkID = link:match("item:(%d+)")
                if linkID and tonumber(linkID) == itemID then
                    OutOK(string.format("  Found in bag %d slot %d: %s", bag, bagSlot, link))
                    found = true
                end
            end
        end
    end

    if not found then
        OutError("  Not found in any bag")
    end

    OutDetail("Checking equipped slots:")
    local foundEquipped = false
    for equipSlot = 1, 19 do
        local link = GetInventoryItemLink("player", equipSlot)
        if link then
            local linkID = link:match("item:(%d+)")
            if linkID and tonumber(linkID) == itemID then
                OutOK(string.format("  Equipped in slot %d: %s", equipSlot, link))
                foundEquipped = true
            end
        end
    end

    if not foundEquipped then
        OutDetail("  Not found equipped")
    end
end

--------------------------------------------------------------------------------
-- Compare: Show saved vs live for all non-empty slots on current level
--------------------------------------------------------------------------------

function Diagnose:Compare()
    local level = Utils:GetPlayerLevel()
    local layout, source = Layout:Get(level)

    if not layout then
        Out(string.format("No saved layout for level %d -- nothing to compare", level))
        return
    end

    Out(string.format("=== Saved vs Live: Level %d (%s) ===", level, source or "unknown"))

    local matches = 0
    local mismatches = 0
    local savedOnly = 0
    local liveOnly = 0

    for slot = 1, Settings.TOTAL_SLOTS do
        if not Profile:IsSlotEnabled(slot) then
        else
            local savedInfo = layout.slots and layout.slots[slot]
            local liveType, liveId, liveSub = GetActionInfo(slot)

            local savedType = savedInfo and savedInfo.type or "empty"
            local savedId = savedInfo and savedInfo.id
            local savedName = savedInfo and savedInfo.name

            local liveIsEmpty = (liveType == nil)
            local savedIsEmpty = (savedType == "empty" or savedType == nil)

            if savedIsEmpty and liveIsEmpty then
            elseif savedIsEmpty and not liveIsEmpty then
                liveOnly = liveOnly + 1
            elseif not savedIsEmpty and liveIsEmpty then
                savedOnly = savedOnly + 1
                local bar = ActionBar:GetBarFromSlot(slot)
                local pos = ActionBar:GetPositionInBar(slot)
                OutWarn(string.format(
                    "Slot %d (Bar %d #%d): SAVED=%s '%s' | LIVE=(empty)",
                    slot, bar, pos,
                    SafeStr(savedType), SafeStr(savedName or savedId)
                ))
            else
                local same = (savedType == liveType) and (savedId == liveId)
                if same then
                    matches = matches + 1
                else
                    mismatches = mismatches + 1
                    local bar = ActionBar:GetBarFromSlot(slot)
                    local pos = ActionBar:GetPositionInBar(slot)
                    local liveName = ActionBar:GetSpellNameFromTooltip(slot) or SafeStr(liveId)
                    OutError(string.format(
                        "Slot %d (Bar %d #%d): SAVED=%s '%s' | LIVE=%s '%s'",
                        slot, bar, pos,
                        SafeStr(savedType), SafeStr(savedName or savedId),
                        SafeStr(liveType), liveName
                    ))
                end
            end
        end
    end

    Out("---")
    Out(string.format("Matches: %d | Mismatches: %d | Saved-only: %d | Live-only: %d",
        matches, mismatches, savedOnly, liveOnly))
end
