#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name = "Stuck",
    author = "server",
    description = "!stuck command to unstuck players from walls/geometry",
    version = "1.0.0",
    url = ""
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_stuck", Command_Stuck);
}

public Action Command_Stuck(int client, int args)
{
    if (!client || !IsClientInGame(client))
        return Plugin_Handled;

    if (!IsPlayerAlive(client))
    {
        PrintToChat(client, "[SM] You must be alive to use !stuck.");
        return Plugin_Handled;
    }

    float origin[3], angles[3];
    GetClientAbsOrigin(client, origin);
    GetClientEyeAngles(client, angles);

    float testPos[3];

    // Try scanning upward from current position
    for (int i = 1; i <= 40; i++)
    {
        testPos[0] = origin[0];
        testPos[1] = origin[1];
        testPos[2] = origin[2] + (i * 16.0);

        if (TracePlayerHull(client, testPos))
        {
            TeleportEntity(client, testPos, angles, NULL_VECTOR);
            PrintToChat(client, "[SM] You have been unstuck!");
            return Plugin_Handled;
        }
    }

    // Try cardinal directions with upward offset
    float offsets[4][2] = {
        {64.0, 0.0},
        {-64.0, 0.0},
        {0.0, 64.0},
        {0.0, -64.0}
    };

    for (int dir = 0; dir < 4; dir++)
    {
        for (int h = 1; h <= 20; h++)
        {
            testPos[0] = origin[0] + offsets[dir][0];
            testPos[1] = origin[1] + offsets[dir][1];
            testPos[2] = origin[2] + (h * 16.0);

            if (TracePlayerHull(client, testPos))
            {
                TeleportEntity(client, testPos, angles, NULL_VECTOR);
                PrintToChat(client, "[SM] You have been unstuck!");
                return Plugin_Handled;
            }
        }
    }

    PrintToChat(client, "[SM] Could not find a clear position. Contact an admin.");
    return Plugin_Handled;
}

bool TracePlayerHull(int client, float pos[3])
{
    float mins[3] = {-16.0, -16.0, 0.0};
    float maxs[3] = {16.0, 16.0, 72.0};

    Handle trace = TR_TraceHullFilterEx(pos, pos, mins, maxs, MASK_PLAYERSOLID, TraceFilterSelf, client);
    bool blocked = TR_DidHit(trace);
    delete trace;

    return !blocked;
}

public bool TraceFilterSelf(int entity, int contentsMask, any data)
{
    return entity != data;
}
