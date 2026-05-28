#include <sourcemod>
#include <sdktools>
#include <keyvalues>

void LoadSprayConfig()
{
    g_iSprayCategoryCount = 0;
    g_iTotalSprayCount = 0;

    char sConfigPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sConfigPath, sizeof(sConfigPath), "configs/sprays/sprays.cfg");

    if (!FileExists(sConfigPath))
    {
        LogError("Sprays: Configuration file not found: %s", sConfigPath);
        return;
    }

    KeyValues kv = new KeyValues("Sprays");
    if (!kv.ImportFromFile(sConfigPath))
    {
        delete kv;
        LogError("Sprays: Failed to parse configuration file: %s", sConfigPath);
        return;
    }

    if (!kv.GotoFirstSubKey())
    {
        delete kv;
        LogMessage("Sprays: No spray categories found in config.");
        return;
    }

    do
    {
        char sCategoryName[64];
        kv.GetSectionName(sCategoryName, sizeof(sCategoryName));

        if (g_iSprayCategoryCount >= 32)
        {
            LogError("Sprays: Too many categories (max 32), skipping '%s'", sCategoryName);
            continue;
        }

        strcopy(g_CategoryNames[g_iSprayCategoryCount], sizeof(g_CategoryNames[]), sCategoryName);

        if (kv.GotoFirstSubKey())
        {
            do
            {
                char sSprayName[64], sMaterial[PLATFORM_MAX_PATH], sDownload[PLATFORM_MAX_PATH];

                kv.GetSectionName(sSprayName, sizeof(sSprayName));
                kv.GetString("material", sMaterial, sizeof(sMaterial), "");
                kv.GetString("download", sDownload, sizeof(sDownload), "");

                if (sMaterial[0] == '\0')
                {
                    LogError("Sprays: Spray '%s' in category '%s' has no material path, skipping.", sSprayName, sCategoryName);
                    continue;
                }

                if (g_iTotalSprayCount >= 256)
                {
                    LogError("Sprays: Too many sprays (max 256), skipping '%s'", sSprayName);
                    continue;
                }

                strcopy(g_SprayNames[g_iTotalSprayCount], sizeof(g_SprayNames[]), sSprayName);
                strcopy(g_SprayMaterials[g_iTotalSprayCount], sizeof(g_SprayMaterials[]), sMaterial);
                strcopy(g_SprayDownloads[g_iTotalSprayCount], sizeof(g_SprayDownloads[]), sDownload);
                g_SprayCategoryIndex[g_iTotalSprayCount] = g_iSprayCategoryCount;
                g_SprayDecalIndex[g_iTotalSprayCount] = 0;

                g_iTotalSprayCount++;

            } while (kv.GotoNextKey());

            kv.GoBack();
        }

        g_iSprayCategoryCount++;

    } while (kv.GotoNextKey());

    delete kv;

    BuildMenus();

    LogMessage("Sprays: Loaded %d sprays in %d categories.", g_iTotalSprayCount, g_iSprayCategoryCount);
}

void BuildMenus()
{
    if (g_iSprayCategoryCount > 1)
    {
        delete g_hCategoryMenu;

        g_hCategoryMenu = new Menu(CategoryMenuHandler, MENU_ACTIONS_DEFAULT);
        g_hCategoryMenu.SetTitle("Sprays - Categories:");
        g_hCategoryMenu.ExitBackButton = false;

        for (int i = 0; i < g_iSprayCategoryCount; i++)
        {
            char sIndex[8];
            IntToString(i, sIndex, sizeof(sIndex));
            g_hCategoryMenu.AddItem(sIndex, g_CategoryNames[i]);
        }
    }

    for (int cat = 0; cat < g_iSprayCategoryCount; cat++)
    {
        delete g_hSprayMenus[cat];

        char sTitle[128];
        FormatEx(sTitle, sizeof(sTitle), "Sprays - %s:", g_CategoryNames[cat]);

        g_hSprayMenus[cat] = new Menu(SprayMenuHandler, MENU_ACTIONS_DEFAULT);
        g_hSprayMenus[cat].SetTitle(sTitle);
        g_hSprayMenus[cat].ExitBackButton = (g_iSprayCategoryCount > 1);

        int menuIndex = 0;
        for (int i = 0; i < g_iTotalSprayCount; i++)
        {
            if (g_SprayCategoryIndex[i] == cat)
            {
                char sIndex[8];
                IntToString(i, sIndex, sizeof(sIndex));
                g_hSprayMenus[cat].AddItem(sIndex, g_SprayNames[i]);
                g_SprayMenuIndex[i] = menuIndex;
                menuIndex++;
            }
        }
    }
}

void ReloadSprayConfig()
{
    delete g_hCategoryMenu;
    for (int i = 0; i < 32; i++)
    {
        delete g_hSprayMenus[i];
    }

    LoadSprayConfig();
}
