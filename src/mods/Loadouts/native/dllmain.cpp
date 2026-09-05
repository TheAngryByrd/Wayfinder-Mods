#include <Windows.h>
#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <deque>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <memory>
#include <mutex>
#include <span>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace RC::LuaMadeSimple
{
class Lua;
}

namespace RC::Unreal
{
class UClass;
class UFunction;
class UObject;
class UStruct;
}

#if defined(LOADOUTS_DEBUG_CONFIGURATION) || defined(_DEBUG) || _ITERATOR_DEBUG_LEVEL != 0
#error LoadoutsEventRelay requires the Release MSVC standard-library ABI used by UE4SS 3.0.1.
#endif

namespace
{
enum class RelayKind
{
    Focus,
    PageRemoved,
};

struct RelayEvent
{
    RelayKind kind{};
    std::uintptr_t context{};
    std::uintptr_t value{};
    std::uint64_t generation{};
};

using ProcessEventCallback = std::function<void(
    RC::Unreal::UObject*,
    RC::Unreal::UFunction*,
    void*)>;
using RegisterProcessEventPreCallbackFn = void(__cdecl*)(ProcessEventCallback);
using StaticFindObjectFn = RC::Unreal::UObject*(__cdecl*)(
    RC::Unreal::UClass*,
    RC::Unreal::UObject*,
    const wchar_t*,
    bool);
using ExecuteLuaInModFn = const char*(__cdecl*)(const char*, const char*, char*);
using LuaCallback = int(__cdecl*)(const RC::LuaMadeSimple::Lua&);
using LuaRegisterFunctionFn = void(__fastcall*)(
    const RC::LuaMadeSimple::Lua*,
    const std::string&,
    const LuaCallback&);
using LuaGetStackSizeFn = int(__fastcall*)(const RC::LuaMadeSimple::Lua*);
using LuaIsStringFn = bool(__fastcall*)(const RC::LuaMadeSimple::Lua*, int);
using LuaGetStringFn = std::string_view(__fastcall*)(const RC::LuaMadeSimple::Lua*, int);
using LuaIsIntegerFn = bool(__fastcall*)(const RC::LuaMadeSimple::Lua*, int);
using LuaGetIntegerFn = std::int64_t(__fastcall*)(const RC::LuaMadeSimple::Lua*, int);
using LuaSetBoolFn = void(__fastcall*)(const RC::LuaMadeSimple::Lua*, bool);
using LuaSetStringFn = void(__fastcall*)(const RC::LuaMadeSimple::Lua*, std::string_view);
using ProcessEventFn = void(__fastcall*)(
    RC::Unreal::UObject*,
    RC::Unreal::UFunction*,
    void*);
using IsAFn = bool(__fastcall*)(const RC::Unreal::UObject*, RC::Unreal::UClass*);
using InitializeStructFn = void(__fastcall*)(const RC::Unreal::UStruct*, void*, int);
using DestroyStructFn = void(__fastcall*)(const RC::Unreal::UStruct*, void*, int);
using UFunctionUInt16GetterFn = const std::uint16_t&(__fastcall*)(
    const RC::Unreal::UFunction*);
using UObjectGetPathNameFn = void(__fastcall*)(
    const RC::Unreal::UObject*,
    RC::Unreal::UObject*,
    std::wstring&);

struct FNameData
{
    std::uint32_t comparison_index{};
    std::uint32_t number{};
};

using FNameConstructorFn = FNameData*(__fastcall*)(FNameData*, const wchar_t*, int, void*);
using FNameToStringFn = std::wstring(__fastcall*)(const FNameData*);

struct DataTableRowHandle
{
    void* data_table{};
    FNameData row_name{};
};

struct Guid
{
    std::uint32_t a{};
    std::uint32_t b{};
    std::uint32_t c{};
    std::uint32_t d{};
};

struct InventoryItemHandle
{
    DataTableRowHandle data{};
    Guid id{};
};

struct ScriptArray
{
    void* data{};
    std::int32_t count{};
    std::int32_t capacity{};
};

struct ApplyDyeParameters
{
    InventoryItemHandle item{};
    DataTableRowHandle dye{};
    ScriptArray map_ids{};
    bool return_value{};
    std::array<std::byte, 7> padding{};
};

struct DyeApplication
{
    DataTableRowHandle dye_data{};
    ScriptArray map_ids{};
};

struct AbilitySlotEntry
{
    ScriptArray applied_ability_handles{};
    DataTableRowHandle current_ability_data{};
    std::uint8_t is_set{};
    std::array<std::byte, 7> padding{};
};

struct TalentItemSpec
{
    InventoryItemHandle talent_item{};
    std::int32_t points{};
    std::array<std::byte, 4> padding{};
};

struct InventoryItemSpecCapture
{
    std::array<std::byte, 0x20> before_slot_name{};
    FNameData equipped_to_slot_name{};
    std::array<std::byte, 0x8> before_fog_souls{};
    ScriptArray fog_souls{};
    std::array<std::byte, 0x38> before_dyes{};
    ScriptArray dyes{};
    std::array<std::byte, 0x18> before_ability_slots{};
    ScriptArray ability_slots{};
    std::array<std::byte, 0x28> before_talent_items{};
    ScriptArray talent_items{};
    std::array<std::byte, 0x18> before_generated_slots{};
    ScriptArray generated_slots{};
};

struct InventoryItemEntryCapture
{
    InventoryItemHandle handle{};
    std::int32_t count{};
    std::array<std::byte, 4> padding{};
    InventoryItemSpecCapture spec{};
};

struct OwnedRow
{
    std::string table_path{};
    std::string row{};
};

struct OwnedHandle
{
    OwnedRow data{};
    Guid id{};
};

struct OwnedDye
{
    OwnedRow dye{};
    std::vector<std::int32_t> map_ids{};
};

struct OwnedAbility
{
    bool is_set{};
    OwnedRow ability{};
};

struct OwnedTalent
{
    OwnedHandle talent{};
    std::int32_t points{};
    OwnedRow pool{};
};

struct OwnedEcho
{
    std::size_t slot{};
    OwnedHandle item{};
};

struct OwnedCapture
{
    OwnedHandle item{};
    std::string slot_name{};
    std::int32_t generated_slot_count{};
    std::vector<OwnedDye> dyes{};
    std::vector<OwnedAbility> abilities{};
    std::vector<OwnedTalent> talents{};
    std::vector<Guid> fog_souls{};
    std::vector<OwnedEcho> echos{};
};

static_assert(sizeof(FNameData) == 0x8);
static_assert(sizeof(DataTableRowHandle) == 0x10);
static_assert(sizeof(InventoryItemHandle) == 0x20);
static_assert(sizeof(ScriptArray) == 0x10);
static_assert(sizeof(ApplyDyeParameters) == 0x48);
static_assert(sizeof(DyeApplication) == 0x20);
static_assert(sizeof(AbilitySlotEntry) == 0x28);
static_assert(sizeof(TalentItemSpec) == 0x28);
static_assert(offsetof(InventoryItemEntryCapture, spec) == 0x28);
static_assert(offsetof(InventoryItemSpecCapture, equipped_to_slot_name) == 0x20);
static_assert(offsetof(InventoryItemSpecCapture, fog_souls) == 0x30);
static_assert(offsetof(InventoryItemSpecCapture, dyes) == 0x78);
static_assert(offsetof(InventoryItemSpecCapture, ability_slots) == 0xA0);
static_assert(offsetof(InventoryItemSpecCapture, talent_items) == 0xD8);
static_assert(offsetof(InventoryItemSpecCapture, generated_slots) == 0x100);

constexpr auto focus_event_path = L"/Script/AirshipUI.AirshipMenuPage:OnChildFocused";
constexpr auto removed_event_path = L"/Script/AirshipUI.AirshipMenuPage:OnRemovedFromPlayerUI";
constexpr auto apply_dye_event_path =
    L"/Script/Wayfinder.PlayerInventoryComponent:ApplyDyeToItem";
constexpr auto find_item_event_path = L"/Script/Wayfinder.PlayerInventoryComponent:FindItem";
constexpr auto find_item_from_id_event_path =
    L"/Script/Wayfinder.PlayerInventoryComponent:FindItemFromId";
constexpr auto talent_pool_event_path =
    L"/Script/Wayfinder.PlayerInventoryComponent:GetTalentPoolForTalent";
constexpr auto inventory_class_path = L"/Script/Wayfinder.PlayerInventoryComponent";
constexpr auto data_table_class_path = L"/Script/Engine.DataTable";
constexpr std::size_t relay_queue_capacity = 256;
constexpr std::size_t capture_array_limit = 64;
constexpr std::size_t find_item_parameter_size = 0x1D0;
constexpr std::size_t find_item_return_offset = 0x28;
constexpr std::size_t find_item_from_id_parameter_size = 0x1C0;
constexpr std::size_t find_item_from_id_return_offset = 0x18;
constexpr std::size_t talent_pool_parameter_size = 0x50;
constexpr std::size_t talent_pool_return_offset = 0x40;

std::atomic<void*> g_focus_event{};
std::atomic<void*> g_removed_event{};
std::atomic<void*> g_apply_dye_event{};
std::atomic<void*> g_find_item_event{};
std::atomic<void*> g_find_item_from_id_event{};
std::atomic<void*> g_talent_pool_event{};
std::atomic<void*> g_inventory_class{};
std::atomic<void*> g_data_table_class{};
std::atomic<bool> g_running{};
std::atomic<bool> g_callback_registered{};
std::atomic<bool> g_bridge_registered{};
std::atomic<bool> g_module_pinned{};
std::atomic<bool> g_initialized{};
std::atomic<std::uint64_t> g_generation{};
std::atomic<std::uint64_t> g_next_resolve{};
std::atomic<std::uint64_t> g_dropped_events{};
StaticFindObjectFn g_static_find_object{};
ExecuteLuaInModFn g_execute_lua{};
LuaRegisterFunctionFn g_lua_register_function{};
LuaGetStackSizeFn g_lua_get_stack_size{};
LuaIsStringFn g_lua_is_string{};
LuaGetStringFn g_lua_get_string{};
LuaIsIntegerFn g_lua_is_integer{};
LuaGetIntegerFn g_lua_get_integer{};
LuaSetBoolFn g_lua_set_bool{};
LuaSetStringFn g_lua_set_string{};
ProcessEventFn g_process_event{};
IsAFn g_is_a{};
FNameConstructorFn g_fname_constructor{};
FNameToStringFn g_fname_to_string{};
UObjectGetPathNameFn g_get_path_name{};
InitializeStructFn g_initialize_struct{};
DestroyStructFn g_destroy_struct{};
UFunctionUInt16GetterFn g_get_parms_size{};
UFunctionUInt16GetterFn g_get_return_value_offset{};
std::mutex g_log_mutex;
std::mutex g_event_mutex;
std::deque<RelayEvent> g_events;

std::filesystem::path log_path()
{
    HMODULE module{};
    if (!GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(&g_running),
            &module))
    {
        return {};
    }
    std::array<wchar_t, MAX_PATH> path{};
    if (!GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size())))
    {
        return {};
    }
    return std::filesystem::path(path.data()).parent_path().parent_path() / L"LoadoutsNative.log";
}

void log(const std::string& message) noexcept
{
    try
    {
        std::lock_guard lock(g_log_mutex);
        std::ofstream file(log_path(), std::ios::app);
        if (file)
        {
            file << message << '\n';
        }
    }
    catch (...) {}
}

template <typename Function>
Function resolve(HMODULE module, const char* name)
{
    return reinterpret_cast<Function>(GetProcAddress(module, name));
}

std::wstring utf8_to_wide(std::string_view value)
{
    if (value.empty())
    {
        return {};
    }
    const int size = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (size <= 0)
    {
        return {};
    }
    std::wstring result(static_cast<std::size_t>(size), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            size) != size)
    {
        return {};
    }
    return result;
}

std::string wide_to_utf8(std::wstring_view value)
{
    if (value.empty())
    {
        return {};
    }
    const int size = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (size <= 0)
    {
        return {};
    }
    std::string result(static_cast<std::size_t>(size), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            size,
            nullptr,
            nullptr) != size)
    {
        return {};
    }
    return result;
}

class CaptureFailure final : public std::runtime_error
{
public:
    using std::runtime_error::runtime_error;
};

class InitializedParameters final
{
public:
    InitializedParameters(RC::Unreal::UFunction* function, void* data)
        : m_struct(reinterpret_cast<RC::Unreal::UStruct*>(function)), m_data(data)
    {
        if (!m_struct || !m_data || !g_initialize_struct || !g_destroy_struct)
        {
            throw CaptureFailure("The native item capture parameter bridge is not ready.");
        }
        g_initialize_struct(m_struct, m_data, 1);
        m_initialized = true;
    }

    InitializedParameters(const InitializedParameters&) = delete;
    InitializedParameters& operator=(const InitializedParameters&) = delete;

    ~InitializedParameters()
    {
        destroy();
    }

    void destroy() noexcept
    {
        if (m_initialized)
        {
            g_destroy_struct(m_struct, m_data, 1);
            m_initialized = false;
        }
    }

private:
    RC::Unreal::UStruct* m_struct{};
    void* m_data{};
    bool m_initialized{};
};

bool function_layout_matches(
    RC::Unreal::UFunction* function,
    std::size_t parameter_size,
    std::size_t return_offset) noexcept
{
    return function
        && g_get_parms_size
        && g_get_return_value_offset
        && g_get_parms_size(function) == parameter_size
        && g_get_return_value_offset(function) == return_offset;
}

bool capture_layouts_ready() noexcept
{
    return function_layout_matches(
            reinterpret_cast<RC::Unreal::UFunction*>(g_find_item_event.load()),
            find_item_parameter_size,
            find_item_return_offset)
        && function_layout_matches(
            reinterpret_cast<RC::Unreal::UFunction*>(g_find_item_from_id_event.load()),
            find_item_from_id_parameter_size,
            find_item_from_id_return_offset)
        && function_layout_matches(
            reinterpret_cast<RC::Unreal::UFunction*>(g_talent_pool_event.load()),
            talent_pool_parameter_size,
            talent_pool_return_offset);
}

bool readable_range(const void* data, std::size_t size) noexcept
{
    if (!data || size == 0)
    {
        return size == 0;
    }
    auto address = reinterpret_cast<std::uintptr_t>(data);
    if (address > UINTPTR_MAX - size)
    {
        return false;
    }
    const auto end = address + size;
    while (address < end)
    {
        MEMORY_BASIC_INFORMATION information{};
        if (VirtualQuery(
                reinterpret_cast<const void*>(address),
                &information,
                sizeof(information)) != sizeof(information)
            || information.State != MEM_COMMIT
            || (information.Protect & PAGE_GUARD) != 0
            || (information.Protect & PAGE_NOACCESS) != 0)
        {
            return false;
        }
        const auto region = reinterpret_cast<std::uintptr_t>(information.BaseAddress);
        if (region > UINTPTR_MAX - information.RegionSize)
        {
            return false;
        }
        const auto next = region + information.RegionSize;
        if (next <= address)
        {
            return false;
        }
        address = next;
    }
    return true;
}

template <typename Element>
std::span<const Element> checked_array(const ScriptArray& array, std::string_view label)
{
    if (array.count < 0
        || array.capacity < array.count
        || static_cast<std::size_t>(array.count) > capture_array_limit)
    {
        throw CaptureFailure(
            "The native item capture returned an invalid " + std::string(label) + " count.");
    }
    if (array.count == 0)
    {
        return {};
    }
    if (!array.data
        || reinterpret_cast<std::uintptr_t>(array.data) % alignof(Element) != 0
        || !readable_range(
            array.data,
            static_cast<std::size_t>(array.count) * sizeof(Element)))
    {
        throw CaptureFailure(
            "The native item capture returned invalid " + std::string(label) + " storage.");
    }
    return {
        static_cast<const Element*>(array.data),
        static_cast<std::size_t>(array.count)
    };
}

bool same_guid(const Guid& left, const Guid& right) noexcept
{
    return left.a == right.a
        && left.b == right.b
        && left.c == right.c
        && left.d == right.d;
}

bool zero_guid(const Guid& value) noexcept
{
    return value.a == 0 && value.b == 0 && value.c == 0 && value.d == 0;
}

bool same_name(const FNameData& left, const FNameData& right) noexcept
{
    return left.comparison_index == right.comparison_index && left.number == right.number;
}

std::string name_to_utf8(const FNameData& name)
{
    if (!g_fname_to_string)
    {
        throw CaptureFailure("The native item capture name bridge is not ready.");
    }
    const std::wstring wide = g_fname_to_string(&name);
    const std::string value = wide_to_utf8(wide);
    if (!wide.empty() && value.empty())
    {
        throw CaptureFailure("The native item capture could not encode an Unreal name.");
    }
    return value;
}

std::string object_path_to_utf8(RC::Unreal::UObject* object)
{
    if (!object || !readable_range(object, sizeof(void*)) || !g_get_path_name)
    {
        throw CaptureFailure("The native item capture received an invalid Unreal object.");
    }
    std::wstring wide;
    g_get_path_name(object, nullptr, wide);
    const std::string path = wide_to_utf8(wide);
    if (path.empty())
    {
        throw CaptureFailure("The native item capture could not resolve an object path.");
    }
    return path;
}

bool is_data_table(void* object) noexcept
{
    auto* data_table_class = reinterpret_cast<RC::Unreal::UClass*>(g_data_table_class.load());
    return object
        && data_table_class
        && g_is_a
        && readable_range(object, sizeof(void*))
        && g_is_a(reinterpret_cast<RC::Unreal::UObject*>(object), data_table_class);
}

bool valid_row_handle(const DataTableRowHandle& row)
{
    if (!is_data_table(row.data_table) || row.row_name.comparison_index == 0)
    {
        return false;
    }
    const std::string name = name_to_utf8(row.row_name);
    return !name.empty() && name != "None";
}

OwnedRow copy_row(const DataTableRowHandle& row)
{
    if (!valid_row_handle(row))
    {
        throw CaptureFailure("The native item capture returned an invalid data-table row.");
    }
    return {
        object_path_to_utf8(reinterpret_cast<RC::Unreal::UObject*>(row.data_table)),
        name_to_utf8(row.row_name)
    };
}

OwnedHandle copy_handle(const InventoryItemHandle& handle)
{
    if (zero_guid(handle.id))
    {
        throw CaptureFailure("The native item capture returned a zero item identifier.");
    }
    return {copy_row(handle.data), handle.id};
}

InventoryItemHandle make_engine_handle(const OwnedHandle& handle)
{
    if (!g_static_find_object || !g_fname_constructor)
    {
        throw CaptureFailure("The native item capture handle bridge is not ready.");
    }
    const std::wstring table_path = utf8_to_wide(handle.data.table_path);
    const std::wstring row_name = utf8_to_wide(handle.data.row);
    if (table_path.empty() || row_name.empty())
    {
        throw CaptureFailure("The native item capture could not decode an item handle.");
    }
    auto* table = g_static_find_object(nullptr, nullptr, table_path.c_str(), false);
    if (!is_data_table(table))
    {
        throw CaptureFailure("The native item capture could not resolve an item data table.");
    }
    InventoryItemHandle result{};
    result.data.data_table = table;
    g_fname_constructor(&result.data.row_name, row_name.c_str(), 1, nullptr);
    result.id = handle.id;
    return result;
}

OwnedCapture capture_holder(RC::Unreal::UObject *inventory, const InventoryItemHandle &expected)
{
    auto *event = reinterpret_cast<RC::Unreal::UFunction *>(g_find_item_event.load());
    if (!g_process_event ||
        !function_layout_matches(event, find_item_parameter_size, find_item_return_offset))
    {
        throw CaptureFailure("The native FindItem bridge is not ready.");
    }
    alignas(16) std::array<std::byte, find_item_parameter_size> parameters{};
    InitializedParameters initialized(event, parameters.data());
    try
    {
        *reinterpret_cast<InventoryItemHandle *>(parameters.data()) = expected;
        g_process_event(inventory, event, parameters.data());

        const auto has_item = *reinterpret_cast<const std::uint8_t *>(parameters.data() + 0x20);
        if (has_item > 1)
        {
            throw CaptureFailure("The native FindItem bridge returned an invalid result flag.");
        }
        if (has_item == 0)
        {
            throw CaptureFailure("Wayfinder could not find the requested inventory item.");
        }

        const auto &entry = *reinterpret_cast<const InventoryItemEntryCapture *>(
            parameters.data() + find_item_return_offset);
        if (entry.handle.data.data_table != expected.data.data_table ||
            !same_name(entry.handle.data.row_name, expected.data.row_name) ||
            !same_guid(entry.handle.id, expected.id))
        {
            throw CaptureFailure("Wayfinder returned a different inventory item.");
        }

        OwnedCapture result{};
        result.item = copy_handle(entry.handle);
        result.slot_name = name_to_utf8(entry.spec.equipped_to_slot_name);

        const auto generated_slots =
            checked_array<std::uint32_t>(entry.spec.generated_slots, "generated Echo slot");
        result.generated_slot_count = static_cast<std::int32_t>(generated_slots.size());

        const auto fog_souls = checked_array<Guid>(entry.spec.fog_souls, "Echo slot");
        result.fog_souls.assign(fog_souls.begin(), fog_souls.end());

        const auto dyes = checked_array<DyeApplication>(entry.spec.dyes, "dye");
        result.dyes.reserve(dyes.size());
        for (const auto &dye : dyes)
        {
            OwnedDye owned{};
            owned.dye = copy_row(dye.dye_data);
            const auto map_ids = checked_array<std::int32_t>(dye.map_ids, "dye channel");
            owned.map_ids.assign(map_ids.begin(), map_ids.end());
            result.dyes.push_back(std::move(owned));
        }

        const auto abilities =
            checked_array<AbilitySlotEntry>(entry.spec.ability_slots, "ability slot");
        result.abilities.reserve(abilities.size());
        for (const auto &ability : abilities)
        {
            if (ability.is_set > 1)
            {
                throw CaptureFailure("The native item capture returned an invalid ability state.");
            }
            OwnedAbility owned{};
            owned.is_set = ability.is_set != 0;
            if (owned.is_set)
            {
                owned.ability = copy_row(ability.current_ability_data);
            }
            result.abilities.push_back(std::move(owned));
        }

        const auto talents = checked_array<TalentItemSpec>(entry.spec.talent_items, "talent");
        result.talents.reserve(talents.size());
        for (const auto &talent : talents)
        {
            if (talent.points < 0)
            {
                throw CaptureFailure("The native item capture returned negative talent points.");
            }
            if (talent.points > 0)
            {
                result.talents.push_back({copy_handle(talent.talent_item), talent.points, {}});
            }
        }
        initialized.destroy();
        return result;
    }
    catch (...)
    {
        initialized.destroy();
        throw;
    }
}

OwnedHandle resolve_echo(RC::Unreal::UObject *inventory, const Guid &id)
{
    auto *event = reinterpret_cast<RC::Unreal::UFunction *>(g_find_item_from_id_event.load());
    if (!g_process_event || zero_guid(id) ||
        !function_layout_matches(event, find_item_from_id_parameter_size,
                                 find_item_from_id_return_offset))
    {
        throw CaptureFailure("The native FindItemFromId bridge is not ready.");
    }
    alignas(16) std::array<std::byte, find_item_from_id_parameter_size> parameters{};
    InitializedParameters initialized(event, parameters.data());
    try
    {
        *reinterpret_cast<Guid *>(parameters.data()) = id;
        g_process_event(inventory, event, parameters.data());

        const auto has_item = *reinterpret_cast<const std::uint8_t *>(parameters.data() + 0x10);
        if (has_item > 1)
        {
            throw CaptureFailure(
                "The native FindItemFromId bridge returned an invalid result flag.");
        }
        if (has_item == 0)
        {
            throw CaptureFailure("Wayfinder could not resolve an equipped Echo.");
        }
        const auto &entry = *reinterpret_cast<const InventoryItemEntryCapture *>(
            parameters.data() + find_item_from_id_return_offset);
        if (!same_guid(entry.handle.id, id))
        {
            throw CaptureFailure("Wayfinder returned a different Echo.");
        }
        OwnedHandle result = copy_handle(entry.handle);
        initialized.destroy();
        return result;
    }
    catch (...)
    {
        initialized.destroy();
        throw;
    }
}

OwnedRow resolve_talent_pool(RC::Unreal::UObject *inventory, const OwnedHandle &holder,
                             const OwnedHandle &talent)
{
    auto *event = reinterpret_cast<RC::Unreal::UFunction *>(g_talent_pool_event.load());
    if (!g_process_event ||
        !function_layout_matches(event, talent_pool_parameter_size, talent_pool_return_offset))
    {
        throw CaptureFailure("The native talent-pool bridge is not ready.");
    }
    alignas(16) std::array<std::byte, talent_pool_parameter_size> parameters{};
    InitializedParameters initialized(event, parameters.data());
    try
    {
        *reinterpret_cast<InventoryItemHandle *>(parameters.data()) = make_engine_handle(holder);
        *reinterpret_cast<InventoryItemHandle *>(parameters.data() + 0x20) =
            make_engine_handle(talent);
        g_process_event(inventory, event, parameters.data());

        const auto &row = *reinterpret_cast<const DataTableRowHandle *>(parameters.data() +
                                                                        talent_pool_return_offset);
        if (!valid_row_handle(row))
        {
            initialized.destroy();
            return {};
        }
        OwnedRow result = copy_row(row);
        initialized.destroy();
        return result;
    }
    catch (...)
    {
        initialized.destroy();
        throw;
    }
}

std::string percent_escape(std::string_view value)
{
    constexpr std::string_view digits{"0123456789ABCDEF"};
    std::string result;
    result.reserve(value.size());
    for (const unsigned char character : value)
    {
        if (character == '%' || character == '\t' || character == '\r' || character == '\n')
        {
            result.push_back('%');
            result.push_back(digits[character >> 4]);
            result.push_back(digits[character & 0x0F]);
        }
        else
        {
            result.push_back(static_cast<char>(character));
        }
    }
    return result;
}

void append_record(std::string& payload, std::span<const std::string> fields)
{
    for (std::size_t index = 0; index < fields.size(); ++index)
    {
        if (index > 0)
        {
            payload.push_back('\t');
        }
        payload.append(percent_escape(fields[index]));
    }
    payload.push_back('\n');
}

std::string serialize_capture(const OwnedCapture& capture)
{
    std::string payload;
    std::vector<std::string> fields;
    fields = {
        "ITEM",
        capture.item.data.table_path,
        capture.item.data.row,
        std::to_string(capture.item.id.a),
        std::to_string(capture.item.id.b),
        std::to_string(capture.item.id.c),
        std::to_string(capture.item.id.d)
    };
    append_record(payload, fields);
    fields = {"SLOTS", std::to_string(capture.generated_slot_count)};
    append_record(payload, fields);
    fields = {"SLOTNAME", capture.slot_name};
    append_record(payload, fields);

    for (const auto& dye : capture.dyes)
    {
        fields = {
            "DYE",
            dye.dye.table_path,
            dye.dye.row,
            std::to_string(dye.map_ids.size())
        };
        for (const auto map_id : dye.map_ids)
        {
            fields.push_back(std::to_string(map_id));
        }
        append_record(payload, fields);
    }
    for (std::size_t slot = 0; slot < capture.abilities.size(); ++slot)
    {
        const auto& ability = capture.abilities[slot];
        fields = {
            "ABILITY",
            std::to_string(slot),
            ability.is_set ? "1" : "0",
            ability.ability.table_path,
            ability.ability.row
        };
        append_record(payload, fields);
    }
    for (const auto& talent : capture.talents)
    {
        fields = {
            "TALENT",
            talent.talent.data.table_path,
            talent.talent.data.row,
            std::to_string(talent.talent.id.a),
            std::to_string(talent.talent.id.b),
            std::to_string(talent.talent.id.c),
            std::to_string(talent.talent.id.d),
            std::to_string(talent.points),
            talent.pool.table_path,
            talent.pool.row
        };
        append_record(payload, fields);
    }
    for (std::size_t slot = 0; slot < capture.fog_souls.size(); ++slot)
    {
        const auto& id = capture.fog_souls[slot];
        fields = {
            "FOG",
            std::to_string(slot),
            std::to_string(id.a),
            std::to_string(id.b),
            std::to_string(id.c),
            std::to_string(id.d)
        };
        append_record(payload, fields);
    }
    for (const auto& echo : capture.echos)
    {
        fields = {
            "ECHO",
            std::to_string(echo.slot),
            echo.item.data.table_path,
            echo.item.data.row,
            std::to_string(echo.item.id.a),
            std::to_string(echo.item.id.b),
            std::to_string(echo.item.id.c),
            std::to_string(echo.item.id.d)
        };
        append_record(payload, fields);
    }
    return payload;
}

int lua_result(const RC::LuaMadeSimple::Lua& lua, bool success, std::string_view message)
{
    if (!g_lua_set_bool || !g_lua_set_string)
    {
        return 0;
    }
    g_lua_set_bool(&lua, success);
    g_lua_set_string(&lua, message);
    return 2;
}

bool take_lua_string(const RC::LuaMadeSimple::Lua& lua, int index, std::string& value)
{
    if (!g_lua_is_string || !g_lua_get_string || !g_lua_is_string(&lua, index))
    {
        return false;
    }
    value.assign(g_lua_get_string(&lua, index));
    return true;
}

bool take_lua_integer(const RC::LuaMadeSimple::Lua& lua, int index, std::int64_t& value)
{
    if (!g_lua_is_integer || !g_lua_get_integer || !g_lua_is_integer(&lua, index))
    {
        return false;
    }
    value = g_lua_get_integer(&lua, index);
    return true;
}

int __cdecl capture_item_from_lua(const RC::LuaMadeSimple::Lua& lua) noexcept
{
    try
    {
        if (!g_running.load())
        {
            return lua_result(lua, false, "The native item capture bridge is not running.");
        }
        if (!g_find_item_event.load()
            || !g_find_item_from_id_event.load()
            || !g_talent_pool_event.load()
            || !g_inventory_class.load()
            || !g_data_table_class.load()
            || !g_static_find_object
            || !g_process_event
            || !g_is_a
            || !g_fname_constructor
            || !g_fname_to_string
            || !g_get_path_name
            || !g_initialize_struct
            || !g_destroy_struct
            || !g_get_parms_size
            || !g_get_return_value_offset
            || !capture_layouts_ready())
        {
            return lua_result(lua, false, "The native item capture bridge is not ready.");
        }
        if (!g_lua_get_stack_size || g_lua_get_stack_size(&lua) != 7)
        {
            return lua_result(lua, false, "The native item capture bridge received incomplete data.");
        }

        std::string inventory_object_path;
        std::string item_table_path;
        std::string item_row_name;
        std::int64_t guid_parts[4]{};
        if (!take_lua_string(lua, 1, inventory_object_path)
            || !take_lua_string(lua, 2, item_table_path)
            || !take_lua_string(lua, 3, item_row_name))
        {
            return lua_result(lua, false, "The native item capture bridge received invalid item data.");
        }
        for (std::size_t index = 0; index < std::size(guid_parts); ++index)
        {
            auto& part = guid_parts[index];
            if (!take_lua_integer(lua, static_cast<int>(index + 4), part)
                || part < 0
                || static_cast<std::uint64_t>(part) > UINT32_MAX)
            {
                return lua_result(
                    lua,
                    false,
                    "The native item capture bridge received an invalid item identifier.");
            }
        }

        const std::wstring inventory_path = utf8_to_wide(inventory_object_path);
        const std::wstring item_path = utf8_to_wide(item_table_path);
        const std::wstring item_row = utf8_to_wide(item_row_name);
        if (inventory_path.empty() || item_path.empty() || item_row.empty())
        {
            return lua_result(lua, false, "The native item capture bridge could not decode a path.");
        }

        auto* inventory = g_static_find_object(nullptr, nullptr, inventory_path.c_str(), false);
        auto* inventory_class = reinterpret_cast<RC::Unreal::UClass*>(g_inventory_class.load());
        auto* item_table = g_static_find_object(nullptr, nullptr, item_path.c_str(), false);
        if (!inventory
            || !inventory_class
            || !g_is_a
            || !readable_range(inventory, sizeof(void*))
            || !g_is_a(inventory, inventory_class))
        {
            return lua_result(
                lua,
                false,
                "The native item capture bridge could not resolve the player inventory.");
        }
        if (!is_data_table(item_table))
        {
            return lua_result(
                lua,
                false,
                "The native item capture bridge could not resolve the item data table.");
        }

        InventoryItemHandle expected{};
        expected.data.data_table = item_table;
        g_fname_constructor(&expected.data.row_name, item_row.c_str(), 1, nullptr);
        expected.id = {
            static_cast<std::uint32_t>(guid_parts[0]),
            static_cast<std::uint32_t>(guid_parts[1]),
            static_cast<std::uint32_t>(guid_parts[2]),
            static_cast<std::uint32_t>(guid_parts[3])
        };
        if (zero_guid(expected.id))
        {
            return lua_result(
                lua,
                false,
                "The native item capture bridge received a zero item identifier.");
        }

        OwnedCapture capture = capture_holder(inventory, expected);
        for (auto& talent : capture.talents)
        {
            talent.pool = resolve_talent_pool(inventory, capture.item, talent.talent);
            if (talent.points > 0 && talent.pool.table_path.empty())
            {
                throw CaptureFailure(
                    "Wayfinder could not resolve the pool for a selected talent.");
            }
        }
        capture.echos.reserve(capture.fog_souls.size());
        for (std::size_t slot = 0; slot < capture.fog_souls.size(); ++slot)
        {
            const auto& id = capture.fog_souls[slot];
            if (!zero_guid(id))
            {
                capture.echos.push_back({slot, resolve_echo(inventory, id)});
            }
        }
        return lua_result(lua, true, serialize_capture(capture));
    }
    catch (const CaptureFailure& error)
    {
        log(std::string("Native item capture rejected data: ") + error.what());
        return lua_result(lua, false, error.what());
    }
    catch (const std::exception& error)
    {
        log(std::string("Native item capture exception: ") + error.what());
        return lua_result(lua, false, "The native item capture bridge failed.");
    }
    catch (...)
    {
        log("Native item capture exception: unknown error");
        return lua_result(lua, false, "The native item capture bridge failed.");
    }
}

int __cdecl capture_bridge_ready_from_lua(const RC::LuaMadeSimple::Lua& lua) noexcept
{
    const bool ready = g_running.load()
        && g_find_item_event.load()
        && g_find_item_from_id_event.load()
        && g_talent_pool_event.load()
        && g_inventory_class.load()
        && g_data_table_class.load()
        && g_static_find_object
        && g_process_event
        && g_is_a
        && g_fname_constructor
        && g_fname_to_string
        && g_get_path_name
        && g_initialize_struct
        && g_destroy_struct
        && g_get_parms_size
        && g_get_return_value_offset
        && capture_layouts_ready();
    return lua_result(
        lua,
        ready,
        ready
            ? "The native item capture bridge is ready."
            : "The native item capture bridge is not ready.");
}

int __cdecl apply_dye_from_lua(const RC::LuaMadeSimple::Lua& lua) noexcept
{
    try
    {
        if (!g_running.load())
        {
            return lua_result(lua, false, "The native dye bridge is not running.");
        }
        if (!g_lua_get_stack_size || g_lua_get_stack_size(&lua) < 10)
        {
            return lua_result(lua, false, "The native dye bridge received incomplete data.");
        }

        std::string inventory_object_path;
        std::string item_table_path;
        std::string item_row_name;
        std::string dye_table_path;
        std::string dye_row_name;
        std::int64_t guid_parts[4]{};
        if (!take_lua_string(lua, 1, inventory_object_path)
            || !take_lua_string(lua, 2, item_table_path)
            || !take_lua_string(lua, 3, item_row_name))
        {
            return lua_result(lua, false, "The native dye bridge received invalid item data.");
        }
        for (std::size_t index = 0; index < std::size(guid_parts); ++index)
        {
            auto& part = guid_parts[index];
            if (!take_lua_integer(lua, static_cast<int>(index + 4), part)
                || part < 0
                || static_cast<std::uint64_t>(part) > UINT32_MAX)
            {
                return lua_result(lua, false, "The native dye bridge received an invalid item identifier.");
            }
        }
        if (!take_lua_string(lua, 8, dye_table_path)
            || !take_lua_string(lua, 9, dye_row_name))
        {
            return lua_result(lua, false, "The native dye bridge received invalid dye data.");
        }

        std::vector<std::int32_t> map_ids;
        const int stack_size = g_lua_get_stack_size(&lua);
        for (int index = 10; index <= stack_size; ++index)
        {
            std::int64_t value{};
            if (!take_lua_integer(lua, index, value)
                || value < INT32_MIN
                || value > INT32_MAX)
            {
                return lua_result(lua, false, "The native dye bridge received an invalid dye channel.");
            }
            map_ids.push_back(static_cast<std::int32_t>(value));
        }
        if (map_ids.empty())
        {
            return lua_result(lua, false, "The saved dye has no material channels.");
        }

        const std::wstring inventory_path = utf8_to_wide(inventory_object_path);
        const std::wstring item_path = utf8_to_wide(item_table_path);
        const std::wstring item_row = utf8_to_wide(item_row_name);
        const std::wstring dye_path = utf8_to_wide(dye_table_path);
        const std::wstring dye_row = utf8_to_wide(dye_row_name);
        if (inventory_path.empty()
            || item_path.empty()
            || item_row.empty()
            || dye_path.empty()
            || dye_row.empty())
        {
            return lua_result(lua, false, "The native dye bridge could not decode a saved path.");
        }

        auto* inventory = g_static_find_object(nullptr, nullptr, inventory_path.c_str(), false);
        auto* inventory_class = reinterpret_cast<RC::Unreal::UClass*>(g_inventory_class.load());
        auto* data_table_class = reinterpret_cast<RC::Unreal::UClass*>(g_data_table_class.load());
        auto* item_table = g_static_find_object(nullptr, nullptr, item_path.c_str(), false);
        auto* dye_table = g_static_find_object(nullptr, nullptr, dye_path.c_str(), false);
        auto* dye_event = reinterpret_cast<RC::Unreal::UFunction*>(g_apply_dye_event.load());
        if (!inventory
            || !inventory_class
            || !g_is_a
            || !g_is_a(inventory, inventory_class))
        {
            return lua_result(lua, false, "The native dye bridge could not resolve the player inventory.");
        }
        if (!data_table_class
            || !item_table
            || !dye_table
            || !g_is_a(item_table, data_table_class)
            || !g_is_a(dye_table, data_table_class))
        {
            return lua_result(lua, false, "The native dye bridge could not resolve a saved data table.");
        }
        if (!dye_event || !g_process_event || !g_fname_constructor)
        {
            return lua_result(lua, false, "The native dye bridge is not ready.");
        }

        ApplyDyeParameters parameters{};
        parameters.item.data.data_table = item_table;
        parameters.dye.data_table = dye_table;
        g_fname_constructor(&parameters.item.data.row_name, item_row.c_str(), 1, nullptr);
        g_fname_constructor(&parameters.dye.row_name, dye_row.c_str(), 1, nullptr);
        parameters.item.id = {
            static_cast<std::uint32_t>(guid_parts[0]),
            static_cast<std::uint32_t>(guid_parts[1]),
            static_cast<std::uint32_t>(guid_parts[2]),
            static_cast<std::uint32_t>(guid_parts[3])
        };
        parameters.map_ids = {
            map_ids.data(),
            static_cast<std::int32_t>(map_ids.size()),
            static_cast<std::int32_t>(map_ids.size())
        };
        g_process_event(inventory, dye_event, &parameters);
        return lua_result(
            lua,
            parameters.return_value,
            parameters.return_value ? "Dye applied." : "Wayfinder rejected the dye.");
    }
    catch (const std::exception& error)
    {
        log(std::string("Native dye bridge exception: ") + error.what());
        return lua_result(lua, false, "The native dye bridge failed.");
    }
    catch (...)
    {
        log("Native dye bridge exception: unknown error");
        return lua_result(lua, false, "The native dye bridge failed.");
    }
}

int __cdecl dye_bridge_ready_from_lua(const RC::LuaMadeSimple::Lua& lua) noexcept
{
    const bool ready = g_running.load()
        && g_apply_dye_event.load()
        && g_inventory_class.load()
        && g_data_table_class.load()
        && g_static_find_object
        && g_process_event
        && g_is_a
        && g_fname_constructor;
    return lua_result(
        lua,
        ready,
        ready ? "The native dye bridge is ready." : "The native dye bridge is not ready.");
}

void register_lua_bridge(RC::LuaMadeSimple::Lua& lua)
{
    if (!g_module_pinned.load() || !g_initialized.load() || !g_lua_register_function)
    {
        return;
    }
    const std::string apply_name{"LoadoutsNativeApplyDye"};
    const LuaCallback apply_callback = &apply_dye_from_lua;
    g_lua_register_function(&lua, apply_name, apply_callback);
    const std::string ready_name{"LoadoutsNativeDyeReady"};
    const LuaCallback ready_callback = &dye_bridge_ready_from_lua;
    g_lua_register_function(&lua, ready_name, ready_callback);
    const std::string capture_name{"LoadoutsNativeCaptureItem"};
    const LuaCallback capture_callback = &capture_item_from_lua;
    g_lua_register_function(&lua, capture_name, capture_callback);
    const std::string capture_ready_name{"LoadoutsNativeCaptureReady"};
    const LuaCallback capture_ready_callback = &capture_bridge_ready_from_lua;
    g_lua_register_function(&lua, capture_ready_name, capture_ready_callback);
    if (!g_bridge_registered.exchange(true))
    {
        log("Lua dye and item-capture bridges registered");
    }
}

void dispatch_relay(const RelayEvent& event) noexcept
{
    if (!g_running.load()
        || event.generation != g_generation.load()
        || !g_execute_lua)
    {
        return;
    }

    try
    {
        std::ostringstream script;
        if (event.kind == RelayKind::Focus)
        {
            script << "if LoadoutsNativeFocus then local ok=pcall(LoadoutsNativeFocus,\""
                   << event.context << "\",\"" << event.value
                   << "\"); if not ok then print('[Loadouts] Native focus relay failed') end end";
        }
        else if (event.kind == RelayKind::PageRemoved)
        {
            script << "if LoadoutsNativePageRemoved then local ok=pcall(LoadoutsNativePageRemoved,\""
                   << event.context
                   << "\"); if not ok then print('[Loadouts] Native removal relay failed') end end";
        }
        std::array<char, 4096> output{};
        if (const char* error = g_execute_lua("Loadouts", script.str().c_str(), output.data()); error)
        {
            log(std::string("Lua relay failed: ") + error);
        }
    }
    catch (const std::exception& error)
    {
        log(std::string("Lua relay exception: ") + error.what());
    }
    catch (...) { log("Lua relay exception: unknown error"); }
}

void enqueue(
    RelayKind kind,
    RC::Unreal::UObject* context,
    std::uint64_t generation,
    void* value = nullptr) noexcept
{
    if (!g_running.load()
        || generation != g_generation.load()
        || !context)
    {
        return;
    }
    try
    {
        RelayEvent event{};
        event.kind = kind;
        event.context = reinterpret_cast<std::uintptr_t>(context);
        event.value = reinterpret_cast<std::uintptr_t>(value);
        event.generation = generation;
        std::lock_guard lock(g_event_mutex);
        if (!g_running.load() || generation != g_generation.load())
        {
            return;
        }
        if (g_events.size() >= relay_queue_capacity)
        {
            g_dropped_events.fetch_add(1);
            return;
        }
        g_events.push_back(event);
    }
    catch (const std::exception& error)
    {
        log(std::string("Event queue exception: ") + error.what());
    }
    catch (...) { log("Event queue exception: unknown error"); }
}

void on_process_event(
    RC::Unreal::UObject* context,
    RC::Unreal::UFunction* function,
    void* params) noexcept
{
    const auto generation = g_generation.load();
    if (!g_running.load() || generation != g_generation.load())
    {
        return;
    }
    if (function == g_focus_event.load())
    {
        void* focus = params ? *static_cast<void**>(params) : nullptr;
        enqueue(RelayKind::Focus, context, generation, focus);
    }
    else if (function == g_removed_event.load())
    {
        enqueue(RelayKind::PageRemoved, context, generation);
    }
}

void resolve_target(std::atomic<void*>& target, const wchar_t* path, const char* label)
{
    if (target.load() || !g_static_find_object)
    {
        return;
    }
    if (void* function = g_static_find_object(nullptr, nullptr, path, false); function)
    {
        target = function;
        std::ostringstream message;
        message << "Resolved " << label << " at " << function;
        log(message.str());
    }
}

bool pin_module()
{
    if (g_module_pinned.load())
    {
        return true;
    }
    HMODULE module{};
    if (!GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
            reinterpret_cast<LPCWSTR>(&g_running),
            &module))
    {
        log("The native relay DLL could not be pinned");
        return false;
    }
    g_module_pinned = true;
    log("Native relay DLL pinned until process exit");
    return true;
}

bool initialize()
{
    if (g_initialized.load(std::memory_order_acquire))
    {
        return true;
    }
    HMODULE ue4ss = GetModuleHandleW(L"UE4SS.dll");
    if (!ue4ss)
    {
        log("UE4SS.dll is unavailable");
        return false;
    }

    auto register_process_event = resolve<RegisterProcessEventPreCallbackFn>(
        ue4ss,
        "?RegisterProcessEventPreCallback@Hook@Unreal@RC@@YAXV?$function@$$A6AXPEAVUObject@Unreal@RC@@PEAVUFunction@23@PEAX@Z@std@@@Z");
    g_static_find_object = resolve<StaticFindObjectFn>(
        ue4ss,
        "?StaticFindObject_InternalSlow@UObjectGlobals@Unreal@RC@@YAPEAVUObject@23@PEAVUClass@23@PEAV423@PEB_W_N@Z");
    g_execute_lua = resolve<ExecuteLuaInModFn>(ue4ss, "execute_lua_in_mod");
    g_lua_register_function = resolve<LuaRegisterFunctionFn>(
        ue4ss,
        "?register_function@Lua@LuaMadeSimple@RC@@QEBAXAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@AEBQ6AHAEBV123@@Z@Z");
    g_lua_get_stack_size = resolve<LuaGetStackSizeFn>(
        ue4ss,
        "?get_stack_size@Lua@LuaMadeSimple@RC@@QEBAHXZ");
    g_lua_is_string = resolve<LuaIsStringFn>(
        ue4ss,
        "?is_string@Lua@LuaMadeSimple@RC@@QEBA_NH@Z");
    g_lua_get_string = resolve<LuaGetStringFn>(
        ue4ss,
        "?get_string@Lua@LuaMadeSimple@RC@@QEBA?AV?$basic_string_view@DU?$char_traits@D@std@@@std@@H@Z");
    g_lua_is_integer = resolve<LuaIsIntegerFn>(
        ue4ss,
        "?is_integer@Lua@LuaMadeSimple@RC@@QEBA_NH@Z");
    g_lua_get_integer = resolve<LuaGetIntegerFn>(
        ue4ss,
        "?get_integer@Lua@LuaMadeSimple@RC@@QEBA_JH@Z");
    g_lua_set_bool = resolve<LuaSetBoolFn>(
        ue4ss,
        "?set_bool@Lua@LuaMadeSimple@RC@@QEBAX_N@Z");
    g_lua_set_string = resolve<LuaSetStringFn>(
        ue4ss,
        "?set_string@Lua@LuaMadeSimple@RC@@QEBAXV?$basic_string_view@DU?$char_traits@D@std@@@std@@@Z");
    g_process_event = resolve<ProcessEventFn>(
        ue4ss,
        "?ProcessEvent@UObject@Unreal@RC@@QEAAXPEAVUFunction@23@PEAX@Z");
    g_is_a = resolve<IsAFn>(
        ue4ss,
        "?IsA@UObjectBase@Unreal@RC@@QEBA_NPEAVUClass@23@@Z");
    g_fname_constructor = resolve<FNameConstructorFn>(
        ue4ss,
        "??0FName@Unreal@RC@@QEAA@PEB_WW4EFindName@12@PEAX@Z");
    g_fname_to_string = resolve<FNameToStringFn>(
        ue4ss,
        "?ToString@FName@Unreal@RC@@QEBA?BV?$basic_string@_WU?$char_traits@_W@std@@V?$allocator@_W@2@@std@@XZ");
    g_get_path_name = resolve<UObjectGetPathNameFn>(
        ue4ss,
        "?GetPathName@UObject@Unreal@RC@@QEBAXPEAV123@AEAV?$basic_string@_WU?$char_traits@_W@std@@V?$allocator@_W@2@@std@@@Z");
    g_initialize_struct = resolve<InitializeStructFn>(
        ue4ss,
        "?InitializeStruct@UStruct@Unreal@RC@@QEBAXPEAXH@Z");
    g_destroy_struct = resolve<DestroyStructFn>(
        ue4ss,
        "?DestroyStruct@UStruct@Unreal@RC@@QEBAXPEAXH@Z");
    g_get_parms_size = resolve<UFunctionUInt16GetterFn>(
        ue4ss,
        "?GetParmsSize@UFunction@Unreal@RC@@QEBAAEBGXZ");
    g_get_return_value_offset = resolve<UFunctionUInt16GetterFn>(
        ue4ss,
        "?GetReturnValueOffset@UFunction@Unreal@RC@@QEBAAEBGXZ");
    if (!register_process_event
        || !g_static_find_object
        || !g_execute_lua
        || !g_lua_register_function
        || !g_lua_get_stack_size
        || !g_lua_is_string
        || !g_lua_get_string
        || !g_lua_is_integer
        || !g_lua_get_integer
        || !g_lua_set_bool
        || !g_lua_set_string
        || !g_process_event
        || !g_is_a
        || !g_fname_constructor
        || !g_fname_to_string
        || !g_get_path_name
        || !g_initialize_struct
        || !g_destroy_struct
        || !g_get_parms_size
        || !g_get_return_value_offset)
    {
        log("One or more UE4SS 3.0.1 relay exports are unavailable");
        return false;
    }

    if (!g_callback_registered.exchange(true))
    {
        try
        {
            register_process_event(ProcessEventCallback(on_process_event));
        }
        catch (...)
        {
            g_callback_registered = false;
            throw;
        }
        log("ProcessEvent relay registered");
    }
    g_initialized.store(true, std::memory_order_release);
    return true;
}

class UE4SSMod301
{
protected:
    std::vector<std::shared_ptr<void>> GUITabs{};
public:
    std::wstring ModName{L"LoadoutsEventRelay"};
    std::wstring ModVersion{L"0.1.0"};
    std::wstring ModDescription{L"Relays Wayfinder Loadouts UI events to Lua."};
    std::wstring ModAuthors{L"Local companion implementation"};
    std::wstring ModIntendedSDKVersion{L"3.0.1"};

    virtual ~UE4SSMod301()
    {
        g_running = false;
        g_generation.fetch_add(1);
        std::lock_guard lock(g_event_mutex);
        g_events.clear();
    }
    virtual void on_update()
    {
        if (!g_callback_registered.load())
        {
            return;
        }
        std::deque<RelayEvent> events;
        {
            std::lock_guard lock(g_event_mutex);
            events.swap(g_events);
        }
        for (const auto& event : events)
        {
            dispatch_relay(event);
        }
        if (const auto dropped = g_dropped_events.exchange(0); dropped > 0)
        {
            log("Dropped native relay events=" + std::to_string(dropped));
        }
        const auto now = GetTickCount64();
        if (now < g_next_resolve.load())
        {
            return;
        }
        g_next_resolve = now + 250;
        try
        {
            resolve_target(g_focus_event, focus_event_path, "focus event");
            resolve_target(g_removed_event, removed_event_path, "page removal event");
            resolve_target(g_apply_dye_event, apply_dye_event_path, "dye event");
            resolve_target(g_find_item_event, find_item_event_path, "FindItem event");
            resolve_target(
                g_find_item_from_id_event,
                find_item_from_id_event_path,
                "FindItemFromId event");
            resolve_target(g_talent_pool_event, talent_pool_event_path, "talent-pool event");
            resolve_target(g_inventory_class, inventory_class_path, "inventory class");
            resolve_target(g_data_table_class, data_table_class_path, "data table class");
        }
        catch (const std::exception& error)
        {
            log(std::string("Event discovery exception: ") + error.what());
        }
        catch (...) { log("Event discovery exception: unknown error"); }
    }
    virtual void on_unreal_init()
    {
        try
        {
            initialize();
        }
        catch (const std::exception& error)
        {
            log(std::string("Relay initialization exception: ") + error.what());
        }
        catch (...) { log("Relay initialization exception: unknown error"); }
    }
    virtual void on_program_start() {}
    virtual void on_lua_start(
        std::wstring_view mod_name,
        RC::LuaMadeSimple::Lua& lua,
        RC::LuaMadeSimple::Lua&,
        RC::LuaMadeSimple::Lua&,
        std::vector<RC::LuaMadeSimple::Lua*>&)
    {
        if (mod_name == L"Loadouts")
        {
            register_lua_bridge(lua);
        }
    }
    virtual void on_lua_start(
        RC::LuaMadeSimple::Lua& lua,
        RC::LuaMadeSimple::Lua&,
        RC::LuaMadeSimple::Lua&,
        std::vector<RC::LuaMadeSimple::Lua*>&)
    {
        static_cast<void>(lua);
    }
    virtual void on_lua_stop(
        std::wstring_view,
        RC::LuaMadeSimple::Lua&,
        RC::LuaMadeSimple::Lua&,
        RC::LuaMadeSimple::Lua&,
        std::vector<RC::LuaMadeSimple::Lua*>&) {}
    virtual void on_lua_stop(
        RC::LuaMadeSimple::Lua&,
        RC::LuaMadeSimple::Lua&,
        RC::LuaMadeSimple::Lua&,
        std::vector<RC::LuaMadeSimple::Lua*>&) {}
    virtual void on_dll_load(std::wstring_view) {}
    virtual void render_tab() {}
};
}

extern "C" __declspec(dllexport) void* start_mod()
{
    if (!pin_module())
    {
        return nullptr;
    }
    auto* mod = new UE4SSMod301();
    {
        std::lock_guard lock(g_event_mutex);
        g_events.clear();
    }
    g_dropped_events = 0;
    g_focus_event = nullptr;
    g_removed_event = nullptr;
    g_apply_dye_event = nullptr;
    g_find_item_event = nullptr;
    g_find_item_from_id_event = nullptr;
    g_talent_pool_event = nullptr;
    g_inventory_class = nullptr;
    g_data_table_class = nullptr;
    g_next_resolve = 0;
    g_generation.fetch_add(1);
    g_running = true;
    return mod;
}

extern "C" __declspec(dllexport) void uninstall_mod(void* mod)
{
    delete static_cast<UE4SSMod301*>(mod);
}

BOOL APIENTRY DllMain(HMODULE, DWORD, LPVOID)
{
    return TRUE;
}
