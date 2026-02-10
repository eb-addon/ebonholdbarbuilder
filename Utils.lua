--[[---------------------------------------------------------------------------- 
    Utilities eg. C_Timer compatibility shim for WotLK 3.3.5
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Utils = {}

local Utils = EBB.Utils

--------------------------------------------------------------------------------
-- Chat Output
--------------------------------------------------------------------------------

function Utils:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[EBB]|r " .. tostring(message))
end

function Utils:PrintSuccess(message)
    self:Print("|cFF00FF00" .. tostring(message) .. "|r")
end

function Utils:PrintError(message)
    self:Print("|cFFFF0000" .. tostring(message) .. "|r")
end

--------------------------------------------------------------------------------
-- Conditional Logging (suppressed by default, toggled via minimap menu)
--------------------------------------------------------------------------------

function Utils:PrintVerbose(message)
    if EBB_CharDB and EBB_CharDB.logVerbose then
        self:Print(message)
    end
end

function Utils:PrintVerboseError(message)
    if EBB_CharDB and EBB_CharDB.logErrors then
        self:PrintError(message)
    end
end

--------------------------------------------------------------------------------
-- WoW API Wrappers
--------------------------------------------------------------------------------

function Utils:GetPlayerLevel()
    return UnitLevel("player")
end

function Utils:GetTimestamp()
    return date("%Y-%m-%d %H:%M:%S")
end

--------------------------------------------------------------------------------
-- Table Utilities
--------------------------------------------------------------------------------

function Utils:DeepCopy(original)
    if type(original) ~= "table" then
        return original
    end
    
    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = self:DeepCopy(value)
        else
            copy[key] = value
        end
    end
    
    return copy
end

--------------------------------------------------------------------------------
-- C_Timer Compatibility Shim (WotLK 3.3.5)
--------------------------------------------------------------------------------

if not C_Timer then
    C_Timer = {}
    
    local activeTimers = {}
    local timerFrame = CreateFrame("Frame")
    local timerID = 0
    
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime()
        local toRemove = {}
        
        for id, timer in pairs(activeTimers) do
            if now >= timer.endTime then
                if timer.callback then
                    timer.callback()
                end
                table.insert(toRemove, id)
            end
        end
        
        for _, id in ipairs(toRemove) do
            activeTimers[id] = nil
        end
        
        if not next(activeTimers) then
            timerFrame:Hide()
        end
    end)
    
    timerFrame:Hide()
    
    function C_Timer.After(seconds, callback)
        timerID = timerID + 1
        activeTimers[timerID] = {
            endTime = GetTime() + seconds,
            callback = callback,
        }
        timerFrame:Show()
        return timerID
    end
end
