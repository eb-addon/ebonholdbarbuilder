--[[----------------------------------------------------------------------------
    Behavior and data population for the Slot Editor picker.
    Manages category browsing, filtering, selection, and slot info conversion.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.SlotEditor = {}

local SlotEditor = EBB.SlotEditor
local UI = EBB.UI
local Utils = EBB.Utils
local Settings = EBB.Settings
local SpellCache = EBB.SpellCache

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local CATEGORY_ORDER = {
    "Spells", "Macros", "Items", "Mounts", "Pets", "Equipment Sets",
}

local MAX_ACCOUNT_MACROS = 36

local BAG_INVENTORY_SLOTS = { [1] = 20, [2] = 21, [3] = 22, [4] = 23 }

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local targetSlot = nil
local targetLevel = nil
local onApplyCallback = nil
local selectedItem = nil
local openCategory = nil
local openSubGroups = {}
local categories = {}
local categoryGroupOrder = {}
local highestRankOnly = false

--------------------------------------------------------------------------------
-- Highest Rank Toggle
--------------------------------------------------------------------------------

function SlotEditor:IsHighestRankOnly()
    return highestRankOnly
end

function SlotEditor:SetHighestRankOnly(enabled)
    highestRankOnly = enabled
    selectedItem = nil
    local frame = UI.PickerFrame
    if frame then
        frame.AddButton:Disable()
        frame.StatusText:SetText("")
    end
    self:PopulateCategories()
    self:RefreshList()
end

local function ParseRankNumber(rank)
    if not rank or rank == "" then return 0 end
    local num = rank:match("Rank (%d+)")
    return tonumber(num) or 0
end

local function FilterHighestRanks(items, level)
    local byName = {}
    local order = {}
    for _, item in ipairs(items) do
        if not byName[item.name] then
            byName[item.name] = {}
            table.insert(order, item.name)
        end
        table.insert(byName[item.name], item)
    end

    local result = {}
    for _, name in ipairs(order) do
        local ranks = byName[name]
        if #ranks <= 1 then
            result[#result + 1] = ranks[1]
        else
            local bestAvailable = nil
            local bestUnavailable = nil
            for _, item in ipairs(ranks) do
                local rn = ParseRankNumber(item.rank)
                if item.availability == "available" then
                    if not bestAvailable or rn > ParseRankNumber(bestAvailable.rank) then
                        bestAvailable = item
                    end
                else
                    if not bestUnavailable or rn > ParseRankNumber(bestUnavailable.rank) then
                        bestUnavailable = item
                    end
                end
            end
            if bestAvailable then
                result[#result + 1] = bestAvailable
            end
            if bestUnavailable then
                local availRank = bestAvailable and ParseRankNumber(bestAvailable.rank) or -1
                if ParseRankNumber(bestUnavailable.rank) > availRank then
                    result[#result + 1] = bestUnavailable
                end
            end
            if not bestAvailable and not bestUnavailable then
                for _, item in ipairs(ranks) do
                    result[#result + 1] = item
                end
            end
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Show / Hide
--------------------------------------------------------------------------------

function SlotEditor:Open(dataSlot, level, callback)
    targetSlot = dataSlot
    targetLevel = level
    onApplyCallback = callback
    selectedItem = nil
    openCategory = nil
    openSubGroups = {}
    categoryGroupOrder = {}

    self:PopulateCategories()

    local frame = UI:CreatePickerFrame()
    self:Initialize()
    frame.FilterBox:SetText("")
    frame.AddButton:Disable()
    frame.StatusText:SetText("")
    if frame.HighestRankCheck then
        frame.HighestRankCheck:SetChecked(highestRankOnly)
    end
    frame:Show()

    self:RefreshList()
end

function SlotEditor:Close()
    if UI.PickerFrame then
        UI.PickerFrame:Hide()
    end
    targetSlot = nil
    onApplyCallback = nil
    selectedItem = nil
end

function SlotEditor:IsOpen()
    return UI.PickerFrame and UI.PickerFrame:IsShown()
end

function SlotEditor:GetTargetSlot()
    return targetSlot
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local isInitialized = false

function SlotEditor:Initialize()
    if isInitialized then return end
    isInitialized = true

    local frame = UI.PickerFrame

    frame.FilterBox:SetScript("OnTextChanged", function()
        selectedItem = nil
        frame.AddButton:Disable()
        frame.StatusText:SetText("")
        SlotEditor:RefreshList()
    end)

    frame.FilterBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    frame.AddButton:SetScript("OnClick", function()
        SlotEditor:OnAddClick()
    end)

    frame.CloseButton:SetScript("OnClick", function()
        SlotEditor:Close()
    end)

    if frame.HighestRankCheck then
        frame.HighestRankCheck:SetScript("OnClick", function(self)
            SlotEditor:SetHighestRankOnly(self:GetChecked())
        end)
    end
end

--------------------------------------------------------------------------------
-- Category Population
--------------------------------------------------------------------------------

function SlotEditor:PopulateCategories()
    categories = {}
    categoryGroupOrder = {}

    categories["Spells"] = self:GetSpellItems()
    categories["Macros"] = self:GetMacroItems()
    categories["Items"] = self:GetBagItems()
    categories["Mounts"] = self:GetCompanionItems("MOUNT")
    categories["Pets"] = self:GetCompanionItems("CRITTER")
    categories["Equipment Sets"] = self:GetEquipmentSetItems()
end

--------------------------------------------------------------------------------
-- Bag Name Helper
--------------------------------------------------------------------------------

local function GetBagDisplayName(bag)
    if bag == 0 then return "Backpack" end
    local invSlot = BAG_INVENTORY_SLOTS[bag]
    if invSlot then
        local link = GetInventoryItemLink("player", invSlot)
        if link then
            local name = GetItemInfo(link)
            if name then return name end
        end
    end
    return "Bag " .. bag
end

--------------------------------------------------------------------------------
-- Spells (grouped by spellbook tab)
--------------------------------------------------------------------------------

function SlotEditor:GetSpellItems()
    local items = {}
    local currentLevel = Utils:GetPlayerLevel()
    local isCurrentLevel = (targetLevel == currentLevel)
    local numTabs = GetNumSpellTabs()
    local groupOrder = {}

    --------------------------------------------------------------------
    -- Current level: just show the spellbook as-is
    --------------------------------------------------------------------
    if isCurrentLevel or not targetLevel then
        for tabIndex = 1, numTabs do
            local tabName, _, offset, numSpells = GetSpellTabInfo(tabIndex)
            table.insert(groupOrder, tabName)

            for spellIndex = offset + 1, offset + numSpells do
                if not IsPassiveSpell(spellIndex, BOOKTYPE_SPELL) then
                    local spellName, spellRank = GetSpellName(spellIndex, BOOKTYPE_SPELL)
                    if spellName then
                        local icon = GetSpellTexture(spellIndex, BOOKTYPE_SPELL)
                        local displayName = spellName
                        if spellRank and spellRank ~= "" then
                            displayName = spellName .. " (" .. spellRank .. ")"
                        end

                        table.insert(items, {
                            type = "spell",
                            name = spellName,
                            rank = spellRank or "",
                            displayName = displayName,
                            icon = icon,
                            spellbookIndex = spellIndex,
                            availability = "available",
                            availabilityText = nil,
                            group = tabName,
                        })
                    end
                end
            end
        end

        categoryGroupOrder["Spells"] = groupOrder
        table.sort(items, function(a, b) return a.displayName < b.displayName end)
        if highestRankOnly then
            items = FilterHighestRanks(items, targetLevel)
        end
        return items
    end

    --------------------------------------------------------------------
    -- Non-current level: combine spellbook + cache, split by
    -- availability at target level
    --------------------------------------------------------------------

    local spellbookTabs = {}
    for tabIndex = 1, numTabs do
        local tabName = GetSpellTabInfo(tabIndex)
        spellbookTabs[tabName] = true
        table.insert(groupOrder, tabName)
    end

    local added = {}

    local notYetLearnedTabs = {}
    local notYetLearnedTabOrder = {}

    for tabIndex = 1, numTabs do
        local tabName, _, offset, numSpells = GetSpellTabInfo(tabIndex)

        for spellIndex = offset + 1, offset + numSpells do
            if not IsPassiveSpell(spellIndex, BOOKTYPE_SPELL) then
                local spellName, spellRank = GetSpellName(spellIndex, BOOKTYPE_SPELL)
                if spellName then
                    local icon = GetSpellTexture(spellIndex, BOOKTYPE_SPELL)
                    local rank = spellRank or ""
                    local key = spellName .. "\0" .. rank
                    added[key] = true

                    local displayName = spellName
                    if spellRank and spellRank ~= "" then
                        displayName = spellName .. " (" .. spellRank .. ")"
                    end

                    local cachedAvail = SpellCache:IsAvailableAtLevel(
                        spellName, rank, targetLevel)

                    if cachedAvail == false then
                        local learnLevel = SpellCache:GetSpellLevel(spellName, rank)
                        local source = SpellCache:GetSpellSource(spellName, rank)
                        local levelPrefix = (source == "trainer")
                            and "Learned at level "
                            or "First seen at level "
                        if not notYetLearnedTabs[tabName] then
                            notYetLearnedTabs[tabName] = true
                            table.insert(notYetLearnedTabOrder, tabName)
                        end
                        table.insert(items, {
                            type = "spell",
                            name = spellName,
                            rank = rank,
                            displayName = displayName,
                            icon = icon,
                            spellbookIndex = spellIndex,
                            availability = "unavailable",
                            availabilityText = levelPrefix
                                .. (learnLevel or "?"),
                            group = tabName .. " (Not Yet Learned)",
                        })
                    else
                        table.insert(items, {
                            type = "spell",
                            name = spellName,
                            rank = rank,
                            displayName = displayName,
                            icon = icon,
                            spellbookIndex = spellIndex,
                            availability = "available",
                            availabilityText = nil,
                            group = tabName,
                        })
                    end
                end
            end
        end
    end

    if SpellCache then
        local allCached = SpellCache:GetSpellsForLevel(Settings.MAX_LEVEL)

        for _, cached in ipairs(allCached) do
            local key = cached.name .. "\0" .. cached.rank
            if not added[key] then
                added[key] = true

                local displayName = cached.name
                if cached.rank and cached.rank ~= "" then
                    displayName = cached.name .. " (" .. cached.rank .. ")"
                end

                local icon = cached.icon

                local tabName = cached.tab or "Unknown"

                if cached.learnLevel <= targetLevel then
                    if not spellbookTabs[tabName] then
                        spellbookTabs[tabName] = true
                        table.insert(groupOrder, tabName)
                    end
                    table.insert(items, {
                        type = "spell",
                        name = cached.name,
                        rank = cached.rank,
                        displayName = displayName,
                        icon = icon,
                        spellbookIndex = nil,
                        availability = "available",
                        availabilityText = nil,
                        group = tabName,
                    })
                else
                    local levelPrefix = (cached.source == "trainer")
                        and "Learned at level "
                        or "First seen at level "
                    if not notYetLearnedTabs[tabName] then
                        notYetLearnedTabs[tabName] = true
                        table.insert(notYetLearnedTabOrder, tabName)
                    end
                    table.insert(items, {
                        type = "spell",
                        name = cached.name,
                        rank = cached.rank,
                        displayName = displayName,
                        icon = icon,
                        spellbookIndex = nil,
                        availability = "unavailable",
                        availabilityText = levelPrefix
                            .. cached.learnLevel,
                        group = tabName .. " (Not Yet Learned)",
                    })
                end
            end
        end
    end

    if #notYetLearnedTabOrder > 0 then
        table.insert(groupOrder, "__section:Not Yet Learned")
        for _, tabName in ipairs(notYetLearnedTabOrder) do
            table.insert(groupOrder, tabName .. " (Not Yet Learned)")
        end
    end

    categoryGroupOrder["Spells"] = groupOrder
    table.sort(items, function(a, b) return a.displayName < b.displayName end)
    if highestRankOnly then
        items = FilterHighestRanks(items, targetLevel)
    end
    return items
end

--------------------------------------------------------------------------------
-- Macros
--------------------------------------------------------------------------------

function SlotEditor:GetMacroItems()
    local items = {}
    local numGlobal, numChar = GetNumMacros()

    local function AddMacro(index)
        local name, icon, body = GetMacroInfo(index)
        if name then
            table.insert(items, {
                type = "macro",
                name = name,
                displayName = name,
                icon = icon,
                id = index,
                body = body,
                availability = "available",
            })
        end
    end

    for i = 1, numGlobal or 0 do
        AddMacro(i)
    end
    for i = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + (numChar or 0) do
        AddMacro(i)
    end

    table.sort(items, function(a, b) return a.displayName < b.displayName end)
    return items
end

--------------------------------------------------------------------------------
-- Bag / Equipped Items (grouped by bag name)
--------------------------------------------------------------------------------

function SlotEditor:GetBagItems()
    local items = {}
    local seen = {}
    local groupOrder = {}
    local groupSeen = {}

    for bag = 0, 4 do
        local bagName = GetBagDisplayName(bag)
        local numSlots = GetContainerNumSlots(bag) or 0

        if numSlots > 0 and not groupSeen[bagName] then
            groupSeen[bagName] = true
            table.insert(groupOrder, bagName)
        end

        for bagSlot = 1, numSlots do
            local link = GetContainerItemLink(bag, bagSlot)
            if link then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID and not seen[itemID] then
                    local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                    if itemName then
                        seen[itemID] = true
                        table.insert(items, {
                            type = "item",
                            name = itemName,
                            displayName = itemName,
                            id = itemID,
                            icon = itemTexture,
                            availability = "available",
                            group = bagName,
                        })
                    end
                end
            end
        end
    end

    local hasEquipped = false
    for equipSlot = 1, 19 do
        local link = GetInventoryItemLink("player", equipSlot)
        if link then
            local itemID = tonumber(link:match("item:(%d+)"))
            if itemID and not seen[itemID] then
                local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                if itemName then
                    seen[itemID] = true
                    hasEquipped = true
                    table.insert(items, {
                        type = "item",
                        name = itemName,
                        displayName = itemName,
                        id = itemID,
                        icon = itemTexture,
                        availability = "available",
                        group = "Equipped",
                    })
                end
            end
        end
    end

    if hasEquipped then
        table.insert(groupOrder, "Equipped")
    end

    categoryGroupOrder["Items"] = groupOrder
    table.sort(items, function(a, b) return a.displayName < b.displayName end)
    return items
end

--------------------------------------------------------------------------------
-- Companions (Mounts / Pets)
--------------------------------------------------------------------------------

function SlotEditor:GetCompanionItems(companionType)
    local items = {}
    local numCompanions = GetNumCompanions(companionType) or 0

    for i = 1, numCompanions do
        local creatureID, creatureName, creatureSpellID, icon = GetCompanionInfo(companionType, i)
        if creatureName then
            table.insert(items, {
                type = "companion",
                name = creatureName,
                displayName = creatureName,
                id = i,
                companionType = companionType,
                icon = icon,
                creatureID = creatureID,
                creatureSpellID = creatureSpellID,
                availability = "available",
            })
        end
    end

    table.sort(items, function(a, b) return a.displayName < b.displayName end)
    return items
end

--------------------------------------------------------------------------------
-- Equipment Sets
--------------------------------------------------------------------------------

function SlotEditor:GetEquipmentSetItems()
    local items = {}
    local numSets = GetNumEquipmentSets and GetNumEquipmentSets() or 0

    for i = 1, numSets do
        local name, icon = GetEquipmentSetInfo(i)
        if name then
            table.insert(items, {
                type = "equipmentset",
                name = name,
                displayName = name,
                setName = name,
                id = name,
                icon = icon,
                availability = "available",
            })
        end
    end

    table.sort(items, function(a, b) return a.displayName < b.displayName end)
    return items
end

--------------------------------------------------------------------------------
-- Item -> SlotInfo Conversion
--------------------------------------------------------------------------------

function SlotEditor:ItemToSlotInfo(item, slot)
    if not item then return nil end

    if item.type == "spell" then
        return {
            type = "spell",
            name = item.name,
            rank = item.rank,
            icon = item.icon,
            slot = slot,
        }
    elseif item.type == "item" then
        return {
            type = "item",
            id = item.id,
            name = item.name,
            icon = item.icon,
            slot = slot,
        }
    elseif item.type == "macro" then
        return {
            type = "macro",
            id = item.id,
            name = item.name,
            icon = item.icon,
            body = item.body,
            slot = slot,
        }
    elseif item.type == "companion" then
        return {
            type = "companion",
            id = item.id,
            companionType = item.companionType,
            subType = item.companionType,
            icon = item.icon,
            slot = slot,
        }
    elseif item.type == "equipmentset" then
        return {
            type = "equipmentset",
            setName = item.setName,
            id = item.setName,
            icon = item.icon,
            slot = slot,
        }
    end

    return nil
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

function SlotEditor:OnCategoryClick(categoryName)
    if openCategory == categoryName then
        openCategory = nil
    else
        openCategory = categoryName
    end
    selectedItem = nil

    local frame = UI.PickerFrame
    if frame then
        frame.AddButton:Disable()
        frame.StatusText:SetText("")
    end

    self:RefreshList()
end

function SlotEditor:OnSubGroupClick(categoryName, groupName)
    local subKey = categoryName .. ":" .. groupName
    openSubGroups[subKey] = not openSubGroups[subKey]
    self:RefreshList()
end

function SlotEditor:OnItemClick(item)
    selectedItem = item

    local frame = UI.PickerFrame
    if not frame then return end

    frame.AddButton:Enable()

    if item.availabilityText then
        frame.StatusText:SetText(item.availabilityText)
        if item.availability == "unavailable" then
            frame.StatusText:SetTextColor(1, 0.4, 0.4)
        else
            frame.StatusText:SetTextColor(1, 0.8, 0)
        end
    else
        frame.StatusText:SetText("")
    end

    self:RefreshList()
end

function SlotEditor:OnAddClick()
    if not selectedItem or not onApplyCallback then return end

    local slotInfo = self:ItemToSlotInfo(selectedItem, targetSlot)
    if slotInfo then
        onApplyCallback(slotInfo)
    end

    self:Close()
end

--------------------------------------------------------------------------------
-- Filtering
--------------------------------------------------------------------------------

local function MatchesFilter(item, filterText)
    if not filterText or filterText == "" then
        return true
    end
    return item.displayName:lower():find(filterText, 1, true) ~= nil
end

function SlotEditor:GetFilteredItems(categoryName)
    local items = categories[categoryName]
    if not items then return {} end

    local frame = UI.PickerFrame
    local filterText = frame and frame.FilterBox and frame.FilterBox:GetText() or ""
    filterText = strtrim(filterText):lower()

    if filterText == "" then
        return items
    end

    local filtered = {}
    for _, item in ipairs(items) do
        if MatchesFilter(item, filterText) then
            table.insert(filtered, item)
        end
    end
    return filtered
end

--------------------------------------------------------------------------------
-- Sub-Group Helpers
--------------------------------------------------------------------------------

function SlotEditor:GroupItemsByGroup(items)
    local grouped = {}
    for _, item in ipairs(items) do
        local group = item.group or ""
        if not grouped[group] then
            grouped[group] = {}
        end
        table.insert(grouped[group], item)
    end
    return grouped
end

--------------------------------------------------------------------------------
-- List Refresh
--------------------------------------------------------------------------------

function SlotEditor:RefreshList()
    local frame = UI.PickerFrame
    if not frame then return end

    local scrollChild = frame.ScrollChild
    local pickerLayout = UI:GetPickerLayout()

    for _, row in pairs(frame.Rows) do
        row:Hide()
    end

    local rowIndex = 0
    local yOffset = 0

    local filterText = frame.FilterBox and frame.FilterBox:GetText() or ""
    local hasFilter = (strtrim(filterText) ~= "")

    for _, categoryName in ipairs(CATEGORY_ORDER) do
        local allItems = categories[categoryName] or {}
        local isExpanded = (openCategory == categoryName)
        local filtered = self:GetFilteredItems(categoryName)

        if #allItems > 0 then
            rowIndex = rowIndex + 1
            local headerRow = UI:GetOrCreatePickerRow(scrollChild, rowIndex)
            headerRow:SetPoint("TOPLEFT", 0, -yOffset)

            local filteredCount = hasFilter and #filtered or nil
            UI:SetRowAsHeader(headerRow, categoryName, #allItems,
                              filteredCount, isExpanded)

            headerRow:SetScript("OnClick", function()
                SlotEditor:OnCategoryClick(categoryName)
            end)
            headerRow:Show()
            yOffset = yOffset + pickerLayout.CATEGORY_HEIGHT

            if isExpanded then
                local groupOrder = categoryGroupOrder[categoryName]

                if groupOrder and #groupOrder > 0 then
                    local grouped = self:GroupItemsByGroup(filtered)

                    local sectionCounts = {}
                    local scanSection = nil
                    for _, gn in ipairs(groupOrder) do
                        if gn:find("^__section:") then
                            scanSection = gn
                            sectionCounts[scanSection] = 0
                        elseif scanSection then
                            local gi = grouped[gn]
                            if gi then
                                sectionCounts[scanSection] =
                                    sectionCounts[scanSection] + #gi
                            end
                        end
                    end

                    local inSection = nil
                    local sectionExpanded = false

                    for _, groupName in ipairs(groupOrder) do

                        ------------------------------------------------
                        -- Section header (e.g. "Not Yet Learned")
                        ------------------------------------------------
                        if groupName:find("^__section:") then
                            inSection = groupName
                            local sectionLabel = groupName:sub(11)
                            local sectionCount = sectionCounts[groupName] or 0

                            if sectionCount > 0 then
                                local sKey = categoryName .. ":" .. groupName
                                sectionExpanded = openSubGroups[sKey]

                                rowIndex = rowIndex + 1
                                local secRow = UI:GetOrCreatePickerRow(
                                    scrollChild, rowIndex)
                                secRow:SetPoint("TOPLEFT",
                                    pickerLayout.SECTION_HEADER_INDENT,
                                    -yOffset)
                                secRow:SetPoint("RIGHT", 0, 0)
                                UI:SetRowAsSectionHeader(secRow,
                                    sectionLabel, sectionExpanded)
                                secRow:SetScript("OnClick", function()
                                    SlotEditor:OnSubGroupClick(
                                        categoryName, groupName)
                                end)
                                secRow:Show()
                                yOffset = yOffset
                                    + pickerLayout.SECTION_HEADER_HEIGHT
                            else
                                sectionExpanded = false
                            end

                        ------------------------------------------------
                        -- Nested sub-group (under a section)
                        ------------------------------------------------
                        elseif inSection then
                            if sectionExpanded then
                                local groupItems = grouped[groupName]
                                if groupItems and #groupItems > 0 then
                                    local subKey = categoryName
                                        .. ":" .. groupName
                                    local isSubExpanded =
                                        openSubGroups[subKey]

                                    local displayName =
                                        groupName:gsub(
                                            " %(Not Yet Learned%)$", "")

                                    rowIndex = rowIndex + 1
                                    local subRow = UI:GetOrCreatePickerRow(
                                        scrollChild, rowIndex)
                                    subRow:SetPoint("TOPLEFT",
                                        pickerLayout.NESTED_SUB_HEADER_INDENT,
                                        -yOffset)
                                    subRow:SetPoint("RIGHT", 0, 0)
                                    UI:SetRowAsSubHeader(subRow,
                                        displayName, #groupItems,
                                        isSubExpanded)
                                    subRow:SetScript("OnClick", function()
                                        SlotEditor:OnSubGroupClick(
                                            categoryName, groupName)
                                    end)
                                    subRow:Show()
                                    yOffset = yOffset
                                        + pickerLayout.SUB_HEADER_HEIGHT

                                    if isSubExpanded then
                                        for _, item in ipairs(groupItems) do
                                            rowIndex = rowIndex + 1
                                            local itemRow =
                                                UI:GetOrCreatePickerRow(
                                                    scrollChild, rowIndex)
                                            itemRow:SetPoint("TOPLEFT",
                                                pickerLayout.NESTED_ITEM_INDENT,
                                                -yOffset)
                                            itemRow:SetPoint("RIGHT", 0, 0)
                                            UI:SetRowAsItem(itemRow,
                                                item.icon,
                                                item.displayName,
                                                item.availability)
                                            itemRow.item = item

                                            if selectedItem == item then
                                                itemRow.SelectedTexture:Show()
                                            else
                                                itemRow.SelectedTexture:Hide()
                                            end

                                            itemRow:SetScript("OnClick",
                                                function()
                                                    SlotEditor:OnItemClick(
                                                        item)
                                                end)
                                            itemRow:Show()
                                            yOffset = yOffset
                                                + pickerLayout.ITEM_ROW_HEIGHT
                                        end
                                    end
                                end
                            end

                        ------------------------------------------------
                        -- Normal sub-group (not under a section)
                        ------------------------------------------------
                        else
                            local groupItems = grouped[groupName]
                            if groupItems and #groupItems > 0 then
                                local subKey = categoryName
                                    .. ":" .. groupName
                                local isSubExpanded =
                                    openSubGroups[subKey]

                                rowIndex = rowIndex + 1
                                local subRow = UI:GetOrCreatePickerRow(
                                    scrollChild, rowIndex)
                                subRow:SetPoint("TOPLEFT",
                                    pickerLayout.SUB_HEADER_INDENT,
                                    -yOffset)
                                subRow:SetPoint("RIGHT", 0, 0)
                                UI:SetRowAsSubHeader(subRow, groupName,
                                    #groupItems, isSubExpanded)
                                subRow:SetScript("OnClick", function()
                                    SlotEditor:OnSubGroupClick(
                                        categoryName, groupName)
                                end)
                                subRow:Show()
                                yOffset = yOffset
                                    + pickerLayout.SUB_HEADER_HEIGHT

                                if isSubExpanded then
                                    for _, item in ipairs(groupItems) do
                                        rowIndex = rowIndex + 1
                                        local itemRow =
                                            UI:GetOrCreatePickerRow(
                                                scrollChild, rowIndex)
                                        itemRow:SetPoint("TOPLEFT",
                                            pickerLayout.ITEM_INDENT_GROUPED,
                                            -yOffset)
                                        itemRow:SetPoint("RIGHT", 0, 0)
                                        UI:SetRowAsItem(itemRow, item.icon,
                                            item.displayName,
                                            item.availability)
                                        itemRow.item = item

                                        if selectedItem == item then
                                            itemRow.SelectedTexture:Show()
                                        else
                                            itemRow.SelectedTexture:Hide()
                                        end

                                        itemRow:SetScript("OnClick",
                                            function()
                                                SlotEditor:OnItemClick(item)
                                            end)
                                        itemRow:Show()
                                        yOffset = yOffset
                                            + pickerLayout.ITEM_ROW_HEIGHT
                                    end
                                end
                            end
                        end
                    end
                else
                    for _, item in ipairs(filtered) do
                        rowIndex = rowIndex + 1
                        local itemRow = UI:GetOrCreatePickerRow(
                            scrollChild, rowIndex)
                        itemRow:SetPoint("TOPLEFT",
                            pickerLayout.ITEM_INDENT, -yOffset)
                        itemRow:SetPoint("RIGHT", 0, 0)
                        UI:SetRowAsItem(itemRow, item.icon,
                            item.displayName, item.availability)
                        itemRow.item = item

                        if selectedItem == item then
                            itemRow.SelectedTexture:Show()
                        else
                            itemRow.SelectedTexture:Hide()
                        end

                        itemRow:SetScript("OnClick", function()
                            SlotEditor:OnItemClick(item)
                        end)
                        itemRow:Show()
                        yOffset = yOffset + pickerLayout.ITEM_ROW_HEIGHT
                    end
                end
            end
        end
    end

    scrollChild:SetHeight(math.max(yOffset, 1))
end
