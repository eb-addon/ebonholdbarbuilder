--[[----------------------------------------------------------------------------
    Per-level layout storage and retrieval within the active spec.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Layout = {}

local Layout = EBB.Layout
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile

--------------------------------------------------------------------------------
-- Session Storage
--------------------------------------------------------------------------------

local sessionLayouts = {}

--------------------------------------------------------------------------------
-- Get layouts table for a spec
--------------------------------------------------------------------------------

local function GetSpecLayouts(specIndex)
    specIndex = specIndex or Profile:GetActive()
    
    local spec = EBB_CharDB.specs[specIndex]
    if not spec then
        return nil
    end
    
    if not spec.layouts then
        spec.layouts = {}
    end
    
    return spec.layouts
end

local function GetSessionLayouts(specIndex)
    specIndex = specIndex or Profile:GetActive()
    
    if not sessionLayouts[specIndex] then
        sessionLayouts[specIndex] = {}
    end
    
    return sessionLayouts[specIndex]
end

--------------------------------------------------------------------------------
-- Layout Operations
--------------------------------------------------------------------------------

function Layout:Save(level, snapshot, specIndex)
    if not snapshot then return false end
    
    level = level or Utils:GetPlayerLevel()
    specIndex = specIndex or Profile:GetActive()
    
    local layouts = GetSpecLayouts(specIndex)
    if not layouts then
        return false
    end
    
    layouts[level] = Utils:DeepCopy(snapshot)
    
    local session = GetSessionLayouts(specIndex)
    session[level] = Utils:DeepCopy(snapshot)
    
    return true
end

function Layout:Get(level, specIndex)
    level = level or Utils:GetPlayerLevel()
    specIndex = specIndex or Profile:GetActive()
    
    local layouts = GetSpecLayouts(specIndex)
    if layouts and layouts[level] then
        return layouts[level], "saved"
    end
    
    local session = GetSessionLayouts(specIndex)
    if session and session[level] then
        return session[level], "session"
    end
    
    return nil, nil
end

function Layout:Has(level, specIndex)
    level = level or Utils:GetPlayerLevel()
    specIndex = specIndex or Profile:GetActive()
    
    local layouts = GetSpecLayouts(specIndex)
    if layouts and layouts[level] then
        return true
    end
    
    local session = GetSessionLayouts(specIndex)
    if session and session[level] then
        return true
    end
    
    return false
end

function Layout:Delete(level, specIndex)
    level = level or Utils:GetPlayerLevel()
    specIndex = specIndex or Profile:GetActive()
    
    local layouts = GetSpecLayouts(specIndex)
    if layouts then
        layouts[level] = nil
    end
    
    local session = GetSessionLayouts(specIndex)
    if session then
        session[level] = nil
    end
end

function Layout:ClearAll(specIndex)
    specIndex = specIndex or Profile:GetActive()
    
    local spec = EBB_CharDB.specs[specIndex]
    if spec then
        spec.layouts = {}
    end
    
    sessionLayouts[specIndex] = {}
end

--------------------------------------------------------------------------------
-- Layout Listing
--------------------------------------------------------------------------------

function Layout:GetSavedLevels(specIndex)
    specIndex = specIndex or Profile:GetActive()
    
    local levels = {}
    local layouts = GetSpecLayouts(specIndex)
    
    if layouts then
        for level in pairs(layouts) do
            table.insert(levels, level)
        end
    end
    
    table.sort(levels)
    return levels
end

function Layout:GetCount(specIndex)
    specIndex = specIndex or Profile:GetActive()
    
    local count = 0
    local layouts = GetSpecLayouts(specIndex)
    
    if layouts then
        for _ in pairs(layouts) do
            count = count + 1
        end
    end
    
    return count
end

--------------------------------------------------------------------------------
-- Session Management
--------------------------------------------------------------------------------

function Layout:ClearSessionData()
    sessionLayouts = {}
end

--------------------------------------------------------------------------------
-- Keyframe-Aware Queries
--------------------------------------------------------------------------------

function Layout:GetEffective(level, specIndex)
    local Keyframe = EBB.Keyframe
    
    if Keyframe and Keyframe:GetCount(specIndex) > 0 then
        return Keyframe:GetEffectiveLayout(level, specIndex)
    end
    
    return self:Get(level, specIndex)
end

function Layout:GetLevelsInRange(fromLevel, toLevel, specIndex)
    local levels = self:GetSavedLevels(specIndex)
    local result = {}
    
    for _, level in ipairs(levels) do
        if level >= fromLevel and level <= toLevel then
            table.insert(result, level)
        end
    end
    
    return result
end
