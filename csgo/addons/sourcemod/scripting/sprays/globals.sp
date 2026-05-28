#include <sdktools>

char g_ChatPrefix[128];
char g_DBConnection[64];
char g_TablePrefix[64];

Database g_hDatabase = null;
Handle g_hCookie = null;

ConVar g_Cvar_ChatPrefix;
ConVar g_Cvar_MaxSprayDistance;
ConVar g_Cvar_MaxSpraysPerRound;
ConVar g_Cvar_RemoveSpraysOnRoundEnd;
ConVar g_Cvar_EnableAdminOnly;
ConVar g_Cvar_DBConnection;
ConVar g_Cvar_TablePrefix;
ConVar g_Cvar_SprayScale;

float g_fMaxSprayDistance;
float g_fSprayScale;
int   g_iMaxSpraysPerRound;
bool  g_bRemoveSpraysOnRoundEnd;
bool  g_bAdminOnly;

int g_iSprayCategoryCount = 0;
int g_iTotalSprayCount = 0;

char g_SprayNames[256][64];
char g_SprayMaterials[256][PLATFORM_MAX_PATH];
char g_SprayDownloads[256][PLATFORM_MAX_PATH];
int  g_SprayCategoryIndex[256];
int  g_SprayDecalIndex[256];
int  g_SprayMenuIndex[256];

char g_CategoryNames[32][64];
Menu g_hCategoryMenu = null;
Menu g_hSprayMenus[32];

int g_iPlayerSpraySelection[MAXPLAYERS + 1] = { -1, ... };
float g_fPlayerLastSprayTime[MAXPLAYERS + 1];
int g_iPlayerSpraysThisRound[MAXPLAYERS + 1];

ArrayList g_hActiveDecals = null;
