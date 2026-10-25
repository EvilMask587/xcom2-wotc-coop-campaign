//---------------------------------------------------------------------------------------
//  FILE:    CoopSaveGate.uc
//  PURPOSE: Manual saves on the co-op client, the counterpart of CoopAutosaveMgr: the pause
//           menu's Save item is disabled with a reason, and a save screen that opens anyway
//           (a disabled list item still reports clicks) is closed at once.
//---------------------------------------------------------------------------------------
class CoopSaveGate extends UIScreenListener;

var localized string m_strHostSaves;

event OnInit(UIScreen Screen)
{
	local UIPauseMenu Menu;
	local UIListItemString SaveItem;

	if (!class'CoopAutosaveMgr'.static.IsCoopClient())
	{
		return;
	}
	Menu = UIPauseMenu(Screen);
	if (Menu != none && Menu.m_optSave >= 0)
	{
		SaveItem = UIListItemString(Menu.List.GetItem(Menu.m_optSave));
		if (SaveItem != none)
		{
			SaveItem.DisableListItem(m_strHostSaves);
			`log("pause menu: save disabled on co-op client",, 'CoopCampaign');
		}
	}
	else if (Screen.IsA('UISaveGame'))
	{
		`log("save screen closed: co-op client (the host saves the campaign)",, 'CoopCampaign');
		Screen.CloseScreen();
	}
}
