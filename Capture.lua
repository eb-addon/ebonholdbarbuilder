--[[----------------------------------------------------------------------------
    Capture coordination and debounce logic.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Capture = {}

local Capture = EBB.Capture
local Utils = EBB.Utils
local Settings = EBB.Settings
local ActionBar = EBB.ActionBar
local Profile = EBB.Profile
local Layout = EBB.Layout

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local pendingCapture = false
local lastDebounceTime = 0

--------------------------------------------------------------------------------
-- Capture All Slots
--------------------------------------------------------------------------------

local function CaptureAllSlots()
    local snapshot = {
        timestamp = Utils:GetTimestamp(),
        playerLevel = Utils:GetPlayerLevel(),
        slots = {},
    }
    
    local configuredCount = 0
    local capturedCount = 0
    
    for slot = 1, Settings.TOTAL_SLOTS do
        if Profile:IsSlotEnabled(slot) then
            local slotInfo = ActionBar:GetSlotInfo(slot)
            if slotInfo then
                snapshot.slots[slot] = slotInfo
                capturedCount = capturedCount + 1
                if slotInfo.type ~= "empty" then
                    configuredCount = configuredCount + 1
                end
            end
        end
    end
    
    snapshot.configuredSlots = configuredCount
    snapshot.capturedSlots = capturedCount
    
    return snapshot
end

--------------------------------------------------------------------------------
-- Macro Duplicate Warning
--------------------------------------------------------------------------------

local function WarnMacroDuplicates(snapshot)
    local duplicates = ActionBar:GetMacroDuplicates()
    if not next(duplicates) then return end
    
    local warned = {}
    for slot = 1, Settings.TOTAL_SLOTS do
        local slotInfo = snapshot.slots[slot]
        if slotInfo and slotInfo.type == "macro" and slotInfo.name then
            if duplicates[slotInfo.name] and not warned[slotInfo.name] then
                warned[slotInfo.name] = true
                Utils:Print(string.format(
                    "Warning: %d macros named '%s' — restore may pick the wrong one",
                    duplicates[slotInfo.name], slotInfo.name))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Get Snapshot (without saving)
--------------------------------------------------------------------------------

function Capture:GetSnapshot()
    if ActionBar:IsFullyBlocked() then
        return nil
    end
    
    return CaptureAllSlots()
end

--------------------------------------------------------------------------------
-- Capture Execution
--------------------------------------------------------------------------------

local CONTEXT_MESSAGES = {
    ["vehicle"] = "in vehicle",
    ["possess"] = "mind controlling",
}

local function GetFriendlyContext(context)
    if CONTEXT_MESSAGES[context] then
        return CONTEXT_MESSAGES[context]
    end
    if context and context:find("^bonus:") then
        return "in stance or form"
    end
    return context
end

function Capture:Perform(manual)
    if ActionBar:IsFullyBlocked() then
        local context = ActionBar:GetCaptureContext()
        local friendly = GetFriendlyContext(context)
        if manual then
            Utils:Print("Skipped save: " .. friendly)
        else
            Utils:PrintVerbose("Skipped save: " .. friendly)
        end
        return false
    end
    
    local level = Utils:GetPlayerLevel()
    local snapshot = CaptureAllSlots()
    
    if not snapshot then
        if manual then
            Utils:PrintError("Failed to capture action bars")
        else
            Utils:PrintVerboseError("Failed to capture action bars")
        end
        return false
    end
    
    local success = Layout:Save(level, snapshot)
    
    if EBB.SpellCache then
        EBB.SpellCache:ScanSpellbook()
    end
    
    if success then
        if manual then
            Utils:Print(string.format("Level %d: %d slots saved", level, snapshot.configuredSlots or 0))
            WarnMacroDuplicates(snapshot)
        else
            Utils:PrintVerbose(string.format("Level %d: %d slots saved", level, snapshot.configuredSlots or 0))
        end
    else
        if manual then
            Utils:PrintError("Failed to save layout")
        else
            Utils:PrintVerboseError("Failed to save layout")
        end
    end
    
    return success
end

--------------------------------------------------------------------------------
-- Debounced Capture Scheduling
--------------------------------------------------------------------------------

function Capture:Schedule()
    if ActionBar:IsFullyBlocked() then
        return
    end
    
    local now = GetTime()
    lastDebounceTime = now
    pendingCapture = true
    
    C_Timer.After(Settings.DEBOUNCE_TIME, function()
        if pendingCapture and lastDebounceTime == now then
            pendingCapture = false
            self:Perform()
        end
    end)
end

--------------------------------------------------------------------------------
-- State Management
--------------------------------------------------------------------------------

function Capture:Cancel()
    pendingCapture = false
end

function Capture:IsPending()
    return pendingCapture
end
