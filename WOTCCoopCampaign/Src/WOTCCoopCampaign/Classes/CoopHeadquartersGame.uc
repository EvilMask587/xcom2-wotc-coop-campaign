//---------------------------------------------------------------------------------------
//  FILE:    CoopHeadquartersGame.uc
//  PURPOSE: Replaces XComHeadquartersGame (ModClassOverrides; the Avenger map ignores
//           "?game="). Behaves like the original unless the co-op client is entering the
//           Avenger with a history received from the host (CoopSession.bEnterAsMirror).
//           A plain "open Avenger_Root" treats the history as a return from tactical
//           and runs post-mission processing (dock Skyranger, squad cleanup...), which
//           adds frames and ObjectIDs the host does not have. The client instead takes
//           the loaded-save path, minus FinishLoadGame (there is no save file).
//           Also swaps in CoopStrategyRuleset (baton rules for submitted frames).
//---------------------------------------------------------------------------------------
class CoopHeadquartersGame extends XComHeadquartersGame;

simulated function class<X2GameRuleset> GetGameRulesetClass()
{
	return class'CoopStrategyRuleset';
}

function StartMatch()
{
	if (!class'CoopSession'.default.bEnterAsMirror)
	{
		super.StartMatch();
		return;
	}

	super(XComGameInfo).StartMatch();
	InitEarth();
	PlayerController.ClientSetOnlineStatus();

	class'CoopSession'.default.bEnterAsMirror = false;
	`log("entering Avenger as mirror, frames=" $ `XCOMHISTORY.GetNumGameStates(),, 'CoopCampaign');
	m_kGameCore = Spawn(class'XGStrategy', self);
	m_kGameCore.OnLoadedGame();

	ModStartMatch();
}
