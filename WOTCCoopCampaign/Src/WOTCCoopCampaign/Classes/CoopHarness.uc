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
	else if (Cmd ~= "histinfo")
	{
		LogHistoryInfo();
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
	`log("hist frames=" $ History.GetNumGameStates() @ "index=" $ History.GetCurrentHistoryIndex()
		@ "supplies=" $ XComHQ.GetSupplies() @ "crew=" $ XComHQ.Crew.Length @ "soldiers=" $ Soldiers.Length
		@ "first=" $ FirstSoldier,, 'CoopHarness');
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
