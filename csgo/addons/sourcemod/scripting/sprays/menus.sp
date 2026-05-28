#include <sourcemod>
#include <sdktools>

void DisplayCategoryMenu(int client)
{
    if (g_hCategoryMenu == null)
        return;

    g_hCategoryMenu.Display(client, MENU_TIME_FOREVER);
}

void DisplaySprayMenu(int client, int categoryIndex)
{
    if (categoryIndex < 0 || categoryIndex >= g_iSprayCategoryCount)
        return;

    if (g_hSprayMenus[categoryIndex] == null)
        return;

    g_hSprayMenus[categoryIndex].Display(client, MENU_TIME_FOREVER);
}

public int CategoryMenuHandler(Menu menu, MenuAction action, int client, int selection)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char sIndex[8];
            menu.GetItem(selection, sIndex, sizeof(sIndex));
            int categoryIndex = StringToInt(sIndex);

            if (categoryIndex >= 0 && categoryIndex < g_iSprayCategoryCount)
            {
                DisplaySprayMenu(client, categoryIndex);
            }
        }
        case MenuAction_Cancel:
        {
            if (selection == MenuCancel_ExitBack)
            {
            }
        }
    }
    return 0;
}

public int SprayMenuHandler(Menu menu, MenuAction action, int client, int selection)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char sIndex[8];
            menu.GetItem(selection, sIndex, sizeof(sIndex));
            int sprayIndex = StringToInt(sIndex);

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

            PrintToChat(client, " %s \x04Spray selected: \x03%s\x04! Use \x03!spray\x04 to place it.", g_ChatPrefix, g_SprayNames[sprayIndex]);

            int categoryIndex = g_SprayCategoryIndex[sprayIndex];
            DisplaySprayMenu(client, categoryIndex);
        }
        case MenuAction_Cancel:
        {
            if (selection == MenuCancel_ExitBack)
            {
                if (g_iSprayCategoryCount > 1)
                {
                    DisplayCategoryMenu(client);
                }
            }
        }
        case MenuAction_DisplayItem:
        {
            char sIndex[8];
            menu.GetItem(selection, sIndex, sizeof(sIndex));
            int sprayIndex = StringToInt(sIndex);

            if (sprayIndex == g_iPlayerSpraySelection[client])
            {
                char sDisplay[128];
                FormatEx(sDisplay, sizeof(sDisplay), "%s [SELECTED]", g_SprayNames[sprayIndex]);
                return RedrawMenuItem(sDisplay);
            }
        }
    }
    return 0;
}
