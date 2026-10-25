//---------------------------------------------------------------------------------------
//  FILE:    CoopHarness.uc
//  PURPOSE: Test bot. Runs a scripted list of console commands from XComCoopHarness.ini
//           so automated tests can drive two game instances without a human.
//           Every step is logged with the 'CoopHarness' tag; the test runner reads
//           Launch.log to check results. Does nothing when Steps is empty.
//---------------------------------------------------------------------------------------
class CoopHarness extends Actor config(CoopHarness);

struct HarnessStep
{
	var float Delay;   // seconds to wait before running Cmd
	var string Cmd;    // console command, or a harness command starting with '@'
};

var config string InstanceTag;
var config array<HarnessStep> Steps;

// config only so default.NextStep may be written: it carries progress across map loads (never saved)
var config int NextStep;

// Active wait started by @waitconn / @waithist; polled once per second.
var name WaitKind;
var int WaitArg;
var float WaitLeft;

// @netwatch: queue logging
var float NetWatchLeft;
var string LastNetWatch;

static function CoopHarness EnsureSpawned(Actor Spawner)
{
	local CoopHarness Harness;

	foreach Spawner.AllActors(class'CoopHarness', Harness)
	{
		return Harness;
	}
	return Spawner.Spawn(class'CoopHarness');
}

event PostBeginPlay()
{
	super.PostBeginPlay();
	class'CoopHarnessNet'.static.Init();
	class'CoopSession'.static.Init();
	class'CoopSession'.static.HookHistory();
	NextStep = default.NextStep;
	`log("ready tag=" $ InstanceTag @ "steps=" $ Steps.Length @ "next=" $ NextStep @ "map=" $ WorldInfo.GetMapName(),, 'CoopHarness');
	ScheduleNext();
}

function ScheduleNext()
{
	if (NextStep >= Steps.Length)
	{
		`log("done tag=" $ InstanceTag,, 'CoopHarness');
		return;
	}
	SetTimer(FMax(Steps[NextStep].Delay, 0.01f), false, nameof(RunNext));
}

function RunNext()
{
	local string Cmd;

	Cmd = Steps[NextStep].Cmd;
	`log("step" @ NextStep @ "cmd=" $ Cmd,, 'CoopHarness');
	NextStep++;
	default.NextStep = NextStep;

	if (Left(Cmd, 1) == "@")
	{
		RunHarnessCommand(Mid(Cmd, 1));
	}
	else
	{
		GetALocalPlayerController().ConsoleCommand(Cmd);
	}
	if (WaitKind == '')
	{
		ScheduleNext();
	}
}

function StartWait(name Kind, int Arg)
{
	WaitKind = Kind;
	WaitArg = Arg;
	WaitLeft = 180.0f;
	SetTimer(1.0f, true, nameof(PollWait));
}

function PollWait()
{
	local bool bMet;

	if (WaitKind == 'Conn')
	{
		// HasConnections() is already true while a server only listens, so wait for the join event
		bMet = class'CoopHarnessNet'.default.bPeerJoined;
	}
	else if (WaitKind == 'Hist')
	{
		bMet = `XCOMHISTORY.GetNumGameStates() >= WaitArg;
	}
	else if (WaitKind == 'Baton')
	{
		bMet = class'CoopSession'.default.bHasBaton;
	}
	WaitLeft -= 1.0f;
	if (bMet || WaitLeft <= 0)
	{
		`log("wait" @ WaitKind @ (bMet ? "met" : "TIMEOUT"),, 'CoopHarness');
		ClearTimer(nameof(PollWait));
		WaitKind = '';
		ScheduleNext();
	}
}

static function string BoolStr(bool b)
{
	if (b)
	{
		return "true";
	}
	return "false";
}

function RunHarnessCommand(string Cmd)
{
	if (Cmd ~= "quit")
	{
		GetALocalPlayerController().ConsoleCommand("exit");
	}
	else if (Cmd ~= "netinfo")
	{
		`log("net server=" $ BoolStr(`XCOMNETMANAGER.HasServerConnection()) @ "client=" $ BoolStr(`XCOMNETMANAGER.HasClientConnection())
			@ "connections=" $ BoolStr(`XCOMNETMANAGER.HasConnections()),, 'CoopHarness');
	}
	else if (Left(Cmd, 8) ~= "connect ")
	{
		Connect(Mid(Cmd, 8));
	}
	else if (Cmd ~= "ping")
	{
		class'CoopHarnessNet'.static.SendCommand("CoopPing");
	}
	else if (Cmd ~= "waitconn")
	{
		StartWait('Conn', 0);
	}
	else if (Left(Cmd, 9) ~= "waithist ")
	{
		StartWait('Hist', int(Mid(Cmd, 9)));
	}
	else if (Cmd ~= "newcampaign")
	{
		StartDebugCampaign();
	}
	else if (Cmd ~= "avenger")
	{
		GetALocalPlayerController().ConsoleCommand("open Avenger_Root?game=XComGame.XComHeadQuartersGame");
	}
	else if (Cmd ~= "mirror")
	{
		class'CoopSession'.default.bEnterAsMirror = true;
		GetALocalPlayerController().ConsoleCommand("open Avenger_Root?game=XComGame.XComHeadQuartersGame");
	}
	else if (Cmd ~= "baton")
	{
		class'CoopSession'.static.SetBaton(true);
	}
	else if (Cmd ~= "nobaton")
	{
		class'CoopSession'.static.SetBaton(false);
	}
	else if (Cmd ~= "batonreq")
	{
		class'CoopSession'.static.RequestBaton();
	}
	else if (Cmd ~= "grant")
	{
		class'CoopSession'.static.GrantBaton(); // unrequested, e.g. right after a frame: tests the command/merge race
	}
	else if (Cmd ~= "waitbaton")
	{
		StartWait('Baton', 0);
	}
	else if (Left(Cmd, 9) ~= "histdump ")
	{
		DumpHistory(int(Mid(Cmd, 9)));
	}
	else if (Cmd ~= "histinfo")
	{
		LogHistoryInfo();
	}
	else if (Left(Cmd, 9) ~= "crewinfo ")
	{
		LogCrewInfo(int(Mid(Cmd, 9)));
	}
	else if (Left(Cmd, 9) ~= "objrange ")
	{
		LogObjectRange(Mid(Cmd, 9));
	}
	else if (Cmd ~= "rooms")
	{
		LogRooms();
	}
	else if (Cmd ~= "hud")
	{
		`HQPRES.ClearUIToHUD(true);
	}
	else if (Cmd ~= "cam")
	{
		LogCamera();
	}
	else if (Cmd ~= "open research")
	{
		`HQPRES.UIChooseResearch(true);
	}
	else if (Cmd ~= "open build")
	{
		`HQPRES.UIBuildFacilities(true);
	}
	else if (Cmd ~= "close")
	{
		`SCREENSTACK.GetCurrentScreen().CloseScreen();
	}
	else if (Cmd ~= "screens")
	{
		LogScreens();
	}
	else if (Cmd ~= "time")
	{
		LogTime();
	}
	else if (Left(Cmd, 9) ~= "research ")
	{
		StartResearch(name(Mid(Cmd, 9)));
	}
	else if (Cmd ~= "geoscape")
	{
		`HQPRES.UIEnterStrategyMap();
	}
	else if (Cmd ~= "scan")
	{
		`GAME.GetGeoscape().FastForward();
	}
	else if (Cmd ~= "pause")
	{
		`GAME.GetGeoscape().Pause();
	}
	else if (Left(Cmd, 9) ~= "netwatch ")
	{
		NetWatchLeft = float(Mid(Cmd, 9));
		SetTimer(0.05f, true, nameof(NetWatch));
	}
	else if (Left(Cmd, 14) ~= "pendingstress ")
	{
		PendingStress(int(Mid(Cmd, 14)));
	}
	else if (Cmd ~= "autosave")
	{
		// what the camera does when going from the Geoscape back to the Avenger (BaseRoomView)
		`AUTOSAVEMGR.DoAutosave();
	}
	else if (Left(Cmd, 9) ~= "walkback ")
	{
		WalkBack(int(Mid(Cmd, 9)));
	}
	else if (Cmd ~= "pausemenu")
	{
		`HQPRES.UIPauseMenu();
	}
	else if (Cmd ~= "savescreen")
	{
		// what the pause menu's Save item does
		`HQPRES.UISaveScreen();
	}
	else if (Left(Cmd, 6) ~= "burst ")
	{
		Burst(int(Mid(Cmd, 6)));
	}
	else if (Cmd ~= "emptyframe")
	{
		// a frame without objects, like the game's "Entered Facility"; SendMergeGameState refuses those
		`XCOMGAME.GameRuleset.SubmitGameState(class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Coop test: empty frame"));
	}
	else if (Cmd ~= "cancelwait")
	{
		// same path as clicking the dialog's Cancel button
		if (UIProgressDialogue(`SCREENSTACK.GetFirstInstanceOf(class'UIProgressDialogue')) != none)
		{
			UIProgressDialogue(`SCREENSTACK.GetFirstInstanceOf(class'UIProgressDialogue')).OnCancel();
		}
		else
		{
			`log("cancelwait: no dialog",, 'CoopHarness');
		}
	}
	else if (Cmd ~= "panel")
	{
		LogPanel();
	}
	else if (Cmd ~= "ask")
	{
		if (class'CoopBatonPanel'.static.Find(self) != none)
		{
			class'CoopBatonPanel'.static.Find(self).OnAskClicked(class'CoopBatonPanel'.static.Find(self).AskButton);
		}
	}
	else if (Left(Cmd, 9) ~= "lookroom ")
	{
		LookAtRoom(int(Mid(Cmd, 9)));
	}
	else if (Left(Cmd, 10) ~= "clearroom ")
	{
		ClearRoom(int(Mid(Cmd, 10)));
	}
	else if (Left(Cmd, 10) ~= "buildroom ")
	{
		BuildRoom(Mid(Cmd, 10));
	}
	else
	{
		`log("unknown harness command" @ Cmd,, 'CoopHarness');
	}
}

// New campaign without tutorial and without the first tactical mission (like the dev
// strategy shell's cheat start), then travel to the Avenger.
function StartDebugCampaign()
{
	local XComGameState StartState;
	local XComGameState_CampaignSettings Settings;
	local XComGameState_Objective ObjectiveState;

	StartState = class'XComGameStateContext_StrategyGameRule'.static.CreateStrategyGameStart(, , false, false, true, 1, , , , true);
	Settings = XComGameState_CampaignSettings(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_CampaignSettings'));
	Settings.SetStartTime(StartState.TimeStamp);
	Settings.bCheatStart = true;
	Settings.bSkipFirstTactical = true;
	foreach StartState.IterateByClassType(class'XComGameState_Objective', ObjectiveState)
	{
		if (ObjectiveState.GetMyTemplateName() == 'T1_M0_FirstMission')
		{
			ObjectiveState.AlreadyPlayedNarratives.AddItem("X2NarrativeMoments.Strategy.GP_GameIntro");
			ObjectiveState.AlreadyPlayedNarratives.AddItem("X2NarrativeMoments.Strategy.GP_WelcomeToHQ");
			ObjectiveState.AlreadyPlayedNarratives.AddItem("X2NarrativeMoments.Strategy.GP_WelcomeToTheResistance");
		}
	}
	`log("campaign created frames=" $ `XCOMHISTORY.GetNumGameStates(),, 'CoopHarness');
	GetALocalPlayerController().ConsoleCommand("open Avenger_Root?game=XComGame.XComHeadQuartersGame");
}

// One line that two instances can compare to tell whether they hold the same campaign.
function LogHistoryInfo()
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local string FirstSoldier;

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom', true));
	if (XComHQ == none)
	{
		`log("hist frames=" $ History.GetNumGameStates() @ "hq=none",, 'CoopHarness');
		return;
	}
	Soldiers = XComHQ.GetSoldiers();
	if (Soldiers.Length > 0)
	{
		FirstSoldier = Soldiers[0].GetFullName() $ "#" $ Soldiers[0].ObjectID;
	}
	`log("hist frames=" $ History.GetNumGameStates() @ "index=" $ History.GetCurrentHistoryIndex() @ "fp=" $ class'CoopSession'.static.Fingerprint()
		@ "supplies=" $ XComHQ.GetSupplies() @ "crew=" $ XComHQ.Crew.Length @ "soldiers=" $ Soldiers.Length
		@ "first=" $ FirstSoldier,, 'CoopHarness');
}

// The last Count crew members, plus a check that no two crew entries share an ObjectID
// (objects created on both sides must not reuse each other's IDs).
function LogCrewInfo(int Count)
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_Unit Unit;
	local int i, j, Dups;

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom', true));
	if (XComHQ == none)
	{
		`log("crew hq=none",, 'CoopHarness');
		return;
	}
	for (i = 0; i < XComHQ.Crew.Length; i++)
	{
		for (j = i + 1; j < XComHQ.Crew.Length; j++)
		{
			if (XComHQ.Crew[i].ObjectID == XComHQ.Crew[j].ObjectID)
			{
				Dups++;
			}
		}
	}
	`log("crew count=" $ XComHQ.Crew.Length @ "duplicateIDs=" $ Dups,, 'CoopHarness');
	for (i = Max(0, XComHQ.Crew.Length - Count); i < XComHQ.Crew.Length; i++)
	{
		Unit = XComGameState_Unit(History.GetGameStateForObjectID(XComHQ.Crew[i].ObjectID));
		if (Unit == none)
		{
			`log("crew" @ i @ "id=" $ XComHQ.Crew[i].ObjectID @ "MISSING in history",, 'CoopHarness');
		}
		else
		{
			`log("crew" @ i @ "id=" $ Unit.ObjectID @ "type=" $ Unit.GetMyTemplateName() @ "name=" $ Unit.GetFullName(),, 'CoopHarness');
		}
	}
}

// Every Avenger room: its facility, the map its state asks for and the map actually streamed in.
// "stale" marks a room whose screen does not match the game state.
function LogRooms()
{
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_HeadquartersRoom Room;
	local XGBase AvengerBase;
	local LevelStreaming Level;
	local string Facility, Wanted, Loaded, Stream;
	local int i;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom', true));
	if (XComHQ == none || XComHeadquartersGame(WorldInfo.Game) == none)
	{
		`log("rooms: not in the strategy layer",, 'CoopHarness');
		return;
	}
	AvengerBase = `GAME.GetGeoscape().m_kBase;
	for (i = 0; i < XComHQ.Rooms.Length; i++)
	{
		Room = XComHQ.GetRoom(i);
		Facility = Room.HasFacility() ? string(Room.GetFacility().GetMyTemplateName()) : "-";
		Wanted = class'XGBase'.static.GetMapname(Room);
		Level = AvengerBase.m_arrLvlStreaming[i];
		Loaded = Level != none ? string(Level.PackageName) : "";
		// streaming state of the room map: loaded level present, visible, meant to be visible
		Stream = Level == none ? "nostream" : ("ld=" $ BoolStr(Level.LoadedLevel != none) $ ",vis=" $ BoolStr(Level.bIsVisible)
			$ ",want=" $ BoolStr(Level.bShouldBeVisible) $ ",pending=" $ BoolStr(Level.bHasLoadRequestPending));
		`log("room" @ i @ "facility=" $ Facility @ "map=" $ Wanted @ Stream
			@ (Loaded ~= Wanted ? "" : "STALE loaded=" $ Loaded),, 'CoopHarness');
	}
}

function LogPanel()
{
	local CoopBatonPanel Panel;

	Panel = class'CoopBatonPanel'.static.Find(self);
	if (Panel == none)
	{
		`log("panel none",, 'CoopHarness');
		return;
	}
	`log("panel visible=" $ BoolStr(Panel.bIsVisible) @ "label=\"" $ Panel.Label.Text $ "\"" @ "button=" $ BoolStr(Panel.AskButton.bIsVisible)
		$ (Panel.AskButton.IsDisabled ? ",disabled" : "") @ "\"" $ Panel.AskButton.Text $ "\"",, 'CoopHarness');
}

// The network manager's send/receive queues: per entry type, state (0 not handled,
// 1 sent, 2 processed) and serialized size; logged only when it changes.
function NetWatch()
{
	local XComGameStateNetworkManager NetMgr;
	local string Line;
	local int i;

	NetMgr = `XCOMNETMANAGER;
	for (i = 0; i < NetMgr.OutGameData.Length; i++)
	{
		Line @= "out" $ i $ "=" $ NetMgr.OutGameData[i].GameDataType $ "/" $ NetMgr.OutGameData[i].PendingState $ "/" $ NetMgr.OutGameData[i].GameStateRaw.Length;
	}
	for (i = 0; i < NetMgr.InGameData.Length; i++)
	{
		Line @= "in" $ i $ "=" $ NetMgr.InGameData[i].GameDataType $ "/" $ NetMgr.InGameData[i].PendingState $ "/" $ NetMgr.InGameData[i].GameStateRaw.Length;
	}
	if (Line != LastNetWatch)
	{
		`log("netq" $ (Line == "" ? " empty" : Line),, 'CoopHarness');
		LastNetWatch = Line;
	}
	NetWatchLeft -= 0.05f;
	if (NetWatchLeft <= 0)
	{
		ClearTimer(nameof(NetWatch));
	}
}

// Count pending states created and discarded (never submitted), as CoopSession.FlushBatch
// does for every batch; no network involved.
function PendingStress(int Count)
{
	local XComGameState Pending;
	local XComGameState_HeadquartersXCom XComHQ;
	local int i;

	for (i = 0; i < Count; i++)
	{
		Pending = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Coop test: pending" @ i);
		XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
		Pending.ModifyStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID);
		`XCOMHISTORY.CleanupPendingGameState(Pending);
	}
	`log("pendingstress" @ Count @ "done",, 'CoopHarness');
}

// Looks up the HQ and every crew member as of each of the last Frames frames, the lookup
// the Avenger's Geoscape map item makes; it walks back through previous versions, which
// crashed on a merged version naming a frame past the end of the history.
function WalkBack(int Frames)
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference Ref;
	local int Index, Found;

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	for (Index = History.GetCurrentHistoryIndex(); Index > History.GetCurrentHistoryIndex() - Frames && Index >= 0; Index--)
	{
		if (History.GetGameStateForObjectID(XComHQ.ObjectID,, Index) != none)
		{
			Found++;
		}
		foreach XComHQ.Crew(Ref)
		{
			if (History.GetGameStateForObjectID(Ref.ObjectID,, Index) != none)
			{
				Found++;
			}
		}
	}
	`log("walkback frames=" $ Frames @ "found=" $ Found,, 'CoopHarness');
}

// Count frames in one tick, each +1 supply, like the bursts the game makes (e.g. three
// "Geoscape Pause" frames when leaving the Geoscape) that preceded two client crashes.
function Burst(int Count)
{
	local XComGameState NewGameState;
	local XComGameState_HeadquartersXCom XComHQ;
	local int i;

	for (i = 0; i < Count; i++)
	{
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Coop test: burst" @ i);
		XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
		XComHQ = XComGameState_HeadquartersXCom(NewGameState.ModifyStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));
		XComHQ.AddResource(NewGameState, 'Supplies', 1);
		`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);
	}
	`log("burst" @ Count @ "frames submitted",, 'CoopHarness');
}

static function string DateStr(TDateTime T)
{
	return T.m_iYear $ "-" $ T.m_iMonth $ "-" $ T.m_iDay $ "+" $ int(T.m_fTime) $ "s";
}

// The strategy clock in its three places (history, ruleset, Geoscape) and every research
// project's completion date. Only the history copy is shared through merge states.
function LogTime()
{
	local XComGameStateHistory History;
	local XComGameState_GameTime TimeState;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_HeadquartersProjectResearch Project;
	local string Line;
	local int i;

	History = `XCOMHISTORY;
	TimeState = XComGameState_GameTime(History.GetSingleGameStateObjectForClass(class'XComGameState_GameTime', true));
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom', true));
	Line = "time history=" $ (TimeState != none ? DateStr(TimeState.CurrentTime) : "none");
	if (XComHeadquartersGame(WorldInfo.Game) != none)
	{
		Line @= "rules=" $ DateStr(`STRATEGYRULES.GameTime) @ "geoscape=" $ DateStr(`GAME.GetGeoscape().m_kDateTime)
			@ "scale=" $ `GAME.GetGeoscape().m_fTimeScale;
	}
	for (i = 0; XComHQ != none && i < XComHQ.Projects.Length; i++)
	{
		Project = XComGameState_HeadquartersProjectResearch(History.GetGameStateForObjectID(XComHQ.Projects[i].ObjectID));
		if (Project != none)
		{
			Line @= "research#" $ Project.ObjectID $ "=" $ XComGameState_Tech(History.GetGameStateForObjectID(Project.ProjectFocus.ObjectID)).GetMyTemplateName()
				$ ",done@" $ DateStr(Project.CompletionDateTime) $ ",points=" $ Project.ProjectPointsRemaining;
		}
	}
	`log(Line @ "techs=" $ (XComHQ != none ? XComHQ.TechsResearched.Length : -1),, 'CoopHarness');
}

function StartResearch(name TechName)
{
	local XComGameState_Tech Tech;
	local XComGameState_HeadquartersXCom XComHQ;

	foreach `XCOMHISTORY.IterateByClassType(class'XComGameState_Tech', Tech)
	{
		if (Tech.GetMyTemplateName() == TechName)
		{
			XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
			XComHQ.SetNewResearchProject(Tech.GetReference()); // what UIChooseResearch does on confirm
			`log("research started" @ TechName @ "tech#" $ Tech.ObjectID,, 'CoopHarness');
			return;
		}
	}
	`log("research: no tech" @ TechName,, 'CoopHarness');
}

// The screen stack, top first, with edit screens and the wait dialog marked.
function LogScreens()
{
	local UIScreenStack Stack;
	local string Line;
	local int i;

	Stack = `SCREENSTACK;
	for (i = 0; i < Stack.Screens.Length; i++)
	{
		Line $= (i > 0 ? " < " : "") $ Stack.Screens[i].Class.Name $ (class'CoopEditGate'.static.IsEditScreen(Stack.Screens[i]) ? "[edit]" : "");
	}
	`log("screens" @ Line @ "baton=" $ BoolStr(class'CoopSession'.default.bHasBaton) @ "editing=" $ BoolStr(class'CoopEditGate'.static.IsEditing())
		@ "grantRequested=" $ BoolStr(class'CoopSession'.default.bGrantRequested),, 'CoopHarness');
}

// Camera state and the actual view point, so the two players' cameras can be compared by numbers.
function LogCamera()
{
	local XComHeadquartersCamera Cam;
	local vector Loc;
	local rotator Rot;

	Cam = `HQPRES.GetCamera();
	GetALocalPlayerController().GetPlayerViewPoint(Loc, Rot);
	`log("cam state=" $ Cam.GetStateName() @ "camstate=" $ (Cam.CameraState != none ? string(Cam.CameraState.Class.Name) : "none")
		@ "room=" $ Cam.CurrentRoom @ "prev=" $ Cam.PreviousRoom @ "anim=" $ Cam.AnimTime $ "/" $ Cam.TotalAnimTime
		@ "loc=" $ Loc @ "rot=" $ Rot @ "screen=" $ `SCREENSTACK.GetCurrentScreen(),, 'CoopHarness');
}

function LookAtRoom(int MapIndex)
{
	local XComGameState_HeadquartersXCom XComHQ;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	`HQPRES.CAMLookAtRoom(XComHQ.GetRoom(MapIndex), 0);
}

// Tears down the facility in a room (the opposite of the GiveFacility cheat), so tests
// can build into a room on a cheat-start campaign where every room is taken. Also tests
// whether merge states carry removed objects.
function ClearRoom(int MapIndex)
{
	local XComGameState NewGameState;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_HeadquartersRoom Room;
	local StateObjectReference FacilityRef;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	Room = XComHQ.GetRoom(MapIndex);
	if (Room == none || !Room.HasFacility())
	{
		`log("clearroom" @ MapIndex @ "has no facility",, 'CoopHarness');
		return;
	}
	FacilityRef = Room.Facility;
	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Coop test: clear room" @ MapIndex);
	Room = XComGameState_HeadquartersRoom(NewGameState.ModifyStateObject(class'XComGameState_HeadquartersRoom', Room.ObjectID));
	Room.Facility.ObjectID = 0;
	XComHQ = XComGameState_HeadquartersXCom(NewGameState.ModifyStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));
	XComHQ.Facilities.RemoveItem(FacilityRef);
	NewGameState.RemoveStateObject(FacilityRef.ObjectID);
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);
	`log("clearroom" @ MapIndex @ "removed facility" @ FacilityRef.ObjectID,, 'CoopHarness');
	class'CoopSession'.static.RefreshAvenger(NewGameState);
}

// "index FacilityTemplate": the state changes of the GiveFacility cheat, but the room on
// screen is updated through CoopSession.RefreshAvenger, the same path the partner uses.
function BuildRoom(string Args)
{
	local array<string> Parts;
	local XComGameState NewGameState;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_HeadquartersRoom Room;
	local XComGameState_FacilityXCom Facility;
	local X2FacilityTemplate FacilityTemplate;
	local int MapIndex;

	Parts = SplitString(Args, " ", true);
	MapIndex = int(Parts[0]);
	FacilityTemplate = X2FacilityTemplate(class'X2StrategyElementTemplateManager'.static.GetStrategyElementTemplateManager().FindStrategyElementTemplate(name(Parts[1])));
	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	Room = XComHQ.GetRoom(MapIndex);
	if (FacilityTemplate == none || Room == none || Room.HasFacility())
	{
		`log("buildroom" @ Args @ "not possible",, 'CoopHarness');
		return;
	}
	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Coop test: build" @ Parts[1] @ "in room" @ MapIndex);
	Room = XComGameState_HeadquartersRoom(NewGameState.ModifyStateObject(class'XComGameState_HeadquartersRoom', Room.ObjectID));
	Facility = FacilityTemplate.CreateInstanceFromTemplate(NewGameState);
	Facility.Room = Room.GetReference();
	Facility.ConstructionDateTime = `STRATEGYRULES.GameTime;
	Room.Facility = Facility.GetReference();
	Room.ConstructionBlocked = false;
	Room.SpecialFeature = '';
	XComHQ = XComGameState_HeadquartersXCom(NewGameState.ModifyStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));
	XComHQ.Facilities.AddItem(Facility.GetReference());
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);
	`log("buildroom" @ MapIndex @ "facility" @ Facility.ObjectID,, 'CoopHarness');
	class'CoopSession'.static.RefreshAvenger(NewGameState);
	class'X2StrategyGameRulesetDataStructures'.static.CheckForPowerStateChange();
	if (FacilityTemplate.OnFacilityBuiltFn != none)
	{
		FacilityTemplate.OnFacilityBuiltFn(Facility.GetReference());
	}
}

// "first last": the class of every ObjectID in the range, to compare which IDs each side allocated.
function LogObjectRange(string Args)
{
	local array<string> Parts;
	local XComGameState_BaseObject Obj;
	local int ID;

	Parts = SplitString(Args, " ", true);
	for (ID = int(Parts[0]); ID <= int(Parts[1]); ID++)
	{
		Obj = `XCOMHISTORY.GetGameStateForObjectID(ID);
		`log("obj" @ ID @ (Obj == none ? "none" : string(Obj.Class.Name)),, 'CoopHarness');
	}
}

// "a.b.c.d port". IpNetDriverSteamworks does not parse a dotted host (it keeps only the
// first number), so the address is passed as one decimal integer.
function Connect(string Args)
{
	local array<string> Parts, Octets;
	local URL ClientURL;
	local string Error;
	local int Addr, i;

	Parts = SplitString(Args, " ", true);
	Octets = SplitString(Parts[0], ".", true);
	for (i = 0; i < Octets.Length; i++)
	{
		Addr = (Addr << 8) | (int(Octets[i]) & 255);
	}
	ClientURL.Host = string(Addr);
	ClientURL.Port = int(Parts[1]);
	`log("connect host=" $ ClientURL.Host @ "port=" $ ClientURL.Port,, 'CoopHarness');
	`XCOMNETMANAGER.CreateClient(ClientURL, Error);
	if (Error != "")
	{
		`log("connect error=" $ Error,, 'CoopHarness');
	}
	SetTimer(0.25f, false, nameof(ForceConnect));
}

function ForceConnect()
{
	`log("force connection attempt result=" $ BoolStr(`XCOMNETMANAGER.ForceConnectionAttempt()),, 'CoopHarness');
}

function DumpHistory(int Count)
{
	local XComGameStateHistory History;
	local XComGameState Frame;
	local int i;

	History = `XCOMHISTORY;
	for (i = Max(0, History.GetNumGameStates() - Count); i < History.GetNumGameStates(); i++)
	{
		Frame = History.GetGameStateFromHistory(i, eReturnType_Reference);
		`log("frame" @ i @ "objects=" $ Frame.GetNumGameStateObjects() @ "context=" $ Frame.GetContext().SummaryString(),, 'CoopHarness');
	}
}
