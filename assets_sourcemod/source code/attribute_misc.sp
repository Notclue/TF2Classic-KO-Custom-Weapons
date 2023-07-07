#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>

public Plugin myinfo =
{
	name = "Attribute: Misc",
	author = "Noclue",
	description = "Miscellaneous attributes.",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

DynamicHook hPrimaryFire;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hPrimaryFire = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::PrimaryAttack" );

	delete hGameConf;
}

public void OnEntityCreated( int iEntity ) {
	static char szEntityName[ 32 ];
	GetEntityClassname( iEntity, szEntityName, sizeof( szEntityName ) );
	if( StrContains( szEntityName, "tf_weapon_shotgun", false ) == 0 )
		hPrimaryFire.HookEntity( Hook_Pre, iEntity, Hook_PrimaryFire );
}

public void OnTakeDamageAlivePostTF( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	CheckLifesteal( iTarget, tfInfo );
}

public void OnTakeDamageBuilding( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	CheckLifesteal( iTarget, tfInfo );
}

float g_flHurtMe[ MAXPLAYERS+1 ];

void CheckLifesteal( int iTarget, TFDamageInfo tfInfo ) {
	int iAttacker = tfInfo.iAttacker;

	if( !IsValidPlayer( iAttacker ) )
		return;

	int iWeapon = tfInfo.iWeapon;
	float flMult = AttribHookFloat( 0.0, iWeapon, "custom_lifesteal" );
	if( flMult == 0.0 )
		return;

	float flAmount = tfInfo.flDamage * flMult;

	float flHurtAmount = AttribHookFloat( 0.0, iWeapon, "custom_hurt_on_fire" );
	if( flHurtAmount > 0.0  ) {
		//if( g_flHurtMe[ iAttacker ] == 0.0 )
			//g_flHurtMe[ iAttacker ] = flHurtAmount;

		g_flHurtMe[ iAttacker ] -= flAmount;
	}
	
	if( flHurtAmount > 0.0 || g_flHurtMe[ iAttacker ] < 0 ) {
		int iGave = HealPlayer( iAttacker, flAmount, iAttacker, HF_NOCRITHEAL | HF_NOOVERHEAL );

		Event eHealEvent = CreateEvent( "player_healonhit" );
		eHealEvent.SetInt( "entindex", iAttacker );
		eHealEvent.SetInt( "amount", iGave );
		eHealEvent.FireToClient( iAttacker );
		delete eHealEvent;
	}
}

MRESReturn Hook_PrimaryFire( int iEntity ) {
	if( GetEntPropFloat( iEntity, Prop_Send, "m_flNextPrimaryAttack" ) > GetGameTime() ) {
		return MRES_Ignored;
	}

	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;

	float flValue = AttribHookFloat( 0.0, iEntity, "custom_hurt_on_fire" );
	if( flValue == 0.0 )
		return MRES_Ignored;

	//hack for lifesteal
	g_flHurtMe[ iOwner ] = flValue;
	RequestFrame( HurtPlayerDelay, iOwner );

	return MRES_Handled;
}

void HurtPlayerDelay( int iPlayer ) {
	if( !IsPlayerAlive( iPlayer ) )
		return;

	float flAmount = MaxFloat( 0.0, g_flHurtMe[ iPlayer ] );
	SDKHooks_TakeDamage( iPlayer, iPlayer, iPlayer, flAmount );
	
	Event eHealEvent = CreateEvent( "player_healonhit" );
	eHealEvent.SetInt( "entindex", iPlayer );
	eHealEvent.SetInt( "amount", -RoundToFloor( flAmount ) );
	eHealEvent.FireToClient( iPlayer );
	delete eHealEvent;

	g_flHurtMe[ iPlayer ] = 0.0;
}