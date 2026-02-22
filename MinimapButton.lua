--[[----------------------------------------------------------------------------  
    Minimap button for quick access to the Explorer panel.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.MinimapButton = {}

local MinimapButton = EBB.MinimapButton

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BUTTON_RADIUS = 80          
local BUTTON_SIZE = 31            
local DEFAULT_ANGLE = 220         

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local button = nil
local isDragging = false

--------------------------------------------------------------------------------
-- Position Management
--------------------------------------------------------------------------------

local function GetSavedAngle()
    if EBB_CharDB and EBB_CharDB.minimapAngle then
        return EBB_CharDB.minimapAngle
    end
    return DEFAULT_ANGLE
end

local function SaveAngle(angle)
    if EBB_CharDB then
        EBB_CharDB.minimapAngle = angle
    end
end

local function UpdatePosition(angle)
    if not button then return end
    
    local radian = math.rad(angle)
    local x = math.cos(radian) * BUTTON_RADIUS
    local y = math.sin(radian) * BUTTON_RADIUS
    
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function GetAngleFromCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    
    cx = cx / scale
    cy = cy / scale
    
    local dx = cx - mx
    local dy = cy - my
    
    return math.deg(math.atan2(dy, dx))
end

--------------------------------------------------------------------------------
-- Button Creation
--------------------------------------------------------------------------------

function MinimapButton:Create()
    if button then return button end
    
    button = CreateFrame("Button", "EBBMinimapButton", Minimap)
    button:SetWidth(BUTTON_SIZE)
    button:SetHeight(BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)
    
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetWidth(20)
    background:SetHeight(20)
    background:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    background:SetPoint("CENTER", -1, 1)
    background:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.Icon = background
    
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    
    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" and not isDragging then
            MinimapButton:OnLeftClick()
        elseif btn == "RightButton" then
            MinimapButton:OnRightClick()
        end
    end)
    
    button:SetScript("OnDragStart", function(self)
        isDragging = true
        self:SetScript("OnUpdate", function()
            local angle = GetAngleFromCursor()
            UpdatePosition(angle)
            SaveAngle(angle)
        end)
    end)
    
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        isDragging = false
    end)
    
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Ebonhold Bar Builder", 1, 1, 1)
        if EBB.FirstRun and EBB.FirstRun:CanAddonRun() then
            GameTooltip:AddLine("Left-click to open settings", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Right-click for options", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Left-click to enable EBB", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    UpdatePosition(GetSavedAngle())
    
    -- Respect user's hide setting
    if EBB.Settings and EBB.Settings:IsMinimapButtonHidden() then
        button:Hide()
    end
    
    return button
end

--------------------------------------------------------------------------------
-- Context Menu
--------------------------------------------------------------------------------

local contextMenu = nil

local function InitializeContextMenu(self, level)
    if not level then return end
    
    local Settings = EBB.Settings
    
    -- Recording mode header
    local info = UIDropDownMenu_CreateInfo()
    info.text = "Recording Mode:"
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.text = "    Per-Level"
    info.checked = Settings:IsPerLevelMode()
    info.isNotRadio = false
    info.func = function()
        Settings:SetRecordingMode(Settings.RECORD_PER_LEVEL)
        EBB.Utils:Print("Recording mode: Per-Level")
        if EBB.Explorer and EBB.Explorer:IsVisible() then
            EBB.Explorer:Refresh()
        end
    end
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.text = "    Breakpoints"
    info.checked = Settings:IsBreakpointMode()
    info.isNotRadio = false
    info.func = function()
        Settings:SetRecordingMode(Settings.RECORD_BREAKPOINT)
        EBB.Utils:Print("Recording mode: Breakpoints")
        if EBB.Explorer and EBB.Explorer:IsVisible() then
            EBB.Explorer:Refresh()
        end
    end
    UIDropDownMenu_AddButton(info, level)
    
    -- Separator
    info = UIDropDownMenu_CreateInfo()
    info.disabled = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
    
    -- Disable
    info = UIDropDownMenu_CreateInfo()
    info.text = "Disable EBB"
    info.notCheckable = true
    info.colorCode = "|cFFFF4444"
    info.func = function()
        if EBB.FirstRun then
            EBB.FirstRun:ResetChoice()
            EBB.FirstRun:SetSessionDisabled(true)
            EBB.Utils:Print("Disabled for this session")
        end
    end
    UIDropDownMenu_AddButton(info, level)

    -- Hide minimap button
    info = UIDropDownMenu_CreateInfo()
    info.text = "Hide Minimap Button"
    info.notCheckable = true
    info.func = function()
        if EBB.Settings then
            EBB.Settings:SetMinimapButtonHidden(true)
            MinimapButton:Hide()
            EBB.Utils:Print("Minimap button hidden. Use '/ebb minimap' to show it again.")
        end
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.disabled = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.text = "Diagnose"
    info.notCheckable = true
    info.func = function()
        if not EBB.Spec:IsConfirmed() then
            EBB.Utils:PrintError("Waiting for spec confirmation...")
            return
        end
        EBB.Diagnose:ScanAll()
    end
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.disabled = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.text = "Logs:"
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.text = "    Verbose"
    info.checked = (EBB_CharDB and EBB_CharDB.logVerbose) or false
    info.isNotRadio = true
    info.keepShownOnClick = true
    info.func = function()
        if EBB_CharDB then
            EBB_CharDB.logVerbose = not EBB_CharDB.logVerbose
        end
    end
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.text = "    Errors"
    info.checked = (EBB_CharDB and EBB_CharDB.logErrors) or false
    info.isNotRadio = true
    info.keepShownOnClick = true
    info.func = function()
        if EBB_CharDB then
            EBB_CharDB.logErrors = not EBB_CharDB.logErrors
        end
    end
    UIDropDownMenu_AddButton(info, level)
end

local function CreateContextMenu()
    if contextMenu then return contextMenu end
    
    contextMenu = CreateFrame("Frame", "EBBMinimapContextMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(contextMenu, InitializeContextMenu, "MENU")
    
    return contextMenu
end

--------------------------------------------------------------------------------
-- Click Handlers
--------------------------------------------------------------------------------

function MinimapButton:OnLeftClick()
    if EBB.FirstRun and not EBB.FirstRun:CanAddonRun() then
        EBB.FirstRun:Show()
        return
    end
    
    if EBB.Explorer then
        EBB.Explorer:Toggle()
    end
end

function MinimapButton:OnRightClick()
    if not EBB.FirstRun or not EBB.FirstRun:CanAddonRun() then
        return
    end
    
    local menu = CreateContextMenu()
    ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function MinimapButton:Show()
    if button then
        button:Show()
    end
end

function MinimapButton:Hide()
    if button then
        button:Hide()
    end
end

function MinimapButton:IsVisible()
    return button and button:IsShown()
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        MinimapButton:Create()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)