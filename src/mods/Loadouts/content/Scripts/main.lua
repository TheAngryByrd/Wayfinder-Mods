local UEHelpers = require("UEHelpers")

local DATABASE_PATH = "Mods/Loadouts/loadouts.db"
local DATABASE_TEMP_PATH = DATABASE_PATH .. ".tmp"
local DATABASE_BACKUP_PATH = DATABASE_PATH .. ".bak"
local DATABASE_VERSION = 3
local INT32_MIN = -2147483648
local INT32_MAX = 2147483647
local UINT32_MAX = 4294967295
local GUID_WORD_MODULUS = 4294967296
local SMALL_INDEX_MAX = 255
local CONFIG_PATH = "Mods/Loadouts/config.ini"
local QUICK_PROFILE_NAME = "Quick"
local QUICK_KEYS_ENABLED = true
local LOADOUT_UI_ENABLED = true
local profiles = {}
local pending_confirmation = nil
local apply_generation = 0
local data_table_cache = {}

local function log(message)
    print(string.format("[Loadouts] %s\n", message))
end

local function output_log(output_device, message)
    log(message)
    if output_device then
        pcall(function()
            output_device:Log(message)
        end)
    end
end

local function unwrap(value)
    if value == nil then
        return nil
    end
    local ok, result = pcall(function()
        return value:get()
    end)
    if ok then
        return result
    end
    return value
end

local function to_text(value)
    if value == nil then
        return ""
    end
    if type(value) == "string" then
        return value
    end
    local ok, result = pcall(function()
        return value:ToString()
    end)
    if ok then
        return result
    end
    return tostring(value)
end

local function to_number(value, fallback)
    if type(value) == "number" then
        return value
    end
    return tonumber(to_text(value)) or fallback
end

local function normalize_guid_word(value)
    local number = to_number(value, nil)
    if type(number) ~= "number"
        or number % 1 ~= 0
        or number < INT32_MIN
        or number > UINT32_MAX then
        return nil
    end
    if number < 0 then
        return number + GUID_WORD_MODULUS
    end
    return number
end

local function engine_guid_word(value)
    local normalized = normalize_guid_word(value)
    if normalized == nil then
        return nil
    end
    if normalized > INT32_MAX then
        return normalized - GUID_WORD_MODULUS
    end
    return normalized
end

local function decimal_word_modulus(value)
    local result = 0
    for index = 1, #value do
        result = (result * 10 + tonumber(value:sub(index, index))) % GUID_WORD_MODULUS
    end
    return result
end

local function normalize_guid_key_text(value)
    local a, b, c, d = tostring(value or ""):match("^(%d+)%-(%d+)%-(%d+)%-(%d+)$")
    if not a then
        return value
    end
    return string.format(
        "%u-%u-%u-%u",
        decimal_word_modulus(a),
        decimal_word_modulus(b),
        decimal_word_modulus(c),
        decimal_word_modulus(d)
    )
end

local function to_boolean(value, fallback)
    value = unwrap(value)
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "number" then
        return value ~= 0
    end
    local text = string.lower(to_text(value))
    if text == "true" or text == "1" then
        return true
    end
    if text == "false" or text == "0" then
        return false
    end
    return fallback
end

local function out_value(values, name)
    if type(values) ~= "table" then
        return nil
    end
    if values[name] ~= nil then
        return unwrap(values[name])
    end
    if values[1] ~= nil then
        return unwrap(values[1])
    end
    for _, value in pairs(values) do
        return unwrap(value)
    end
    return nil
end

local function out_boolean(values, name)
    return to_boolean(out_value(values, name), false)
end

local function is_valid(object)
    if object == nil then
        return false
    end
    local ok, valid = pcall(function()
        return object:IsValid()
    end)
    return ok and valid
end

local function each_array(array, callback)
    if array == nil then
        return false, "array unavailable"
    end
    if type(array) == "table" then
        return pcall(function()
            for index, element in ipairs(array) do
                callback(index, unwrap(element))
            end
        end)
    end
    local ok, array_error = pcall(function()
        array:ForEach(function(index, element)
            callback(index, unwrap(element))
        end)
    end)
    return ok, array_error
end

local function array_count(array)
    if array == nil then
        return 0
    end
    if type(array) == "table" then
        return #array
    end
    local ok, count = pcall(function()
        return array:GetArrayNum()
    end)
    if ok then
        return count
    end
    return 0
end

local function object_path(object)
    if not is_valid(object) then
        return ""
    end
    local ok, full_name = pcall(function()
        return object:GetFullName()
    end)
    if not ok or not full_name then
        return ""
    end
    return full_name:match("^%S+%s+(.+)$") or full_name
end

local function row_snapshot(row_handle)
    if row_handle == nil then
        return nil
    end
    if type(row_handle) == "table"
        and type(row_handle.table_path) == "string"
        and type(row_handle.row) == "string" then
        if row_handle.table_path == "" or row_handle.row == "" or row_handle.row == "None" then
            return nil
        end
        return {
            table_path = row_handle.table_path,
            row = row_handle.row
        }
    end
    local ok, result = pcall(function()
        return {
            table_path = object_path(row_handle.DataTable),
            row = to_text(row_handle.RowName)
        }
    end)
    if not ok or result.table_path == "" or result.row == "" or result.row == "None" then
        return nil
    end
    return result
end

local function guid_snapshot(guid)
    if guid == nil then
        return nil
    end
    if type(guid) == "table"
        and guid.a ~= nil
        and guid.b ~= nil
        and guid.c ~= nil
        and guid.d ~= nil then
        local result = {
            a = normalize_guid_word(guid.a),
            b = normalize_guid_word(guid.b),
            c = normalize_guid_word(guid.c),
            d = normalize_guid_word(guid.d)
        }
        if result.a ~= nil and result.b ~= nil and result.c ~= nil and result.d ~= nil then
            return result
        end
        return nil
    end
    local ok, result = pcall(function()
        return {
            a = normalize_guid_word(guid.A),
            b = normalize_guid_word(guid.B),
            c = normalize_guid_word(guid.C),
            d = normalize_guid_word(guid.D)
        }
    end)
    if not ok or result.a == nil or result.b == nil or result.c == nil or result.d == nil then
        return nil
    end
    return result
end

local function guid_key_from_parts(a, b, c, d)
    return string.format("%u-%u-%u-%u", a or 0, b or 0, c or 0, d or 0)
end

local function guid_key(guid)
    local value = guid_snapshot(guid)
    if not value then
        return ""
    end
    return guid_key_from_parts(value.a, value.b, value.c, value.d)
end

local function handle_snapshot(handle)
    if handle == nil then
        return nil
    end
    if type(handle) == "table"
        and handle.table_path ~= nil
        and handle.row ~= nil
        and handle.a ~= nil
        and handle.b ~= nil
        and handle.c ~= nil
        and handle.d ~= nil then
        local row = row_snapshot(handle)
        local id = guid_snapshot(handle)
        if row and id then
            return {
                table_path = row.table_path,
                row = row.row,
                a = id.a,
                b = id.b,
                c = id.c,
                d = id.d
            }
        end
        return nil
    end
    local ok, row, id = pcall(function()
        return row_snapshot(handle.Data), guid_snapshot(handle.ID)
    end)
    if not ok or not row or not id then
        return nil
    end
    return {
        table_path = row.table_path,
        row = row.row,
        a = id.a,
        b = id.b,
        c = id.c,
        d = id.d
    }
end

local function handle_key(snapshot)
    if not snapshot then
        return ""
    end
    return guid_key_from_parts(snapshot.a, snapshot.b, snapshot.c, snapshot.d)
end

local function handle_identity(snapshot)
    if not snapshot then
        return ""
    end
    return table.concat({
        snapshot.table_path,
        snapshot.row,
        tostring(snapshot.a),
        tostring(snapshot.b),
        tostring(snapshot.c),
        tostring(snapshot.d)
    }, "\31")
end

local function handle_has_zero_id(snapshot)
    return snapshot
        and snapshot.a == 0
        and snapshot.b == 0
        and snapshot.c == 0
        and snapshot.d == 0
end

local function resolve_data_table(path)
    if path == "" then
        return nil
    end
    local cached = data_table_cache[path]
    if is_valid(cached) then
        return cached
    end
    local ok, result = pcall(StaticFindObject, path)
    if (not ok or not is_valid(result)) and LoadAsset then
        ok, result = pcall(LoadAsset, path)
    end
    if ok and is_valid(result) then
        data_table_cache[path] = result
        return result
    end
    return nil
end

local function make_row(snapshot)
    if not snapshot then
        return nil
    end
    local data_table = resolve_data_table(snapshot.table_path)
    if not data_table then
        return nil
    end
    return {
        DataTable = data_table,
        RowName = FName(snapshot.row)
    }
end

local function make_guid(snapshot)
    if not snapshot then
        return nil
    end
    local a = engine_guid_word(snapshot.a)
    local b = engine_guid_word(snapshot.b)
    local c = engine_guid_word(snapshot.c)
    local d = engine_guid_word(snapshot.d)
    if a == nil or b == nil or c == nil or d == nil then
        return nil
    end
    return {
        A = a,
        B = b,
        C = c,
        D = d
    }
end

local function make_handle(snapshot)
    local row = make_row(snapshot)
    local id = make_guid(snapshot)
    if not row or not id then
        return nil
    end
    return {
        Data = row,
        ID = id
    }
end

local function profile_key(name)
    return name:lower()
end

local function clean_profile_name(parameters)
    local name = table.concat(parameters or {}, " ")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    name = name:gsub("[%c]", "")
    if #name > 64 then
        name = name:sub(1, 64)
    end
    return name
end

local function new_profile(name, character)
    return {
        name = name,
        character = character or "",
        items = {},
        echos = {},
        abilities = {},
        talents = {},
        talent_holders = {},
        nodes = {},
        dyes = {},
        weapon_styles = {},
        armor_styles = {},
        echos_trusted = true,
        talents_trusted = true,
        nodes_trusted = true,
        styles_trusted = true,
        dyes_trusted = true
    }
end

local function encode_field(value)
    return tostring(value or ""):gsub("[%%\t\r\n]", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
end

local function decode_field(value)
    return (value or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local function split_record(line)
    local fields = {}
    for value in (line .. "\t"):gmatch("(.-)\t") do
        fields[#fields + 1] = decode_field(value)
    end
    return fields
end

local function write_record(file, fields)
    local encoded = {}
    for index, value in ipairs(fields) do
        encoded[index] = encode_field(value)
    end
    local call_ok, result, write_error = pcall(function()
        return file:write(table.concat(encoded, "\t"), "\n")
    end)
    if not call_ok then
        return false, tostring(result)
    end
    if not result then
        return false, tostring(write_error or "write failed")
    end
    return true
end

local function close_written_file(file)
    local flush_ok, flushed, flush_error = pcall(function()
        return file:flush()
    end)
    local close_ok, closed, close_error = pcall(function()
        return file:close()
    end)
    if not flush_ok then
        return false, tostring(flushed)
    end
    if not flushed then
        return false, tostring(flush_error or "flush failed")
    end
    if not close_ok then
        return false, tostring(closed)
    end
    if not closed then
        return false, tostring(close_error or "close failed")
    end
    return true
end

local function close_read_file(file)
    local close_ok, closed, close_error = pcall(function()
        return file:close()
    end)
    if not close_ok then
        return false, tostring(closed)
    end
    if not closed then
        return false, tostring(close_error or "close failed")
    end
    return true
end

local function number_at(fields, index)
    if fields[index] == nil or fields[index] == "" then
        return nil
    end
    return tonumber(fields[index])
end

local function is_integer(value, minimum, maximum)
    return type(value) == "number"
        and value % 1 == 0
        and value >= (minimum or 0)
        and (maximum == nil or value <= maximum)
end

local function parse_database(path, allow_missing)
    local file, open_error = io.open(path, "r")
    if not file then
        if allow_missing then
            return {}, DATABASE_VERSION, nil, false
        end
        return nil, nil, tostring(open_error), false
    end

    local parsed = {}
    local version = nil
    local parse_error = nil
    local line_number = 0
    local read_ok, read_error = pcall(function()
        for line in file:lines() do
            line_number = line_number + 1
            if line ~= "" and not parse_error then
                local fields = split_record(line)
                local record_type = fields[1]
                local function fail(message)
                    parse_error = string.format("%s line %d: %s", path, line_number, message)
                end
                local function require_fields(count)
                    if #fields < count then
                        fail(string.format("%s record has %d fields; expected at least %d", record_type, #fields, count))
                        return false
                    end
                    return true
                end
                local function require_numbers(indices)
                    for _, index in ipairs(indices) do
                        if number_at(fields, index) == nil then
                            fail(string.format("%s record field %d is not numeric", record_type, index))
                            return false
                        end
                    end
                    return true
                end
                local function require_guid_parts(indices)
                    for _, index in ipairs(indices) do
                        if normalize_guid_word(number_at(fields, index)) == nil then
                            fail(string.format("%s record field %d is not a 32-bit GUID word", record_type, index))
                            return false
                        end
                    end
                    return true
                end

                if not version then
                    if record_type ~= "VERSION" or not require_fields(2) then
                        if not parse_error then
                            fail("the first record must declare a database version")
                        end
                    else
                        local parsed_version = number_at(fields, 2)
                        if not parsed_version or parsed_version % 1 ~= 0 then
                            fail("the database version is invalid")
                        elseif parsed_version < 1 or parsed_version > DATABASE_VERSION then
                            fail("unsupported database version " .. tostring(fields[2]))
                        else
                            version = parsed_version
                        end
                    end
                elseif record_type == "VERSION" then
                    fail("the database contains more than one version record")
                elseif record_type == "PROFILE" then
                    local profile_fields = version >= 3 and 8 or 2
                    if require_fields(profile_fields) then
                        if fields[2] == "" then
                            fail("PROFILE name is empty")
                        elseif parsed[profile_key(fields[2])] then
                            fail("duplicate PROFILE name " .. fields[2])
                        elseif version >= 3
                            and (fields[4] ~= "0" and fields[4] ~= "1"
                                or fields[5] ~= "0" and fields[5] ~= "1"
                                or fields[6] ~= "0" and fields[6] ~= "1"
                                or fields[7] ~= "0" and fields[7] ~= "1"
                                or fields[8] ~= "0" and fields[8] ~= "1") then
                            fail("PROFILE trust fields must be 0 or 1")
                        else
                            local profile = new_profile(fields[2], fields[3])
                            if version < 3 then
                                profile.echos_trusted = false
                                profile.talents_trusted = false
                                profile.nodes_trusted = false
                                profile.styles_trusted = false
                                profile.dyes_trusted = false
                            else
                                profile.echos_trusted = fields[4] ~= "0"
                                profile.talents_trusted = fields[5] ~= "0"
                                profile.nodes_trusted = fields[6] ~= "0"
                                profile.styles_trusted = fields[7] ~= "0"
                                profile.dyes_trusted = fields[8] ~= "0"
                            end
                            parsed[profile_key(fields[2])] = profile
                        end
                    end
                else
                    if not require_fields(2) then
                        return
                    end
                    local profile = parsed[profile_key(fields[2])]
                    if not profile then
                        fail(record_type .. " refers to an unknown profile")
                    elseif record_type == "ITEM" then
                        local minimum = version == 1 and 10 or 11
                        if require_fields(minimum)
                            and require_numbers({ 7, 8, 9, 10 })
                            and require_guid_parts({ 7, 8, 9, 10 }) then
                            profile.items[#profile.items + 1] = {
                                category = fields[3], label = fields[4], table_path = fields[5], row = fields[6],
                                a = normalize_guid_word(number_at(fields, 7)),
                                b = normalize_guid_word(number_at(fields, 8)),
                                c = normalize_guid_word(number_at(fields, 9)),
                                d = normalize_guid_word(number_at(fields, 10)),
                                slot = fields[11] or ""
                            }
                        end
                    elseif record_type == "ECHO" then
                        if require_fields(11)
                            and require_numbers({ 4, 8, 9, 10, 11 })
                            and require_guid_parts({ 8, 9, 10, 11 }) then
                            local slot = number_at(fields, 4) - (version < 3 and 1 or 0)
                            if not is_integer(slot, 0, SMALL_INDEX_MAX) then
                                fail("ECHO slot is outside the supported range")
                            else
                                profile.echos[#profile.echos + 1] = {
                                    holder_id = normalize_guid_key_text(fields[3]), slot = slot, label = fields[5],
                                    table_path = fields[6], row = fields[7],
                                    a = normalize_guid_word(number_at(fields, 8)),
                                    b = normalize_guid_word(number_at(fields, 9)),
                                    c = normalize_guid_word(number_at(fields, 10)),
                                    d = normalize_guid_word(number_at(fields, 11))
                                }
                            end
                        end
                    elseif record_type == "ABILITY" then
                        if require_fields(7) and require_numbers({ 4 }) then
                            local slot = number_at(fields, 4) - (version < 3 and 1 or 0)
                            if not is_integer(slot, 0, SMALL_INDEX_MAX) then
                                fail("ABILITY slot is outside the supported range")
                            else
                                profile.abilities[#profile.abilities + 1] = {
                                    holder_id = normalize_guid_key_text(fields[3]), slot = slot,
                                    label = fields[5], table_path = fields[6], row = fields[7]
                                }
                            end
                        end
                    elseif record_type == "TALENT" then
                        if require_fields(13)
                            and require_numbers({ 7, 8, 9, 10, 11 })
                            and require_guid_parts({ 7, 8, 9, 10 }) then
                            local points = number_at(fields, 11)
                            if not is_integer(points, 1, SMALL_INDEX_MAX) then
                                fail("TALENT points are outside the supported range")
                            else
                                profile.talents[#profile.talents + 1] = {
                                    holder_id = normalize_guid_key_text(fields[3]), label = fields[4],
                                    table_path = fields[5], row = fields[6],
                                    a = normalize_guid_word(number_at(fields, 7)),
                                    b = normalize_guid_word(number_at(fields, 8)),
                                    c = normalize_guid_word(number_at(fields, 9)),
                                    d = normalize_guid_word(number_at(fields, 10)), points = points,
                                    pool_table_path = fields[12], pool_row = fields[13]
                                }
                            end
                        end
                    elseif record_type == "NODE" then
                        if require_fields(5) and require_numbers({ 4, 5 }) then
                            local tree_type = number_at(fields, 4)
                            local tree_index = number_at(fields, 5)
                            if not is_integer(tree_type, 0, SMALL_INDEX_MAX)
                                or not is_integer(tree_index, 0, INT32_MAX) then
                                fail("NODE tree values are outside the supported range")
                            else
                                profile.nodes[#profile.nodes + 1] = {
                                    node_id = fields[3], tree_type = tree_type, tree_index = tree_index
                                }
                            end
                        end
                    elseif record_type == "TALENT_HOLDER" then
                        if require_fields(3) and fields[3] ~= "" then
                            profile.talent_holders[#profile.talent_holders + 1] = normalize_guid_key_text(fields[3])
                        elseif not parse_error then
                            fail("TALENT_HOLDER identifier is empty")
                        end
                    elseif record_type == "DYE" then
                        if require_fields(7) then
                            local map_ids = {}
                            for map_id in fields[7]:gmatch("[^,]+") do
                                local parsed_map_id = tonumber(map_id)
                                if not is_integer(parsed_map_id, 0, INT32_MAX) then
                                    fail("DYE map identifier is not numeric")
                                    break
                                end
                                map_ids[#map_ids + 1] = parsed_map_id
                            end
                            if not parse_error then
                                profile.dyes[#profile.dyes + 1] = {
                                    holder_id = normalize_guid_key_text(fields[3]),
                                    label = fields[4], table_path = fields[5],
                                    row = fields[6], map_ids = map_ids
                                }
                            end
                        end
                    elseif record_type == "WEAPON_STYLE" then
                        if require_fields(6) and require_numbers({ 4 }) then
                            local weapon_subclass = number_at(fields, 4)
                            if not is_integer(weapon_subclass, 1, 12) then
                                fail("WEAPON_STYLE subclass is outside the supported range")
                            else
                                profile.weapon_styles[#profile.weapon_styles + 1] = {
                                    label = fields[3], weapon_subclass = weapon_subclass,
                                    table_path = fields[5], row = fields[6]
                                }
                            end
                        end
                    elseif record_type == "ARMOR_STYLE" then
                        if require_fields(6) and require_numbers({ 4 }) then
                            local armor_slot = number_at(fields, 4)
                            if not is_integer(armor_slot, 0, SMALL_INDEX_MAX) then
                                fail("ARMOR_STYLE slot is outside the supported range")
                            else
                                profile.armor_styles[#profile.armor_styles + 1] = {
                                    label = fields[3], armor_slot = armor_slot,
                                    table_path = fields[5], row = fields[6]
                                }
                            end
                        end
                    else
                        fail("unknown record type " .. tostring(record_type))
                    end
                end
            end
        end
    end)
    local close_ok, close_error = close_read_file(file)
    if not read_ok then
        return nil, nil, string.format("%s line %d: %s", path, line_number, tostring(read_error)), true
    end
    if not close_ok then
        return nil, nil, path .. ": " .. close_error, true
    end
    if parse_error then
        return nil, nil, parse_error, true
    end
    if not version then
        return nil, nil, path .. ": the database has no version record", true
    end
    return parsed, version, nil, true
end

local function sorted_profiles()
    local result = {}
    for _, profile in pairs(profiles) do
        result[#result + 1] = profile
    end
    table.sort(result, function(left, right)
        return left.name:lower() < right.name:lower()
    end)
    return result
end

local function save_database()
    local _, _, current_error, current_exists = parse_database(DATABASE_PATH, true)
    if current_error then
        return false, "the existing database is invalid: " .. current_error
    end

    local file, open_error = io.open(DATABASE_TEMP_PATH, "w")
    if not file then
        return false, tostring(open_error)
    end
    local write_error = nil
    local function emit(fields)
        if write_error then
            return
        end
        local wrote, record_error = write_record(file, fields)
        if not wrote then
            write_error = record_error
        end
    end

    emit({ "VERSION", DATABASE_VERSION })
    for _, profile in ipairs(sorted_profiles()) do
        emit({
            "PROFILE",
            profile.name,
            profile.character,
            profile.echos_trusted == false and "0" or "1",
            profile.talents_trusted == false and "0" or "1",
            profile.nodes_trusted == false and "0" or "1",
            profile.styles_trusted == false and "0" or "1",
            profile.dyes_trusted == false and "0" or "1"
        })
        for _, item in ipairs(profile.items) do
            emit({
                "ITEM", profile.name, item.category, item.label,
                item.table_path, item.row, item.a, item.b, item.c, item.d, item.slot
            })
        end
        for _, echo in ipairs(profile.echos) do
            emit({
                "ECHO", profile.name, echo.holder_id, echo.slot, echo.label,
                echo.table_path, echo.row, echo.a, echo.b, echo.c, echo.d
            })
        end
        for _, ability in ipairs(profile.abilities) do
            emit({
                "ABILITY", profile.name, ability.holder_id, ability.slot,
                ability.label, ability.table_path, ability.row
            })
        end
        for _, talent in ipairs(profile.talents) do
            emit({
                "TALENT", profile.name, talent.holder_id, talent.label,
                talent.table_path, talent.row, talent.a, talent.b, talent.c, talent.d,
                talent.points, talent.pool_table_path, talent.pool_row
            })
        end
        for _, holder_id in ipairs(profile.talent_holders) do
            emit({ "TALENT_HOLDER", profile.name, holder_id })
        end
        for _, node in ipairs(profile.nodes) do
            emit({
                "NODE", profile.name, node.node_id, node.tree_type, node.tree_index
            })
        end
        for _, dye in ipairs(profile.dyes) do
            emit({
                "DYE", profile.name, dye.holder_id, dye.label,
                dye.table_path, dye.row, table.concat(dye.map_ids, ",")
            })
        end
        for _, style in ipairs(profile.weapon_styles) do
            emit({
                "WEAPON_STYLE", profile.name, style.label, style.weapon_subclass,
                style.table_path, style.row
            })
        end
        for _, style in ipairs(profile.armor_styles) do
            emit({
                "ARMOR_STYLE", profile.name, style.label, style.armor_slot,
                style.table_path, style.row
            })
        end
    end
    local closed, close_error = close_written_file(file)
    if write_error or not closed then
        os.remove(DATABASE_TEMP_PATH)
        return false, tostring(write_error or close_error)
    end

    local _, saved_version, validation_error = parse_database(DATABASE_TEMP_PATH, false)
    if validation_error or saved_version ~= DATABASE_VERSION then
        os.remove(DATABASE_TEMP_PATH)
        return false, "temporary database validation failed: " .. tostring(validation_error or saved_version)
    end

    if current_exists then
        local backup = io.open(DATABASE_BACKUP_PATH, "r")
        if backup then
            local backup_closed, backup_close_error = close_read_file(backup)
            if not backup_closed then
                os.remove(DATABASE_TEMP_PATH)
                return false, "unable to close the existing database backup: " .. backup_close_error
            end
            local removed, remove_error = os.remove(DATABASE_BACKUP_PATH)
            if not removed then
                os.remove(DATABASE_TEMP_PATH)
                return false, "unable to replace the database backup: " .. tostring(remove_error)
            end
        end
        local backed_up, backup_error = os.rename(DATABASE_PATH, DATABASE_BACKUP_PATH)
        if not backed_up then
            os.remove(DATABASE_TEMP_PATH)
            return false, "unable to create the database backup: " .. tostring(backup_error)
        end
    end

    local replaced, replace_error = os.rename(DATABASE_TEMP_PATH, DATABASE_PATH)
    if not replaced then
        local restore_error = nil
        if current_exists then
            local restored, rollback_error = os.rename(DATABASE_BACKUP_PATH, DATABASE_PATH)
            if not restored then
                restore_error = tostring(rollback_error)
            end
        end
        if restore_error then
            return false, string.format(
                "unable to replace the database: %s; backup restore failed: %s",
                tostring(replace_error),
                restore_error
            )
        end
        return false, "unable to replace the database: " .. tostring(replace_error)
    end
    return true
end

local function persist_database()
    local call_ok, saved, save_error = pcall(save_database)
    if not call_ok then
        return false, tostring(saved)
    end
    return saved, save_error
end

local function load_database()
    local loaded, version, load_error, exists = parse_database(DATABASE_PATH, true)
    if load_error then
        log("Unable to load the loadout database. Existing profiles were kept: " .. load_error)
        return false, load_error
    end
    if not exists then
        for _, candidate in ipairs({
            { path = DATABASE_TEMP_PATH, label = "temporary database" },
            { path = DATABASE_BACKUP_PATH, label = "database backup" }
        }) do
            local recovered, recovered_version, recovery_error, recovery_exists =
                parse_database(candidate.path, true)
            if recovery_exists and not recovery_error then
                local restored, restore_error = os.rename(candidate.path, DATABASE_PATH)
                if restored then
                    log("Recovered the missing loadout database from the " .. candidate.label .. ".")
                else
                    log(string.format(
                        "Loaded the %s in memory, but could not restore its file: %s",
                        candidate.label,
                        tostring(restore_error)
                    ))
                end
                loaded = recovered
                version = recovered_version
                exists = true
                break
            elseif recovery_exists and recovery_error then
                log("Ignored an invalid " .. candidate.label .. ": " .. recovery_error)
            end
        end
    end
    profiles = loaded
    if version < DATABASE_VERSION then
        log(string.format("Loaded legacy loadout database version=%d", version))
    end
    return true
end

local function load_config()
    local file = io.open(CONFIG_PATH, "r")
    if not file then
        return
    end
    for line in file:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key == "QuickProfileName" and value ~= "" then
            QUICK_PROFILE_NAME = value:sub(1, 64)
        elseif key == "EnableQuickKeys" then
            QUICK_KEYS_ENABLED = value ~= "0"
        elseif key == "EnableLoadoutUi" then
            LOADOUT_UI_ENABLED = value ~= "0"
        end
    end
    file:close()
end

local function get_context()
    local ok, player_controller = pcall(UEHelpers.GetPlayerController)
    if not ok or not is_valid(player_controller) then
        return nil, "The local player controller is not ready."
    end
    local state_ok, player_state = pcall(function()
        return player_controller.PlayerState
    end)
    if not state_ok or not is_valid(player_state) then
        return nil, "The local player state is not ready."
    end
    local components_ok, inventory, loadout, archetype = pcall(function()
        return player_state:GetInventoryComponent(),
            player_state.m_pInventoryLoadoutComponent,
            player_state:GetArchetypeComponent()
    end)
    if not components_ok or not is_valid(inventory) or not is_valid(loadout) then
        return nil, "The loadout data is not ready."
    end
    return {
        player_controller = player_controller,
        player_state = player_state,
        inventory = inventory,
        loadout = loadout,
        archetype = archetype
    }
end

local function get_current_loadout(component)
    local properties_ok, current_id, loadouts = pcall(function()
        return component.m_CurrentLoadoutIdData, component.m_Loadouts.m_Loadouts
    end)
    if not properties_ok or not current_id then
        return nil
    end
    local target_key = guid_key(current_id.LoadoutId)
    local found = nil
    local scan_ok = each_array(loadouts, function(_, candidate)
        if not found and guid_key(candidate.LoadoutIdData.LoadoutId) == target_key then
            local copied = {
                Items = {},
                WeaponGlamours = {},
                ArmorGlamours = {}
            }
            local items_ok, items_error = each_array(candidate.Items, function(_, item)
                local handle = handle_snapshot(item.ItemHandle)
                if not handle then
                    error("current item handle unavailable")
                end
                copied.Items[#copied.Items + 1] = { ItemHandle = handle }
            end)
            if not items_ok then
                error(items_error)
            end
            local weapons_ok, weapons_error = each_array(candidate.WeaponGlamours, function(_, style)
                local source = row_snapshot(style.Source)
                if not source then
                    error("current weapon style unavailable")
                end
                copied.WeaponGlamours[#copied.WeaponGlamours + 1] = {
                    WeaponSubclass = to_number(style.WeaponSubclass, 0),
                    Source = source
                }
            end)
            if not weapons_ok then
                error(weapons_error)
            end
            local armor_ok, armor_error = each_array(candidate.ArmorGlamours, function(_, style)
                local source = row_snapshot(style.Source)
                if not source then
                    error("current armor style unavailable")
                end
                copied.ArmorGlamours[#copied.ArmorGlamours + 1] = {
                    ArmorSlot = to_number(style.ArmorSlot, 0),
                    Source = source
                }
            end)
            if not armor_ok then
                error(armor_error)
            end
            found = copied
        end
    end)
    if not scan_ok then
        return nil
    end
    return found
end

local last_item_lookup_error = ""

local function native_integer(value, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= math.floor(number) or number < minimum or number > maximum then
        return nil
    end
    return number
end

local function native_handle(fields, offset)
    local snapshot = {
        table_path = fields[offset],
        row = fields[offset + 1],
        a = normalize_guid_word(fields[offset + 2]),
        b = normalize_guid_word(fields[offset + 3]),
        c = normalize_guid_word(fields[offset + 4]),
        d = normalize_guid_word(fields[offset + 5])
    }
    if not snapshot.table_path
        or snapshot.table_path == ""
        or not snapshot.row
        or snapshot.row == ""
        or snapshot.row == "None"
        or snapshot.a == nil
        or snapshot.b == nil
        or snapshot.c == nil
        or snapshot.d == nil then
        return nil
    end
    return snapshot
end

local function parse_native_item(payload)
    if type(payload) ~= "string" or payload == "" then
        return nil, "The native item capture returned no data."
    end
    local entry = {
        Handle = nil,
        Spec = {
            Dyes = {},
            AbilitySlots = {},
            TalentItems = {},
            FogSouls = {},
            EchoItems = {},
            GeneratedFogSoulSlotCount = nil,
            EquippedToSlotName = ""
        }
    }
    local fog_souls = {}
    local highest_fog_slot = -1
    for line in (payload .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then
            local fields = split_record(line)
            local kind = fields[1]
            if kind == "ITEM" then
                entry.Handle = native_handle(fields, 2)
            elseif kind == "SLOTS" then
                entry.Spec.GeneratedFogSoulSlotCount = native_integer(fields[2], 0, 64)
            elseif kind == "SLOTNAME" then
                entry.Spec.EquippedToSlotName = fields[2] or ""
            elseif kind == "DYE" then
                local map_count = native_integer(fields[4], 0, 64)
                if not fields[2] or fields[2] == "" or not fields[3] or fields[3] == "" or not map_count then
                    return nil, "The native item capture returned an invalid dye."
                end
                local map_ids = {}
                for index = 1, map_count do
                    local map_id = native_integer(fields[4 + index], -2147483648, 2147483647)
                    if map_id == nil then
                        return nil, "The native item capture returned an invalid dye channel."
                    end
                    map_ids[index] = map_id
                end
                entry.Spec.Dyes[#entry.Spec.Dyes + 1] = {
                    DyeData = { table_path = fields[2], row = fields[3] },
                    MapIDs = map_ids
                }
            elseif kind == "ABILITY" then
                local slot = native_integer(fields[2], 0, 63)
                if slot == nil then
                    return nil, "The native item capture returned an invalid ability slot."
                end
                local ability = {
                    Slot = slot,
                    IsSet = fields[3] == "1",
                    CurrentAbilityData = nil
                }
                if ability.IsSet then
                    if not fields[4] or fields[4] == "" or not fields[5] or fields[5] == "" then
                        return nil, "The native item capture returned an invalid selected ability."
                    end
                    ability.CurrentAbilityData = { table_path = fields[4], row = fields[5] }
                end
                entry.Spec.AbilitySlots[#entry.Spec.AbilitySlots + 1] = ability
            elseif kind == "TALENT" then
                local talent = native_handle(fields, 2)
                local points = native_integer(fields[8], 0, 2147483647)
                local pool = {
                    table_path = fields[9],
                    row = fields[10]
                }
                if not talent
                    or points == nil
                    or not pool.table_path
                    or pool.table_path == ""
                    or not pool.row
                    or pool.row == ""
                    or pool.row == "None" then
                    return nil, "The native item capture returned an invalid talent."
                end
                entry.Spec.TalentItems[#entry.Spec.TalentItems + 1] = {
                    TalentItem = talent,
                    NumPointsSpent = points,
                    TalentPool = pool
                }
            elseif kind == "FOG" then
                local slot = native_integer(fields[2], 0, 63)
                local id = slot ~= nil and {
                    a = normalize_guid_word(fields[3]),
                    b = normalize_guid_word(fields[4]),
                    c = normalize_guid_word(fields[5]),
                    d = normalize_guid_word(fields[6])
                } or nil
                if not id or id.a == nil or id.b == nil or id.c == nil or id.d == nil then
                    return nil, "The native item capture returned an invalid Echo slot."
                end
                fog_souls[slot] = id
                highest_fog_slot = math.max(highest_fog_slot, slot)
            elseif kind == "ECHO" then
                local slot = native_integer(fields[2], 0, 63)
                local echo = native_handle(fields, 3)
                if slot == nil or not echo then
                    return nil, "The native item capture returned an invalid Echo."
                end
                entry.Spec.EchoItems[handle_key(echo)] = echo
            else
                return nil, "The native item capture returned an unknown record."
            end
        end
    end
    if not entry.Handle or entry.Spec.GeneratedFogSoulSlotCount == nil then
        return nil, "The native item capture returned an incomplete item."
    end
    for slot = 0, highest_fog_slot do
        if not fog_souls[slot] then
            return nil, "The native item capture omitted an Echo slot."
        end
        entry.Spec.FogSouls[slot + 1] = fog_souls[slot]
    end
    return entry
end

local function native_capture_ready()
    if type(_G.LoadoutsNativeCaptureReady) ~= "function" then
        return false, "The native item capture bridge is unavailable. Restart Wayfinder after deployment."
    end
    local call_ok, ready, message = pcall(_G.LoadoutsNativeCaptureReady)
    if not call_ok or ready ~= true then
        return false, tostring(message or ready or "The native item capture bridge is not ready.")
    end
    return true, tostring(message or "")
end

local function get_item_entry(inventory, handle)
    local expected = handle_snapshot(handle)
    local inventory_path = object_path(inventory)
    if not expected or inventory_path == "" or type(_G.LoadoutsNativeCaptureItem) ~= "function" then
        last_item_lookup_error = "The native item capture bridge is unavailable."
        return nil
    end
    local call_ok, captured, payload = pcall(
        _G.LoadoutsNativeCaptureItem,
        inventory_path,
        expected.table_path,
        expected.row,
        expected.a,
        expected.b,
        expected.c,
        expected.d
    )
    if not call_ok or captured ~= true then
        last_item_lookup_error = tostring(payload or captured or "The native item capture failed.")
        return nil
    end
    local entry, parse_error = parse_native_item(payload)
    local actual = entry and handle_snapshot(entry.Handle) or nil
    if not actual or handle_identity(actual) ~= handle_identity(expected) then
        last_item_lookup_error = parse_error or "The native item capture returned the wrong inventory item."
        return nil
    end
    last_item_lookup_error = ""
    return entry
end

local function item_label(inventory, handle, entry)
    local snapshot = handle_snapshot(handle)
    return snapshot and snapshot.row or "Unknown item"
end

local function row_label(row_handle)
    local snapshot = row_snapshot(row_handle)
    return snapshot and snapshot.row or "Unknown style"
end

local function category_for_slot(slot_type)
    if slot_type == 2 then
        return "Weapon"
    end
    if slot_type == 5 or slot_type == 6 or (slot_type >= 54 and slot_type <= 58) then
        return "Armor"
    end
    if slot_type == 4 or slot_type == 7 or slot_type == 8 or slot_type == 59 then
        return "Talent"
    end
    if slot_type == 9 then
        return "Character"
    end
    if (slot_type >= 10 and slot_type <= 18)
        or (slot_type >= 20 and slot_type <= 37)
        or (slot_type >= 39 and slot_type <= 52) then
        return "Style"
    end
    return "Other"
end

local function capture_dyes(profile, holder_id, entry)
    if not entry or not entry.Spec then
        return false, "The equipped item has no dye data."
    end
    local read_ok, read_error = each_array(entry.Spec.Dyes, function(_, application)
        local row = row_snapshot(application.DyeData)
        if not row then
            error("Wayfinder returned a dye without a valid data row.")
        end
        local map_ids = {}
        local maps_ok, maps_error = each_array(application.MapIDs, function(_, map_id)
            map_ids[#map_ids + 1] = to_number(map_id, 0)
        end)
        if not maps_ok then
            error(maps_error)
        end
        if #map_ids > 0 then
            profile.dyes[#profile.dyes + 1] = {
                holder_id = holder_id,
                label = row_label(application.DyeData),
                table_path = row.table_path,
                row = row.row,
                map_ids = map_ids
            }
        end
    end)
    if not read_ok then
        return false, "The equipped dye set could not be read: " .. tostring(read_error)
    end
    return true
end

local function capture_abilities(profile, holder_id, entry)
    if not entry or not entry.Spec then
        return false, "The equipped item has no ability data."
    end
    local read_ok, read_error = each_array(entry.Spec.AbilitySlots, function(index, ability)
        if ability.IsSet then
            local row = row_snapshot(ability.CurrentAbilityData)
            if not row then
                error("Wayfinder returned a selected ability without a valid data row.")
            end
            profile.abilities[#profile.abilities + 1] = {
                holder_id = holder_id,
                slot = to_number(ability.Slot, index - 1),
                label = row.row,
                table_path = row.table_path,
                row = row.row
            }
        end
    end)
    if not read_ok then
        return false, "The equipped ability set could not be read: " .. tostring(read_error)
    end
    return true
end

local function capture_talents(profile, inventory, holder, holder_id, entry)
    if not entry or not entry.Spec then
        return false, "The equipped item has no talent data."
    end
    local read_ok, read_error = each_array(entry.Spec.TalentItems, function(_, talent)
        local points = to_number(talent.NumPointsSpent, 0)
        if points > 0 then
            local snapshot = handle_snapshot(talent.TalentItem)
            if not snapshot then
                error("Wayfinder returned an allocated talent without a valid item handle.")
            end
            local pool_row = row_snapshot(talent.TalentPool)
            if not pool_row then
                error("Wayfinder returned an allocated talent without a valid pool.")
            end
            profile.talents[#profile.talents + 1] = {
                holder_id = holder_id,
                label = item_label(inventory, snapshot, nil),
                table_path = snapshot.table_path,
                row = snapshot.row,
                a = snapshot.a,
                b = snapshot.b,
                c = snapshot.c,
                d = snapshot.d,
                points = points,
                pool_table_path = pool_row.table_path,
                pool_row = pool_row.row
            }
        end
    end)
    if not read_ok then
        return false, "The equipped talent set could not be read: " .. tostring(read_error)
    end
    return true
end

local function capture_item(profile, context, handle, seen_items, slot_name, slot_type)
    local snapshot = handle_snapshot(handle)
    if not snapshot then
        return false, "Wayfinder returned an invalid loadout item handle."
    end
    if handle_has_zero_id(snapshot) then
        return false, "Wayfinder returned an equipped item without an inventory GUID for " .. snapshot.row .. "."
    end
    local id = handle_key(snapshot)
    local identity = handle_identity(snapshot)
    if seen_items[identity] then
        return true
    end
    seen_items[identity] = true
    local entry = get_item_entry(context.inventory, handle)
    if not entry or not entry.Spec then
        local detail = last_item_lookup_error ~= "" and " " .. last_item_lookup_error or ""
        return false, "Wayfinder did not return the equipped item data for " .. snapshot.row .. "." .. detail
    end
    if entry.Spec.EquippedToSlotName ~= "" and entry.Spec.EquippedToSlotName ~= "None" then
        slot_name = entry.Spec.EquippedToSlotName
    end
    if not slot_name or slot_name == "" or slot_name == "None" then
        return false, "Wayfinder returned an equipped item without a slot name for " .. snapshot.row .. "."
    end
    local label = item_label(context.inventory, handle, entry)
    local category = category_for_slot(slot_type)
    profile.items[#profile.items + 1] = {
        category = category,
        label = label,
        table_path = snapshot.table_path,
        row = snapshot.row,
        a = snapshot.a,
        b = snapshot.b,
        c = snapshot.c,
        d = snapshot.d,
        slot = slot_name
    }
    if category == "Character" then
        profile.character = label
    end
    profile.talent_holders[#profile.talent_holders + 1] = id
    local dyes_ok, dyes_error = capture_dyes(profile, id, entry)
    if not dyes_ok then
        return false, dyes_error
    end
    local abilities_ok, abilities_error = capture_abilities(profile, id, entry)
    if not abilities_ok then
        return false, abilities_error
    end
    local talents_ok, talents_error = capture_talents(profile, context.inventory, handle, id, entry)
    if not talents_ok then
        return false, talents_error
    end
    local fog_souls_ok, fog_souls = pcall(function()
        return entry.Spec.FogSouls
    end)
    if not fog_souls_ok or fog_souls == nil then
        return false, "The equipped item has no attached Echo data."
    end
    local echos_ok, echos_error = each_array(fog_souls, function(index, echo_id)
        local echo_id_key = guid_key(echo_id)
        if echo_id_key == "" or echo_id_key == "0-0-0-0" then
            return
        end
        local echo = entry.Spec.EchoItems[echo_id_key]
        if not echo then
            error("Wayfinder returned an attached Echo that is not in the inventory.")
        end
        profile.echos[#profile.echos + 1] = {
            holder_id = id,
            slot = index - 1,
            label = item_label(context.inventory, echo, nil),
            table_path = echo.table_path,
            row = echo.row,
            a = echo.a,
            b = echo.b,
            c = echo.c,
            d = echo.d
        }
    end)
    if not echos_ok then
        return false, "The attached Echo set could not be read: " .. tostring(echos_error)
    end
    return true
end

local function each_unlocked_archetype_node(archetype, callback)
    if not is_valid(archetype) then
        return false
    end
    local properties_ok, current_character, tree_data = pcall(function()
        return to_text(archetype.m_CurrentCharacter), archetype.m_ArchetypeTreeData
    end)
    if not properties_ok or current_character == "" or current_character == "None" then
        return false
    end
    local matched = false
    local trees_ok = each_array(tree_data, function(_, tree)
        if not matched and to_text(tree.CharacterName) == current_character then
            matched = true
            local nodes_ok, nodes_error = each_array(tree.UnlockedNodes, callback)
            if not nodes_ok then
                error(nodes_error)
            end
        end
    end)
    return trees_ok and matched
end

local function capture_profile(name, context)
    local current = get_current_loadout(context.loadout)
    if not current then
        return nil, "Wayfinder did not return a current loadout."
    end
    local profile = new_profile(name, "")
    local seen_items = {}
    local capture_error = nil
    local slot_count = 0
    local loadout_items = {}
    local loadout_items_by_key = {}
    local loadout_read_ok, loadout_read_error = each_array(current.Items, function(_, loadout_item)
        if loadout_item then
            local snapshot = handle_snapshot(loadout_item.ItemHandle)
            if snapshot then
                local key = handle_identity(snapshot)
                loadout_items[#loadout_items + 1] = snapshot
                loadout_items_by_key[key] = true
            end
        end
    end)
    if not loadout_read_ok then
        return nil, "Wayfinder's current loadout items could not be read: " .. tostring(loadout_read_error)
    end
    local current_weapon_styles = {}
    local weapon_styles_ok, weapon_styles_error = each_array(current.WeaponGlamours, function(_, style)
        local row = row_snapshot(style.Source)
        if not row then
            error("Wayfinder returned a weapon style without a valid data row.")
        end
        current_weapon_styles[#current_weapon_styles + 1] = {
            weapon_subclass = to_number(style.WeaponSubclass, 0),
            table_path = row.table_path,
            row = row.row
        }
    end)
    if not weapon_styles_ok then
        return nil, "Wayfinder's weapon styles could not be read: " .. tostring(weapon_styles_error)
    end
    local current_armor_styles = {}
    local armor_styles_ok, armor_styles_error = each_array(current.ArmorGlamours, function(_, style)
        local row = row_snapshot(style.Source)
        if not row then
            error("Wayfinder returned an armor style without a valid data row.")
        end
        current_armor_styles[#current_armor_styles + 1] = {
            armor_slot = to_number(style.ArmorSlot, 0),
            table_path = row.table_path,
            row = row.row
        }
    end)
    if not armor_styles_ok then
        return nil, "Wayfinder's armor styles could not be read: " .. tostring(armor_styles_error)
    end
    local equipment_slots = {}
    local slot_scan_ok, slot_scan_error = each_array(context.inventory.m_equipmentSlots, function(_, slot)
        local definition = row_snapshot(slot.SlotDefinition)
        if not definition then
            error("equipment slot definition unavailable")
        end
        local copied = {
            name = definition.row,
            slot_type = to_number(slot.SlotType, 0),
            equipped_items = {}
        }
        local equipped_ok, equipped_error = each_array(slot.EquippedItems, function(_, handle)
            local snapshot = handle_snapshot(handle)
            if not snapshot then
                error("equipped item handle unavailable")
            end
            copied.equipped_items[#copied.equipped_items + 1] = snapshot
        end)
        if not equipped_ok then
            error(equipped_error)
        end
        equipment_slots[#equipment_slots + 1] = copied
    end)
    if not slot_scan_ok then
        return nil, "Wayfinder's equipment slots could not be read: " .. tostring(slot_scan_error)
    end
    local inventory_matches = 0
    for _, slot in ipairs(equipment_slots) do
        if capture_error then
            break
        end
        for _, handle in ipairs(slot.equipped_items) do
            if not capture_error then
                local snapshot = handle_snapshot(handle)
                local key = handle_identity(snapshot)
                if loadout_items_by_key[key] and not seen_items[key] then
                    local item_ok, item_error = capture_item(
                        profile,
                        context,
                        handle,
                        seen_items,
                        slot.name,
                        slot.slot_type
                    )
                    if item_ok then
                        slot_count = slot_count + 1
                        inventory_matches = inventory_matches + 1
                    else
                        capture_error = item_error
                    end
                end
            end
        end
    end
    if not capture_error then
        for _, snapshot in ipairs(loadout_items) do
            local key = handle_identity(snapshot)
            if not seen_items[key] then
                capture_error = "Wayfinder did not expose the equipment slot for "
                    .. (snapshot and snapshot.row or "an equipped item") .. "."
                break
            end
        end
    end
    log(string.format(
        "Capture current loadout entries=%d inventory_slots=%d inventory_matches=%d verified=%d items=%d",
        #loadout_items,
        #equipment_slots,
        inventory_matches,
        slot_count,
        #profile.items
    ))
    if capture_error then
        return nil, "The loadout item read failed: " .. capture_error
    end
    if slot_count == 0 or #profile.items == 0 then
        return nil, "Wayfinder returned no verified equipped loadout slots."
    end
    if profile.character == "" then
        return nil, "Wayfinder returned no equipped character slot."
    end
    for _, style in ipairs(current_weapon_styles) do
        profile.weapon_styles[#profile.weapon_styles + 1] = {
            label = row_label(style),
            weapon_subclass = style.weapon_subclass,
            table_path = style.table_path,
            row = style.row
        }
    end
    for _, style in ipairs(current_armor_styles) do
        profile.armor_styles[#profile.armor_styles + 1] = {
            label = row_label(style),
            armor_slot = style.armor_slot,
            table_path = style.table_path,
            row = style.row
        }
    end
    local nodes_ok = each_unlocked_archetype_node(context.archetype, function(_, node)
        profile.nodes[#profile.nodes + 1] = {
            node_id = to_text(node.NodeID),
            tree_type = to_number(node.TreeType, 0),
            tree_index = to_number(node.TreeIndex, 0)
        }
    end)
    if not nodes_ok then
        return nil, "Wayfinder did not expose the current archetype talent tree."
    end
    return profile
end

local function profile_capture_issue(profile)
    if #profile.items == 0 then
        return "The profile contains no equipped items."
    end
    local invalid = 0
    for _, item in ipairs(profile.items) do
        if item.slot == nil or item.slot == "" or item.slot == "None" then
            invalid = invalid + 1
        end
    end
    if invalid > 0 then
        return string.format(
            "%d saved item records have no verified equipment slot. Overwrite this profile to recapture it.",
            invalid
        )
    end
    if profile.character == nil or profile.character == "" then
        return "The profile has no verified Wayfinder character. Overwrite this profile to recapture it."
    end
    return nil
end

local function profile_counts(profile)
    local counts = {
        armor = 0,
        weapons = 0,
        style = #profile.dyes + #profile.weapon_styles + #profile.armor_styles,
        echos = #profile.echos,
        talents = #profile.talents + #profile.nodes,
        abilities = #profile.abilities
    }
    for _, item in ipairs(profile.items) do
        if item.category == "Armor" then
            counts.armor = counts.armor + 1
        elseif item.category == "Weapon" then
            counts.weapons = counts.weapons + 1
        elseif item.category == "Style" then
            counts.style = counts.style + 1
        elseif item.category == "Talent" then
            counts.talents = counts.talents + 1
        end
    end
    return counts
end

local function has_item(context, handle)
    if not handle then
        return false
    end
    local query = make_handle(handle_snapshot(handle))
    if not query then
        return false
    end
    local ok, result = pcall(function()
        return context.inventory:HasItem(query)
    end)
    return (ok and result) or get_item_entry(context.inventory, query) ~= nil
end

local function add_missing(result, seen, category, label)
    local key = category .. "\0" .. label
    if not seen[key] then
        seen[key] = true
        result[#result + 1] = category .. ": " .. label
    end
end

local function current_talent_signature(context, holder)
    local values = {}
    local entry = get_item_entry(context.inventory, holder)
    if not entry or not entry.Spec then
        return nil
    end
    local read_ok = each_array(entry.Spec.TalentItems, function(_, talent)
        local points = to_number(talent.NumPointsSpent, 0)
        if points > 0 then
            local talent_id = guid_key(talent.TalentItem.ID)
            if talent_id == "" then
                error("Wayfinder returned an allocated talent without a valid identifier.")
            end
            values[#values + 1] = talent_id .. "=" .. points
        end
    end)
    if not read_ok then
        return nil
    end
    table.sort(values)
    return table.concat(values, ";")
end

local function talent_pool_key(talent)
    return table.concat({
        talent.holder_id or "",
        talent.pool_table_path or "",
        talent.pool_row or ""
    }, "|")
end

local function target_talent_signatures(profile)
    local groups = {}
    for _, holder_id in ipairs(profile.talent_holders) do
        groups[holder_id] = groups[holder_id] or {}
    end
    for _, talent in ipairs(profile.talents) do
        groups[talent.holder_id] = groups[talent.holder_id] or {}
        groups[talent.holder_id][#groups[talent.holder_id] + 1] =
            handle_key(talent) .. "=" .. talent.points
    end
    local signatures = {}
    for holder_id, values in pairs(groups) do
        table.sort(values)
        signatures[holder_id] = table.concat(values, ";")
    end
    return signatures
end

local function current_node_signature(archetype)
    local values = {}
    local ok = each_unlocked_archetype_node(archetype, function(_, node)
        values[#values + 1] = to_text(node.NodeID)
    end)
    if not ok then
        return nil
    end
    table.sort(values)
    return table.concat(values, ";")
end

local function target_node_signature(profile)
    local values = {}
    for _, node in ipairs(profile.nodes) do
        values[#values + 1] = node.node_id
    end
    table.sort(values)
    return table.concat(values, ";")
end

local function profile_character_row(profile)
    for _, item in ipairs(profile.items) do
        if item.category == "Character" then
            return item.row
        end
    end
    return ""
end

local function archetype_node_exists(archetype, node)
    if not is_valid(archetype) or node.node_id == nil or node.node_id == "" then
        return false
    end
    local result = {}
    local ok = pcall(function()
        archetype:GetArchetypeTreeNodeByTypeAndID(node.tree_type, FName(node.node_id), result)
    end)
    if not ok then
        return false
    end
    local definition = out_value(result, "Node")
    return definition ~= nil and to_text(definition.NodeID) == node.node_id
end

local function native_dye_ready()
    if type(LoadoutsNativeDyeReady) ~= "function" or type(LoadoutsNativeApplyDye) ~= "function" then
        return false, "the native dye bridge is unavailable"
    end
    local call_ok, ready, message = pcall(LoadoutsNativeDyeReady)
    if not call_ok then
        return false, tostring(ready)
    end
    if ready ~= true then
        return false, tostring(message or "the native dye bridge is not ready")
    end
    return true, tostring(message or "")
end

local function echo_slot_count(context, holder)
    local entry = get_item_entry(context.inventory, holder)
    if not entry or not entry.Spec then
        return nil
    end
    local property_ok, count = pcall(function()
        return entry.Spec.GeneratedFogSoulSlotCount
    end)
    if not property_ok or count == nil then
        return nil
    end
    return count
end

local function resolve_profile(profile, context)
    local dye_ready, dye_message = native_dye_ready()
    local resolved = {
        items = {},
        item_records = {},
        echos = {},
        ability_rows = {},
        talents = {},
        talent_pools = {},
        dye_rows = {},
        weapon_style_rows = {},
        armor_style_rows = {},
        blocked_echo_holders = {},
        blocked_talent_holders = {},
        blocked_talent_pools = {},
        blocked_dye_holders = {},
        echo_slot_counts = {},
        current_talent_signatures = {},
        block_all_echos = profile.echos_trusted == false,
        block_all_talents = profile.talents_trusted == false,
        block_all_dyes = profile.dyes_trusted == false or not dye_ready,
        dye_bridge_ready = dye_ready,
        dye_bridge_message = dye_message,
        block_weapon_styles = profile.styles_trusted == false,
        block_armor_styles = profile.styles_trusted == false,
        block_archetype_nodes = profile.nodes_trusted == false
    }
    local missing = {}
    local missing_seen = {}
    for _, item in ipairs(profile.items) do
        local handle = make_handle(item)
        if has_item(context, handle) then
            local key = handle_key(item)
            resolved.items[key] = handle
            resolved.item_records[key] = item
        else
            add_missing(missing, missing_seen, item.category, item.label)
        end
    end
    for index, echo in ipairs(profile.echos) do
        local handle = make_handle(echo)
        if has_item(context, handle) then
            resolved.echos[index] = handle
        else
            add_missing(missing, missing_seen, "Echo", echo.label)
            resolved.blocked_echo_holders[echo.holder_id] = true
        end
        if not resolved.items[echo.holder_id] then
            add_missing(missing, missing_seen, "Echo host", echo.holder_id)
            resolved.blocked_echo_holders[echo.holder_id] = true
        else
            local slot_count = resolved.echo_slot_counts[echo.holder_id]
            if slot_count == nil then
                slot_count = echo_slot_count(context, resolved.items[echo.holder_id])
                resolved.echo_slot_counts[echo.holder_id] = slot_count
            end
            if slot_count == nil or echo.slot < 0 or echo.slot >= slot_count then
                add_missing(missing, missing_seen, "Echo slot", echo.label)
                resolved.blocked_echo_holders[echo.holder_id] = true
            end
        end
    end
    for index, ability in ipairs(profile.abilities) do
        local row = make_row(ability)
        if row and resolved.items[ability.holder_id] then
            resolved.ability_rows[index] = row
        else
            add_missing(missing, missing_seen, "Ability", ability.label)
        end
    end
    for index, talent in ipairs(profile.talents) do
        local handle = make_handle(talent)
        local pool = make_row({
            table_path = talent.pool_table_path,
            row = talent.pool_row
        })
        if has_item(context, handle) and resolved.items[talent.holder_id] and pool then
            resolved.talents[index] = handle
            resolved.talent_pools[index] = pool
        else
            add_missing(missing, missing_seen, "Talent", talent.label)
            if talent.pool_table_path == nil
                or talent.pool_table_path == ""
                or talent.pool_row == nil
                or talent.pool_row == "" then
                resolved.blocked_talent_holders[talent.holder_id] = true
            else
                resolved.blocked_talent_pools[talent_pool_key(talent)] = true
            end
        end
    end
    for index, dye in ipairs(profile.dyes) do
        local row = make_row(dye)
        local owned = false
        if row and resolved.items[dye.holder_id] and #dye.map_ids > 0 then
            pcall(function()
                owned = context.inventory:GetItemTypeCount(row) > 0
            end)
        end
        if owned then
            resolved.dye_rows[index] = row
        else
            add_missing(missing, missing_seen, "Dye", dye.label)
            resolved.blocked_dye_holders[dye.holder_id] = true
        end
    end
    for index, style in ipairs(profile.weapon_styles) do
        local row = make_row(style)
        local owned = false
        if row then
            pcall(function()
                owned = context.inventory:HasWeaponGlamour(row)
            end)
        end
        if owned then
            resolved.weapon_style_rows[index] = row
        else
            add_missing(missing, missing_seen, "Weapon style", style.label)
            resolved.block_weapon_styles = true
        end
    end
    for index, style in ipairs(profile.armor_styles) do
        local row = make_row(style)
        local owned = false
        if row then
            pcall(function()
                owned = context.inventory:HasArmorGlamour(row)
            end)
        end
        if owned then
            resolved.armor_style_rows[index] = row
        else
            add_missing(missing, missing_seen, "Armor style", style.label)
            resolved.block_armor_styles = true
        end
    end

    local target_signatures = target_talent_signatures(profile)
    for holder_id in pairs(target_signatures) do
        local holder = resolved.items[holder_id]
        if holder then
            local signature = current_talent_signature(context, holder)
            resolved.current_talent_signatures[holder_id] = signature
            if signature == nil then
                resolved.blocked_talent_holders[holder_id] = true
                add_missing(missing, missing_seen, "Talent host", holder_id)
            end
        end
    end

    local current_character = ""
    pcall(function()
        current_character = to_text(context.archetype.m_CurrentCharacter)
    end)
    local target_character = profile_character_row(profile)
    local current_nodes = nil
    if target_character ~= "" and target_character ~= current_character then
        resolved.block_archetype_nodes = true
        resolved.defer_archetype_nodes = profile.nodes_trusted ~= false
    else
        current_nodes = current_node_signature(context.archetype)
        resolved.current_node_signature = current_nodes
        if current_nodes == nil then
            resolved.block_archetype_nodes = true
            add_missing(missing, missing_seen, "Archetype tree", profile.character)
        elseif not resolved.block_archetype_nodes then
            for _, node in ipairs(profile.nodes) do
                if not archetype_node_exists(context.archetype, node) then
                    resolved.block_archetype_nodes = true
                    add_missing(missing, missing_seen, "Archetype node", node.node_id)
                end
            end
        end
    end

    local notices = {}
    for holder_id, target_signature in pairs(target_signatures) do
        local holder = resolved.items[holder_id]
        if holder
            and not resolved.block_all_talents
            and not resolved.blocked_talent_holders[holder_id]
            and resolved.current_talent_signatures[holder_id] ~= target_signature then
            notices[#notices + 1] = "Talent allocations will use Wayfinder's reset and upgrade operations."
            break
        end
    end
    if resolved.block_all_echos or next(resolved.blocked_echo_holders) then
        notices[#notices + 1] = "Echoes with incomplete saved data will be preserved."
    end
    if resolved.block_all_talents
        or next(resolved.blocked_talent_holders)
        or next(resolved.blocked_talent_pools) then
        notices[#notices + 1] = "Talent pools with incomplete saved data will be preserved."
    end
    if resolved.block_weapon_styles then
        notices[#notices + 1] = "Weapon styles will be preserved because the saved style set is incomplete."
    end
    if resolved.block_armor_styles then
        notices[#notices + 1] = "Armor styles will be preserved because the saved style set is incomplete."
    end
    if not resolved.dye_bridge_ready then
        notices[#notices + 1] = "Dyes will be preserved because the native dye bridge is not ready."
    elseif profile.dyes_trusted == false then
        notices[#notices + 1] = "Dyes will be preserved because the saved dye set needs recapture."
    elseif next(resolved.blocked_dye_holders) then
        notices[#notices + 1] = "Dye sets with incomplete saved data will be preserved."
    end
    if resolved.defer_archetype_nodes then
        notices[#notices + 1] = "The saved archetype tree will be validated after the target character equips and will reset only if every node is valid."
    elseif resolved.block_archetype_nodes then
        notices[#notices + 1] = "The archetype talent tree will be preserved because the saved node set cannot be verified."
    elseif current_nodes ~= target_node_signature(profile) then
        notices[#notices + 1] = "The archetype talent tree will reset before the saved nodes are applied."
    end
    return resolved, missing, notices
end

local function schedule_apply(delay, generation, callback)
    ExecuteWithDelay(delay, function()
        if generation ~= apply_generation then
            return
        end
        ExecuteInGameThread(function()
            if generation == apply_generation then
                callback()
            end
        end)
    end)
end

local function apply_items(profile, context, resolved)
    local ordered = {}
    for _, item in ipairs(profile.items) do
        ordered[#ordered + 1] = item
    end
    table.sort(ordered, function(left, right)
        local left_character = left.slot:lower():find("character", 1, true) and 0 or 1
        local right_character = right.slot:lower():find("character", 1, true) and 0 or 1
        if left_character ~= right_character then
            return left_character < right_character
        end
        return left.category < right.category
    end)
    for _, item in ipairs(ordered) do
        local handle = resolved.items[handle_key(item)]
        if handle then
            local ok, equipped = pcall(function()
                return context.inventory:TryEquipItem(handle, FName(item.slot))
            end)
            if not ok or equipped == false then
                log(string.format("Unable to equip category=%s item=%s", item.category, item.label))
            end
        end
    end
end

local function apply_echos(profile, context, resolved, generation)
    if resolved.block_all_echos then
        return
    end

    local target_holders = {}
    for _, item in ipairs(profile.items) do
        target_holders[handle_key(item)] = true
    end
    local current_slots = {}
    local read_ok, read_error = pcall(function()
        for holder_id in pairs(target_holders) do
            current_slots[holder_id] = {}
            local holder = resolved.items[holder_id]
            local entry = holder and get_item_entry(context.inventory, holder) or nil
            if not entry or not entry.Spec then
                resolved.blocked_echo_holders[holder_id] = true
                error("The equipped item data could not be resolved for its Echo slots.")
            end
            local slots_ok, slots_error = each_array(entry.Spec.FogSouls, function(index, echo_id)
                local echo_id_key = guid_key(echo_id)
                if echo_id_key ~= "" and echo_id_key ~= "0-0-0-0" then
                    current_slots[holder_id][#current_slots[holder_id] + 1] = index - 1
                end
            end)
            if not slots_ok then
                resolved.blocked_echo_holders[holder_id] = true
                error(slots_error)
            end
        end
    end)
    if not read_ok then
        log("Echoes were preserved because their current slots could not be read: " .. tostring(read_error))
        return
    end

    local blocked = {}
    for holder_id in pairs(target_holders) do
        local holder = resolved.items[holder_id]
        if holder and not resolved.blocked_echo_holders[holder_id] then
            local slots = current_slots[holder_id]
            if slots == nil then
                blocked[holder_id] = true
                log("Echoes were preserved for an item whose current loadout entry could not be read.")
            else
                for _, slot in ipairs(slots) do
                    local detached = pcall(function()
                        context.inventory:SERVER_FogSoul_Detach(holder.ID, slot)
                    end)
                    if not detached then
                        blocked[holder_id] = true
                        log(string.format("Unable to detach an Echo slot=%d. This item's remaining Echo changes were skipped.", slot))
                        break
                    end
                end
            end
        end
    end

    schedule_apply(250, generation, function()
        local fresh = get_context()
        if not fresh then
            return
        end
        for index, echo in ipairs(profile.echos) do
            local holder = resolved.items[echo.holder_id]
            local echo_handle = resolved.echos[index]
            if holder
                and echo_handle
                and not blocked[echo.holder_id]
                and not resolved.blocked_echo_holders[echo.holder_id] then
                local ok = pcall(function()
                    fresh.inventory:SERVER_FogSoul_Attach(holder.ID, echo_handle.ID, echo.slot)
                end)
                if not ok then
                    log(string.format("Unable to attach Echo item=%s slot=%d", echo.label, echo.slot))
                end
            end
        end
    end)
end

local function apply_abilities(profile, context, resolved)
    for index, ability in ipairs(profile.abilities) do
        local holder = resolved.items[ability.holder_id]
        if holder and resolved.ability_rows[index] then
            local ok, selected = pcall(function()
                return context.inventory:TrySelectAbilityForItem(holder, ability.slot, FName(ability.row))
            end)
            if not ok or selected == false then
                log(string.format("Unable to select ability item=%s slot=%d", ability.label, ability.slot))
            end
        end
    end
end

local function apply_item_talents(profile, context, resolved, generation)
    if resolved.block_all_talents then
        return
    end
    local groups = {}
    local target_signatures = target_talent_signatures(profile)
    local changed_holders = {}
    for holder_id, target_signature in pairs(target_signatures) do
        local holder = resolved.items[holder_id]
        local current_signature = holder and current_talent_signature(context, holder) or nil
        if holder
            and current_signature ~= nil
            and not resolved.blocked_talent_holders[holder_id]
            and current_signature ~= target_signature then
            changed_holders[holder_id] = true
            local entry = get_item_entry(context.inventory, holder)
            if entry and entry.Spec then
                local holder_groups = {}
                local talents_ok = each_array(entry.Spec.TalentItems, function(_, current_talent)
                    local points = to_number(current_talent.NumPointsSpent, 0)
                    if points > 0 then
                        local pool_snapshot = row_snapshot(current_talent.TalentPool)
                        if not pool_snapshot then
                            error("Wayfinder returned an allocated talent without a valid pool.")
                        end
                        local pool = make_row(pool_snapshot)
                        if not pool then
                            error("Wayfinder's talent pool data table is unavailable.")
                        end
                        local pool_key = holder_id .. "|" .. pool_snapshot.table_path .. "|" .. pool_snapshot.row
                        if not resolved.blocked_talent_pools[pool_key] then
                            holder_groups[pool_key] = holder_groups[pool_key] or {
                                holder = holder,
                                pool = pool,
                                talents = {}
                            }
                        end
                    end
                end)
                if talents_ok then
                    for pool_key, group in pairs(holder_groups) do
                        groups[pool_key] = group
                    end
                else
                    changed_holders[holder_id] = nil
                    log("A talent allocation was preserved because its current pools could not be read.")
                end
            else
                changed_holders[holder_id] = nil
                log("A talent allocation was preserved because its current item data could not be read.")
            end
        end
    end
    for index, talent in ipairs(profile.talents) do
        local pool = resolved.talent_pools[index]
        local holder = resolved.items[talent.holder_id]
        local talent_handle = resolved.talents[index]
        local pool_key = talent_pool_key(talent)
        if changed_holders[talent.holder_id]
            and pool
            and holder
            and talent_handle
            and not resolved.blocked_talent_pools[pool_key] then
            groups[pool_key] = groups[pool_key] or {
                holder = holder,
                pool = pool,
                talents = {}
            }
            groups[pool_key].talents[#groups[pool_key].talents + 1] = {
                record = talent,
                handle = talent_handle
            }
        end
    end
    local delay = 350
    for _, group in pairs(groups) do
        local operation_group = group
        local reset_ok, reset_started = pcall(function()
            return context.inventory:TryToResetTalentPoints(operation_group.holder, operation_group.pool)
        end)
        if reset_ok and reset_started == true then
            for _, talent in ipairs(operation_group.talents) do
                for _ = 1, talent.record.points do
                    local operation = talent
                    schedule_apply(delay, generation, function()
                        local fresh = get_context()
                        if fresh then
                            local ok, upgraded = pcall(function()
                                return fresh.inventory:TryToUpgradeTalent(operation_group.holder, operation.handle)
                            end)
                            if not ok or upgraded == false then
                                log("Unable to upgrade talent item=" .. operation.record.label)
                            end
                        end
                    end)
                    delay = delay + 100
                end
            end
        else
            log("Unable to reset a talent pool. The saved talent allocation was skipped.")
        end
    end
end

local function apply_archetype_nodes(profile, context, resolved, generation)
    if not is_valid(context.archetype) or resolved.block_archetype_nodes then
        return
    end
    local current_signature = current_node_signature(context.archetype)
    if current_signature == nil then
        log("The archetype talent tree was preserved because its current nodes could not be read.")
        return
    end
    if current_signature == target_node_signature(profile) then
        return
    end
    for _, node in ipairs(profile.nodes) do
        if not archetype_node_exists(context.archetype, node) then
            log("The archetype talent tree was preserved because a saved node is unavailable: " .. node.node_id)
            return
        end
    end
    local nodes = {}
    for _, node in ipairs(profile.nodes) do
        nodes[#nodes + 1] = node
    end
    table.sort(nodes, function(left, right)
        if left.tree_index ~= right.tree_index then
            return left.tree_index < right.tree_index
        end
        return left.tree_type < right.tree_type
    end)
    local ok = pcall(function()
        context.archetype:SERVER_TryRespecArchetypeTree()
    end)
    if not ok then
        log("Unable to reset the archetype talent tree.")
        return
    end
    local delay = 500
    for _, node in ipairs(nodes) do
        local operation = node
        schedule_apply(delay, generation, function()
            local fresh = get_context()
            if fresh and is_valid(fresh.archetype) then
                local purchase_ok = pcall(function()
                    fresh.archetype:SERVER_TryPurchaseArchetypeNode(FName(operation.node_id))
                end)
                if not purchase_ok then
                    log("Unable to purchase talent node=" .. operation.node_id)
                end
            end
        end)
        delay = delay + 100
    end
end

local function apply_styles(profile, context, resolved)
    if resolved.block_weapon_styles and resolved.block_armor_styles then
        return
    end
    local ok, loadout_id = pcall(function()
        return context.loadout:GetCurrentLoadoutIdData()
    end)
    if not ok or not loadout_id then
        log("Unable to read the active style loadout identifier.")
        return
    end
    local armor_reset = false
    if not resolved.block_armor_styles then
        local reset_ok, reset_result = pcall(function()
            return context.loadout:TryResetAllArmorGlamours(loadout_id)
        end)
        armor_reset = reset_ok and reset_result == true
        if not armor_reset then
            log("Unable to reset the saved armor style set before applying it.")
        end
    end
    local weapon_resets = {}
    if not resolved.block_weapon_styles then
        for subclass = 1, 12 do
            local reset_ok, reset_result = pcall(function()
                return context.loadout:TryResetWeaponGlamour(subclass, loadout_id)
            end)
            weapon_resets[subclass] = reset_ok and reset_result == true
            if not weapon_resets[subclass] then
                log(string.format("Unable to reset weapon style subclass=%d before applying the saved style set.", subclass))
            end
        end
    end
    if not resolved.block_weapon_styles then
        for index, style in ipairs(profile.weapon_styles) do
            local row = resolved.weapon_style_rows[index]
            if row and weapon_resets[style.weapon_subclass] then
                local style_ok, applied = pcall(function()
                    return context.loadout:TryApplyWeaponGlamour(style.weapon_subclass, row, loadout_id)
                end)
                if not style_ok or applied == false then
                    log("Unable to apply weapon style=" .. style.label)
                end
            end
        end
    end
    if not resolved.block_armor_styles and armor_reset then
        for index, style in ipairs(profile.armor_styles) do
            local row = resolved.armor_style_rows[index]
            if row then
                local style_ok, applied = pcall(function()
                    return context.loadout:TryApplyArmorGlamour(style.armor_slot, row, loadout_id)
                end)
                if not style_ok or applied == false then
                    log("Unable to apply armor style=" .. style.label)
                end
            end
        end
    end
end

local function apply_dyes(profile, context, resolved)
    if resolved.block_all_dyes or type(LoadoutsNativeApplyDye) ~= "function" then
        return
    end
    local dye_ready, dye_error = native_dye_ready()
    if not dye_ready then
        log("Dyes were preserved because the native dye bridge is not ready: " .. dye_error)
        return
    end
    local inventory_path = object_path(context.inventory)
    if inventory_path == "" then
        log("Dyes were preserved because the inventory object path is unavailable.")
        return
    end

    local groups = {}
    for holder_id, holder in pairs(resolved.items) do
        if not resolved.blocked_dye_holders[holder_id] then
            groups[holder_id] = {
                handle = holder,
                record = resolved.item_records[holder_id],
                dyes = {}
            }
        end
    end
    for index, dye in ipairs(profile.dyes) do
        local group = groups[dye.holder_id]
        if group and resolved.dye_rows[index] then
            group.dyes[#group.dyes + 1] = dye
        end
    end
    for _, group in pairs(groups) do
        if group.record then
            local reset_ok, reset_result = pcall(function()
                return context.inventory:ResetDyes(group.handle)
            end)
            if not reset_ok or reset_result == false then
                log("Unable to reset a complete saved dye set. Its dyes were skipped.")
            else
                for _, dye in ipairs(group.dyes) do
                    local bridge_ok, applied, bridge_message = pcall(
                        LoadoutsNativeApplyDye,
                        inventory_path,
                        group.record.table_path,
                        group.record.row,
                        group.record.a,
                        group.record.b,
                        group.record.c,
                        group.record.d,
                        dye.table_path,
                        dye.row,
                        table.unpack(dye.map_ids)
                    )
                    if not bridge_ok or applied ~= true then
                        log(string.format(
                            "Unable to apply dye=%s error=%s",
                            dye.label,
                            tostring(bridge_ok and bridge_message or applied)
                        ))
                    end
                end
            end
        end
    end
end

local function copy_keys(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if value then
            result[key] = true
        end
    end
    return result
end

local function approval_policy(resolved)
    return {
        block_all_echos = resolved.block_all_echos,
        block_all_talents = resolved.block_all_talents,
        block_all_dyes = resolved.block_all_dyes,
        block_weapon_styles = resolved.block_weapon_styles,
        block_armor_styles = resolved.block_armor_styles,
        block_archetype_nodes = resolved.block_archetype_nodes,
        defer_archetype_nodes = resolved.defer_archetype_nodes,
        blocked_echo_holders = copy_keys(resolved.blocked_echo_holders),
        blocked_talent_holders = copy_keys(resolved.blocked_talent_holders),
        blocked_talent_pools = copy_keys(resolved.blocked_talent_pools),
        blocked_dye_holders = copy_keys(resolved.blocked_dye_holders)
    }
end

local function apply_approval_policy(resolved, approved)
    resolved.block_all_echos = resolved.block_all_echos or approved.block_all_echos
    resolved.block_all_talents = resolved.block_all_talents or approved.block_all_talents
    resolved.block_all_dyes = resolved.block_all_dyes or approved.block_all_dyes
    resolved.block_weapon_styles = resolved.block_weapon_styles or approved.block_weapon_styles
    resolved.block_armor_styles = resolved.block_armor_styles or approved.block_armor_styles
    if approved.block_archetype_nodes and not approved.defer_archetype_nodes then
        resolved.block_archetype_nodes = true
        resolved.defer_archetype_nodes = false
    end
    for key in pairs(approved.blocked_echo_holders) do
        resolved.blocked_echo_holders[key] = true
    end
    for key in pairs(approved.blocked_talent_holders) do
        resolved.blocked_talent_holders[key] = true
    end
    for key in pairs(approved.blocked_talent_pools) do
        resolved.blocked_talent_pools[key] = true
    end
    for key in pairs(approved.blocked_dye_holders) do
        resolved.blocked_dye_holders[key] = true
    end
end

local function apply_secondary(profile, generation, approved)
    local context, context_error = get_context()
    if not context then
        log(context_error)
        return
    end
    local resolved, missing = resolve_profile(profile, context)
    apply_approval_policy(resolved, approved)
    if #missing > 0 then
        log(string.format("Loadout changed during application; skipping %d unavailable parts", #missing))
    end
    apply_styles(profile, context, resolved)
    apply_dyes(profile, context, resolved)
    apply_abilities(profile, context, resolved)
    apply_echos(profile, context, resolved, generation)
    apply_item_talents(profile, context, resolved, generation)
    if resolved.defer_archetype_nodes then
        schedule_apply(1000, generation, function()
            local fresh = get_context()
            if fresh then
                local fresh_resolved = resolve_profile(profile, fresh)
                apply_archetype_nodes(profile, fresh, fresh_resolved, generation)
            end
        end)
    else
        apply_archetype_nodes(profile, context, resolved, generation)
    end
    schedule_apply(5000, generation, function()
        local fresh = get_context()
        if fresh then
            local save_ok, save_error = pcall(function()
                fresh.loadout:SaveCurrentLoadout()
            end)
            if save_ok then
                log("Loadout application complete: " .. profile.name)
            else
                log("Unable to save the applied loadout: " .. tostring(save_error))
            end
        end
    end)
end

local function apply_profile(profile, resolved)
    local context, context_error = get_context()
    if not context then
        log(context_error)
        return
    end
    apply_generation = apply_generation + 1
    local generation = apply_generation
    local approved = approval_policy(resolved)
    apply_items(profile, context, resolved)
    schedule_apply(600, generation, function()
        apply_secondary(profile, generation, approved)
    end)
    log("Applying loadout=" .. profile.name)
end

local function warning_body(profile, missing, notices)
    local lines = {
        string.format("Loadout: %s", profile.name)
    }
    if #missing > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Unavailable parts:"
        local limit = math.min(#missing, 16)
        for index = 1, limit do
            lines[#lines + 1] = "- " .. missing[index]
        end
        if #missing > limit then
            lines[#lines + 1] = string.format("- %d additional parts", #missing - limit)
        end
    end
    if #notices > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Other changes:"
        for _, notice in ipairs(notices) do
            lines[#lines + 1] = "- " .. notice
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Confirm to apply available parts, or cancel to leave the loadout unchanged."
    return table.concat(lines, "\n")
end

local function queue_confirmation(profile, missing, notices)
    if pending_confirmation then
        return false, "A loadout confirmation is already pending."
    end
    pending_confirmation = {
        profile = profile,
        profile_name = profile.name,
        body = warning_body(profile, missing, notices),
        missing = missing,
        notices = notices
    }
    return true
end

local function pending_confirmation_data()
    if not pending_confirmation then
        return nil
    end
    local missing = {}
    local notices = {}
    for index, value in ipairs(pending_confirmation.missing) do
        missing[index] = value
    end
    for index, value in ipairs(pending_confirmation.notices) do
        notices[index] = value
    end
    return {
        profile_name = pending_confirmation.profile_name,
        body = pending_confirmation.body,
        missing = missing,
        notices = notices,
        missing_count = #missing,
        notice_count = #notices
    }
end

local function confirm_pending(output_device)
    if not pending_confirmation then
        local message = "No loadout confirmation is pending."
        output_log(output_device, message)
        return false, message
    end
    local request = pending_confirmation
    local profile = request.profile
    if profiles[profile_key(profile.name)] ~= profile then
        pending_confirmation = nil
        local message = "The pending loadout no longer exists. Nothing was applied."
        output_log(output_device, message)
        return false, message
    end
    local capture_issue = profile_capture_issue(profile)
    if capture_issue then
        pending_confirmation = nil
        local message = "Loadout cannot be applied: " .. capture_issue
        output_log(output_device, message)
        return false, message
    end
    local context, context_error = get_context()
    if not context then
        output_log(output_device, context_error)
        return false, context_error
    end
    local resolved, missing, notices = resolve_profile(profile, context)
    local fresh_body = warning_body(profile, missing, notices)
    if fresh_body ~= request.body then
        pending_confirmation = {
            profile = profile,
            profile_name = profile.name,
            body = fresh_body,
            missing = missing,
            notices = notices
        }
        local message = "Loadout conditions changed. Review the updated confirmation before applying."
        output_log(output_device, message)
        return false, message
    end
    pending_confirmation = nil
    apply_profile(profile, resolved)
    local message = "Loadout application started: " .. profile.name
    output_log(output_device, message)
    return true, message
end

local function cancel_pending(output_device)
    if not pending_confirmation then
        local message = "No loadout confirmation is pending."
        output_log(output_device, message)
        return false, message
    end
    local name = pending_confirmation.profile_name
    pending_confirmation = nil
    local message = "Loadout application canceled: " .. name
    output_log(output_device, message)
    return true, message
end

local function request_apply(name, output_device)
    if pending_confirmation then
        local message = "Resolve the pending loadout confirmation before starting another application."
        output_log(output_device, message)
        return false, message
    end
    local profile = profiles[profile_key(name)]
    if not profile then
        local message = "Loadout not found: " .. name
        output_log(output_device, message)
        return false, message
    end
    local capture_issue = profile_capture_issue(profile)
    if capture_issue then
        local message = "Loadout cannot be applied: " .. capture_issue
        output_log(output_device, message)
        return false, message
    end
    local context, context_error = get_context()
    if not context then
        output_log(output_device, context_error)
        return false, context_error
    end
    local resolved, missing, notices = resolve_profile(profile, context)
    if #missing > 0 or #notices > 0 then
        local shown, warning_error = queue_confirmation(profile, missing, notices)
        if shown then
            local message = string.format(
                "Confirmation required for loadout=%s unavailable=%d notices=%d. Use the Loadouts page or LoadoutConfirm.",
                profile.name,
                #missing,
                #notices
            )
            output_log(output_device, message)
            return true, message
        else
            output_log(output_device, warning_error)
            return false, warning_error
        end
    end
    apply_profile(profile, resolved)
    local message = "Loadout application started: " .. profile.name
    output_log(output_device, message)
    return true, message
end

local function save_named_profile(name, output_device)
    local capture_ready, capture_error = native_capture_ready()
    if not capture_ready then
        output_log(output_device, capture_error)
        return false, capture_error
    end
    local context, context_error = get_context()
    if not context then
        output_log(output_device, context_error)
        return false, context_error
    end
    local profile, capture_error = capture_profile(name, context)
    if not profile then
        output_log(output_device, capture_error)
        return false, capture_error
    end
    local key = profile_key(name)
    local previous = profiles[key]
    profiles[key] = profile
    local saved, save_error = persist_database()
    if not saved then
        profiles[key] = previous
        local message = "Unable to save the loadout database: " .. save_error
        output_log(output_device, message)
        return false, message
    end
    local counts = profile_counts(profile)
    local message = string.format(
        "Saved loadout=%s character=%s armor=%d weapons=%d style=%d echos=%d talents=%d abilities=%d",
        profile.name,
        profile.character,
        counts.armor,
        counts.weapons,
        counts.style,
        counts.echos,
        counts.talents,
        counts.abilities
    )
    output_log(output_device, message)
    return true, message
end

local function delete_named_profile(name, output_device)
    local key = profile_key(name)
    local previous = profiles[key]
    if not previous then
        local message = "Loadout not found: " .. name
        output_log(output_device, message)
        return false, message
    end
    profiles[key] = nil
    local saved, save_error = persist_database()
    if not saved then
        profiles[key] = previous
        local message = "Unable to save the loadout database: " .. save_error
        output_log(output_device, message)
        return false, message
    end
    local message = "Deleted loadout: " .. previous.name
    output_log(output_device, message)
    return true, message
end

local function rename_named_profile(old_name, new_name, output_device)
    local old_key = profile_key(old_name)
    local new_key = profile_key(new_name)
    local profile = profiles[old_key]
    if not profile then
        local message = "Loadout not found: " .. old_name
        output_log(output_device, message)
        return false, message
    end
    if old_key ~= new_key and profiles[new_key] then
        local message = "A loadout already uses this name: " .. new_name
        output_log(output_device, message)
        return false, message
    end

    local previous_name = profile.name
    profiles[old_key] = nil
    profile.name = new_name
    profiles[new_key] = profile
    local saved, save_error = persist_database()
    if not saved then
        profiles[new_key] = nil
        profile.name = previous_name
        profiles[old_key] = profile
        local message = "Unable to save the loadout database: " .. save_error
        output_log(output_device, message)
        return false, message
    end
    local message = string.format("Renamed loadout=%s to=%s", previous_name, new_name)
    output_log(output_device, message)
    return true, message
end

local function profile_summaries()
    local result = {}
    for _, profile in ipairs(sorted_profiles()) do
        local counts = profile_counts(profile)
        local issue = profile_capture_issue(profile)
        result[#result + 1] = {
            name = profile.name,
            character = profile.character,
            valid = issue == nil,
            issue = issue or "",
            unverified_items = issue and #profile.items or 0,
            armor = counts.armor,
            weapons = counts.weapons,
            style = counts.style,
            echos = counts.echos,
            talents = counts.talents,
            abilities = counts.abilities
        }
    end
    return result
end

local function list_profiles(output_device)
    local summaries = profile_summaries()
    if #summaries == 0 then
        output_log(output_device, "No loadouts are saved.")
        return
    end
    output_log(output_device, string.format("Saved loadouts: %d", #summaries))
    for _, profile in ipairs(summaries) do
        if profile.valid then
            output_log(output_device, string.format(
                "%s | %s | armor=%d weapons=%d style=%d echos=%d talents=%d abilities=%d",
                profile.name,
                profile.character,
                profile.armor,
                profile.weapons,
                profile.style,
                profile.echos,
                profile.talents,
                profile.abilities
            ))
        else
            output_log(output_device, string.format(
                "%s | RECAPTURE REQUIRED | unverified_items=%d",
                profile.name,
                profile.unverified_items
            ))
        end
    end
end

local function register_command(name, callback)
    local ok, command_error = pcall(function()
        RegisterConsoleCommandHandler(name, callback)
    end)
    if not ok then
        log(string.format("Unable to register command=%s error=%s", name, tostring(command_error)))
    end
end

load_config()
load_database()

register_command("LoadoutSave", function(_, parameters, output_device)
    local name = clean_profile_name(parameters)
    if name == "" then
        output_log(output_device, "Use: LoadoutSave <name>")
        return true
    end
    save_named_profile(name, output_device)
    return true
end)

register_command("LoadoutApply", function(_, parameters, output_device)
    local name = clean_profile_name(parameters)
    if name == "" then
        output_log(output_device, "Use: LoadoutApply <name>")
        return true
    end
    request_apply(name, output_device)
    return true
end)

register_command("LoadoutConfirm", function(_, _, output_device)
    confirm_pending(output_device)
    return true
end)

register_command("LoadoutCancel", function(_, _, output_device)
    cancel_pending(output_device)
    return true
end)

register_command("LoadoutDelete", function(_, parameters, output_device)
    local name = clean_profile_name(parameters)
    if name == "" then
        output_log(output_device, "Use: LoadoutDelete <name>")
        return true
    end
    delete_named_profile(name, output_device)
    return true
end)

register_command("LoadoutRename", function(_, parameters, output_device)
    if #parameters < 2 then
        output_log(output_device, "Use: LoadoutRename <old name> <new name>")
        return true
    end
    local old_name = clean_profile_name({ parameters[1] })
    local new_parameters = {}
    for index = 2, #parameters do
        new_parameters[#new_parameters + 1] = parameters[index]
    end
    local new_name = clean_profile_name(new_parameters)
    if old_name == "" or new_name == "" then
        output_log(output_device, "Use: LoadoutRename <old name> <new name>")
        return true
    end
    rename_named_profile(old_name, new_name, output_device)
    return true
end)

register_command("LoadoutList", function(_, _, output_device)
    list_profiles(output_device)
    return true
end)

if QUICK_KEYS_ENABLED then
    RegisterKeyBind(Key.F5, { ModifierKey.CONTROL }, function()
        ExecuteInGameThread(function()
            save_named_profile(QUICK_PROFILE_NAME)
        end)
    end)
    RegisterKeyBind(Key.F6, { ModifierKey.CONTROL }, function()
        ExecuteInGameThread(function()
            request_apply(QUICK_PROFILE_NAME)
        end)
    end)
end

local loadout_ui = nil
if LOADOUT_UI_ENABLED then
    local module_ok, module_result = pcall(dofile, "Mods/Loadouts/Scripts/loadout_ui.lua")
    if module_ok and type(module_result) == "table" then
        loadout_ui = module_result
        local start_ok, started_ui = pcall(function()
            return loadout_ui.start({
                log = log,
                context = get_context,
                clean_name = function(name)
                    return clean_profile_name({ name })
                end,
                list = profile_summaries,
                save = save_named_profile,
                apply = request_apply,
                pending_confirmation = pending_confirmation_data,
                confirm = confirm_pending,
                cancel = cancel_pending,
                delete = delete_named_profile,
                rename = rename_named_profile
            })
        end)
        if not start_ok or not started_ui then
            log("Loadouts UI bridge could not start: " .. tostring(start_ok and "initialization failed" or started_ui))
            loadout_ui = nil
        end
    else
        log("Loadouts UI module could not load: " .. tostring(module_result))
    end
end

register_command("LoadoutUI", function(_, _, output_device)
    if not loadout_ui then
        output_log(output_device, "The Loadouts UI is unavailable. Check Loadouts.pak and UE4SS.log.")
        return true
    end
    ExecuteInGameThread(function()
        local _, message = loadout_ui.open()
        output_log(nil, message)
    end)
    return true
end)

if loadout_ui then
    RegisterKeyBind(Key.F7, { ModifierKey.CONTROL }, function()
        ExecuteInGameThread(function()
            local ok, message = loadout_ui.open()
            if not ok then
                log(message)
            end
        end)
    end)
end

log(string.format(
    "Mod loaded profiles=%d quick_profile=%s quick_keys=%s ui=%s",
    #sorted_profiles(),
    QUICK_PROFILE_NAME,
    QUICK_KEYS_ENABLED and "enabled" or "disabled",
    loadout_ui and "enabled" or "disabled"
))
