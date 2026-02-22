--[[----------------------------------------------------------------------------
    Clipboard, Push, and Undo system.
    Provides copy/paste of layouts between levels, push up/down with
    slot-level diff, and a multi-level undo stack.
    All clipboard/undo state is session-only (not persisted).
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Clipboard = {}

local Clipboard = EBB.Clipboard
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile
local SpellCache = EBB.SpellCache

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_UNDO_DEPTH = 20

--------------------------------------------------------------------------------
-- Session State
--------------------------------------------------------------------------------

local clipboardBuffer = nil   
local undoStack = {}    

--------------------------------------------------------------------------------
-- Clipboard: Copy / Paste
--------------------------------------------------------------------------------

function Clipboard:Copy(level, specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout

    local layout = Layout:Get(level, specIndex)
    if not layout then
        return false, "No layout at level " .. level
    end

    clipboardBuffer = {
        layout = Utils:DeepCopy(layout),
        sourceLevel = level,
        sourceSpec = specIndex,
    }

    return true
end

function Clipboard:HasContent()
    return clipboardBuffer ~= nil
end

function Clipboard:GetInfo()
    if not clipboardBuffer then return nil end
    return {
        sourceLevel = clipboardBuffer.sourceLevel,
        sourceSpec = clipboardBuffer.sourceSpec,
    }
end

function Clipboard:Clear()
    clipboardBuffer = nil
end

function Clipboard:Paste(targetLevel, specIndex, smartAdjust)
    if not clipboardBuffer then
        return false, "Nothing on clipboard"
    end

    specIndex = specIndex or Profile:GetActive()
    smartAdjust = (smartAdjust ~= false)

    local Layout = EBB.Layout
    local Keyframe = EBB.Keyframe

    self:PushUndo(targetLevel, specIndex, "Paste from level " .. clipboardBuffer.sourceLevel)

    local pastedLayout
    if smartAdjust and Keyframe then
        pastedLayout = Keyframe:DeriveLayout(clipboardBuffer.layout, targetLevel)
    else
        pastedLayout = Utils:DeepCopy(clipboardBuffer.layout)
    end

    pastedLayout.playerLevel = targetLevel
    pastedLayout.timestamp = Utils:GetTimestamp()
    pastedLayout.isDerived = nil

    Layout:Save(targetLevel, pastedLayout, specIndex)

    return true
end

--------------------------------------------------------------------------------
-- Slot-Level Diff
--------------------------------------------------------------------------------

function Clipboard:ComputeDiff(beforeLayout, afterLayout)
    local changes = {}

    for slot = 1, Settings.TOTAL_SLOTS do
        local before = beforeLayout and beforeLayout.slots and beforeLayout.slots[slot]
        local after = afterLayout and afterLayout.slots and afterLayout.slots[slot]

        if self:SlotsDiffer(before, after) then
            changes[slot] = after and Utils:DeepCopy(after) or { type = "empty", slot = slot }
        end
    end

    return changes
end

function Clipboard:SlotsDiffer(a, b)
    local aEmpty = not a or a.type == "empty"
    local bEmpty = not b or b.type == "empty"

    if aEmpty and bEmpty then return false end
    if aEmpty ~= bEmpty then return true end

    if a.type ~= b.type then return true end

    if a.type == "spell" then
        return a.name ~= b.name or a.rank ~= b.rank
    elseif a.type == "macro" then
        return a.name ~= b.name or a.id ~= b.id
    elseif a.type == "item" then
        return a.id ~= b.id
    elseif a.type == "companion" then
        return a.id ~= b.id or a.companionType ~= b.companionType
    elseif a.type == "equipmentset" then
        return a.setName ~= b.setName
    end

    return false
end

--------------------------------------------------------------------------------
-- Push Up / Push Down
--------------------------------------------------------------------------------

function Clipboard:ApplyChanges(changes, targetLevel, specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout
    local Keyframe = EBB.Keyframe

    local layout = Layout:Get(targetLevel, specIndex)
    if not layout then
        return false, "No layout at level " .. targetLevel
    end

    -- Save undo
    self:PushUndo(targetLevel, specIndex, "Push changes to level " .. targetLevel)

    local updated = Utils:DeepCopy(layout)

    for slot, slotInfo in pairs(changes) do
        if slotInfo.type == "spell" and slotInfo.name and Keyframe then
            -- Adjust rank for the target level
            local adjusted = Keyframe:AdjustSpellRank(slotInfo, targetLevel)
            updated.slots[slot] = adjusted
        else
            updated.slots[slot] = Utils:DeepCopy(slotInfo)
        end
    end

    -- Recount configured slots
    local configured = 0
    for s = 1, Settings.TOTAL_SLOTS do
        if updated.slots[s] and updated.slots[s].type ~= "empty" then
            configured = configured + 1
        end
    end
    updated.configuredSlots = configured

    Layout:Save(targetLevel, updated, specIndex)
    return true
end

--- Push the source layout to target levels using per-target diffs.
--- For each target, we compare the source against that target and apply the
--- source's version of any slots that differ.  This means:
---   - Slots the source has that the target doesn't → added to target
---   - Slots the source cleared that the target has  → cleared on target (only if overwrite=true)
---   - Slots that match (same spell/item)            → left alone
---   - Spell ranks are adjusted to the target level via AdjustSpellRank
---
--- `direction` is "up" or "down".
--- `limitLevel` is the level to stop at (inclusive). If nil, pushes to boundary.
--- `overwrite` if true, also pushes empty slots (clears target slots). Default false.
function Clipboard:PushToTargets(sourceLayout, sourceLevel, direction, limitLevel, specIndex, overwrite)
    specIndex = specIndex or Profile:GetActive()
    overwrite = (overwrite == true)
    local Layout = EBB.Layout
    local Keyframe = EBB.Keyframe

    if not sourceLayout or not sourceLayout.slots then
        return 0, "No source layout"
    end

    local levels = Layout:GetSavedLevels(specIndex)
    local affectedCount = 0

    -- Determine range boundaries
    local lowerLimit, upperLimit

    if direction == "up" then
        upperLimit = limitLevel or Settings.MAX_LEVEL
        if Keyframe and not limitLevel then
            local nextKF = Keyframe:GetNearestAbove(sourceLevel, specIndex)
            if nextKF then
                upperLimit = nextKF - 1
            end
        end
    elseif direction == "down" then
        lowerLimit = limitLevel or 1
        if Keyframe and not limitLevel then
            local prevKF = Keyframe:GetNearestBelow(sourceLevel - 1, specIndex)
            if prevKF then
                lowerLimit = prevKF + 1
            end
        end
    end

    -- Iterate over saved levels in the appropriate direction
    local iterLevels = {}
    if direction == "up" then
        for _, level in ipairs(levels) do
            if level > sourceLevel and level <= upperLimit then
                table.insert(iterLevels, level)
            end
        end
    elseif direction == "down" then
        for i = #levels, 1, -1 do
            local level = levels[i]
            if level < sourceLevel and level >= lowerLimit then
                table.insert(iterLevels, level)
            end
        end
    end

    for _, targetLevel in ipairs(iterLevels) do
        local targetLayout = Layout:Get(targetLevel, specIndex)
        if targetLayout then
            -- Diff the source against THIS specific target
            local rawChanges = self:ComputeDiff(targetLayout, sourceLayout)
            
            -- Filter: by default only push non-empty slots from source (additive).
            -- If overwrite is true, also push empty slots (clearing target content).
            local changes = {}
            for slot, slotInfo in pairs(rawChanges) do
                if overwrite then
                    changes[slot] = slotInfo
                elseif slotInfo and slotInfo.type and slotInfo.type ~= "empty" then
                    changes[slot] = slotInfo
                end
            end
            
            if next(changes) then
                local ok = self:ApplyChanges(changes, targetLevel, specIndex)
                if ok then
                    affectedCount = affectedCount + 1
                end
            end
        end
    end

    return affectedCount
end

--- Legacy method kept for backward compat — prefer PushToTargets.
function Clipboard:PushChanges(sourceLevel, beforeLayout, afterLayout, direction, limitLevel, specIndex)
    specIndex = specIndex or Profile:GetActive()

    local changes = self:ComputeDiff(beforeLayout, afterLayout)
    if not next(changes) then
        return 0, "No changes to push"
    end

    local Layout = EBB.Layout
    local Keyframe = EBB.Keyframe
    local levels = Layout:GetSavedLevels(specIndex)
    local affectedCount = 0

    local lowerLimit, upperLimit

    if direction == "up" then
        upperLimit = limitLevel or Settings.MAX_LEVEL
        if Keyframe and not limitLevel then
            local nextKF = Keyframe:GetNearestAbove(sourceLevel, specIndex)
            if nextKF then
                upperLimit = nextKF - 1
            end
        end

        for _, level in ipairs(levels) do
            if level > sourceLevel and level <= upperLimit then
                local ok = self:ApplyChanges(changes, level, specIndex)
                if ok then
                    affectedCount = affectedCount + 1
                end
            end
        end

    elseif direction == "down" then
        lowerLimit = limitLevel or 1
        if Keyframe and not limitLevel then
            local prevKF = Keyframe:GetNearestBelow(sourceLevel - 1, specIndex)
            if prevKF then
                lowerLimit = prevKF + 1
            end
        end

        for i = #levels, 1, -1 do
            local level = levels[i]
            if level < sourceLevel and level >= lowerLimit then
                local ok = self:ApplyChanges(changes, level, specIndex)
                if ok then
                    affectedCount = affectedCount + 1
                end
            end
        end
    end

    return affectedCount
end

--------------------------------------------------------------------------------
-- Undo Stack
--------------------------------------------------------------------------------

function Clipboard:PushUndo(level, specIndex, description)
    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout

    local currentLayout = Layout:Get(level, specIndex)

    table.insert(undoStack, {
        level = level,
        specIndex = specIndex,
        previousLayout = currentLayout and Utils:DeepCopy(currentLayout) or nil,
        description = description or ("Change at level " .. level),
        timestamp = Utils:GetTimestamp(),
    })

    -- Trim to max depth
    while #undoStack > MAX_UNDO_DEPTH do
        table.remove(undoStack, 1)
    end
end

function Clipboard:Undo()
    if #undoStack == 0 then
        return false, "Nothing to undo"
    end

    local entry = table.remove(undoStack)
    local Layout = EBB.Layout

    if entry.previousLayout then
        Layout:Save(entry.level, entry.previousLayout, entry.specIndex)
    else
        Layout:Delete(entry.level, entry.specIndex)
    end

    return true, entry.description, entry.level
end

function Clipboard:CanUndo()
    return #undoStack > 0
end

function Clipboard:GetUndoDescription()
    if #undoStack == 0 then return nil end
    return undoStack[#undoStack].description
end

function Clipboard:GetUndoCount()
    return #undoStack
end

function Clipboard:ClearUndoStack()
    undoStack = {}
end

function Clipboard:GetUndoStack()
    local result = {}
    for i = #undoStack, 1, -1 do
        table.insert(result, {
            description = undoStack[i].description,
            level = undoStack[i].level,
            timestamp = undoStack[i].timestamp,
        })
    end
    return result
end
