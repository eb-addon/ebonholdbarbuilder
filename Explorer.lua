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
    self:Refresh()
end

function Explorer:OnActiveSpecChanged(newSpecIndex)
    if editingLevel then
        editingLevel = nil
        pendingChanges = {}
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
    local levels = Layout:GetSavedLevels(specIndex)
    local currentLevel = Utils:GetPlayerLevel()
    
    for _, button in pairs(frame.LevelButtons) do
        button:Hide()
    end
    
    if not selectedLevel or not Layout:Has(selectedLevel, specIndex) then
        if Layout:Has(currentLevel, specIndex) then
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
        button.Text:SetText("Level " .. level)
        button.level = level
        
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
end

function Explorer:OnLevelSelected(level)
    self:DoLevelSelect(level)
end

function Explorer:DoLevelSelect(level)
    selectedLevel = level
    self:RefreshSpecDropdown()
    self:RefreshSwitchButton()
    self:RefreshLevelList()
    self:BuildMapping()
    self:RefreshSlotGrid()
    self:RefreshBarLabels()
    self:RefreshBarToggles()
    self:RefreshEditControls()
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
                
                button.slotInfo = slotInfo
                button.dataSlot = dataSlot
            end
        end
    end
end

function Explorer:OnSlotClick(button, mouseButton)
    if not button.dataSlot then return end
    
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
        if canEdit and dataSlot then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Left-click to assign", 0.7, 0.7, 0.7)
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
    
    local mapping   = self:GetCurrentMapping()
    local specIndex = self:GetViewedSpec()
    
    for displayRow = 1, Settings.TOTAL_BARS do
        local toggle  = frame.BarToggles[displayRow]
        local rowInfo = mapping[displayRow]
        local dataBar = rowInfo and rowInfo.dataBar
        
        if not dataBar then
            toggle:SetChecked(false)
            toggle.MixedTexture:Hide()
            toggle.state = "unchecked"
        else
            local fullyEnabled     = Profile:IsBarFullyEnabled(dataBar, specIndex)
            local partiallyEnabled = Profile:IsBarPartiallyEnabled(dataBar, specIndex)
            
            if fullyEnabled then
                toggle:SetChecked(true)
                toggle.MixedTexture:Hide()
                toggle.state = "checked"
            elseif partiallyEnabled then
                toggle:SetChecked(false)
                toggle.MixedTexture:Show()
                toggle.state = "mixed"
            else
                toggle:SetChecked(false)
                toggle.MixedTexture:Hide()
                toggle.state = "unchecked"
            end
        end
    end
end

function Explorer:OnBarToggleClick(displayRow)
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local mapping = self:GetCurrentMapping()
    local rowInfo = mapping[displayRow]
    if not rowInfo or not rowInfo.dataBar then return end
    
    local dataBar  = rowInfo.dataBar
    local specIndex = self:GetViewedSpec()
    
    local newEnabled = not Profile:IsBarFullyEnabled(dataBar, specIndex)
    Profile:SetBarEnabled(dataBar, newEnabled, specIndex)
    
    self:RefreshBarToggles()
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
end

function Explorer:RevertEdits()
    pendingChanges = {}
    editingLevel = nil
    
    if SlotEditor:IsOpen() then
        SlotEditor:Close()
    end
    
    self:RefreshSlotGrid()
    self:RefreshEditControls()
    self:RefreshSwitchButton()
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
-- Full Refresh
--------------------------------------------------------------------------------

function Explorer:Refresh()
    if not UI.ExplorerFrame then return end
    
    self:RefreshSpecDropdown()
    self:RefreshSwitchButton()
    self:RefreshLevelList()
    self:BuildMapping()
    self:RefreshSlotGrid()
    self:RefreshBarLabels()
    self:RefreshBarToggles()
    self:RefreshEditControls()
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