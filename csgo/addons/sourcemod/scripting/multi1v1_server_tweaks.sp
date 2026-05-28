#include <sourcemod>

#undef REQUIRE_PLUGIN
#include "include/multi1v1.inc"

#pragma semicolon 1
#pragma newdecls required

ConVar g_AwpChanceCvar;
ConVar g_RandomPairingsCvar;

bool g_Multi1v1Available;
int g_AwpRoundType = -1;

public Plugin myinfo =
{
    name = "Multi1v1 Server Tweaks",
    author = "OpenAI",
    description = "Randomizes 1v1 pairings and injects rare AWP rounds.",
    version = "1.0.0",
    url = ""
};

public void OnPluginStart()
{
    g_AwpChanceCvar = CreateConVar("sm_multi1v1_rare_awp_chance", "6", "Percent chance for an arena to be forced into an AWP round.", _, true, 0.0, true, 100.0);
    g_RandomPairingsCvar = CreateConVar("sm_multi1v1_random_pairings", "1", "Whether to shuffle the active multi1v1 queue before assigning arenas.", _, true, 0.0, true, 1.0);

    AutoExecConfig(true, "server_tweaks", "sourcemod/multi1v1");
}

public void OnAllPluginsLoaded()
{
    RefreshMulti1v1State();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "multi1v1"))
    {
        RefreshMulti1v1State();
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "multi1v1"))
    {
        g_Multi1v1Available = false;
        g_AwpRoundType = -1;
    }
}

public void Multi1v1_OnRoundTypesAdded()
{
    RefreshRoundTypes();
}

public void Multi1v1_OnPostArenaRankingsSet(ArrayList rankingQueue)
{
    if (!g_Multi1v1Available || !g_RandomPairingsCvar.BoolValue)
    {
        return;
    }

    ShuffleQueue(rankingQueue);
}

public void Multi1v1_OnRoundTypeDecided(int arena, int player1, int player2, int &roundType)
{
    if (!g_Multi1v1Available)
    {
        return;
    }

    if (g_AwpRoundType < 0)
    {
        RefreshRoundTypes();
    }

    int chance = g_AwpChanceCvar.IntValue;
    if (g_AwpRoundType >= 0 && chance > 0 && GetRandomInt(1, 100) <= chance)
    {
        roundType = g_AwpRoundType;
    }
}

void RefreshMulti1v1State()
{
    g_Multi1v1Available = LibraryExists("multi1v1");
    if (g_Multi1v1Available)
    {
        RefreshRoundTypes();
    }
    else
    {
        g_AwpRoundType = -1;
    }
}

void RefreshRoundTypes()
{
    if (!LibraryExists("multi1v1"))
    {
        g_Multi1v1Available = false;
        g_AwpRoundType = -1;
        return;
    }

    g_Multi1v1Available = true;
    g_AwpRoundType = Multi1v1_GetRoundTypeIndex("awp");
}

void ShuffleQueue(ArrayList queue)
{
    for (int i = queue.Length - 1; i > 0; i--)
    {
        int j = GetRandomInt(0, i);
        int a = queue.Get(i);
        int b = queue.Get(j);
        queue.Set(i, b);
        queue.Set(j, a);
    }
}
