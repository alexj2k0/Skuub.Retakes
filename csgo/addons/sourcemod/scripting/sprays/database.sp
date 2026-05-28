#include <sourcemod>
#include <sdktools>

public void SQLConnectCallback(Database database, const char[] error, any data)
{
    if (database == null)
    {
        LogError("Sprays: Failed to connect to database: %s", error);
        return;
    }

    g_hDatabase = database;
    LogMessage("Sprays: Connected to database successfully.");

    char createQuery[512];
    FormatEx(createQuery, sizeof(createQuery),
        "CREATE TABLE IF NOT EXISTS %ssprays (\
            steamid VARCHAR(32) PRIMARY KEY,\
            spray_index INT DEFAULT -1,\
            last_updated INT DEFAULT 0\
        )", g_TablePrefix);

    g_hDatabase.Query(T_CreateTableCallback, createQuery, _, DBPrio_High);
}

public void T_CreateTableCallback(Database database, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("Sprays: Failed to create table: %s", error);
        return;
    }

    LoadSprayConfig();
    PrecacheAllSprays();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            GetPlayerData(i);
        }
    }
}

void GetPlayerData(int client)
{
    if (g_hDatabase == null || IsFakeClient(client))
        return;

    char steamid[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), true))
        return;

    char query[256];
    FormatEx(query, sizeof(query), "SELECT spray_index FROM %ssprays WHERE steamid = '%s'", g_TablePrefix, steamid);

    g_hDatabase.Query(T_GetPlayerDataCallback, query, GetClientUserId(client));
}

public void T_GetPlayerDataCallback(Database database, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client))
        return;

    if (error[0] != '\0')
    {
        LogError("Sprays: Failed to get player data: %s", error);
        return;
    }

    if (results != null && results.FetchRow())
    {
        int sprayIndex = results.FetchInt(0);
        if (sprayIndex >= 0 && sprayIndex < g_iTotalSprayCount)
        {
            g_iPlayerSpraySelection[client] = sprayIndex;
        }
    }
}

void SavePlayerData(int client)
{
    if (g_hDatabase == null || IsFakeClient(client))
        return;

    if (g_iPlayerSpraySelection[client] < 0)
        return;

    char steamid[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), true))
        return;

    int now = GetTime();
    char query[512];
    FormatEx(query, sizeof(query),
        "REPLACE INTO %ssprays (steamid, spray_index, last_updated) VALUES ('%s', %d, %d)",
        g_TablePrefix, steamid, g_iPlayerSpraySelection[client], now);

    g_hDatabase.Query(T_SavePlayerDataCallback, query);
}

public void T_SavePlayerDataCallback(Database database, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("Sprays: Failed to save player data: %s", error);
    }
}
