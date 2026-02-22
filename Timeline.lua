--[[----------------------------------------------------------------------------
    Timeline behavior and diff computation.
    Manages the visual timeline data model and computes "what changes"
    summaries between levels.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Timeline = {}

local Timeline = EBB.Timeline
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile

--------------------------------------------------------------------------------
-- Level Entry Types
--------------------------------------------------------------------------------

local ENTRY_TYPES = {
    EMPTY = "empty",          
    KEYFRAME = "keyframe",    
    SAVED = "saved",           
    DERIVED = "derived",      
    CURRENT = "current",    
}

Timeline.ENTRY_TYPES = ENTRY_TYPES

--------------------------------------------------------------------------------
-- Build Timeline Data
--------------------------------------------------------------------------------

function Timeline:Build(specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout
    local Keyframe = EBB.Keyframe

    local currentLevel = Utils:GetPlayerLevel()
    local savedLevels = Layout:GetSavedLevels(specIndex)
    local savedSet = {}
    for _, level in ipairs(savedLevels) do
        savedSet[level] = true
    end

    local keyframeSet = {}
    if Keyframe then
        local kfLevels = Keyframe:GetAll(specIndex)
        for _, level in ipairs(kfLevels) do
            keyframeSet[level] = true
        end
    end

    local entries = {}

    for level = 1, Settings.MAX_LEVEL do
        local entry = {
            level = level,
            isCurrent = (level == currentLevel),
            isKeyframe = keyframeSet[level] == true,
            isSaved = savedSet[level] == true,
            isDerived = false,
            entryType = ENTRY_TYPES.EMPTY,
        }

        if entry.isKeyframe and entry.isSaved then
            entry.entryType = ENTRY_TYPES.KEYFRAME
        elseif entry.isSaved then
            entry.entryType = ENTRY_TYPES.SAVED
        elseif Keyframe and Keyframe:IsDerived(level, specIndex) then
            entry.isDerived = true
            entry.entryType = ENTRY_TYPES.DERIVED
        end

        entries[level] = entry
    end

    return entries
end

function Timeline:GetActiveLevels(specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout
    local Keyframe = EBB.Keyframe

    local levels = {}
    local savedLevels = Layout:GetSavedLevels(specIndex)
    local savedSet = {}

    for _, level in ipairs(savedLevels) do
        savedSet[level] = true
        table.insert(levels, level)
    end

    if Keyframe and Keyframe:GetCount(specIndex) > 0 then
        local kfLevels = Keyframe:GetAll(specIndex)
        for i = 1, #kfLevels do
            local kfLevel = kfLevels[i]
            local nextKF = kfLevels[i + 1] or (Settings.MAX_LEVEL + 1)

            for level = kfLevel + 1, math.min(nextKF - 1, Settings.MAX_LEVEL) do
                if not savedSet[level] then
                end
            end
        end
    end

    local seen = {}
    local result = {}
    for _, level in ipairs(levels) do
        if not seen[level] then
            seen[level] = true
            table.insert(result, level)
        end
    end
    table.sort(result)

    return result
end

--------------------------------------------------------------------------------
-- Diff Computation: "What Changes at This Level"
--------------------------------------------------------------------------------

function Timeline:ComputeDiff(layoutA, layoutB)
    local changes = {
        rankUpgrades = {},     
        rankDowngrades = {},   
        newSpells = {},        
        removedSpells = {},    
        replacedSlots = {},   
        newItems = {},         
        removedItems = {},    
        totalChanges = 0,
    }

    for slot = 1, Settings.TOTAL_SLOTS do
        local a = layoutA and layoutA.slots and layoutA.slots[slot]
        local b = layoutB and layoutB.slots and layoutB.slots[slot]

        local aEmpty = not a or a.type == "empty"
        local bEmpty = not b or b.type == "empty"

        if aEmpty and bEmpty then
        elseif aEmpty and not bEmpty then
            if b.type == "spell" then
                table.insert(changes.newSpells, {
                    slot = slot,
                    name = b.name or "Unknown",
                    rank = b.rank or "",
                })
            else
                table.insert(changes.newItems, {
                    slot = slot,
                    type = b.type,
                    name = b.name or b.setName or "Unknown",
                })
            end
            changes.totalChanges = changes.totalChanges + 1

        elseif not aEmpty and bEmpty then
            if a.type == "spell" then
                table.insert(changes.removedSpells, {
                    slot = slot,
                    name = a.name or "Unknown",
                    rank = a.rank or "",
                })
            else
                table.insert(changes.removedItems, {
                    slot = slot,
                    type = a.type,
                    name = a.name or a.setName or "Unknown",
                })
            end
            changes.totalChanges = changes.totalChanges + 1

        else
            if a.type == "spell" and b.type == "spell" and a.name == b.name then
                if a.rank ~= b.rank then
                    local aRank = self:ParseRankNumber(a.rank)
                    local bRank = self:ParseRankNumber(b.rank)

                    if bRank > aRank then
                        table.insert(changes.rankUpgrades, {
                            slot = slot,
                            name = a.name,
                            fromRank = a.rank,
                            toRank = b.rank,
                        })
                    else
                        table.insert(changes.rankDowngrades, {
                            slot = slot,
                            name = a.name,
                            fromRank = a.rank,
                            toRank = b.rank,
                        })
                    end
                    changes.totalChanges = changes.totalChanges + 1
                end
            elseif a.type ~= b.type or a.name ~= b.name or a.id ~= b.id then
                table.insert(changes.replacedSlots, {
                    slot = slot,
                    from = {
                        type = a.type,
                        name = a.name or a.setName or "Unknown",
                    },
                    to = {
                        type = b.type,
                        name = b.name or b.setName or "Unknown",
                    },
                })
                changes.totalChanges = changes.totalChanges + 1
            end
        end
    end

    return changes
end

function Timeline:GetChangeSummary(level, specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Keyframe = EBB.Keyframe
    local Layout = EBB.Layout

    local thisLayout
    if Keyframe then
        thisLayout = Keyframe:GetEffectiveLayout(level, specIndex)
    else
        thisLayout = Layout:Get(level, specIndex)
    end

    if not thisLayout then
        return nil
    end

    local prevLayout
    if Keyframe then
        prevLayout = Keyframe:GetEffectiveLayout(level - 1, specIndex)
    else
        prevLayout = Layout:Get(level - 1, specIndex)
    end

    if not prevLayout then
        return self:ComputeDiff(nil, thisLayout)
    end

    return self:ComputeDiff(prevLayout, thisLayout)
end

function Timeline:FormatSummary(diff)
    if not diff then return {} end

    local lines = {}

    for _, change in ipairs(diff.rankUpgrades) do
        table.insert(lines, {
            text = string.format("%s: %s -> %s",
                change.name, change.fromRank or "?", change.toRank or "?"),
            color = { 0.3, 1, 0.3 },
            type = "upgrade",
        })
    end

    for _, change in ipairs(diff.newSpells) do
        local rankStr = (change.rank and change.rank ~= "")
            and (" (" .. change.rank .. ")") or ""
        table.insert(lines, {
            text = "+ " .. change.name .. rankStr,
            color = { 0.3, 0.8, 1 },
            type = "new",
        })
    end

    for _, change in ipairs(diff.newItems) do
        table.insert(lines, {
            text = "+ " .. change.name .. " (" .. change.type .. ")",
            color = { 0.3, 0.8, 1 },
            type = "new",
        })
    end

    for _, change in ipairs(diff.replacedSlots) do
        table.insert(lines, {
            text = string.format("Slot %d: %s -> %s",
                change.slot, change.from.name, change.to.name),
            color = { 1, 0.8, 0.3 },
            type = "replaced",
        })
    end

    for _, change in ipairs(diff.rankDowngrades) do
        table.insert(lines, {
            text = string.format("%s: %s -> %s",
                change.name, change.fromRank or "?", change.toRank or "?"),
            color = { 1, 0.5, 0.5 },
            type = "downgrade",
        })
    end

    for _, change in ipairs(diff.removedSpells) do
        table.insert(lines, {
            text = "- " .. change.name,
            color = { 0.6, 0.6, 0.6 },
            type = "removed",
        })
    end

    for _, change in ipairs(diff.removedItems) do
        table.insert(lines, {
            text = "- " .. change.name,
            color = { 0.6, 0.6, 0.6 },
            type = "removed",
        })
    end

    return lines
end

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------

function Timeline:ParseRankNumber(rank)
    if not rank or rank == "" then return 0 end
    local num = rank:match("Rank (%d+)")
    return tonumber(num) or 0
end
