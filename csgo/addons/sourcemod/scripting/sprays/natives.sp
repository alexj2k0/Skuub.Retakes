#include <sourcemod>
#include <sprays>

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("Sprays_GetClientSpray", Native_GetClientSpray);
    CreateNative("Sprays_SetClientSpray", Native_SetClientSpray);
    CreateNative("Sprays_GetSprayCount", Native_GetSprayCount);
    CreateNative("Sprays_GetSprayName", Native_GetSprayName);
    CreateNative("Sprays_GetSprayMaterial", Native_GetSprayMaterial);

    RegPluginLibrary("sprays");

    return APLRes_Success;
}

public int Native_GetClientSpray(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        return -1;

    return g_iPlayerSpraySelection[client];
}

public int Native_SetClientSpray(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int sprayIndex = GetNativeCell(2);

    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        return 0;

    if (sprayIndex < 0 || sprayIndex >= g_iTotalSprayCount)
        return 0;

    g_iPlayerSpraySelection[client] = sprayIndex;

    if (g_hCookie != null && AreClientCookiesCached(client))
    {
        char sCookie[16];
        IntToString(sprayIndex, sCookie, sizeof(sCookie));
        SetClientCookie(client, g_hCookie, sCookie);
    }

    SavePlayerData(client);

    return 1;
}

public int Native_GetSprayCount(Handle plugin, int numParams)
{
    return g_iTotalSprayCount;
}

public int Native_GetSprayName(Handle plugin, int numParams)
{
    int sprayIndex = GetNativeCell(1);
    int maxLength = GetNativeCell(3);

    if (sprayIndex < 0 || sprayIndex >= g_iTotalSprayCount)
        return 0;

    SetNativeString(2, g_SprayNames[sprayIndex], maxLength);
    return 1;
}

public int Native_GetSprayMaterial(Handle plugin, int numParams)
{
    int sprayIndex = GetNativeCell(1);
    int maxLength = GetNativeCell(3);

    if (sprayIndex < 0 || sprayIndex >= g_iTotalSprayCount)
        return 0;

    SetNativeString(2, g_SprayMaterials[sprayIndex], maxLength);
    return 1;
}
