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
std::atomic<int> g_limit{25};
bool g_mh{};
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

extern "C" __declspec(dllexport) void* start_mod() { return new UE4SSMod301(); }
extern "C" __declspec(dllexport) void uninstall_mod(void* mod) { delete static_cast<UE4SSMod301*>(mod); }

BOOL APIENTRY DllMain(HMODULE, DWORD, LPVOID) { return TRUE; }
