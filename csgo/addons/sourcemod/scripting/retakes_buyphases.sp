#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>
#include "include/retakes.inc"

#pragma semicolon 1
#pragma newdecls required

#define MENU_TIME_LENGTH 20

enum BuyPhase
{
    BuyPhase_Pistol = 0,
    BuyPhase_Force,
    BuyPhase_Full
};

enum PistolChoice
{
    Pistol_Default = 0,
    Pistol_USPS,
    Pistol_P250,
    Pistol_TecFive,
    Pistol_CZ,
    Pistol_Dualies,
    Pistol_Deagle,
    Pistol_Revolver
};

enum ForceChoice
{
    Force_MAC10MP9 = 0,
    Force_MAG7Sawedoff,
    Force_GalilFamas,
    Force_SSG08,
    Force_MP7,
    Force_MP5SD,
    Force_UMP45,
    Force_P90,
    Force_Bizon,
    Force_Nova,
    Force_XM1014
};

enum FullPrimaryChoice
{
    FullPrimary_TeamRifle = 0,
    FullPrimary_AK47,
    FullPrimary_M4A4,
    FullPrimary_M4A1S,
    FullPrimary_Galil,
    FullPrimary_Famas,
    FullPrimary_AUG,
    FullPrimary_SG556,
    FullPrimary_AWP,
    FullPrimary_SSG08,
    FullPrimary_AutoSniper,
    FullPrimary_MAC10MP9,
    FullPrimary_MP7,
    FullPrimary_MP5SD,
    FullPrimary_UMP45,
    FullPrimary_P90,
    FullPrimary_Bizon,
    FullPrimary_Nova,
    FullPrimary_XM1014,
    FullPrimary_MAG7Sawedoff,
    FullPrimary_Negev,
    FullPrimary_M249
};

BuyPhase g_CurrentPhase = BuyPhase_Pistol;
PistolChoice g_PistolChoice[MAXPLAYERS + 1];
ForceChoice g_ForceChoice[MAXPLAYERS + 1];
FullPrimaryChoice g_FullPrimaryChoice[MAXPLAYERS + 1];
PistolChoice g_FullSidearmChoice[MAXPLAYERS + 1];
bool g_HasPistolChoice[MAXPLAYERS + 1];
bool g_HasForceChoice[MAXPLAYERS + 1];
bool g_HasFullPrimaryChoice[MAXPLAYERS + 1];
bool g_HasFullSidearmChoice[MAXPLAYERS + 1];
bool g_HasSeenLoadoutPrompt[MAXPLAYERS + 1];

float g_LastDenyMessage[MAXPLAYERS + 1];
int g_Kills[MAXPLAYERS + 1];
int g_Deaths[MAXPLAYERS + 1];
int g_Plants[MAXPLAYERS + 1];
int g_Defuses[MAXPLAYERS + 1];
int g_Clutches[MAXPLAYERS + 1];

ConVar g_FreezetimeCvar;
ConVar g_PistolRoundsCvar;
ConVar g_ForceRoundsCvar;

Handle g_PistolCookie = INVALID_HANDLE;
Handle g_ForceCookie = INVALID_HANDLE;
Handle g_FullPrimaryCookie = INVALID_HANDLE;
Handle g_FullSidearmCookie = INVALID_HANDLE;
Handle g_LoadoutPromptCookie = INVALID_HANDLE;

public Plugin myinfo =
{
    name = "Retakes Buy Phases",
    author = "OpenAI",
    description = "Uses player-selected pistol/force/full retake loadouts.",
    version = "2.0.0",
    url = ""
};

public void OnPluginStart()
{
    g_FreezetimeCvar = CreateConVar("sm_retakes_buy_freezetime", "3", "Retake freeze time in seconds.", _, true, 1.0);
    g_PistolRoundsCvar = CreateConVar("sm_retakes_buy_pistol_rounds", "2", "Number of opening retake rounds using pistol loadouts.", _, true, 0.0);
    g_ForceRoundsCvar = CreateConVar("sm_retakes_buy_force_rounds", "3", "Number of retake rounds after pistol rounds using force loadouts.", _, true, 0.0);

    g_PistolCookie = RegClientCookie("retakes_loadout_pistol", "Retakes pistol loadout", CookieAccess_Private);
    g_ForceCookie = RegClientCookie("retakes_loadout_force", "Retakes force loadout", CookieAccess_Private);
    g_FullPrimaryCookie = RegClientCookie("retakes_loadout_full_primary", "Retakes full-buy primary loadout", CookieAccess_Private);
    g_FullSidearmCookie = RegClientCookie("retakes_loadout_full_sidearm", "Retakes full-buy sidearm loadout", CookieAccess_Private);
    g_LoadoutPromptCookie = RegClientCookie("retakes_loadout_prompted", "Retakes loadout prompt has been shown", CookieAccess_Private);

    AutoExecConfig(true, "retakes_buyphases");

    HookEvent("round_prestart", Event_RoundPreStart);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("bomb_planted", Event_BombPlanted);
    HookEvent("bomb_defused", Event_BombDefused);

    AddCommandListener(Command_Buy, "buy");
    AddCommandListener(Command_Buy, "buymenu");
    AddCommandListener(Command_Buy, "rebuy");
    AddCommandListener(Command_Buy, "autobuy");

    RegConsoleCmd("sm_stats", Command_Stats);
    RegConsoleCmd("sm_sessionstats", Command_Stats);

    ApplyBuyCvars();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            ResetStats(client);
            SetDefaultLoadouts(client);

            if (!IsFakeClient(client) && AreClientCookiesCached(client))
            {
                LoadClientLoadoutCookies(client);
            }
        }
    }
}

public void OnClientPutInServer(int client)
{
    ResetStats(client);
    SetDefaultLoadouts(client);
}

public void OnClientCookiesCached(int client)
{
    if (IsFakeClient(client))
    {
        return;
    }

    LoadClientLoadoutCookies(client);
}

void LoadClientLoadoutCookies(int client)
{
    bool hasPistolChoice = CookieHasValue(client, g_PistolCookie);
    bool hasForceChoice = CookieHasValue(client, g_ForceCookie);
    bool hasFullPrimaryChoice = CookieHasValue(client, g_FullPrimaryCookie);
    bool hasFullSidearmChoice = CookieHasValue(client, g_FullSidearmCookie);

    g_HasPistolChoice[client] = hasPistolChoice;
    g_HasForceChoice[client] = hasForceChoice;
    g_HasFullPrimaryChoice[client] = hasFullPrimaryChoice;
    g_HasFullSidearmChoice[client] = hasFullSidearmChoice;
    g_HasSeenLoadoutPrompt[client] = CookieHasValue(client, g_LoadoutPromptCookie)
        || hasPistolChoice
        || hasForceChoice
        || hasFullPrimaryChoice
        || hasFullSidearmChoice;

    if (hasPistolChoice)
    {
        g_PistolChoice[client] = view_as<PistolChoice>(ClampInt(GetCookieInt(client, g_PistolCookie), 0, view_as<int>(Pistol_Revolver)));
    }

    if (hasForceChoice)
    {
        g_ForceChoice[client] = view_as<ForceChoice>(ClampInt(GetCookieInt(client, g_ForceCookie), 0, view_as<int>(Force_XM1014)));
    }

    if (hasFullPrimaryChoice)
    {
        g_FullPrimaryChoice[client] = view_as<FullPrimaryChoice>(ClampInt(GetCookieInt(client, g_FullPrimaryCookie), 0, view_as<int>(FullPrimary_M249)));
    }

    if (hasFullSidearmChoice)
    {
        g_FullSidearmChoice[client] = view_as<PistolChoice>(ClampInt(GetCookieInt(client, g_FullSidearmCookie), 0, view_as<int>(Pistol_Revolver)));
    }

    if (g_HasSeenLoadoutPrompt[client] && !CookieHasValue(client, g_LoadoutPromptCookie))
    {
        SetCookieInt(client, g_LoadoutPromptCookie, 1);
    }
}

public void OnMapStart()
{
    ApplyBuyCvars();
}

public void OnConfigsExecuted()
{
    ApplyBuyCvars();
}

public Action Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
    if (Retakes_Live())
    {
        UpdateCurrentPhase();
        ApplyBuyCvars();
    }

    return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsActiveRetakePlayer(client))
    {
        return Plugin_Continue;
    }

    CreateTimer(0.3, Timer_ShowLoadoutHint, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(0.6, Timer_ShowMissingLoadoutMenu, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Timer_ShowLoadoutHint(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsActiveRetakePlayer(client))
    {
        return Plugin_Stop;
    }

    char phaseName[32];
    char primary[64];
    char secondary[64];

    GetPhaseName(g_CurrentPhase, phaseName, sizeof(phaseName));
    GetCurrentLoadoutNames(client, primary, sizeof(primary), secondary, sizeof(secondary));
    PrintHintText(client, "%s round: %s / %s | !guns changes loadouts", phaseName, primary, secondary);

    return Plugin_Stop;
}

public Action Timer_ShowMissingLoadoutMenu(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsActiveRetakePlayer(client) || !AreClientCookiesCached(client) || g_HasSeenLoadoutPrompt[client])
    {
        return Plugin_Stop;
    }

    MarkLoadoutPromptSeen(client);
    PrintToChat(client, "[Retakes] Choose loadouts now or use defaults. !guns changes them later.");
    ShowGunsMenu(client);

    return Plugin_Stop;
}

public void Retakes_OnWeaponsAllocated(ArrayList tPlayers, ArrayList ctPlayers, Bombsite bombsite)
{
    UpdateCurrentPhase();

    for (int i = 0; i < tPlayers.Length; i++)
    {
        AssignLoadout(tPlayers.Get(i), CS_TEAM_T);
    }

    for (int i = 0; i < ctPlayers.Length; i++)
    {
        AssignLoadout(ctPlayers.Get(i), CS_TEAM_CT);
    }
}

public void Retakes_OnGunsCommand(int client)
{
    if (!IsTrackedClient(client))
    {
        return;
    }

    ShowGunsMenu(client);
}

public Action Command_Buy(int client, const char[] command, int argc)
{
    if (!IsActiveRetakePlayer(client))
    {
        return Plugin_Continue;
    }

    DenyBuy(client, "Buying is disabled. Use !guns to choose pistol, force, and full-buy loadouts.");
    return Plugin_Handled;
}

public Action Command_Stats(int client, int args)
{
    if (!IsTrackedClient(client))
    {
        return Plugin_Handled;
    }

    PrintToChat(client, "[Stats] K:%d D:%d Plants:%d Defuses:%d Clutches:%d", g_Kills[client], g_Deaths[client], g_Plants[client], g_Defuses[client], g_Clutches[client]);
    return Plugin_Handled;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!Retakes_Live())
    {
        return Plugin_Continue;
    }

    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (IsTrackedClient(victim))
    {
        g_Deaths[victim]++;
    }

    if (IsTrackedClient(attacker) && attacker != victim)
    {
        g_Kills[attacker]++;
        if (IsPlayerAlive(attacker) && CountAliveTeam(GetClientTeam(attacker)) == 1 && CountAliveTeam(GetOtherTeam(GetClientTeam(attacker))) == 0)
        {
            g_Clutches[attacker]++;
            PrintToChatAll("[Stats] %N clutched the round.", attacker);
        }
    }

    return Plugin_Continue;
}

public Action Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    if (!Retakes_Live())
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsTrackedClient(client))
    {
        g_Plants[client]++;
    }

    return Plugin_Continue;
}

public Action Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
    if (!Retakes_Live())
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsTrackedClient(client))
    {
        g_Defuses[client]++;
    }

    return Plugin_Continue;
}

void AssignLoadout(int client, int team)
{
    if (!IsTrackedClient(client))
    {
        return;
    }

    char primary[WEAPON_STRING_LENGTH];
    char secondary[WEAPON_STRING_LENGTH];
    char nades[NADE_STRING_LENGTH];
    int health = 100;
    int kevlar = 100;
    bool helmet = false;
    bool kit = false;

    SetRandomNades(team, nades, sizeof(nades));

    switch (g_CurrentPhase)
    {
        case BuyPhase_Pistol:
        {
            primary[0] = '\0';
            GetPistolWeapon(team, g_PistolChoice[client], secondary, sizeof(secondary));
        }
        case BuyPhase_Force:
        {
            GetForceWeapon(team, g_ForceChoice[client], primary, sizeof(primary));
            GetPistolWeapon(team, Pistol_USPS, secondary, sizeof(secondary));
            helmet = true;
            kit = team == CS_TEAM_CT;
        }
        default:
        {
            GetFullPrimaryWeapon(team, g_FullPrimaryChoice[client], primary, sizeof(primary));
            GetPistolWeapon(team, g_FullSidearmChoice[client], secondary, sizeof(secondary));
            helmet = true;
            kit = team == CS_TEAM_CT;
        }
    }

    Retakes_SetPlayerInfo(client, primary, secondary, nades, health, kevlar, helmet, kit);
}

void SetRandomNades(int team, char[] nades, int maxlen)
{
    char pool[4];
    int poolSize = 0;

    pool[poolSize++] = 'h';
    pool[poolSize++] = 'f';
    pool[poolSize++] = 's';
    pool[poolSize++] = team == CS_TEAM_CT ? 'i' : 'm';

    int count = GetRandomInt(1, 2);
    nades[0] = '\0';

    for (int i = 0; i < count && i < maxlen - 1 && poolSize > 0; i++)
    {
        int index = GetRandomInt(0, poolSize - 1);
        int len = strlen(nades);
        nades[len] = pool[index];
        nades[len + 1] = '\0';

        for (int j = index; j < poolSize - 1; j++)
        {
            pool[j] = pool[j + 1];
        }
        poolSize--;
    }
}

void ShowGunsMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_Guns);
    SetMenuTitle(menu, "Guns loadouts");
    AddMenuItem(menu, "pistol", "Pistol loadout");
    AddMenuItem(menu, "force", "Force loadout");
    AddMenuItem(menu, "full", "Full buy loadout");
    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

public int MenuHandler_Guns(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        int client = param1;
        char info[16];
        GetMenuItem(menu, param2, info, sizeof(info));

        if (StrEqual(info, "pistol"))
        {
            ShowPistolMenu(client);
        }
        else if (StrEqual(info, "force"))
        {
            ShowForceCategoryMenu(client);
        }
        else
        {
            ShowFullCategoryMenu(client);
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }

    return 0;
}

void ShowPistolMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_Pistol);
    SetMenuTitle(menu, "Pistol loadout");
    int team = GetMenuTeam(client);

    AddPistolMenuItem(menu, client, Pistol_Default, team == CS_TEAM_CT ? "P2000" : "Glock-18");
    if (team == CS_TEAM_CT)
    {
        AddPistolMenuItem(menu, client, Pistol_USPS, "USP-S");
    }
    AddPistolMenuItem(menu, client, Pistol_P250, "P250");
    AddPistolMenuItem(menu, client, Pistol_TecFive, team == CS_TEAM_CT ? "Five-SeveN" : "Tec-9");
    AddPistolMenuItem(menu, client, Pistol_CZ, "CZ75-Auto");
    AddPistolMenuItem(menu, client, Pistol_Dualies, "Dual Berettas");
    AddPistolMenuItem(menu, client, Pistol_Deagle, "Desert Eagle");
    AddPistolMenuItem(menu, client, Pistol_Revolver, "R8 Revolver");
    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

public int MenuHandler_Pistol(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        int client = param1;
        g_PistolChoice[client] = view_as<PistolChoice>(GetMenuInt(menu, param2));
        g_HasPistolChoice[client] = true;
        SetCookieInt(client, g_PistolCookie, view_as<int>(g_PistolChoice[client]));
        PrintToChat(client, "[Retakes] Pistol loadout saved.");
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }

    return 0;
}

void ShowForceCategoryMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_ForceCategory);
    SetMenuTitle(menu, "Force-buy loadout");
    AddMenuItem(menu, "smg", "SMGs");
    AddMenuItem(menu, "shotgun", "Shotguns");
    AddMenuItem(menu, "rifle", "Rifles");
    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

public int MenuHandler_ForceCategory(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        int client = param1;
        char info[16];
        GetMenuItem(menu, param2, info, sizeof(info));

        if (StrEqual(info, "smg"))
        {
            ShowForceSmgMenu(client);
        }
        else if (StrEqual(info, "shotgun"))
        {
            ShowForceShotgunMenu(client);
        }
        else
        {
            ShowForceRifleMenu(client);
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }

    return 0;
}

void ShowForceSmgMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_Force);
    SetMenuTitle(menu, "Force SMGs");
    int team = GetMenuTeam(client);

    AddForceMenuItem(menu, client, Force_MAC10MP9, team == CS_TEAM_CT ? "MP9" : "MAC-10");
    AddForceMenuItem(menu, client, Force_MP7, "MP7");
    AddForceMenuItem(menu, client, Force_MP5SD, "MP5-SD");
    AddForceMenuItem(menu, client, Force_UMP45, "UMP-45");
    AddForceMenuItem(menu, client, Force_P90, "P90");
    AddForceMenuItem(menu, client, Force_Bizon, "PP-Bizon");
    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

void ShowForceShotgunMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_Force);
    SetMenuTitle(menu, "Force shotguns");
    int team = GetMenuTeam(client);

    AddForceMenuItem(menu, client, Force_Nova, "Nova");
    AddForceMenuItem(menu, client, Force_XM1014, "XM1014");
    AddForceMenuItem(menu, client, Force_MAG7Sawedoff, team == CS_TEAM_CT ? "MAG-7" : "Sawed-Off");
    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

void ShowForceRifleMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_Force);
    SetMenuTitle(menu, "Force rifles");
    int team = GetMenuTeam(client);

    AddForceMenuItem(menu, client, Force_GalilFamas, team == CS_TEAM_CT ? "FAMAS" : "Galil AR");
    AddForceMenuItem(menu, client, Force_SSG08, "SSG 08");
    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

public int MenuHandler_Force(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        int client = param1;
        g_ForceChoice[client] = view_as<ForceChoice>(GetMenuInt(menu, param2));
        g_HasForceChoice[client] = true;
        SetCookieInt(client, g_ForceCookie, view_as<int>(g_ForceChoice[client]));
        PrintToChat(client, "[Retakes] Force-buy loadout saved.");
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }

    return 0;
}

void ShowFullCategoryMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_FullCategory);
    SetMenuTitle(menu, "Full-buy loadout");
    AddMenuItem(menu, "rifle", "Rifles");
    AddMenuItem(menu, "shotgun", "Shotguns");
    AddMenuItem(menu, "smg", "SMGs");
    AddMenuItem(menu, "heavy", "Heavy");
    AddMenuItem(menu, "pistol", "Pistols");
    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

public int MenuHandler_FullCategory(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        int client = param1;
        char info[16];
        GetMenuItem(menu, param2, info, sizeof(info));

        if (StrEqual(info, "rifle"))
        {
            ShowFullRifleMenu(client);
        }
        else if (StrEqual(info, "shotgun"))
        {
            ShowFullShotgunMenu(client);
        }
        else if (StrEqual(info, "smg"))
        {
            ShowFullSmgMenu(client);
        }
        else if (StrEqual(info, "heavy"))
        {
            ShowFullHeavyMenu(client);
        }
        else
        {
            ShowFullSidearmMenu(client);
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }

    return 0;
}

void ShowFullRifleMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_FullPrimary);
    SetMenuTitle(menu, "Full-buy rifles");
    int team = GetMenuTeam(client);

    if (team == CS_TEAM_CT)
    {
        AddFullPrimaryMenuItem(menu, client, FullPrimary_Famas, "FAMAS");
        AddFullPrimaryMenuItem(menu, client, FullPrimary_M4A4, "M4A4");
        AddFullPrimaryMenuItem(menu, client, FullPrimary_M4A1S, "M4A1-S");
        AddFullPrimaryMenuItem(menu, client, FullPrimary_AUG, "AUG");
        AddFullPrimaryMenuItem(menu, client, FullPrimary_SSG08, "SSG 08");
        AddFullPrimaryMenuItem(menu, client, FullPrimary_AWP, "AWP");
        AddFullPrimaryMenuItem(menu, client, FullPrimary_AutoSniper, "SCAR-20");
    }
    else
    {
        AddFullPrimaryMenuItem(menu, client, FullPrimary_Galil, "Galil AR");
        AddFullPrimaryMenuItem(menu, client, FullPrimary_AK47, "AK-47");
        AddFullPrimaryMenuItem(menu, client, FullPrimary_SG556, "SG 553");
        AddFullPrimaryMenuItem(menu, client, FullPrimary_SSG08, "SSG 08");
        AddFullPrimaryMenuItem(menu, client, FullPrimary_AWP, "AWP");
        AddFullPrimaryMenuItem(menu, client, FullPrimary_AutoSniper, "G3SG1");
    }

    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

void ShowFullShotgunMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_FullPrimary);
    SetMenuTitle(menu, "Full-buy shotguns");
    int team = GetMenuTeam(client);

    AddFullPrimaryMenuItem(menu, client, FullPrimary_Nova, "Nova");
    AddFullPrimaryMenuItem(menu, client, FullPrimary_XM1014, "XM1014");
    AddFullPrimaryMenuItem(menu, client, FullPrimary_MAG7Sawedoff, team == CS_TEAM_CT ? "MAG-7" : "Sawed-Off");
    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

void ShowFullSmgMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_FullPrimary);
    SetMenuTitle(menu, "Full-buy SMGs");
    int team = GetMenuTeam(client);

    AddFullPrimaryMenuItem(menu, client, FullPrimary_MAC10MP9, team == CS_TEAM_CT ? "MP9" : "MAC-10");
    AddFullPrimaryMenuItem(menu, client, FullPrimary_MP7, "MP7");
    AddFullPrimaryMenuItem(menu, client, FullPrimary_MP5SD, "MP5-SD");
    AddFullPrimaryMenuItem(menu, client, FullPrimary_UMP45, "UMP-45");
    AddFullPrimaryMenuItem(menu, client, FullPrimary_P90, "P90");
    AddFullPrimaryMenuItem(menu, client, FullPrimary_Bizon, "PP-Bizon");
    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

void ShowFullHeavyMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_FullPrimary);
    SetMenuTitle(menu, "Full-buy heavy");
    AddFullPrimaryMenuItem(menu, client, FullPrimary_Negev, "Negev");
    AddFullPrimaryMenuItem(menu, client, FullPrimary_M249, "M249");
    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

public int MenuHandler_FullPrimary(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        int client = param1;
        g_FullPrimaryChoice[client] = view_as<FullPrimaryChoice>(GetMenuInt(menu, param2));
        g_HasFullPrimaryChoice[client] = true;
        SetCookieInt(client, g_FullPrimaryCookie, view_as<int>(g_FullPrimaryChoice[client]));
        PrintToChat(client, "[Retakes] Full-buy primary saved.");
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }

    return 0;
}

void ShowFullSidearmMenu(int client)
{
    Handle menu = CreateMenu(MenuHandler_FullSidearm);
    SetMenuTitle(menu, "Full-buy pistols");
    int team = GetMenuTeam(client);

    AddFullSidearmMenuItem(menu, client, Pistol_Default, team == CS_TEAM_CT ? "P2000" : "Glock-18");
    if (team == CS_TEAM_CT)
    {
        AddFullSidearmMenuItem(menu, client, Pistol_USPS, "USP-S");
    }
    AddFullSidearmMenuItem(menu, client, Pistol_P250, "P250");
    AddFullSidearmMenuItem(menu, client, Pistol_TecFive, team == CS_TEAM_CT ? "Five-SeveN" : "Tec-9");
    AddFullSidearmMenuItem(menu, client, Pistol_CZ, "CZ75-Auto");
    AddFullSidearmMenuItem(menu, client, Pistol_Dualies, "Dual Berettas");
    AddFullSidearmMenuItem(menu, client, Pistol_Deagle, "Desert Eagle");
    AddFullSidearmMenuItem(menu, client, Pistol_Revolver, "R8 Revolver");
    DisplayMenu(menu, client, MENU_TIME_LENGTH);
}

public int MenuHandler_FullSidearm(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        int client = param1;
        g_FullSidearmChoice[client] = view_as<PistolChoice>(GetMenuInt(menu, param2));
        g_HasFullSidearmChoice[client] = true;
        SetCookieInt(client, g_FullSidearmCookie, view_as<int>(g_FullSidearmChoice[client]));
        PrintToChat(client, "[Retakes] Full-buy loadout saved.");
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }

    return 0;
}

void AddPistolMenuItem(Handle menu, int client, PistolChoice choice, const char[] label)
{
    AddCheckedMenuInt(menu, view_as<int>(choice), label, g_PistolChoice[client] == choice);
}

void AddForceMenuItem(Handle menu, int client, ForceChoice choice, const char[] label)
{
    AddCheckedMenuInt(menu, view_as<int>(choice), label, g_ForceChoice[client] == choice);
}

void AddFullPrimaryMenuItem(Handle menu, int client, FullPrimaryChoice choice, const char[] label)
{
    int team = GetMenuTeam(client);
    FullPrimaryChoice selectedChoice = GetTeamFullPrimaryChoice(team, g_FullPrimaryChoice[client]);
    AddCheckedMenuInt(menu, view_as<int>(choice), label, selectedChoice == choice);
}

void AddFullSidearmMenuItem(Handle menu, int client, PistolChoice choice, const char[] label)
{
    AddCheckedMenuInt(menu, view_as<int>(choice), label, g_FullSidearmChoice[client] == choice);
}

void AddCheckedMenuInt(Handle menu, int value, const char[] label, bool selected)
{
    char info[12];
    char display[96];
    IntToString(value, info, sizeof(info));
    Format(display, sizeof(display), "%s%s", selected ? "* " : "", label);
    AddMenuItem(menu, info, display);
}

int GetMenuInt(Handle menu, int item)
{
    char info[12];
    GetMenuItem(menu, item, info, sizeof(info));
    return StringToInt(info);
}

void GetPistolWeapon(int team, PistolChoice choice, char[] weapon, int maxlen)
{
    switch (choice)
    {
        case Pistol_USPS:
        {
            strcopy(weapon, maxlen, team == CS_TEAM_CT ? "weapon_usp_silencer" : "weapon_glock");
        }
        case Pistol_P250:
        {
            strcopy(weapon, maxlen, "weapon_p250");
        }
        case Pistol_TecFive:
        {
            strcopy(weapon, maxlen, team == CS_TEAM_CT ? "weapon_fiveseven" : "weapon_tec9");
        }
        case Pistol_CZ:
        {
            strcopy(weapon, maxlen, "weapon_cz75a");
        }
        case Pistol_Dualies:
        {
            strcopy(weapon, maxlen, "weapon_elite");
        }
        case Pistol_Deagle:
        {
            strcopy(weapon, maxlen, "weapon_deagle");
        }
        case Pistol_Revolver:
        {
            strcopy(weapon, maxlen, "weapon_revolver");
        }
        default:
        {
            strcopy(weapon, maxlen, team == CS_TEAM_CT ? "weapon_hkp2000" : "weapon_glock");
        }
    }
}

void GetForceWeapon(int team, ForceChoice choice, char[] weapon, int maxlen)
{
    switch (choice)
    {
        case Force_MAG7Sawedoff:
        {
            strcopy(weapon, maxlen, team == CS_TEAM_CT ? "weapon_mag7" : "weapon_sawedoff");
        }
        case Force_GalilFamas:
        {
            strcopy(weapon, maxlen, team == CS_TEAM_CT ? "weapon_famas" : "weapon_galilar");
        }
        case Force_SSG08:
        {
            strcopy(weapon, maxlen, "weapon_ssg08");
        }
        case Force_MP7:
        {
            strcopy(weapon, maxlen, "weapon_mp7");
        }
        case Force_MP5SD:
        {
            strcopy(weapon, maxlen, "weapon_mp5sd");
        }
        case Force_UMP45:
        {
            strcopy(weapon, maxlen, "weapon_ump45");
        }
        case Force_P90:
        {
            strcopy(weapon, maxlen, "weapon_p90");
        }
        case Force_Bizon:
        {
            strcopy(weapon, maxlen, "weapon_bizon");
        }
        case Force_Nova:
        {
            strcopy(weapon, maxlen, "weapon_nova");
        }
        case Force_XM1014:
        {
            strcopy(weapon, maxlen, "weapon_xm1014");
        }
        default:
        {
            strcopy(weapon, maxlen, team == CS_TEAM_CT ? "weapon_mp9" : "weapon_mac10");
        }
    }
}

void GetFullPrimaryWeapon(int team, FullPrimaryChoice choice, char[] weapon, int maxlen)
{
    choice = GetTeamFullPrimaryChoice(team, choice);

    switch (choice)
    {
        case FullPrimary_AK47: strcopy(weapon, maxlen, "weapon_ak47");
        case FullPrimary_M4A4: strcopy(weapon, maxlen, "weapon_m4a1");
        case FullPrimary_M4A1S: strcopy(weapon, maxlen, "weapon_m4a1_silencer");
        case FullPrimary_Galil: strcopy(weapon, maxlen, "weapon_galilar");
        case FullPrimary_Famas: strcopy(weapon, maxlen, "weapon_famas");
        case FullPrimary_AUG: strcopy(weapon, maxlen, "weapon_aug");
        case FullPrimary_SG556: strcopy(weapon, maxlen, "weapon_sg556");
        case FullPrimary_AWP: strcopy(weapon, maxlen, "weapon_awp");
        case FullPrimary_SSG08: strcopy(weapon, maxlen, "weapon_ssg08");
        case FullPrimary_AutoSniper: strcopy(weapon, maxlen, team == CS_TEAM_CT ? "weapon_scar20" : "weapon_g3sg1");
        case FullPrimary_MAC10MP9: strcopy(weapon, maxlen, team == CS_TEAM_CT ? "weapon_mp9" : "weapon_mac10");
        case FullPrimary_MP7: strcopy(weapon, maxlen, "weapon_mp7");
        case FullPrimary_MP5SD: strcopy(weapon, maxlen, "weapon_mp5sd");
        case FullPrimary_UMP45: strcopy(weapon, maxlen, "weapon_ump45");
        case FullPrimary_P90: strcopy(weapon, maxlen, "weapon_p90");
        case FullPrimary_Bizon: strcopy(weapon, maxlen, "weapon_bizon");
        case FullPrimary_Nova: strcopy(weapon, maxlen, "weapon_nova");
        case FullPrimary_XM1014: strcopy(weapon, maxlen, "weapon_xm1014");
        case FullPrimary_MAG7Sawedoff: strcopy(weapon, maxlen, team == CS_TEAM_CT ? "weapon_mag7" : "weapon_sawedoff");
        case FullPrimary_Negev: strcopy(weapon, maxlen, "weapon_negev");
        case FullPrimary_M249: strcopy(weapon, maxlen, "weapon_m249");
        default: strcopy(weapon, maxlen, team == CS_TEAM_CT ? "weapon_m4a1" : "weapon_ak47");
    }
}

void GetCurrentLoadoutNames(int client, char[] primary, int primaryMaxLen, char[] secondary, int secondaryMaxLen)
{
    int team = GetClientTeam(client);
    switch (g_CurrentPhase)
    {
        case BuyPhase_Pistol:
        {
            strcopy(primary, primaryMaxLen, "Pistol");
            GetPistolDisplayName(team, g_PistolChoice[client], secondary, secondaryMaxLen);
        }
        case BuyPhase_Force:
        {
            GetForceDisplayName(team, g_ForceChoice[client], primary, primaryMaxLen);
            GetPistolDisplayName(team, Pistol_USPS, secondary, secondaryMaxLen);
        }
        default:
        {
            GetFullPrimaryDisplayName(team, g_FullPrimaryChoice[client], primary, primaryMaxLen);
            GetPistolDisplayName(team, g_FullSidearmChoice[client], secondary, secondaryMaxLen);
        }
    }
}

void GetPistolDisplayName(int team, PistolChoice choice, char[] buffer, int maxlen)
{
    switch (choice)
    {
        case Pistol_USPS: strcopy(buffer, maxlen, team == CS_TEAM_CT ? "USP-S" : "Glock");
        case Pistol_P250: strcopy(buffer, maxlen, "P250");
        case Pistol_TecFive: strcopy(buffer, maxlen, team == CS_TEAM_CT ? "Five-SeveN" : "Tec-9");
        case Pistol_CZ: strcopy(buffer, maxlen, "CZ75-Auto");
        case Pistol_Dualies: strcopy(buffer, maxlen, "Dual Berettas");
        case Pistol_Deagle: strcopy(buffer, maxlen, "Desert Eagle");
        case Pistol_Revolver: strcopy(buffer, maxlen, "R8 Revolver");
        default: strcopy(buffer, maxlen, team == CS_TEAM_CT ? "P2000" : "Glock");
    }
}

void GetForceDisplayName(int team, ForceChoice choice, char[] buffer, int maxlen)
{
    switch (choice)
    {
        case Force_MAG7Sawedoff: strcopy(buffer, maxlen, team == CS_TEAM_CT ? "MAG-7" : "Sawed-Off");
        case Force_GalilFamas: strcopy(buffer, maxlen, team == CS_TEAM_CT ? "FAMAS" : "Galil AR");
        case Force_SSG08: strcopy(buffer, maxlen, "SSG 08");
        case Force_MP7: strcopy(buffer, maxlen, "MP7");
        case Force_MP5SD: strcopy(buffer, maxlen, "MP5-SD");
        case Force_UMP45: strcopy(buffer, maxlen, "UMP-45");
        case Force_P90: strcopy(buffer, maxlen, "P90");
        case Force_Bizon: strcopy(buffer, maxlen, "PP-Bizon");
        case Force_Nova: strcopy(buffer, maxlen, "Nova");
        case Force_XM1014: strcopy(buffer, maxlen, "XM1014");
        default: strcopy(buffer, maxlen, team == CS_TEAM_CT ? "MP9" : "MAC-10");
    }
}

void GetFullPrimaryDisplayName(int team, FullPrimaryChoice choice, char[] buffer, int maxlen)
{
    choice = GetTeamFullPrimaryChoice(team, choice);

    switch (choice)
    {
        case FullPrimary_AK47: strcopy(buffer, maxlen, "AK-47");
        case FullPrimary_M4A4: strcopy(buffer, maxlen, "M4A4");
        case FullPrimary_M4A1S: strcopy(buffer, maxlen, "M4A1-S");
        case FullPrimary_Galil: strcopy(buffer, maxlen, "Galil AR");
        case FullPrimary_Famas: strcopy(buffer, maxlen, "FAMAS");
        case FullPrimary_AUG: strcopy(buffer, maxlen, "AUG");
        case FullPrimary_SG556: strcopy(buffer, maxlen, "SG 553");
        case FullPrimary_AWP: strcopy(buffer, maxlen, "AWP");
        case FullPrimary_SSG08: strcopy(buffer, maxlen, "SSG 08");
        case FullPrimary_AutoSniper: strcopy(buffer, maxlen, "Auto sniper");
        case FullPrimary_MAC10MP9: strcopy(buffer, maxlen, "MAC-10 / MP9");
        case FullPrimary_MP7: strcopy(buffer, maxlen, "MP7");
        case FullPrimary_MP5SD: strcopy(buffer, maxlen, "MP5-SD");
        case FullPrimary_UMP45: strcopy(buffer, maxlen, "UMP-45");
        case FullPrimary_P90: strcopy(buffer, maxlen, "P90");
        case FullPrimary_Bizon: strcopy(buffer, maxlen, "PP-Bizon");
        case FullPrimary_Nova: strcopy(buffer, maxlen, "Nova");
        case FullPrimary_XM1014: strcopy(buffer, maxlen, "XM1014");
        case FullPrimary_MAG7Sawedoff: strcopy(buffer, maxlen, "MAG-7 / Sawed-Off");
        case FullPrimary_Negev: strcopy(buffer, maxlen, "Negev");
        case FullPrimary_M249: strcopy(buffer, maxlen, "M249");
        default: strcopy(buffer, maxlen, "Team rifle");
    }
}

void UpdateCurrentPhase()
{
    int currentRound = Retakes_GetRetakeRoundsPlayed() + 1;
    int pistolRounds = g_PistolRoundsCvar.IntValue;
    int forceRounds = g_ForceRoundsCvar.IntValue;

    if (currentRound <= pistolRounds)
    {
        g_CurrentPhase = BuyPhase_Pistol;
    }
    else if (currentRound <= pistolRounds + forceRounds)
    {
        g_CurrentPhase = BuyPhase_Force;
    }
    else
    {
        g_CurrentPhase = BuyPhase_Full;
    }
}

void ApplyBuyCvars()
{
    ServerCommand("mp_freezetime %d", g_FreezetimeCvar.IntValue);
    ServerCommand("mp_buytime 0.001");
    ServerCommand("mp_buy_anywhere 0");
    ServerCommand("mp_startmoney 0");
    ServerCommand("mp_playercashawards 0");
    ServerCommand("mp_teamcashawards 0");
}

bool IsActiveRetakePlayer(int client)
{
    return client > 0
        && client <= MaxClients
        && IsClientInGame(client)
        && !IsFakeClient(client)
        && IsPlayerAlive(client)
        && Retakes_Live()
        && Retakes_IsJoined(client)
        && (GetClientTeam(client) == CS_TEAM_T || GetClientTeam(client) == CS_TEAM_CT);
}

bool IsTrackedClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

void SetDefaultLoadouts(int client)
{
    g_PistolChoice[client] = Pistol_USPS;
    g_ForceChoice[client] = Force_MAC10MP9;
    g_FullPrimaryChoice[client] = FullPrimary_M4A1S;
    g_FullSidearmChoice[client] = Pistol_USPS;
    g_HasPistolChoice[client] = false;
    g_HasForceChoice[client] = false;
    g_HasFullPrimaryChoice[client] = false;
    g_HasFullSidearmChoice[client] = false;
    g_HasSeenLoadoutPrompt[client] = false;
}

void MarkLoadoutPromptSeen(int client)
{
    g_HasSeenLoadoutPrompt[client] = true;

    if (AreClientCookiesCached(client))
    {
        SetCookieInt(client, g_LoadoutPromptCookie, 1);
    }
}

int GetMenuTeam(int client)
{
    int team = GetClientTeam(client);
    if (team == CS_TEAM_T || team == CS_TEAM_CT)
    {
        return team;
    }

    return CS_TEAM_CT;
}

FullPrimaryChoice GetTeamFullPrimaryChoice(int team, FullPrimaryChoice choice)
{
    if (team == CS_TEAM_CT)
    {
        switch (choice)
        {
            case FullPrimary_AK47:
            {
                return FullPrimary_M4A4;
            }
            case FullPrimary_Galil:
            {
                return FullPrimary_Famas;
            }
            case FullPrimary_SG556:
            {
                return FullPrimary_AUG;
            }
        }
    }
    else
    {
        switch (choice)
        {
            case FullPrimary_M4A4, FullPrimary_M4A1S:
            {
                return FullPrimary_AK47;
            }
            case FullPrimary_Famas:
            {
                return FullPrimary_Galil;
            }
            case FullPrimary_AUG:
            {
                return FullPrimary_SG556;
            }
        }
    }

    return choice;
}

void ResetStats(int client)
{
    g_Kills[client] = 0;
    g_Deaths[client] = 0;
    g_Plants[client] = 0;
    g_Defuses[client] = 0;
    g_Clutches[client] = 0;
}

int CountAliveTeam(int team)
{
    int count;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsTrackedClient(client) && IsPlayerAlive(client) && GetClientTeam(client) == team)
        {
            count++;
        }
    }

    return count;
}

int GetOtherTeam(int team)
{
    return team == CS_TEAM_CT ? CS_TEAM_T : CS_TEAM_CT;
}

void GetPhaseName(BuyPhase phase, char[] buffer, int maxlen)
{
    switch (phase)
    {
        case BuyPhase_Pistol:
        {
            strcopy(buffer, maxlen, "Pistol");
            return;
        }
        case BuyPhase_Force:
        {
            strcopy(buffer, maxlen, "Force");
            return;
        }
    }

    strcopy(buffer, maxlen, "Full buy");
}

void DenyBuy(int client, const char[] message)
{
    float now = GetGameTime();
    if (now - g_LastDenyMessage[client] >= 1.0)
    {
        PrintToChat(client, "[Retakes] %s", message);
        PrintCenterText(client, "%s", message);
        g_LastDenyMessage[client] = now;
    }
}

int ClampInt(int value, int minValue, int maxValue)
{
    if (value < minValue)
    {
        return minValue;
    }

    if (value > maxValue)
    {
        return maxValue;
    }

    return value;
}

void SetCookieInt(int client, Handle cookie, int value)
{
    char buffer[12];
    IntToString(value, buffer, sizeof(buffer));
    SetClientCookie(client, cookie, buffer);
}

int GetCookieInt(int client, Handle cookie)
{
    char buffer[12];
    GetClientCookie(client, cookie, buffer, sizeof(buffer));
    return StringToInt(buffer);
}

bool CookieHasValue(int client, Handle cookie)
{
    char buffer[12];
    GetClientCookie(client, cookie, buffer, sizeof(buffer));
    return buffer[0] != '\0';
}
