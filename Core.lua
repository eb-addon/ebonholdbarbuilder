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
local Diagnose = EBB.Diagnose
local Keyframe = EBB.Keyframe
local Clipboard = EBB.Clipboard
local Template = EBB.Template
local Timeline = EBB.Timeline
local ImportExport = EBB.ImportExport

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local isInitialized = false
local pendingLevelUp = nil
local levelUpDebounceTime = 0
local HandleLevelUp

local function ExecutePendingLevelUp()
    if not pendingLevelUp then return end
    local newLevel = pendingLevelUp
    pendingLevelUp = nil
    levelUpDebounceTime = 0
    HandleLevelUp(newLevel)
end

local function SchedulePendingLevelUp()
    if not pendingLevelUp then return end
    local now = GetTime()
    levelUpDebounceTime = now
    C_Timer.After(Settings.RESTORE_DELAY, function()
        if pendingLevelUp and levelUpDebounceTime == now then
            ExecutePendingLevelUp()
        end
    end)
end

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
    
    if EBB.SpellCache then
        EBB.SpellCache:Initialize()
    end
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

local function HandleLevelUpPerLevel(newLevel, oldLevel)
    if Layout:Has(newLevel) then
        Capture:Cancel()
        Restore:PerformWhenSafe(newLevel)
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
                Utils:PrintVerbose(string.format("Level %d: Layout saved", newLevel))
            else
                Utils:PrintVerbose(string.format("Levels %d-%d: %d layouts saved", 
                    oldLevel + 1, newLevel, gapsFilled))
            end
        end
    end
end

local function HandleLevelUpBreakpoint(newLevel, oldLevel)
    -- If this level already has an explicit layout, restore it
    if Layout:Has(newLevel) then
        Capture:Cancel()
        Restore:PerformWhenSafe(newLevel)
        return
    end
    
    -- Try to derive from nearest keyframe below
    local nearestKF = Keyframe:GetNearestBelow(newLevel)
    if nearestKF then
        local kfLayout = Layout:Get(nearestKF)
        if kfLayout then
            local derived = Keyframe:DeriveLayout(kfLayout, newLevel)
            if derived then
                Capture:Cancel()
                -- Don't save derived layouts — just restore from them
                Restore:PerformFromLayout(derived, newLevel)
                Utils:PrintVerbose(string.format(
                    "Level %d: Restored from keyframe %d", newLevel, nearestKF))
                return
            end
        end
    end
    
    -- No keyframes exist yet — auto-capture this level as a new keyframe
    local snapshot = Capture:GetSnapshot()
    if snapshot then
        Layout:Save(newLevel, snapshot)
        Keyframe:Set(newLevel)
        Utils:PrintVerbose(string.format(
            "Level %d: Auto-saved as keyframe", newLevel))
    end
end

HandleLevelUp = function(newLevel)
    local oldLevel = GetLastKnownLevel() or (newLevel - 1)
    SetLastKnownLevel(newLevel)
    
    if EBB.SpellCache then
        EBB.SpellCache:ScanSpellbook(newLevel)
    end
    
    if Settings:IsBreakpointMode() then
        HandleLevelUpBreakpoint(newLevel, oldLevel)
    else
        HandleLevelUpPerLevel(newLevel, oldLevel)
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
            Restore:PerformWhenSafe(1)
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
    
    if EBB.SpellCache then
        EBB.SpellCache:ScanSpellbook()
    end
    
    local specRequested = Spec:Initialize()
    
    if not specRequested then
        if not Layout:Has(currentLevel) then
            if Settings:IsBreakpointMode() then
                -- In breakpoint mode, check if we can derive from a keyframe
                local nearestKF = Keyframe:GetNearestBelow(currentLevel)
                if not nearestKF then
                    -- No keyframes at all — capture as first keyframe
                    C_Timer.After(Settings.RESTORE_DELAY, function()
                        local ok = Capture:Perform()
                        if ok then
                            Keyframe:Set(currentLevel)
                        end
                    end)
                end
                -- If nearestKF exists, derived layouts will be used on demand
            else
                C_Timer.After(Settings.RESTORE_DELAY, function()
                    Capture:Perform()
                end)
            end
        end
        Utils:Print(string.format("v%s loaded", Settings.VERSION))
    end
end

local function OnPlayerLevelUp(newLevel)
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    
    DebugPrint("PLAYER_LEVEL_UP:", newLevel, "- waiting for spellbook update")
    pendingLevelUp = newLevel
    
    C_Timer.After(3, function()
        if pendingLevelUp == newLevel then
            DebugPrint("Level-up spellbook timeout, proceeding")
            ExecutePendingLevelUp()
        end
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
    if Restore:IsRecentlyFinished() then return end
    if Restore:HasPendingCombatRestore() then return end
    if Spec:IsSwitchPending() then return end
    if pendingLevelUp then return end
    
    -- In breakpoint mode, only auto-capture if current level is a keyframe
    -- or if no keyframes exist yet (first capture creates one)
    if Settings:IsBreakpointMode() then
        local currentLevel = Utils:GetPlayerLevel()
        local hasAnyKF = Keyframe:GetCount() > 0
        local isKF = Keyframe:IsKeyframe(currentLevel)
        
        if hasAnyKF and not isKF then
            return  -- don't auto-save intermediate levels in breakpoint mode
        end
    end
    
    Capture:Schedule()
end

local function OnSpellsChanged()
    if not isInitialized then return end
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    
    Spec:CheckTimeout()
end

local function OnLearnedSpellInTab()
    if not isInitialized then return end
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    
    Spec:CheckTimeout()

    if pendingLevelUp then
        DebugPrint("LEARNED_SPELL_IN_TAB during pending level-up, scheduling restore")
        SchedulePendingLevelUp()
        return
    end
    
    if not Restore:IsInProgress() and not Restore:IsRecentlyFinished()
       and not Restore:HasPendingCombatRestore() and not Spec:IsSwitchPending() then
        -- In breakpoint mode, only auto-capture at keyframe levels
        if Settings:IsBreakpointMode() then
            local currentLevel = Utils:GetPlayerLevel()
            local hasAnyKF = Keyframe:GetCount() > 0
            local isKF = Keyframe:IsKeyframe(currentLevel)
            if hasAnyKF and not isKF then
                return
            end
        end
        Capture:Schedule()
    end
end

local function OnBonusBarUpdate()
    if not isInitialized then return end
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    if Restore:IsInProgress() then return end
    if Restore:IsRecentlyFinished() then return end
    if Restore:HasPendingCombatRestore() then return end
    if Spec:IsSwitchPending() then return end
    
    DebugPrint("UPDATE_BONUS_ACTIONBAR, stance:", EBB.ActionBar:GetStanceIndex())
    
    -- In breakpoint mode, only auto-capture at keyframe levels
    if Settings:IsBreakpointMode() then
        local currentLevel = Utils:GetPlayerLevel()
        local hasAnyKF = Keyframe:GetCount() > 0
        local isKF = Keyframe:IsKeyframe(currentLevel)
        if hasAnyKF and not isKF then
            return
        end
    end
    
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
frame:RegisterEvent("LEARNED_SPELL_IN_TAB")
frame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
frame:RegisterEvent("TRAINER_SHOW")
frame:RegisterEvent("TRAINER_UPDATE")

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
    elseif event == "LEARNED_SPELL_IN_TAB" then
        OnLearnedSpellInTab()
    elseif event == "UPDATE_BONUS_ACTIONBAR" then
        OnBonusBarUpdate()
    elseif event == "TRAINER_SHOW" then
        if EBB.SpellCache then
            EBB.SpellCache:ScanTrainer()
        end
    elseif event == "TRAINER_UPDATE" then
        if EBB.SpellCache then
            EBB.SpellCache:ScanTrainer()
        end
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
        Restore:PerformWhenSafe()
        
    elseif msg == "status" then
        local specIndex = Profile:GetActive()
        local specName = Profile:GetSpecName(specIndex)
        local level = Utils:GetPlayerLevel()
        local layout, source = Layout:Get(level)
        
        Utils:Print(string.format("Spec: %s (#%d)", specName, specIndex))
        Utils:Print(string.format("Recording: %s", Settings:GetRecordingModeLabel()))
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
        
    elseif msg == "mode" then
        if Settings:IsPerLevelMode() then
            Settings:SetRecordingMode(Settings.RECORD_BREAKPOINT)
        else
            Settings:SetRecordingMode(Settings.RECORD_PER_LEVEL)
        end
        Utils:Print("Recording mode: " .. Settings:GetRecordingModeLabel())
        if EBB.Explorer and EBB.Explorer:IsVisible() then
            EBB.Explorer:Refresh()
        end
        
    elseif msg:find("^mode%s+") then
        local arg = msg:match("^mode%s+(.+)")
        if arg == "perlevel" or arg == "per_level" or arg == "level" then
            Settings:SetRecordingMode(Settings.RECORD_PER_LEVEL)
        elseif arg == "breakpoint" or arg == "breakpoints" or arg == "kf" then
            Settings:SetRecordingMode(Settings.RECORD_BREAKPOINT)
        else
            Utils:Print("Usage: /ebb mode [perlevel|breakpoint]")
            return
        end
        Utils:Print("Recording mode: " .. Settings:GetRecordingModeLabel())
        if EBB.Explorer and EBB.Explorer:IsVisible() then
            EBB.Explorer:Refresh()
        end
        
    elseif msg == "resetcache" then
        if EBB.SpellCache then
            EBB.SpellCache:ClearClassCache()
            EBB.SpellCache:ScanSpellbook()
            Utils:PrintSuccess("Spell cache cleared and rescanned")
        end
        
    elseif msg:find("^diagnose") then
        if not Spec:IsConfirmed() then
            Utils:PrintError("Waiting for spec confirmation...")
            return
        end
        local arg = msg:match("^diagnose%s+(.+)")
        if arg == "all" then
            Diagnose:ScanAll()
        elseif arg and tonumber(arg) then
            Diagnose:ScanBar(tonumber(arg))
        else
            Diagnose:ScanBar(nil)
        end
        
    elseif msg:find("^testslot") then
        if not Spec:IsConfirmed() then
            Utils:PrintError("Waiting for spec confirmation...")
            return
        end
        local slotNum = msg:match("^testslot%s+(%d+)")
        if slotNum then
            Diagnose:TestSlot(tonumber(slotNum))
        else
            Utils:Print("Usage: /ebb testslot <1-" .. Settings.TOTAL_SLOTS .. ">")
        end
        
    elseif msg == "compare" then
        if not Spec:IsConfirmed() then
            Utils:PrintError("Waiting for spec confirmation...")
            return
        end
        Diagnose:Compare()
        
    elseif msg == "ui" or msg == "config" then
        if EBB.Explorer then
            EBB.Explorer:Toggle()
        else
            Utils:PrintError("Explorer UI not loaded")
        end
        
    elseif msg == "minimap" then
        local hidden = Settings:ToggleMinimapButton()
        if hidden then
            if EBB.MinimapButton then
                EBB.MinimapButton:Hide()
            end
            Utils:Print("Minimap button hidden. Use '/ebb minimap' to show it again.")
        else
            if EBB.MinimapButton then
                EBB.MinimapButton:Show()
            end
            Utils:Print("Minimap button shown.")
        end
        
    elseif msg:find("^label%s+") then
        local args = msg:match("^label%s+(.+)")
        local barNum, newLabel = args:match("^(%d+)%s+(.+)")
        barNum = tonumber(barNum)
        if barNum and newLabel and barNum >= 1 and barNum <= Settings.TOTAL_BARS then
            newLabel = strtrim(newLabel)
            Settings:SetBarLabel(barNum, newLabel)
            Utils:Print(string.format("Bar %d renamed to: %s", barNum, newLabel))
            if EBB.Explorer and EBB.Explorer:IsVisible() then
                EBB.Explorer:BuildMapping()
                EBB.Explorer:RefreshBarLabels()
            end
        else
            Utils:Print("Usage: /ebb label <1-" .. Settings.TOTAL_BARS .. "> <name>")
        end
        
    elseif msg == "resetlabels" then
        Settings:ResetBarLabels()
        Utils:PrintSuccess("Bar labels reset to defaults")
        if EBB.Explorer and EBB.Explorer:IsVisible() then
            EBB.Explorer:BuildMapping()
            EBB.Explorer:RefreshBarLabels()
        end
        
    else
        Utils:Print("Commands:")
        Utils:Print("  /ebb ui - Open configuration panel")
        Utils:Print("  /ebb status - Show current status")
        Utils:Print("  /ebb save - Save current level")
        Utils:Print("  /ebb restore - Restore current level")
        Utils:Print("  /ebb mode - Toggle recording mode (per-level / breakpoints)")
        Utils:Print("  /ebb minimap - Toggle minimap button visibility")
        Utils:Print("  /ebb label <bar#> <name> - Rename a bar label")
        Utils:Print("  /ebb resetlabels - Reset all bar labels to defaults")
        Utils:Print("  /ebb clear - Clear all layouts in current spec")
        Utils:Print("  /ebb resetcache - Reset spell level cache and rescan")
        Utils:Print("  /ebb diagnose [bar|all] - Inspect live slot data")
        --Utils:Print("  /ebb testslot <slot> - Dry-run restore for one slot")
        --Utils:Print("  /ebb compare - Saved vs live comparison")
    end
end