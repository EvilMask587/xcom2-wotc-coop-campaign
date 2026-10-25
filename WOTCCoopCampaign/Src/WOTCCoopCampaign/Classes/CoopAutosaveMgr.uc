//---------------------------------------------------------------------------------------
//  FILE:    CoopAutosaveMgr.uc
//  PURPOSE: Replaces XComAutosaveMgr (ModClassOverrides). Only the host saves the shared
//           campaign: on the co-op client autosaves and quicksaves do nothing.
//           A client that sent a merge state while it was saving crashed in a worker thread
//           ("FWriteHistoryObjects", XCom2.exe+0x4ce235 reading null+0xe0), reproduced in tests
//           "autosave-burst" and "client-send-then-save"; the host did not crash in the same
//           pattern. Its saves would not be loadable as the shared campaign anyway.
//---------------------------------------------------------------------------------------
class CoopAutosaveMgr extends XComAutosaveMgr;

static function bool IsCoopClient()
{
	return `XCOMNETMANAGER.HasClientConnection();
}

function bool AutosaveEnabled(bool bIsIronman)
{
	if (IsCoopClient())
	{
		`log("autosave skipped: co-op client (the host saves the campaign)",, 'CoopCampaign');
		return false;
	}
	return super.AutosaveEnabled(bIsIronman);
}

function DoQuicksave(delegate<XComOnlineEventMgr.WriteSaveGameComplete> QuicksaveCompleteCallback = none)
{
	if (IsCoopClient())
	{
		`log("quicksave skipped: co-op client (the host saves the campaign)",, 'CoopCampaign');
		if (QuicksaveCompleteCallback != none)
		{
			QuicksaveCompleteCallback(false);
		}
		return;
	}
	super.DoQuicksave(QuicksaveCompleteCallback);
}
