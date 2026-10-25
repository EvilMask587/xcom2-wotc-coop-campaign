//---------------------------------------------------------------------------------------
//  FILE:    CoopFlushTimer.uc
//  PURPOSE: Calls CoopSession.FlushBatch after a short delay, so the frames of one burst
//           go out as one merge state. One-shot actor (CoopSession cannot own timers).
//---------------------------------------------------------------------------------------
class CoopFlushTimer extends Actor;

static function Schedule(float Delay)
{
	class'WorldInfo'.static.GetWorldInfo().Spawn(class'CoopFlushTimer').SetTimer(Delay, false, nameof(Fire));
}

function Fire()
{
	class'CoopSession'.static.FlushBatch();
	Destroy();
}
