//---------------------------------------------------------------------------------------
//  FILE:    CoopSession.uc
//  PURPOSE: Co-op state shared by both players for the whole game session.
//           Strategy sync, first version: the player holding the baton is the authority;
//           the frames it adds to the history are sent to the partner in batches as merge
//           game states, each announced by "CoopAlign" with a fingerprint (resources, counts,
//           last ObjectIDs) so the receiver can detect divergence. The baton moves on request
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
var config bool bMirrorClient;  // entered the campaign from the host's history (the client side)
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

var config array<int> BatchObjects;    // ObjectIDs touched since the last flush (OnNewGameState)
var config int BatchFrames;
var config bool bFlushScheduled;
var config bool bGrantAfterFlush;     // a grant waits for a save to finish (GrantBaton)
const BatchDelaySeconds = 0.2;

var config int AlignTarget;          // frame the next merge should land in (AlignHistory)

// One merge state in flight at a time: the receiver answers each one with "CoopMergeAck".
// Two batches sent 0.23 s apart arrived as one merge callback (test "projects" in the suite:
// two "CoopAlign" handled, one merge received; the first batch's object was lost). Frames
// made meanwhile wait in the next batch; a merge not acknowledged in time is sent again.
var config bool bMergeInFlight;
var config float MergeSentTime;
var config array<int> InFlightObjects;
const MergeAckTimeoutSeconds = 5.0;

var config bool bGrantRequested;     // partner asked while an edit screen was open here (CoopEditGate)
var config bool bRequestSent;        // we asked and have not received the baton yet
var config bool bRequestQueued;      // the holder answered "CoopBatonDeferred": it hands over after its edit screen
var config float RequestTime;
const RequestTimeoutSeconds = 10.0;  // no answer at all: let the player ask again
var config name WaitingScreenClass;  // edit screen waiting for the baton behind the wait dialog

// The sender's fingerprint for the next merge, carried by "CoopAlign" (handled before the
// merge sent after it) and compared when that merge has been applied. Not a queue: a lost
// merge must not shift the comparison of every later one.
var string ExpectedRemoteFp;

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
	NetMgr.AddNotifyConnectionClosedDelegate(Session.OnConnectionClosed);
	`log("session ready",, 'CoopCampaign');
}

// The partner is gone (quit, crash, lost connection; seen about 3 s after its process was
// killed, test "rejoin-explore"). Everything in flight between the two is dropped. The host
// takes the baton back: a client that died holding it left nobody able to change the
// campaign, and the host's own changes were not sent after the client came back
// (supplies 4005 on the host, 4000 on the rejoined client). The client rejoins by
// receiving the whole history again.
function OnConnectionClosed(int ConnectionIdx)
{
	default.bGrantPending = false;
	default.bGrantRequested = false;
	default.bGrantAfterFlush = false;
	default.bMergeInFlight = false;
	default.InFlightObjects.Length = 0;
	default.BatchObjects.Length = 0;
	default.BatchFrames = 0;
	ExpectedRemoteFp = "";
	if (default.bMirrorClient)
	{
		`log("connection closed: the host left; this copy of the campaign is no longer shared",, 'CoopCampaign');
		SetBaton(false);
		return;
	}
	`log("connection closed: the partner left; the host takes the baton back (had it: " $ (default.bHasBaton ? "yes" : "no") $ ")",, 'CoopCampaign');
	if (!default.bHasBaton)
	{
		SetBaton(true);
	}
}

// ResetHistory (new campaign, loading a save) drops the history's delegates, so this is
// called on every map. A duplicate hook is harmless: OnNewGameState handles a frame once.
static function HookHistory()
{
	local CoopSession Hook;

	Hook = new class'CoopSession';
	`XCOMHISTORY.RegisterOnNewGameStateDelegate(Hook.OnNewGameState);
	default.LastHandledFrame = `XCOMHISTORY.GetNumGameStates() - 1; // indices restart after a reset
	// a map load destroys a pending CoopFlushTimer; send what it was waiting for
	if (default.bFlushScheduled)
	{
		FlushBatch();
	}
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

	CommitClock(); // still the holder: the clock frame goes out before the grant
	if (`ONLINEEVENTMGR.SaveInProgress())
	{
		// the last batch cannot go out during a save (see FlushBatch); grant once it has
		default.bGrantAfterFlush = true;
		RescheduleFlush();
		`log("baton grant waits for the save to finish",, 'CoopCampaign');
		return;
	}
	FlushBatch();
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
	local XComGameState_BaseObject StateObject;

	if (NewGameState.HistoryIndex <= default.LastHandledFrame && NewGameState.HistoryIndex > 0)
	{
		return;
	}
	default.LastHandledFrame = NewGameState.HistoryIndex;
	if (default.bApplyingRemote || !IsConnected())
	{
		return;
	}
	if (!default.bHasBaton)
	{
		default.LocalFramesWithoutBaton++;
		`log("local frame without baton:" @ NewGameState.GetContext().SummaryString()
			@ "total=" $ default.LocalFramesWithoutBaton,, 'CoopCampaign');
		return;
	}
	if (`XCOMHISTORY.GetStartState() != none)
	{
		return; // still building a start state (tactical/strategy start), not a normal frame
	}
	// Frames are not sent one by one: the network layer lost most of a 10- and a 20-frame
	// burst (test "burst-2", 30 sent, 3 merge callbacks). The objects a frame touched are
	// collected and sent as one merge state with their newest versions (see FlushBatch).
	foreach NewGameState.IterateByClassType(class'XComGameState_BaseObject', StateObject)
	{
		if (default.BatchObjects.Find(StateObject.ObjectID) == INDEX_NONE)
		{
			default.BatchObjects.AddItem(StateObject.ObjectID);
		}
	}
	default.BatchFrames++;
	if (default.BatchObjects.Length > 0)
	{
		RescheduleFlush();
	}
}

static function RescheduleFlush()
{
	if (!default.bFlushScheduled)
	{
		default.bFlushScheduled = true;
		class'CoopFlushTimer'.static.Schedule(BatchDelaySeconds);
	}
}

// Sends everything collected since the last flush as one merge state: the newest
// version of every touched object (removed objects as removals), then one fingerprint.
// Also called right before a grant, so the partner has it all before it takes the baton.
static function FlushBatch()
{
	local XComGameStateHistory History;
	local XComGameState Batch;
	local XComGameState_BaseObject StateObject;
	local array<byte> AlignParams;
	local int ObjectID, Frames;

	default.bFlushScheduled = false;
	if (`ONLINEEVENTMGR.SaveInProgress())
	{
		// sending while a save runs crashed the client (CoopAutosaveMgr); try again shortly
		RescheduleFlush();
		return;
	}
	if (default.bGrantAfterFlush)
	{
		default.bGrantAfterFlush = false;
		GrantBaton(); // flushes the batch itself before granting
		return;
	}
	if (!IsConnected())
	{
		default.BatchObjects.Length = 0;
		default.BatchFrames = 0;
		default.bMergeInFlight = false;
		return;
	}
	if (default.bMergeInFlight)
	{
		if (Now() - default.MergeSentTime < MergeAckTimeoutSeconds)
		{
			RescheduleFlush(); // keep collecting; poll for the ack (or the timeout)
			return;
		}
		`log("merge not acknowledged after" @ int(MergeAckTimeoutSeconds) @ "s, sending its objects again",, 'CoopCampaign');
		foreach default.InFlightObjects(ObjectID)
		{
			if (default.BatchObjects.Find(ObjectID) == INDEX_NONE)
			{
				default.BatchObjects.AddItem(ObjectID);
			}
		}
		default.bMergeInFlight = false;
	}
	if (default.BatchObjects.Length == 0)
	{
		default.BatchFrames = 0;
		return;
	}
	History = `XCOMHISTORY;
	Batch = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Coop batch");
	foreach default.BatchObjects(ObjectID)
	{
		StateObject = History.GetGameStateForObjectID(ObjectID);
		if (StateObject == none)
		{
			continue;
		}
		if (StateObject.bRemoved)
		{
			Batch.RemoveStateObject(ObjectID);
		}
		else
		{
			Batch.ModifyStateObject(StateObject.Class, ObjectID);
		}
	}
	Frames = default.BatchFrames;
	default.InFlightObjects = default.BatchObjects;
	default.BatchObjects.Length = 0;
	default.BatchFrames = 0;
	if (Batch.GetNumGameStateObjects() == 0)
	{
		History.CleanupPendingGameState(Batch);
		return;
	}
	// The batch is submitted here as a frame of its own and that frame is sent. Sending a
	// pending (never submitted) state cut the previous-version link of the newest version of
	// every object in it, here on the sender: GetPreviousVersion returned none from then on
	// (test "sendvar"; a submitted frame sent the same way kept the chain).
	default.bApplyingRemote = true; // not a frame to batch again (OnNewGameState)
	`XCOMGAME.GameRuleset.SubmitGameState(Batch);
	default.bApplyingRemote = false;
	// the partner pads its history first, so the merge lands in the batch's frame number,
	// after every frame its versions can name (AlignHistory); it checks our fingerprint after the merge
	class'XComGameStateNetworkManager'.static.AddCommandParam_Int(History.GetCurrentHistoryIndex(), AlignParams);
	class'XComGameStateNetworkManager'.static.AddCommandParam_String(Fingerprint(), AlignParams);
	`XCOMNETMANAGER.SendRemoteCommand("CoopAlign", AlignParams);
	`XCOMNETMANAGER.SendMergeGameState(History.GetGameStateFromHistory(-1));
	default.bMergeInFlight = true;
	default.MergeSentTime = Now();
	RescheduleFlush(); // polls for the ack, then sends what collected meanwhile
	`log("sent batch of" @ Frames @ "frames," @ Batch.GetNumGameStateObjects() @ "objects, fp=" $ Fingerprint(),, 'CoopCampaign');
}

// A merged object version keeps the sender's PreviousHistoryFrameIndex (the history frame
// of its previous version, a private field). Merges are applied into the receiver's current
// frame, so with differing frame counts that index pointed past the end of the receiver's
// history: anything walking back through versions crashed (native lookup on an empty frame
// slot), e.g. the Avenger's Geoscape map item, UIStrategyMapItem.UpdateFromGeoscapeEntity,
// looking up the HQ as of its last update, and GetPreviousVersion (test "baton-objects":
// the client's batch from its frame 231 reached a host whose last frame was 229).
// Before each merge the sender sends the index of its batch frame (FlushBatch); the receiver adds empty
// frames until that is its current frame, so the merge lands right after every frame the
// sender's versions name: a named frame is then never past the end and always before the
// version's own one. Landing in the sender's current frame itself made versions name their
// own frame, and the walk back looped forever (both instances hung, 3 of 3 runs). A frame
// named that holds no version of the object ends the walk (GetPreviousVersion gave none); one that
// holds an earlier merged version continues it to lower frames. A receiver already past the
// target (its own frames without the baton) cannot go back; the rule still holds there.
static function AlignHistory(int Target)
{
	local XComGameStateHistory History;
	local int Added;

	History = `XCOMHISTORY;
	default.bApplyingRemote = true;
	while (History.GetCurrentHistoryIndex() < Target)
	{
		`XCOMGAME.GameRuleset.SubmitGameState(class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Coop: align history"));
		Added++;
	}
	default.bApplyingRemote = false;
	default.AlignTarget = Target;
	if (Added > 0 || History.GetCurrentHistoryIndex() > Target)
	{
		`log("history aligned for merge in frame" @ Target @ "added=" $ Added @ "ahead=" $ (History.GetCurrentHistoryIndex() - Target),, 'CoopCampaign');
	}
}

function OnReceiveMergeGameState(XComGameState InGameState)
{
	local string LocalFp;
	local array<byte> Params;

	`XCOMNETMANAGER.SendRemoteCommand("CoopMergeAck", Params); // the sender may send its next batch

	if (`XCOMHISTORY.GetCurrentHistoryIndex() != default.AlignTarget)
	{
		`log("merge applied in frame" @ `XCOMHISTORY.GetCurrentHistoryIndex() @ "target=" $ default.AlignTarget,, 'CoopCampaign');
	}
	default.LastRemoteFrameTime = Now();
	ApplyClock(InGameState);
	RefreshAvenger(InGameState);
	LocalFp = Fingerprint();
	`log("received merge state, frames now=" $ `XCOMHISTORY.GetNumGameStates()
		@ "objects=" $ InGameState.GetNumGameStateObjects() @ "fp=" $ LocalFp,, 'CoopCampaign');
	if (ExpectedRemoteFp != "")
	{
		`log((ExpectedRemoteFp == LocalFp ? "in sync" : "DESYNC") @ "remote=" $ ExpectedRemoteFp @ "local=" $ LocalFp,, 'CoopCampaign');
		ExpectedRemoteFp = "";
	}
	TryAcceptGrant();
}

function OnRemoteCommand(string Command, array<byte> RawParams)
{
	local int Epoch;
	local array<byte> Params;

	Params.Length = 0; // replies below carry no parameters

	if (Command == "CoopAlign")
	{
		default.LastRemoteFrameTime = Now();
		AlignHistory(class'XComGameStateNetworkManager'.static.GetCommandParam_Int(RawParams));
		ExpectedRemoteFp = class'XComGameStateNetworkManager'.static.GetCommandParam_String(RawParams);
	}
	else if (Command == "CoopMergeAck")
	{
		default.bMergeInFlight = false;
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
// The strategy clock lives in memory (X2StrategyGameRuleset.GameTime, XGGeoscape.m_kDateTime)
// and reaches the history only in "Geoscape Pause" frames. A receiver must copy a received
// time into its memory clock, or it keeps the time of its join and, once it holds the baton,
// runs the Geoscape from there and sends the partner back in time (test "clock").
static function ApplyClock(XComGameState InGameState)
{
	local XComGameState_GameTime TimeState;

	if (XComHeadquartersGame(class'Engine'.static.GetCurrentWorldInfo().Game) == none)
	{
		return;
	}
	foreach InGameState.IterateByClassType(class'XComGameState_GameTime', TimeState)
	{
		`STRATEGYRULES.GameTime = TimeState.CurrentTime;
		`GAME.GetGeoscape().m_kDateTime = TimeState.CurrentTime;
		`EARTH.SetTime(TimeState.CurrentTime);
		`log("clock set to" @ ClockString(),, 'CoopCampaign');
	}
}

// Writes the memory clock into the history when they differ, so the partner gets it.
static function CommitClock()
{
	local XComGameState NewGameState;
	local XComGameState_GameTime TimeState;

	if (XComHeadquartersGame(class'Engine'.static.GetCurrentWorldInfo().Game) == none)
	{
		return;
	}
	TimeState = XComGameState_GameTime(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_GameTime'));
	if (TimeState.CurrentTime == `STRATEGYRULES.GameTime)
	{
		return;
	}
	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Coop: commit clock");
	TimeState = XComGameState_GameTime(NewGameState.ModifyStateObject(class'XComGameState_GameTime', TimeState.ObjectID));
	TimeState.CurrentTime = `STRATEGYRULES.GameTime;
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);
}

// History clock to the hour.
static function string ClockString()
{
	local XComGameState_GameTime TimeState;

	TimeState = XComGameState_GameTime(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_GameTime', true));
	if (TimeState == none)
	{
		return "t?";
	}
	return "t" $ TimeState.CurrentTime.m_iYear $ "-" $ TimeState.CurrentTime.m_iMonth $ "-" $ TimeState.CurrentTime.m_iDay
		$ "h" $ int(TimeState.CurrentTime.m_fTime / 3600);
}

static function string Fingerprint()
{
	local XComGameState_HeadquartersXCom XComHQ;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom', true));
	if (XComHQ == none)
	{
		return "nohq";
	}
	// the last ObjectIDs show whether objects created on one side got the same IDs on the other
	return ClockString() $ ".sup" $ XComHQ.GetSupplies() $ ".int" $ XComHQ.GetIntel() $ ".all" $ XComHQ.GetAlienAlloys()
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
