--[[----------------------------------------------------------------------------  
    Visual frame structure for the Explorer configuration panel.
    Creates frames and visual elements only - behavior in Explorer.lua
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.UI = EBB.UI or {}

local UI = EBB.UI
local Settings = EBB.Settings

--------------------------------------------------------------------------------
-- Layout Constants
--------------------------------------------------------------------------------

local LAYOUT = {

    FRAME_WIDTH = 720,
    FRAME_HEIGHT = 405,
    FRAME_PADDING = 15,
    
    RIGHT_PANEL_WIDTH = 150,
    RIGHT_PANEL_MARGIN = 10,
    
    DROPDOWN_HEIGHT = 30,
    DROPDOWN_LABEL_GAP = 2,  
    
    SWITCH_BUTTON_HEIGHT = 22,
    SWITCH_BUTTON_TOP_MARGIN = 0, 
    SWITCH_BUTTON_BOTTOM_MARGIN = 10,
    
    LEVEL_LIST_TOP_MARGIN = 15,
    LEVEL_BUTTON_HEIGHT = 20,
    
    GRID_OFFSET_X = 25,
    GRID_OFFSET_Y = -10,
    SLOT_SIZE = 28,
    SLOT_SPACING = 2,
    BAR_ROW_HEIGHT = 32,
    BAR_LABEL_WIDTH = 70,
    BAR_LABEL_GAP = 8,          
    TOGGLE_GAP = 10,                
    TOGGLE_SIZE = 24,
    
    BACKDROP_ALPHA = 1,
    INNER_BACKDROP_ALPHA = 0.5,
    DISABLED_OVERLAY_ALPHA = 0.6,
}

--------------------------------------------------------------------------------
-- Derived Values
--------------------------------------------------------------------------------

local function GetGridWidth()
    local slotsWidth = (LAYOUT.SLOT_SIZE + LAYOUT.SLOT_SPACING) * Settings.SLOTS_PER_BAR - LAYOUT.SLOT_SPACING
    return LAYOUT.BAR_LABEL_WIDTH + LAYOUT.BAR_LABEL_GAP + slotsWidth + LAYOUT.TOGGLE_GAP + LAYOUT.TOGGLE_SIZE
end

local function GetSlotOffset(slotInBar)
    return LAYOUT.BAR_LABEL_WIDTH + LAYOUT.BAR_LABEL_GAP + ((slotInBar - 1) * (LAYOUT.SLOT_SIZE + LAYOUT.SLOT_SPACING))
end

local function GetToggleOffset()
    local slotsWidth = (LAYOUT.SLOT_SIZE + LAYOUT.SLOT_SPACING) * Settings.SLOTS_PER_BAR - LAYOUT.SLOT_SPACING
    return LAYOUT.BAR_LABEL_WIDTH + LAYOUT.BAR_LABEL_GAP + slotsWidth + LAYOUT.TOGGLE_GAP
end

--------------------------------------------------------------------------------
-- Textures
--------------------------------------------------------------------------------

local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
}

local BACKDROP_INNER = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
}

--------------------------------------------------------------------------------
-- Main Frame Creation
--------------------------------------------------------------------------------

function UI:CreateExplorerFrame()
    if UI.ExplorerFrame then
        return UI.ExplorerFrame
    end
    
    local frame = CreateFrame("Frame", "EBBExplorerFrame", UIParent)
    frame:SetWidth(LAYOUT.FRAME_WIDTH)
    frame:SetHeight(LAYOUT.FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, LAYOUT.BACKDROP_ALPHA)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    tinsert(UISpecialFrames, "EBBExplorerFrame")
    
    UI.ExplorerFrame = frame
    
    self:CreateCloseButton(frame)
    self:CreateRightPanel(frame)
    self:CreateBarGrid(frame)
    self:CreateEditControls(frame)
    
    return frame
end

--------------------------------------------------------------------------------
-- Close Button
--------------------------------------------------------------------------------

function UI:CreateCloseButton(parent)
    local closeButton = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    parent.CloseButton = closeButton
end

--------------------------------------------------------------------------------
-- Right Panel (Spec Dropdown + Level List)
--------------------------------------------------------------------------------

function UI:CreateRightPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(LAYOUT.RIGHT_PANEL_WIDTH)
    panel:SetPoint("TOPRIGHT", -LAYOUT.FRAME_PADDING, -LAYOUT.FRAME_PADDING)
    panel:SetPoint("BOTTOMRIGHT", -LAYOUT.FRAME_PADDING, LAYOUT.FRAME_PADDING)
    
    local yOffset = 10
    
    local specLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specLabel:SetPoint("TOPLEFT", 0, -yOffset)
    specLabel:SetText("Specialization")
    
    yOffset = yOffset + specLabel:GetStringHeight() + LAYOUT.DROPDOWN_LABEL_GAP
    
    local dropdown = CreateFrame("Frame", "EBBSpecDropdown", panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", -15, -yOffset)
    UIDropDownMenu_SetWidth(dropdown, LAYOUT.RIGHT_PANEL_WIDTH - 20)
    
    yOffset = yOffset + LAYOUT.DROPDOWN_HEIGHT + LAYOUT.SWITCH_BUTTON_TOP_MARGIN
    
    local switchButton = CreateFrame("Button", "EBBSwitchSpecButton", panel, "UIPanelButtonTemplate")
    switchButton:SetPoint("TOPLEFT", 0, -yOffset)
    switchButton:SetWidth(LAYOUT.RIGHT_PANEL_WIDTH)
    switchButton:SetHeight(LAYOUT.SWITCH_BUTTON_HEIGHT)
    switchButton:SetText("Switch Spec")
    
    yOffset = yOffset + LAYOUT.SWITCH_BUTTON_HEIGHT + LAYOUT.SWITCH_BUTTON_BOTTOM_MARGIN
    
    local levelsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelsLabel:SetPoint("TOPLEFT", 0, -yOffset)
    levelsLabel:SetText("Saved Levels")
    
    yOffset = yOffset + levelsLabel:GetStringHeight() + LAYOUT.DROPDOWN_LABEL_GAP
    
    local listContainer = CreateFrame("Frame", nil, panel)
    listContainer:SetPoint("TOPLEFT", 0, -yOffset)
    listContainer:SetPoint("BOTTOMRIGHT", 0, 0)
    listContainer:SetBackdrop(BACKDROP_INNER)
    listContainer:SetBackdropColor(0, 0, 0, LAYOUT.INNER_BACKDROP_ALPHA)
    
    local scrollFrame = CreateFrame("ScrollFrame", "EBBLevelScrollFrame", listContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -27, 5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(LAYOUT.RIGHT_PANEL_WIDTH - 35)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    
    parent.RightPanel = panel
    parent.SpecDropdown = dropdown
    parent.SwitchSpecButton = switchButton
    parent.LevelScrollFrame = scrollFrame
    parent.LevelScrollChild = scrollChild
    parent.LevelButtons = {}
end

--------------------------------------------------------------------------------
-- Bar Grid (10 rows x 12 slots)
--------------------------------------------------------------------------------

function UI:CreateBarGrid(parent)
    local gridWidth = GetGridWidth()
    
    local gridContainer = CreateFrame("Frame", nil, parent)
    gridContainer:SetPoint("TOPLEFT", LAYOUT.FRAME_PADDING + (LAYOUT.GRID_OFFSET_X or 0), -LAYOUT.FRAME_PADDING + (LAYOUT.GRID_OFFSET_Y or 0))
    gridContainer:SetPoint("BOTTOMLEFT", LAYOUT.FRAME_PADDING + (LAYOUT.GRID_OFFSET_X or 0), LAYOUT.FRAME_PADDING + (LAYOUT.GRID_OFFSET_Y or 0))
    gridContainer:SetWidth(gridWidth)
    
    parent.BarRows = {}
    parent.SlotButtons = {}
    parent.BarToggles = {}
    parent.BarLabels = {}
    
    for barIndex = 1, Settings.TOTAL_BARS do
        local row = self:CreateBarRow(gridContainer, barIndex)
        row:SetPoint("TOPLEFT", 0, -((barIndex - 1) * LAYOUT.BAR_ROW_HEIGHT))
        parent.BarRows[barIndex] = row
    end
    
    parent.GridContainer = gridContainer
end

function UI:CreateBarRow(parent, barIndex)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(LAYOUT.BAR_ROW_HEIGHT)
    row:SetPoint("LEFT", 0, 0)
    row:SetPoint("RIGHT", 0, 0)
    
    local mainFrame = UI.ExplorerFrame
    
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(LAYOUT.BAR_LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetText("Bar " .. barIndex)
    mainFrame.BarLabels[barIndex] = label
    
    local startSlot = ((barIndex - 1) * Settings.SLOTS_PER_BAR) + 1
    for i = 1, Settings.SLOTS_PER_BAR do
        local slot = startSlot + i - 1
        local button = self:CreateSlotButton(row, slot)
        button:SetPoint("LEFT", GetSlotOffset(i), 0)
        mainFrame.SlotButtons[slot] = button
    end
    
    local toggle = self:CreateBarToggle(row, barIndex)
    toggle:SetPoint("LEFT", GetToggleOffset(), 0)
    mainFrame.BarToggles[barIndex] = toggle
    
    return row
end

function UI:CreateSlotButton(parent, slot)
    local button = CreateFrame("Button", "EBBSlot" .. slot, parent)
    button:SetWidth(LAYOUT.SLOT_SIZE)
    button:SetHeight(LAYOUT.SLOT_SIZE)
    
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    button.Background = bg
    
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.Icon = icon
    
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetAlpha(0)
    button.Border = border
    
    local disabled = button:CreateTexture(nil, "OVERLAY")
    disabled:SetAllPoints()
    disabled:SetTexture(0, 0, 0, LAYOUT.DISABLED_OVERLAY_ALPHA)
    disabled:Hide()
    button.DisabledOverlay = disabled
    
    local editBorder = button:CreateTexture(nil, "OVERLAY")
    editBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    editBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    editBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    editBorder:SetBlendMode("ADD")
    editBorder:SetVertexColor(1, 0.6, 0)
    editBorder:SetAlpha(0.8)
    editBorder:Hide()
    button.EditBorder = editBorder
    
    local activeEditBorder = button:CreateTexture(nil, "OVERLAY")
    activeEditBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    activeEditBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    activeEditBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    activeEditBorder:SetBlendMode("ADD")
    activeEditBorder:SetVertexColor(0.3, 0.7, 1)
    activeEditBorder:SetAlpha(0.9)
    activeEditBorder:Hide()
    button.ActiveEditBorder = activeEditBorder
    
    button.slot = slot
    
    return button
end

function UI:CreateBarToggle(parent, barIndex)
    local toggle = CreateFrame("CheckButton", "EBBBarToggle" .. barIndex, parent, "UICheckButtonTemplate")
    toggle:SetWidth(LAYOUT.TOGGLE_SIZE)
    toggle:SetHeight(LAYOUT.TOGGLE_SIZE)
    
    local mixed = toggle:CreateTexture(nil, "ARTWORK")
    mixed:SetPoint("CENTER")
    mixed:SetWidth(14)
    mixed:SetHeight(14)
    mixed:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
    mixed:Hide()
    toggle.MixedTexture = mixed
    
    toggle.barIndex = barIndex
    toggle.state = "checked"
    
    return toggle
end

--------------------------------------------------------------------------------
-- Edit Controls (below grid)
--------------------------------------------------------------------------------

function UI:CreateEditControls(parent)
    local gridBottom = LAYOUT.FRAME_PADDING + 5

    local editLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    editLabel:SetPoint("BOTTOMLEFT", LAYOUT.FRAME_PADDING + (LAYOUT.GRID_OFFSET_X or 0), gridBottom + 5)
    editLabel:SetText("")
    parent.EditLabel = editLabel

    local revertButton = CreateFrame("Button", "EBBEditRevertButton", parent, "UIPanelButtonTemplate")
    revertButton:SetWidth(60)
    revertButton:SetHeight(22)
    revertButton:SetPoint("LEFT", editLabel, "RIGHT", 10, 0)
    revertButton:SetText("Revert")
    revertButton:Hide()
    parent.EditRevertButton = revertButton

    local saveButton = CreateFrame("Button", "EBBEditSaveButton", parent, "UIPanelButtonTemplate")
    saveButton:SetWidth(60)
    saveButton:SetHeight(22)
    saveButton:SetPoint("LEFT", revertButton, "RIGHT", 5, 0)
    saveButton:SetText("Save")
    saveButton:Hide()
    parent.EditSaveButton = saveButton
end

--------------------------------------------------------------------------------
-- Level Button Pool
--------------------------------------------------------------------------------

function UI:GetOrCreateLevelButton(parent, index)
    local mainFrame = UI.ExplorerFrame
    
    if mainFrame.LevelButtons[index] then
        return mainFrame.LevelButtons[index]
    end
    
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(LAYOUT.LEVEL_BUTTON_HEIGHT)
    button:SetPoint("LEFT", 0, 0)
    button:SetPoint("RIGHT", 0, 0)
    
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    highlight:SetBlendMode("ADD")
    
    local selected = button:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints()
    selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    selected:SetVertexColor(1, 0.82, 0, 0.5)
    selected:Hide()
    button.SelectedTexture = selected
    
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 5, 0)
    text:SetJustifyH("LEFT")
    button.Text = text
    
    local current = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    current:SetPoint("RIGHT", -5, 0)
    current:SetText("current")
    current:SetTextColor(0, 1, 0)
    current:Hide()
    button.CurrentIndicator = current
    
    mainFrame.LevelButtons[index] = button
    return button
end

--------------------------------------------------------------------------------
-- Get Layout Constants
--------------------------------------------------------------------------------

function UI:GetLayout()
    return LAYOUT
end
