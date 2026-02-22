--[[----------------------------------------------------------------------------
    Behavior and event handling for the Explorer configuration panel.
    Manages spec dropdown, level list, slot grid display.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Explorer = {}

local Explorer = EBB.Explorer
local UI = EBB.UI
local ActionBar = EBB.ActionBar
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile
local Layout = EBB.Layout
local Core = EBB.Core
local ClassBars = EBB.ClassBars
local SlotEditor = EBB.SlotEditor
local Restore = EBB.Restore
local Keyframe = EBB.Keyframe
local Clipboard = EBB.Clipboard
local Template = EBB.Template
local Timeline = EBB.Timeline
local ImportExport = EBB.ImportExport

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local viewedSpecIndex = nil  
local selectedLevel = nil
local currentMapping = nil  

local editingLevel = nil
local pendingChanges = {}
local isForceClosing = false
local pendingAction = nil
local preEditSnapshot = nil
local preEditLevel = nil

--------------------------------------------------------------------------------
-- Display Mapping
--------------------------------------------------------------------------------

function Explorer:BuildMapping()
    local isActiveSpec = self:IsViewingActiveSpec()
    local stanceIndex = isActiveSpec and ActionBar:GetStanceIndex() or 0

    currentMapping = ClassBars:GetDisplayMapping(stanceIndex, isActiveSpec)
end

function Explorer:GetCurrentMapping()
    if not currentMapping then
        self:BuildMapping()
    end
    return currentMapping
end

--------------------------------------------------------------------------------
-- Show / Hide / Toggle
--------------------------------------------------------------------------------

function Explorer:Show()
    local frame = UI:CreateExplorerFrame()
    self:Initialize()
    
    viewedSpecIndex = Profile:GetActive()
    selectedLevel = nil
    editingLevel = nil
    pendingChanges = {}
    
    self:Refresh()
    frame:Show()
end

function Explorer:Hide()
    if UI.ExplorerFrame then
        UI.ExplorerFrame:Hide()
    end
end

function Explorer:Toggle()
    if UI.ExplorerFrame and UI.ExplorerFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function Explorer:IsVisible()
    return UI.ExplorerFrame and UI.ExplorerFrame:IsShown()
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local isInitialized = false

function Explorer:Initialize()
    if isInitialized then return end
    isInitialized = true
    
    local frame = UI.ExplorerFrame
    
    UIDropDownMenu_Initialize(frame.SpecDropdown, function(self, level)
        Explorer:InitializeSpecDropdown(self, level)
    end)
    
    for barIndex = 1, Settings.TOTAL_BARS do
        local toggle = frame.BarToggles[barIndex]
        toggle:SetScript("OnClick", function(self)
            Explorer:OnBarToggleClick(self.barIndex)
        end)
    end
    
    if frame.SwitchSpecButton then
        frame.SwitchSpecButton:SetScript("OnClick", function()
            Explorer:OnSwitchSpecClick()
        end)
    end
    
    for slot = 1, Settings.TOTAL_SLOTS do
        local button = frame.SlotButtons[slot]
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(self, btn)
            Explorer:OnSlotClick(self, btn)
        end)
        button:SetScript("OnEnter", function(self)
            Explorer:OnSlotEnter(self)
        end)
        button:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    
    frame.EditSaveButton:SetScript("OnClick", function()
        Explorer:SaveEdits()
    end)
    
    frame.EditRevertButton:SetScript("OnClick", function()
        Explorer:RevertEdits()
    end)
    
    frame:SetScript("OnHide", function(self)
        if isForceClosing then return end
        if Explorer:HasPendingEdits() then
            C_Timer.After(0, function()
                self:Show()
                Explorer:ShowConfirmDialog(function()
                    Explorer:ForceClose()
                end)
            end)
            return
        end
        Explorer:OnClose()
    end)
    
    local dialog = UI:CreateConfirmDialog()
    dialog.SaveButton:SetScript("OnClick", function()
        Explorer:SaveEdits()
        dialog:Hide()
        if pendingAction then
            local action = pendingAction
            pendingAction = nil
            action()
        end
    end)
    dialog.DiscardButton:SetScript("OnClick", function()
        Explorer:RevertEdits()
        dialog:Hide()
        if pendingAction then
            local action = pendingAction
            pendingAction = nil
            action()
        end
    end)
    dialog.CancelButton:SetScript("OnClick", function()
        dialog:Hide()
        pendingAction = nil
    end)
    
    Core:RegisterSpecChangeCallback(function(newSpecIndex)
        Explorer:OnActiveSpecChanged(newSpecIndex)
    end)
    
    if frame.Toolbar then
        local tb = frame.Toolbar
        if tb.CopyBtn then
            tb.CopyBtn:SetScript("OnClick", function()
                Explorer:OnCopyClick()
            end)
        end
        if tb.PasteBtn then
            tb.PasteBtn:SetScript("OnClick", function()
                Explorer:OnPasteClick()
            end)
        end
        if tb.PushUpBtn then
            tb.PushUpBtn:SetScript("OnClick", function()
                Explorer:OnPushClick("up")
            end)
        end
        if tb.PushDownBtn then
            tb.PushDownBtn:SetScript("OnClick", function()
                Explorer:OnPushClick("down")
            end)
        end
        if tb.UndoBtn then
            tb.UndoBtn:SetScript("OnClick", function()
                Explorer:OnUndoClick()
            end)
        end
        if tb.SaveTmplBtn then
            tb.SaveTmplBtn:SetScript("OnClick", function()
                Explorer:OnSaveTemplateClick()
            end)
        end
        if tb.LoadTmplBtn then
            tb.LoadTmplBtn:SetScript("OnClick", function()
                Explorer:OnLoadTemplateClick()
            end)
        end
        if tb.ImportExportBtn then
            tb.ImportExportBtn:SetScript("OnClick", function()
                Explorer:OnImportExportClick()
            end)
        end
        if tb.BackupBtn then
            tb.BackupBtn:SetScript("OnClick", function()
                Explorer:OnBackupClick()
            end)
        end
        if tb.RestoreBtn then
            tb.RestoreBtn:SetScript("OnClick", function()
                Explorer:OnRestoreClick()
            end)
        end
    end
    
    for barIndex = 1, Settings.TOTAL_BARS do
        local label = frame.BarLabels[barIndex]
        if label then
            if not label.ClickFrame then
                local clickFrame = CreateFrame("Button", nil, label:GetParent())
                clickFrame:SetAllPoints(label)
                clickFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                clickFrame:SetScript("OnClick", function(self, btn)
                    if btn == "LeftButton" and IsShiftKeyDown() then
                        Explorer:OnBarLabelShiftClick(self.barIndex)
                    elseif btn == "RightButton" then
                        Explorer:OnBarLabelRightClick(self.barIndex, label)
                    end
                end)
                clickFrame:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Shift-click to toggle entire bar", 0.6, 0.6, 0.6)
                    GameTooltip:AddLine("Right-click to rename", 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end)
                clickFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
                clickFrame.barIndex = barIndex
                label.ClickFrame = clickFrame
            end
        end
    end
    
    if frame.StoreBPBtn then
        frame.StoreBPBtn:SetScript("OnClick", function()
            Explorer:OnStoreBPClick()
        end)
        frame.StoreBPBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Store as Breakpoint", 1, 1, 1)
            GameTooltip:AddLine("Mark the selected level as a breakpoint.", 0.7, 0.7, 0.7, true)
            GameTooltip:AddLine("The existing layout data is preserved.", 0.5, 0.8, 0.5)
            GameTooltip:Show()
        end)
        frame.StoreBPBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if frame.CreateBPBtn then
        frame.CreateBPBtn:SetScript("OnClick", function()
            Explorer:OnCreateBPClick()
        end)
        frame.CreateBPBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Create Breakpoint", 1, 1, 1)
            GameTooltip:AddLine("Create a new breakpoint at any level.", 0.7, 0.7, 0.7, true)
            GameTooltip:AddLine("You can then edit the layout using the slot editor.", 0.5, 0.8, 0.5)
            GameTooltip:Show()
        end)
        frame.CreateBPBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    if frame.ModePerLevelBtn then
        frame.ModePerLevelBtn:SetScript("OnClick", function()
            Explorer:OnModeSelected(Settings.RECORD_PER_LEVEL)
        end)
        frame.ModePerLevelBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Per-Level Recording", 1, 1, 1)
            GameTooltip:AddLine("Saves a full layout snapshot at every level.", 0.7, 0.7, 0.7, true)
            GameTooltip:AddLine("Best for detailed tracking.", 0.5, 0.8, 0.5)
            GameTooltip:Show()
        end)
        frame.ModePerLevelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if frame.ModeBreakpointBtn then
        frame.ModeBreakpointBtn:SetScript("OnClick", function()
            Explorer:OnModeSelected(Settings.RECORD_BREAKPOINT)
        end)
        frame.ModeBreakpointBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Breakpoint Recording", 1, 1, 1)
            GameTooltip:AddLine("Only saves at keyframe levels. Intermediate levels are derived with auto-adjusted spell ranks.", 0.7, 0.7, 0.7, true)
            GameTooltip:AddLine("Best for clean milestone-based layouts.", 0.5, 0.8, 0.5)
            GameTooltip:Show()
        end)
        frame.ModeBreakpointBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

--------------------------------------------------------------------------------
-- Spec Dropdown
--------------------------------------------------------------------------------

function Explorer:InitializeSpecDropdown(dropdown, level)
    local activeSpec = Profile:GetActive()
    
    for specIndex = 1, 5 do
        local info = UIDropDownMenu_CreateInfo()
        local specName = Profile:GetSpecName(specIndex)
        
        if specIndex == activeSpec then
            info.text = specName .. " |cFF00FF00(active)|r"
        else
            info.text = specName
        end
        
        info.value = specIndex
        info.checked = (specIndex == viewedSpecIndex)
        info.func = function()
            Explorer:OnSpecSelected(specIndex)
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

function Explorer:RefreshSpecDropdown()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local specName = Profile:GetSpecName(viewedSpecIndex)
    local activeSpec = Profile:GetActive()
    
    if viewedSpecIndex == activeSpec then
        UIDropDownMenu_SetText(frame.SpecDropdown, specName .. " |cFF00FF00(active)|r")
    else
        UIDropDownMenu_SetText(frame.SpecDropdown, specName)
    end
    
    if editingLevel then
        UIDropDownMenu_DisableDropDown(frame.SpecDropdown)
    else
        UIDropDownMenu_EnableDropDown(frame.SpecDropdown)
    end
end

function Explorer:OnSpecSelected(specIndex)
    if specIndex == viewedSpecIndex then
        return
    end
    
    if editingLevel then
        Utils:Print("Save or revert edits before switching specs")
        return
    end
    
    self:DoSpecSelect(specIndex)
end

function Explorer:DoSpecSelect(specIndex)
    viewedSpecIndex = specIndex
    selectedLevel = nil
    editingLevel = nil
    pendingChanges = {}
    preEditSnapshot = nil
    self:Refresh()
end

function Explorer:OnActiveSpecChanged(newSpecIndex)
    if editingLevel then
        editingLevel = nil
        pendingChanges = {}
        preEditSnapshot = nil
        if SlotEditor:IsOpen() then
            SlotEditor:Close()
        end
    end
    
    viewedSpecIndex = newSpecIndex
    selectedLevel = nil
    
    if self:IsVisible() then
        self:Refresh()
    end
end

--------------------------------------------------------------------------------
-- Viewed Spec Helpers
--------------------------------------------------------------------------------

function Explorer:GetViewedSpec()
    return viewedSpecIndex or Profile:GetActive()
end

function Explorer:IsViewingActiveSpec()
    return self:GetViewedSpec() == Profile:GetActive()
end

--------------------------------------------------------------------------------
-- Switch Spec Button
--------------------------------------------------------------------------------

function Explorer:RefreshSwitchButton()
    local frame = UI.ExplorerFrame
    if not frame or not frame.SwitchSpecButton then return end
    
    local button = frame.SwitchSpecButton
    
    if editingLevel then
        button:SetText("Editing...")
        button:Disable()
        return
    end
    
    local isPending = Core.IsSpecSwitchPending and Core:IsSpecSwitchPending()
    
    if isPending then
        button:SetText("Switching...")
        button:Disable()
    elseif self:IsViewingActiveSpec() then
        button:SetText("Active Spec")
        button:Disable()
    else
        button:SetText("Switch Spec")
        button:Enable()
    end
end

function Explorer:OnSwitchSpecClick()
    if editingLevel then return end
    
    local targetSpec = self:GetViewedSpec()
    if targetSpec == Profile:GetActive() then return end
    
    if Core.SwitchSpec then
        local success = Core:SwitchSpec(targetSpec)
        if success then
            self:RefreshSwitchButton()
        end
    end
end

--------------------------------------------------------------------------------
-- Level List
--------------------------------------------------------------------------------

function Explorer:RefreshLevelList()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local specIndex = self:GetViewedSpec()
    local allLevels = Layout:GetSavedLevels(specIndex)
    local currentLevel = Utils:GetPlayerLevel()
    local isBreakpoint = Settings:IsBreakpointMode()
    
    local levels
    if isBreakpoint and Keyframe then
        local kfSet = {}
        levels = {}
        for _, level in ipairs(Keyframe:GetAll(specIndex)) do
            kfSet[level] = true
            table.insert(levels, level)
        end
        for _, level in ipairs(allLevels) do
            if Keyframe:IsKeyframe(level, specIndex) and not kfSet[level] then
                table.insert(levels, level)
            end
        end
        table.sort(levels)
    else
        levels = allLevels
    end
    
    if frame.LevelsLabel then
        if isBreakpoint then
            frame.LevelsLabel:SetText("Breakpoints")
        else
            frame.LevelsLabel:SetText("Saved Levels")
        end
    end
    
    for _, button in pairs(frame.LevelButtons) do
        button:Hide()
    end
    
    local filteredSet = {}
    for _, level in ipairs(levels) do
        filteredSet[level] = true
    end
    
    if not selectedLevel or not filteredSet[selectedLevel] then
        if filteredSet[currentLevel] then
            selectedLevel = currentLevel
        elseif #levels > 0 then
            selectedLevel = levels[#levels]
        else
            selectedLevel = nil
        end
    end
    
    local yOffset = 0
    for i, level in ipairs(levels) do
        local button = UI:GetOrCreateLevelButton(frame.LevelScrollChild, i)
        button:SetPoint("TOPLEFT", 0, -yOffset)
        button.level = level
        
        local isKF = Keyframe and Keyframe:IsKeyframe(level, specIndex)
        local isDerived = Keyframe and Keyframe:IsDerived(level, specIndex)
        
        button.Text:SetText("Lv " .. level)
        
        if button.Indicator then
            if isKF then
                button.Indicator:SetVertexColor(1, 0.82, 0, 1)  -- gold
            elseif isDerived then
                button.Indicator:SetVertexColor(0.5, 0.7, 1, 0.6)  -- blue
            else
                button.Indicator:SetVertexColor(0.7, 0.7, 0.7, 1)  -- grey
            end
        end
        
        if button.TypeLabel then
            if isKF then
                button.TypeLabel:SetText("BP")
                button.TypeLabel:SetTextColor(1, 0.82, 0)
                button.TypeLabel:Show()
            elseif isDerived then
                button.TypeLabel:SetText("D")
                button.TypeLabel:SetTextColor(0.5, 0.7, 1)
                button.TypeLabel:Show()
            else
                button.TypeLabel:SetText("")
                button.TypeLabel:Hide()
            end
        end
        
        if button.SlotCount then
            local layout = Layout:Get(level, specIndex)
            if layout and layout.configuredSlots then
                button.SlotCount:SetText(layout.configuredSlots)
                button.SlotCount:Show()
            else
                button.SlotCount:Hide()
            end
        end
        
        if isKF then
            button.Text:SetTextColor(1, 0.9, 0.6)
        elseif isDerived then
            button.Text:SetTextColor(0.6, 0.75, 0.9)
        else
            button.Text:SetTextColor(0.9, 0.9, 0.9)
        end
        
        if level == selectedLevel then
            button.SelectedTexture:Show()
        else
            button.SelectedTexture:Hide()
        end
        
        if level == currentLevel and self:IsViewingActiveSpec() then
            button.CurrentIndicator:Show()
        else
            button.CurrentIndicator:Hide()
        end
        
        button:SetScript("OnClick", function(self)
            Explorer:OnLevelSelected(self.level)
        end)
        
        button:Show()
        yOffset = yOffset + 20
    end
    
    frame.LevelScrollChild:SetHeight(math.max(yOffset, 1))
    
    self:RefreshKeyframeToggle()
end

function Explorer:OnLevelSelected(level)
    self:DoLevelSelect(level)
end

function Explorer:DoLevelSelect(level)
    if preEditLevel and preEditLevel ~= level then
        preEditSnapshot = nil
        preEditLevel = nil
    end
    
    selectedLevel = level
    self:RefreshSpecDropdown()
    self:RefreshSwitchButton()
    self:RefreshLevelList()
    self:BuildMapping()
    self:RefreshSlotGrid()
    self:RefreshBarLabels()
    self:RefreshBarToggles()
    self:RefreshEditControls()
    self:RefreshToolbar()
    self:RefreshChangeSummary()
end

--------------------------------------------------------------------------------
-- Slot Grid 
--------------------------------------------------------------------------------

function Explorer:RefreshSlotGrid()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local mapping   = self:GetCurrentMapping()
    local specIndex = self:GetViewedSpec()
    local currentLevel = Utils:GetPlayerLevel()
    local useLiveData  = self:IsViewingActiveSpec() and selectedLevel == currentLevel
    
    if editingLevel and selectedLevel == editingLevel then
        useLiveData = false
    end
    
    local layout = nil
    if not useLiveData and selectedLevel then
        layout = Layout:Get(selectedLevel, specIndex)
    end
    
    local isEditingThisLevel = editingLevel and selectedLevel == editingLevel
    local pickerTargetSlot = (editingLevel and SlotEditor:IsOpen())
                             and SlotEditor:GetTargetSlot() or nil
    
    for displayRow = 1, Settings.TOTAL_BARS do
        local rowInfo = mapping[displayRow]
        local dataBar = rowInfo and rowInfo.dataBar
        
        for pos = 1, Settings.SLOTS_PER_BAR do
            local visualSlot = ((displayRow - 1) * Settings.SLOTS_PER_BAR) + pos
            local button = frame.SlotButtons[visualSlot]
            
            if not dataBar then
                button.Icon:SetTexture(nil)
                button.DisabledOverlay:Hide()
                button.EditBorder:Hide()
                button.ActiveEditBorder:Hide()
                if button.TypeDot then button.TypeDot:Hide() end
                if button.PosLabel then button.PosLabel:Hide() end
                button.slotInfo = nil
                button.dataSlot = nil
            else
                local dataSlot = ((dataBar - 1) * Settings.SLOTS_PER_BAR) + pos
                local slotInfo
                
                if useLiveData then
                    slotInfo = ActionBar:GetSlotInfo(dataSlot)
                else
                    slotInfo = layout and layout.slots and layout.slots[dataSlot]
                end
                
                local hasPendingEdit = false
                if isEditingThisLevel and pendingChanges[dataSlot] then
                    slotInfo = pendingChanges[dataSlot]
                    hasPendingEdit = true
                end
                
                local isEnabled = Profile:IsSlotEnabled(dataSlot, specIndex)
                
                if slotInfo and slotInfo.icon then
                    button.Icon:SetTexture(slotInfo.icon)
                elseif slotInfo and slotInfo.type and slotInfo.type ~= "empty" then
                    button.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                else
                    button.Icon:SetTexture(nil)
                end

                if isEnabled then
                    button.DisabledOverlay:Hide()
                else
                    button.DisabledOverlay:Show()
                end
                
                if hasPendingEdit then
                    button.EditBorder:Show()
                else
                    button.EditBorder:Hide()
                end
                
                if pickerTargetSlot and pickerTargetSlot == dataSlot then
                    button.ActiveEditBorder:Show()
                else
                    button.ActiveEditBorder:Hide()
                end
                
                if button.TypeDot then
                    if slotInfo and slotInfo.type and slotInfo.type ~= "empty" then
                        local t = slotInfo.type
                        if t == "spell" then
                            button.TypeDot:SetVertexColor(0.3, 0.6, 1, 0.9)    -- blue
                        elseif t == "item" then
                            button.TypeDot:SetVertexColor(0.3, 0.9, 0.3, 0.9)  -- green
                        elseif t == "macro" then
                            button.TypeDot:SetVertexColor(1, 0.6, 0.2, 0.9)    -- orange
                        elseif t == "companion" then
                            button.TypeDot:SetVertexColor(0.7, 0.4, 1, 0.9)    -- purple
                        elseif t == "equipmentset" then
                            button.TypeDot:SetVertexColor(0.8, 0.8, 0.8, 0.9)  -- silver
                        else
                            button.TypeDot:SetVertexColor(0.5, 0.5, 0.5, 0.7)  -- grey
                        end
                        button.TypeDot:Show()
                    else
                        button.TypeDot:Hide()
                    end
                end
                
                if button.PosLabel then
                    button.PosLabel:SetText(tostring(pos))
                    if slotInfo and slotInfo.type and slotInfo.type ~= "empty" then
                        button.PosLabel:Hide() 
                    else
                        button.PosLabel:Show() 
                    end
                end
                
                button.slotInfo = slotInfo
                button.dataSlot = dataSlot
            end
        end
    end
end

function Explorer:OnSlotClick(button, mouseButton)
    if not button.dataSlot then return end
    
    if IsShiftKeyDown() then
        self:OnSlotShiftClick(button)
        return
    end
    
    if not self:IsViewingActiveSpec() then return end
    
    if editingLevel and selectedLevel ~= editingLevel then return end
    
    if not selectedLevel or not Layout:Has(selectedLevel, self:GetViewedSpec()) then
        return
    end
    
    local dataSlot = button.dataSlot
    
    if mouseButton == "RightButton" then
        if not editingLevel then
            local layout = Layout:Get(selectedLevel, self:GetViewedSpec())
            local savedInfo = layout and layout.slots and layout.slots[dataSlot]
            if not savedInfo or savedInfo.type == "empty" then
                return
            end
        end
    end
    
    if not editingLevel then
        editingLevel = selectedLevel
        local specIndex = self:GetViewedSpec()
        local layout = Layout:Get(editingLevel, specIndex)
        preEditSnapshot = layout and Utils:DeepCopy(layout) or nil
        preEditLevel = editingLevel
    end
    
    if mouseButton == "LeftButton" then
        self:OpenPickerForSlot(dataSlot)
    elseif mouseButton == "RightButton" then
        self:ClearSlotEdit(dataSlot)
    end
end

--------------------------------------------------------------------------------
-- Spellbook Search (for tooltip enrichment)
--------------------------------------------------------------------------------

function Explorer:FindSpellInSpellbook(spellName)
    if not spellName then return nil end
    
    local numTabs = GetNumSpellTabs()
    local bestMatch = nil
    
    for tabIndex = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tabIndex)
        for spellIndex = offset + 1, offset + numSpells do
            local bookName = GetSpellName(spellIndex, BOOKTYPE_SPELL)
            if bookName and bookName == spellName then
                bestMatch = spellIndex
            end
        end
    end
    
    return bestMatch
end

function Explorer:OnSlotEnter(button)
    local info = button.slotInfo
    local dataSlot = button.dataSlot
    
    local canEdit = self:IsViewingActiveSpec()
                    and (not editingLevel or selectedLevel == editingLevel)
                    and selectedLevel
                    and Layout:Has(selectedLevel, self:GetViewedSpec())
    
    if not info or info.type == "empty" then
        if dataSlot then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            if canEdit then
                GameTooltip:AddLine("Left-click to assign", 0.7, 0.7, 0.7)
            end
            local specIndex = self:GetViewedSpec()
            local isEnabled = Profile:IsSlotEnabled(dataSlot, specIndex)
            if not isEnabled then
                GameTooltip:AddLine("Slot disabled", 0.8, 0.3, 0.3)
            end
            GameTooltip:AddLine(
                "Shift-click to " .. (isEnabled and "disable" or "enable") .. " this slot",
                0.6, 0.6, 0.6
            )
            GameTooltip:Show()
        end
        return
    end
    
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local currentLevel = Utils:GetPlayerLevel()
    local useLiveData = self:IsViewingActiveSpec() and selectedLevel == currentLevel
                        and not (editingLevel and selectedLevel == editingLevel)
    
    if useLiveData and dataSlot then
        GameTooltip:SetAction(dataSlot)
    else
        local enriched = false
        
        if info.type == "spell" and info.name then
            local spellbookIndex = self:FindSpellInSpellbook(info.name)
            if spellbookIndex then
                GameTooltip:SetSpell(spellbookIndex, BOOKTYPE_SPELL)
                enriched = true
            end
        elseif info.type == "item" and info.id then
            GameTooltip:SetHyperlink("item:" .. info.id)
            enriched = true
        end
        
        if not enriched then
            GameTooltip:AddLine(info.name or "Unknown", 1, 1, 1)
            if info.type == "spell" and info.rank and info.rank ~= "" then
                GameTooltip:AddLine(info.rank, 0.5, 0.5, 0.5)
            end
            if info.type == "macro" and info.body then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(info.body, 0.7, 0.7, 0.7, true)
            end
        end
    end
    
    if dataSlot then
        local bar = ActionBar:GetBarFromSlot(dataSlot)
        local pos = ActionBar:GetPositionInBar(dataSlot)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            string.format("Slot %d (Bar %d, #%d)", dataSlot, bar, pos),
            0.4, 0.4, 0.4
        )
    end
    
    if canEdit and dataSlot then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click to change, Right-click to clear", 0.5, 0.8, 1)
    end
    
    if dataSlot then
        local specIndex = self:GetViewedSpec()
        local isEnabled = Profile:IsSlotEnabled(dataSlot, specIndex)
        GameTooltip:AddLine(
            "Shift-click to " .. (isEnabled and "disable" or "enable") .. " this slot",
            0.6, 0.6, 0.6
        )
    end
    
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Bar Labels
--------------------------------------------------------------------------------

local LABEL_COLOR_NORMAL = { r = 1.0, g = 0.82, b = 0.0 }
local LABEL_COLOR_ACTIVE = { r = 0.0, g = 1.0,  b = 0.0 }
local LABEL_COLOR_GRAYED = { r = 0.5, g = 0.5,  b = 0.5 }

function Explorer:RefreshBarLabels()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local mapping = self:GetCurrentMapping()
    
    for displayRow = 1, Settings.TOTAL_BARS do
        local label   = frame.BarLabels[displayRow]
        local rowInfo = mapping[displayRow]
        
        label:SetText(rowInfo.label)
        
        if rowInfo.isActive then
            label:SetTextColor(LABEL_COLOR_ACTIVE.r, LABEL_COLOR_ACTIVE.g, LABEL_COLOR_ACTIVE.b)
        elseif rowInfo.grayed then
            label:SetTextColor(LABEL_COLOR_GRAYED.r, LABEL_COLOR_GRAYED.g, LABEL_COLOR_GRAYED.b)
        else
            label:SetTextColor(LABEL_COLOR_NORMAL.r, LABEL_COLOR_NORMAL.g, LABEL_COLOR_NORMAL.b)
        end
    end
end

--------------------------------------------------------------------------------
-- Bar Toggles
--------------------------------------------------------------------------------

function Explorer:RefreshBarToggles()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    if frame.BarToggles then
        for displayRow = 1, Settings.TOTAL_BARS do
            local toggle = frame.BarToggles[displayRow]
            if toggle then
                toggle:Hide()
            end
        end
    end
end

function Explorer:OnBarToggleClick(displayRow)
end

function Explorer:OnBarLabelShiftClick(displayRow)
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local mapping = self:GetCurrentMapping()
    local rowInfo = mapping[displayRow]
    if not rowInfo or not rowInfo.dataBar then return end
    
    local dataBar  = rowInfo.dataBar
    local specIndex = self:GetViewedSpec()
    
    local newEnabled = not Profile:IsBarFullyEnabled(dataBar, specIndex)
    Profile:SetBarEnabled(dataBar, newEnabled, specIndex)
    
    self:RefreshSlotGrid()
end

function Explorer:OnBarLabelRightClick(displayRow, labelFontString)
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local mapping = self:GetCurrentMapping()
    local rowInfo = mapping[displayRow]
    if not rowInfo or not rowInfo.dataBar then return end
    
    local dataBar = rowInfo.dataBar
    
    if not frame.BarLabelEditBox then
        local editBox = CreateFrame("EditBox", "EBBBarLabelEdit", frame)
        editBox:SetFontObject("GameFontNormalSmall")
        editBox:SetHeight(14)
        editBox:SetAutoFocus(true)
        editBox:SetMaxLetters(30)
        
        local bg = editBox:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(0, 0, 0, 0.8)
        editBox.Background = bg
        
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            self:Hide()
            if self.targetLabel then
                self.targetLabel:Show()
            end
        end)
        
        editBox:SetScript("OnEnterPressed", function(self)
            local newLabel = strtrim(self:GetText())
            if newLabel ~= "" and self.targetBar then
                Settings:SetBarLabel(self.targetBar, newLabel)
                Utils:Print(string.format("Bar %d renamed to: %s", self.targetBar, newLabel))
                Explorer:BuildMapping()
                Explorer:RefreshBarLabels()
            end
            self:ClearFocus()
            self:Hide()
            if self.targetLabel then
                self.targetLabel:Show()
            end
        end)
        
        editBox:Hide()
        frame.BarLabelEditBox = editBox
    end
    
    local editBox = frame.BarLabelEditBox
    
    editBox:ClearAllPoints()
    editBox:SetPoint("TOPLEFT", labelFontString, "TOPLEFT", -2, 2)
    editBox:SetPoint("BOTTOMRIGHT", labelFontString, "BOTTOMRIGHT", 2, -2)
    editBox:SetWidth(labelFontString:GetWidth() + 20)
    
    local currentLabel = Settings:GetBarLabel(dataBar)
    editBox:SetText(currentLabel)
    editBox:HighlightText()
    editBox.targetBar = dataBar
    editBox.targetLabel = labelFontString
    
    labelFontString:Hide()
    editBox:Show()
    editBox:SetFocus()
end

function Explorer:OnSlotShiftClick(button)
    if not button.dataSlot then return end
    
    local specIndex = self:GetViewedSpec()
    local slot = button.dataSlot
    local isEnabled = Profile:IsSlotEnabled(slot, specIndex)
    
    Profile:SetSlotEnabled(slot, not isEnabled, specIndex)
    self:RefreshSlotGrid()
end

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------

function Explorer:IsEditMode()
    return editingLevel ~= nil
end

function Explorer:HasPendingEdits()
    return editingLevel ~= nil and next(pendingChanges) ~= nil
end

function Explorer:RefreshEditControls()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    if editingLevel then
        if selectedLevel == editingLevel then
            frame.EditLabel:SetTextColor(1, 0.82, 0)
            frame.EditLabel:SetText(string.format("Editing Level %d", editingLevel))
        else
            frame.EditLabel:SetTextColor(0.5, 0.5, 0.5)
            frame.EditLabel:SetText(string.format("Editing Level %d", editingLevel))
        end
    else
        frame.EditLabel:SetText("")
    end
    
    if self:HasPendingEdits() then
        frame.EditSaveButton:Show()
        frame.EditRevertButton:Show()
    else
        frame.EditSaveButton:Hide()
        frame.EditRevertButton:Hide()
    end
    
    self:RefreshSpecDropdown()
end

--------------------------------------------------------------------------------
-- Slot Editing
--------------------------------------------------------------------------------

function Explorer:OpenPickerForSlot(dataSlot)
    local level = editingLevel
    SlotEditor:Open(dataSlot, level, function(slotInfo)
        pendingChanges[dataSlot] = slotInfo
        self:RefreshSlotGrid()
        self:RefreshEditControls()
    end)
    
    local picker = UI.PickerFrame
    if picker and not picker.explorerOnHideHooked then
        picker:HookScript("OnHide", function()
            if editingLevel and not next(pendingChanges) then
                editingLevel = nil
                Explorer:RefreshEditControls()
                Explorer:RefreshSwitchButton()
            end
            Explorer:RefreshSlotGrid()
        end)
        picker.explorerOnHideHooked = true
    end
    
    self:RefreshSlotGrid()
end

function Explorer:ClearSlotEdit(dataSlot)
    if pendingChanges[dataSlot] and pendingChanges[dataSlot].type == "empty" then
        return
    end
    
    local layout = Layout:Get(editingLevel, self:GetViewedSpec())
    local savedInfo = layout and layout.slots and layout.slots[dataSlot]
    local savedIsEmpty = not savedInfo or savedInfo.type == "empty"
    
    if pendingChanges[dataSlot] and savedIsEmpty then
        pendingChanges[dataSlot] = nil
    elseif savedIsEmpty and not pendingChanges[dataSlot] then
        return
    else
        pendingChanges[dataSlot] = { type = "empty", slot = dataSlot }
    end
    
    self:RefreshSlotGrid()
    self:RefreshEditControls()
end

--------------------------------------------------------------------------------
-- Save / Revert
--------------------------------------------------------------------------------

function Explorer:SaveEdits()
    if not editingLevel then return end
    
    local specIndex = self:GetViewedSpec()
    local layout = Layout:Get(editingLevel, specIndex)
    if not layout then return end
    
    if Clipboard then
        Clipboard:PushUndo(editingLevel, specIndex, "Edit level " .. editingLevel)
    end
    
    local updated = Utils:DeepCopy(layout)
    
    for slot, info in pairs(pendingChanges) do
        updated.slots[slot] = Utils:DeepCopy(info)
    end
    
    local configured = 0
    for s = 1, Settings.TOTAL_SLOTS do
        if updated.slots[s] and updated.slots[s].type ~= "empty" then
            configured = configured + 1
        end
    end
    updated.configuredSlots = configured
    
    Layout:Save(editingLevel, updated, specIndex)
    
    local savedLevel = editingLevel
    pendingChanges = {}
    editingLevel = nil
    
    Utils:Print(string.format("Level %d: Edits saved", savedLevel))
    
    local currentLevel = Utils:GetPlayerLevel()
    if savedLevel == currentLevel and specIndex == Profile:GetActive() then
        Restore:PerformWhenSafe(savedLevel)
    end
    
    if SlotEditor:IsOpen() then
        SlotEditor:Close()
    end
    
    self:RefreshSlotGrid()
    self:RefreshEditControls()
    self:RefreshSwitchButton()
    self:RefreshToolbar()
    self:RefreshChangeSummary()
end

function Explorer:RevertEdits()
    pendingChanges = {}
    editingLevel = nil
    preEditSnapshot = nil
    
    if SlotEditor:IsOpen() then
        SlotEditor:Close()
    end
    
    self:RefreshSlotGrid()
    self:RefreshEditControls()
    self:RefreshSwitchButton()
    self:RefreshToolbar()
end

--------------------------------------------------------------------------------
-- Confirmation Dialog
--------------------------------------------------------------------------------

function Explorer:ShowConfirmDialog(onComplete)
    pendingAction = onComplete
    local dialog = UI:CreateConfirmDialog()
    dialog:Show()
end

--------------------------------------------------------------------------------
-- Close Handling
--------------------------------------------------------------------------------

function Explorer:OnClose()
    editingLevel = nil
    pendingChanges = {}
    preEditSnapshot = nil
    
    if SlotEditor:IsOpen() then
        SlotEditor:Close()
    end
end

function Explorer:ForceClose()
    isForceClosing = true
    if UI.ExplorerFrame then
        UI.ExplorerFrame:Hide()
    end
    isForceClosing = false
    self:OnClose()
end

--------------------------------------------------------------------------------
-- Keyframe Toggle
--------------------------------------------------------------------------------

function Explorer:RefreshKeyframeToggle()
    self:RefreshBreakpointButtons()
end

function Explorer:RefreshBreakpointButtons()
    local frame = UI.ExplorerFrame
    if not frame then return end

    local isBP = Settings:IsBreakpointMode()

    if frame.StoreBPBtn then
        if not isBP then
            frame.StoreBPBtn:Hide()
        else
            frame.StoreBPBtn:Show()
            if not selectedLevel or not Keyframe then
                frame.StoreBPBtn:Disable()
            else
                local specIndex = self:GetViewedSpec()
                local hasLayout = Layout:Has(selectedLevel, specIndex)
                local isAlreadyKF = Keyframe:IsKeyframe(selectedLevel, specIndex)

                if hasLayout and not isAlreadyKF then
                    frame.StoreBPBtn:Enable()
                    frame.StoreBPBtn:SetText("Store BP")
                elseif isAlreadyKF then
                    frame.StoreBPBtn:Enable()
                    frame.StoreBPBtn:SetText("Remove BP")
                else
                    frame.StoreBPBtn:Disable()
                    frame.StoreBPBtn:SetText("Store BP")
                end
            end
        end
    end

    if frame.CreateBPBtn then
        if not isBP then
            frame.CreateBPBtn:Hide()
        else
            frame.CreateBPBtn:Show()
            if editingLevel then
                frame.CreateBPBtn:Disable()
            else
                frame.CreateBPBtn:Enable()
            end
        end
    end
end

function Explorer:OnStoreBPClick()
    if not selectedLevel or not Keyframe then return end

    local specIndex = self:GetViewedSpec()
    local isAlreadyKF = Keyframe:IsKeyframe(selectedLevel, specIndex)

    if isAlreadyKF then
        Keyframe:Remove(selectedLevel, specIndex)

        local layout = Layout:Get(selectedLevel, specIndex)
        if layout and layout.isScaffold and (layout.configuredSlots or 0) == 0 then
            Layout:Delete(selectedLevel, specIndex)
        end

        Utils:Print(string.format("Level %d: Breakpoint removed", selectedLevel))

        selectedLevel = nil
    else
        local ok, err = Keyframe:StoreAsBreakpoint(selectedLevel, specIndex)
        if ok then
            Utils:Print(string.format("Level %d: Stored as breakpoint", selectedLevel))
        else
            Utils:PrintError("Cannot store breakpoint: " .. (err or "unknown"))
            return
        end
    end

    self:RefreshLevelList()
    self:RefreshBreakpointButtons()
    self:RefreshToolbar()
    self:RefreshChangeSummary()
end

function Explorer:OnCreateBPClick()
    if editingLevel then
        Utils:Print("Save or revert edits before creating a breakpoint")
        return
    end

    local dialog = UI:CreateBreakpointDialog()

    dialog.LevelInput:SetText("")
    dialog.StatusText:SetText("")

    dialog.OKButton:SetScript("OnClick", function()
        local levelText = dialog.LevelInput:GetText()
        local level = tonumber(levelText)

        if not level or level < 1 or level > Settings.MAX_LEVEL then
            dialog.StatusText:SetText("Enter a level between 1 and " .. Settings.MAX_LEVEL)
            return
        end

        level = math.floor(level)
        local specIndex = Explorer:GetViewedSpec()

        if Keyframe:IsKeyframe(level, specIndex) then
            dialog.StatusText:SetText("Level " .. level .. " is already a breakpoint")
            return
        end

        local ok, result = Keyframe:CreateAtLevel(level, specIndex)
        if ok then
            if result == "existing" then
                Utils:Print(string.format("Level %d: Existing layout marked as breakpoint", level))
            else
                Utils:Print(string.format("Level %d: Breakpoint created (empty — edit to set up)", level))
            end
            dialog:Hide()

            selectedLevel = level
            Explorer:RefreshLevelList()
            Explorer:RefreshBreakpointButtons()
            Explorer:RefreshSlotGrid()
            Explorer:RefreshToolbar()
            Explorer:RefreshChangeSummary()
        else
            dialog.StatusText:SetText("Failed to create breakpoint")
        end
    end)

    dialog:Show()
    dialog.LevelInput:SetFocus()
end

--------------------------------------------------------------------------------
-- Recording Mode
--------------------------------------------------------------------------------

function Explorer:OnModeSelected(mode)
    if editingLevel then
        Utils:Print("Save or revert edits before switching modes")
        return
    end
    
    local current = Settings:GetRecordingMode()
    if mode == current then return end
    
    Settings:SetRecordingMode(mode)
    Utils:Print("Recording mode: " .. Settings:GetRecordingModeLabel())
    
    self:RefreshModeSelector()
    self:RefreshLevelList()
    self:RefreshKeyframeToggle()
    self:RefreshTitleBar()
    self:RefreshChangeSummary()
end

function Explorer:RefreshModeSelector()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local isPerLevel = Settings:IsPerLevelMode()
    
    if frame.ModePerLevelBtn then
        local fs = frame.ModePerLevelBtn:GetFontString()
        if isPerLevel then
            fs:SetTextColor(0.2, 1, 0.2)
        else
            fs:SetTextColor(1, 0.82, 0)
        end
    end
    
    if frame.ModeBreakpointBtn then
        local fs = frame.ModeBreakpointBtn:GetFontString()
        if not isPerLevel then
            fs:SetTextColor(0.2, 1, 0.2)
        else
            fs:SetTextColor(1, 0.82, 0)
        end
    end
end

function Explorer:RefreshTitleBar()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    if frame.ModeBadge then
        local modeLabel = Settings:GetRecordingModeLabel()
        frame.ModeBadge:SetText(modeLabel)
        
        if Settings:IsBreakpointMode() then
            frame.ModeBadge:SetTextColor(1, 0.82, 0)
        else
            frame.ModeBadge:SetTextColor(0.4, 1, 0.4)
        end
    end
end

--------------------------------------------------------------------------------
-- Toolbar State
--------------------------------------------------------------------------------

function Explorer:RefreshToolbar()
    local frame = UI.ExplorerFrame
    if not frame or not frame.Toolbar then return end
    
    local tb = frame.Toolbar
    local specIndex = self:GetViewedSpec()
    local hasLevel = selectedLevel and Layout:Has(selectedLevel, specIndex)
    local isEditing = editingLevel ~= nil
    local isActiveSpec = self:IsViewingActiveSpec()
    
    if tb.CopyBtn then
        if hasLevel and not isEditing then
            tb.CopyBtn:Enable()
        else
            tb.CopyBtn:Disable()
        end
    end
    
    if tb.PasteBtn then
        if hasLevel and not isEditing and Clipboard and Clipboard:HasContent()
           and isActiveSpec then
            tb.PasteBtn:Enable()
        else
            tb.PasteBtn:Disable()
        end
    end
    
    if tb.PushUpBtn then
        if hasLevel and not isEditing and isActiveSpec then
            tb.PushUpBtn:Enable()
        else
            tb.PushUpBtn:Disable()
        end
    end
    if tb.PushDownBtn then
        if hasLevel and not isEditing and isActiveSpec then
            tb.PushDownBtn:Enable()
        else
            tb.PushDownBtn:Disable()
        end
    end
    
    if tb.UndoBtn then
        if Clipboard and Clipboard:CanUndo() then
            tb.UndoBtn:Enable()
            local desc = Clipboard:GetUndoDescription()
            tb.UndoBtn:SetText(desc and "Undo" or "Undo")
        else
            tb.UndoBtn:Disable()
        end
    end
    
    if tb.SaveTmplBtn then
        if hasLevel and not isEditing then
            tb.SaveTmplBtn:Enable()
        else
            tb.SaveTmplBtn:Disable()
        end
    end
    if tb.LoadTmplBtn then
        if hasLevel and not isEditing and isActiveSpec
           and Template and Template:GetCount(specIndex) > 0 then
            tb.LoadTmplBtn:Enable()
        else
            tb.LoadTmplBtn:Disable()
        end
    end
    
    if tb.ImportExportBtn then
        if not isEditing then
            tb.ImportExportBtn:Enable()
        else
            tb.ImportExportBtn:Disable()
        end
    end
    
    if tb.BackupBtn then
        local levelCount = Layout:GetCount(specIndex)
        if levelCount > 0 and not isEditing then
            tb.BackupBtn:Enable()
        else
            tb.BackupBtn:Disable()
        end
    end
    
    if tb.RestoreBtn then
        if not isEditing then
            tb.RestoreBtn:Enable()
        else
            tb.RestoreBtn:Disable()
        end
    end
end

--------------------------------------------------------------------------------
-- Change Summary
--------------------------------------------------------------------------------

function Explorer:RefreshChangeSummary()
    local frame = UI.ExplorerFrame
    if not frame or not frame.ChangeSummaryPanel then return end
    
    local panel = frame.ChangeSummaryPanel
    
    if panel.Lines then
        for _, line in ipairs(panel.Lines) do
            line:Hide()
        end
    end
    if panel.OverflowText then
        panel.OverflowText:Hide()
    end
    if panel.ScrollLines then
        for _, line in ipairs(panel.ScrollLines) do
            line:Hide()
        end
    end
    
    if not selectedLevel or not Timeline then
        panel.Title:SetText("No changes")
        panel.Title:SetTextColor(0.5, 0.5, 0.5)
        return
    end
    
    local specIndex = self:GetViewedSpec()
    local diff = Timeline:GetChangeSummary(selectedLevel, specIndex)
    
    if not diff or diff.totalChanges == 0 then
        panel.Title:SetText("No changes")
        panel.Title:SetTextColor(0.5, 0.5, 0.5)
        return
    end
    
    local summaryLines = Timeline:FormatSummary(diff)
    
    panel.Title:SetText(string.format("Changes (%d)", diff.totalChanges))
    panel.Title:SetTextColor(1, 0.82, 0)
    
    local scrollChild = panel.ScrollChild
    if scrollChild then
        if not panel.ScrollLines then
            panel.ScrollLines = {}
        end
        
        local yOffset = 0
        for i, lineData in ipairs(summaryLines) do
            local line = panel.ScrollLines[i]
            if not line then
                line = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                line:SetPoint("TOPLEFT", 2, -yOffset)
                line:SetPoint("RIGHT", -2, 0)
                line:SetJustifyH("LEFT")
                line:SetWordWrap(false)
                panel.ScrollLines[i] = line
            else
                line:SetPoint("TOPLEFT", 2, -yOffset)
            end
            
            line:SetText(lineData.text)
            line:SetTextColor(lineData.color[1], lineData.color[2], lineData.color[3])
            line:Show()
            yOffset = yOffset + 12
        end
        
        for i = #summaryLines + 1, #panel.ScrollLines do
            panel.ScrollLines[i]:Hide()
        end
        
        scrollChild:SetHeight(math.max(yOffset, 1))
    else
        local maxLines = panel.Lines and #panel.Lines or 0
        local showCount = math.min(#summaryLines, maxLines)
        
        for i = 1, showCount do
            local lineData = summaryLines[i]
            panel.Lines[i]:SetText(lineData.text)
            panel.Lines[i]:SetTextColor(lineData.color[1], lineData.color[2], lineData.color[3])
            panel.Lines[i]:Show()
        end
        
        if #summaryLines > maxLines and panel.OverflowText then
            panel.OverflowText:SetText(string.format("... and %d more", #summaryLines - maxLines))
            panel.OverflowText:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- Clipboard Operations
--------------------------------------------------------------------------------

function Explorer:OnCopyClick()
    if not selectedLevel or not Clipboard then return end
    
    local specIndex = self:GetViewedSpec()
    local ok, err = Clipboard:Copy(selectedLevel, specIndex)
    
    if ok then
        Utils:Print(string.format("Level %d: Layout copied to clipboard", selectedLevel))
    else
        Utils:PrintError("Copy failed: " .. (err or "unknown"))
    end
    
    self:RefreshToolbar()
end

function Explorer:OnPasteClick()
    if not selectedLevel or not Clipboard or not Clipboard:HasContent() then return end
    
    local specIndex = self:GetViewedSpec()
    local ok, err = Clipboard:Paste(selectedLevel, specIndex, true)
    
    if ok then
        local info = Clipboard:GetInfo()
        Utils:Print(string.format("Level %d: Pasted from level %d (rank-adjusted)",
            selectedLevel, info and info.sourceLevel or 0))
    else
        Utils:PrintError("Paste failed: " .. (err or "unknown"))
    end
    
    self:Refresh()
end

function Explorer:OnPushClick(direction)
    if not selectedLevel or not Clipboard then return end
    
    local specIndex = self:GetViewedSpec()
    local sourceLayout = Layout:Get(selectedLevel, specIndex)
    
    if not sourceLayout then
        Utils:PrintError("No layout at selected level to push")
        return
    end
    
    local frame = UI.ExplorerFrame
    local overwrite = false
    if frame and frame.Toolbar and frame.Toolbar.OverwriteCheckbox then
        overwrite = frame.Toolbar.OverwriteCheckbox:GetChecked() == true
            or frame.Toolbar.OverwriteCheckbox:GetChecked() == 1
    end
    
    local count = Clipboard:PushToTargets(
        sourceLayout, selectedLevel, direction, nil, specIndex, overwrite)
    
    local dirLabel = (direction == "up") and "up" or "down"
    local modeLabel = overwrite and " (overwrite)" or ""
    if count > 0 then
        Utils:Print(string.format("Pushed %s from level %d to %d level(s)%s",
            dirLabel, selectedLevel, count, modeLabel))
    else
        Utils:Print("No levels affected by push")
    end
    
    self:Refresh()
end

function Explorer:OnUndoClick()
    if not Clipboard or not Clipboard:CanUndo() then return end
    
    local ok, description, level = Clipboard:Undo()
    
    if ok then
        Utils:Print(string.format("Undone: %s", description or "last change"))
        if level then
            selectedLevel = level
        end
    else
        Utils:PrintError("Undo failed: " .. (description or "unknown"))
    end
    
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Template Operations
--------------------------------------------------------------------------------

function Explorer:OnSaveTemplateClick()
    if not selectedLevel or not Template then return end
    
    local dialog = UI:CreateTemplateNameDialog()
    dialog.Title:SetText("Save as Template")
    dialog.NameEditBox:SetText("")
    
    dialog.OKButton:SetScript("OnClick", function()
        local name = strtrim(dialog.NameEditBox:GetText())
        if name == "" then return end
        
        local specIndex = Explorer:GetViewedSpec()
        local ok, err = Template:SaveFromLevel(name, selectedLevel, specIndex)
        
        if ok then
            Utils:Print(string.format("Template '%s' saved from level %d", name, selectedLevel))
        else
            Utils:PrintError("Save failed: " .. (err or "unknown"))
        end
        
        dialog:Hide()
        Explorer:RefreshToolbar()
    end)
    
    dialog.NameEditBox:SetScript("OnEnterPressed", function()
        dialog.OKButton:Click()
    end)
    
    dialog:Show()
end

function Explorer:OnLoadTemplateClick()
    if not selectedLevel or not Template then return end
    
    local specIndex = self:GetViewedSpec()
    local dialog = UI:CreateTemplateListDialog()
    
    local names = Template:GetNames(specIndex)
    
    for _, row in pairs(dialog.TemplateRows) do
        row:Hide()
    end
    
    dialog.selectedTemplate = nil
    dialog.ApplyButton:Disable()
    dialog.DeleteButton:Disable()
    
    local yOffset = 0
    for i, name in ipairs(names) do
        local row = UI:GetOrCreateTemplateRow(dialog.ScrollChild, i)
        row:SetPoint("TOPLEFT", 0, -yOffset)
        row.Text:SetText(name)
        row.templateName = name
        row.SelectedTexture:Hide()
        
        row:SetScript("OnClick", function(self)
            dialog.selectedTemplate = self.templateName
            dialog.ApplyButton:Enable()
            dialog.DeleteButton:Enable()
            
            for _, r in pairs(dialog.TemplateRows) do
                if r.SelectedTexture then r.SelectedTexture:Hide() end
            end
            self.SelectedTexture:Show()
        end)
        
        row:Show()
        yOffset = yOffset + 20
    end
    
    dialog.ScrollChild:SetHeight(math.max(yOffset, 1))
    
    dialog.ApplyButton:SetScript("OnClick", function()
        if not dialog.selectedTemplate then return end
        
        local ok, err = Template:ApplyToLevel(
            dialog.selectedTemplate, selectedLevel, specIndex, true)
        
        if ok then
            Utils:Print(string.format("Template '%s' applied to level %d",
                dialog.selectedTemplate, selectedLevel))
        else
            Utils:PrintError("Apply failed: " .. (err or "unknown"))
        end
        
        dialog:Hide()
        Explorer:Refresh()
    end)
    
    dialog.DeleteButton:SetScript("OnClick", function()
        if not dialog.selectedTemplate then return end
        
        Template:Delete(dialog.selectedTemplate, specIndex)
        Utils:Print(string.format("Template '%s' deleted", dialog.selectedTemplate))
        
        dialog:Hide()
        Explorer:OnLoadTemplateClick()
    end)
    
    dialog:Show()
end

--------------------------------------------------------------------------------
-- Import/Export Operations
--------------------------------------------------------------------------------

function Explorer:OnImportExportClick()
    local dialog = UI:CreateImportExportDialog()
    
    dialog.Title:SetText("Import / Export")
    dialog.ExportButton:Show()
    dialog.ImportButton:Show()
    dialog.EditBox:SetText("")
    dialog.StatusText:SetText("")
    
    dialog.ExportButton:SetScript("OnClick", function()
        if not selectedLevel then
            dialog.StatusText:SetText("Select a level first")
            return
        end
        
        local specIndex = Explorer:GetViewedSpec()
        
        local exportStr, err
        if Keyframe and Keyframe:GetCount(specIndex) > 0 then
            exportStr, err = ImportExport:ExportKeyframes(specIndex)
            if exportStr then
                dialog.StatusText:SetText("Exported all keyframes — select all and copy")
            end
        else
            exportStr, err = ImportExport:ExportLayout(selectedLevel, specIndex)
            if exportStr then
                dialog.StatusText:SetText("Exported level " .. selectedLevel .. " — select all and copy")
            end
        end
        
        if exportStr then
            dialog.EditBox:SetText(exportStr)
            dialog.EditBox:HighlightText()
            dialog.EditBox:SetFocus()
        else
            dialog.StatusText:SetText("Export failed: " .. (err or "unknown"))
        end
    end)
    
    dialog.ImportButton:SetScript("OnClick", function()
        local text = dialog.EditBox:GetText()
        if not text or strtrim(text) == "" then
            dialog.StatusText:SetText("Paste an import string first")
            return
        end
        
        local result, err = ImportExport:Import(text)
        if not result then
            dialog.StatusText:SetText("Import failed: " .. (err or "unknown"))
            return
        end
        
        if not result.classMatch then
            dialog.StatusText:SetText("Warning: Different class! Applying anyway...")
        end
        
        local specIndex = Explorer:GetViewedSpec()
        local ok, importType, detail = ImportExport:Apply(result, specIndex)
        
        if ok then
            local msg
            if importType == "layout" then
                msg = "Imported layout at level " .. tostring(detail)
            elseif importType == "keyframes" then
                msg = "Imported " .. tostring(detail) .. " keyframe(s)"
            elseif importType == "template" then
                msg = "Imported template: " .. tostring(detail)
            else
                msg = "Import complete"
            end
            dialog.StatusText:SetText(msg)
            Utils:Print(msg)
            Explorer:Refresh()
        else
            dialog.StatusText:SetText("Apply failed: " .. tostring(importType))
        end
    end)
    
    dialog:Show()
end

--------------------------------------------------------------------------------
-- Backup (Clean Export)
--------------------------------------------------------------------------------

function Explorer:OnBackupClick()
    local dialog = UI:CreateImportExportDialog()
    
    local specIndex = self:GetViewedSpec()
    local exportStr, err = ImportExport:ExportFull(specIndex)
    
    if exportStr then
        local levelCount = Layout:GetCount(specIndex)
        local specName = Profile:GetSpecName(specIndex)
        local kfCount = Keyframe and Keyframe:GetCount(specIndex) or 0
        local summary = string.format("Backup: %d levels", levelCount)
        if kfCount > 0 then
            summary = summary .. string.format(", %d breakpoints", kfCount)
        end
        summary = summary .. string.format(" (%s)", specName)
        dialog.Title:SetText("Backup")
        dialog.StatusText:SetText(summary .. " — select all and copy")
        dialog.EditBox:SetText(exportStr)
        dialog.EditBox:HighlightText()
        dialog.EditBox:SetFocus()
    else
        dialog.Title:SetText("Backup")
        dialog.StatusText:SetText("Backup failed: " .. (err or "unknown"))
        dialog.EditBox:SetText("")
    end
    
    dialog.ExportButton:Hide()
    dialog.ImportButton:Hide()
    
    dialog:Show()
end

--------------------------------------------------------------------------------
-- Restore (Import Backup with Preview)
--------------------------------------------------------------------------------

function Explorer:OnRestoreClick()
    local dialog = UI:CreateRestoreDialog()
    
    dialog.EditBox:SetText("")
    dialog.StatusText:SetText("")
    dialog.PreviewText:SetText("Paste a backup string and click Preview to see contents.")
    dialog.PreviewText:SetTextColor(0.6, 0.6, 0.6)
    dialog.RestoreButton:Disable()
    
    dialog.parsedResult = nil
    
    dialog.PreviewButton:SetScript("OnClick", function()
        local text = dialog.EditBox:GetText()
        if not text or strtrim(text) == "" then
            dialog.StatusText:SetText("Paste a backup string first")
            dialog.PreviewText:SetText("Paste a backup string and click Preview to see contents.")
            dialog.PreviewText:SetTextColor(0.6, 0.6, 0.6)
            dialog.RestoreButton:Disable()
            dialog.parsedResult = nil
            return
        end
        
        local summary, parsed = ImportExport:Preview(text)
        if not summary then
            dialog.StatusText:SetText(parsed or "Failed to parse backup")
            dialog.PreviewText:SetText("Could not read backup data.")
            dialog.PreviewText:SetTextColor(1, 0.3, 0.3)
            dialog.RestoreButton:Disable()
            dialog.parsedResult = nil
            return
        end
        
        local previewLines = table.concat(summary.lines, "\n")
        dialog.PreviewText:SetText(previewLines)
        dialog.PreviewText:SetTextColor(0.9, 0.9, 0.9)
        dialog.StatusText:SetText("")
        
        dialog.parsedResult = parsed
        dialog.RestoreButton:Enable()
    end)
    
    dialog.RestoreButton:SetScript("OnClick", function()
        if not dialog.parsedResult then return end
        
        local specIndex = Explorer:GetViewedSpec()
        local ok, importType, detail = ImportExport:Apply(dialog.parsedResult, specIndex)
        
        if ok then
            local msg
            if importType == "full" then
                msg = "Restored " .. tostring(detail) .. " level(s) from backup"
            elseif importType == "keyframes" then
                msg = "Restored " .. tostring(detail) .. " breakpoint(s)"
            elseif importType == "layout" then
                msg = "Restored layout at level " .. tostring(detail)
            elseif importType == "template" then
                msg = "Restored template: " .. tostring(detail)
            else
                msg = "Restore complete"
            end
            Utils:PrintSuccess(msg)
            dialog:Hide()
            Explorer:Refresh()
        else
            dialog.StatusText:SetText("Restore failed: " .. tostring(importType))
        end
    end)
    
    dialog:Show()
end

--------------------------------------------------------------------------------
-- Full Refresh
--------------------------------------------------------------------------------

function Explorer:Refresh()
    if not UI.ExplorerFrame then return end
    
    self:RefreshTitleBar()
    self:RefreshModeSelector()
    self:RefreshSpecDropdown()
    self:RefreshSwitchButton()
    self:RefreshLevelList()
    self:BuildMapping()
    self:RefreshSlotGrid()
    self:RefreshBarLabels()
    self:RefreshBarToggles()
    self:RefreshEditControls()
    self:RefreshToolbar()
    self:RefreshChangeSummary()
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:SetScript("OnEvent", function(self, event, slot)
    if not Explorer:IsVisible() then return end
    if not Explorer:IsViewingActiveSpec() then return end

    if event == "PLAYER_LEVEL_UP" then
        C_Timer.After(Settings.RESTORE_DELAY, function()
            if Explorer:IsVisible() then
                Explorer:Refresh()
            end
        end)
        return
    end
    
    local currentLevel = Utils:GetPlayerLevel()
    if selectedLevel == currentLevel then
        if event == "UPDATE_BONUS_ACTIONBAR" then
            Explorer:BuildMapping()
            Explorer:RefreshBarLabels()
            Explorer:RefreshBarToggles()
        end
        Explorer:RefreshSlotGrid()
    end
end)