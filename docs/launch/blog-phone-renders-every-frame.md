# Why Glyph's phone renders every frame of a WLED display

A 16×16 LED panel has only 256 pixels, but making those pixels useful involves more than choosing an effect. I wanted the same display to show procedural animation, authored pixel art, drawings, games and whatever my phone was playing. Glyph is a free, MIT-licensed Flutter app built around one decision: the phone renders the frames, and WLED handles the LEDs.

That produces two playback paths. During live playback, the phone sends RGB frames over DDP/UDP. When you tap **Send**, it renders an animation into a GIF, uploads it, and configures WLED's Image effect and a saved preset. The controller then plays the recording without the phone. Both start with the same rendering engine; they have different timing, colour and failure constraints.

## A renderer independent of Flutter

The engine in `lib/engine` is pure Dart. It has no Flutter imports, sockets or Android services. A frame is a row-major `Uint8List` containing three bytes per pixel, with the origin at the top left. Flutter draws the preview from those pixels; the networking layer sends them to the device.

An effect instance owns any simulation state and implements this interface:

```dart
void render(Frame out, double t, double dt, Params p, Palette pal);
```

`t` is elapsed seconds and `dt` is the interval since the previous frame. A plasma field can calculate its colours from time and position. Fire, falling sand and reaction-diffusion retain buffers between calls. The separation lets the engine run in command-line tools and worker isolates, and lets tests inspect RGB output without building widgets or connecting hardware.

Glyph's own catalog has 1,236 looks, based on 62 procedural generators and 356 sprites. Those are different counts: a look can reuse a generator with another palette and parameter set. The catalog is data pointing to rendering code or sprite content, rather than 1,236 separate algorithms. (The app also bundles 12,361 pre-rendered animations shared by their creator, for 13,597 looks in 32 subject groups; those are frame data rather than code.)

Sprites are authored as text grids with named colours, frame sequences, durations and motion. Palette-linked inks allow recolouring; patches and reusable parts keep the source manageable. Original art and drawings based on public-domain works carry the project's content rules and provenance. This format also makes a small art contribution possible without writing a new Flutter screen.

Keeping rendering on the phone avoids making controller memory determine which simulations are available. An ESP8266 can receive live frames even though its WLED build cannot play uploaded GIFs. The tradeoff is explicit: interactive content needs the phone, a reachable controller and usable Wi-Fi.

## Live frames: a small UDP pipeline

Glyph sends Distributed Display Protocol packets to UDP port 4048. A 16×16 RGB frame is 768 bytes. At the default 40 frames per second for effects, that is 30,720 bytes of pixel payload per second, before headers and network overhead. Slow information cards can request a lower rate.

The sender uses a ten-byte DDP header and chunks of at most 1,440 payload bytes, or 480 RGB pixels. Larger frames span packets with byte offsets into the frame; only the final packet carries the push flag. Packet buffers are reused instead of allocated for every update. A simplified use of the actual sender is:

```dart
final sender = DdpSender('192.168.1.50');
await sender.open();
sender.send(frame.rgb); // Pass device-corrected RGB in production.
sender.close();
```

UDP does not guarantee delivery. Glyph counts local send failures, but a successful socket send is not proof that the controller displayed a complete frame. Larger panels cost more bandwidth, and LED output itself limits refresh rates. Forty frames per second is a rendering target, not a promise for every panel, controller and network.

Live rendering is useful where the input keeps changing: strokes in the pixel editor, game controls, microphone visualisers and album art from Android media sessions. It also means the preview and physical display share the rendering logic, rather than approximating a firmware effect on the phone.

## Send: turn a renderer into device-owned playback

For content that can become a recording, Glyph bakes frames into a looping GIF. Authored sprites retain a complete sequence and motion pass. Procedural simulations can evolve indefinitely, so Send records at least 30 seconds and prepares a loop boundary, warming up stateful effects and blending the seam where needed. It cannot preserve an infinite simulation in a finite file.

The device baker normally samples motion at 20 fps. Sprite sampling also includes authored changes so short steps are retained. GIF delays are expressed in centiseconds, and WLED advances playback on its effect ticks, so device timing is not identical to the live 40 fps path.

The encoder writes one shared colour table and later frames as changed rectangles, using transparency for unchanged pixels. It quantises to at most 255 colours, reserving an entry for transparency, without dithering. This is useful for small pixel displays, but it is still a limited-colour recording. File size depends on content and duration; a long procedural recording should not be advertised as an invariably tiny GIF.

Send also needs a GIF-capable controller. Glyph detects capabilities, including the Image effect, rather than assuming that every WLED device supports it. The supported device path requires WLED 16+ on an ESP32-family chip with enough filesystem space. Phone preparation has its own resource bounds. Insufficient storage is an error; Glyph does not silently shorten the animation to make it fit.

## The wait that survived a file change

One device-specific problem was surprising: WLED's GIF frame wait can carry over from one file into the next. In the WLED 16.0.1 source, `image_loader.cpp` never resets `currentFrameDelay` when opening the next image. A very long hold in one GIF can therefore make the next animation appear blank while the inherited wait runs out.

Glyph's device encoder limits every frame delay to one second:

```dart
const deviceMaxFrameCs = 100; // GIF centiseconds.
```

This limit also applies when identical frames are folded into a longer hold. Once merging would exceed the cap, the encoder emits another frame, using a tiny transparent rectangle where appropriate. Static content must not become one enormous wait. The device limit is separate from GIFs exported for ordinary screens.

This is a workaround for the verified firmware behaviour, not a claim that Glyph repairs WLED's decoder. It bounds the delay contributed by Glyph's files; it cannot undo a long wait inherited from an unrelated file.

## Gamma belongs to exactly one side

The same RGB bytes can look different through streaming and GIF playback. LED drive levels are not screen colours. Without correction, near-black pixels can glow and a saturated hue can look washed out, especially at low brightness.

WLED can bypass colour gamma for realtime input. Glyph reads the colour configuration, including this flag:

```json
{"if":{"live":{"no-gc":true}}}
```

When `if.live.no-gc` is true, Glyph applies device gamma on the phone before streaming. When WLED applies gamma to live input, Glyph leaves that step to WLED. The correction layer also applies white balance and a black floor. Its default WS2812-family balance reduces green in LED space, and pixels below the visible floor become fully black.

GIFs take the Image effect path through WLED's own gamma. Glyph stores them with white balance and the black floor prepared, but without applying gamma a second time. Applying gamma on both sides would make midtones too dark. This division is why “send exactly the preview bytes” is insufficient as a colour policy.

## Upload first, switch after

Sending is a staged operation. `saveGifToDevice` chooses a fresh filename, uploads through `/upload`, and checks the stored size when the firmware supplies it. It retries recoverable upload failures before switching playback. Older listings without sizes fall back to trusting the HTTP success response; this is not a cryptographic read-back guarantee.

Only after upload verification does Glyph select the Image effect, set the filename, leave realtime mode and save the preset. Re-sending reuses the Saved look's preset, while the previous file is retired only after it is no longer referenced or playing. A failed upload must preserve the previous playback. Errors after switching are a different stage and should not be described as an atomic transaction.

This order matters on weak Wi-Fi. Stopping the stream first would leave a working display interrupted while the transfer struggles. Staging also avoids overwriting a GIF that WLED currently has open.

## Setup starts with physical evidence

The new setup wizard uses three physical tests for a conventional panel: which corner contains LED zero, which direction the first run travels, and where the second run starts. With known dimensions, those answers identify the start corner, rows or columns, and straight or zig-zag wiring.

During these tests Glyph switches off `if.live.rlm`, WLED's “Use LED map for realtime” option. Otherwise an existing map could turn a supposed physical-index test into a logical-coordinate test. The flag is restored on exit or enabled for the applied layout. Diagrams confirm the answers, with manual choices available.

Applying that layout uses `POST /settings/2D`, with fields such as `SOMP`, `MPC` and `P0W/P0H/P0B/P0R/P0V/P0S/P0X/P0Y`. The form takes effect immediately and can turn 2D off again. JSON `hw.led.matrix` needs a reboot and cannot disable 2D. Because the form recreates segments, Glyph restores playback afterwards, reads back the layout and keeps an undo snapshot.

Wi-Fi needs the opposite choice. Glyph avoids `/settings/wifi`, whose omitted fields can reset the AP name and transmit power. It patches the target network through `/json/cfg`, then restarts:

```json
{"nw":{"ins":[{"ssid":"Home","psk":"example-password","bssid":"000000000000"}]}}
```

An acknowledgement is not proof of joining. While the phone is connected to the setup AP, WLED does not search for home Wi-Fi. After handoff, Glyph finds the same controller again by MAC using mDNS and subnet scanning, rather than trusting an old IP address.

## Scope and credit

The wizard configures hardware already running WLED; it does not flash firmware. Its write path supports a single digital output and regular grids of equal panels, preserving complex setups through the existing settings/orientation path. It shipped in v1.4.0 without a never-configured ESP32 check because no spare controller was available. Real multi-panel grids and iOS remain untested on hardware. Android is the release platform; shared Flutter code is not evidence of a working iOS release.

[WLED](https://github.com/wled/WLED) supplies the firmware, LED drivers, realtime receiver, Image effect, storage and scheduling that make this possible. Glyph is independent and MIT licensed; it contains no copied WLED code. The [repository](https://github.com/spandan-kumar/glyph), [setup implementation notes](../DEVICE_SETUP.md#as-built-11-october) and [Android releases](https://github.com/spandan-kumar/glyph/releases/latest) are open for inspection. The engineering benefit is simple: one phone-side renderer can feed either a live display or a recording, provided each path respects the controller's actual behaviour.
