#include <sourcemod>

#define CHAT_PREFIX "[Maps]"

char g_CurrentMode[32];

public Plugin myinfo =
{
    name = "Map Lister",
    author = "pach",
    description = "Chat command !maps to list all maps for the current game mode.",
    version = "1.0.0",
    url = ""
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_maps", Command_Maps, "Lists all maps for the current server mode");
}

public void OnMapStart()
{
    DetectCurrentMode();
}

void DetectCurrentMode()
{
    char mapName[PLATFORM_MAX_PATH];
    GetCurrentMap(mapName, sizeof(mapName));

    if (StrContains(mapName, "am_") == 0)
        g_CurrentMode = "1v1";
    else if (StrContains(mapName, "surf_") == 0 || StrContains(mapName, "kz_") == 0)
        g_CurrentMode = "movement";
    else
        g_CurrentMode = "retakes";
}

void GetMaplistFile(char[] buffer, int maxlen)
{
    if (StrEqual(g_CurrentMode, "1v1"))
        strcopy(buffer, maxlen, "addons/sourcemod/configs/onevone_maplist.ini");
    else if (StrEqual(g_CurrentMode, "movement"))
        strcopy(buffer, maxlen, "addons/sourcemod/configs/movement_maplist.ini");
    else
        strcopy(buffer, maxlen, "addons/sourcemod/configs/retakes_maplist.ini");
}

void GetModeLabel(char[] buffer, int maxlen)
{
    if (StrEqual(g_CurrentMode, "1v1"))
        strcopy(buffer, maxlen, "1v1 Arena");
    else if (StrEqual(g_CurrentMode, "movement"))
        strcopy(buffer, maxlen, "Movement");
    else
        strcopy(buffer, maxlen, "Retakes");
}

public Action Command_Maps(int client, int args)
{
    char maplistFile[256];
    GetMaplistFile(maplistFile, sizeof(maplistFile));

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), maplistFile);

    File file = OpenFile(path, "r");
    if (file == null)
    {
        char modeLabel[32];
        GetModeLabel(modeLabel, sizeof(modeLabel));
        ReplyToCommand(client, "%s No map list found for %s mode.", CHAT_PREFIX, modeLabel);
        return Plugin_Handled;
    }

    char maps[1024];
    maps[0] = '\0';
    char line[PLATFORM_MAX_PATH];
    int count = 0;

    while (!file.EndOfFile() && file.ReadLine(line, sizeof(line)))
    {
        TrimString(line);
        if (line[0] == '\0' || line[0] == ';' || (line[0] == '/' && line[1] == '/'))
            continue;

        if (count > 0)
            StrCat(maps, sizeof(maps), ", ");
        StrCat(maps, sizeof(maps), line);
        count++;

        if (count >= 20)
        {
            StrCat(maps, sizeof(maps), "...");
            break;
        }
    }

    delete file;

    if (count == 0)
    {
        ReplyToCommand(client, "%s Map list is empty.", CHAT_PREFIX);
        return Plugin_Handled;
    }

    char modeLabel[32];
    GetModeLabel(modeLabel, sizeof(modeLabel));
    ReplyToCommand(client, "%s %s maps (%d): %s", CHAT_PREFIX, modeLabel, count, maps);
    return Plugin_Handled;
}
