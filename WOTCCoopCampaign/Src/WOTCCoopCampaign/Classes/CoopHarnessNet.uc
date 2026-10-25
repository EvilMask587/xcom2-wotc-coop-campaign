//---------------------------------------------------------------------------------------
//  FILE:    CoopHarnessNet.uc
//  PURPOSE: Network event logger for the test harness. A plain Object (not an Actor)
//           because XComGameStateNetworkManager outlives every map: delegates bound to an
//           Actor keep its World alive and the engine asserts on the next map load.
//---------------------------------------------------------------------------------------
class CoopHarnessNet extends Object config(CoopHarness);

var config bool bInited;       // the instance is kept alive by the network manager's delegate arrays
var config bool bPeerJoined;   // set by the PlayerJoined event; config only so the default may be written
var config int JoinCount;      // PlayerJoined events so far (a rejoin is the second)
var config int ClosedCount;    // ConnectionClosed events so far

static function Init()
{
	local CoopHarnessNet Net;
	local XComGameStateNetworkManager NetMgr;

	if (default.bInited)
	{
		return;
	}
	Net = new class'CoopHarnessNet';
	default.bInited = true;
	NetMgr = `XCOMNETMANAGER;
	NetMgr.AddPlayerJoinedDelegate(Net.OnPlayerJoined);
	NetMgr.AddNotifyAcceptedConnectionDelegate(Net.OnAcceptedConnection);
	NetMgr.AddNotifyConnectionClosedDelegate(Net.OnConnectionClosed);
	NetMgr.AddReceiveRemoteCommandDelegate(Net.OnRemoteCommand);
	NetMgr.AddReceiveHistoryDelegate(Net.OnReceiveHistory);
}

static function SendCommand(string Command)
{
	local array<byte> Params;

	Params.Length = 0;
	`XCOMNETMANAGER.SendRemoteCommand(Command, Params);
}

function OnPlayerJoined(string RequestURL, string Address, const UniqueNetId UniqueId, bool bSupportsAuth)
{
	default.JoinCount++;
	`log("event PlayerJoined addr=" $ Address @ "joins=" $ default.JoinCount,, 'CoopHarness');
	default.bPeerJoined = true;
}

function OnAcceptedConnection(int ConnectionIdx)
{
	`log("event AcceptedConnection idx=" $ ConnectionIdx,, 'CoopHarness');
}

function OnConnectionClosed(int ConnectionIdx)
{
	default.ClosedCount++;
	`log("event ConnectionClosed idx=" $ ConnectionIdx @ "closed=" $ default.ClosedCount,, 'CoopHarness');
}

function OnRemoteCommand(string Command, array<byte> RawParams)
{
	`log("event RemoteCommand cmd=" $ Command @ "bytes=" $ RawParams.Length,, 'CoopHarness');
	if (Command == "CoopPing")
	{
		SendCommand("CoopPong");
	}
}

function OnReceiveHistory(XComGameStateHistory InHistory, X2EventManager EventManager)
{
	`log("event ReceiveHistory frames=" $ InHistory.GetNumGameStates(),, 'CoopHarness');
}
