#include <Windows.h>
#include <MinHook.h>
#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iterator>
#include <limits>
#include <memory>
#include <mutex>
#include <random>
#include <sstream>
#include <string>
#include <type_traits>
#include <unordered_map>
#include <vector>

extern "C" void MoreDropsEchoAppendGate();
extern "C" void* MoreDropsEchoGateTarget(const void* item);

namespace
{
struct ArrayView
{
    void* data;
    std::int32_t count;
    std::int32_t capacity;
};

struct NameView
{
    std::uint32_t comparison_index;
    std::uint32_t number;
};

struct UnrealStringView
{
    wchar_t* data;
    std::int32_t count;
    std::int32_t capacity;
};

struct DataTableRowHandleView
{
    void* data_table;
    NameView row_name;
};

struct InventoryItemCreationParamsView
{
    DataTableRowHandleView data;
    std::int32_t amount;
    std::int32_t level;
    std::byte padding[8];
};

struct EchoItemView
{
    DataTableRowHandleView data;
    std::byte before_echo_rarity[0x110];
    std::uint8_t echo_rarity;
};

struct LootEntryView
{
    float probability;
    std::byte probability_level_multiplier[0x2c];
    float minimum;
    float maximum;
    std::byte remainder[0xf8];
};

struct LootTableRecordView
{
    std::byte table_row_base[8];
    ArrayView loot;
    bool spawn_items_as_pickups;
};

struct LootResultView
{
    ArrayView player_items;
    ArrayView player_pickups;
    ArrayView manifest_items;
    ArrayView manifest_items_as_pickups;
    ArrayView manifest_items_as_fauxjectiles;
    ArrayView manifest_pickups;
    void* player_controller;
    std::byte padding[8];
};

struct CoreResultView
{
    ArrayView manifest_items;
    ArrayView manifest_items_as_pickups;
    ArrayView manifest_items_as_fauxjectiles;
    ArrayView manifest_pickups;
    void* player_controller;
    float content_level;
    std::byte padding[4];
};

static_assert(sizeof(ArrayView) == 0x10);
static_assert(sizeof(NameView) == 0x08);
static_assert(sizeof(DataTableRowHandleView) == 0x10);
static_assert(sizeof(InventoryItemCreationParamsView) == 0x20);
static_assert(std::is_trivially_copyable_v<InventoryItemCreationParamsView>);
static_assert(offsetof(EchoItemView, echo_rarity) == 0x120);
static_assert(sizeof(LootEntryView) == 0x130);
static_assert(offsetof(LootTableRecordView, loot) == 0x8);
static_assert(sizeof(LootResultView) == 0x70);
static_assert(sizeof(CoreResultView) == 0x50);

using SpawnLootFn = LootResultView*(__fastcall*)(void*, LootResultView*, LootTableRecordView*, void*, void*);
using GenerateLootFn = CoreResultView*(__fastcall*)(void*, CoreResultView*, LootTableRecordView*, void*, void*);
using NameToStringFn = void(__fastcall*)(const NameView*, UnrealStringView*);
using AssignEchoRarityFn = void(__fastcall*)(EchoItemView*, void*, std::int32_t, std::int32_t);
struct Settings
{
    float core_probability{2.0f};
    float final_probability{1.0f};
    float minimum{1.0f};
    float maximum{1.0f};
    std::unordered_map<std::string, float> item_probabilities;
    std::uint8_t echo_rarity_mask{0x1e};
};

struct OriginalEntry
{
    LootEntryView* entry;
    float probability;
    float minimum;
    float maximum;
};

SpawnLootFn g_spawn_loot{};
GenerateLootFn g_generate_loot{};
NameToStringFn g_name_to_string{};
AssignEchoRarityFn g_assign_echo_rarity{};
void* g_echo_append_trampoline{};
void* g_echo_cleanup_target{};
Settings g_settings{};
std::filesystem::file_time_type g_config_write_time{};
bool g_config_write_time_valid{};
bool g_config_error_logged{};
std::chrono::steady_clock::time_point g_next_config_check{};
bool g_mh{};
bool g_echo_hooks_active{};
bool g_hook_install_complete{};
std::atomic<std::uint64_t> g_core_call_count{};
std::atomic<std::uint64_t> g_result_call_count{};
std::atomic<std::uint64_t> g_core_entry_log_count{};
std::atomic<std::uint64_t> g_final_entry_log_count{};
std::atomic<std::uint64_t> g_item_log_count{};
std::atomic<std::uint64_t> g_echo_roll_count{};
std::mutex g_log_mutex;
std::recursive_mutex g_loot_mutex;
thread_local std::vector<LootTableRecordView*> g_active_records;
thread_local std::vector<LootTableRecordView*> g_active_final_records;
thread_local std::uint32_t g_loot_spawn_depth{};

struct PendingEchoRejection
{
    const EchoItemView* item;
    std::uint64_t call;
    std::uint8_t rarity;
    std::string item_key;
};

thread_local std::vector<PendingEchoRejection> g_pending_echo_rejections;

constexpr std::uintptr_t spawn_loot_rva = 0x1B09200;
constexpr std::uintptr_t generate_loot_rva = 0x1B12B40;
constexpr std::uintptr_t name_to_string_rva = 0x1F08B30;
constexpr std::uintptr_t assign_echo_rarity_rva = 0x178C0F0;
constexpr std::uintptr_t echo_rarity_call_site_rva = 0x177D76C;
constexpr std::uintptr_t echo_append_gate_rva = 0x177E1A0;
constexpr std::uintptr_t echo_cleanup_rva = 0x177E38D;
constexpr std::uint64_t diagnostic_call_limit = 200;
constexpr std::uint64_t diagnostic_entry_limit = 40;
constexpr std::uint64_t diagnostic_item_limit = 1000;
constexpr std::uint64_t diagnostic_echo_limit = 1000;
constexpr std::int32_t maximum_array_count = 4096;
constexpr std::uint8_t all_echo_rarities = 0x1e;

std::filesystem::path module_path()
{
    HMODULE module{};
    if (!GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(&g_settings), &module)) return {};
    wchar_t path[MAX_PATH]{};
    if (!GetModuleFileNameW(module, path, MAX_PATH)) return {};
    return path;
}

std::filesystem::path mod_directory()
{
    const auto path = module_path();
    if (path.empty()) return {};
    return path.parent_path().parent_path();
}

void log(const std::string& message)
{
    std::scoped_lock lock(g_log_mutex);
    const std::string line = "[MoreDropsNative] " + message + "\n";
    std::printf("%s", line.c_str());
    OutputDebugStringA(line.c_str());
    const auto directory = mod_directory();
    if (!directory.empty())
    {
        std::ofstream file(directory / L"MoreDropsNative.log", std::ios::app);
        file << line;
    }
}

std::string trim(std::string value)
{
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return {};
    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

std::string normalized_key(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character)
    {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

bool parse_multiplier(const std::string& text, float& target)
{
    try
    {
        std::size_t consumed{};
        const float value = std::stof(text, &consumed);
        if (!trim(text.substr(consumed)).empty() || !std::isfinite(value) || value < 1.0f || value > 100.0f)
            return false;
        target = value;
        return true;
    }
    catch (...)
    {
        return false;
    }
}

bool parse_percentage(const std::string& text, float& target)
{
    try
    {
        std::size_t consumed{};
        const float value = std::stof(text, &consumed);
        if (!trim(text.substr(consumed)).empty() || !std::isfinite(value) || value < 0.0f || value > 100.0f)
            return false;
        target = value;
        return true;
    }
    catch (...)
    {
        return false;
    }
}

std::string echo_rarity_name(std::uint8_t rarity)
{
    switch (rarity)
    {
    case 0: return "NotAssigned";
    case 1: return "Common";
    case 2: return "Uncommon";
    case 3: return "Rare";
    case 4: return "Epic";
    default: return "Unknown(" + std::to_string(rarity) + ")";
    }
}

std::string echo_rarity_mask_text(std::uint8_t mask)
{
    if (mask == all_echo_rarities) return "All";
    if (mask == 0) return "None";
    std::string result;
    for (std::uint8_t rarity = 1; rarity <= 4; ++rarity)
    {
        if ((mask & (1u << rarity)) == 0) continue;
        if (!result.empty()) result += ',';
        result += echo_rarity_name(rarity);
    }
    return result;
}

bool parse_echo_rarities(const std::string& text, std::uint8_t& target)
{
    const std::string value = normalized_key(trim(text));
    if (value == "all")
    {
        target = all_echo_rarities;
        return true;
    }
    if (value == "none")
    {
        target = 0;
        return true;
    }

    std::uint8_t mask{};
    std::stringstream values(value);
    std::string rarity;
    bool found{};
    while (std::getline(values, rarity, ','))
    {
        rarity = trim(rarity);
        std::uint8_t number{};
        if (rarity == "common") number = 1;
        else if (rarity == "uncommon") number = 2;
        else if (rarity == "rare") number = 3;
        else if (rarity == "epic") number = 4;
        else return false;
        mask |= static_cast<std::uint8_t>(1u << number);
        found = true;
    }
    if (!found) return false;
    target = mask;
    return true;
}

bool load_config(bool reloaded = false)
{
    const auto path = mod_directory() / L"config.ini";
    std::ifstream file(path);
    if (!file)
    {
        if (!g_config_error_logged)
        {
            log("Config unavailable path=" + path.string());
            g_config_error_logged = true;
        }
        return false;
    }

    Settings next = g_settings;
    next.item_probabilities.clear();
    std::string line;
    std::string section{"general"};
    bool has_core_probability{};
    while (std::getline(file, line))
    {
        line = trim(line);
        if (line.empty() || line.front() == '#' || line.front() == ';') continue;
        if (line.front() == '[' && line.back() == ']')
        {
            section = normalized_key(trim(line.substr(1, line.size() - 2)));
            continue;
        }
        const auto equals = line.find('=');
        if (equals == std::string::npos) continue;
        const std::string key = trim(line.substr(0, equals));
        const std::string value = trim(line.substr(equals + 1));
        if (section == "itemprobability")
        {
            float probability{};
            if (key.empty() || !parse_percentage(value, probability))
            {
                log("Invalid ItemProbability " + key + "=" + value + "; use 0 through 100");
                const auto existing = g_settings.item_probabilities.find(normalized_key(key));
                if (existing != g_settings.item_probabilities.end())
                    next.item_probabilities.emplace(existing->first, existing->second);
            }
            else
                next.item_probabilities[normalized_key(key)] = probability;
            continue;
        }
        if (section == "echofilter")
        {
            if (key == "AllowedRarities"
                && !parse_echo_rarities(value, next.echo_rarity_mask))
            {
                log("Invalid AllowedRarities=" + value
                    + "; use All, None, or Common,Uncommon,Rare,Epic");
            }
            continue;
        }
        if (section != "general") continue;
        float* setting{};
        if (key == "CoreProbabilityMultiplier")
        {
            setting = &next.core_probability;
            has_core_probability = true;
        }
        else if (key == "FinalProbabilityMultiplier") setting = &next.final_probability;
        else if (key == "ProbabilityMultiplier" && !has_core_probability) setting = &next.core_probability;
        else if (key == "MinAmountMultiplier") setting = &next.minimum;
        else if (key == "MaxAmountMultiplier") setting = &next.maximum;
        if (setting && !parse_multiplier(value, *setting))
            log("Invalid " + key + "=" + value + "; using " + std::to_string(*setting));
    }

    g_settings = std::move(next);
    std::error_code error;
    const auto write_time = std::filesystem::last_write_time(path, error);
    if (!error)
    {
        g_config_write_time = write_time;
        g_config_write_time_valid = true;
    }
    else
    {
        g_config_write_time_valid = false;
    }
    g_config_error_logged = false;

    std::ostringstream out;
    out << std::fixed << std::setprecision(2)
        << (reloaded ? "Config reloaded core_probability=" : "Config core_probability=")
        << g_settings.core_probability
        << " final_probability=" << g_settings.final_probability
        << " minimum=" << g_settings.minimum
        << " maximum=" << g_settings.maximum
        << " item_probability_rules=" << g_settings.item_probabilities.size()
        << " echo_rarities_requested=" << echo_rarity_mask_text(g_settings.echo_rarity_mask)
        << " echo_filter="
        << (g_echo_hooks_active ? "active" : (g_hook_install_complete ? "unavailable" : "pending"))
        << " path=" << path.string();
    log(out.str());
    const double combined_probability = static_cast<double>(g_settings.core_probability)
        * static_cast<double>(g_settings.final_probability);
    if (combined_probability > 100.0)
    {
        std::ostringstream warning;
        warning << std::fixed << std::setprecision(2)
            << "High loot workload warning combined_probability_multiplier="
            << combined_probability
            << " Reduce CoreProbabilityMultiplier or FinalProbabilityMultiplier";
        log(warning.str());
    }
    return true;
}

void maybe_reload_config()
{
    const auto now = std::chrono::steady_clock::now();
    if (now < g_next_config_check) return;
    g_next_config_check = now + std::chrono::seconds(1);

    const auto path = mod_directory() / L"config.ini";
    std::error_code error;
    const auto write_time = std::filesystem::last_write_time(path, error);
    if (error)
    {
        if (!g_config_error_logged)
        {
            log("Config reload unavailable: " + error.message() + " path=" + path.string());
            g_config_error_logged = true;
        }
        return;
    }

    g_config_error_logged = false;
    if (g_config_write_time_valid && write_time == g_config_write_time) return;
    load_config(true);
}

float scaled_value(float value, float multiplier)
{
    if (!std::isfinite(value)) return value;
    const double scaled = static_cast<double>(value) * multiplier;
    const double limit = std::numeric_limits<float>::max();
    return static_cast<float>(std::clamp(scaled, -limit, limit));
}

bool valid_array(const ArrayView& array)
{
    return array.count >= 0
        && array.count <= maximum_array_count
        && array.capacity >= array.count
        && (array.count == 0 || array.data != nullptr);
}

bool readable_range(const void* pointer, std::size_t size)
{
    if (!pointer || size == 0) return false;
    MEMORY_BASIC_INFORMATION information{};
    if (!VirtualQuery(pointer, &information, sizeof(information))) return false;
    if (information.State != MEM_COMMIT || (information.Protect & (PAGE_GUARD | PAGE_NOACCESS))) return false;
    const auto start = reinterpret_cast<std::uintptr_t>(pointer);
    const auto region_start = reinterpret_cast<std::uintptr_t>(information.BaseAddress);
    const auto region_end = region_start + information.RegionSize;
    return start >= region_start && start <= region_end && size <= region_end - start;
}

std::string wide_to_utf8(const wchar_t* value, std::size_t length)
{
    if (!value || length == 0) return {};
    const int required = WideCharToMultiByte(
        CP_UTF8, 0, value, static_cast<int>(length), nullptr, 0, nullptr, nullptr);
    if (required <= 0) return {};
    std::string result(static_cast<std::size_t>(required), '\0');
    WideCharToMultiByte(
        CP_UTF8, 0, value, static_cast<int>(length), result.data(), required, nullptr, nullptr);
    return result;
}

std::string name_text(const NameView& name)
{
    if (!g_name_to_string) return "<unavailable>";
    thread_local UnrealStringView output{};
    output.count = 0;
    g_name_to_string(&name, &output);
    if (!output.data || output.count <= 0 || output.count > 4096
        || output.capacity < output.count
        || !readable_range(output.data, static_cast<std::size_t>(output.count) * sizeof(wchar_t)))
        return "<unsupported-name>";
    std::size_t length = static_cast<std::size_t>(output.count);
    if (length > 0 && output.data[length - 1] == L'\0') --length;
    return wide_to_utf8(output.data, length);
}

struct ItemIdentity
{
    std::string row_name;
    std::string data_table;
    std::string key;
};

ItemIdentity item_identity(const DataTableRowHandleView& data)
{
    ItemIdentity identity;
    identity.row_name = name_text(data.row_name);
    if (readable_range(data.data_table, 0x20))
    {
        NameView table_name{};
        std::memcpy(
            &table_name,
            static_cast<const std::byte*>(data.data_table) + 0x18,
            sizeof(table_name));
        identity.data_table = name_text(table_name);
    }
    else
    {
        identity.data_table = "<none>";
    }
    identity.key = identity.data_table == "<none>"
        ? identity.row_name
        : identity.data_table + ":" + identity.row_name;
    return identity;
}

ItemIdentity item_identity(const InventoryItemCreationParamsView& item)
{
    return item_identity(item.data);
}

void log_echo_roll(
    std::uint64_t call,
    const std::string& item_key,
    std::uint8_t rarity,
    const char* decision)
{
    if (call > diagnostic_echo_limit) return;
    std::ostringstream out;
    out << "Echo roll diagnostic call=" << call
        << " item_key=" << item_key
        << " rarity=" << echo_rarity_name(rarity)
        << " allowed_rarities=" << echo_rarity_mask_text(g_settings.echo_rarity_mask)
        << " decision=" << decision;
    log(out.str());
    if (call == diagnostic_echo_limit)
        log("Echo diagnostic limit reached; Echo filtering remains active");
}

void __fastcall assign_echo_rarity_hook(
    EchoItemView* item,
    void* inventory,
    std::int32_t value,
    std::int32_t level)
{
    g_assign_echo_rarity(item, inventory, value, level);
    if (g_loot_spawn_depth == 0) return;

    const auto call = g_echo_roll_count.fetch_add(1) + 1;
    if (!item || !readable_range(item, offsetof(EchoItemView, echo_rarity) + 1))
    {
        if (call <= diagnostic_echo_limit)
            log("Echo roll diagnostic call=" + std::to_string(call)
                + " decision=keep-fail-open reason=invalid-temporary-item");
        return;
    }

    bool rejection_queued{};
    try
    {
        const std::uint8_t rarity = item->echo_rarity;
        const ItemIdentity identity = item_identity(item->data);
        if (rarity < 1 || rarity > 4)
        {
            log_echo_roll(call, identity.key, rarity, "keep-fail-open");
            return;
        }

        const bool allowed = (g_settings.echo_rarity_mask & (1u << rarity)) != 0;
        if (allowed)
        {
            log_echo_roll(call, identity.key, rarity, "allow");
            return;
        }

        g_pending_echo_rejections.push_back({item, call, rarity, identity.key});
        rejection_queued = true;
        log_echo_roll(call, identity.key, rarity, "reject-pending");
    }
    catch (...)
    {
        if (rejection_queued
            && !g_pending_echo_rejections.empty()
            && g_pending_echo_rejections.back().item == item)
            g_pending_echo_rejections.pop_back();
        if (call <= diagnostic_echo_limit)
            log("Echo roll diagnostic call=" + std::to_string(call)
                + " decision=keep-fail-open reason=diagnostic-error");
    }
}

void* echo_gate_target(const EchoItemView* item) noexcept
{
    if (g_loot_spawn_depth != 0 && item)
    {
        const auto match = std::find_if(
            g_pending_echo_rejections.rbegin(),
            g_pending_echo_rejections.rend(),
            [item](const PendingEchoRejection& pending)
            {
                return pending.item == item;
            });
        if (match != g_pending_echo_rejections.rend())
        {
            const PendingEchoRejection pending = std::move(*match);
            g_pending_echo_rejections.erase(std::next(match).base());
            if (pending.call <= diagnostic_echo_limit)
            {
                try
                {
                    log("Echo filter diagnostic call=" + std::to_string(pending.call)
                        + " item_key=" + pending.item_key
                        + " rarity=" + echo_rarity_name(pending.rarity)
                        + " action=rejected-before-append");
                }
                catch (...)
                {
                }
            }
            return g_echo_cleanup_target;
        }
    }
    return g_echo_append_trampoline;
}

class LootSpawnScope
{
public:
    LootSpawnScope() { ++g_loot_spawn_depth; }
    ~LootSpawnScope() noexcept
    {
        if (--g_loot_spawn_depth != 0 || g_pending_echo_rejections.empty()) return;
        const auto count = g_pending_echo_rejections.size();
        g_pending_echo_rejections.clear();
        try
        {
            log("Echo filter fail-open pending_rejections=" + std::to_string(count)
                + " reason=normal-rejection-check-not-reached");
        }
        catch (...)
        {
        }
    }
};

const float* find_item_probability(const ItemIdentity& identity)
{
    auto match = g_settings.item_probabilities.find(normalized_key(identity.key));
    if (match != g_settings.item_probabilities.end()) return &match->second;
    match = g_settings.item_probabilities.find(normalized_key(identity.row_name));
    return match == g_settings.item_probabilities.end() ? nullptr : &match->second;
}

bool keep_item(float probability)
{
    if (probability <= 0.0f) return false;
    if (probability >= 100.0f) return true;
    thread_local std::mt19937 generator(std::random_device{}());
    std::uniform_real_distribution<float> distribution(0.0f, 100.0f);
    return distribution(generator) < probability;
}

void log_item(std::uint64_t call, const char* destination,
    const InventoryItemCreationParamsView& item, const ItemIdentity& identity,
    const float* probability, bool kept)
{
    const auto number = g_item_log_count.fetch_add(1) + 1;
    if (number > diagnostic_item_limit) return;
    std::ostringstream out;
    out << std::fixed << std::setprecision(2)
        << "Item diagnostic call=" << call
        << " destination=" << destination
        << " item_key=" << identity.key
        << " amount=" << item.amount
        << " level=" << item.level
        << " item_probability=";
    if (probability) out << *probability;
    else out << "default";
    out << " action=" << (kept ? "kept" : "removed");
    log(out.str());
    if (number == diagnostic_item_limit)
        log("Item diagnostic limit reached; item filtering remains active");
}

struct ItemFilterStats
{
    std::int32_t examined{};
    std::int32_t removed{};
    std::int64_t removed_units{};
};

ItemFilterStats filter_item_array(std::uint64_t call, ArrayView& array, const char* destination)
{
    ItemFilterStats stats;
    if (!valid_array(array)) return stats;
    auto* items = static_cast<InventoryItemCreationParamsView*>(array.data);
    std::int32_t write_index{};
    for (std::int32_t read_index = 0; read_index < array.count; ++read_index)
    {
        auto& item = items[read_index];
        const ItemIdentity identity = item_identity(item);
        const float* probability = find_item_probability(identity);
        const bool kept = !probability || keep_item(*probability);
        ++stats.examined;
        log_item(call, destination, item, identity, probability, kept);
        if (kept)
        {
            if (write_index != read_index)
                std::memmove(&items[write_index], &item, sizeof(item));
            ++write_index;
        }
        else
        {
            ++stats.removed;
            stats.removed_units += std::max(item.amount, 0);
        }
    }
    array.count = write_index;
    return stats;
}

void filter_core_result(std::uint64_t call, CoreResultView* result)
{
    if (!result || !g_name_to_string) return;
    ItemFilterStats total;
    for (const auto& part : {
        filter_item_array(call, result->manifest_items, "inventory"),
        filter_item_array(call, result->manifest_items_as_pickups, "pickup-item"),
        filter_item_array(call, result->manifest_items_as_fauxjectiles, "faux-item")})
    {
        total.examined += part.examined;
        total.removed += part.removed;
        total.removed_units += part.removed_units;
    }
    if (call <= diagnostic_call_limit && (total.examined > 0 || !g_settings.item_probabilities.empty()))
    {
        std::ostringstream out;
        out << "Item filter diagnostic call=" << call
            << " examined=" << total.examined
            << " removed=" << total.removed
            << " removed_units=" << total.removed_units
            << " rules=" << g_settings.item_probabilities.size();
        log(out.str());
    }
}

std::int64_t sum_array_field(const ArrayView& array, std::size_t stride, std::size_t offset)
{
    if (!valid_array(array)) return -1;
    std::int64_t total{};
    auto* data = static_cast<const std::byte*>(array.data);
    for (std::int32_t index = 0; index < array.count; ++index)
    {
        std::int32_t value{};
        std::memcpy(&value, data + static_cast<std::size_t>(index) * stride + offset, sizeof(value));
        total += value;
    }
    return total;
}

std::string pointer_text(const void* pointer)
{
    std::ostringstream out;
    out << pointer;
    return out.str();
}

void log_entry(const char* stage, std::atomic<std::uint64_t>& counter,
    std::uint64_t call, std::int32_t index, const OriginalEntry& original)
{
    const auto number = counter.fetch_add(1) + 1;
    if (number > diagnostic_entry_limit) return;
    std::ostringstream out;
    out << std::setprecision(6)
        << stage << " Entry diagnostic call=" << call
        << " entry=" << index
        << " probability=" << original.probability << "->" << original.entry->probability
        << " minimum=" << original.minimum << "->" << original.entry->minimum
        << " maximum=" << original.maximum << "->" << original.entry->maximum;
    log(out.str());
    if (number == diagnostic_entry_limit)
        log(std::string(stage) + " Entry diagnostic limit reached; scaling remains active");
}

void log_result(std::uint64_t call, const void* source, const LootResultView* result,
    std::int32_t entry_count)
{
    if (call > diagnostic_call_limit || !result) return;
    std::ostringstream out;
    out << "Result diagnostic call=" << call
        << " source=" << pointer_text(source)
        << " entries=" << entry_count
        << " player_items=" << result->player_items.count
        << " player_item_units=" << sum_array_field(result->player_items, 0x1a8, 0x20)
        << " player_pickups=" << result->player_pickups.count
        << " manifest_items=" << result->manifest_items.count
        << " manifest_item_units=" << sum_array_field(result->manifest_items, 0x20, 0x10)
        << " manifest_pickup_items=" << result->manifest_items_as_pickups.count
        << " manifest_pickup_units=" << sum_array_field(result->manifest_items_as_pickups, 0x20, 0x10)
        << " manifest_faux_items=" << result->manifest_items_as_fauxjectiles.count
        << " manifest_faux_units=" << sum_array_field(result->manifest_items_as_fauxjectiles, 0x20, 0x10)
        << " manifest_pickups=" << result->manifest_pickups.count;
    log(out.str());
}

void log_core_result(std::uint64_t call, const void* source, const CoreResultView* result,
    std::int32_t entry_count, std::int32_t changed_count)
{
    if (call > diagnostic_call_limit || !result) return;
    std::ostringstream out;
    out << "Core result diagnostic call=" << call
        << " source=" << pointer_text(source)
        << " entries=" << entry_count
        << " changed=" << changed_count
        << " manifest_items=" << result->manifest_items.count
        << " manifest_item_units=" << sum_array_field(result->manifest_items, 0x20, 0x10)
        << " manifest_pickup_items=" << result->manifest_items_as_pickups.count
        << " manifest_pickup_units=" << sum_array_field(result->manifest_items_as_pickups, 0x20, 0x10)
        << " manifest_faux_items=" << result->manifest_items_as_fauxjectiles.count
        << " manifest_faux_units=" << sum_array_field(result->manifest_items_as_fauxjectiles, 0x20, 0x10)
        << " manifest_pickups=" << result->manifest_pickups.count;
    log(out.str());
}

LootResultView* __fastcall spawn_loot_hook(
    void* self,
    LootResultView* result,
    LootTableRecordView* record,
    void* source,
    void* context)
{
    const auto call = g_result_call_count.fetch_add(1) + 1;
    if (!record || !valid_array(record->loot)
        || std::find(g_active_final_records.begin(), g_active_final_records.end(), record)
            != g_active_final_records.end())
    {
        LootResultView* returned{};
        {
            LootSpawnScope scope;
            returned = g_spawn_loot(self, result, record, source, context);
        }
        log_result(call, source, result, record && valid_array(record->loot) ? record->loot.count : -1);
        return returned;
    }

    std::scoped_lock lock(g_loot_mutex);
    maybe_reload_config();
    g_active_final_records.push_back(record);
    auto* entries = static_cast<LootEntryView*>(record->loot.data);
    std::vector<OriginalEntry> originals;
    originals.reserve(static_cast<std::size_t>(record->loot.count));

    for (std::int32_t index = 0; index < record->loot.count; ++index)
    {
        auto& entry = entries[index];
        originals.push_back({&entry, entry.probability, entry.minimum, entry.maximum});
        entry.probability = scaled_value(entry.probability, g_settings.final_probability);
        if (entry.probability != originals.back().probability)
            log_entry("Final", g_final_entry_log_count, call, index, originals.back());
    }

    LootResultView* returned{};
    {
        LootSpawnScope scope;
        returned = g_spawn_loot(self, result, record, source, context);
    }
    log_result(call, source, result, record && valid_array(record->loot) ? record->loot.count : -1);

    for (const auto& original : originals)
        original.entry->probability = original.probability;
    g_active_final_records.pop_back();
    return returned;
}

CoreResultView* __fastcall generate_loot_hook(
    void* self,
    CoreResultView* result,
    LootTableRecordView* record,
    void* source,
    void* context)
{
    if (!record || !valid_array(record->loot)
        || std::find(g_active_records.begin(), g_active_records.end(), record) != g_active_records.end())
        return g_generate_loot(self, result, record, source, context);

    std::scoped_lock lock(g_loot_mutex);
    maybe_reload_config();
    const bool outermost = g_active_records.empty();
    g_active_records.push_back(record);
    const auto call = g_core_call_count.fetch_add(1) + 1;
    auto* entries = static_cast<LootEntryView*>(record->loot.data);
    std::vector<OriginalEntry> originals;
    originals.reserve(static_cast<std::size_t>(record->loot.count));
    std::int32_t changed_count{};

    for (std::int32_t index = 0; index < record->loot.count; ++index)
    {
        auto& entry = entries[index];
        originals.push_back({&entry, entry.probability, entry.minimum, entry.maximum});
        entry.probability = scaled_value(entry.probability, g_settings.core_probability);
        entry.minimum = scaled_value(entry.minimum, g_settings.minimum);
        entry.maximum = scaled_value(entry.maximum, g_settings.maximum);
        if (entry.maximum < entry.minimum) entry.maximum = entry.minimum;
        const auto& original = originals.back();
        if (entry.probability != original.probability
            || entry.minimum != original.minimum
            || entry.maximum != original.maximum)
        {
            ++changed_count;
            log_entry("Core", g_core_entry_log_count, call, index, original);
        }
    }

    CoreResultView* returned = g_generate_loot(self, result, record, source, context);
    CoreResultView* generated = returned ? returned : result;
    if (outermost) filter_core_result(call, generated);
    log_core_result(call, source, generated, record->loot.count, changed_count);

    for (const auto& original : originals)
    {
        original.entry->probability = original.probability;
        original.entry->minimum = original.minimum;
        original.entry->maximum = original.maximum;
    }
    g_active_records.pop_back();
    return returned;
}

bool install_echo_hooks(HMODULE wayfinder)
{
    constexpr unsigned char expected_rarity_prologue[] = {
        0x48, 0x89, 0x5c, 0x24, 0x10, 0x48, 0x89, 0x6c,
        0x24, 0x18, 0x56, 0x57, 0x41, 0x54, 0x41, 0x56,
        0x41, 0x57, 0x48, 0x83, 0xec, 0x20,
    };
    constexpr unsigned char expected_rarity_call_site[] = {
        0x45, 0x8b, 0xce, 0x44, 0x8b, 0x47, 0x14, 0x49,
        0x8b, 0xd4, 0x48, 0x8d, 0x4d, 0xa0, 0xe8, 0x71,
        0xe9, 0x00, 0x00,
    };
    constexpr unsigned char expected_append_gate[] = {
        0x48, 0x63, 0x5e, 0x08, 0x8d, 0x43, 0x01, 0x89,
        0x46, 0x08, 0x3b, 0x46, 0x0c, 0x7e, 0x0a, 0x8b,
        0xd3, 0x48, 0x8b, 0xce, 0xe8, 0xd7, 0x0e, 0xd3,
        0xff,
    };
    constexpr unsigned char expected_cleanup[] = {
        0x48, 0x8d, 0x4d, 0xc8, 0xe8, 0x8a, 0x81, 0xe0,
        0xff, 0x48, 0x8b, 0x9c, 0x24, 0x50, 0x04, 0x00,
        0x00,
    };

    auto* rarity_target = reinterpret_cast<unsigned char*>(wayfinder) + assign_echo_rarity_rva;
    auto* rarity_call_site = reinterpret_cast<unsigned char*>(wayfinder) + echo_rarity_call_site_rva;
    auto* append_target = reinterpret_cast<unsigned char*>(wayfinder) + echo_append_gate_rva;
    auto* cleanup_target = reinterpret_cast<unsigned char*>(wayfinder) + echo_cleanup_rva;
    if (std::memcmp(rarity_target, expected_rarity_prologue, sizeof(expected_rarity_prologue)) != 0
        || std::memcmp(
            rarity_call_site,
            expected_rarity_call_site,
            sizeof(expected_rarity_call_site)) != 0
        || std::memcmp(
            append_target,
            expected_append_gate,
            sizeof(expected_append_gate)) != 0
        || std::memcmp(cleanup_target, expected_cleanup, sizeof(expected_cleanup)) != 0)
    {
        log("Echo rarity filter unavailable: Wayfinder pre-append path signature mismatch");
        return false;
    }

    const MH_STATUS create_rarity = MH_CreateHook(
        rarity_target,
        reinterpret_cast<void*>(&assign_echo_rarity_hook),
        reinterpret_cast<void**>(&g_assign_echo_rarity));
    if (create_rarity != MH_OK)
    {
        log("Echo rarity filter unavailable: rarity hook creation failed status="
            + std::to_string(create_rarity));
        return false;
    }
    g_echo_cleanup_target = cleanup_target;
    const MH_STATUS create_append = MH_CreateHook(
        append_target,
        reinterpret_cast<void*>(&MoreDropsEchoAppendGate),
        reinterpret_cast<void**>(&g_echo_append_trampoline));
    if (create_append != MH_OK)
    {
        MH_RemoveHook(rarity_target);
        log("Echo rarity filter unavailable: pre-append hook creation failed status="
            + std::to_string(create_append));
        return false;
    }

    const MH_STATUS queue_rarity = MH_QueueEnableHook(rarity_target);
    const MH_STATUS queue_append = MH_QueueEnableHook(append_target);
    const MH_STATUS apply = queue_rarity == MH_OK && queue_append == MH_OK
        ? MH_ApplyQueued()
        : MH_UNKNOWN;
    if (queue_rarity != MH_OK || queue_append != MH_OK || apply != MH_OK)
    {
        MH_DisableHook(rarity_target);
        MH_DisableHook(append_target);
        MH_RemoveHook(rarity_target);
        MH_RemoveHook(append_target);
        log("Echo rarity filter unavailable: hook enable failed");
        return false;
    }

    g_echo_hooks_active = true;
    log("Echo rarity filter active roll=Wayfinder+0x178C0F0 gate=Wayfinder+0x177E1A0"
        " cleanup=Wayfinder+0x177E38D"
        " mode=pre-append-fail-open allowed_rarities="
        + echo_rarity_mask_text(g_settings.echo_rarity_mask));
    return true;
}

bool install_hooks()
{
    constexpr unsigned char expected_spawn_prologue[] = {
        0x48, 0x89, 0x5c, 0x24, 0x08, 0x48, 0x89, 0x74,
        0x24, 0x18, 0x48, 0x89, 0x54, 0x24, 0x10, 0x55,
        0x57, 0x41, 0x54, 0x41, 0x56, 0x41, 0x57, 0x48,
    };
    constexpr unsigned char expected_generate_prologue[] = {
        0x48, 0x8b, 0xc4, 0x48, 0x89, 0x58, 0x18, 0x4c,
        0x89, 0x48, 0x20, 0x48, 0x89, 0x50, 0x10, 0x48,
        0x89, 0x48, 0x08, 0x55, 0x56, 0x57, 0x41, 0x54,
    };
    constexpr unsigned char expected_name_to_string_prologue[] = {
        0x48, 0x89, 0x5c, 0x24, 0x10, 0x48, 0x89, 0x6c,
        0x24, 0x18, 0x48, 0x89, 0x74, 0x24, 0x20, 0x57,
        0x48, 0x83, 0xec, 0x30, 0x48, 0x8b, 0xda, 0x48,
    };
    HMODULE wayfinder = GetModuleHandleW(nullptr);
    if (!wayfinder)
    {
        log("Native scaler unavailable: Wayfinder module not found");
        return false;
    }
    auto* spawn_target = reinterpret_cast<unsigned char*>(wayfinder) + spawn_loot_rva;
    auto* generate_target = reinterpret_cast<unsigned char*>(wayfinder) + generate_loot_rva;
    auto* name_to_string_target = reinterpret_cast<unsigned char*>(wayfinder) + name_to_string_rva;
    if (std::memcmp(spawn_target, expected_spawn_prologue, sizeof(expected_spawn_prologue)) != 0)
    {
        log("Native scaler unavailable: result hook signature mismatch target=" + pointer_text(spawn_target));
        return false;
    }
    if (std::memcmp(generate_target, expected_generate_prologue, sizeof(expected_generate_prologue)) != 0)
    {
        log("Native scaler unavailable: core hook signature mismatch target=" + pointer_text(generate_target));
        return false;
    }
    if (std::memcmp(
            name_to_string_target,
            expected_name_to_string_prologue,
            sizeof(expected_name_to_string_prologue)) == 0)
    {
        g_name_to_string = reinterpret_cast<NameToStringFn>(name_to_string_target);
        log("Item identity active target=Wayfinder+0x1F08B30");
    }
    else
    {
        log("Item identity unavailable: FName signature mismatch; item rules are inactive");
    }
    if (MH_Initialize() != MH_OK)
    {
        log("Native scaler unavailable: MinHook initialization failed");
        return false;
    }
    g_mh = true;
    const MH_STATUS create_spawn = MH_CreateHook(
        spawn_target,
        reinterpret_cast<void*>(&spawn_loot_hook),
        reinterpret_cast<void**>(&g_spawn_loot));
    if (create_spawn != MH_OK)
    {
        log("Native scaler unavailable: result hook creation failed status=" + std::to_string(create_spawn));
        return false;
    }
    const MH_STATUS create_generate = MH_CreateHook(
        generate_target,
        reinterpret_cast<void*>(&generate_loot_hook),
        reinterpret_cast<void**>(&g_generate_loot));
    if (create_generate != MH_OK)
    {
        MH_RemoveHook(spawn_target);
        log("Native scaler unavailable: core hook creation failed status=" + std::to_string(create_generate));
        return false;
    }
    const MH_STATUS queue_spawn = MH_QueueEnableHook(spawn_target);
    const MH_STATUS queue_generate = MH_QueueEnableHook(generate_target);
    const MH_STATUS apply = queue_spawn == MH_OK && queue_generate == MH_OK
        ? MH_ApplyQueued()
        : MH_UNKNOWN;
    if (queue_spawn != MH_OK || queue_generate != MH_OK || apply != MH_OK)
    {
        MH_RemoveHook(spawn_target);
        MH_RemoveHook(generate_target);
        log("Native scaler unavailable: hook enable failed");
        return false;
    }
    log("Native scaler active core=Wayfinder+0x1B12B40 result=Wayfinder+0x1B09200");
    install_echo_hooks(wayfinder);
    return true;
}

void install()
{
    log("Native companion starting");
    load_config();
    install_hooks();
    g_hook_install_complete = true;
}

class UE4SSMod301
{
    struct Opaque {};
protected:
    std::vector<std::shared_ptr<void>> GUITabs{};
public:
    std::wstring ModName{L"MoreDropsNative"};
    std::wstring ModVersion{L"0.9.1"};
    std::wstring ModDescription{L"Scales Wayfinder loot probabilities and amounts."};
    std::wstring ModAuthors{L"Local companion implementation"};
    std::wstring ModIntendedSDKVersion{L"3.0.1"};

    virtual ~UE4SSMod301()
    {
        if (g_mh)
        {
            MH_DisableHook(MH_ALL_HOOKS);
            MH_Uninitialize();
        }
    }
    virtual void on_update() {}
    virtual void on_unreal_init() {}
    virtual void on_ui_init() {}
    virtual void on_program_start() { install(); }
    virtual void on_lua_start(const void*, Opaque&, Opaque&, Opaque&, std::vector<Opaque*>&) {}
    virtual void on_lua_start(Opaque&, Opaque&, Opaque&, std::vector<Opaque*>&) {}
    virtual void on_lua_stop(const void*, Opaque&, Opaque&, Opaque&, std::vector<Opaque*>&) {}
    virtual void on_lua_stop(Opaque&, Opaque&, Opaque&, std::vector<Opaque*>&) {}
    virtual void on_dll_load(const void*) {}
    virtual void render_tab() {}
};
}

extern "C" void* MoreDropsEchoGateTarget(const void* item)
{
    return echo_gate_target(static_cast<const EchoItemView*>(item));
}

extern "C" __declspec(dllexport) void* start_mod() { return new UE4SSMod301(); }
extern "C" __declspec(dllexport) void uninstall_mod(void* mod) { delete static_cast<UE4SSMod301*>(mod); }

BOOL APIENTRY DllMain(HMODULE, DWORD, LPVOID) { return TRUE; }
