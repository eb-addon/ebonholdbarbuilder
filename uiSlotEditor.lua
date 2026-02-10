--[[----------------------------------------------------------------------------
    Visual frame structure for the Slot Editor picker window
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.UI = EBB.UI or {}

local UI = EBB.UI

--------------------------------------------------------------------------------
-- Layout Constants
--------------------------------------------------------------------------------

local LAYOUT = {
    FRAME_WIDTH = 270,
    FRAME_HEIGHT = 380,
    FRAME_PADDING = 10,

    FILTER_HEIGHT = 22,
    FILTER_TOP_MARGIN = 5,

    CATEGORY_HEIGHT = 20,
    ITEM_ROW_HEIGHT = 20,
    ITEM_ICON_SIZE = 16,
    ITEM_INDENT = 12,

    SUB_HEADER_HEIGHT = 18,
    SUB_HEADER_INDENT = 6,
    ITEM_INDENT_GROUPED = 20,

    SECTION_HEADER_HEIGHT = 18,
    SECTION_HEADER_INDENT = 6,
    NESTED_SUB_HEADER_INDENT = 18,
    NESTED_ITEM_INDENT = 30,

    ADD_BUTTON_WIDTH = 80,
    ADD_BUTTON_HEIGHT = 22,
    ADD_BUTTON_MARGIN = -10,

    STATUS_HEIGHT = 14,

    CONFIRM_WIDTH = 280,
    CONFIRM_HEIGHT = 100,

    BACKDROP_ALPHA = 1,
    INNER_BACKDROP_ALPHA = 0.5,
}

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
-- Picker Frame
--------------------------------------------------------------------------------

function UI:CreatePickerFrame()
    if UI.PickerFrame then
        return UI.PickerFrame
    end

    local frame = CreateFrame("Frame", "EBBPickerFrame", UIParent)
    frame:SetWidth(LAYOUT.FRAME_WIDTH)
    frame:SetHeight(LAYOUT.FRAME_HEIGHT)
    frame:SetPoint("CENTER", 200, 0)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, LAYOUT.BACKDROP_ALPHA)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    tinsert(UISpecialFrames, "EBBPickerFrame")

    UI.PickerFrame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -LAYOUT.FRAME_PADDING)
    title:SetText("Select Action")
    frame.Title = title

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    frame.CloseButton = closeButton

    local yOffset = LAYOUT.FRAME_PADDING + 14 + LAYOUT.FILTER_TOP_MARGIN

    local filterBox = CreateFrame("EditBox", "EBBPickerFilter", frame, "InputBoxTemplate")
    filterBox:SetPoint("TOPLEFT", LAYOUT.FRAME_PADDING + 5, -yOffset)
    filterBox:SetPoint("TOPRIGHT", -LAYOUT.FRAME_PADDING - 5, -yOffset)
    filterBox:SetHeight(LAYOUT.FILTER_HEIGHT)
    filterBox:SetAutoFocus(false)
    filterBox:SetMaxLetters(50)
    frame.FilterBox = filterBox

    yOffset = yOffset + LAYOUT.FILTER_HEIGHT + 6

    local bottomReserved = LAYOUT.FRAME_PADDING + LAYOUT.ADD_BUTTON_HEIGHT
                         + LAYOUT.ADD_BUTTON_MARGIN + LAYOUT.STATUS_HEIGHT + 4

    local listContainer = CreateFrame("Frame", nil, frame)
    listContainer:SetPoint("TOPLEFT", LAYOUT.FRAME_PADDING, -yOffset)
    listContainer:SetPoint("BOTTOMRIGHT", -LAYOUT.FRAME_PADDING, bottomReserved)
    listContainer:SetBackdrop(BACKDROP_INNER)
    listContainer:SetBackdropColor(0, 0, 0, LAYOUT.INNER_BACKDROP_ALPHA)
    frame.ListContainer = listContainer

    local scrollFrame = CreateFrame("ScrollFrame", "EBBPickerScrollFrame",
                                     listContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -27, 5)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(LAYOUT.FRAME_WIDTH - LAYOUT.FRAME_PADDING * 2 - 37)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    frame.ScrollFrame = scrollFrame
    frame.ScrollChild = scrollChild
    frame.Rows = {}

    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", LAYOUT.FRAME_PADDING,
                        LAYOUT.FRAME_PADDING + LAYOUT.ADD_BUTTON_HEIGHT + 3)
    statusText:SetPoint("RIGHT", -(LAYOUT.FRAME_PADDING + LAYOUT.ADD_BUTTON_WIDTH + 10), 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetHeight(LAYOUT.STATUS_HEIGHT)
    frame.StatusText = statusText

    local addButton = CreateFrame("Button", "EBBPickerAddButton", frame, "UIPanelButtonTemplate")
    addButton:SetPoint("BOTTOMRIGHT", -LAYOUT.FRAME_PADDING, LAYOUT.FRAME_PADDING)
    addButton:SetWidth(LAYOUT.ADD_BUTTON_WIDTH)
    addButton:SetHeight(LAYOUT.ADD_BUTTON_HEIGHT)
    addButton:SetText("Add")
    addButton:Disable()
    frame.AddButton = addButton

    return frame
end

--------------------------------------------------------------------------------
-- Picker Row Pool
--------------------------------------------------------------------------------

function UI:GetOrCreatePickerRow(parent, index)
    local frame = UI.PickerFrame
    if frame.Rows[index] then
        return frame.Rows[index]
    end

    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(LAYOUT.ITEM_ROW_HEIGHT)
    row:SetPoint("LEFT", 0, 0)
    row:SetPoint("RIGHT", 0, 0)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    highlight:SetBlendMode("ADD")

    local selected = row:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints()
    selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    selected:SetVertexColor(1, 0.82, 0, 0.5)
    selected:Hide()
    row.SelectedTexture = selected

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", 4, 0)
    icon:SetWidth(LAYOUT.ITEM_ICON_SIZE)
    icon:SetHeight(LAYOUT.ITEM_ICON_SIZE)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.Icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    name:SetPoint("RIGHT", -4, 0)
    name:SetJustifyH("LEFT")
    row.Name = name

    local arrow = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("LEFT", 2, 0)
    arrow:SetWidth(10)
    row.Arrow = arrow

    local catLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catLabel:SetPoint("LEFT", arrow, "RIGHT", 2, 0)
    catLabel:SetPoint("RIGHT", -4, 0)
    catLabel:SetJustifyH("LEFT")
    row.CategoryLabel = catLabel

    row.isHeader = false
    frame.Rows[index] = row
    return row
end

--------------------------------------------------------------------------------
-- Row Configuration Helpers
--------------------------------------------------------------------------------

function UI:SetRowAsHeader(row, categoryName, totalCount, filteredCount, isExpanded)
    row.isHeader = true
    row.Arrow:SetText(isExpanded and "-" or "+")
    row.Arrow:SetTextColor(1, 0.82, 0)
    row.Arrow:Show()

    if filteredCount then
        row.CategoryLabel:SetText(string.format("%s (%d/%d)",
            categoryName, filteredCount, totalCount))
    else
        row.CategoryLabel:SetText(string.format("%s (%d)", categoryName, totalCount))
    end

    row.CategoryLabel:SetTextColor(1, 0.82, 0)
    row.CategoryLabel:Show()
    row.Icon:Hide()
    row.Name:Hide()
    row.SelectedTexture:Hide()
end

function UI:SetRowAsSubHeader(row, groupName, count, isExpanded)
    row.isHeader = true
    row.Arrow:SetText(isExpanded and "-" or "+")
    row.Arrow:SetTextColor(0.7, 0.7, 0.7)
    row.Arrow:Show()
    row.CategoryLabel:SetText(string.format("%s (%d)", groupName, count))
    row.CategoryLabel:SetTextColor(0.8, 0.8, 0.8)
    row.CategoryLabel:Show()
    row.Icon:Hide()
    row.Name:Hide()
    row.SelectedTexture:Hide()
end

function UI:SetRowAsSectionHeader(row, label, isExpanded)
    row.isHeader = true
    row.Arrow:SetText(isExpanded and "-" or "+")
    row.Arrow:SetTextColor(0.5, 0.5, 0.5)
    row.Arrow:Show()
    row.CategoryLabel:SetText(label)
    row.CategoryLabel:SetTextColor(0.6, 0.6, 0.6)
    row.CategoryLabel:Show()
    row.Icon:Hide()
    row.Name:Hide()
    row.SelectedTexture:Hide()
end

function UI:SetRowAsItem(row, iconTex, name, availability)
    row.isHeader = false
    row.Arrow:Hide()
    row.CategoryLabel:Hide()
    row.Icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.Icon:Show()
    row.Name:SetText(name or "Unknown")
    row.Name:Show()

    if availability == "unavailable" then
        row.Name:SetTextColor(0.5, 0.5, 0.5)
    elseif availability == "warning" then
        row.Name:SetTextColor(1, 0.8, 0)
    else
        row.Name:SetTextColor(1, 1, 1)
    end
end

--------------------------------------------------------------------------------
-- Confirmation Dialog
--------------------------------------------------------------------------------

function UI:CreateConfirmDialog()
    if UI.ConfirmDialog then
        return UI.ConfirmDialog
    end

    local frame = CreateFrame("Frame", "EBBConfirmDialog", UIParent)
    frame:SetWidth(LAYOUT.CONFIRM_WIDTH)
    frame:SetHeight(LAYOUT.CONFIRM_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:EnableMouse(true)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:Hide()

    tinsert(UISpecialFrames, "EBBConfirmDialog")

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOP", 0, -20)
    text:SetText("You have unsaved slot edits.")
    frame.Text = text

    local saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveBtn:SetWidth(70)
    saveBtn:SetHeight(22)
    saveBtn:SetPoint("BOTTOMLEFT", 20, 15)
    saveBtn:SetText("Save")
    frame.SaveButton = saveBtn

    local discardBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    discardBtn:SetWidth(70)
    discardBtn:SetHeight(22)
    discardBtn:SetPoint("BOTTOM", 0, 15)
    discardBtn:SetText("Discard")
    frame.DiscardButton = discardBtn

    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(70)
    cancelBtn:SetHeight(22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    cancelBtn:SetText("Cancel")
    frame.CancelButton = cancelBtn

    UI.ConfirmDialog = frame
    return frame
end

--------------------------------------------------------------------------------
-- Get Layout Constants
--------------------------------------------------------------------------------

function UI:GetPickerLayout()
    return LAYOUT
end
