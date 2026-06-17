#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define MAX_CHECKPOINTS 32
#define SOLO_MAPS_BUFFER 512
#define ONEVONE_MAPS_BUFFER 512
#define RETAKES_PLUGIN_COUNT 5
#define MULTI1V1_PLUGIN "multi1v1"

char g_RetakesPlugins[RETAKES_PLUGIN_COUNT][] =
{
    "retakes",
    "retakes_autoplant",
    "retakes_buyphases",
    "retakes_instadefuse",
    "retakes_sitepicker"
};

public Plugin myinfo =
{
    name = "Retakes Solo Warmup",
    author = "OpenAI",
    description = "Uses movement mode by default with a player-selected retakes mode.",
    version = "1.5.0",
    url = ""
};

bool g_SoloWarmup;
bool g_ChangingMap;
bool g_MovementMode = true;
bool g_OneVOneMode;
bool g_RetakeCountdownActive;
int g_RetakeCountdownRemaining;
char g_LastRetakeMap[PLATFORM_MAX_PATH] = "de_mirage";
float g_StartOrigin[MAXPLAYERS + 1][3];
float g_StartAngles[MAXPLAYERS + 1][3];
bool g_HasStartPosition[MAXPLAYERS + 1];
float g_UndoOrigin[MAXPLAYERS + 1][3];
float g_UndoAngles[MAXPLAYERS + 1][3];
bool g_HasUndoPosition[MAXPLAYERS + 1];
float g_PauseOrigin[MAXPLAYERS + 1][3];
float g_PauseAngles[MAXPLAYERS + 1][3];
bool g_Paused[MAXPLAYERS + 1];
float g_CheckpointOrigin[MAXPLAYERS + 1][MAX_CHECKPOINTS][3];
float g_CheckpointAngles[MAXPLAYERS + 1][MAX_CHECKPOINTS][3];
int g_CheckpointCount[MAXPLAYERS + 1];
int g_CurrentCheckpoint[MAXPLAYERS + 1];

ConVar g_SoloMapCvar;
ConVar g_SoloMapsCvar;
ConVar g_OneVOneMapCvar;
ConVar g_OneVOneMapsCvar;
ConVar g_ReturnMapCvar;
ConVar g_ReturnCountdownCvar;

public void OnPluginStart()
{
    g_SoloMapCvar = CreateConVar("sm_solo_warmup_map", "kz_phamous", "Default map used for movement mode.");
    g_SoloMapsCvar = CreateConVar("sm_solo_warmup_maps", "surf_utopia_v3,surf_summit_csgo,kz_beginnerblock_go", "Additional comma-separated movement maps available in solo mode.");
    g_OneVOneMapCvar = CreateConVar("sm_1v1_map", "am_ramps", "Default map used for 1v1 mode.");
    g_OneVOneMapsCvar = CreateConVar("sm_1v1_maps", "am_courtyard,am_grass2,am_water", "Additional comma-separated maps available in 1v1 mode.");
    g_ReturnMapCvar = CreateConVar("sm_solo_warmup_return_map", "", "Retakes map to load when retakes mode is selected. Empty returns to the previous retakes map.");
    g_ReturnCountdownCvar = CreateConVar("sm_solo_warmup_return_countdown", "10", "Deprecated; retakes mode now starts from !mode.", _, true, 0.0);
    AutoExecConfig(true, "retakes_solo_warmup");

    HookEvent("player_connect_full", Event_CheckPlayers);
    HookEvent("player_team", Event_CheckPlayers);
    HookEvent("player_spawn", Event_PlayerSpawn);

    RegConsoleCmd("sm_tpmenu", Command_CheckpointMenu);
    RegConsoleCmd("sm_menu", Command_CheckpointMenu);
    RegConsoleCmd("sm_mode", Command_ModeMenu);
    RegConsoleCmd("sm_solo", Command_MovementMapMenu);
    RegConsoleCmd("sm_movement", Command_MovementMapMenu);
    RegConsoleCmd("sm_1v1", Command_OneVOneMapMenu);
    RegConsoleCmd("sm_onevone", Command_OneVOneMapMenu);

    CreateTimer(2.0, Timer_CheckPlayers, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(0.2, Timer_UpdateHud, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    ApplyRetakesPluginStateForCurrentMap();
    QueuePlayerCheck();
}

public void OnMapStart()
{
    g_SoloWarmup = false;
    g_ChangingMap = false;
    g_RetakeCountdownActive = false;
    g_RetakeCountdownRemaining = 0;
    ResetAllCheckpoints();

    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    if (IsSoloMap(currentMap))
    {
        g_MovementMode = true;
        g_OneVOneMode = false;
        DisableOneVOnePlugin();
        DisableRetakesPluginsForSolo();
        ApplySoloWarmupSettings();
    }
    else if (IsOneVOneMap(currentMap))
    {
        g_MovementMode = false;
        g_OneVOneMode = true;
        ApplyOneVOneSettings();
    }
    else
    {
        g_MovementMode = false;
        g_OneVOneMode = false;
        DisableOneVOnePlugin();
        RestoreRetakesPlugins(true);
        SetRetakesEnabled(true);
        strcopy(g_LastRetakeMap, sizeof(g_LastRetakeMap), currentMap);
    }

    CreateTimer(2.0, Timer_CheckPlayers, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(0.2, Timer_UpdateHud, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    QueuePlayerCheck();
}

void ApplyRetakesPluginStateForCurrentMap()
{
    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));

    if (IsSoloMap(currentMap))
    {
        g_MovementMode = true;
        g_OneVOneMode = false;
        DisableOneVOnePlugin();
        DisableRetakesPluginsForSolo();
    }
    else if (IsOneVOneMap(currentMap))
    {
        g_MovementMode = false;
        g_OneVOneMode = true;
        ApplyOneVOneSettings();
    }
    else
    {
        g_MovementMode = false;
        g_OneVOneMode = false;
        DisableOneVOnePlugin();
        RestoreRetakesPlugins(true);
        SetRetakesEnabled(true);
    }
}

public void OnClientPutInServer(int client)
{
    if (!IsFakeClient(client))
    {
        SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
        if (g_MovementMode && IsCurrentSoloMap())
        {
            CreateTimer(0.5, Timer_PrepareSoloPlayers, _, TIMER_FLAG_NO_MAPCHANGE);
        }

        QueuePlayerCheck();
    }
}

public void OnClientDisconnect(int client)
{
    if (!IsFakeClient(client))
    {
        QueuePlayerCheck();
    }
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (IsCurrentSoloMap())
    {
        damage = 0.0;
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

public Action Event_CheckPlayers(Event event, const char[] name, bool dontBroadcast)
{
    QueuePlayerCheck();
    return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsHumanInGame(client))
    {
        return Plugin_Continue;
    }

    if (!IsCurrentSoloMap())
    {
        ApplyRetakesCollision(client);
        SetEntProp(client, Prop_Data, "m_takedamage", 2);
        return Plugin_Continue;
    }

    ApplyMovementCollision(client);
    SetEntProp(client, Prop_Data, "m_takedamage", 0);

    if (g_CheckpointCount[client] > 0)
    {
        CreateTimer(0.1, Timer_RestoreCheckpoint, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        CreateTimer(0.1, Timer_SaveStartPosition, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }

    return Plugin_Continue;
}

public Action Timer_CheckPlayers(Handle timer)
{
    UpdateWarmupState();
    return Plugin_Continue;
}

public Action Timer_CheckPlayersOnce(Handle timer)
{
    UpdateWarmupState();
    return Plugin_Stop;
}

public Action Timer_PrepareSoloPlayers(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsHumanInGame(client))
        {
            continue;
        }

        if (GetClientTeam(client) < CS_TEAM_T)
        {
            FakeClientCommand(client, "jointeam 2");
        }
        else if (!IsPlayerAlive(client))
        {
            CS_RespawnPlayer(client);
        }
        else if (g_Paused[client])
        {
            SetEntityMoveType(client, MOVETYPE_NONE);
        }

        ApplyMovementCollision(client);
    }

    return Plugin_Stop;
}

public Action Timer_SaveStartPosition(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsHumanInGame(client) || !IsPlayerAlive(client) || !IsCurrentSoloMap())
    {
        return Plugin_Stop;
    }

    GetClientAbsOrigin(client, g_StartOrigin[client]);
    GetClientEyeAngles(client, g_StartAngles[client]);
    g_HasStartPosition[client] = true;

    return Plugin_Stop;
}

public Action Timer_RestoreCheckpoint(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsHumanInGame(client) || !IsPlayerAlive(client) || !IsCurrentSoloMap())
    {
        return Plugin_Stop;
    }

    if (g_CheckpointCount[client] > 0)
    {
        TeleportToCheckpoint(client);
        PrintToChat(client, "[KZ] Returned to your last checkpoint (%d/%d).",
            GetDisplayCheckpoint(client), g_CheckpointCount[client]);
    }

    return Plugin_Stop;
}

public Action Timer_UpdateHud(Handle timer)
{
    if (!IsCurrentSoloMap())
    {
        return Plugin_Continue;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsHumanInGame(client))
        {
            continue;
        }

        ShowKzHud(client);
    }

    return Plugin_Continue;
}

public Action Timer_RetakeCountdown(Handle timer)
{
    if (!g_RetakeCountdownActive || !IsCurrentSoloMap() || CountHumansInGame() < 2)
    {
        g_RetakeCountdownActive = false;
        g_RetakeCountdownRemaining = 0;
        PrintToChatAll("[SM] Retakes return cancelled; waiting for another player.");
        return Plugin_Stop;
    }

    if (g_RetakeCountdownRemaining <= 0)
    {
        g_RetakeCountdownActive = false;
        ChangeToRetakeMap();
        return Plugin_Stop;
    }

    PrintCenterTextAll("Retakes starting in %d", g_RetakeCountdownRemaining);
    if (g_RetakeCountdownRemaining == g_ReturnCountdownCvar.IntValue || g_RetakeCountdownRemaining <= 5)
    {
        PrintToChatAll("[SM] Retakes starting in %d seconds.", g_RetakeCountdownRemaining);
    }

    g_RetakeCountdownRemaining--;
    return Plugin_Continue;
}

public Action Command_RestartRun(int client, int args)
{
    if (!IsHumanInGame(client) || !IsCurrentSoloMap())
    {
        return Plugin_Handled;
    }

    RestartRun(client);
    PrintToChat(client, "[Movement] Run restarted.");
    return Plugin_Handled;
}

public Action Command_CheckpointMenu(int client, int args)
{
    if (!CanUseKzCommand(client))
    {
        return Plugin_Handled;
    }

    OpenCheckpointMenu(client);
    return Plugin_Handled;
}

public int CheckpointMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (action != MenuAction_Select || !CanUseKzCommand(client))
    {
        return 0;
    }

    char info[32];
    menu.GetItem(item, info, sizeof(info));

    if (StrEqual(info, "tele"))
    {
        TeleportToCheckpoint(client);
    }
    else if (StrEqual(info, "save"))
    {
        SaveCheckpoint(client);
    }
    else if (StrEqual(info, "prev"))
    {
        SelectCheckpoint(client, -1);
    }
    else if (StrEqual(info, "next"))
    {
        SelectCheckpoint(client, 1);
    }
    else if (StrEqual(info, "restart"))
    {
        RestartRun(client);
        PrintToChat(client, "[Movement] Run restarted.");
    }
    else if (StrEqual(info, "clear"))
    {
        ResetCheckpoints(client);
        PrintToChat(client, "[KZ] Checkpoints cleared.");
    }
    else if (StrEqual(info, "pause"))
    {
        PauseRun(client);
    }
    else if (StrEqual(info, "resume"))
    {
        ResumeRun(client);
    }
    else if (StrEqual(info, "undo"))
    {
        UndoTeleport(client);
    }
    else if (StrEqual(info, "stuck"))
    {
        StuckRecovery(client);
    }

    if (CanUseKzCommand(client))
    {
        OpenCheckpointMenu(client);
    }

    return 0;
}

public Action Command_MovementMapMenu(int client, int args)
{
    if (!IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    OpenMovementMapMenu(client);
    return Plugin_Handled;
}

public Action Command_OneVOneMapMenu(int client, int args)
{
    if (!IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    OpenOneVOneMapMenu(client);
    return Plugin_Handled;
}

public Action Command_ModeMenu(int client, int args)
{
    if (!IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    OpenModeMenu(client);
    return Plugin_Handled;
}

public int ModeMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (action != MenuAction_Select || !IsHumanInGame(client))
    {
        return 0;
    }

    char mode[16];
    menu.GetItem(item, mode, sizeof(mode));

    if (StrEqual(mode, "movement"))
    {
        SelectMovementMode(client);
    }
    else if (StrEqual(mode, "retakes"))
    {
        SelectRetakesMode(client);
    }
    else if (StrEqual(mode, "1v1"))
    {
        SelectOneVOneMode(client);
    }

    return 0;
}

public int MovementMapMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (action != MenuAction_Select || !IsHumanInGame(client))
    {
        return 0;
    }

    char soloMap[PLATFORM_MAX_PATH];
    menu.GetItem(item, soloMap, sizeof(soloMap));

    if (!IsMapValid(soloMap))
    {
        PrintToChat(client, "[SM] Movement map is not installed: %s", soloMap);
        return 0;
    }

    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    if (StrEqual(currentMap, soloMap, false))
    {
        PrintToChat(client, "[SM] You are already on %s.", soloMap);
        return 0;
    }

    ChangeToMovementMap(soloMap);
    return 0;
}

public int OneVOneMapMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (action != MenuAction_Select || !IsHumanInGame(client))
    {
        return 0;
    }

    char oneVOneMap[PLATFORM_MAX_PATH];
    menu.GetItem(item, oneVOneMap, sizeof(oneVOneMap));

    if (!IsMapValid(oneVOneMap))
    {
        PrintToChat(client, "[SM] 1v1 map is not installed: %s", oneVOneMap);
        return 0;
    }

    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    if (StrEqual(currentMap, oneVOneMap, false))
    {
        PrintToChat(client, "[SM] You are already on %s.", oneVOneMap);
        return 0;
    }

    ChangeToOneVOneMap(oneVOneMap);
    return 0;
}

void OpenModeMenu(int client)
{
    Menu menu = new Menu(ModeMenuHandler);
    menu.SetTitle("Server Mode");
    menu.AddItem("movement", g_MovementMode ? "Movement (current)" : "Movement");
    menu.AddItem("1v1", g_OneVOneMode ? "1v1 (current)" : "1v1");
    menu.AddItem("retakes", (!g_MovementMode && !g_OneVOneMode) ? "Retakes (current)" : "Retakes");
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void SelectMovementMode(int client)
{
    g_MovementMode = true;
    g_OneVOneMode = false;
    g_RetakeCountdownActive = false;
    g_RetakeCountdownRemaining = 0;

    if (IsCurrentSoloMap())
    {
        StartSoloWarmup();
        ApplySoloWarmupSettings();
        PrintToChat(client, "[SM] Movement mode is already active.");
        return;
    }

    ChangeToSoloMap();
}

void SelectRetakesMode(int client)
{
    g_MovementMode = false;
    g_OneVOneMode = false;
    g_RetakeCountdownActive = false;
    g_RetakeCountdownRemaining = 0;

    if (IsCurrentSoloMap() || IsCurrentOneVOneMap())
    {
        ChangeToRetakeMap();
        return;
    }

    EndSoloWarmup();
    RestoreRetakesPlugins(true);
    SetRetakesEnabled(true);
    PrintToChat(client, "[SM] Retakes mode is already active.");
}

void SelectOneVOneMode(int client)
{
    g_MovementMode = false;
    g_OneVOneMode = true;
    g_RetakeCountdownActive = false;
    g_RetakeCountdownRemaining = 0;

    if (IsCurrentOneVOneMap())
    {
        ApplyOneVOneSettings();
        PrintToChat(client, "[SM] 1v1 mode is already active.");
        return;
    }

    ChangeToOneVOneMap();
}

void QueuePlayerCheck()
{
    CreateTimer(0.2, Timer_CheckPlayersOnce, _, TIMER_FLAG_NO_MAPCHANGE);
}

void RestartRun(int client)
{
    if (g_HasStartPosition[client] && IsPlayerAlive(client))
    {
        SaveUndoPosition(client);
        float velocity[3] = {0.0, 0.0, 0.0};
        TeleportEntity(client, g_StartOrigin[client], g_StartAngles[client], velocity);
        SetEntityHealth(client, 100);
    }
    else
    {
        CS_RespawnPlayer(client);
        CreateTimer(0.1, Timer_SaveStartPosition, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }

}

void PauseRun(int client)
{
    if (!IsPlayerAlive(client))
    {
        PrintToChat(client, "[Movement] You must be alive to pause.");
        return;
    }

    GetClientAbsOrigin(client, g_PauseOrigin[client]);
    GetClientEyeAngles(client, g_PauseAngles[client]);
    SetEntityMoveType(client, MOVETYPE_NONE);
    g_Paused[client] = true;
    PrintToChat(client, "[Movement] Paused. Use !tpmenu to resume.");
}

void ResumeRun(int client)
{
    if (!g_Paused[client])
    {
        PrintToChat(client, "[Movement] You are not paused.");
        return;
    }

    SetEntityMoveType(client, MOVETYPE_WALK);
    if (IsPlayerAlive(client))
    {
        TeleportEntity(client, g_PauseOrigin[client], g_PauseAngles[client], NULL_VECTOR);
    }

    g_Paused[client] = false;
    PrintToChat(client, "[Movement] Resumed.");
}

void UndoTeleport(int client)
{
    if (!IsPlayerAlive(client))
    {
        PrintToChat(client, "[Movement] You must be alive to undo.");
        return;
    }

    if (!g_HasUndoPosition[client])
    {
        PrintToChat(client, "[Movement] No previous teleport position saved.");
        return;
    }

    float targetOrigin[3];
    float targetAngles[3];
    CopyVector(g_UndoOrigin[client], targetOrigin);
    CopyVector(g_UndoAngles[client], targetAngles);
    SaveUndoPosition(client);

    float velocity[3] = {0.0, 0.0, 0.0};
    TeleportEntity(client, targetOrigin, targetAngles, velocity);
    PrintToChat(client, "[Movement] Returned to your previous teleport position.");
}

void StuckRecovery(int client)
{
    if (g_CheckpointCount[client] > 0)
    {
        TeleportToCheckpoint(client);
    }
    else
    {
        RestartRun(client);
    }

    PrintToChat(client, "[Movement] Stuck recovery used.");
}

void OpenCheckpointMenu(int client)
{
    Menu menu = new Menu(CheckpointMenuHandler);
    menu.SetTitle("Movement Teleport Menu");

    char label[64];
    Format(label, sizeof(label), "Teleport to CP (%d/%d)", GetDisplayCheckpoint(client), g_CheckpointCount[client]);
    menu.AddItem("tele", label, g_CheckpointCount[client] > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("save", "Save checkpoint", IsPlayerAlive(client) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("prev", "Previous checkpoint", g_CheckpointCount[client] > 1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("next", "Next checkpoint", g_CheckpointCount[client] > 1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("restart", "Restart run");
    menu.AddItem(g_Paused[client] ? "resume" : "pause", g_Paused[client] ? "Resume" : "Pause", IsPlayerAlive(client) || g_Paused[client] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("undo", "Undo teleport", g_HasUndoPosition[client] && IsPlayerAlive(client) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("stuck", "Stuck recovery");
    menu.AddItem("clear", "Clear checkpoints", g_CheckpointCount[client] > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void OpenMovementMapMenu(int client)
{
    ArrayList maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    BuildSoloMapList(maps);

    if (maps.Length <= 0)
    {
        delete maps;
        PrintToChat(client, "[SM] No movement maps are configured.");
        return;
    }

    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));

    Menu menu = new Menu(MovementMapMenuHandler);
    menu.SetTitle("Movement Maps");

    char soloMap[PLATFORM_MAX_PATH];
    char baseLabel[96];
    char label[96];
    for (int i = 0; i < maps.Length; i++)
    {
        maps.GetString(i, soloMap, sizeof(soloMap));
        GetMovementMapLabel(soloMap, baseLabel, sizeof(baseLabel));

        if (StrEqual(currentMap, soloMap, false))
        {
            Format(label, sizeof(label), "%s (current)", baseLabel);
        }
        else if (!IsMapValid(soloMap))
        {
            Format(label, sizeof(label), "%s (missing)", baseLabel);
        }
        else
        {
            strcopy(label, sizeof(label), baseLabel);
        }

        menu.AddItem(soloMap, label, IsMapValid(soloMap) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    }

    delete maps;

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void OpenOneVOneMapMenu(int client)
{
    ArrayList maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    BuildOneVOneMapList(maps);

    if (maps.Length <= 0)
    {
        delete maps;
        PrintToChat(client, "[SM] No 1v1 maps are configured.");
        return;
    }

    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));

    Menu menu = new Menu(OneVOneMapMenuHandler);
    menu.SetTitle("1v1 Maps");

    char oneVOneMap[PLATFORM_MAX_PATH];
    char baseLabel[96];
    char label[96];
    for (int i = 0; i < maps.Length; i++)
    {
        maps.GetString(i, oneVOneMap, sizeof(oneVOneMap));
        GetOneVOneMapLabel(oneVOneMap, baseLabel, sizeof(baseLabel));

        if (StrEqual(currentMap, oneVOneMap, false))
        {
            Format(label, sizeof(label), "%s (current)", baseLabel);
        }
        else if (!IsMapValid(oneVOneMap))
        {
            Format(label, sizeof(label), "%s (missing)", baseLabel);
        }
        else
        {
            strcopy(label, sizeof(label), baseLabel);
        }

        menu.AddItem(oneVOneMap, label, IsMapValid(oneVOneMap) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    }

    delete maps;

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

int GetDisplayCheckpoint(int client)
{
    if (g_CheckpointCount[client] <= 0)
    {
        return 0;
    }

    int slot = g_CurrentCheckpoint[client];
    if (slot < 0 || slot >= g_CheckpointCount[client])
    {
        return g_CheckpointCount[client];
    }

    return slot + 1;
}

void SaveCheckpoint(int client)
{
    if (!IsPlayerAlive(client))
    {
        PrintToChat(client, "[KZ] You must be alive to save a checkpoint.");
        return;
    }

    int slot = g_CheckpointCount[client];
    if (slot >= MAX_CHECKPOINTS)
    {
        slot = MAX_CHECKPOINTS - 1;
        for (int i = 1; i < MAX_CHECKPOINTS; i++)
        {
            CopyVector(g_CheckpointOrigin[client][i], g_CheckpointOrigin[client][i - 1]);
            CopyVector(g_CheckpointAngles[client][i], g_CheckpointAngles[client][i - 1]);
        }
    }
    else
    {
        g_CheckpointCount[client]++;
    }

    GetClientAbsOrigin(client, g_CheckpointOrigin[client][slot]);
    GetClientEyeAngles(client, g_CheckpointAngles[client][slot]);
    g_CurrentCheckpoint[client] = slot;

    PrintToChat(client, "[KZ] Checkpoint %d/%d saved.", slot + 1, g_CheckpointCount[client]);
}

void TeleportToCheckpoint(int client)
{
    if (g_CheckpointCount[client] <= 0)
    {
        PrintToChat(client, "[KZ] No checkpoints saved. Use !menu first.");
        return;
    }

    if (!IsPlayerAlive(client))
    {
        CS_RespawnPlayer(client);
    }

    int slot = g_CurrentCheckpoint[client];
    if (slot < 0 || slot >= g_CheckpointCount[client])
    {
        slot = g_CheckpointCount[client] - 1;
        g_CurrentCheckpoint[client] = slot;
    }

    float velocity[3] = {0.0, 0.0, 0.0};
    SaveUndoPosition(client);
    TeleportEntity(client, g_CheckpointOrigin[client][slot], g_CheckpointAngles[client][slot], velocity);
    SetEntityHealth(client, 100);

    PrintToChat(client, "[KZ] Teleported to checkpoint %d/%d.", slot + 1, g_CheckpointCount[client]);
}

void SelectCheckpoint(int client, int direction)
{
    if (g_CheckpointCount[client] <= 0)
    {
        PrintToChat(client, "[KZ] No checkpoints saved. Use !menu first.");
        return;
    }

    g_CurrentCheckpoint[client] += direction;
    if (g_CurrentCheckpoint[client] < 0)
    {
        g_CurrentCheckpoint[client] = g_CheckpointCount[client] - 1;
    }
    else if (g_CurrentCheckpoint[client] >= g_CheckpointCount[client])
    {
        g_CurrentCheckpoint[client] = 0;
    }

    TeleportToCheckpoint(client);
}

bool CanUseKzCommand(int client)
{
    return IsHumanInGame(client) && IsCurrentSoloMap();
}

void ResetAllCheckpoints()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        ResetCheckpoints(client);
    }
}

void ResetCheckpoints(int client)
{
    g_CheckpointCount[client] = 0;
    g_CurrentCheckpoint[client] = -1;
    g_HasUndoPosition[client] = false;
    g_Paused[client] = false;
}

void CopyVector(float source[3], float dest[3])
{
    dest[0] = source[0];
    dest[1] = source[1];
    dest[2] = source[2];
}

void ShowKzHud(int client)
{
    float velocity[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);

    float speed = SquareRoot((velocity[0] * velocity[0]) + (velocity[1] * velocity[1]));

    char tier[32];
    GetVelocityTier(speed, tier, sizeof(tier));
    PrintHintText(client, "Velocity %.0f | %s", speed, tier);
}

void UpdateWarmupState()
{
    int humans = CountHumansInGame();

    if (humans <= 0)
    {
        if (IsCurrentOneVOneMap())
        {
            g_MovementMode = false;
            g_OneVOneMode = true;
        }
        else
        {
            g_MovementMode = true;
            g_OneVOneMode = false;
        }
        g_RetakeCountdownActive = false;
        g_RetakeCountdownRemaining = 0;
        return;
    }

    if (g_OneVOneMode)
    {
        g_RetakeCountdownActive = false;
        g_RetakeCountdownRemaining = 0;

        if (!IsCurrentOneVOneMap())
        {
            ChangeToOneVOneMap();
            return;
        }

        ApplyOneVOneSettings();
        return;
    }

    if (g_MovementMode)
    {
        g_RetakeCountdownActive = false;
        g_RetakeCountdownRemaining = 0;

        if (!IsCurrentSoloMap())
        {
            ChangeToSoloMap();
            return;
        }

        StartSoloWarmup();
        ApplySoloWarmupSettings();
    }
    else
    {
        if (IsCurrentSoloMap())
        {
            ChangeToRetakeMap();
            return;
        }

        EndSoloWarmup();
    }
}

void StartSoloWarmup()
{
    if (g_SoloWarmup)
    {
        return;
    }

    g_SoloWarmup = true;

    ApplySoloWarmupSettings();
    ServerCommand("mp_warmup_pausetimer 0");
    ServerCommand("mp_warmup_end");
    ServerCommand("mp_restartgame 1");

    CreateTimer(0.5, Timer_PrepareSoloPlayers, _, TIMER_FLAG_NO_MAPCHANGE);
    PrintToChatAll("[SM] Movement mode enabled. Use !mode to switch modes.");
}

void ApplySoloWarmupSettings()
{
    DisableOneVOnePlugin();
    DisableRetakesPluginsForSolo();
    ServerCommand("bot_kick");
    ServerCommand("bot_quota 0");
    ServerCommand("mp_do_warmup_period 0");
    ServerCommand("mp_freezetime 0");
    ServerCommand("mp_ignore_round_win_conditions 1");
    ServerCommand("mp_roundtime 60");
    ServerCommand("mp_roundtime_defuse 60");
    ServerCommand("mp_respawn_on_death_ct 1");
    ServerCommand("mp_respawn_on_death_t 1");
    ServerCommand("sv_airaccelerate 100");
    ServerCommand("sv_enablebunnyhopping 1");
    ServerCommand("sv_autobunnyhopping 1");
    ServerCommand("sv_staminajumpcost 0");
    ServerCommand("sv_staminalandcost 0");
    ServerCommand("sv_maxvelocity 3500");
    ServerCommand("mp_solid_teammates 0");

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsHumanInGame(client))
        {
            ApplyMovementCollision(client);
        }
    }
}

void EndSoloWarmup()
{
    if (!g_SoloWarmup)
    {
        return;
    }

    g_SoloWarmup = false;

    RestoreRetakesPlugins(false);
    SetRetakesEnabled(true);
    ServerCommand("mp_solid_teammates 1");
    ServerCommand("mp_ignore_round_win_conditions 0");
    ServerCommand("mp_warmup_pausetimer 0");
    ServerCommand("mp_warmup_end");

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsHumanInGame(client))
        {
            ApplyRetakesCollision(client);
        }
    }

    PrintToChatAll("[SM] Retakes mode enabled. Use !mode to switch modes.");
}

int CountHumansInGame()
{
    int humans;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsHumanConnected(client))
        {
            humans++;
        }
    }

    return humans;
}

bool IsHumanInGame(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

bool IsHumanConnected(int client)
{
    return client > 0 && client <= MaxClients && IsClientConnected(client) && !IsFakeClient(client);
}

void ApplyMovementCollision(int client)
{
    if (IsHumanInGame(client) && IsPlayerAlive(client))
    {
        SetEntProp(client, Prop_Send, "m_CollisionGroup", 2);
    }
}

void ApplyRetakesCollision(int client)
{
    if (IsHumanInGame(client) && IsPlayerAlive(client))
    {
        SetEntProp(client, Prop_Send, "m_CollisionGroup", 5);
    }
}

bool IsCurrentSoloMap()
{
    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    return IsSoloMap(currentMap);
}

bool IsCurrentOneVOneMap()
{
    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    return IsOneVOneMap(currentMap);
}

bool IsSoloMap(const char[] map)
{
    ArrayList maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    BuildSoloMapList(maps);

    char soloMap[PLATFORM_MAX_PATH];
    bool found;
    for (int i = 0; i < maps.Length; i++)
    {
        maps.GetString(i, soloMap, sizeof(soloMap));
        if (StrEqual(map, soloMap, false))
        {
            found = true;
            break;
        }
    }

    delete maps;
    return found;
}

bool IsOneVOneMap(const char[] map)
{
    ArrayList maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    BuildOneVOneMapList(maps);

    char oneVOneMap[PLATFORM_MAX_PATH];
    bool found;
    for (int i = 0; i < maps.Length; i++)
    {
        maps.GetString(i, oneVOneMap, sizeof(oneVOneMap));
        if (StrEqual(map, oneVOneMap, false))
        {
            found = true;
            break;
        }
    }

    delete maps;
    return found;
}

void ChangeToSoloMap()
{
    if (g_ChangingMap)
    {
        return;
    }

    char soloMap[PLATFORM_MAX_PATH];
    if (!GetDefaultSoloMap(soloMap, sizeof(soloMap)))
    {
        LogError("No configured solo movement maps are installed.");
        return;
    }

    ChangeToMovementMap(soloMap);
}

void ChangeToMovementMap(const char[] soloMap)
{
    if (g_ChangingMap)
    {
        return;
    }

    if (!IsMapValid(soloMap))
    {
        LogError("Solo movement map \"%s\" is not installed.", soloMap);
        return;
    }

    g_ChangingMap = true;
    g_MovementMode = true;
    g_OneVOneMode = false;
    g_RetakeCountdownActive = false;
    DisableOneVOnePlugin();
    DisableRetakesPluginsForSolo();
    PrintToChatAll("[SM] Loading movement map: %s", soloMap);
    ServerCommand("changelevel %s", soloMap);
}

void ChangeToOneVOneMap(const char[] selectedMap = "")
{
    if (g_ChangingMap)
    {
        return;
    }

    char oneVOneMap[PLATFORM_MAX_PATH];
    if (selectedMap[0] == '\0')
    {
        if (!GetDefaultOneVOneMap(oneVOneMap, sizeof(oneVOneMap)))
        {
            LogError("No configured 1v1 maps are installed.");
            return;
        }
    }
    else
    {
        strcopy(oneVOneMap, sizeof(oneVOneMap), selectedMap);
    }

    if (!IsMapValid(oneVOneMap))
    {
        LogError("1v1 map \"%s\" is not installed.", oneVOneMap);
        return;
    }

    g_ChangingMap = true;
    g_MovementMode = false;
    g_OneVOneMode = true;
    g_RetakeCountdownActive = false;
    ApplyOneVOneTransitionSettings();
    PrintToChatAll("[SM] Loading 1v1 map: %s", oneVOneMap);
    ServerCommand("changelevel %s", oneVOneMap);
}

void ChangeToRetakeMap()
{
    if (g_ChangingMap)
    {
        return;
    }

    char retakeMap[PLATFORM_MAX_PATH];
    g_ReturnMapCvar.GetString(retakeMap, sizeof(retakeMap));

    if (retakeMap[0] == '\0')
    {
        strcopy(retakeMap, sizeof(retakeMap), g_LastRetakeMap);
    }

    if (retakeMap[0] == '\0' || IsSoloMap(retakeMap) || IsOneVOneMap(retakeMap) || !IsMapValid(retakeMap))
    {
        GetFallbackRetakeMap(retakeMap, sizeof(retakeMap));
    }

    if (!IsMapValid(retakeMap))
    {
        LogError("Could not find a valid retakes map to return to.");
        return;
    }

    g_ChangingMap = true;
    g_MovementMode = false;
    g_OneVOneMode = false;
    g_RetakeCountdownActive = false;
    ApplyRetakesTransitionSettings();
    SetRetakesEnabled(true);
    PrintToChatAll("[SM] Loading retakes map: %s", retakeMap);
    ServerCommand("changelevel %s", retakeMap);
}

void ApplyRetakesTransitionSettings()
{
    g_SoloWarmup = false;
    DisableOneVOnePlugin();
    RestoreRetakesPlugins(false);
    ServerCommand("bot_kick");
    ServerCommand("bot_quota 0");
    ServerCommand("mp_do_warmup_period 1");
    ServerCommand("mp_ignore_round_win_conditions 0");
    ServerCommand("mp_respawn_on_death_ct 0");
    ServerCommand("mp_respawn_on_death_t 0");
    ServerCommand("mp_roundtime 1.92");
    ServerCommand("mp_roundtime_defuse 1.92");
    ServerCommand("mp_freezetime 10");
    ServerCommand("mp_solid_teammates 1");
    ServerCommand("sv_airaccelerate 12");
    ServerCommand("sv_enablebunnyhopping 0");
    ServerCommand("sv_autobunnyhopping 0");
    ServerExecute();
}

void ApplyOneVOneTransitionSettings()
{
    g_SoloWarmup = false;
    DisableRetakesPluginsForSolo();
    RestoreOneVOnePlugin(false);
    SetMulti1v1Enabled(true);
    ServerCommand("bot_kick");
    ServerCommand("bot_quota 0");
    ServerCommand("mp_do_warmup_period 0");
    ServerCommand("mp_ignore_round_win_conditions 0");
    ServerCommand("mp_respawn_on_death_ct 0");
    ServerCommand("mp_respawn_on_death_t 0");
    ServerCommand("mp_solid_teammates 0");
    ServerCommand("sv_airaccelerate 12");
    ServerCommand("sv_enablebunnyhopping 0");
    ServerCommand("sv_autobunnyhopping 0");
    ServerExecute();
}

void ApplyOneVOneSettings()
{
    g_SoloWarmup = false;
    DisableRetakesPluginsForSolo();
    RestoreOneVOnePlugin(true);
    SetMulti1v1Enabled(true);
    ServerCommand("bot_kick");
    ServerCommand("bot_quota 0");
    ServerCommand("mp_solid_teammates 0");
    ServerCommand("sv_airaccelerate 12");
    ServerCommand("sv_enablebunnyhopping 0");
    ServerCommand("sv_autobunnyhopping 0");
    ServerExecute();
}

void GetFallbackRetakeMap(char[] map, int maxlen)
{
    File file = OpenFile("mapcycle.txt", "r");
    if (file == null)
    {
        strcopy(map, maxlen, "de_mirage");
        return;
    }

    char line[PLATFORM_MAX_PATH];
    while (!file.EndOfFile() && file.ReadLine(line, sizeof(line)))
    {
        TrimString(line);
        if (line[0] == '\0' || line[0] == '/' || IsSoloMap(line) || IsOneVOneMap(line) || !IsMapValid(line))
        {
            continue;
        }

        strcopy(map, maxlen, line);
        delete file;
        return;
    }

    delete file;
    strcopy(map, maxlen, "de_mirage");
}

void SetRetakesEnabled(bool enabled)
{
    ConVar retakesEnabled = FindConVar("sm_retakes_enabled");
    if (retakesEnabled != null)
    {
        retakesEnabled.SetInt(enabled ? 1 : 0);
    }
}

void SetMulti1v1Enabled(bool enabled)
{
    ConVar multi1v1Enabled = FindConVar("sm_multi1v1_enabled");
    if (multi1v1Enabled != null)
    {
        multi1v1Enabled.SetInt(enabled ? 1 : 0);
    }
}

void DisableOneVOnePlugin()
{
    SetMulti1v1Enabled(false);
    EnsureDisabledPluginsDir();

    char activePath[PLATFORM_MAX_PATH];
    char disabledPath[PLATFORM_MAX_PATH];
    BuildOneVOnePluginPath(false, activePath, sizeof(activePath));
    BuildOneVOnePluginPath(true, disabledPath, sizeof(disabledPath));

    if (FileExists(activePath))
    {
        ServerCommand("sm plugins unload %s", MULTI1V1_PLUGIN);
        ServerExecute();

        if (FileExists(disabledPath))
        {
            if (!DeleteFile(activePath))
            {
                LogError("Could not remove active 1v1 plugin copy: %s", activePath);
            }
        }
        else if (!RenameFile(disabledPath, activePath))
        {
            LogError("Could not park 1v1 plugin %s at %s", activePath, disabledPath);
        }
    }
}

void RestoreOneVOnePlugin(bool loadNow)
{
    EnsureDisabledPluginsDir();

    char activePath[PLATFORM_MAX_PATH];
    char disabledPath[PLATFORM_MAX_PATH];
    BuildOneVOnePluginPath(false, activePath, sizeof(activePath));
    BuildOneVOnePluginPath(true, disabledPath, sizeof(disabledPath));

    if (!FileExists(activePath) && FileExists(disabledPath))
    {
        if (!RenameFile(activePath, disabledPath))
        {
            LogError("Could not restore 1v1 plugin %s from %s", activePath, disabledPath);
            return;
        }
    }

    if (loadNow && FileExists(activePath) && FindConVar("sm_multi1v1_enabled") == null)
    {
        ServerCommand("sm plugins load %s", MULTI1V1_PLUGIN);
        ServerExecute();
    }

    SetMulti1v1Enabled(true);
}

void DisableRetakesPluginsForSolo()
{
    SetRetakesEnabled(false);
    SetRetakesAddonConVars(false);
    EnsureDisabledPluginsDir();

    char activePath[PLATFORM_MAX_PATH];
    char disabledPath[PLATFORM_MAX_PATH];
    bool queuedUnload;
    for (int i = 0; i < RETAKES_PLUGIN_COUNT; i++)
    {
        BuildRetakesPluginPath(g_RetakesPlugins[i], false, activePath, sizeof(activePath));

        if (FileExists(activePath))
        {
            queuedUnload = true;
            ServerCommand("sm plugins unload %s", g_RetakesPlugins[i]);
        }
    }

    if (queuedUnload)
    {
        ServerExecute();
    }

    for (int i = 0; i < RETAKES_PLUGIN_COUNT; i++)
    {
        BuildRetakesPluginPath(g_RetakesPlugins[i], false, activePath, sizeof(activePath));
        BuildRetakesPluginPath(g_RetakesPlugins[i], true, disabledPath, sizeof(disabledPath));

        if (!FileExists(activePath))
        {
            continue;
        }

        if (FileExists(disabledPath))
        {
            if (!DeleteFile(activePath))
            {
                LogError("Could not remove active retakes plugin copy: %s", activePath);
            }
        }
        else if (!RenameFile(disabledPath, activePath))
        {
            LogError("Could not park retakes plugin %s at %s", activePath, disabledPath);
        }
    }
}

void RestoreRetakesPlugins(bool loadNow)
{
    EnsureDisabledPluginsDir();

    char activePath[PLATFORM_MAX_PATH];
    char disabledPath[PLATFORM_MAX_PATH];
    bool restoredAny;
    for (int i = 0; i < RETAKES_PLUGIN_COUNT; i++)
    {
        BuildRetakesPluginPath(g_RetakesPlugins[i], false, activePath, sizeof(activePath));
        BuildRetakesPluginPath(g_RetakesPlugins[i], true, disabledPath, sizeof(disabledPath));

        if (!FileExists(activePath) && FileExists(disabledPath))
        {
            if (!RenameFile(activePath, disabledPath))
            {
                LogError("Could not restore retakes plugin %s from %s", activePath, disabledPath);
                continue;
            }

            restoredAny = true;
        }

    }

    if (loadNow && restoredAny)
    {
        for (int i = 0; i < RETAKES_PLUGIN_COUNT; i++)
        {
            BuildRetakesPluginPath(g_RetakesPlugins[i], false, activePath, sizeof(activePath));
            if (FileExists(activePath))
            {
                ServerCommand("sm plugins load %s", g_RetakesPlugins[i]);
            }
        }

        ServerExecute();
    }

    SetRetakesAddonConVars(true);
}

void SetRetakesAddonConVars(bool enabled)
{
    SetOptionalConVarBool("sm_autoplant_enabled", enabled);
    SetOptionalConVarBool("instant_defuse_if_time", enabled);
    SetOptionalConVarBool("instant_defuse_end_if_too_late", enabled);
}

void SetOptionalConVarBool(const char[] name, bool enabled)
{
    ConVar cvar = FindConVar(name);
    if (cvar != null)
    {
        cvar.SetInt(enabled ? 1 : 0);
    }
}

void EnsureDisabledPluginsDir()
{
    char disabledDir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, disabledDir, sizeof(disabledDir), "plugins/disabled");

    if (!DirExists(disabledDir))
    {
        CreateDirectory(disabledDir);
    }
}

void BuildRetakesPluginPath(const char[] plugin, bool disabled, char[] path, int maxlen)
{
    if (disabled)
    {
        BuildPath(Path_SM, path, maxlen, "plugins/disabled/%s.smx", plugin);
    }
    else
    {
        BuildPath(Path_SM, path, maxlen, "plugins/%s.smx", plugin);
    }
}

void BuildOneVOnePluginPath(bool disabled, char[] path, int maxlen)
{
    if (disabled)
    {
        BuildPath(Path_SM, path, maxlen, "plugins/disabled/%s.smx", MULTI1V1_PLUGIN);
    }
    else
    {
        BuildPath(Path_SM, path, maxlen, "plugins/%s.smx", MULTI1V1_PLUGIN);
    }
}

bool GetDefaultSoloMap(char[] soloMap, int maxlen)
{
    ArrayList maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    BuildSoloMapList(maps);

    char configuredMap[PLATFORM_MAX_PATH];
    for (int i = 0; i < maps.Length; i++)
    {
        maps.GetString(i, configuredMap, sizeof(configuredMap));
        if (IsMapValid(configuredMap))
        {
            strcopy(soloMap, maxlen, configuredMap);
            delete maps;
            return true;
        }
    }

    delete maps;
    soloMap[0] = '\0';
    return false;
}

bool GetDefaultOneVOneMap(char[] oneVOneMap, int maxlen)
{
    ArrayList maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    BuildOneVOneMapList(maps);

    char configuredMap[PLATFORM_MAX_PATH];
    for (int i = 0; i < maps.Length; i++)
    {
        maps.GetString(i, configuredMap, sizeof(configuredMap));
        if (IsMapValid(configuredMap))
        {
            strcopy(oneVOneMap, maxlen, configuredMap);
            delete maps;
            return true;
        }
    }

    delete maps;
    oneVOneMap[0] = '\0';
    return false;
}

void BuildSoloMapList(ArrayList maps)
{
    char soloMap[PLATFORM_MAX_PATH];
    g_SoloMapCvar.GetString(soloMap, sizeof(soloMap));
    AddSoloMap(maps, soloMap);

    char pool[SOLO_MAPS_BUFFER];
    g_SoloMapsCvar.GetString(pool, sizeof(pool));

    char token[PLATFORM_MAX_PATH];
    int tokenLength;
    int poolLength = strlen(pool);

    for (int i = 0; i <= poolLength; i++)
    {
        if (pool[i] == '\0' || pool[i] == ',' || pool[i] == ';')
        {
            if (tokenLength > 0)
            {
                token[tokenLength] = '\0';
                AddSoloMap(maps, token);
                tokenLength = 0;
            }
            continue;
        }

        if (tokenLength < sizeof(token) - 1)
        {
            token[tokenLength] = pool[i];
            tokenLength++;
        }
    }
}

void BuildOneVOneMapList(ArrayList maps)
{
    char oneVOneMap[PLATFORM_MAX_PATH];
    g_OneVOneMapCvar.GetString(oneVOneMap, sizeof(oneVOneMap));
    AddOneVOneMap(maps, oneVOneMap);

    char pool[ONEVONE_MAPS_BUFFER];
    g_OneVOneMapsCvar.GetString(pool, sizeof(pool));

    char token[PLATFORM_MAX_PATH];
    int tokenLength;
    int poolLength = strlen(pool);

    for (int i = 0; i <= poolLength; i++)
    {
        if (pool[i] == '\0' || pool[i] == ',' || pool[i] == ';')
        {
            if (tokenLength > 0)
            {
                token[tokenLength] = '\0';
                AddOneVOneMap(maps, token);
                tokenLength = 0;
            }
            continue;
        }

        if (tokenLength < sizeof(token) - 1)
        {
            token[tokenLength] = pool[i];
            tokenLength++;
        }
    }
}

void AddSoloMap(ArrayList maps, const char[] rawMap)
{
    char soloMap[PLATFORM_MAX_PATH];
    strcopy(soloMap, sizeof(soloMap), rawMap);
    TrimString(soloMap);

    if (soloMap[0] == '\0')
    {
        return;
    }

    char existingMap[PLATFORM_MAX_PATH];
    for (int i = 0; i < maps.Length; i++)
    {
        maps.GetString(i, existingMap, sizeof(existingMap));
        if (StrEqual(existingMap, soloMap, false))
        {
            return;
        }
    }

    maps.PushString(soloMap);
}

void AddOneVOneMap(ArrayList maps, const char[] rawMap)
{
    char oneVOneMap[PLATFORM_MAX_PATH];
    strcopy(oneVOneMap, sizeof(oneVOneMap), rawMap);
    TrimString(oneVOneMap);

    if (oneVOneMap[0] == '\0')
    {
        return;
    }

    char existingMap[PLATFORM_MAX_PATH];
    for (int i = 0; i < maps.Length; i++)
    {
        maps.GetString(i, existingMap, sizeof(existingMap));
        if (StrEqual(existingMap, oneVOneMap, false))
        {
            return;
        }
    }

    maps.PushString(oneVOneMap);
}

void SaveUndoPosition(int client)
{
    if (!IsHumanInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    GetClientAbsOrigin(client, g_UndoOrigin[client]);
    GetClientEyeAngles(client, g_UndoAngles[client]);
    g_HasUndoPosition[client] = true;
}

void GetVelocityTier(float speed, char[] tier, int maxlen)
{
    if (speed >= 1000.0)
    {
        strcopy(tier, maxlen, "very fast");
    }
    else if (speed >= 600.0)
    {
        strcopy(tier, maxlen, "fast");
    }
    else if (speed >= 300.0)
    {
        strcopy(tier, maxlen, "building");
    }
    else
    {
        strcopy(tier, maxlen, "slow");
    }
}

void GetMovementMapLabel(const char[] map, char[] label, int maxlen)
{
    if (StrEqual(map, "kz_phamous", false))
    {
        strcopy(label, maxlen, "KZ: Phamous");
    }
    else if (StrEqual(map, "surf_utopia_v3", false))
    {
        strcopy(label, maxlen, "Surf: Utopia");
    }
    else if (StrEqual(map, "surf_summit_csgo", false))
    {
        strcopy(label, maxlen, "Surf: Summit");
    }
    else if (StrEqual(map, "kz_beginnerblock_go", false))
    {
        strcopy(label, maxlen, "KZ: Beginner Block");
    }
    else
    {
        strcopy(label, maxlen, map);
    }
}

void GetOneVOneMapLabel(const char[] map, char[] label, int maxlen)
{
    if (StrEqual(map, "am_ramps", false))
    {
        strcopy(label, maxlen, "1v1: Ramps");
    }
    else if (StrEqual(map, "am_courtyard", false))
    {
        strcopy(label, maxlen, "1v1: Courtyard");
    }
    else if (StrEqual(map, "am_grass2", false))
    {
        strcopy(label, maxlen, "1v1: Grass2");
    }
    else if (StrEqual(map, "am_water", false))
    {
        strcopy(label, maxlen, "1v1: Water");
    }
    else
    {
        strcopy(label, maxlen, map);
    }
}
