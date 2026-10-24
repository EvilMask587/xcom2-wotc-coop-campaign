//---------------------------------------------------------------------------------------
//  FILE:    UIScreenListener_CoopHarness.uc
//  PURPOSE: Starts the test harness on the first screen of every map.
//---------------------------------------------------------------------------------------
class UIScreenListener_CoopHarness extends UIScreenListener;

event OnInit(UIScreen Screen)
{
	class'CoopHarness'.static.EnsureSpawned(Screen);
}

defaultproperties
{
	ScreenClass = none;
}
