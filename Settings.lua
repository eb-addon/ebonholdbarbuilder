--[[----------------------------------------------------------------------------
    Configuration constants and settings management.
    Settings are stored in EBB_CharDB.settings and are character-specific.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Settings = {}

local Settings = EBB.Settings

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

Settings.VERSION = "0.2.1"
Settings.MAX_LEVEL = 80

Settings.DEBOUNCE_TIME = 1.5
Settings.RESTORE_DELAY = 0.5

Settings.TOTAL_SLOTS = 120
Settings.SLOTS_PER_BAR = 12
Settings.TOTAL_BARS = 10

Settings.MAX_UNDO_DEPTH = 20
Settings.MAX_TEMPLATES = 20

-- Recording modes
Settings.RECORD_PER_LEVEL = "per_level"
Settings.RECORD_BREAKPOINT = "breakpoint"

--------------------------------------------------------------------------------
-- Default Settings
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    recordingMode = "per_level",
    hideMinimapButton = false,
    barLabels = {
        [1] = "Action Bar 1",
        [2] = "Action Bar 2",
        [3] = "Action Bar 3",
        [4] = "Action Bar 4",
        [5] = "Action Bar 5",
        [6] = "Action Bar 6",
        [7] = "Stance Bar A",
        [8] = "Stance Bar B",
        [9] = "Stance Bar C",
        [10] = "Stance Bar D",
    },
}

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function Settings:Initialize()
    if not EBB_CharDB.settings then
        EBB_CharDB.settings = {}
    end
    
    for key, value in pairs(DEFAULT_SETTINGS) do
        if EBB_CharDB.settings[key] == nil then
            if type(value) == "table" then
                EBB_CharDB.settings[key] = EBB.Utils:DeepCopy(value)
            else
                EBB_CharDB.settings[key] = value
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Get / Set
--------------------------------------------------------------------------------

function Settings:Get(key)
    if EBB_CharDB.settings then
        return EBB_CharDB.settings[key]
    end
    return DEFAULT_SETTINGS[key]
end

function Settings:Set(key, value)
    if not EBB_CharDB.settings then
        EBB_CharDB.settings = {}
    end
    EBB_CharDB.settings[key] = value
end

--------------------------------------------------------------------------------
-- Bar Labels
--------------------------------------------------------------------------------

function Settings:GetBarLabel(barNumber)
    if barNumber < 1 or barNumber > self.TOTAL_BARS then
        return nil
    end
    
    local labels = self:Get("barLabels")
    if labels and labels[barNumber] then
        return labels[barNumber]
    end
    
    return "Action Bar " .. barNumber
end

function Settings:SetBarLabel(barNumber, label)
    if barNumber < 1 or barNumber > self.TOTAL_BARS then
        return false
    end
    
    local labels = self:Get("barLabels")
    if not labels then
        labels = EBB.Utils:DeepCopy(DEFAULT_SETTINGS.barLabels)
    end
    
    labels[barNumber] = label
    self:Set("barLabels", labels)
    return true
end

function Settings:ResetBarLabels()
    self:Set("barLabels", EBB.Utils:DeepCopy(DEFAULT_SETTINGS.barLabels))
end

--------------------------------------------------------------------------------
-- Recording Mode
--------------------------------------------------------------------------------

function Settings:GetRecordingMode()
    return self:Get("recordingMode") or self.RECORD_PER_LEVEL
end

function Settings:SetRecordingMode(mode)
    if mode ~= self.RECORD_PER_LEVEL and mode ~= self.RECORD_BREAKPOINT then
        return false
    end
    self:Set("recordingMode", mode)
    return true
end

function Settings:IsPerLevelMode()
    return self:GetRecordingMode() == self.RECORD_PER_LEVEL
end

function Settings:IsBreakpointMode()
    return self:GetRecordingMode() == self.RECORD_BREAKPOINT
end

function Settings:GetRecordingModeLabel()
    if self:IsBreakpointMode() then
        return "Breakpoints"
    end
    return "Per-Level"
end

--------------------------------------------------------------------------------
-- Minimap Button
--------------------------------------------------------------------------------

function Settings:IsMinimapButtonHidden()
    return self:Get("hideMinimapButton") == true
end

function Settings:SetMinimapButtonHidden(hidden)
    self:Set("hideMinimapButton", hidden == true)
end

function Settings:ToggleMinimapButton()
    local hidden = not self:IsMinimapButtonHidden()
    self:SetMinimapButtonHidden(hidden)
    return hidden
end
