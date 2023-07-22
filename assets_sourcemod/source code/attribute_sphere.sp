#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>
#include <hudframework>

public Plugin myinfo =
{
	name = "Attribute: Sphere",
	author = "Noclue",
	description = "Attributes for The Sphere.",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

DynamicDetour hSimpleTrace;
DynamicDetour hSentryTrace;
DynamicHook hShouldCollide;
DynamicHook hTouch;
DynamicHook hPostFrame;
DynamicHook hTakeDamage;

Handle hTouchCall;

PlayerFlags g_HasSphere;
int g_iSphereShields[ MAXPLAYERS+1 ] = { -1, ... };
int g_iMaterialManager[ MAXPLAYERS+1 ] = { -1, ... };
float g_flShieldCooler[ MAXPLAYERS+1 ];

#define SHIELD_MODEL "models/props_mvm/mvm_player_shield.mdl"
#define SHIELDKEYNAME "Shield"

//max shield energy
#define SHIELD_MAX 1200.0
//time for shield to drain while active
#define SHIELD_DURATION 16.0
//multiplier for shield energy to be gained when dealing damage
#define SHIELD_DAMAGE_TO_CHARGE_SCALE 2.0
//multiplier for shield energy to be lost when it is damaged
#define SHIELD_DAMAGE_DRAIN_SCALE 1.0

public void OnPluginStart() {
	HookEvent( EVENT_POSTINVENTORY,	Event_PostInventory );

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hSimpleTrace = DynamicDetour.FromConf( hGameConf, "CTraceFilterSimple::ShouldHitEntity" );
	hSimpleTrace.Enable( Hook_Post, Detour_ShouldHitEntitySimple );

	hSentryTrace = DynamicDetour.FromConf( hGameConf, "CTraceFilterIgnoreTeammatesExceptEntity::ShouldHitEntity" );
	hSentryTrace.Enable( Hook_Post, Detour_ShouldHitEntitySentry );

	hShouldCollide = DynamicHook.FromConf( hGameConf, "CBaseEntity::ShouldCollide" );
	hTouch = DynamicHook.FromConf( hGameConf, "CBaseEntity::Touch" );

	hPostFrame = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::ItemPostFrame" );
	hTakeDamage = DynamicHook.FromConf( hGameConf, "CBaseEntity::OnTakeDamage" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CBaseEntity::Touch" );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	hTouchCall = EndPrepSDKCall();

	delete hGameConf;
}

public void OnMapStart() {
	PrecacheModel( SHIELD_MODEL );
	PrecacheSound( "weapons/medi_shield_deploy.wav" );
	PrecacheSound( "weapons/medi_shield_retract.wav" );
}

public void OnEntityCreated( int iEntity ) {
	static char szEntityName[ 128 ];
	GetEntityClassname( iEntity, szEntityName, sizeof( szEntityName ) );
	if( StrEqual( szEntityName, "tf_weapon_minigun", false ) ) {
		RequestFrame( SetupMinigun, EntIndexToEntRef( iEntity ) );
	}
}

void SetupMinigun( int iMinigun ) {
	iMinigun = EntRefToEntIndex( iMinigun );
	if( iMinigun == -1 || AttribHookFloat( 0.0, iMinigun, "custom_sphere" ) == 0.0 )
		return;

	hPostFrame.HookEntity( Hook_Post, iMinigun, Hook_PostFrame );
}

MRESReturn Hook_PostFrame( int iThis ) {
	int iWeaponOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( !IsValidPlayer( iWeaponOwner ) )
		return MRES_Ignored;

	int iWeaponState = GetEntProp( iThis, Prop_Send, "m_iWeaponState" );
	int iShield = EntRefToEntIndex( g_iSphereShields[ iWeaponOwner ] );
	float flTrackerValue = Tracker_GetValue( iWeaponOwner, SHIELDKEYNAME );

	if( !( iWeaponState == 2 || iWeaponState == 3 ) && flTrackerValue > 0.0 ) { //spinning
		RemoveShield( iWeaponOwner );
		return MRES_Handled;
	}

	if( iShield == -1 )
		SpawnShield( iWeaponOwner );

	float flDrainRate = ( SHIELD_MAX / ( SHIELD_DURATION / GetGameFrameTime() ) );
	Tracker_SetValue( iWeaponOwner, SHIELDKEYNAME, MaxFloat( 0.0, flTrackerValue - flDrainRate ) );

	return MRES_Handled;
}

Action Event_PostInventory( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( IsValidPlayer( iPlayer ) ) {
		if( AttribHookFloat( 0.0, iPlayer, "custom_sphere" ) != 0.0 ) {
			Tracker_Create( iPlayer, SHIELDKEYNAME, 1200.0, 0.0, RTF_NOOVERWRITE /*| RTF_CLEARONSPAWN*/ );
			g_HasSphere.Set( iPlayer, true );
		}
		else {
			Tracker_Remove( iPlayer, SHIELDKEYNAME );
			g_HasSphere.Set( iPlayer, false );
		}
	}

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int iClient, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if( !IsValidEntity( iClient ) )
		return Plugin_Continue;

	
	if( EntRefToEntIndex( g_iSphereShields[ iClient ] ) != -1 ) {
		if( IsPlayerAlive( iClient ) )
			UpdateShield( iClient );
		else
			RemoveShield( iClient );
	}
	return Plugin_Continue;
}

static char szShieldMats[][] = {
	"models/effects/resist_shield/resist_shield",
	"models/effects/resist_shield/resist_shield_blue",
	"models/effects/resist_shield/resist_shield_green",
	"models/effects/resist_shield/resist_shield_yellow"
};

void SpawnShield( int iOwner ) {
	if( g_flShieldCooler[ iOwner ] > GetGameTime() )
		return;

	int iShield = CreateEntityByName( "prop_dynamic_override" );
	if( !IsValidEntity( iShield ) ) 
		return;

	int iOwnerTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" );
	
	SetEntityModel( iShield, SHIELD_MODEL );
	SetEntProp( iShield, Prop_Send, "m_iTeamNum", iOwnerTeam );
	SetEntPropEnt( iShield, Prop_Send, "m_hOwnerEntity", iOwner );

	SetEntProp( iShield, Prop_Data, "m_iEFlags", EFL_DONTBLOCKLOS );
	
	DispatchSpawn( iShield );

	SetSolid( iShield, SOLID_VPHYSICS );
	SetSolidFlags( iShield, FSOLID_TRIGGER );
	SetCollisionGroup( iShield, COLLISION_GROUP_PUSHAWAY );

	SetEntProp( iShield, Prop_Send, "m_nSkin", iOwnerTeam - 2 );

	//SetEntProp( iShield, Prop_Data, "m_takedamage", DAMAGE_EVENTS_ONLY );
	SetEntProp( iShield, Prop_Data, "m_fEffects", EF_NOSHADOW );

	hShouldCollide.HookEntity( Hook_Post, iShield, Hook_ShieldShouldCollide );
	hTouch.HookEntity( Hook_Post, iShield, Hook_ShieldTouch );
	hTakeDamage.HookEntity( Hook_Pre, iShield, Hook_ShieldTakeDamage );

	EmitSoundToAll( "weapons/medi_shield_deploy.wav", iShield, SNDCHAN_AUTO, 95 );

	g_iSphereShields[ iOwner ] = EntIndexToEntRef( iShield );

	int iManager = CreateEntityByName( "material_modify_control" );

	ParentModel( iManager, iShield );

	DispatchKeyValue( iManager, "materialName", szShieldMats[ iOwnerTeam - 2 ] );
	DispatchKeyValue( iManager, "materialVar", "$shield_falloff" );

	DispatchSpawn( iManager );
	g_iMaterialManager[ iOwner ] = EntIndexToEntRef( iManager );
}

void RemoveShield( int iOwner ) {
	int iShield = EntRefToEntIndex( g_iSphereShields[ iOwner ] );
	int iManager = EntRefToEntIndex( g_iMaterialManager[ iOwner ] );

	if( iShield != -1 ) {
		EmitSoundToAll( "weapons/medi_shield_retract.wav", iShield, SNDCHAN_AUTO, 95 );
		RemoveEntity( iShield );
		g_iSphereShields[ iOwner ] = -1;
		g_flShieldCooler[ iOwner ] = GetGameTime() + 2.0;
	}
	if( iManager != -1 ) {
		RemoveEntity( iManager );
		g_iMaterialManager[ iOwner ] = -1;
	}
}

void UpdateShield( int iClient ) {
	int iShield = EntRefToEntIndex( g_iSphereShields[ iClient ] );
	if( iShield == -1 ) {
		g_iSphereShields[ iClient ] = -1;
		return;
	}

	float vecOrigin[3];
	float vecEyePos[3];
	float vecEyeAngles[3];
	GetEntPropVector( iClient, Prop_Data, "m_vecAbsOrigin", vecOrigin );
	GetClientEyePosition( iClient, vecEyePos );
	GetClientEyeAngles( iClient, vecEyeAngles );

	float vecEndPos[3];
	GetAngleVectors( vecEyeAngles, vecEndPos, NULL_VECTOR, NULL_VECTOR );
	ScaleVector( vecEndPos, 150.0 );
	AddVectors( vecOrigin, vecEndPos, vecEndPos );

	TeleportEntity( iShield, vecEndPos, vecEyeAngles );
	//SetEntPropVector( iShield, Prop_Send, "m_vecOrigin", vecEndPos );
	//SetEntPropVector( iShield, Prop_Send, "m_angRotation", vecEyeAngles );

	int iManager = EntRefToEntIndex( g_iMaterialManager[ iClient ] );
	if( iManager == -1 )
		return;

	//float flLastDamaged = GetGameTime() - g_flLastDamagedShield[ i ];

	float flShieldFalloff = RemapValClamped( Tracker_GetValue( iClient, SHIELDKEYNAME ), 1200.0, 450.0, 2.0, 0.0 );

	static char szFalloff[8];
	FloatToString(flShieldFalloff, szFalloff, 8);

	SetVariantString( szFalloff );
	AcceptEntityInput( iManager, "SetMaterialVar" );
}

static int iCollisionMasks[4] = {
	0x800,	//red
	0x1000,	//blue
	0x400,	//green
	0x200,	//yellow
};

MRESReturn Hook_ShieldShouldCollide( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	int iCollisionGroup = hParams.Get( 1 );
	if( !( iCollisionGroup == COLLISION_GROUP_PROJECTILE || iCollisionGroup == TFCOLLISION_GROUP_ROCKETS || iCollisionGroup == TFCOLLISION_GROUP_ROCKET_BUT_NOT_WITH_OTHER_ROCKETS ) )
		return MRES_Ignored;

	int iTeam = GetEntProp( iThis, Prop_Send, "m_iTeamNum" ) - 2;
	if( iTeam < 0 || iTeam > 3 )
		return MRES_Ignored;

	int iContentsMask = hParams.Get( 2 );
	hReturn.Value = ( iContentsMask & iCollisionMasks[ iTeam ] );
	return MRES_Override;
}

MRESReturn Hook_ShieldTouch( int iThis, DHookParam hParams ) {
	int iOther = hParams.Get( 1 );
	if( !HasEntProp( iOther, Prop_Send, "m_iDeflected" ) )
		return MRES_Handled;

	int iShieldTeam = GetEntProp( iThis, Prop_Send, "m_iTeamNum" );
	int iTouchTeam = GetEntProp( iOther, Prop_Send, "m_iTeamNum" );

	if( iShieldTeam != iTouchTeam ) {
		SDKCall( hTouchCall, iOther, GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" ) );
		return MRES_Handled;
	}
	
	return MRES_Ignored;
}

MRESReturn Hook_ShieldTakeDamage( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( !IsValidPlayer( iOwner ) )
		return MRES_Ignored;

	TFDamageInfo tfInfo = TFDamageInfo( hParams.GetAddress( 1 ) );
	int iAttacker = tfInfo.iAttacker;

	int iOwnerTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" );
	int iAttackerTeam = GetEntProp( iAttacker, Prop_Send, "m_iTeamNum" );

	if( iOwnerTeam == iAttackerTeam )
		return MRES_Ignored;

	float flTrackerValue = Tracker_GetValue( iOwner, SHIELDKEYNAME );
	flTrackerValue = MaxFloat( 0.0, flTrackerValue - ( tfInfo.flDamage * SHIELD_DAMAGE_DRAIN_SCALE ) );
	Tracker_SetValue( iOwner, SHIELDKEYNAME, flTrackerValue );
	
	return MRES_Handled;
}

public void OnTakeDamagePostTF( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	BuildShieldCharge( iTarget, tfInfo );
}

public void OnTakeDamageBuilding( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	BuildShieldCharge( iTarget, tfInfo );
}

void BuildShieldCharge( int iTarget, TFDamageInfo tfInfo ) {
	int iOwner = tfInfo.iAttacker;
	if( !IsValidPlayer( iOwner ) )
		return;

	if( !g_HasSphere.Get( iOwner ) )
		return;

	float flNewValue = MinFloat( SHIELD_MAX, Tracker_GetValue( iOwner, SHIELDKEYNAME ) + ( tfInfo.flDamage * SHIELD_DAMAGE_TO_CHARGE_SCALE ) );
	Tracker_SetValue( iOwner, SHIELDKEYNAME, flNewValue );
}

//offset 4: pass entity
//offset 16: pass team
//offset 20: except entity


//todo: sentry and flame particle collision
MRESReturn Detour_ShouldHitEntitySimple( Address aTrace, DHookReturn hReturn, DHookParam hParams ) {
	//we only care about ignoring the shield so if we weren't going to hit it to begin with than ignore
	if( hReturn.Value == false )
		return MRES_Ignored;
	
	Address aLoad = LoadFromAddressOffset( aTrace, 4, NumberType_Int32 );
	if( aLoad == Address_Null )
		return MRES_Ignored;

	int iPassEntity = GetEntityFromAddress( aLoad );
	if( !IsValidPlayer( iPassEntity ) )
		return MRES_Ignored;

	int iTouched = GetEntityFromAddress( hParams.Get( 1 ) );
	int iOwner = GetEntPropEnt( iTouched, Prop_Send, "m_hOwnerEntity" );

	if( !IsValidPlayer( iOwner ) )
		return MRES_Ignored;

	int iOwnerTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" );
	int iPassTeam = GetEntProp( iPassEntity, Prop_Send, "m_iTeamNum" );

	if( iTouched == EntRefToEntIndex( g_iSphereShields[ iOwner ] ) && iOwnerTeam == iPassTeam ) {
		hReturn.Value = false;
		return MRES_ChangedOverride;
	}

	return MRES_Ignored;
}

//this is only ever called by sentry guns
MRESReturn Detour_ShouldHitEntitySentry( Address aTrace, DHookReturn hReturn, DHookParam hParams ) {
	//we only care about ignoring the shield so if we weren't going to hit it to begin with than ignore
	if( hReturn.Value == false )
		return MRES_Ignored;

	Address aLoad = LoadFromAddressOffset( aTrace, 20, NumberType_Int32 );
	if( aLoad == Address_Null )
		return MRES_Ignored;

	int iExcept = GetEntityFromAddress( aLoad );
	if( !IsValidPlayer( iExcept ) )
		return MRES_Ignored;

	int iTouched = GetEntityFromAddress( hParams.Get( 1 ) );
	int iOwner = GetEntPropEnt( iTouched, Prop_Send, "m_hOwnerEntity" );

	if( !IsValidPlayer( iOwner ) )
		return MRES_Ignored;

	int iShield = EntRefToEntIndex( g_iSphereShields[ iOwner ] );

	int iTouchTeam = GetEntProp( iTouched, Prop_Send, "m_iTeamNum" );
	int iShieldTeam = GetEntProp( iExcept, Prop_Send, "m_iTeamNum" );

	if( iTouched == iShield && iTouchTeam == iShieldTeam ) {
		hReturn.Value = false;
		return MRES_ChangedOverride;
	}

	return MRES_Ignored;
}