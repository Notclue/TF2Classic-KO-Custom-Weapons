function GetTableValue( tTable, szKey, defaultVal, valuetype ) {
	if( szKey in tTable ) {
		local value = tTable.szKey
		return typeof value == valuetype ? value : defaultVal
	}
	return defaultVal
}

enum VSCF {
	None,
	LimitPerEnt			= 1 << 0, //if set each entity can apply their own instance of the condition
	NoTick				= 1 << 1,
	NegativeCond		= 1 << 2,
	KeepOnDeath			= 1 << 3,
	KeepOnResupply		= 1 << 4,
	KeepOnMedkit		= 1 << 5,
	CallDamageFunc		= 1 << 6, //enables calling the OwnerTakeDamage function 
}

aCondTickList <- []

function TickVSConds() {
	local flTime = Time()
	
	for( local ind = 0; ind < aCondTickList.len(); ind++ ) {
		local cond = aCondTickList[ind]
		if( cond == null ) {
			aCondTickList.Remove(ind)
			ind--
			continue
		}
		
		if( !cond.IsTimeToTick( flTime ) )
			continue
		
		if( !cond.Tick( flTime ) || cond.m_flRemoveTime <= flTime ) {
			RemoveVSCondInstance( cond )
			aCondTickList.Remove(ind)
			ind--
			continue
		}
		else {
			cond.m_flLastTickTime = flTime
		}
	}
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
	if( !cCondClass.IsValidTarget( hEntity ) )
		return

	local hSourceEnt = GetTableValue( tParams, "source", null, handle )
	local hSourceWeapon = GetTableValue( tParams, "weapon", null, handle )

	local aCondList = GetVSConds( hEntity, cCondClass )
	
	local flSetTime = GetTableValue( tParams, "settime", 0.0, float )
	local flAddTime = GetTableValue( tParams, "addtime", 0.0, float )
	local flMaxTime = GetTableValue( tParams, "maxtime", 9999.9, float )
	
	//one or more conds of this type already exist
	if( aCondList.len() != 0 ) {
		local cExistingCond = null
		
		//find the instance we want to modify, if multiple can exist find the one that belongs to this player
		if( cCondClass.m_eCondFlags & VSCF.LimitPerEnt ) {
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
			else
				cExistingCond.m_flRemoveTime = FLT_MAX
			
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
	
	if( flSetTime == 0.0 )
		cNewCond.m_flRemoveTime = FLT_MAX
	else
		cNewCond.m_flRemoveTime = Time() + flSetTime
		
	cNewCond.m_flAddTime = Time()
	
	cNewCond.OnAdd( tParams )
	
	local hEntityScope = hEntity.GetScriptScope()
	hEntityScope.aVSConds.append( cNewCond )
	
	if( !( cCondClass.m_eCondFlags & VSCF.NoTick ) )
		aCondTickList.append( cNewCond.weakref() )
}

function RemoveVSCond( hEntity, cCondClass, hFilterEnt = null ) {
	local hEntityScope = hEntity.GetScriptScope()
	
	for( local ind = 0; ind < hEntityScope.aVSConds.len(); ind++ ) {
		local cCondInst = hEntityScope.aVSConds[ind]
		if( cCondInst instanceof cCondClass ) {
			if( hFilterEnt == null || cCondInst.m_hSourceEnt == hFilterEnt ) {
				hEntityScope.aVSConds.remove(ind)
				ind--
			}
		}
	}
}

function RemoveVSCondInstance( cCondInstance ) {
	local hEntity = cCondInstance.m_hOwnerEnt
	local hEntityScope = hEntity.GetScriptScope()
	
	cCondInstance.OnRemove()
	
	local ind = hEntityScope.aVSConds.find( cCondInstance )
	hEntityScope.aVSConds.remove( ind )
}

class VSCond {
	static m_szDisplayName = "INVALID CONDITION"
	static m_eCondFlags = VSCF.None
	static m_szCondIconPath = ""
	
	m_flTickInterval = 1.0
	
	m_hOwnerEnt = null
	m_hSourceEnt = null
	m_hSourceWeapon = null
	
	m_flAddTime = 0.0
	m_flRemoveTime = 0.0
	m_flLastTickTime = 0.0
	
	function IsValidTarget( hTarget, tParams ) { return hTarget.IsPlayer() }
	
	function IsTimeToTick( flTime ) { return ( flTime >= m_flLastTickTime + m_flTickInterval ) }
	
	function OnAdd( tParams ) {}
	function OnUpdate( tParams ) {}
	function OnRemove() {} //todo: may need to pass new handle if called from OnDestroy
	function Tick( flTime ) {} //return false to remove the condition
	
	function OwnerTakeDamage( tParams ) {}
}

class VSCondToxin extends VSCond {
	static m_szDisplayName = "Toxin"
	static m_eCondFlags = VSCF.NegativeCond
	
	static m_flHealRateMult = 0.5
	static m_flDamageAmount = 2.0
	
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
		if( !m_hOwnerEnt.IsValid() )
			return false
			
		m_hOwnerEnt.TakeDamageEx( m_hSourceEnt, m_hSourceEnt, m_hSourceWeapon, Vector(0,0,0), m_hOwnerEnt.GetOrigin(), m_flDamageAmount, FDmgType.DMG_PHYSGUN )
			
		return true
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

class VSCondAngelBubble extends VSCond {
	static m_szDisplayName = "Angel Shield"
	static m_eCondFlags = VSCF.KeepOnMedkit | VSCF.KeepOnResupply | VSCF.CallDamageFunc
	
	static m_flBubbleDuration = 8.0
	static m_flBubbleMaxHealth = 80.0
	
	m_flTickInterval = 0.0
	m_flBubbleHealth = m_flBubbleMaxHealth
	
	function OnAdd( tParams ) {
		m_flBubbleHealth = m_flBubbleMaxHealth
		//m_hOwnerEnt.EmitSound(  )
		//remove negative conds
		//SetScriptOverlayMaterial()
	}
	
	function OwnerTakeDamage( tParams ) {
		tParams.damage_for_force_calc = tParams.damage
		
		m_flBubbleHealth -= tParams.damage
		tParams.damage = 0.0
		if( m_flBubbleHealth <= 0.0 ) {
			return false
		}
		
		return true
	}
	
	function OnRemove() {
		//particle things
		//m_hOwnerEnt.EmitSound(  )
	}
}