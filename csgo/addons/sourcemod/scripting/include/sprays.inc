#if defined _sprays_included
    #endinput
#endif
#define _sprays_included

public SharedPlugin __pl_sprays =
{
    name = "sprays",
    file = "sprays.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_sprays_SetNTVOptional()
{
    MarkNativeAsOptional("Sprays_GetClientSpray");
    MarkNativeAsOptional("Sprays_SetClientSpray");
    MarkNativeAsOptional("Sprays_GetSprayCount");
    MarkNativeAsOptional("Sprays_GetSprayName");
    MarkNativeAsOptional("Sprays_GetSprayMaterial");
}
#endif

native int Sprays_GetClientSpray(int client);
native int Sprays_SetClientSpray(int client, int sprayIndex);
native int Sprays_GetSprayCount();
native int Sprays_GetSprayName(int sprayIndex, char[] name, int maxLength);
native int Sprays_GetSprayMaterial(int sprayIndex, char[] material, int maxLength);
