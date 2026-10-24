//---------------------------------------------------------------------------------------
//  FILE:    CoopStrategyRuleset.uc
//  PURPOSE: Strategy ruleset used by CoopHeadquartersGame. While connected, a player who
//           does not hold the baton must not create game state objects: the new object
//           takes the next ObjectID, which the baton holder does not know about and hands
//           out again; its merge state then silently replaces the local object (seen in
//           test "client-local-alloc"). Such frames are rejected here. Frames that only
//           change existing objects (UI bookkeeping: alert seen, entered facility...) pass;
//           the baton holder's merges overwrite them.
//---------------------------------------------------------------------------------------
class CoopStrategyRuleset extends X2StrategyGameRuleset;

simulated function bool SubmitGameStates(array<XComGameState> NewStates)
{
	local XComGameState NewState;
	local int NewObjectID;

	if (class'CoopSession'.static.IsConnected() && !class'CoopSession'.default.bHasBaton && !class'CoopSession'.default.bApplyingRemote)
	{
		foreach NewStates(NewState)
		{
			NewObjectID = FindNewObject(NewState);
			if (NewObjectID != 0)
			{
				`log("blocked frame without baton (creates object " $ NewObjectID $ "):" @ NewState.GetContext().SummaryString(),, 'CoopCampaign');
				foreach NewStates(NewState)
				{
					CachedHistory.CleanupPendingGameState(NewState);
				}
				return false;
			}
		}
	}
	return super.SubmitGameStates(NewStates);
}

event PostBeginPlay()
{
	super.PostBeginPlay();
	`log("strategy ruleset active",, 'CoopCampaign');
}

// ObjectID of the first object created in this state, or 0. A created object has no
// previous version (the history already resolves the pending state's new IDs, so
// GetGameStateForObjectID cannot tell new objects apart).
simulated function int FindNewObject(XComGameState NewState)
{
	local XComGameState_BaseObject StateObject;

	foreach NewState.IterateByClassType(class'XComGameState_BaseObject', StateObject)
	{
		if (StateObject.GetPreviousVersion() == none)
		{
			return StateObject.ObjectID;
		}
	}
	return 0;
}
