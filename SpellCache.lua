--[[----------------------------------------------------------------------------
    Account-wide spell/rank level availability cache.
    Tracks the lowest level at which each spell+rank was observed per class.
    Stored in EBB_DB (SavedVariables, shared across characters).
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.SpellCache = {}

local SpellCache = EBB.SpellCache

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function SpellCache:Initialize()
    if not EBB_DB then
        EBB_DB = {}
    end
    if not EBB_DB.spellCache then
        EBB_DB.spellCache = {}
    end
end

--------------------------------------------------------------------------------
-- Class Cache Access
--------------------------------------------------------------------------------

local playerClass = nil

function SpellCache:GetClassCache()
    if not playerClass then
        local _, classFile = UnitClass("player")
        playerClass = classFile
    end

    if not EBB_DB or not EBB_DB.spellCache then
        return {}
    end

    if not EBB_DB.spellCache[playerClass] then
        EBB_DB.spellCache[playerClass] = {}
    end

    return EBB_DB.spellCache[playerClass]
end

--------------------------------------------------------------------------------
-- Spellbook Scan
--------------------------------------------------------------------------------

function SpellCache:ScanSpellbook(overrideLevel)
    local cache = self:GetClassCache()
    local level = overrideLevel or UnitLevel("player")
    local numTabs = GetNumSpellTabs()

    for tabIndex = 1, numTabs do
        local tabName, _, offset, numSpells = GetSpellTabInfo(tabIndex)
        for spellIndex = offset + 1, offset + numSpells do
            if not IsPassiveSpell(spellIndex, BOOKTYPE_SPELL) then
                local spellName, spellRank = GetSpellName(spellIndex, BOOKTYPE_SPELL)
                if spellName then
                    if not cache[spellName] then
                        cache[spellName] = {}
                    end
                    local rank = spellRank or ""
                    local existing = cache[spellName][rank]
                    local existingLevel = self:ReadEntryLevel(existing)

                    if not existingLevel or level < existingLevel then
                        local icon = GetSpellTexture(spellIndex, BOOKTYPE_SPELL)
                        cache[spellName][rank] = { level = level, tab = tabName, icon = icon }
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Trainer Scan
--------------------------------------------------------------------------------

function SpellCache:ScanTrainer()
    local numServices = GetNumTrainerServices and GetNumTrainerServices() or 0
    if numServices == 0 then return end

    local cache = self:GetClassCache()
    local scanned = 0

    for i = 1, numServices do
        local name, rankText, category = GetTrainerServiceInfo(i)
        if name and category ~= "header" then
            local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or nil
            local icon = GetTrainerServiceIcon and GetTrainerServiceIcon(i) or nil

            if level and level > 0 then
                local rank = rankText or ""

                if not cache[name] then
                    cache[name] = {}
                end

                local existing = cache[name][rank]
                local existingLevel = self:ReadEntryLevel(existing)

                -- Trainer provides authoritative level requirements,
                -- so always prefer trainer data over spellbook-inferred data
                if not existingLevel or level < existingLevel then
                    -- Try to preserve existing icon/tab if trainer doesn't provide one
                    local existingIcon = self:ReadEntryIcon(existing)
                    local existingTab = self:ReadEntryTab(existing)

                    cache[name][rank] = {
                        level = level,
                        tab = existingTab,
                        icon = icon or existingIcon,
                        source = "trainer",
                    }
                    scanned = scanned + 1
                end
            end
        end
    end

    -- After trainer scan, do a spellbook scan to fill in tab names
    -- for any entries that are missing them
    self:BackfillTabNames()

    if scanned > 0 then
        EBB.Utils:Print(string.format("Spell cache updated: %d entries from trainer", scanned))
    end
end

--------------------------------------------------------------------------------
-- Backfill tab names from spellbook for trainer-sourced entries
--------------------------------------------------------------------------------

function SpellCache:BackfillTabNames()
    local cache = self:GetClassCache()
    local numTabs = GetNumSpellTabs()

    for tabIndex = 1, numTabs do
        local tabName, _, offset, numSpells = GetSpellTabInfo(tabIndex)
        for spellIndex = offset + 1, offset + numSpells do
            local spellName, spellRank = GetSpellName(spellIndex, BOOKTYPE_SPELL)
            if spellName then
                local rank = spellRank or ""
                if cache[spellName] and cache[spellName][rank] then
                    local entry = cache[spellName][rank]
                    if type(entry) == "table" and not entry.tab then
                        entry.tab = tabName
                    end
                    -- Also backfill icon if missing
                    if type(entry) == "table" and not entry.icon then
                        entry.icon = GetSpellTexture(spellIndex, BOOKTYPE_SPELL)
                    end
                end
            end
        end
    end

    -- For trainer entries that have no tab match in the spellbook yet,
    -- try to infer from other ranks of the same spell
    for spellName, ranks in pairs(cache) do
        local knownTab = nil
        for rank, entry in pairs(ranks) do
            local tab = self:ReadEntryTab(entry)
            if tab then
                knownTab = tab
                break
            end
        end
        if knownTab then
            for rank, entry in pairs(ranks) do
                if type(entry) == "table" and not entry.tab then
                    entry.tab = knownTab
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Backward Compatibility
-- Old format: cache[name][rank] = level (number)
-- New format: cache[name][rank] = { level = N, tab = "Holy", icon = "..." }
--------------------------------------------------------------------------------

function SpellCache:ReadEntryLevel(entry)
    if type(entry) == "number" then
        return entry
    elseif type(entry) == "table" then
        return entry.level
    end
    return nil
end

function SpellCache:ReadEntryTab(entry)
    if type(entry) == "table" then
        return entry.tab
    end
    return nil
end

function SpellCache:ReadEntryIcon(entry)
    if type(entry) == "table" then
        return entry.icon
    end
    return nil
end

function SpellCache:ReadEntrySource(entry)
    if type(entry) == "table" then
        return entry.source
    end
    return nil
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

function SpellCache:GetSpellLevel(spellName, rank)
    local cache = self:GetClassCache()
    rank = rank or ""

    if cache[spellName] and cache[spellName][rank] then
        return self:ReadEntryLevel(cache[spellName][rank])
    end

    return nil
end

function SpellCache:GetSpellTab(spellName, rank)
    local cache = self:GetClassCache()
    rank = rank or ""

    if cache[spellName] and cache[spellName][rank] then
        return self:ReadEntryTab(cache[spellName][rank])
    end

    return nil
end

function SpellCache:GetSpellIcon(spellName, rank)
    local cache = self:GetClassCache()
    rank = rank or ""

    if cache[spellName] and cache[spellName][rank] then
        return self:ReadEntryIcon(cache[spellName][rank])
    end

    return nil
end

function SpellCache:GetSpellSource(spellName, rank)
    local cache = self:GetClassCache()
    rank = rank or ""

    if cache[spellName] and cache[spellName][rank] then
        return self:ReadEntrySource(cache[spellName][rank])
    end

    return nil
end

function SpellCache:IsAvailableAtLevel(spellName, rank, level)
    local spellLevel = self:GetSpellLevel(spellName, rank)
    if not spellLevel then
        return nil
    end
    return level >= spellLevel
end

--------------------------------------------------------------------------------
-- Bulk Query (for SlotEditor higher-level editing)
--------------------------------------------------------------------------------

function SpellCache:GetSpellsForLevel(level)
    local cache = self:GetClassCache()
    local results = {}

    for spellName, ranks in pairs(cache) do
        for rank, entry in pairs(ranks) do
            local spellLevel = self:ReadEntryLevel(entry)
            local tab = self:ReadEntryTab(entry)
            local icon = self:ReadEntryIcon(entry)
            local source = self:ReadEntrySource(entry)
            if spellLevel and spellLevel <= level then
                table.insert(results, {
                    name = spellName,
                    rank = rank,
                    learnLevel = spellLevel,
                    tab = tab,
                    icon = icon,
                    source = source,
                })
            end
        end
    end

    return results
end

--------------------------------------------------------------------------------
-- Cache Reset
--------------------------------------------------------------------------------

function SpellCache:ClearClassCache()
    if not playerClass then
        local _, classFile = UnitClass("player")
        playerClass = classFile
    end

    if EBB_DB and EBB_DB.spellCache then
        EBB_DB.spellCache[playerClass] = {}
    end
end
