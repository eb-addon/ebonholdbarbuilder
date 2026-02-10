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
            if spellLevel and spellLevel <= level then
                table.insert(results, {
                    name = spellName,
                    rank = rank,
                    learnLevel = spellLevel,
                    tab = tab,
                    icon = icon,
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
