# Android signing

Glyph's existing GitHub release key is the maintainer's Android debug key,
with certificate name `CN=Android Debug` and SHA-256 fingerprint:

```text
8f7a1d1830d401866985253d480eb7f4748c4c1144a8eb77f0e11448c28f9b68
```

It is already the identity trusted by installed copies of Glyph. Replacing it
with an unrelated key would break updates. We rotate to a dedicated release
key using Android's signed proof of rotation (the **lineage**), while keeping
the old key for older phones. The debug key's familiar name and default
password are reasons to move to a dedicated key; rotation does not remove
the need to protect the old private key.

| Android version | Signature it uses after rotation |
| --- | --- |
| 7–8.1 (API 24–27) | v2 with the **old** key; v1 is also signed with the old key |
| 9+ (API 28+) | v3 with the **new** key and the old-to-new lineage |

The app's minimum Android version remains API 24. CI explicitly sets
`--rotation-min-sdk-version 28`; apksigner's default otherwise targets rotation
at Android 13+. Supplying the old signer, the new signer and `--lineage` lets
apksigner use the oldest key for v1/v2. See the [Android apksigner reference](https://developer.android.com/tools/apksigner).

## Status (11 October 2026)

Rotation is set up. The new release key was created with
`tool/setup_release_signing.sh` and all five `ANDROID_RELEASE_*` /
`ANDROID_SIGNING_LINEAGE_BASE64` secrets are set; the next tagged release is the
first signed with both keys.

| Key | Signs | Certificate SHA-256 |
|---|---|---|
| Old (Android debug keystore, `androiddebugkey`) | v1/v2, read by Android 7–8 | `8f7a1d1830d401866985253d480eb7f4748c4c1144a8eb77f0e11448c28f9b68` |
| New (`glyph-release`, `CN=Glyph, O=Glyph`, RSA 4096, PKCS12) | v3 with lineage, read by Android 9+ | `d9f51a1f873db96bfec0be9c230e5ec2ead72660aa42abaf04389291ad84441e` |

Where they live: `~/glyph-release-keys/` on the maintainer's Mac (new key, old
key copy, lineage, README); a zipped copy in the maintainer's Google Drive; the
new key's password only in the macOS Keychain ("Glyph release keystore") and the
maintainer's password manager, never in the same place as the key files.

## Keys and GitHub secrets

Keep these four existing secrets unchanged: they hold the **old signer**.

| Existing secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Old keystore, base64 encoded |
| `ANDROID_KEYSTORE_PASSWORD` | Old keystore password |
| `ANDROID_KEY_ALIAS` | Old key alias (normally `androiddebugkey`) |
| `ANDROID_KEY_PASSWORD` | Old key password |

Add these five secrets for rotation:

| New secret | Value |
| --- | --- |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | New `glyph-release.jks`, base64 encoded |
| `ANDROID_RELEASE_KEYSTORE_PASSWORD` | New keystore password |
| `ANDROID_RELEASE_KEY_ALIAS` | `glyph-release` |
| `ANDROID_RELEASE_KEY_PASSWORD` | New key password (may equal the keystore password) |
| `ANDROID_SIGNING_LINEAGE_BASE64` | `glyph-signing.lineage`, base64 encoded |

CI builds an unsigned APK using `--android-project-arg unsignedRelease=true`
(Gradle `-PunsignedRelease=true`; `-Pfdroid=true` remains an alias). It then
signs with apksigner. All four old secrets are always required. If any of the
five new secrets are missing, CI emits a notice and signs with only the old
key. Invalid complete rotation material fails the release, without fallback.
Passwords reach apksigner through `env:` references, never command arguments
or properties files. Decoded keystores live only in a private runner temporary
directory and are removed when the signing step exits.

**After the first rotated release, keep all five new secrets set.** An old-only
release is not a safe fallback for phones that have already updated to the new
key. The lineage deliberately does not grant rollback to the old key.

## One-time procedure

**Quick path (recommended, decided 11 October 2026).** Run one command on the
Mac that holds `~/.android/debug.keystore`:

```bash
./tool/setup_release_signing.sh
```

It generates a random 40-character password that is never shown, stores it in
the macOS Keychain ("Glyph release keystore"), creates the new PKCS12 key
(`CN=Glyph, O=Glyph`, RSA 4096) and the rotation lineage in
`~/glyph-release-keys/` (with a copy of the old debug keystore), and sets the
five GitHub secrets using the `spandan-kumar` gh login. Afterwards, back up
`~/glyph-release-keys` and the Keychain entry to two offline places. The
commands were dry-run with throwaway keys on 11 October 2026: API 24–27
verified with the old certificate, API 28+ with the new one, and the APK's
lineage listed both. The manual path below does the same with your own prompts.

### Manual path

1. Confirm the old keystore matches the fingerprint above using
   `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey`.
   Let it prompt for its password. Use the original keystore, not a newly
   generated debug key with the same name.
2. In a local terminal run `tool/rotate_signing_key.sh`. You can instead run
   `tool/rotate_signing_key.sh /path/to/old.keystore /path/to/new.jks old-alias`.
   `--help` explains the defaults. It checks for keytool/apksigner, creates a
   JKS keystore with an RSA 4096-bit key valid for 10000 days, and asks for your
   certificate details and passwords. Use your own name, not Android Debug.
   apksigner then prompts for the old and new passwords to create the lineage.
   The Android debug password is `android` unless changed. Neither tool is
   given passwords on the command line.
3. Record the printed public certificate fingerprints: lineage signer #1 is
   old and signer #2 is new. Run the script's exact `gh secret set` commands.
   The keystore/lineage commands pipe base64 directly into GitHub; the password
   and alias commands prompt for values. Set all five before releasing. Keep
   passwords in your password manager, never in shell history or files in this
   project. Never paste base64 key contents into logs or documentation.
4. Back up the keys as described below, then follow the normal version and
   changelog procedure in [AGENTS.md](../AGENTS.md) and push a `vX.Y.Z` tag.
   Inspect the signing step: it must verify the old key on API 24–27, the new
   key on modern Android, and both in the lineage read from the signed APK.
5. Download the published APK and check it with build-tools 36.0.0 or newer:

   ```sh
   apksigner verify --print-certs -v glyph-X.Y.Z-arm64-v8a.apk
   apksigner verify --print-certs -v --min-sdk-version 24 --max-sdk-version 27 glyph-X.Y.Z-arm64-v8a.apk
   apksigner lineage --in glyph-X.Y.Z-arm64-v8a.apk --print-certs
   ```

   The first must verify v3 and show the new fingerprint; the second must
   verify v2 and show the old fingerprint above. The third must show both in
   order. **A single full-range `verify --print-certs -v` may print only the new
   certificate**, so its signer count need not be two. The extra checks are
   necessary to see both with this rotation target, as shown by the
   [apksigner implementation](https://android.googlesource.com/platform/tools/apksig/+/refs/heads/main/src/apksigner/java/com/android/apksigner/ApkSignerTool.java).
   Test an update from the previous release on Android 7–8 and Android 9+,
   checking that Glyph's data stays intact.

If key creation succeeds but rotation fails, do not delete or regenerate the
new key. Resolve the failure and finish rotation interactively (replace paths
and aliases if you used other ones; do not overwrite a valid lineage):

```sh
"$HOME/Library/Android/sdk/build-tools/36.0.0/apksigner" rotate \
  --out "$HOME/glyph-release-keys/glyph-signing.lineage" \
  --old-signer --ks "$HOME/.android/debug.keystore" --ks-key-alias androiddebugkey \
  --set-installed-data true --set-rollback false \
  --new-signer --ks "$HOME/glyph-release-keys/glyph-release.jks" --ks-key-alias glyph-release
```

## Backups and loss

Back up **both `~/glyph-release-keys` and `~/.android/debug.keystore` offline in
two separate places**, including the lineage. Back up your chosen paths too if
you changed them. Protect the copies and keep recoverable passwords in your
password manager. GitHub secrets are not a backup you can download. Never
delete/regenerate the original debug keystore: its default-looking name does
not make a replacement equivalent.

If the old key is lost before making the lineage, existing installs cannot
move to an unrelated new key. If it is lost after rotation, Android 9+ can
still receive new-key updates with the lineage, but Android 7–8 cannot; this
workflow needs both keys and will fail until the old key is restored. If the
new key is lost after rotation, the old key alone cannot update phones already
using the new key. Restore a backup; another rotation needs the current private
key. Lost passwords can likewise make a keystore unusable. Without a usable
backup, affected users may need an uninstall/reinstall and data backup.

The lineage contains certificates and signed history, not private keys. If
its file is lost, a rotated APK can serve as the `--lineage` input to apksigner
sign, or you can recreate the file while both keys remain available. Check
its fingerprints and capabilities before using it.

## Google Play and F-Droid

Play App Signing will need an **upload key** when Glyph goes to Play; use a
dedicated upload key and plan the Play app-signing identity separately. The
old Android Debug certificate cannot be used for Play uploads. Play's signing
and upgrade procedure is separate from this GitHub APK rotation; do not assume
cross-store updates until the certificates and lineage are confirmed. See
[Android's app signing guide](https://developer.android.com/studio/publish/app-signing).

F-Droid upstream signing also needs testing with this mixed old-v2/new-v3
signature. See the blockers and TODOs in [the submission draft](launch/fdroid-submission.md).
