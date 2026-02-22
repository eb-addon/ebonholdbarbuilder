--[[----------------------------------------------------------------------------
    Template system for named layout presets.
    Templates are saved per-spec in SavedVariables and can be applied to any
    level with automatic spell rank adjustment.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Template = {}

local Template = EBB.Template
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile

--------------------------------------------------------------------------------
-- Storage Access
--------------------------------------------------------------------------------

local function GetTemplateTable(specIndex)
    specIndex = specIndex or Profile:GetActive()
    local spec = EBB_CharDB.specs[specIndex]
    if not spec then return nil end

    if not spec.templates then
        spec.templates = {}
    end

    return spec.templates
end

--------------------------------------------------------------------------------
-- Template CRUD
--------------------------------------------------------------------------------

function Template:SaveFromLevel(name, level, specIndex, description)
    if not name or name == "" then
        return false, "Template name required"
    end

    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout

    local layout = Layout:Get(level, specIndex)
    if not layout then
        return false, "No layout at level " .. level
    end

    local templates = GetTemplateTable(specIndex)
    if not templates then
        return false, "Invalid spec"
    end

    templates[name] = {
        slots = Utils:DeepCopy(layout.slots),
        configuredSlots = layout.configuredSlots or 0,
        description = description or "",
        createdAt = Utils:GetTimestamp(),
        sourceLevel = level,
    }

    return true
end

function Template:SaveFromSnapshot(name, snapshot, specIndex, description)
    if not name or name == "" then
        return false, "Template name required"
    end
    if not snapshot or not snapshot.slots then
        return false, "Invalid snapshot"
    end

    specIndex = specIndex or Profile:GetActive()
    local templates = GetTemplateTable(specIndex)
    if not templates then
        return false, "Invalid spec"
    end

    templates[name] = {
        slots = Utils:DeepCopy(snapshot.slots),
        configuredSlots = snapshot.configuredSlots or 0,
        description = description or "",
        createdAt = Utils:GetTimestamp(),
    }

    return true
end

function Template:Get(name, specIndex)
    specIndex = specIndex or Profile:GetActive()
    local templates = GetTemplateTable(specIndex)
    if not templates then return nil end
    return templates[name]
end

function Template:Delete(name, specIndex)
    specIndex = specIndex or Profile:GetActive()
    local templates = GetTemplateTable(specIndex)
    if not templates then return false end

    if not templates[name] then
        return false, "Template not found"
    end

    templates[name] = nil
    return true
end

--- Rename a template.
function Template:Rename(oldName, newName, specIndex)
    if not newName or newName == "" then
        return false, "New name required"
    end

    specIndex = specIndex or Profile:GetActive()
    local templates = GetTemplateTable(specIndex)
    if not templates then return false end

    if not templates[oldName] then
        return false, "Template not found"
    end
    if templates[newName] then
        return false, "Name already in use"
    end

    templates[newName] = templates[oldName]
    templates[oldName] = nil
    return true
end

--- Check if a template exists.
function Template:Exists(name, specIndex)
    specIndex = specIndex or Profile:GetActive()
    local templates = GetTemplateTable(specIndex)
    return templates and templates[name] ~= nil
end

--------------------------------------------------------------------------------
-- Template Listing
--------------------------------------------------------------------------------

--- Get all template names sorted alphabetically.
function Template:GetNames(specIndex)
    specIndex = specIndex or Profile:GetActive()
    local templates = GetTemplateTable(specIndex)
    if not templates then return {} end

    local names = {}
    for name in pairs(templates) do
        table.insert(names, name)
    end

    table.sort(names)
    return names
end

--- Get template count.
function Template:GetCount(specIndex)
    specIndex = specIndex or Profile:GetActive()
    local templates = GetTemplateTable(specIndex)
    if not templates then return 0 end

    local count = 0
    for _ in pairs(templates) do
        count = count + 1
    end
    return count
end

--- Get all templates as a list with metadata.
function Template:GetAll(specIndex)
    specIndex = specIndex or Profile:GetActive()
    local templates = GetTemplateTable(specIndex)
    if not templates then return {} end

    local result = {}
    for name, data in pairs(templates) do
        table.insert(result, {
            name = name,
            description = data.description or "",
            configuredSlots = data.configuredSlots or 0,
            createdAt = data.createdAt or "",
            sourceLevel = data.sourceLevel,
        })
    end

    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

--------------------------------------------------------------------------------
-- Template Application
--------------------------------------------------------------------------------

--- Apply a template to a target level, with optional smart rank adjustment.
function Template:ApplyToLevel(name, targetLevel, specIndex, smartAdjust)
    specIndex = specIndex or Profile:GetActive()
    smartAdjust = (smartAdjust ~= false)

    local tmpl = self:Get(name, specIndex)
    if not tmpl then
        return false, "Template not found"
    end

    local Layout = EBB.Layout
    local Clipboard = EBB.Clipboard
    local Keyframe = EBB.Keyframe

    -- Push undo
    if Clipboard then
        Clipboard:PushUndo(targetLevel, specIndex, "Apply template '" .. name .. "'")
    end

    local layout = {
        timestamp = Utils:GetTimestamp(),
        playerLevel = targetLevel,
        slots = Utils:DeepCopy(tmpl.slots),
        configuredSlots = tmpl.configuredSlots,
    }

    -- Smart rank adjustment
    if smartAdjust and Keyframe then
        layout = Keyframe:DeriveLayout(layout, targetLevel)
        layout.isDerived = nil  -- it's being saved explicitly
    end

    layout.playerLevel = targetLevel
    layout.timestamp = Utils:GetTimestamp()

    Layout:Save(targetLevel, layout, specIndex)
    return true
end

--- Copy a template to a different spec.
function Template:CopyToSpec(name, fromSpec, toSpec)
    local tmpl = self:Get(name, fromSpec)
    if not tmpl then
        return false, "Template not found"
    end

    local destTemplates = GetTemplateTable(toSpec)
    if not destTemplates then
        return false, "Invalid target spec"
    end

    destTemplates[name] = Utils:DeepCopy(tmpl)
    return true
end
