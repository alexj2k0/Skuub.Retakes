#include <sourcemod>
#include <sdktools>

stock bool IsValidClient(int client, bool checkAlive = false)
{
    if (client <= 0 || client > MaxClients)
        return false;
    if (!IsClientInGame(client))
        return false;
    if (IsFakeClient(client))
        return false;
    if (IsClientSourceTV(client) || IsClientReplay(client))
        return false;
    if (checkAlive && !IsPlayerAlive(client))
        return false;
    return true;
}

int g_iGlowSprite = 0;

stock void PrecacheAllSprays()
{
    for (int i = 0; i < g_iTotalSprayCount; i++)
    {
        if (g_SprayDownloads[i][0] != '\0')
        {
            AddFileToDownloadsTable(g_SprayDownloads[i]);
        }

        g_SprayDecalIndex[i] = PrecacheDecal(g_SprayMaterials[i], true);
    }
}

stock bool PlaceSprayDecal(int client, int sprayIndex)
{
    if (sprayIndex < 0 || sprayIndex >= g_iTotalSprayCount)
        return false;

    float fEyePos[3], fEyeAng[3], fEndPos[3];
    GetClientEyePosition(client, fEyePos);
    GetClientEyeAngles(client, fEyeAng);

    float fDir[3];
    GetAngleVectors(fEyeAng, fDir, NULL_VECTOR, NULL_VECTOR);

    fEndPos[0] = fEyePos[0] + fDir[0] * g_fMaxSprayDistance;
    fEndPos[1] = fEyePos[1] + fDir[1] * g_fMaxSprayDistance;
    fEndPos[2] = fEyePos[2] + fDir[2] * g_fMaxSprayDistance;

    Handle hTrace = TR_TraceRayFilterEx(fEyePos, fEndPos, MASK_SHOT, RayType_EndPoint, TraceFilterWorldOnly, client);

    if (!TR_DidHit(hTrace))
    {
        delete hTrace;
        return false;
    }

    float fHitPos[3], fHitNormal[3];
    TR_GetEndPosition(fHitPos, hTrace);
    TR_GetPlaneNormal(hTrace, fHitNormal);

    delete hTrace;

    int decal = CreateEntityByName("infodecal");
    if (decal == -1)
        return false;

    DispatchKeyValue(decal, "texture", g_SprayMaterials[sprayIndex]);

    float fDecalPos[3];
    fDecalPos[0] = fHitPos[0] + fHitNormal[0] * 2.0;
    fDecalPos[1] = fHitPos[1] + fHitNormal[1] * 2.0;
    fDecalPos[2] = fHitPos[2] + fHitNormal[2] * 2.0;

    TeleportEntity(decal, fDecalPos, NULL_VECTOR, NULL_VECTOR);
    DispatchSpawn(decal);

    if (g_hActiveDecals != null)
    {
        int iData[1];
        iData[0] = EntIndexToEntRef(decal);
        g_hActiveDecals.PushArray(iData);
    }

    return true;
}

stock bool PlaceTestGlow(int client)
{
    float fEyePos[3], fEyeAng[3], fEndPos[3];
    GetClientEyePosition(client, fEyePos);
    GetClientEyeAngles(client, fEyeAng);

    float fDir[3];
    GetAngleVectors(fEyeAng, fDir, NULL_VECTOR, NULL_VECTOR);

    fEndPos[0] = fEyePos[0] + fDir[0] * g_fMaxSprayDistance;
    fEndPos[1] = fEyePos[1] + fDir[1] * g_fMaxSprayDistance;
    fEndPos[2] = fEyePos[2] + fDir[2] * g_fMaxSprayDistance;

    Handle hTrace = TR_TraceRayFilterEx(fEyePos, fEndPos, MASK_SHOT, RayType_EndPoint, TraceFilterWorldOnly, client);

    if (!TR_DidHit(hTrace))
    {
        delete hTrace;
        return false;
    }

    float fHitPos[3];
    TR_GetEndPosition(fHitPos, hTrace);
    delete hTrace;

    int sprite = CreateEntityByName("env_sprite");
    if (sprite == -1)
        return false;

    DispatchKeyValue(sprite, "model", "sprites/glow01.vmt");
    DispatchKeyValue(sprite, "scale", "0.5");
    DispatchKeyValue(sprite, "spawnflags", "1");
    DispatchKeyValue(sprite, "rendermode", "0");

    TeleportEntity(sprite, fHitPos, NULL_VECTOR, NULL_VECTOR);
    DispatchSpawn(sprite);

    PrintToChat(client, " %s \x04Test glow placed at (%.1f, %.1f, %.1f). Can you see it?", g_ChatPrefix, fHitPos[0], fHitPos[1], fHitPos[2]);
    return true;
}

public bool TraceFilterWorldOnly(int entity, int contentsMask, any data)
{
    if (entity == data || entity == 0)
        return true;
    return false;
}

stock void RemoveAllActiveDecals()
{
    if (g_hActiveDecals == null || g_hActiveDecals.Length == 0)
        return;

    for (int i = 0; i < g_hActiveDecals.Length; i++)
    {
        int iData[1];
        g_hActiveDecals.GetArray(i, iData);

        int sprite = EntRefToEntIndex(iData[0]);
        if (sprite != INVALID_ENT_REFERENCE && IsValidEntity(sprite))
        {
            AcceptEntityInput(sprite, "Kill");
        }
    }

    g_hActiveDecals.Clear();
}

public Action Command_Spray(int client, int args)
{
    if (!IsValidClient(client, true))
    {
        PrintToChat(client, " %s \x02You must be alive to spray!", g_ChatPrefix);
        return Plugin_Handled;
    }

    if (g_bAdminOnly && !CheckCommandAccess(client, "sm_sprays_admin", ADMFLAG_GENERIC))
    {
        PrintToChat(client, " %s \x02Sprays are currently restricted to admins only.", g_ChatPrefix);
        return Plugin_Handled;
    }

    if (g_iTotalSprayCount == 0)
    {
        PrintToChat(client, " %s \x02No sprays are available.", g_ChatPrefix);
        return Plugin_Handled;
    }

    if (g_iPlayerSpraySelection[client] < 0)
    {
        PrintToChat(client, " %s \x02You haven't selected a spray yet! Type \x03!sprays", g_ChatPrefix);
        return Plugin_Handled;
    }

    if (g_iMaxSpraysPerRound > 0 && g_iPlayerSpraysThisRound[client] >= g_iMaxSpraysPerRound)
    {
        PrintToChat(client, " %s \x02You've reached the spray limit for this round!", g_ChatPrefix);
        return Plugin_Handled;
    }

    int sprayIndex = g_iPlayerSpraySelection[client];
    if (PlaceSprayDecal(client, sprayIndex))
    {
        g_iPlayerSpraysThisRound[client]++;
        PrintToChat(client, " %s \x04Spray placed! \x03(%s)", g_ChatPrefix, g_SprayNames[sprayIndex]);
    }
    else
    {
        PrintToChat(client, " %s \x02Cannot place spray here. Try a wall or floor.", g_ChatPrefix);
    }

    return Plugin_Handled;
}

public Action Command_Sprays(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    if (g_bAdminOnly && !CheckCommandAccess(client, "sm_sprays_admin", ADMFLAG_GENERIC))
    {
        PrintToChat(client, " %s \x02Sprays are currently restricted to admins only.", g_ChatPrefix);
        return Plugin_Handled;
    }

    if (g_iTotalSprayCount == 0)
    {
        PrintToChat(client, " %s \x02No sprays are available.", g_ChatPrefix);
        return Plugin_Handled;
    }

    if (g_iSprayCategoryCount > 1)
    {
        DisplayCategoryMenu(client);
    }
    else
    {
        DisplaySprayMenu(client, 0);
    }

    return Plugin_Handled;
}

public Action Command_SprayTest(int client, int args)
{
    if (!IsValidClient(client, true))
        return Plugin_Handled;

    PlaceTestGlow(client);
    return Plugin_Handled;
}
