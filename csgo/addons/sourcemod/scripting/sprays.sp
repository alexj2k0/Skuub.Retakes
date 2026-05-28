#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>
#include <sprays>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name = "Sprays",
    author = "CS:GO Legacy",
    description = "Custom player sprays with decal placement and menu selection",
    version = "1.0.0",
    url = "https://github.com/kgns"
};

#include "sprays/globals.sp"
#include "sprays/hooks.sp"
#include "sprays/helpers.sp"
#include "sprays/database.sp"
#include "sprays/config.sp"
#include "sprays/menus.sp"
#include "sprays/natives.sp"

public void OnPluginStart()
{
    RegConsoleCmd("sm_spray", Command_Spray, "Place your spray on the wall");
    RegConsoleCmd("sm_sprays", Command_Sprays, "Open the spray selection menu");
    RegConsoleCmd("sm_spraymenu", Command_Sprays, "Open the spray selection menu");
    RegConsoleCmd("sm_spraytest", Command_SprayTest, "Place a test glow sprite");
    RegAdminCmd("sm_sprays_reload", Command_SpraysReload, ADMFLAG_ROOT, "Reload the sprays configuration");

    LoadTranslations("common.phrases");
    LoadTranslations("sprays.phrases");

    g_Cvar_ChatPrefix             = CreateConVar("sm_sprays_chat_prefix", "[Retakes]");
    g_Cvar_MaxSprayDistance       = CreateConVar("sm_sprays_max_distance", "128.0");
    g_Cvar_SprayScale             = CreateConVar("sm_sprays_scale", "0.04");
    g_Cvar_MaxSpraysPerRound      = CreateConVar("sm_sprays_max_per_round", "5");
    g_Cvar_RemoveSpraysOnRoundEnd = CreateConVar("sm_sprays_remove_on_round_end", "1");
    g_Cvar_EnableAdminOnly        = CreateConVar("sm_sprays_admin_only", "0");
    g_Cvar_DBConnection           = CreateConVar("sm_sprays_db_connection", "storage-local");
    g_Cvar_TablePrefix            = CreateConVar("sm_sprays_table_prefix", "");

    AutoExecConfig(true, "sprays");

    g_hCookie = RegClientCookie("sprays_selection", "Selected spray index", CookieAccess_Private);

    g_hActiveDecals = new ArrayList(1);

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
    if (g_hDatabase != null)
    {
        ReloadSprayConfig();
        PrecacheAllSprays();
    }
}

public void OnMapEnd()
{
    g_iSprayCategoryCount = 0;
    g_iTotalSprayCount = 0;

    delete g_hCategoryMenu;
    for (int i = 0; i < 32; i++)
    {
        delete g_hSprayMenus[i];
    }
}

public void OnConfigsExecuted()
{
    g_Cvar_ChatPrefix.GetString(g_ChatPrefix, sizeof(g_ChatPrefix));
    g_fMaxSprayDistance = g_Cvar_MaxSprayDistance.FloatValue;
    g_fSprayScale = g_Cvar_SprayScale.FloatValue;
    g_iMaxSpraysPerRound = g_Cvar_MaxSpraysPerRound.IntValue;
    g_bRemoveSpraysOnRoundEnd = g_Cvar_RemoveSpraysOnRoundEnd.BoolValue;
    g_bAdminOnly = g_Cvar_EnableAdminOnly.BoolValue;

    g_Cvar_DBConnection.GetString(g_DBConnection, sizeof(g_DBConnection));
    g_Cvar_TablePrefix.GetString(g_TablePrefix, sizeof(g_TablePrefix));

    if (g_hDatabase == null)
    {
        Database.Connect(SQLConnectCallback, g_DBConnection);
    }
}

public Action Command_SpraysReload(int client, int args)
{
    ReloadSprayConfig();
    PrecacheAllSprays();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            g_iPlayerSpraySelection[i] = -1;
            if (g_hDatabase != null)
                GetPlayerData(i);
        }
    }

    ReplyToCommand(client, " %s \x04Sprays configuration reloaded. (%d sprays in %d categories)", g_ChatPrefix, g_iTotalSprayCount, g_iSprayCategoryCount);
    return Plugin_Handled;
}

public void OnClientPostAdminCheck(int client)
{
    if (!IsFakeClient(client))
    {
        OnClientPutInServer(client);
    }
}
