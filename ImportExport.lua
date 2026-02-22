--[[----------------------------------------------------------------------------
    Import/Export system for sharing layouts and keyframe configurations.
    Encodes layout data to shareable strings and decodes them back.
    Uses a simple serialization format with Base64 encoding.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.ImportExport = {}

local ImportExport = EBB.ImportExport
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile

--------------------------------------------------------------------------------
-- Base64 Encoding/Decoding
--------------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function Base64Encode(data)
    return ((data:gsub(".", function(x)
        local r, b = "", x:byte()
        for i = 8, 1, -1 do
            r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0")
        end
        return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then return "" end
        local c = 0
        for i = 1, 6 do
            c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0)
        end
        return B64:sub(c + 1, c + 1)
    end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

local function Base64Decode(data)
    data = data:gsub("[^" .. B64 .. "=]", "")
    return (data:gsub(".", function(x)
        if x == "=" then return "" end
        local r, f = "", (B64:find(x) - 1)
        for i = 6, 1, -1 do
            r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0")
        end
        return r
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
        if #x ~= 8 then return "" end
        local c = 0
        for i = 1, 8 do
            c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0)
        end
        return string.char(c)
    end))
end

--------------------------------------------------------------------------------
-- Simple Serializer (Lua table -> string)
--------------------------------------------------------------------------------

local function SerializeValue(val, depth)
    depth = depth or 0
    if depth > 20 then return "nil" end

    local t = type(val)
    if t == "string" then
        return string.format("%q", val)
    elseif t == "number" then
        return tostring(val)
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "nil" then
        return "nil"
    elseif t == "table" then
        local parts = {}
        local maxn = 0
        for k in pairs(val) do
            if type(k) == "number" and k > maxn then
                maxn = k
            end
        end
        local arrayDone = {}
        for i = 1, maxn do
            table.insert(parts, SerializeValue(val[i], depth + 1))
            arrayDone[i] = true
        end
        for k, v in pairs(val) do
            if not arrayDone[k] then
                local keyStr
                if type(k) == "string" then
                    keyStr = "[" .. string.format("%q", k) .. "]"
                elseif type(k) == "number" then
                    keyStr = "[" .. tostring(k) .. "]"
                else
                    keyStr = "[" .. string.format("%q", tostring(k)) .. "]"
                end
                table.insert(parts, keyStr .. "=" .. SerializeValue(v, depth + 1))
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end

    return "nil"
end

local function DeserializeValue(str)
    if not str or str == "" then return nil end

    local func, err = loadstring("return " .. str)
    if not func then
        return nil, "Parse error: " .. (err or "unknown")
    end

    setfenv(func, {})

    local ok, result = pcall(func)
    if not ok then
        return nil, "Execution error: " .. tostring(result)
    end

    return result
end

--------------------------------------------------------------------------------
-- Export Format
--------------------------------------------------------------------------------

local EXPORT_PREFIX = "EBB:"
local EXPORT_VERSION = 1

--------------------------------------------------------------------------------
-- Export: Single Level Layout
--------------------------------------------------------------------------------

function ImportExport:ExportLayout(level, specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout

    local layout = Layout:Get(level, specIndex)
    if not layout then
        return nil, "No layout at level " .. level
    end

    local _, classFile = UnitClass("player")

    local payload = {
        version = EXPORT_VERSION,
        class = classFile,
        type = "layout",
        data = {
            level = level,
            layout = self:StripLayout(layout),
        },
    }

    local serialized = SerializeValue(payload)
    local encoded = Base64Encode(serialized)

    return EXPORT_PREFIX .. "v" .. EXPORT_VERSION .. ":" .. encoded
end

--------------------------------------------------------------------------------
-- Export: Keyframe Configuration (all keyframes + their layouts)
--------------------------------------------------------------------------------

function ImportExport:ExportKeyframes(specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Keyframe = EBB.Keyframe
    local Layout = EBB.Layout

    if not Keyframe then
        return nil, "Keyframe system not loaded"
    end

    local kfLevels = Keyframe:GetAll(specIndex)
    local _, classFile = UnitClass("player")

    local keyframeData = {}
    for _, level in ipairs(kfLevels) do
        local layout = Layout:Get(level, specIndex)
        if layout then
            table.insert(keyframeData, {
                level = level,
                layout = self:StripLayout(layout),
            })
        end
    end

    local payload = {
        version = EXPORT_VERSION,
        class = classFile,
        type = "keyframes",
        data = {
            keyframes = keyframeData,
        },
    }

    local serialized = SerializeValue(payload)
    local encoded = Base64Encode(serialized)

    return EXPORT_PREFIX .. "v" .. EXPORT_VERSION .. ":" .. encoded
end

--------------------------------------------------------------------------------
-- Export: Full Backup (All Levels for a Spec)
--------------------------------------------------------------------------------

function ImportExport:ExportFull(specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout
    local Keyframe = EBB.Keyframe

    local levels = Layout:GetSavedLevels(specIndex)
    if not levels or #levels == 0 then
        return nil, "No saved levels to export"
    end

    local _, classFile = UnitClass("player")

    local levelData = {}
    local keyframeLevels = {}
    
    for _, level in ipairs(levels) do
        local layout = Layout:Get(level, specIndex)
        if layout then
            table.insert(levelData, {
                level = level,
                layout = self:StripLayout(layout),
            })
        end
        if Keyframe and Keyframe:IsKeyframe(level, specIndex) then
            table.insert(keyframeLevels, level)
        end
    end

    local enabledSlots = {}
    for slot = 1, Settings.TOTAL_SLOTS do
        if not Profile:IsSlotEnabled(slot, specIndex) then
            enabledSlots[slot] = false
        end
    end

    local payload = {
        version = EXPORT_VERSION,
        class = classFile,
        type = "full",
        data = {
            levels = levelData,
            keyframes = keyframeLevels,
            enabledSlots = enabledSlots,
            specName = Profile:GetSpecName(specIndex),
        },
    }

    local serialized = SerializeValue(payload)
    local encoded = Base64Encode(serialized)

    return EXPORT_PREFIX .. "v" .. EXPORT_VERSION .. ":" .. encoded
end

--------------------------------------------------------------------------------
-- Export: Template
--------------------------------------------------------------------------------

function ImportExport:ExportTemplate(name, specIndex)
    specIndex = specIndex or Profile:GetActive()
    local Template = EBB.Template

    if not Template then
        return nil, "Template system not loaded"
    end

    local tmpl = Template:Get(name, specIndex)
    if not tmpl then
        return nil, "Template not found"
    end

    local _, classFile = UnitClass("player")

    local payload = {
        version = EXPORT_VERSION,
        class = classFile,
        type = "template",
        data = {
            name = name,
            template = {
                slots = tmpl.slots,
                configuredSlots = tmpl.configuredSlots,
                description = tmpl.description,
            },
        },
    }

    local serialized = SerializeValue(payload)
    local encoded = Base64Encode(serialized)

    return EXPORT_PREFIX .. "v" .. EXPORT_VERSION .. ":" .. encoded
end

--------------------------------------------------------------------------------
-- Import
--------------------------------------------------------------------------------

function ImportExport:Import(importString)
    if not importString or importString == "" then
        return nil, "Empty import string"
    end

    importString = importString:gsub("%s+", "")

    if not importString:find("^EBB:v%d+:") then
        return nil, "Invalid format: missing EBB prefix"
    end

    local version, encoded = importString:match("^EBB:v(%d+):(.+)$")
    version = tonumber(version)

    if not version or not encoded then
        return nil, "Invalid format: could not parse header"
    end

    if version > EXPORT_VERSION then
        return nil, "Import version " .. version .. " not supported (max: " .. EXPORT_VERSION .. ")"
    end

    local serialized = Base64Decode(encoded)
    if not serialized or serialized == "" then
        return nil, "Failed to decode import data"
    end

    local payload, err = DeserializeValue(serialized)
    if not payload then
        return nil, "Failed to parse import data: " .. (err or "unknown")
    end

    if type(payload) ~= "table" then
        return nil, "Invalid import data structure"
    end

    local _, playerClass = UnitClass("player")
    local classMatch = (not payload.class) or (payload.class == playerClass)

    return {
        version = payload.version,
        type = payload.type,
        class = payload.class,
        classMatch = classMatch,
        data = payload.data,
    }
end

function ImportExport:Apply(importResult, specIndex)
    if not importResult then
        return false, "No import data"
    end

    specIndex = specIndex or Profile:GetActive()
    local Layout = EBB.Layout
    local Keyframe = EBB.Keyframe
    local Template = EBB.Template
    local Clipboard = EBB.Clipboard

    if importResult.type == "layout" then
        local data = importResult.data
        if not data or not data.layout then
            return false, "Invalid layout data"
        end

        local level = data.level or Utils:GetPlayerLevel()

        if Clipboard then
            Clipboard:PushUndo(level, specIndex, "Import layout at level " .. level)
        end

        local layout = self:RestoreLayout(data.layout)
        layout.playerLevel = level
        Layout:Save(level, layout, specIndex)

        return true, "layout", level

    elseif importResult.type == "keyframes" then
        local data = importResult.data
        if not data or not data.keyframes then
            return false, "Invalid keyframe data"
        end

        local count = 0
        for _, kfData in ipairs(data.keyframes) do
            if kfData.level and kfData.layout then
                if Clipboard then
                    Clipboard:PushUndo(kfData.level, specIndex, "Import keyframe at level " .. kfData.level)
                end

                local layout = self:RestoreLayout(kfData.layout)
                layout.playerLevel = kfData.level
                Layout:Save(kfData.level, layout, specIndex)

                if Keyframe then
                    Keyframe:Set(kfData.level, specIndex)
                end

                count = count + 1
            end
        end

        return true, "keyframes", count

    elseif importResult.type == "template" then
        local data = importResult.data
        if not data or not data.template or not data.name then
            return false, "Invalid template data"
        end

        if Template then
            local tmplData = data.template
            local templates = EBB_CharDB.specs[specIndex].templates
            if not templates then
                EBB_CharDB.specs[specIndex].templates = {}
                templates = EBB_CharDB.specs[specIndex].templates
            end
            templates[data.name] = {
                slots = tmplData.slots,
                configuredSlots = tmplData.configuredSlots or 0,
                description = tmplData.description or "",
                createdAt = Utils:GetTimestamp(),
            }
            return true, "template", data.name
        end

        return false, "Template system not available"

    elseif importResult.type == "full" then
        local data = importResult.data
        if not data or not data.levels then
            return false, "Invalid full backup data"
        end

        local count = 0
        for _, lvlData in ipairs(data.levels) do
            if lvlData.level and lvlData.layout then
                if Clipboard then
                    Clipboard:PushUndo(lvlData.level, specIndex, "Full restore level " .. lvlData.level)
                end

                local layout = self:RestoreLayout(lvlData.layout)
                layout.playerLevel = lvlData.level
                Layout:Save(lvlData.level, layout, specIndex)
                count = count + 1
            end
        end

        if data.keyframes and Keyframe then
            Keyframe:ClearAll(specIndex)
            for _, level in ipairs(data.keyframes) do
                Keyframe:Set(level, specIndex)
            end
        end

        if data.enabledSlots then
            local Profile = EBB.Profile
            Profile:SetAllSlotsEnabled(true, specIndex)
            for slot, enabled in pairs(data.enabledSlots) do
                if enabled == false then
                    Profile:SetSlotEnabled(slot, false, specIndex)
                end
            end
        end

        return true, "full", count
    end

    return false, "Unknown import type: " .. tostring(importResult.type)
end

--------------------------------------------------------------------------------
-- Layout Strip/Restore (minimize export size)
--------------------------------------------------------------------------------

function ImportExport:StripLayout(layout)
    if not layout then return nil end

    local stripped = {
        slots = {},
    }

    for slot = 1, Settings.TOTAL_SLOTS do
        local info = layout.slots and layout.slots[slot]
        if info and info.type ~= "empty" then
            local s = { t = info.type, s = slot }

            if info.type == "spell" then
                s.n = info.name
                s.r = info.rank
                s.i = info.icon
            elseif info.type == "macro" then
                s.n = info.name
                s.id = info.id
                s.b = info.body
                s.i = info.icon
            elseif info.type == "item" then
                s.n = info.name
                s.id = info.id
                s.i = info.icon
            elseif info.type == "companion" then
                s.id = info.id
                s.ct = info.companionType or info.subType
                s.i = info.icon
            elseif info.type == "equipmentset" then
                s.sn = info.setName or info.id
                s.i = info.icon
            end

            stripped.slots[slot] = s
        end
    end

    return stripped
end

function ImportExport:RestoreLayout(stripped)
    if not stripped then return nil end

    local layout = {
        timestamp = Utils:GetTimestamp(),
        slots = {},
        configuredSlots = 0,
    }

    for slot = 1, Settings.TOTAL_SLOTS do
        local s = stripped.slots and stripped.slots[slot]
        if s and s.t then
            local info = {
                type = s.t,
                slot = slot,
                icon = s.i,
            }

            if s.t == "spell" then
                info.name = s.n
                info.rank = s.r or ""
            elseif s.t == "macro" then
                info.name = s.n
                info.id = s.id
                info.body = s.b
            elseif s.t == "item" then
                info.name = s.n
                info.id = s.id
            elseif s.t == "companion" then
                info.id = s.id
                info.companionType = s.ct
                info.subType = s.ct
            elseif s.t == "equipmentset" then
                info.setName = s.sn
                info.id = s.sn
            end

            layout.slots[slot] = info
            layout.configuredSlots = layout.configuredSlots + 1
        end
    end

    return layout
end

--------------------------------------------------------------------------------
-- Preview (describe backup contents without applying)
--------------------------------------------------------------------------------

function ImportExport:Preview(importString)
    local result, err = self:Import(importString)
    if not result then
        return nil, err
    end

    local summary = {
        type = result.type,
        class = result.class,
        classMatch = result.classMatch,
        version = result.version,
    }

    if result.type == "layout" then
        local data = result.data
        summary.description = "Single Level Layout"
        summary.level = data and data.level or "?"
        local configured = 0
        if data and data.layout and data.layout.slots then
            for _, s in pairs(data.layout.slots) do
                if s and s.t then configured = configured + 1 end
            end
        end
        summary.configuredSlots = configured
        summary.lines = {
            string.format("Type: Single level layout"),
            string.format("Level: %s", tostring(summary.level)),
            string.format("Configured slots: %d", configured),
            string.format("Class: %s%s", result.class or "Unknown",
                result.classMatch and "" or " |cFFFF4444(MISMATCH)|r"),
        }

    elseif result.type == "keyframes" then
        local data = result.data
        local kfList = data and data.keyframes or {}
        local levels = {}
        for _, kf in ipairs(kfList) do
            table.insert(levels, tostring(kf.level))
        end
        summary.description = "Keyframe Configuration"
        summary.count = #kfList
        summary.levels = levels
        summary.lines = {
            string.format("Type: Keyframe configuration"),
            string.format("Breakpoints: %d", #kfList),
            string.format("Levels: %s", table.concat(levels, ", ")),
            string.format("Class: %s%s", result.class or "Unknown",
                result.classMatch and "" or " |cFFFF4444(MISMATCH)|r"),
        }

    elseif result.type == "full" then
        local data = result.data
        local levelList = data and data.levels or {}
        local kfList = data and data.keyframes or {}
        local specName = data and data.specName or "Unknown"
        local hasSlotStates = data and data.enabledSlots and next(data.enabledSlots) ~= nil
        local disabledCount = 0
        if data and data.enabledSlots then
            for _, v in pairs(data.enabledSlots) do
                if v == false then disabledCount = disabledCount + 1 end
            end
        end
        local minLvl, maxLvl = 999, 0
        for _, lvl in ipairs(levelList) do
            local l = lvl.level or 0
            if l < minLvl then minLvl = l end
            if l > maxLvl then maxLvl = l end
        end

        summary.description = "Full Backup"
        summary.levelCount = #levelList
        summary.keyframeCount = #kfList
        summary.specName = specName
        summary.lines = {
            string.format("Type: Full backup (%s)", specName),
            string.format("Levels: %d (range %d-%d)", #levelList, minLvl, maxLvl),
            string.format("Breakpoints: %d", #kfList),
            string.format("Class: %s%s", result.class or "Unknown",
                result.classMatch and "" or " |cFFFF4444(MISMATCH)|r"),
        }
        if disabledCount > 0 then
            table.insert(summary.lines,
                string.format("Disabled slots: %d (will be restored)", disabledCount))
        end
        table.insert(summary.lines, "")
        table.insert(summary.lines, "|cFFFF8800Warning: This will overwrite all existing data|r")
        table.insert(summary.lines, "|cFFFF8800for the current spec.|r")

    elseif result.type == "template" then
        local data = result.data
        summary.description = "Template"
        summary.templateName = data and data.name or "Unknown"
        summary.lines = {
            string.format("Type: Template"),
            string.format("Name: %s", summary.templateName),
            string.format("Class: %s%s", result.class or "Unknown",
                result.classMatch and "" or " |cFFFF4444(MISMATCH)|r"),
        }
    else
        summary.description = "Unknown type"
        summary.lines = { "Unknown backup type: " .. tostring(result.type) }
    end

    return summary, result
end
