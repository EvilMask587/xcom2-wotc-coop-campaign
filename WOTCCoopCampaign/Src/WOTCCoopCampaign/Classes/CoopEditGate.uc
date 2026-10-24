//---------------------------------------------------------------------------------------
//  FILE:    CoopEditGate.uc
//  PURPOSE: Ties the baton to the screens where a player changes the campaign
//           (EditScreens in XComCoopCampaign.ini: research, building, armory, Geoscape...).
//           Opening such a screen without the baton requests it and covers the screen with
//           a "waiting for partner" dialog until the grant arrives; Cancel closes the
//           screen. The holder does not hand the baton over while one of its own edit
//           screens is open: the request waits until the last one closes.
//---------------------------------------------------------------------------------------
class CoopEditGate extends UIScreenListener config(CoopCampaign);

var config array<name> EditScreens;

var localized string m_strWaitTitle;
var localized string m_strWaitText;
var localized string m_strCancel;

static function bool IsEditScreen(UIScreen Screen)
{
	local name ClassName;

	foreach default.EditScreens(ClassName)
	{
		if (Screen.IsA(ClassName))
		{
			return true;
		}
	}
	return false;
}

// True while an edit screen other than Ignore is on the local screen stack.
static function bool IsEditing(optional UIScreen Ignore)
{
	local UIScreen Screen;

	if (`SCREENSTACK == none)
	{
		return false;
	}
	foreach `SCREENSTACK.Screens(Screen)
	{
		if (Screen != Ignore && IsEditScreen(Screen))
		{
			return true;
		}
	}
	return false;
}

event OnInit(UIScreen Screen)
{
	if (Screen.IsA('UIAvengerHUD'))
	{
		Screen.Spawn(class'CoopBatonPanel', Screen).InitBatonPanel();
		return;
	}
	if (!IsEditScreen(Screen) || !class'CoopSession'.static.IsConnected() || class'CoopSession'.default.bHasBaton)
	{
		return;
	}
	`log("edit screen" @ Screen.Class.Name @ "opened without baton",, 'CoopCampaign');
	class'CoopSession'.default.WaitingScreenClass = Screen.Class.Name;
	class'CoopSession'.static.RequestBaton();
	ShowWaitDialog(Screen);
}

event OnRemoved(UIScreen Screen)
{
	if (!IsEditScreen(Screen))
	{
		return;
	}
	if (class'CoopSession'.default.WaitingScreenClass == Screen.Class.Name)
	{
		class'CoopSession'.default.WaitingScreenClass = '';
	}
	if (class'CoopSession'.default.bGrantRequested && class'CoopSession'.default.bHasBaton && !IsEditing(Screen))
	{
		`log("last edit screen closed, handing over the requested baton",, 'CoopCampaign');
		class'CoopSession'.static.GrantBaton();
	}
}

function ShowWaitDialog(UIScreen Screen)
{
	local TProgressDialogData Data;

	Data.strTitle = default.m_strWaitTitle;
	Data.strDescription = default.m_strWaitText;
	Data.strAbortButtonText = default.m_strCancel;
	Data.fnCallback = OnWaitCancelled;
	Screen.Movie.Pres.UIProgressDialog(Data);
}

// Called by CoopSession once the baton arrives.
static function CloseWaitDialog()
{
	if (`PRESBASE != none && `PRESBASE.IsInState('State_ProgressDialog'))
	{
		`PRESBASE.UICloseProgressDialog();
	}
}

// The dialog pops itself before this runs; leave the edit screen too.
function OnWaitCancelled()
{
	local UIScreen Screen;

	`log("waiting for baton cancelled, closing" @ class'CoopSession'.default.WaitingScreenClass,, 'CoopCampaign');
	foreach `SCREENSTACK.Screens(Screen)
	{
		if (Screen.Class.Name == class'CoopSession'.default.WaitingScreenClass)
		{
			Screen.CloseScreen();
			return;
		}
	}
}

defaultproperties
{
	ScreenClass = none;
}
