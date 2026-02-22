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

    FRAME_WIDTH = 730,
    FRAME_HEIGHT = 490,
    FRAME_PADDING = 12,
    
    TITLE_HEIGHT = 24,
    TITLE_PADDING = 4,
    
    RIGHT_PANEL_WIDTH = 160,
    RIGHT_PANEL_MARGIN = 8,
    
    DROPDOWN_HEIGHT = 30,
    DROPDOWN_LABEL_GAP = 2,  
    
    SWITCH_BUTTON_HEIGHT = 22,
    SWITCH_BUTTON_TOP_MARGIN = 0, 
    SWITCH_BUTTON_BOTTOM_MARGIN = 6,
    
    MODE_BUTTON_HEIGHT = 20,
    MODE_SECTION_GAP = 8,
    
    LEVEL_LIST_TOP_MARGIN = 15,
    LEVEL_BUTTON_HEIGHT = 20,
    
    GRID_OFFSET_X = 12,
    GRID_OFFSET_Y = -8,
    SLOT_SIZE = 32,
    SLOT_SPACING = 5,
    BAR_ROW_HEIGHT = 36,
    BAR_LABEL_WIDTH = 70,
    BAR_LABEL_GAP = 6,          
    TOGGLE_GAP = 10,                
    TOGGLE_SIZE = 24,
    
    BACKDROP_ALPHA = 1,
    INNER_BACKDROP_ALPHA = 0.5,
    DISABLED_OVERLAY_ALPHA = 0.6,
    
    TOOLBAR_HEIGHT = 52,
    TOOLBAR_TOP_MARGIN = 4,
    SUMMARY_HEIGHT = 95,
    SUMMARY_MARGIN = 5,
}

--------------------------------------------------------------------------------
-- Derived Values
--------------------------------------------------------------------------------

local function GetGridWidth()
    local slotsWidth = (LAYOUT.SLOT_SIZE + LAYOUT.SLOT_SPACING) * Settings.SLOTS_PER_BAR - LAYOUT.SLOT_SPACING
    return LAYOUT.BAR_LABEL_WIDTH + LAYOUT.BAR_LABEL_GAP + slotsWidth
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
    
    self:CreateTitleBar(frame)
    self:CreateCloseButton(frame)
    self:CreateRightPanel(frame)
    self:CreateBarGrid(frame)
    self:CreateEditControls(frame)
    self:CreateToolbarPanel(frame)
    self:CreateChangeSummary(frame)
    
    return frame
end

--------------------------------------------------------------------------------
-- Title Bar
--------------------------------------------------------------------------------

function UI:CreateTitleBar(parent)
    local titleBar = CreateFrame("Frame", nil, parent)
    titleBar:SetPoint("TOPLEFT", 12, -12)
    titleBar:SetPoint("TOPRIGHT", -12, -12)
    titleBar:SetHeight(LAYOUT.TITLE_HEIGHT)
    
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 4, 0)
    title:SetText("Ebonhold Bar Builder")
    title:SetTextColor(1, 0.82, 0)
    parent.TitleText = title
    
    local modeBadge = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeBadge:SetPoint("RIGHT", -30, 0)
    modeBadge:SetTextColor(0.7, 0.7, 0.7)
    parent.ModeBadge = modeBadge
    
    local sep = titleBar:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)
    sep:SetTexture(1, 0.82, 0, 0.3)
    
    parent.TitleBar = titleBar
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
    local topOffset = LAYOUT.FRAME_PADDING + LAYOUT.TITLE_HEIGHT + LAYOUT.TITLE_PADDING
    
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(LAYOUT.RIGHT_PANEL_WIDTH)
    panel:SetPoint("TOPRIGHT", -LAYOUT.FRAME_PADDING, -topOffset)
    panel:SetPoint("BOTTOMRIGHT", -LAYOUT.FRAME_PADDING, LAYOUT.FRAME_PADDING)
    
    local yOffset = 0
    
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
    
    local modeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeLabel:SetPoint("TOPLEFT", 0, -yOffset)
    modeLabel:SetText("Recording Mode")
    modeLabel:SetTextColor(0.8, 0.8, 0.8)
    
    yOffset = yOffset + modeLabel:GetStringHeight() + 3
    
    local modeBtnWidth = math.floor((LAYOUT.RIGHT_PANEL_WIDTH - 2) / 2)
    
    local perLevelBtn = CreateFrame("Button", "EBBModePerLevel", panel, "UIPanelButtonTemplate")
    perLevelBtn:SetPoint("TOPLEFT", 0, -yOffset)
    perLevelBtn:SetWidth(modeBtnWidth)
    perLevelBtn:SetHeight(LAYOUT.MODE_BUTTON_HEIGHT)
    perLevelBtn:SetText("Per-Level")
    perLevelBtn:SetNormalFontObject("GameFontNormalSmall")
    perLevelBtn:SetHighlightFontObject("GameFontHighlightSmall")
    
    local breakpointBtn = CreateFrame("Button", "EBBModeBreakpoint", panel, "UIPanelButtonTemplate")
    breakpointBtn:SetPoint("TOPLEFT", perLevelBtn, "TOPRIGHT", 2, 0)
    breakpointBtn:SetWidth(modeBtnWidth)
    breakpointBtn:SetHeight(LAYOUT.MODE_BUTTON_HEIGHT)
    breakpointBtn:SetText("Breakpoints")
    breakpointBtn:SetNormalFontObject("GameFontNormalSmall")
    breakpointBtn:SetHighlightFontObject("GameFontHighlightSmall")
    
    yOffset = yOffset + LAYOUT.MODE_BUTTON_HEIGHT + LAYOUT.MODE_SECTION_GAP
    
    local levelsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelsLabel:SetPoint("TOPLEFT", 0, -yOffset)
    levelsLabel:SetText("Saved Levels")
    parent.LevelsLabel = levelsLabel
    
    yOffset = yOffset + levelsLabel:GetStringHeight() + LAYOUT.DROPDOWN_LABEL_GAP
    
    local listContainer = CreateFrame("Frame", nil, panel)
    listContainer:SetPoint("TOPLEFT", 0, -yOffset)
    listContainer:SetPoint("RIGHT", 0, 0)
    listContainer:SetPoint("BOTTOM", 0, LAYOUT.SUMMARY_HEIGHT + LAYOUT.SUMMARY_MARGIN + 24)
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
    parent.ModePerLevelBtn = perLevelBtn
    parent.ModeBreakpointBtn = breakpointBtn
    parent.LevelScrollFrame = scrollFrame
    parent.LevelScrollChild = scrollChild
    parent.LevelButtons = {}
    
    local bpBtnWidth = math.floor((LAYOUT.RIGHT_PANEL_WIDTH - 2) / 2)

    local storeBPBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    storeBPBtn:SetWidth(bpBtnWidth)
    storeBPBtn:SetHeight(20)
    storeBPBtn:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 0, -2)
    storeBPBtn:SetText("Store BP")
    storeBPBtn:SetNormalFontObject("GameFontNormalSmall")
    storeBPBtn:Disable()
    storeBPBtn:Hide()
    parent.StoreBPBtn = storeBPBtn

    local createBPBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    createBPBtn:SetWidth(bpBtnWidth)
    createBPBtn:SetHeight(20)
    createBPBtn:SetPoint("TOPLEFT", storeBPBtn, "TOPRIGHT", 2, 0)
    createBPBtn:SetText("Create BP")
    createBPBtn:SetNormalFontObject("GameFontNormalSmall")
    createBPBtn:Hide()
    parent.CreateBPBtn = createBPBtn

    parent.KeyframeToggleBtn = nil
    
    local summaryPanel = CreateFrame("Frame", nil, panel)
    summaryPanel:SetPoint("BOTTOMLEFT", 0, 0)
    summaryPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    summaryPanel:SetHeight(LAYOUT.SUMMARY_HEIGHT)
    summaryPanel:SetBackdrop(BACKDROP_INNER)
    summaryPanel:SetBackdropColor(0, 0, 0, LAYOUT.INNER_BACKDROP_ALPHA)
    
    local summaryTitle = summaryPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryTitle:SetPoint("TOPLEFT", 6, -4)
    summaryTitle:SetText("Changes")
    summaryTitle:SetTextColor(1, 0.82, 0)
    summaryPanel.Title = summaryTitle
    
    local summaryScroll = CreateFrame("ScrollFrame", "EBBChangeSummaryScroll", summaryPanel, "UIPanelScrollFrameTemplate")
    summaryScroll:SetPoint("TOPLEFT", 4, -(4 + 12))
    summaryScroll:SetPoint("BOTTOMRIGHT", -25, 4)
    
    local summaryScrollChild = CreateFrame("Frame", nil, summaryScroll)
    summaryScrollChild:SetWidth(LAYOUT.RIGHT_PANEL_WIDTH - 35)
    summaryScrollChild:SetHeight(1)
    summaryScroll:SetScrollChild(summaryScrollChild)
    
    summaryPanel.ScrollFrame = summaryScroll
    summaryPanel.ScrollChild = summaryScrollChild
    
    summaryPanel.Lines = {}
    
    parent.ChangeSummaryPanel = summaryPanel
end

--------------------------------------------------------------------------------
-- Bar Grid (10 rows x 12 slots)
--------------------------------------------------------------------------------

function UI:CreateBarGrid(parent)
    local gridWidth = GetGridWidth()
    local topOffset = LAYOUT.FRAME_PADDING + LAYOUT.TITLE_HEIGHT + LAYOUT.TITLE_PADDING
    
    local gridContainer = CreateFrame("Frame", nil, parent)
    gridContainer:SetPoint("TOPLEFT", LAYOUT.FRAME_PADDING + (LAYOUT.GRID_OFFSET_X or 0), -topOffset + (LAYOUT.GRID_OFFSET_Y or 0))
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
    toggle:Hide()
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
    
    local typeDot = button:CreateTexture(nil, "OVERLAY")
    typeDot:SetPoint("BOTTOMRIGHT", -1, 1)
    typeDot:SetWidth(6)
    typeDot:SetHeight(6)
    typeDot:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    typeDot:Hide()
    button.TypeDot = typeDot
    
    local posLabel = button:CreateFontString(nil, "OVERLAY")
    posLabel:SetFont("Fonts\\ARIALN.TTF", 7, "OUTLINE")
    posLabel:SetPoint("TOPLEFT", 1, -1)
    posLabel:SetTextColor(0.6, 0.6, 0.6, 0.6)
    posLabel:Hide()
    button.PosLabel = posLabel
    
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
-- Toolbar Panel (below grid, above edit controls)
--------------------------------------------------------------------------------

function UI:CreateToolbarPanel(parent)
    local gridBottom = LAYOUT.FRAME_PADDING + 9

    local toolbar = CreateFrame("Frame", nil, parent)
    toolbar:SetPoint("BOTTOMLEFT", LAYOUT.FRAME_PADDING + (LAYOUT.GRID_OFFSET_X or 0), gridBottom)
    toolbar:SetPoint("RIGHT", parent.RightPanel, "LEFT", -LAYOUT.RIGHT_PANEL_MARGIN, 0)
    toolbar:SetHeight(LAYOUT.TOOLBAR_HEIGHT)

    local btn1Defs = {
        { key = "CopyBtn",      text = "Copy",     w = 48 },
        { key = "PasteBtn",     text = "Paste",    w = 48 },
        { key = "PushUpBtn",    text = "Push Up",  w = 52 },
        { key = "PushDownBtn",  text = "Push Down", w = 66 },
        { key = "UndoBtn",      text = "Undo",     w = 48 },
    }

    local xOff = 4
    for _, def in ipairs(btn1Defs) do
        local btn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
        btn:SetWidth(def.w)
        btn:SetHeight(20)
        btn:SetPoint("TOPLEFT", xOff, -2)
        btn:SetText(def.text)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:Disable()
        toolbar[def.key] = btn
        xOff = xOff + def.w + 4
    end

    local overwriteCB = CreateFrame("CheckButton", "EBBPushOverwriteCB", toolbar, "UICheckButtonTemplate")
    overwriteCB:SetWidth(20)
    overwriteCB:SetHeight(20)
    overwriteCB:SetPoint("TOPLEFT", xOff + 4, 0)
    overwriteCB:SetChecked(false)

    local overwriteLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overwriteLabel:SetPoint("LEFT", overwriteCB, "RIGHT", 0, 0)
    overwriteLabel:SetText("Overwrite")
    overwriteLabel:SetTextColor(0.8, 0.8, 0.8)

    overwriteCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Overwrite mode", 1, 1, 1)
        GameTooltip:AddLine("When checked, Push will also clear slots", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("that are empty on the source level.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    overwriteCB:SetScript("OnLeave", function() GameTooltip:Hide() end)

    toolbar.OverwriteCheckbox = overwriteCB

    local btn2Defs = {
        { key = "SaveTmplBtn",     text = "Save Level",    w = 72 },
        { key = "LoadTmplBtn",     text = "Load Level",    w = 72 },
        { key = "ImportExportBtn", text = "Import/Export",  w = 86 },
        { key = "BackupBtn",       text = "Backup",        w = 52 },
        { key = "RestoreBtn",      text = "Restore",       w = 52 },
    }

    xOff = 4
    for _, def in ipairs(btn2Defs) do
        local btn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
        btn:SetWidth(def.w)
        btn:SetHeight(20)
        btn:SetPoint("BOTTOMLEFT", xOff, 4)
        btn:SetText(def.text)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:Disable()
        toolbar[def.key] = btn
        xOff = xOff + def.w + 4
    end

    parent.Toolbar = toolbar
end

--------------------------------------------------------------------------------
-- Change Summary (part of right panel, created in CreateRightPanel)
--------------------------------------------------------------------------------

function UI:CreateChangeSummary(parent)
end

--------------------------------------------------------------------------------
-- Level Button Pool (enhanced for timeline)
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
    
    local indicator = button:CreateTexture(nil, "ARTWORK")
    indicator:SetPoint("LEFT", 2, 0)
    indicator:SetWidth(8)
    indicator:SetHeight(8)
    indicator:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    indicator:SetVertexColor(0.5, 0.5, 0.5, 1)
    button.Indicator = indicator
    
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", indicator, "RIGHT", 3, 0)
    text:SetJustifyH("LEFT")
    button.Text = text
    
    local slotCount = button:CreateFontString(nil, "OVERLAY")
    slotCount:SetFont("Fonts\\ARIALN.TTF", 9, "")
    slotCount:SetPoint("RIGHT", -5, 0)
    slotCount:SetTextColor(0.5, 0.5, 0.5)
    slotCount:Hide()
    button.SlotCount = slotCount
    
    local current = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    current:SetPoint("RIGHT", slotCount, "LEFT", -3, 0)
    current:SetText("YOU")
    current:SetTextColor(0, 1, 0)
    current:Hide()
    button.CurrentIndicator = current
    
    local typeLabel = button:CreateFontString(nil, "OVERLAY")
    typeLabel:SetFont("Fonts\\ARIALN.TTF", 8, "OUTLINE")
    typeLabel:SetPoint("RIGHT", current, "LEFT", -2, 0)
    typeLabel:SetTextColor(1, 0.82, 0)
    typeLabel:Hide()
    button.TypeLabel = typeLabel
    
    mainFrame.LevelButtons[index] = button
    return button
end

--------------------------------------------------------------------------------
-- Create Breakpoint Dialog (level number input)
--------------------------------------------------------------------------------

function UI:CreateBreakpointDialog()
    if UI.CreateBPDialog then
        return UI.CreateBPDialog
    end

    local dialog = CreateFrame("Frame", "EBBCreateBPDialog", UIParent)
    dialog:SetWidth(280)
    dialog:SetHeight(120)
    dialog:SetPoint("CENTER")
    dialog:SetBackdrop(BACKDROP)
    dialog:SetBackdropColor(0, 0, 0, 1)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:SetFrameStrata("DIALOG")
    dialog:Hide()

    tinsert(UISpecialFrames, "EBBCreateBPDialog")

    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Create Breakpoint")
    title:SetTextColor(1, 0.82, 0)

    local levelLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelLabel:SetPoint("TOPLEFT", 20, -40)
    levelLabel:SetText("Level (1-" .. Settings.MAX_LEVEL .. "):")
    levelLabel:SetTextColor(0.8, 0.8, 0.8)

    local editBox = CreateFrame("EditBox", "EBBCreateBPLevelInput", dialog, "InputBoxTemplate")
    editBox:SetWidth(50)
    editBox:SetHeight(20)
    editBox:SetPoint("LEFT", levelLabel, "RIGHT", 8, 0)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(2)
    editBox:SetNumeric(true)
    dialog.LevelInput = editBox

    -- "Current Level" quick-fill button
    local currentBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    currentBtn:SetWidth(90)
    currentBtn:SetHeight(20)
    currentBtn:SetPoint("LEFT", editBox, "RIGHT", 6, 0)
    currentBtn:SetText("Current Lv")
    currentBtn:SetNormalFontObject("GameFontNormalSmall")
    currentBtn:SetScript("OnClick", function()
        local Utils = EBB.Utils
        local lvl = Utils and Utils:GetPlayerLevel() or 1
        editBox:SetText(tostring(lvl))
    end)
    dialog.CurrentLevelBtn = currentBtn

    local statusText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOM", 0, 35)
    statusText:SetTextColor(1, 0.3, 0.3)
    statusText:SetText("")
    dialog.StatusText = statusText

    local okBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    okBtn:SetWidth(70)
    okBtn:SetHeight(22)
    okBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -5, 10)
    okBtn:SetText("Create")
    dialog.OKButton = okBtn

    local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(70)
    cancelBtn:SetHeight(22)
    cancelBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 5, 10)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() dialog:Hide() end)

    editBox:SetScript("OnEnterPressed", function()
        okBtn:Click()
    end)
    editBox:SetScript("OnEscapePressed", function()
        dialog:Hide()
    end)

    UI.CreateBPDialog = dialog
    return dialog
end

--------------------------------------------------------------------------------
-- Get Layout Constants
--------------------------------------------------------------------------------

function UI:GetLayout()
    return LAYOUT
end
