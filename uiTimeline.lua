--[[----------------------------------------------------------------------------
    Visual frame structure for the Timeline component.
    Enhances the Explorer's level list with keyframe indicators,
    change summary panel, and operation toolbar.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.UI = EBB.UI or {}

local UI = EBB.UI
local Settings = EBB.Settings

--------------------------------------------------------------------------------
-- Timeline Layout Constants
--------------------------------------------------------------------------------

local TL = {
    LEVEL_ROW_HEIGHT = 20,
    INDICATOR_SIZE = 10,
    INDICATOR_MARGIN = 4,

    SUMMARY_HEIGHT = 100,
    SUMMARY_MARGIN = 5,
    SUMMARY_LINE_HEIGHT = 13,

    TOOLBAR_BUTTON_WIDTH = 60,
    TOOLBAR_BUTTON_HEIGHT = 20,
    TOOLBAR_SPACING = 4,
    TOOLBAR_HEIGHT = 24,
    TOOLBAR_MARGIN = 6,

    COLOR_KEYFRAME     = { r = 1.0,  g = 0.82, b = 0.0  },  
    COLOR_SAVED        = { r = 0.8,  g = 0.8,  b = 0.8  },  
    COLOR_DERIVED      = { r = 0.5,  g = 0.7,  b = 1.0  },  
    COLOR_CURRENT      = { r = 0.0,  g = 1.0,  b = 0.0  },  
    COLOR_EMPTY        = { r = 0.3,  g = 0.3,  b = 0.3  },  
}

UI.TimelineLayout = TL

--------------------------------------------------------------------------------
-- Enhanced Level Button
--------------------------------------------------------------------------------

function UI:GetOrCreateTimelineLevelButton(parent, index)
    local mainFrame = UI.ExplorerFrame
    if not mainFrame then return nil end

    if mainFrame.LevelButtons[index] then
        return mainFrame.LevelButtons[index]
    end

    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(TL.LEVEL_ROW_HEIGHT)
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
    indicator:SetPoint("LEFT", 3, 0)
    indicator:SetWidth(TL.INDICATOR_SIZE)
    indicator:SetHeight(TL.INDICATOR_SIZE)
    indicator:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    button.Indicator = indicator

    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", indicator, "RIGHT", TL.INDICATOR_MARGIN, 0)
    text:SetJustifyH("LEFT")
    button.Text = text

    local infoText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("RIGHT", -3, 0)
    infoText:SetJustifyH("RIGHT")
    button.InfoText = infoText

    local pinIcon = button:CreateTexture(nil, "OVERLAY")
    pinIcon:SetPoint("LEFT", text, "RIGHT", 2, 0)
    pinIcon:SetWidth(10)
    pinIcon:SetHeight(10)
    pinIcon:SetTexture("Interface\\Minimap\\Tracking\\None")
    pinIcon:Hide()
    button.PinIcon = pinIcon

    mainFrame.LevelButtons[index] = button
    return button
end

function UI:StyleTimelineButton(button, entryType, isCurrent, isSelected)
    local c

    if entryType == "keyframe" then
        c = TL.COLOR_KEYFRAME
        button.Indicator:SetVertexColor(c.r, c.g, c.b, 1)
        button.Indicator:Show()
        button.Text:SetTextColor(1, 0.9, 0.6)
    elseif entryType == "saved" then
        c = TL.COLOR_SAVED
        button.Indicator:SetVertexColor(c.r, c.g, c.b, 1)
        button.Indicator:Show()
        button.Text:SetTextColor(0.9, 0.9, 0.9)
    elseif entryType == "derived" then
        c = TL.COLOR_DERIVED
        button.Indicator:SetVertexColor(c.r, c.g, c.b, 0.6)
        button.Indicator:Show()
        button.Text:SetTextColor(0.6, 0.75, 0.9)
    else
        button.Indicator:SetVertexColor(0.3, 0.3, 0.3, 0.3)
        button.Indicator:Show()
        button.Text:SetTextColor(0.5, 0.5, 0.5)
    end

    if isCurrent then
        button.InfoText:SetText("current")
        button.InfoText:SetTextColor(0, 1, 0)
        button.InfoText:Show()
    else
        button.InfoText:SetText("")
        button.InfoText:Hide()
    end

    if isSelected then
        button.SelectedTexture:Show()
    else
        button.SelectedTexture:Hide()
    end
end

--------------------------------------------------------------------------------
-- Change Summary Panel
--------------------------------------------------------------------------------

function UI:CreateChangeSummaryPanel(parent)
    if parent.ChangeSummaryPanel then
        return parent.ChangeSummaryPanel
    end

    local BACKDROP_INNER = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    }

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetBackdrop(BACKDROP_INNER)
    panel:SetBackdropColor(0, 0, 0, 0.7)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 6, -5)
    title:SetText("Changes")
    title:SetTextColor(1, 0.82, 0)
    panel.Title = title

    panel.Lines = {}
    for i = 1, 6 do
        local line = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line:SetPoint("TOPLEFT", 6, -(5 + i * TL.SUMMARY_LINE_HEIGHT))
        line:SetPoint("RIGHT", -6, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        line:Hide()
        panel.Lines[i] = line
    end

    local overflow = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overflow:SetPoint("BOTTOMLEFT", 6, 4)
    overflow:SetTextColor(0.5, 0.5, 0.5)
    overflow:Hide()
    panel.OverflowText = overflow

    parent.ChangeSummaryPanel = panel
    return panel
end

function UI:PopulateChangeSummary(panel, summaryLines)
    if not panel then return end

    for _, line in ipairs(panel.Lines) do
        line:Hide()
    end
    panel.OverflowText:Hide()

    if not summaryLines or #summaryLines == 0 then
        panel.Title:SetText("No changes")
        panel.Title:SetTextColor(0.5, 0.5, 0.5)
        return
    end

    panel.Title:SetText(string.format("Changes (%d)", #summaryLines))
    panel.Title:SetTextColor(1, 0.82, 0)

    local maxLines = #panel.Lines
    local showCount = math.min(#summaryLines, maxLines)

    for i = 1, showCount do
        local lineData = summaryLines[i]
        panel.Lines[i]:SetText(lineData.text)
        panel.Lines[i]:SetTextColor(
            lineData.color[1], lineData.color[2], lineData.color[3])
        panel.Lines[i]:Show()
    end

    if #summaryLines > maxLines then
        panel.OverflowText:SetText(
            string.format("... and %d more", #summaryLines - maxLines))
        panel.OverflowText:Show()
    end
end

--------------------------------------------------------------------------------
-- Toolbar
--------------------------------------------------------------------------------

function UI:CreateTimelineToolbar(parent)
    if parent.TimelineToolbar then
        return parent.TimelineToolbar
    end

    local toolbar = CreateFrame("Frame", nil, parent)
    toolbar:SetHeight(TL.TOOLBAR_HEIGHT)
    toolbar.Buttons = {}

    local buttonDefs = {
        { name = "CopyBtn",     text = "Copy",     tooltip = "Copy this level's layout" },
        { name = "PasteBtn",    text = "Paste",    tooltip = "Paste clipboard to this level" },
        { name = "PushUpBtn",   text = "Push Up",  tooltip = "Push layout to higher levels" },
        { name = "PushDownBtn", text = "Push Dn",  tooltip = "Push layout to lower levels" },
        { name = "UndoBtn",     text = "Undo",     tooltip = "Undo last operation" },
    }

    local xOffset = 0
    for _, def in ipairs(buttonDefs) do
        local btn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
        btn:SetWidth(TL.TOOLBAR_BUTTON_WIDTH)
        btn:SetHeight(TL.TOOLBAR_BUTTON_HEIGHT)
        btn:SetPoint("LEFT", xOffset, 0)
        btn:SetText(def.text)
        btn:Disable()

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(def.tooltip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        toolbar.Buttons[def.name] = btn
        toolbar[def.name] = btn

        xOffset = xOffset + TL.TOOLBAR_BUTTON_WIDTH + TL.TOOLBAR_SPACING
    end

    parent.TimelineToolbar = toolbar
    return toolbar
end

--------------------------------------------------------------------------------
-- Keyframe Toggle Button (right-click context or dedicated button)
--------------------------------------------------------------------------------

function UI:CreateKeyframeToggle(parent)
    if parent.KeyframeToggleBtn then
        return parent.KeyframeToggleBtn
    end

    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetWidth(20)
    btn:SetHeight(20)
    btn:SetText("K")
    btn:SetNormalFontObject("GameFontNormalSmall")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Toggle Breakpoint", 1, 0.82, 0)
        GameTooltip:AddLine("Mark/unmark this level as a breakpoint", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    parent.KeyframeToggleBtn = btn
    return btn
end

--------------------------------------------------------------------------------
-- Template Dropdown
--------------------------------------------------------------------------------

function UI:CreateTemplateControls(parent)
    if parent.TemplateControls then
        return parent.TemplateControls
    end

    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(22)

    local saveBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    saveBtn:SetWidth(70)
    saveBtn:SetHeight(20)
    saveBtn:SetPoint("LEFT", 0, 0)
    saveBtn:SetText("Save Tmpl")
    container.SaveTemplateBtn = saveBtn

    local loadBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    loadBtn:SetWidth(70)
    loadBtn:SetHeight(20)
    loadBtn:SetPoint("LEFT", saveBtn, "RIGHT", TL.TOOLBAR_SPACING, 0)
    loadBtn:SetText("Load Tmpl")
    container.LoadTemplateBtn = loadBtn

    local ioBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    ioBtn:SetWidth(50)
    ioBtn:SetHeight(20)
    ioBtn:SetPoint("LEFT", loadBtn, "RIGHT", TL.TOOLBAR_SPACING, 0)
    ioBtn:SetText("I/O")
    container.ImportExportBtn = ioBtn

    parent.TemplateControls = container
    return container
end

--------------------------------------------------------------------------------
-- Import/Export Dialog
--------------------------------------------------------------------------------

function UI:CreateImportExportDialog()
    if UI.ImportExportDialog then
        return UI.ImportExportDialog
    end

    local BACKDROP = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    }

    local frame = CreateFrame("Frame", "EBBImportExportDialog", UIParent)
    frame:SetWidth(400)
    frame:SetHeight(250)
    frame:SetPoint("CENTER")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:Hide()

    tinsert(UISpecialFrames, "EBBImportExportDialog")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Import / Export")
    frame.Title = title

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local scrollFrame = CreateFrame("ScrollFrame", "EBBIOScrollFrame",
                                     frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 55)

    local editBox = CreateFrame("EditBox", "EBBIOEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(350)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)

    frame.EditBox = editBox
    frame.ScrollFrame = scrollFrame

    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetWidth(80)
    exportBtn:SetHeight(22)
    exportBtn:SetPoint("BOTTOMLEFT", 15, 15)
    exportBtn:SetText("Export")
    frame.ExportButton = exportBtn

    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetWidth(80)
    importBtn:SetHeight(22)
    importBtn:SetPoint("BOTTOMRIGHT", -15, 15)
    importBtn:SetText("Import")
    frame.ImportButton = importBtn

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("BOTTOM", 0, 42)
    status:SetTextColor(1, 0.8, 0)
    frame.StatusText = status

    UI.ImportExportDialog = frame
    return frame
end

--------------------------------------------------------------------------------
-- Restore (Backup Import) Dialog
--------------------------------------------------------------------------------

function UI:CreateRestoreDialog()
    if UI.RestoreDialog then
        return UI.RestoreDialog
    end

    local BACKDROP = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    }

    local frame = CreateFrame("Frame", "EBBRestoreDialog", UIParent)
    frame:SetWidth(420)
    frame:SetHeight(300)
    frame:SetPoint("CENTER")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:Hide()

    tinsert(UISpecialFrames, "EBBRestoreDialog")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Restore from Backup")
    title:SetTextColor(1, 0.82, 0)
    frame.Title = title

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local pasteLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pasteLabel:SetPoint("TOPLEFT", 15, -38)
    pasteLabel:SetText("Paste backup string below:")
    pasteLabel:SetTextColor(0.8, 0.8, 0.8)
    frame.PasteLabel = pasteLabel

    local scrollFrame = CreateFrame("ScrollFrame", "EBBRestoreScrollFrame",
                                     frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -55)
    scrollFrame:SetPoint("RIGHT", -35, 0)
    scrollFrame:SetHeight(80)

    local editBox = CreateFrame("EditBox", "EBBRestoreEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(360)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)
    frame.EditBox = editBox

    local previewBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    previewBtn:SetWidth(100)
    previewBtn:SetHeight(22)
    previewBtn:SetPoint("TOPLEFT", 15, -140)
    previewBtn:SetText("Preview")
    frame.PreviewButton = previewBtn

    local previewPanel = CreateFrame("Frame", nil, frame)
    previewPanel:SetPoint("TOPLEFT", 15, -168)
    previewPanel:SetPoint("RIGHT", -15, 0)
    previewPanel:SetHeight(75)

    local BACKDROP_INNER = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    }
    previewPanel:SetBackdrop(BACKDROP_INNER)
    previewPanel:SetBackdropColor(0, 0, 0, 0.6)

    local previewText = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewText:SetPoint("TOPLEFT", 8, -6)
    previewText:SetPoint("BOTTOMRIGHT", -8, 6)
    previewText:SetJustifyH("LEFT")
    previewText:SetJustifyV("TOP")
    previewText:SetTextColor(0.8, 0.8, 0.8)
    previewText:SetText("Paste a backup string and click Preview to see contents.")
    frame.PreviewText = previewText
    frame.PreviewPanel = previewPanel

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("BOTTOM", 0, 42)
    status:SetTextColor(1, 0.3, 0.3)
    frame.StatusText = status

    local restoreBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    restoreBtn:SetWidth(120)
    restoreBtn:SetHeight(22)
    restoreBtn:SetPoint("BOTTOMRIGHT", -15, 15)
    restoreBtn:SetText("Restore Backup")
    restoreBtn:Disable()
    frame.RestoreButton = restoreBtn

    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(80)
    cancelBtn:SetHeight(22)
    cancelBtn:SetPoint("BOTTOMLEFT", 15, 15)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() frame:Hide() end)

    UI.RestoreDialog = frame
    return frame
end

--------------------------------------------------------------------------------
-- Template Name Input Dialog
--------------------------------------------------------------------------------

function UI:CreateTemplateNameDialog()
    if UI.TemplateNameDialog then
        return UI.TemplateNameDialog
    end

    local BACKDROP = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    }

    local frame = CreateFrame("Frame", "EBBTemplateNameDialog", UIParent)
    frame:SetWidth(280)
    frame:SetHeight(120)
    frame:SetPoint("CENTER")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:EnableMouse(true)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:Hide()

    tinsert(UISpecialFrames, "EBBTemplateNameDialog")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Template Name")
    frame.Title = title

    local editBox = CreateFrame("EditBox", "EBBTemplateNameInput", frame,
                                 "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", 20, -45)
    editBox:SetPoint("TOPRIGHT", -20, -45)
    editBox:SetHeight(22)
    editBox:SetAutoFocus(true)
    editBox:SetMaxLetters(40)
    frame.NameEditBox = editBox

    local okBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    okBtn:SetWidth(80)
    okBtn:SetHeight(22)
    okBtn:SetPoint("BOTTOMLEFT", 30, 15)
    okBtn:SetText("OK")
    frame.OKButton = okBtn

    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(80)
    cancelBtn:SetHeight(22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -30, 15)
    cancelBtn:SetText("Cancel")
    frame.CancelButton = cancelBtn

    cancelBtn:SetScript("OnClick", function() frame:Hide() end)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)

    UI.TemplateNameDialog = frame
    return frame
end

--------------------------------------------------------------------------------
-- Template List Dialog
--------------------------------------------------------------------------------

function UI:CreateTemplateListDialog()
    if UI.TemplateListDialog then
        return UI.TemplateListDialog
    end

    local BACKDROP = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    }

    local BACKDROP_INNER = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    }

    local frame = CreateFrame("Frame", "EBBTemplateListDialog", UIParent)
    frame:SetWidth(250)
    frame:SetHeight(280)
    frame:SetPoint("CENTER")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:Hide()

    tinsert(UISpecialFrames, "EBBTemplateListDialog")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Templates")
    frame.Title = title

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local listContainer = CreateFrame("Frame", nil, frame)
    listContainer:SetPoint("TOPLEFT", 12, -35)
    listContainer:SetPoint("BOTTOMRIGHT", -12, 50)
    listContainer:SetBackdrop(BACKDROP_INNER)
    listContainer:SetBackdropColor(0, 0, 0, 0.5)

    local scrollFrame = CreateFrame("ScrollFrame", "EBBTemplateListScroll",
                                     listContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -27, 5)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(180)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    frame.ScrollChild = scrollChild
    frame.TemplateRows = {}

    local applyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyBtn:SetWidth(80)
    applyBtn:SetHeight(22)
    applyBtn:SetPoint("BOTTOMLEFT", 15, 15)
    applyBtn:SetText("Apply")
    applyBtn:Disable()
    frame.ApplyButton = applyBtn

    local deleteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deleteBtn:SetWidth(80)
    deleteBtn:SetHeight(22)
    deleteBtn:SetPoint("BOTTOMRIGHT", -15, 15)
    deleteBtn:SetText("Delete")
    deleteBtn:Disable()
    frame.DeleteButton = deleteBtn

    frame.selectedTemplate = nil

    UI.TemplateListDialog = frame
    return frame
end

function UI:GetOrCreateTemplateRow(parent, index)
    local dialog = UI.TemplateListDialog
    if dialog.TemplateRows[index] then
        return dialog.TemplateRows[index]
    end

    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(20)
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

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 5, 0)
    text:SetPoint("RIGHT", -5, 0)
    text:SetJustifyH("LEFT")
    row.Text = text

    dialog.TemplateRows[index] = row
    return row
end
