//---------------------------------------------------------------------------------------
//  FILE:    CoopGrantRetry.uc
//  PURPOSE: Calls CoopSession.TryAcceptGrant again after a delay. CoopSession is a plain
//           Object and cannot own timers; WorldInfo.SetTimer with the session as inObj
//           never fired in the strategy layer (test "baton-protocol-2"). The actor dies
//           with the map, which is fine: a grant is re-checked on every merge state too.
//---------------------------------------------------------------------------------------
class CoopGrantRetry extends Actor;

var CoopSession Target;

static function Schedule(CoopSession Session, float Delay)
{
	local CoopGrantRetry Retry;

	Retry = class'WorldInfo'.static.GetWorldInfo().Spawn(class'CoopGrantRetry');
	Retry.Target = Session;
	Retry.SetTimer(Delay, false, nameof(Fire));
}

function Fire()
{
	Target.TryAcceptGrant();
	Destroy();
}
