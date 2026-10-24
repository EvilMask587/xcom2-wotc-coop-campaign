//---------------------------------------------------------------------------------------
//  FILE:    CoopSession.uc
//  PURPOSE: Co-op state shared by both players for the whole game session.
//           Strategy sync, first version: the player holding the baton is the authority;
//           every frame it adds to the history is sent to the partner as a merge game
//           state, followed by a "CoopFrame" fingerprint (resources, counts, last
//           ObjectIDs) so the receiver can detect divergence. The baton moves on request
//           (see BatonEpoch).
//           A plain Object kept alive by the network manager's and history's delegate
//           arrays (delegates bound to Actors would leak the World across map loads).
//---------------------------------------------------------------------------------------
class CoopSession extends Object config(CoopCampaign);

var config bool bInited;       // config only so the default may be written; never saved
var config bool bHasBaton;
var config bool bApplyingRemote;
var config int LocalFramesWithoutBaton;
var config bool bEnterAsMirror; // read by CoopHeadquartersGame on the next Avenger load
var config int LastHandledFrame; // history hooks are re-added every map; a frame is handled once

// Baton handoff: the holder answers "CoopBatonRequest" by dropping the baton and sending
// "CoopBatonGrant" (epoch, fingerprint, highest ObjectID). Commands overtake merge states,
// so the receiver takes the baton only when its fingerprint and highest ObjectID have caught
// up with the grant and no remote frame arrived for GrantQuietSeconds; otherwise it could
// create objects before it knows the holder's last ObjectIDs. Counting merge states does
// not work: frames from one tick may arrive as one merge, so commands and merges differ in
// number. While the grant is in flight neither side holds the baton.
var config int BatonEpoch;
var config bool bGrantPending;
var config string GrantFp;
var config int GrantMaxID;
var config float LastRemoteFrameTime;
const GrantQuietSeconds = 1.0;

var config bool bGrantRequested;     // partner asked while an edit screen was open here (CoopEditGate)
var config bool bRequestSent;        // we asked and have not received the baton yet
var config bool bRequestQueued;      // the holder answered "CoopBatonDeferred": it hands over after its edit screen
var config float RequestTime;
const RequestTimeoutSeconds = 10.0;  // no answer at all: let the player ask again
var config name WaitingScreenClass;  // edit screen waiting for the baton behind the wait dialog

// The "CoopFrame" command is handled before the merge state sent ahead of it, so the
// remote fingerprint waits here until the merge state has been applied.
var array<string> PendingRemoteFps;

static function Init()
{
	local CoopSession Session;
	local XComGameStateNetworkManager NetMgr;

	if (default.bInited)
	{
		return;
	}
	default.bInited = true;
	Session = new class'CoopSession';
	NetMgr = `XCOMNETMANAGER;
	NetMgr.AddReceiveMergeGameStateDelegate(Session.OnReceiveMergeGameState);
	NetMgr.AddReceiveRemoteCommandDelegate(Session.OnRemoteCommand);
	`log("session ready",, 'CoopCampaign');
}

// ResetHistory (new campaign, loading a save) drops the history's delegates, so this is
// called on every map. A duplicate hook is harmless: OnNewGameState handles a frame once.
static function HookHistory()
{
	local CoopSession Hook;

	Hook = new class'CoopSession';
	`XCOMHISTORY.RegisterOnNewGameStateDelegate(Hook.OnNewGameState);
	default.LastHandledFrame = `XCOMHISTORY.GetNumGameStates() - 1; // indices restart after a reset
}

static function SetBaton(bool bHolder)
{
	default.bHasBaton = bHolder;
	`log("baton=" $ (bHolder ? "mine" : "partner"),, 'CoopCampaign');
	if (bHolder)
	{
		default.bRequestSent = false;
		default.bRequestQueued = false;
		class'CoopEditGate'.static.CloseWaitDialog();
	}
}

// Called by CoopBatonPanel's refresh timer.
static function CheckRequestTimeout()
{
	if (default.bRequestSent && !default.bRequestQueued && !default.bGrantPending
		&& Now() - default.RequestTime > RequestTimeoutSeconds)
	{
		default.bRequestSent = false;
		`log("baton request: no answer, may ask again",, 'CoopCampaign');
	}
}

static function RequestBaton()
{
	local array<byte> Params;

	if (default.bHasBaton)
	{
		`log("baton request: already mine",, 'CoopCampaign');
		return;
	}
	if (default.bRequestSent)
	{
		`log("baton request: already sent",, 'CoopCampaign');
		return;
	}
	default.bRequestSent = true;
	default.bRequestQueued = false;
	default.RequestTime = Now();
	Params.Length = 0; // no parameters
	`XCOMNETMANAGER.SendRemoteCommand("CoopBatonRequest", Params);
	`log("baton requested",, 'CoopCampaign');
}

static function GrantBaton()
{
	local array<byte> Params;

	SetBaton(false);
	default.bGrantRequested = false;
	default.BatonEpoch++;
	class'XComGameStateNetworkManager'.static.AddCommandParam_Int(default.BatonEpoch, Params);
	class'XComGameStateNetworkManager'.static.AddCommandParam_String(Fingerprint(), Params);
	class'XComGameStateNetworkManager'.static.AddCommandParam_Int(MaxObjectID(), Params);
	`XCOMNETMANAGER.SendRemoteCommand("CoopBatonGrant", Params);
	`log("baton granted epoch=" $ default.BatonEpoch @ "fp=" $ Fingerprint() @ "maxID=" $ MaxObjectID(),, 'CoopCampaign');
}

// Highest ObjectID in the history. Unlike History.GetNextObjectID() it allocates nothing.
static function int MaxObjectID()
{
	local XComGameState_BaseObject StateObject;
	local int MaxID;

	foreach `XCOMHISTORY.IterateByClassType(class'XComGameState_BaseObject', StateObject)
	{
		MaxID = Max(MaxID, StateObject.ObjectID);
	}
	return MaxID;
}

static function float Now()
{
	return class'WorldInfo'.static.GetWorldInfo().TimeSeconds;
}

// Takes a received grant once the holder's frames sent before it have been applied.
// Retried on every merge state and by a timer while waiting for the quiet period.
function TryAcceptGrant()
{
	local array<byte> Params;
	local string LocalFp;
	local int LocalMaxID;
	local float Quiet;

	if (!default.bGrantPending)
	{
		return;
	}
	LocalFp = Fingerprint();
	LocalMaxID = MaxObjectID();
	if (LocalFp != default.GrantFp || LocalMaxID < default.GrantMaxID)
	{
		`log("baton grant waiting: local=" $ LocalFp @ "maxID=" $ LocalMaxID @ "grant=" $ default.GrantFp @ "maxID=" $ default.GrantMaxID,, 'CoopCampaign');
		return;
	}
	Quiet = Now() - default.LastRemoteFrameTime;
	if (Quiet < GrantQuietSeconds)
	{
		`log("baton grant caught up, waiting for quiet:" @ Quiet,, 'CoopCampaign');
		class'CoopGrantRetry'.static.Schedule(self, GrantQuietSeconds - Quiet + 0.05f);
		return;
	}
	default.bGrantPending = false;
	SetBaton(true);
	class'XComGameStateNetworkManager'.static.AddCommandParam_Int(default.BatonEpoch, Params);
	`XCOMNETMANAGER.SendRemoteCommand("CoopBatonAck", Params);
}

static function bool IsConnected()
{
	return `XCOMNETMANAGER.HasServerConnection() || `XCOMNETMANAGER.HasClientConnection();
}

function OnNewGameState(XComGameState NewGameState)
{
	local XComGameStateHistory History;
	local array<byte> Params;

	if (NewGameState.HistoryIndex <= default.LastHandledFrame && NewGameState.HistoryIndex > 0)
	{
		return;
	}
	default.LastHandledFrame = NewGameState.HistoryIndex;
	if (default.bApplyingRemote || !IsConnected())
	{
		return;
	}
	History = `XCOMHISTORY;
	if (!default.bHasBaton)
	{
		default.LocalFramesWithoutBaton++;
		`log("local frame without baton:" @ NewGameState.GetContext().SummaryString()
			@ "total=" $ default.LocalFramesWithoutBaton,, 'CoopCampaign');
		return;
	}
	if (History.GetStartState() != none)
	{
		return; // still building a start state (tactical/strategy start), not a normal frame
	}
	if (NewGameState.GetNumGameStateObjects() == 0)
	{
		// e.g. "Entered Facility": SendMergeGameState refuses it ("GameState has 0 Objects"),
		// so no fingerprint either, or commands and merge states stop pairing up
		return;
	}

	`XCOMNETMANAGER.SendMergeGameState(NewGameState);
	class'XComGameStateNetworkManager'.static.AddCommandParam_String(Fingerprint(), Params);
	`XCOMNETMANAGER.SendRemoteCommand("CoopFrame", Params);
	`log("sent frame" @ (History.GetNumGameStates() - 1) $ ":" @ NewGameState.GetContext().SummaryString(),, 'CoopCampaign');
}

function OnReceiveMergeGameState(XComGameState InGameState)
{
	local string RemoteFp, LocalFp;

	default.LastRemoteFrameTime = Now();
	RefreshAvenger(InGameState);
	LocalFp = Fingerprint();
	`log("received merge state, frames now=" $ `XCOMHISTORY.GetNumGameStates()
		@ "objects=" $ InGameState.GetNumGameStateObjects() @ "fp=" $ LocalFp,, 'CoopCampaign');
	if (PendingRemoteFps.Length > 0)
	{
		// several frames sent in one tick can arrive as one merge state; the newest fingerprint covers them all
		RemoteFp = PendingRemoteFps[PendingRemoteFps.Length - 1];
		PendingRemoteFps.Length = 0;
		`log((RemoteFp == LocalFp ? "in sync" : "DESYNC") @ "remote=" $ RemoteFp @ "local=" $ LocalFp,, 'CoopCampaign');
	}
	TryAcceptGrant();
}

function OnRemoteCommand(string Command, array<byte> RawParams)
{
	local int Epoch;
	local array<byte> Params;

	Params.Length = 0; // replies below carry no parameters

	if (Command == "CoopFrame")
	{
		default.LastRemoteFrameTime = Now();
		PendingRemoteFps.AddItem(class'XComGameStateNetworkManager'.static.GetCommandParam_String(RawParams));
	}
	else if (Command == "CoopBatonRequest")
	{
		if (default.bHasBaton && class'CoopEditGate'.static.IsEditing())
		{
			default.bGrantRequested = true; // granted by CoopEditGate when the last edit screen closes
			`XCOMNETMANAGER.SendRemoteCommand("CoopBatonDeferred", Params);
			`log("baton request deferred: edit screen open",, 'CoopCampaign');
		}
		else if (default.bHasBaton)
		{
			GrantBaton();
		}
		else
		{
			// crossed a grant in flight, or both sides think the other holds it
			`XCOMNETMANAGER.SendRemoteCommand("CoopBatonNotMine", Params);
			`log("baton request ignored: not mine",, 'CoopCampaign');
		}
	}
	else if (Command == "CoopBatonGrant")
	{
		Epoch = class'XComGameStateNetworkManager'.static.GetCommandParam_Int(RawParams);
		default.GrantFp = class'XComGameStateNetworkManager'.static.GetCommandParam_String(RawParams);
		default.GrantMaxID = class'XComGameStateNetworkManager'.static.GetCommandParam_Int(RawParams);
		default.BatonEpoch = Epoch;
		default.bGrantPending = true;
		`log("baton grant received epoch=" $ Epoch @ "fp=" $ default.GrantFp @ "maxID=" $ default.GrantMaxID,, 'CoopCampaign');
		TryAcceptGrant();
	}
	else if (Command == "CoopBatonDeferred")
	{
		default.bRequestQueued = true;
		`log("baton request queued by partner",, 'CoopCampaign');
	}
	else if (Command == "CoopBatonNotMine")
	{
		default.bRequestSent = false;
		`log("baton request answered: partner does not hold it",, 'CoopCampaign');
	}
	else if (Command == "CoopBatonAck")
	{
		`log("baton ack epoch=" $ class'XComGameStateNetworkManager'.static.GetCommandParam_Int(RawParams),, 'CoopCampaign');
	}
}

// A merge state changes the history but not what is already on screen. Rooms whose
// streamed map no longer matches their state are swapped, then the resource bar and the
// facility grid are rebuilt. The swap copies XGBase.QueueRoomSwap (private), the path a
// finished construction takes: the old map is removed only once the new one has loaded.
// RemoveRoom + StreamInRoom, as the GiveFacility cheat does, often left a hole in the room.
static function RefreshAvenger(XComGameState InGameState)
{
	local XGBase Base;
	local XComHQPresentationLayer HQPres;
	local XComGameState_HeadquartersRoom Room;
	local QueuedRoomSwapInfo SwapInfo;
	local string Wanted, Loaded;

	if (XComHeadquartersGame(class'Engine'.static.GetCurrentWorldInfo().Game) == none)
	{
		return; // not in the strategy layer
	}
	Base = `GAME.GetGeoscape().m_kBase;
	foreach InGameState.IterateByClassType(class'XComGameState_HeadquartersRoom', Room)
	{
		Room = XComGameState_HeadquartersRoom(`XCOMHISTORY.GetGameStateForObjectID(Room.ObjectID));
		Wanted = class'XGBase'.static.GetMapname(Room);
		Loaded = Base.m_arrLvlStreaming[Room.MapIndex] != none ? string(Base.m_arrLvlStreaming[Room.MapIndex].PackageName) : "";
		if (Loaded ~= Wanted)
		{
			continue;
		}
		`log("room" @ Room.MapIndex @ "swap" @ Loaded @ "->" @ Wanted,, 'CoopCampaign');
		if (Loaded != "")
		{
			SwapInfo.RoomIndex = Room.MapIndex;
			SwapInfo.RoomOffset = class'XGBase'.static.GetRoomLocation(Base, Room.MapIndex);
			SwapInfo.RoomToRemove = Loaded;
			SwapInfo.RoomBeingAdded = name(Wanted);
			Base.m_queuedRoomSwaps.AddItem(SwapInfo);
		}
		Base.StreamInRoom(Room.MapIndex, true);
	}

	HQPres = `HQPRES;
	if (HQPres != none)
	{
		if (HQPres.m_kAvengerHUD != none)
		{
			HQPres.m_kAvengerHUD.UpdateResources();
		}
		if (HQPres.m_kFacilityGrid != none)
		{
			HQPres.m_kFacilityGrid.UpdateData();
		}
	}
}

// Summary of the strategy state both players must agree on. Deliberately avoids
// History.GetNextObjectID(): that call allocates an ID, so reading it changes the state.
static function string Fingerprint()
{
	local XComGameState_HeadquartersXCom XComHQ;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom', true));
	if (XComHQ == none)
	{
		return "nohq";
	}
	// the last ObjectIDs show whether objects created on one side got the same IDs on the other
	return "sup" $ XComHQ.GetSupplies() $ ".int" $ XComHQ.GetIntel() $ ".all" $ XComHQ.GetAlienAlloys()
		$ ".ele" $ XComHQ.GetEleriumDust() $ ".crew" $ XComHQ.Crew.Length $ "#" $ LastID(XComHQ.Crew)
		$ ".fac" $ XComHQ.Facilities.Length $ "#" $ LastID(XComHQ.Facilities)
		$ ".tech" $ XComHQ.TechsResearched.Length $ "#" $ LastID(XComHQ.TechsResearched)
		$ ".squad" $ XComHQ.Squad.Length;
}

static function int LastID(const out array<StateObjectReference> Refs)
{
	if (Refs.Length == 0)
	{
		return 0;
	}
	return Refs[Refs.Length - 1].ObjectID;
}
