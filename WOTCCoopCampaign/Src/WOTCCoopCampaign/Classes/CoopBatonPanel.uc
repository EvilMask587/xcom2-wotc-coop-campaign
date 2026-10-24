//---------------------------------------------------------------------------------------
//  FILE:    CoopBatonPanel.uc
//  PURPOSE: Avenger HUD widget (top right, under the resource bar) showing who holds
//           the co-op baton, with an "ask for control" button for the other player.
//           Added to UIAvengerHUD by CoopEditGate; polls CoopSession twice a second and
//           stays hidden while no partner is connected.
//---------------------------------------------------------------------------------------
class CoopBatonPanel extends UIPanel;

var UIBGBox BG;
var UIText Label;
var UIButton AskButton;

var localized string m_strYou;
var localized string m_strYouAsked;
var localized string m_strPartner;
var localized string m_strArriving;
var localized string m_strPartnerBusy;
var localized string m_strAsk;
var localized string m_strAsked;

const PanelWidth = 600;
const ButtonWidth = 260; // fits the Russian "ask for control" label, the longest one
const PanelHeight = 40;
const PanelHeightTwoLines = 70;

simulated function CoopBatonPanel InitBatonPanel()
{
	InitPanel('CoopBatonPanel');
	AnchorTopRight();
	SetPosition(-PanelWidth - 10, 62);
	SetSize(PanelWidth, PanelHeight);

	BG = Spawn(class'UIBGBox', self);
	BG.InitBG('CoopBatonBG', 0, 0, PanelWidth, PanelHeight);
	Label = Spawn(class'UIText', self);
	Label.InitText('CoopBatonLabel');
	Label.SetPosition(10, 6);
	Label.SetWidth(PanelWidth - ButtonWidth - 20);
	AskButton = Spawn(class'UIButton', self);
	AskButton.InitButton('CoopBatonAsk', m_strAsk, OnAskClicked);
	AskButton.SetPosition(PanelWidth - ButtonWidth, 5);

	Refresh();
	SetTimer(0.5f, true, nameof(Refresh));
	return self;
}

simulated function Refresh()
{
	local string Text;
	local bool bButton;

	if (!class'CoopSession'.static.IsConnected())
	{
		Hide();
		return;
	}
	Show();
	class'CoopSession'.static.CheckRequestTimeout();
	if (class'CoopSession'.default.bHasBaton)
	{
		Text = class'CoopSession'.default.bGrantRequested ? m_strYouAsked : m_strYou;
	}
	else if (class'CoopSession'.default.bGrantPending)
	{
		Text = m_strArriving;
	}
	else if (class'CoopSession'.default.bRequestQueued)
	{
		Text = m_strPartnerBusy;
	}
	else
	{
		Text = m_strPartner;
		bButton = true;
		AskButton.SetText(class'CoopSession'.default.bRequestSent ? m_strAsked : m_strAsk);
		AskButton.SetDisabled(class'CoopSession'.default.bRequestSent);
	}
	if (bButton != AskButton.bIsVisible)
	{
		AskButton.SetVisible(bButton);
		// texts without the button use the full width
		Label.SetWidth(bButton ? PanelWidth - ButtonWidth - 20 : PanelWidth - 20);
	}
	if (Text != Label.Text)
	{
		Label.SetText(Text);
		// the two long texts wrap to a second line; keep them inside the box
		BG.SetSize(PanelWidth, (Text == m_strYouAsked || Text == m_strPartnerBusy) ? PanelHeightTwoLines : PanelHeight);
	}
}

simulated function OnAskClicked(UIButton Button)
{
	class'CoopSession'.static.RequestBaton();
	Refresh();
}

// The panel of the current HUD, for the test harness.
static function CoopBatonPanel Find(Actor AnyActor)
{
	local CoopBatonPanel Panel;

	foreach AnyActor.AllActors(class'CoopBatonPanel', Panel)
	{
		return Panel;
	}
	return none;
}
