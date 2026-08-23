#include <Windows.h>
#include <MinHook.h>
#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <filesystem>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_set>
#include <vector>

namespace
{
using SteamApiCall = std::uint64_t;
using SteamId = std::uint64_t;
using CreateLobbyFn = SteamApiCall(__cdecl*)(void*, int, int);
using SetLobbyMemberLimitFn = bool(__cdecl*)(void*, SteamId, int);
using SetLobbyJoinableFn = bool(__cdecl*)(void*, SteamId, bool);
using InviteUserToLobbyFn = bool(__cdecl*)(void*, SteamId, SteamId);
using SteamMatchmakingFn = void*(__cdecl*)();
using SteamFriendsFn = void*(__cdecl*)();
using SetRichPresenceFn = bool(__cdecl*)(void*, const char*, const char*);
using ActivateInviteDialogFn = void(__cdecl*)(void*, SteamId);
using GetNumLobbyMembersFn = int(__cdecl*)(void*, SteamId);
using GetLobbyMemberLimitFn = int(__cdecl*)(void*, SteamId);
using GetLobbyOwnerFn = SteamId(__cdecl*)(void*, SteamId);

// EOS SDK 1.16.3 C ABI prefixes used only for diagnostics. These mirror the
// public EOS headers; trailing fields are intentionally not accessed.
using EosResult = std::int32_t;
struct EosLobbyCreateOptionsPrefix
{
    std::int32_t ApiVersion;
    std::int32_t Padding;
    void* LocalUserId;
    std::uint32_t MaxLobbyMembers;
};
struct EosSetMaxMembersOptions
{
    std::int32_t ApiVersion;
    std::uint32_t MaxMembers;
};
union EosAttributeValue
{
    std::int64_t AsInt64;
    double AsDouble;
    std::int32_t AsBool;
    const char* AsUtf8;
};
struct EosAttributeData
{
    std::int32_t ApiVersion;
    std::int32_t Padding;
    const char* Key;
    EosAttributeValue Value;
    std::int32_t ValueType;
};
struct EosSearchSetParameterOptions
{
    std::int32_t ApiVersion;
    std::int32_t Padding;
    const EosAttributeData* Parameter;
    std::int32_t ComparisonOp;
};
struct EosCreateSessionModificationOptionsPrefix
{
    std::int32_t ApiVersion;
    std::int32_t Padding;
    const char* SessionName;
    const char* BucketId;
    std::uint32_t MaxPlayers;
};
struct EosUpdateSessionModificationOptions
{
    std::int32_t ApiVersion;
    std::int32_t Padding;
    const char* SessionName;
};
struct EosSessionSetMaxPlayersOptions
{
    std::int32_t ApiVersion;
    std::uint32_t MaxPlayers;
};
struct EosSessionAddAttributeOptions
{
    std::int32_t ApiVersion;
    std::int32_t Padding;
    const EosAttributeData* SessionAttribute;
    std::int32_t AdvertisementType;
};
using EosLobbyCreateFn = void(__cdecl*)(void*, const EosLobbyCreateOptionsPrefix*, void*, void*);
using EosSetMaxMembersFn = EosResult(__cdecl*)(void*, const EosSetMaxMembersOptions*);
using EosSearchSetParameterFn = EosResult(__cdecl*)(void*, const EosSearchSetParameterOptions*);
using EosCreateSessionModificationFn = EosResult(__cdecl*)(void*, const EosCreateSessionModificationOptionsPrefix*, void**);
using EosUpdateSessionModificationFn = EosResult(__cdecl*)(void*, const EosUpdateSessionModificationOptions*, void**);
using EosSessionSetMaxPlayersFn = EosResult(__cdecl*)(void*, const EosSessionSetMaxPlayersOptions*);
using EosSessionAddAttributeFn = EosResult(__cdecl*)(void*, const EosSessionAddAttributeOptions*);

CreateLobbyFn g_create_lobby{};
SetLobbyMemberLimitFn g_set_limit{};
SetLobbyJoinableFn g_set_joinable{};
InviteUserToLobbyFn g_invite_user{};
SteamFriendsFn g_steam_friends{};
SetRichPresenceFn g_set_rich_presence{};
ActivateInviteDialogFn g_activate_invite_dialog{};
GetNumLobbyMembersFn g_get_num_lobby_members{};
GetLobbyMemberLimitFn g_get_lobby_member_limit{};
GetLobbyOwnerFn g_get_lobby_owner{};
EosLobbyCreateFn g_eos_lobby_create{};
EosSetMaxMembersFn g_eos_set_max_members{};
EosSearchSetParameterFn g_eos_lobby_search_parameter{};
EosSearchSetParameterFn g_eos_session_search_parameter{};
EosCreateSessionModificationFn g_eos_create_session_modification{};
EosUpdateSessionModificationFn g_eos_update_session_modification{};
EosSessionSetMaxPlayersFn g_eos_session_set_max_players{};
EosSessionAddAttributeFn g_eos_session_add_attribute{};
std::atomic<int> g_limit{25};
bool g_mh{};
std::atomic<bool> g_eos_installed{false};
std::atomic<bool> g_eos_wait_logged{false};
std::mutex g_log_mutex;
std::unordered_set<SteamId> g_invite_dialog_shown;

int limit() { return std::clamp(g_limit.load(), 3, 25); }
void log(const std::string& message);

std::filesystem::path config_path()
{
    HMODULE module{};
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(&g_limit), &module)) return {};
    wchar_t path[MAX_PATH]{};
    if (!GetModuleFileNameW(module, path, MAX_PATH)) return {};
    return std::filesystem::path(path).parent_path().parent_path() / L"config.ini";
}

void load_config()
{
    const auto path = config_path();
    std::ifstream file(path);
    std::string line;
    while (std::getline(file, line))
    {
        const auto equals = line.find('=');
        if (equals == std::string::npos || line.substr(0, equals).find("MaxPlayers") == std::string::npos) continue;
        try
        {
            const int configured = std::stoi(line.substr(equals + 1));
            if (configured < 3 || configured > 25) throw std::out_of_range("MaxPlayers");
            g_limit = configured;
            log("Config MaxPlayers=" + std::to_string(configured) + " path=" + path.string());
            return;
        }
        catch (...) { break; }
    }
    log("Config missing/invalid; using MaxPlayers=25 path=" + path.string());
    g_limit = 25;
}

std::string pointer_details(void* address)
{
    std::ostringstream out;
    out << address;
    HMODULE module{};
    if (address && GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(address), &module))
    {
        char path[MAX_PATH]{};
        if (GetModuleFileNameA(module, path, MAX_PATH)) out << " module=" << path;
    }
    return out.str();
}

void log(const std::string& message)
{
    std::scoped_lock lock(g_log_mutex);
    const std::string line = "[MorePlayersSteamLimit] " + message + "\n";
    std::printf("%s", line.c_str());
    OutputDebugStringA(line.c_str());
    std::ofstream file("MorePlayersSteamLimit.log", std::ios::app);
    file << line;
}

std::string safe_utf8(const char* value)
{
    if (!value || IsBadStringPtrA(value, 1)) return "<null/invalid>";
    return std::string(value, strnlen_s(value, 256));
}

std::string eos_attribute_value(const EosAttributeData* attribute)
{
    if (!attribute) return "<no attribute>";
    std::ostringstream out;
    // EOS_EAttributeType: Boolean=0, Int64=1, Double=2, String=3.
    switch (attribute->ValueType)
    {
    case 0: out << (attribute->Value.AsBool ? "true" : "false"); break;
    case 1: out << attribute->Value.AsInt64; break;
    case 2: out << attribute->Value.AsDouble; break;
    case 3: out << '"' << safe_utf8(attribute->Value.AsUtf8) << '"'; break;
    default: out << "<unknown type>"; break;
    }
    return out.str();
}

void __cdecl eos_lobby_create_hook(void* handle, const EosLobbyCreateOptionsPrefix* options,
    void* client_data, void* completion)
{
    if (options)
    {
        log("EOS Lobby_CreateLobby api=" + std::to_string(options->ApiVersion)
            + " max_members=" + std::to_string(options->MaxLobbyMembers));
    }
    else log("EOS Lobby_CreateLobby options=<null>");
    g_eos_lobby_create(handle, options, client_data, completion);
}

EosResult __cdecl eos_set_max_members_hook(void* modification, const EosSetMaxMembersOptions* options)
{
    if (options)
    {
        log("EOS LobbyModification_SetMaxMembers api=" + std::to_string(options->ApiVersion)
            + " max_members=" + std::to_string(options->MaxMembers));
    }
    else log("EOS LobbyModification_SetMaxMembers options=<null>");
    const EosResult result = g_eos_set_max_members(modification, options);
    log("EOS LobbyModification_SetMaxMembers result=" + std::to_string(result));
    return result;
}

void log_eos_search(const char* source, const EosSearchSetParameterOptions* options)
{
    if (!options || !options->Parameter)
    {
        log(std::string("EOS ") + source + " options/parameter=<null>");
        return;
    }
    const auto* attribute = options->Parameter;
    log(std::string("EOS ") + source + " options_api=" + std::to_string(options->ApiVersion)
        + " attribute_api=" + std::to_string(attribute->ApiVersion)
        + " key=" + safe_utf8(attribute->Key)
        + " type=" + std::to_string(attribute->ValueType)
        + " value=" + eos_attribute_value(attribute)
        + " comparison=" + std::to_string(options->ComparisonOp));
}

EosResult __cdecl eos_lobby_search_parameter_hook(void* search, const EosSearchSetParameterOptions* options)
{
    log_eos_search("LobbySearch_SetParameter", options);
    const EosResult result = g_eos_lobby_search_parameter(search, options);
    log("EOS LobbySearch_SetParameter result=" + std::to_string(result));
    return result;
}

EosResult __cdecl eos_session_search_parameter_hook(void* search, const EosSearchSetParameterOptions* options)
{
    log_eos_search("SessionSearch_SetParameter", options);
    const EosResult result = g_eos_session_search_parameter(search, options);
    log("EOS SessionSearch_SetParameter result=" + std::to_string(result));
    return result;
}

EosResult __cdecl eos_create_session_modification_hook(void* sessions,
    const EosCreateSessionModificationOptionsPrefix* options, void** out_modification)
{
    std::uint32_t original_max{};
    EosCreateSessionModificationOptionsPrefix* mutable_options{};
    if (options)
    {
        original_max = options->MaxPlayers;
        const std::uint32_t effective = std::max(original_max, static_cast<std::uint32_t>(limit()));
        mutable_options = const_cast<EosCreateSessionModificationOptionsPrefix*>(options);
        mutable_options->MaxPlayers = effective;
        log("EOS Sessions_CreateSessionModification api=" + std::to_string(options->ApiVersion)
            + " session=" + safe_utf8(options->SessionName)
            + " bucket=" + safe_utf8(options->BucketId)
            + " max_players=" + std::to_string(original_max) + " -> " + std::to_string(effective));
    }
    else log("EOS Sessions_CreateSessionModification options=<null>");
    const EosResult result = g_eos_create_session_modification(sessions, options, out_modification);
    if (mutable_options) mutable_options->MaxPlayers = original_max;
    log("EOS Sessions_CreateSessionModification result=" + std::to_string(result)
        + " modification=" + pointer_details(out_modification ? *out_modification : nullptr));
    return result;
}

EosResult __cdecl eos_update_session_modification_hook(void* sessions,
    const EosUpdateSessionModificationOptions* options, void** out_modification)
{
    if (options)
        log("EOS Sessions_UpdateSessionModification api=" + std::to_string(options->ApiVersion)
            + " session=" + safe_utf8(options->SessionName));
    else log("EOS Sessions_UpdateSessionModification options=<null>");
    const EosResult result = g_eos_update_session_modification(sessions, options, out_modification);
    log("EOS Sessions_UpdateSessionModification result=" + std::to_string(result)
        + " modification=" + pointer_details(out_modification ? *out_modification : nullptr));
    return result;
}

EosResult __cdecl eos_session_set_max_players_hook(void* modification,
    const EosSessionSetMaxPlayersOptions* options)
{
    std::uint32_t original_max{};
    EosSessionSetMaxPlayersOptions* mutable_options{};
    if (options)
    {
        original_max = options->MaxPlayers;
        const std::uint32_t effective = std::max(original_max, static_cast<std::uint32_t>(limit()));
        mutable_options = const_cast<EosSessionSetMaxPlayersOptions*>(options);
        mutable_options->MaxPlayers = effective;
        log("EOS SessionModification_SetMaxPlayers api=" + std::to_string(options->ApiVersion)
            + " max_players=" + std::to_string(original_max) + " -> " + std::to_string(effective)
            + " modification=" + pointer_details(modification));
    }
    else log("EOS SessionModification_SetMaxPlayers options=<null>");
    const EosResult result = g_eos_session_set_max_players(modification, options);
    if (mutable_options) mutable_options->MaxPlayers = original_max;
    log("EOS SessionModification_SetMaxPlayers result=" + std::to_string(result));
    return result;
}

EosResult __cdecl eos_session_add_attribute_hook(void* modification,
    const EosSessionAddAttributeOptions* options)
{
    EosAttributeData* mutable_attribute{};
    std::int64_t original_value{};
    bool capacity_override{};
    if (options && options->SessionAttribute)
    {
        const auto* attribute = options->SessionAttribute;
        const std::string key = safe_utf8(attribute->Key);
        if (key == "NumPublicConnections" && attribute->ValueType == 1)
        {
            original_value = attribute->Value.AsInt64;
            const std::int64_t effective = std::max(original_value, static_cast<std::int64_t>(limit()));
            mutable_attribute = const_cast<EosAttributeData*>(attribute);
            mutable_attribute->Value.AsInt64 = effective;
            capacity_override = true;
            log("EOS advertised NumPublicConnections " + std::to_string(original_value)
                + " -> " + std::to_string(effective));
        }
        log("EOS SessionModification_AddAttribute options_api=" + std::to_string(options->ApiVersion)
            + " attribute_api=" + std::to_string(attribute->ApiVersion)
            + " key=" + key
            + " type=" + std::to_string(attribute->ValueType)
            + " value=" + eos_attribute_value(attribute)
            + " advertisement=" + std::to_string(options->AdvertisementType)
            + " modification=" + pointer_details(modification));
    }
    else log("EOS SessionModification_AddAttribute options/attribute=<null>");
    const EosResult result = g_eos_session_add_attribute(modification, options);
    if (capacity_override) mutable_attribute->Value.AsInt64 = original_value;
    log("EOS SessionModification_AddAttribute result=" + std::to_string(result));
    return result;
}

void publish_invite_state(void* matchmaking, SteamId lobby)
{
    if (!lobby || !g_steam_friends || !g_set_rich_presence) return;
    void* friends = g_steam_friends();
    if (!friends) { log("SteamFriends_v017 returned null"); return; }

    const std::string lobby_text = std::to_string(lobby);
    const std::string connect = "+connect_lobby " + lobby_text;
    const std::string member_text = "1";

    const bool connect_ok = g_set_rich_presence(friends, "connect", connect.c_str());
    const bool group_ok = g_set_rich_presence(friends, "steam_player_group", lobby_text.c_str());
    const bool size_ok = g_set_rich_presence(friends, "steam_player_group_size", member_text.c_str());

    std::ostringstream out;
    out << "Published lobby " << lobby << " rich presence: connect=" << connect_ok
        << " group=" << group_ok << " size=" << size_ok;
    log(out.str());

    if (g_activate_invite_dialog && g_invite_dialog_shown.insert(lobby).second)
    {
        g_activate_invite_dialog(friends, lobby);
        log("Opened Steam invite dialog for lobby " + lobby_text);
    }
}

SteamApiCall __cdecl create_hook(void* self, int type, int requested)
{
    const int effective = std::max(requested, limit());
    log("CreateLobby " + std::to_string(requested) + " -> " + std::to_string(effective));
    const SteamApiCall call = g_create_lobby(self, type, effective);
    log("CreateLobby returned SteamAPICall=" + std::to_string(call) + " type=" + std::to_string(type));
    return call;
}

bool __cdecl limit_hook(void* self, SteamId lobby, int requested)
{
    const int effective = std::max(requested, limit());
    log("SetLobbyMemberLimit " + std::to_string(requested) + " -> " + std::to_string(effective)
        + " lobby=" + std::to_string(lobby));
    const bool result = g_set_limit(self, lobby, effective);
    log("SetLobbyMemberLimit result=" + std::to_string(result));
    publish_invite_state(self, lobby);
    return result;
}

bool __cdecl joinable_hook(void* self, SteamId lobby, bool requested)
{
    log("SetLobbyJoinable " + std::to_string(requested) + " -> 1 lobby=" + std::to_string(lobby));
    const bool result = g_set_joinable(self, lobby, true);
    log("SetLobbyJoinable result=" + std::to_string(result));
    publish_invite_state(self, lobby);
    return result;
}

bool __cdecl invite_user_hook(void* self, SteamId lobby, SteamId user)
{
    log("InviteUserToLobby lobby=" + std::to_string(lobby) + " user=" + std::to_string(user));
    // Refresh the limit and Steam join metadata immediately before the invite.
    if (g_set_limit) g_set_limit(self, lobby, limit());
    if (g_set_joinable) g_set_joinable(self, lobby, true);
    publish_invite_state(self, lobby);
    const bool result = g_invite_user(self, lobby, user);
    log("InviteUserToLobby result=" + std::to_string(result));
    return result;
}

bool hook(HMODULE dll, const char* export_name, void* replacement, void** original)
{
    void* target = reinterpret_cast<void*>(GetProcAddress(dll, export_name));
    if (!target || MH_CreateHook(target, replacement, original) != MH_OK || MH_EnableHook(target) != MH_OK)
    {
        log(std::string("Unable to hook ") + export_name);
        return false;
    }
    log(std::string("Hooked ") + export_name);
    return true;
}

bool hook_address(void* target, const char* label, void* replacement, void** original)
{
    log(std::string("Hook target ") + label + " address=" + pointer_details(target));
    if (!target || MH_CreateHook(target, replacement, original) != MH_OK || MH_EnableHook(target) != MH_OK)
    {
        log(std::string("Unable to hook ") + label);
        return false;
    }
    log(std::string("Hooked ") + label);
    return true;
}

void install_eos_diagnostics()
{
    if (g_eos_installed.load()) return;
    HMODULE eos = GetModuleHandleW(L"EOSSDK-Win64-Shipping.dll");
    if (!eos)
    {
        if (!g_eos_wait_logged.exchange(true))
            log("EOS diagnostics waiting for EOSSDK-Win64-Shipping.dll");
        return;
    }

    log("Installing EOS SDK 1.16.3 diagnostics module=" + pointer_details(eos));
    hook(eos, "EOS_Lobby_CreateLobby", reinterpret_cast<void*>(&eos_lobby_create_hook), reinterpret_cast<void**>(&g_eos_lobby_create));
    hook(eos, "EOS_LobbyModification_SetMaxMembers", reinterpret_cast<void*>(&eos_set_max_members_hook), reinterpret_cast<void**>(&g_eos_set_max_members));
    hook(eos, "EOS_LobbySearch_SetParameter", reinterpret_cast<void*>(&eos_lobby_search_parameter_hook), reinterpret_cast<void**>(&g_eos_lobby_search_parameter));
    hook(eos, "EOS_SessionSearch_SetParameter", reinterpret_cast<void*>(&eos_session_search_parameter_hook), reinterpret_cast<void**>(&g_eos_session_search_parameter));
    hook(eos, "EOS_Sessions_CreateSessionModification", reinterpret_cast<void*>(&eos_create_session_modification_hook), reinterpret_cast<void**>(&g_eos_create_session_modification));
    hook(eos, "EOS_Sessions_UpdateSessionModification", reinterpret_cast<void*>(&eos_update_session_modification_hook), reinterpret_cast<void**>(&g_eos_update_session_modification));
    hook(eos, "EOS_SessionModification_SetMaxPlayers", reinterpret_cast<void*>(&eos_session_set_max_players_hook), reinterpret_cast<void**>(&g_eos_session_set_max_players));
    hook(eos, "EOS_SessionModification_AddAttribute", reinterpret_cast<void*>(&eos_session_add_attribute_hook), reinterpret_cast<void**>(&g_eos_session_add_attribute));
    g_eos_installed = true;
    log("EOS diagnostics installed; options are forwarded unchanged");
}

void install()
{
    HMODULE steam = GetModuleHandleW(L"steam_api64.dll");
    log("Native companion starting");
    load_config();
    if (!steam) { log("steam_api64.dll not loaded"); return; }
    if (MH_Initialize() != MH_OK) { log("MinHook init failed"); return; }
    g_mh = true;
    // Wayfinder ships Steamworks v157, embeds SteamMatchMaking009, and acquires
    // it through SteamInternal_ContextInit. The crash-run trace proved that
    // v009 slot 31 receives (this, lobby, limit), returns true, and changes the
    // reported limit. Hook only this runtime-proven ABI entry.
    auto matchmaking_accessor = reinterpret_cast<SteamMatchmakingFn>(GetProcAddress(steam, "SteamAPI_SteamMatchmaking_v009"));
    void* matchmaking = matchmaking_accessor ? matchmaking_accessor() : nullptr;
    if (!matchmaking)
    {
        log("SteamAPI_SteamMatchmaking_v009 unavailable");
        return;
    }
    log("Steamworks ABI: SDK=v157 interface=SteamMatchMaking009 pointer=" + pointer_details(matchmaking));
    void** vtable = *reinterpret_cast<void***>(matchmaking);
    hook_address(vtable[31], "ISteamMatchmaking009::SetLobbyMemberLimit[v31]", reinterpret_cast<void*>(&limit_hook), reinterpret_cast<void**>(&g_set_limit));

    g_steam_friends = reinterpret_cast<SteamFriendsFn>(GetProcAddress(steam, "SteamAPI_SteamFriends_v017"));
    g_set_rich_presence = reinterpret_cast<SetRichPresenceFn>(GetProcAddress(steam, "SteamAPI_ISteamFriends_SetRichPresence"));
    g_activate_invite_dialog = reinterpret_cast<ActivateInviteDialogFn>(GetProcAddress(steam, "SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog"));
    g_get_num_lobby_members = reinterpret_cast<GetNumLobbyMembersFn>(GetProcAddress(steam, "SteamAPI_ISteamMatchmaking_GetNumLobbyMembers"));
    log(std::string("Invite API exports: friends=") + (g_steam_friends ? "1" : "0")
        + " rich_presence=" + (g_set_rich_presence ? "1" : "0")
        + " invite_dialog=" + (g_activate_invite_dialog ? "1" : "0")
        + " member_count=" + (g_get_num_lobby_members ? "1" : "0"));
    log("Post-hook diagnostics avoid unproven vtable getters");

    install_eos_diagnostics();
}

// ABI-compatible subset of UE4SS 3.0.1's CppUserModBase. The UE4SS loader
// receives this through the exported C entry point and invokes virtual events.
class UE4SSMod301
{
    struct Opaque {};
protected:
    std::vector<std::shared_ptr<void>> GUITabs{};
public:
    std::wstring ModName{L"MorePlayersSteamLimit"};
    std::wstring ModVersion{L"0.1.0"};
    std::wstring ModDescription{L"Raises Wayfinder's Steam lobby member limit to 25."};
    std::wstring ModAuthors{L"Local companion implementation"};
    std::wstring ModIntendedSDKVersion{L"3.0.1"};

    virtual ~UE4SSMod301()
    {
        if (g_mh) { MH_DisableHook(MH_ALL_HOOKS); MH_Uninitialize(); }
    }
    virtual void on_update() { if (g_mh && !g_eos_installed.load()) install_eos_diagnostics(); }
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

extern "C" __declspec(dllexport) void* start_mod() { return new UE4SSMod301(); }
extern "C" __declspec(dllexport) void uninstall_mod(void* mod) { delete static_cast<UE4SSMod301*>(mod); }

BOOL APIENTRY DllMain(HMODULE, DWORD, LPVOID) { return TRUE; }
