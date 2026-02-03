--[[----------------------------------------------------------------------------
    Main addon initialization and event coordination.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Core = {}

local Core = EBB.Core
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile
local Layout = EBB.Layout
local Capture = EBB.Capture
local Restore = EBB.Restore
local Spec = EBB.Spec
local FirstRun = EBB.FirstRun

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local isInitialized = false

--------------------------------------------------------------------------------
-- Debug Logging
--------------------------------------------------------------------------------

local debugMode = false

local function DebugPrint(...)
    if debugMode then
        local args = {...}
        local msg = ""
        for i, v in ipairs(args) do
            msg = msg .. tostring(v)
            if i < #args then msg = msg .. " " end
        end
        Utils:Print("|cFFFFFF00[DEBUG]|r " .. msg)
    end
end

function Core:SetDebugMode(enabled)
    debugMode = enabled
    Utils:Print("Debug mode: " .. (enabled and "ON" or "OFF"))
end

function Core:IsDebugMode()
    return debugMode
end

--------------------------------------------------------------------------------
-- SavedVariables Initialization
--------------------------------------------------------------------------------

local function InitializeSavedVariables()
    if not EBB_CharDB then
        EBB_CharDB = {
            version = Settings.VERSION,
        }
    end
    
    EBB_CharDB.version = Settings.VERSION
    
    Settings:Initialize()
    Profile:Initialize()
end

--------------------------------------------------------------------------------
-- Level Tracking
--------------------------------------------------------------------------------

local function GetLastKnownLevel()
    return EBB_CharDB.lastKnownLevel
end

local function SetLastKnownLevel(level)
    EBB_CharDB.lastKnownLevel = level
end

--------------------------------------------------------------------------------
-- Level-Up Handling with Gap Fill
--------------------------------------------------------------------------------

local function HandleLevelUp(newLevel)
    local oldLevel = GetLastKnownLevel() or (newLevel - 1)
    SetLastKnownLevel(newLevel)
    
    if Layout:Has(newLevel) then
        Capture:Cancel()
        Restore:Perform(newLevel)
        return
    end
    
    local snapshot = Capture:GetSnapshot()
    if snapshot then
        local gapsFilled = 0
        for level = oldLevel + 1, newLevel do
            if not Layout:Has(level) then
                Layout:Save(level, snapshot)
                gapsFilled = gapsFilled + 1
            end
        end
        
        if gapsFilled > 0 then
            if gapsFilled == 1 then
                Utils:Print(string.format("Level %d: Layout saved", newLevel))
            else
                Utils:Print(string.format("Levels %d-%d: %d layouts saved", 
                    oldLevel + 1, newLevel, gapsFilled))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Level 1 Return Detection
--------------------------------------------------------------------------------

local function HandleLevelChange(newLevel)
    local oldLevel = GetLastKnownLevel()
    
    if oldLevel and oldLevel > 1 and newLevel == 1 then
        SetLastKnownLevel(newLevel)
        if Layout:Has(1) then
            Utils:Print("Returned to level 1: Restoring bars")
            Restore:Perform(1)
        end
        return true
    end
    
    return false
end

--------------------------------------------------------------------------------
-- Public State
--------------------------------------------------------------------------------

function Core:IsReady()
    return isInitialized and FirstRun:CanAddonRun() and Spec:IsConfirmed()
end

function Core:RegisterSpecChangeCallback(callback)
    return Spec:RegisterChangeCallback(callback)
end

function Core:GetActiveSpec()
    return Spec:GetActive()
end

function Core:SwitchSpec(specIndex)
    return Spec:Switch(specIndex)
end

function Core:IsSpecSwitchPending()
    return Spec:IsSwitchPending()
end

function Core:GetPendingSpec()
    return Spec:GetPendingSpec()
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

local function OnAddonLoaded(addonName)
    if addonName ~= ADDON_NAME then return end
    
    DebugPrint("ADDON_LOADED:", addonName)
    InitializeSavedVariables()
end

local function OnPlayerEnteringWorld()
    DebugPrint("PLAYER_ENTERING_WORLD, isInitialized:", tostring(isInitialized))
    
    if isInitialized then return end
    isInitialized = true
    
    local firstRunResult = FirstRun:CheckOnLoad()
    DebugPrint("FirstRun check result:", firstRunResult)
    
    if firstRunResult == "show_popup" then
        C_Timer.After(0.5, function()
            FirstRun:Show()
        end)
        return
    elseif firstRunResult == "disabled_permanent" then
        DebugPrint("Addon disabled by user choice")
        return
    end
    
    Core:InitializeAddon()
end

function Core:OnAddonEnabled()
    if not isInitialized then return end
    self:InitializeAddon()
end

function Core:InitializeAddon()
    local currentLevel = Utils:GetPlayerLevel()
    if not GetLastKnownLevel() then
        SetLastKnownLevel(currentLevel)
    end
    
    local specRequested = Spec:Initialize()
    
    if not specRequested then
        if not Layout:Has(currentLevel) then
            C_Timer.After(Settings.RESTORE_DELAY, function()
                Capture:Perform()
            end)
        end
        Utils:Print(string.format("v%s loaded", Settings.VERSION))
    end
end

local function OnPlayerLevelUp(newLevel)
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    
    C_Timer.After(Settings.RESTORE_DELAY, function()
        HandleLevelUp(newLevel)
    end)
end

local function OnUnitLevel(unit)
    if unit ~= "player" then return end
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    
    local newLevel = Utils:GetPlayerLevel()
    HandleLevelChange(newLevel)
end

local function OnActionBarSlotChanged(slot)
    if not isInitialized then return end
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    if Restore:IsInProgress() then return end
    if Spec:IsSwitchPending() then return end
    
    Capture:Schedule()
end

local function OnSpellsChanged()
    if not isInitialized then return end
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    
    Spec:CheckTimeout()
end

local function OnBonusBarUpdate()
    if not isInitialized then return end
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    if Restore:IsInProgress() then return end
    if Spec:IsSwitchPending() then return end
    
    DebugPrint("UPDATE_BONUS_ACTIONBAR, stance:", EBB.ActionBar:GetStanceIndex())
    Capture:Schedule()
end

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "EbonholdBarBuilderFrame")

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("UNIT_LEVEL")
frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnPlayerEnteringWorld()
    elseif event == "PLAYER_LEVEL_UP" then
        OnPlayerLevelUp(...)
    elseif event == "UNIT_LEVEL" then
        OnUnitLevel(...)
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        OnActionBarSlotChanged(...)
    elseif event == "SPELLS_CHANGED" then
        OnSpellsChanged()
    elseif event == "UPDATE_BONUS_ACTIONBAR" then
        OnBonusBarUpdate()
    end
end)

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

SLASH_EBB1 = "/ebb"
SlashCmdList["EBB"] = function(msg)
    msg = msg and strtrim(msg):lower() or ""

    if msg == "enable" then
        FirstRun:ResetChoice()
        FirstRun:SetSessionDisabled(false)
        FirstRun:Show()
        return
    end
    
    if msg == "debug" then
        Core:SetDebugMode(not debugMode)
        return
    end
    
    if msg == "debugstatus" then
        Utils:Print("=== Debug Status ===")
        Utils:Print("isInitialized: " .. tostring(isInitialized))
        Utils:Print("addonEnabled: " .. tostring(FirstRun:GetEnabledState()))
        Utils:Print("canAddonRun: " .. tostring(FirstRun:CanAddonRun()))
        Utils:Print("stanceIndex: " .. tostring(EBB.ActionBar:GetStanceIndex()))
        return
    end
    
    if not FirstRun:CanAddonRun() then
        Utils:Print("Addon is disabled. Use '/ebb enable' to enable.")
        return
    end
    
    if msg == "save" then
        if not Spec:IsConfirmed() then
            Utils:PrintError("Waiting for spec confirmation...")
            return
        end
        Capture:Perform()
        
    elseif msg == "restore" then
        if not Spec:IsConfirmed() then
            Utils:PrintError("Waiting for spec confirmation...")
            return
        end
        Restore:Perform()
        
    elseif msg == "status" then
        local specIndex = Profile:GetActive()
        local specName = Profile:GetSpecName(specIndex)
        local level = Utils:GetPlayerLevel()
        local layout, source = Layout:Get(level)
        
        Utils:Print(string.format("Spec: %s (#%d)", specName, specIndex))
        Utils:Print(string.format("Enabled slots: %d/%d", 
            Profile:GetEnabledSlotCount(), Settings.TOTAL_SLOTS))
        
        if layout then
            Utils:Print(string.format("Level %d: %d slots saved (%s)", 
                level, layout.configuredSlots or 0, source))
        else
            Utils:Print(string.format("Level %d: No layout saved", level))
        end
        
        Utils:Print(string.format("Total layouts: %d", Layout:GetCount()))
        
    elseif msg == "list" then
        local specIndex = Profile:GetActive()
        local specName = Profile:GetSpecName(specIndex)
        Utils:Print(string.format("Layouts in '%s':", specName))
        local levels = Layout:GetSavedLevels()
        
        if #levels == 0 then
            Utils:Print("  (none)")
        else
            for _, level in ipairs(levels) do
                local layout = Layout:Get(level)
                Utils:Print(string.format("  Level %d: %d slots", level, layout.configuredSlots or 0))
            end
        end
        
    elseif msg == "specs" then
        Utils:Print("Specs:")
        local active = Profile:GetActive()
        
        for specIndex = 1, 5 do
            local marker = (specIndex == active) and " (active)" or ""
            local specName = Profile:GetSpecName(specIndex)
            local layoutCount = Layout:GetCount(specIndex)
            Utils:Print(string.format("  %d. %s: %d layouts%s", specIndex, specName, layoutCount, marker))
        end
        
    elseif msg == "clear" then
        Layout:ClearAll()
        Utils:PrintSuccess("All layouts cleared for current spec")
        
    elseif msg == "ui" or msg == "config" then
        if EBB.Explorer then
            EBB.Explorer:Toggle()
        else
            Utils:PrintError("Explorer UI not loaded")
        end
        
    else
        Utils:Print("Commands:")
        Utils:Print("  /ebb ui - Open configuration panel")
        Utils:Print("  /ebb status - Show current status")
        Utils:Print("  /ebb save - Save current level")
        Utils:Print("  /ebb restore - Restore current level")
        Utils:Print("  /ebb clear - Clear all layouts in current spec")
    end
end
