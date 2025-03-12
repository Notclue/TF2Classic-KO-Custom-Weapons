function Min( a, b ) {
	return ( a < b ) ? a : b
}
function Max( a, b ) {
	return ( a > b ) ? a : b
}

function Clamp( val, a, b ) {
	return Min( Max( val, a ), b )
}

function GetTableValue( tTable, szKey, defaultVal, valuetype ) {
	if( szKey in tTable ) {
		local value = tTable.szKey
		return typeof value == valuetype ? value : defaultVal
	}
	return defaultVal
}

enum Flags {
	None,
	LimitPerPlayer		= 1 << 0, //if set each player can apply their own instance of the condition
	Tick				= 1 << 1,
	NegativeCond		= 1 << 2,
	RemoveOnDeath		= 1 << 3,
	RemoveOnResupply	= 1 << 4,
	RemoveOnMedkit		= 1 << 5,
	AllowOnPlayers		= 1 << 6,
	AllowOnBuildings	= 1 << 7,
	AllowOnMedkits		= 1 << 8
}

aCondTickList <- []

function TickVSConds() {
	local flTime = Time()
	local bRemove = false
	foreach( ind, cond in aCondTickList ) {
		if( !cond ) {
			bRemove = true
			continue
		}
			
		if( !( cond.m_eCondFlags & Flags.Tick && cond.IsTimeToTick( flTime ) ) )
			continue
		
		if( !cond.Tick( flTime ) ) {
			cond.RemoveSelf()
			aCondTickList[ind] = null
			bRemove = true
		}
		else {
			cond.m_flLastTickTime = flTime
		}
	}
	
	if( bRemove )
		aCondTickList.filter( function( ind, cond ) { return cond != null } )
}

//returns array of all conds of provided type
function GetVSConds( hEntity, cCondClass, hFilterEnt = null ) {
	if( hFilterEnt )
		return hEntity.GetScriptScope().aVSConds.filter( function( ind, cond ) { return ( cond instanceof cCondClass ) && cond.hSourceEnt == hFilterEnt } )
	else
		return hEntity.GetScriptScope().aVSConds.filter( function( ind, cond ) { return cond instanceof cCondClass } )
}

function HasVSCond( hEntity, cCondClass ) {
	return GetVSConds( hEntity, cCondClass ).len() > 0
}

function AddVSCond( hEntity, cCondClass, tParams ) {
	local hSourceEnt = GetTableValue( tParams, "source", null, handle )
	if( !hSourceEnt.IsValid() )
		hSourceEnt == null
	
	local hSourceWeapon = GetTableValue( tParams, "weapon", null, handle )
	if( !hSourceWeapon.IsValid() )
		hSourceWeapon == null
	
	local aCondList = GetVSConds( hEntity, cCondClass )
	
	local flSetTime = GetTableValue( tParams, "settime", 0.0, float )
	local flAddTime = GetTableValue( tParams, "addtime", 0.0, float )
	local flMaxTime = GetTableValue( tParams, "maxtime", 9999.9, float )
	
	//one or more conds of this type already exist
	if( aCondList.len() != 0 ) {
		local cExistingCond = null
		
		//find the instance we want to modify, if multiple can exist find the one that belongs to this player
		if( cCondClass.m_eCondFlags & Flags.LimitPerPlayer ) {
			foreach( ind, cond in aCondList ) {
				if( cond.hSourceEnt == hSourceEnt ) {
					cExistingCond = cond
					break
				}
			}
		} 
		else {
			cExistingCond = aCondList[0]
		}
			
		//edit the existing instance
		if( cExistingCond != null ) {
			//tParams <- {  } //set old values here if it ever becomes necessary
			
			if( flAddTime != 0.0 )
				cExistingCond.m_flRemoveTime = Min( cExistingCond.m_flRemoveTime + flAddTime, cExistingCond.m_flRemoveTime + flMaxTime )
			else if( flSetTime != 0.0 )
				cExistingCond.m_flRemoveTime = Time() + flSetTime
			
			if( hSourceEnt ) cExistingCond.m_hSourceEnt = hSourceEnt
			if( hSourceWeapon ) cExistingCond.m_hSourceWeapon = hSourceWeapon
			
			cExistingCond.OnUpdate( tParams )
			
			return
		}
	}
		
	//create a new instance
	local cNewCond = cCondClass.instance()
	
	cNewCond.m_hOwnerEnt = hEntity
	cNewCond.m_hSourceEnt = hSourceEnt
	cNewCond.m_hSourceWeapon = hSourceWeapon
	
	cNewCond.m_flRemoveTime = Time() + flSetTime
	
	cNewCond.OnAdd( tParams )
	
	local hEntityScope = hEntity.GetScriptScope()
	hEntityScope.aVSConds.append( cNewCond )
	aCondTickList.append( cNewCond.weakref() )
}

function RemoveVSCond( hEntity, cCondClass, hFilterPlayer = null ) {
	local hEntityScope = hEntity.GetScriptScope()
	
	//todo: factor filterplayer
	foreach( ind, cond in hEntityScope.aVSConds ) {
		if( !(cond instanceof cCondClass) )
			continue
	
		cond.OnRemove()
		hEntityScope.aVSConds[ind] = null
	}
	
	hEntityScope.aVSConds.filter( function( ind, cond ) { return cond != null } )
}

class VSCond {
	static m_szDisplayName = "INVALID CONDITION"
	static m_eCondFlags = VSCond.None
	
	m_flTickInterval = 1.0
	
	m_hOwnerEnt = null
	m_hSourceEnt = null
	m_hSourceWeapon = null
	
	m_flRemoveTime = 0.0
	m_flLastTickTime = 0.0
	
	function IsTimeToTick( flTime ) {
		return ( flTime >= m_flLastTickTime + m_flTickInterval )
	}
	
	function OnAdd( tParams ) {}
	function OnUpdate( tParams ) {}
	function OnRemove() {} //todo: may need to pass new handle if called from OnDestroy
	function Tick( flTime ) {} //return false to remove the condition
	
	//todo: write this
	function RemoveSelf() {}
}

class VSCondToxin extends VSCond {
	static m_szDisplayName = "Toxin"
	static m_eCondFlags = Flags.Tick | Flags.NegativeCond | Flags.RemoveOnDeath | Flags.RemoveOnResupply | Flags.RemoveOnMedkit | Flags.AllowOnPlayers
	
	static m_flHealRateMult = 0.5
	static m_iDamageAmount = 2
	
	m_flTickInterval = 0.5
	
	m_hParticleEmitter = null
	
	function OnAdd( tParams ) {
		m_hParticleEmitter = SpawnEntityFromTable( "info_particle_system", {
			effect_name = "toxin_particle"
			start_active = true
		})
		
		m_hParticleEmitter.AcceptInput( "SetParent", "!activator", m_hOwnerEnt, null )
		m_hOwnerEnt.AddCustomAttribute( "healing received penalty", m_flHealRateMult, -1 )
		m_hOwnerEnt.EmitSound( "Powerup.PickUpPlagueInfectedLoop" )
	}
	
	function Tick( flTime ) {
	
	}
	
	function OnRemove() {
		if( m_hParticleEmitter.IsValid() ) {
			m_hParticleEmitter.Destroy()
		}
		if( m_hOwnerEnt.IsValid() ) {
			m_hOwnerEnt.RemoveCustomAttribute( "healing received penalty" )
			m_hOwnerEnt.StopSound( "Powerup.PickUpPlagueInfectedLoop" )
		}
	}
}