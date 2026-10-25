# WOTC Co-op Campaign (prototype)

Two-player shared campaign for **XCOM 2: War of the Chosen**: both players run the same
Avenger, take turns changing it, and (later) play the tactical missions together.

**Status: prototype, strategy layer only.** Not playable as a campaign yet: tactical
missions are not shared, and only the Avenger/strategy state is synchronised. Built with
the [Co-op Anything](https://github.com/cranebeaker/coop-anything) playbook; full
research notes are in `games/xcom-2/NOTES.md` there.

Tested on: Steam, XCOM 2 buildid 8270065 (changelist 699444), War of the Chosen + all DLC,
Windows 10, two game instances on one PC over 127.0.0.1. Not tested between two PCs or
over Steam networking.

## What works (each item has a test, see QA)

- **Join:** the host sends its whole campaign history; the client opens the Avenger
  from it through the load-game path (`CoopHeadquartersGame`, "mirror" entry).
- **Baton:** one player at a time may change the campaign. The holder's every new frame
  goes to the partner as a merge game state plus a fingerprint (resources, counts, last
  ObjectIDs). Resources, new units, techs, facilities built and removed all arrive with the
  same ObjectIDs on both sides.
- **Handoff over the network:** request -> grant (epoch, fingerprint, highest ObjectID)
  -> the receiver takes the baton once it has caught up and no frame arrived for 1 s -> ack.
- **Edit screens need the baton** (`CoopEditGate`, list in `Config/XComCoopCampaign.ini`:
  research, Proving Ground, building, armory, inventory, recruiting, squad select,
  Geoscape...). Opening one without the baton asks for it and shows a "waiting for
  partner" dialog with Cancel. The holder hands over only after closing its edit screens.
- **Safety net:** the player without the baton cannot create game state objects
  (`CoopStrategyRuleset`), otherwise both sides would hand out the same ObjectID.
- **HUD panel** (Avenger and Geoscape, top right): who has control, "Ask for control"
  button, partner busy / asking hints. English and Russian texts.
- **Screen refresh on the receiver:** changed rooms are swapped like a finished
  construction; resource bar and facility grid are rebuilt.
- **Geoscape clock:** the holder's time travels with its frames; the partner's clock
  follows and continues forward after a handoff.
- **Batching:** frames made within 0.2 s go out as one merge state (the network layer lost
  frames sent one by one in bursts). The batch is a frame of its own on the sender
  ("Coop batch"): sending a state that is not in the history cut the sender's own
  previous-version links.
  One merge state in flight: the receiver acknowledges each one ("CoopMergeAck"); a second
  batch sent 0.23 s after the first was lost. A merge without an ack is sent again after 5 s.
- **History alignment:** before each merge the receiver adds empty frames so the merge
  lands in the same frame number as the sender's batch; without it the host crashed in 5 of
  11 runs of the new-units test (the Avenger's map icon looked up an older version).
- **Projects across players:** research and facility construction started by one player
  complete on the other's Geoscape; the result and the room swap reach the starter.
- **Host saves after merges load back** the same campaign (fingerprint and crew equal,
  Geoscape time runs, saving again works).
- **Only the host saves:** on the client autosaves, quicksaves and the pause menu's Save are
  disabled (`CoopAutosaveMgr`, `CoopSaveGate`); a client that saved while sending crashed.

## Known issues

- No tactical co-op yet; no mission launch for two players.
- The player without the baton still runs some local UI frames (alerts seen, entered
  facility...). They are not sent and get overwritten by the holder's merges.
- The Geoscape clock: a player who stays on the Geoscape keeps the baton until leaving it.
- Popups (research done, facility built, new missions) appear only for the player on the
  Geoscape; the partner sees the result but no popup.
- The edit screen list is a first guess (staff slots inside facilities, DLC/mod screens).
- One unexplained crash of the client (engine package loading, tbbmalloc) while it was
  entering facilities by hand; not reproduced.
- Merged object versions keep the sender's "previous version" frame number; the receiver
  pads its history so they stay valid (`CoopSession.AlignHistory`). On the receiver the
  previous-version chain of a merged object ends at the merged version (the lookup returns
  none, no crash). Whether some game code needs that older version is unknown.
- Only direct IP tested (the host address is passed as one decimal integer: the engine's
  IpNetDriverSteamworks does not parse a dotted host).

## Build

Needs the XCOM 2 War of the Chosen SDK (Steam) and a **copy** of the game used only for
tests (never build into the install you play):

```powershell
$env:XCOM2_SDK = "<SDK dir>"          # ...\XCOM 2 War of the Chosen SDK
$env:COOP_WORKSPACE = "<workspace>"   # holds test-install\ and test-install-b\
tools\build_mod.ps1
```

Build scripts: [X2ModBuildCommon](https://github.com/X2CommunityCore/X2ModBuildCommon)
(MIT, in `.scripts/`).

## QA: two game instances on one PC

- `test-install` = copy of the game folder, `test-install-b` = hard-link clone of it with
  its own `XComGame/Config` (`tools/hardlink_clone.py`). Both run with `-nohomedir`, so
  saves/config/logs stay inside the copies.
- XCOM 2 refuses a second instance while the first holds the mutex `UnrealEngine3_<n>`;
  `tools/launch_pair.ps1` closes that handle inside instance A (same user, no admin) with
  Sysinternals `handle64.exe` (download it yourself, set `SYSINTERNALS_HANDLE`) and
  `tools/close_remote_handle.py`.
- The mod contains a test bot (`CoopHarness`): `tools/run_pair_test.ps1` writes a list of
  steps per instance (console commands and `@harness` commands such as `@connect`,
  `@baton`, `@crewinfo`, `@rooms`, `@open research`, `@ask`, `@save`, `@load N`,
  `@verchain`, `@construct`, `@dismiss`, `@waitgrantreq`) and collects both logs.
  It does nothing when its step list is empty (normal play).
- `tools/test_suite.ps1` runs the scenarios and asserts on both logs (expected lines, no
  DESYNC/crash/duplicate IDs, equal final fingerprints). Do not touch the game windows
  during a run: the client's camera and screens react to the mouse.

Last suite result: see the Co-op Anything write-up (`games/xcom-2/README.md`).

Other tools: `minidump_info.py` (crash address -> module+offset, stack scan),
`re_func_strings.py`, `re_dis.py`, `re_callers.py` (strings/disassembly around an address),
`trace_start.py` (DLL loads/exceptions at start), `udp_sniff.py`, `list_windows.py`.

## License

See `LICENSE`.
