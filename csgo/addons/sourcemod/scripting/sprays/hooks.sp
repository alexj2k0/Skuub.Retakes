#include <sourcemod>
#include <sdktools>

public void OnClientPutInServer(int client)
{
    if (IsFakeClient(client))
        return;

    g_iPlayerSpraySelection[client] = -1;
    g_fPlayerLastSprayTime[client] = 0.0;
    g_iPlayerSpraysThisRound[client] = 0;

    if (g_hDatabase != null)
    {
        GetPlayerData(client);
    }

    if (g_iTotalSprayCount > 0)
    {
        CreateTimer(10.0, Timer_WelcomeSprays, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnClientCookiesCached(int client)
{
    if (IsFakeClient(client) || g_hCookie == null)
        return;

    char sCookie[16];
    GetClientCookie(client, g_hCookie, sCookie, sizeof(sCookie));

    if (sCookie[0] != '\0')
    {
        int cookieIndex = StringToInt(sCookie);
        if (cookieIndex >= 0 && cookieIndex < g_iTotalSprayCount)
        {
            g_iPlayerSpraySelection[client] = cookieIndex;
        }
    }
}

public void OnClientDisconnect(int client)
{
    if (IsFakeClient(client))
        return;

    if (g_hCookie != null && g_iPlayerSpraySelection[client] >= 0 && AreClientCookiesCached(client))
    {
        char sCookie[16];
        IntToString(g_iPlayerSpraySelection[client], sCookie, sizeof(sCookie));
        SetClientCookie(client, g_hCookie, sCookie);
    }

    g_iPlayerSpraySelection[client] = -1;
    g_fPlayerLastSprayTime[client] = 0.0;
    g_iPlayerSpraysThisRound[client] = 0;
}

public Action Timer_WelcomeSprays(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
        return Plugin_Stop;

    PrintToChat(client, " %s \x04Type \x03!sprays\x04 to choose a custom spray, then \x03!spray\x04 to place it!", g_ChatPrefix);
    return Plugin_Stop;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iPlayerSpraysThisRound[i] = 0;
    }

    if (g_bRemoveSpraysOnRoundEnd && g_hActiveDecals != null)
    {
        g_hActiveDecals.Clear();
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
}
