# Home Assistant

Make your Glyph device react to your home: flash a look when the doorbell
rings, glow warm at sunset, show a Show when you arrive. Glyph ships two
blueprints (ready-made automations) that you fill in with a few taps.

## Before you start

- Your Glyph device is a WLED controller, and Home Assistant's built-in
  **WLED** integration finds it by itself. Check **Settings, Devices &
  services**: if the device is listed under WLED, you are set. If not, add the
  **WLED** integration and enter the device's address (shown in Glyph under
  Device).
- Home Assistant 2024.10 or newer.
- Save at least one look on your device in Glyph (**Send to device**). Only
  Saved looks can be triggered; Home Assistant plays what is already on the
  device, so it works even when your phone is away.

## Add the blueprints

Tap a button (it opens your Home Assistant and asks to import):

- [Import: show a Saved look](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2Fspandan-kumar%2Fglyph%2Fblob%2Fmain%2Fhomeassistant%2Fblueprints%2Fautomation%2Fglyph%2Fshow_saved_look.yaml)
- [Import: play a Show](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2Fspandan-kumar%2Fglyph%2Fblob%2Fmain%2Fhomeassistant%2Fblueprints%2Fautomation%2Fglyph%2Fplay_show.yaml)

Or in Home Assistant: **Settings, Automations & scenes, Blueprints, Import
blueprint**, then paste one of these addresses:

- `https://github.com/spandan-kumar/glyph/blob/main/homeassistant/blueprints/automation/glyph/show_saved_look.yaml`
- `https://github.com/spandan-kumar/glyph/blob/main/homeassistant/blueprints/automation/glyph/play_show.yaml`

## Make an automation

1. **Settings, Automations & scenes, Blueprints**, pick *Glyph: show a Saved
   look when something happens*, then **Create automation**.
2. **When this happens**: add the trigger (a doorbell button, sunset, a person
   arriving, a time of day).
3. **Your Glyph device (light)** and **(Preset)**: choose the entries that
   belong to your device. They are named after it, for example
   `light.matrix` and `select.matrix_preset`.
4. **Saved look name**: type the name exactly as Glyph shows it. In Glyph, open
   **Device**, then **Saved**, then **Use with Home Assistant**: every name has
   a copy button.
5. Optional: **Go back after** (how long to show it, 0 stays on it) and
   **Brightness**.

For a Show, use *Glyph: play a Show when something happens* and pick the
device's **Playlist** entry; Shows appear in the same Glyph sheet.

## Options

- **Go back after**: show the look for this long, then return to what the
  device was doing (even a different look, or off). 0 stays on the look.
- **Until this happens**: with Go back after at 0, keep the look until one of
  these triggers fires (a door opening, a button), then go back.
  **Longest wait** (12 hours by default) goes back anyway if it never fires.
- **Quiet hours**: switch on **Use quiet hours** and set a start and end; the
  automation does nothing in between. Windows that cross midnight, like 22:00
  to 07:00, work.
- **Cooldown**: ignore triggers that arrive within this time of the last run.
- **Brightness**: a percentage for this moment; 0 keeps the device's own.
  A Saved look stored with its own brightness may override this value.
- **The other selector (optional)**: the Saved look blueprint can also take
  the device's **Playlist** entry, and the Show blueprint its **Preset** entry.
  Fill it in and going back can resume whatever was playing, whether it was a
  Saved look or a Show. Left empty, it goes back to the same kind of thing
  you picked.

Each automation keeps its own snapshot, so several automations can share one
device. Going back only happens if the device still shows your look. If someone chose
something else in the meantime (in Glyph, WLED or Home Assistant), their
choice is left alone.

Playback runs on the device itself, so these looks keep playing, and going
back still works, even when your phone is off or away.

## Recipes

**Doorbell: 30 seconds, then go back.**
Trigger: the doorbell button pressed. Saved look name: `Alert`. Go back
after: 30 seconds. Optional cooldown of 1 minute stops a double press from
restarting it.

**Laundry done: until the washer door opens.**
Trigger: the washer's cycle-finished sensor turns on. Saved look name:
`Laundry`. Go back after: 0. Until this happens: the washer door opens.
Leave Longest wait at 12 hours so it is never stuck on. Turn on quiet hours
(22:00 to 07:00) if you do not want it glowing overnight.

**Timer finished: until cleared, or 2 minutes.**
Trigger: the kitchen timer finishes. Saved look name: `Timer`. Go back after:
0. Until this happens: a button press or a tap on the dashboard. Longest
wait: 2 minutes.

**Sunset: a calm look.**
Trigger: Sun, sunset. Saved look name: `Fireplace`. Go back after: 0 and no
"until this happens", so it stays on. Brightness 40 keeps it dim.

## If it does not work

- **The name must match exactly**, including capitals and spaces. Use the copy
  button in Glyph rather than typing it.
- **Renamed it in Glyph?** The option in Home Assistant changes with it.
  Update the name in the automation, and reload the WLED integration (or wait
  a moment) so Home Assistant sees the new name.
- **A look is missing from Glyph's list?** Glyph hides its own looks
  ("Glyph intro" and "Power-on"); you cannot trigger those. Looks without a
  name are not listed either; rename them in Glyph first.
- **Nothing happens at all**: check the automation's *Traces* in Home
  Assistant. A "not a valid option" error means the name does not match.
- If a trigger fires again while a look is showing, the timer restarts and the
  device still goes back to what it was originally showing.
- For Shows, going back only happens while the device still reports that Show
  as playing; a Show that ends by itself may leave the device where it is.

## Not here yet

Glyph does not watch Home Assistant entities (to draw a temperature or an
alert on the display) yet. That is planned for later; for now Home Assistant
chooses what the device plays, and Glyph provides the looks.
