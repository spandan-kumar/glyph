Glyph’s F-Droid submission draft targets **v1.4.0, arm64 only**. It follows the current [Flutter template](https://gitlab.com/fdroid/fdroiddata/-/blob/master/templates/build-flutter.yml), [Flutter srclib](https://gitlab.com/fdroid/fdroiddata/-/blob/master/srclibs/flutter.yml), and examples from [LocalSend](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/org.localsend.localsend_app.yml), [Ente Photos](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/io.ente.photos.fdroid.yml) and [Energize](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/com.flasskamp.energize.yml). This is an untested packaging draft, not proof of a successful F-Droid build.

**Since v1.4.7 (15 October 2026): the bundled imported collection.** The app
now bundles 12,273 clips (30 MiB) from an imported animation collection,
included with its creator's permission but not under a free licence, and some
of them show third-party characters (game, cartoon and brand mascots). This
matters for F-Droid in two ways:

- It must be declared as the **NonFreeAssets** anti-feature (the metadata
  draft below now does). Reviewers may still refuse an app whose bundled art
  depicts trademarked characters, regardless of the anti-feature.
- **Recommended path:** an F-Droid build without the collection. The recipe's
  `prebuild` removes `catalog_assets/imported/` and its `pubspec.yaml` asset
  entry, and builds with `--dart-define=GLYPH_COLLECTION=false` so the app
  hides imported entries instead of trying to load them. That build needs no
  NonFreeAssets declaration and returns the APK to about 28 MB. **TODO (app):**
  support that define and tolerate the missing assets; it doesn't yet.
- Alternative: submit as is with NonFreeAssets and wait for review feedback.
  Submitting a build that ships different content from GitHub releases also
  rules out reproducible upstream signing for that flavour; it would be
  F-Droid-signed.

1. **Choose signing before publication.** Attempt reproducible builds with Glyph's rotated upstream signature so existing GitHub/Obtainium installs can update from F-Droid. First complete [the signing rotation procedure](../SIGNING.md). The YAML remains an F-Droid-signed packaging baseline until the checks below pass; do not enable `Binaries` and `AllowedAPKSigningKeys` yet. Never give F-Droid either private key. If upstream signing is impractical, leave both fields absent and choose F-Droid signing, accepting uninstall/reinstall and data backup when switching channels. Failed reproducible verification with `Binaries` prevents publication; it does not silently select another signature. See [reproducible builds](https://f-droid.org/en/docs/Reproducible_Builds/).

   Signing research (2026-10-11):

   - **Fingerprint:** For a rotated-only upstream release, the intended pin is the **new v3 signing certificate's SHA-256** (`d9f51a1f873db96bfec0be9c230e5ec2ead72660aa42abaf04389291ad84441e`), 64 lowercase hex digits, as printed by a full-range `apksigner verify --print-certs -v`. The old fingerprint is `8f7a1d1830d401866985253d480eb7f4748c4c1144a8eb77f0e11448c28f9b68`; add it as an alternative only if also accepting pre-rotation releases. `AllowedAPKSigningKeys` contains accepted certificate identities, not an old-to-new lineage, and the downloaded `.sha256` is a file hash. The [field reference](https://f-droid.org/docs/Build_Metadata_Reference/#AllowedAPKSigningKeys) describes pinning and warns that multiple simultaneous signers are unsupported. This rotation uses one signer per Android version, not two simultaneous signers.
   - **Server blocker:** The inspected [fdroidserver certificate helper](https://github.com/f-droid/fdroidserver/blob/master/fdroidserver/common.py) reads v3 first, then v2, but rejects unequal certificates without interpreting rotation history. This APK deliberately has new-v3/old-v2. Adding both pins does not fix that. [The build path](https://github.com/f-droid/fdroidserver/blob/master/fdroidserver/build.py) uses this helper for the allowed-key check; do not treat a successful signature-copy comparison alone as approval. **TODO:** Test the exact fdroidserver version used for submission, record its returned fingerprint, and obtain server support/reviewer guidance if it rejects the rotated APK or reports no fingerprint. Do not bypass signature checks.
   - **Signature copying:** [apksigcopier's implementation](https://github.com/obfusk/apksigcopier/blob/master/apksigcopier/__init__.py) extracts and implants the whole APK Signing Block. This should preserve v3's embedded proof of rotation without needing either key (an inference from the implementation, not a tested Glyph result). fdroidserver's `verify_apks` copies signatures then calls apksigner. **TODO:** Run a local `fdroid build` against the first rotated release; check the copied APK verifies, its embedded lineage has both certificates, and `fdroid publish --error-on-failed` plus `fdroid update` retain it and index the intended signer. Also test updates from the last old-only APK on Android 7–8 and Android 9+ through the F-Droid client.
   - **Debug certificate:** The inspected [build checks](https://github.com/f-droid/fdroidserver/blob/master/fdroidserver/build.py) and [repository update checks](https://github.com/f-droid/fdroidserver/blob/master/fdroidserver/update.py) reject `android:debuggable`/`testOnly` manifest flags; no blanket certificate-subject rejection for `CN=Android Debug` was found in those paths. That is separate from Google's [debug-certificate publishing restriction](https://developer.android.com/studio/publish/app-signing#debug-mode). **TODO:** Confirm the deployed server and F-Droid reviewers accept the old debug-named v1/v2 certificate and lineage ancestor; the release APK must remain non-debuggable. Rotation retains that ancestor.

   Verification commands are in [SIGNING.md](../SIGNING.md). Full-range `verify --print-certs -v` may show only the new signer: use API 24–27 verification to see the old one and `apksigner lineage --in APK --print-certs` to see both. **TODO:** Once these checks pass, update the draft's version/code/commit to the tested rotated tag, enable both upstream fields and replace the new-certificate TODO. Match CI's project/SDK paths, JDK, NDK and lockfile where differences require it; inspect reproducibility failures with diffoscope.

2. **Confirm release inputs.** Check the public `v1.4.0` tag contains `1.4.0+12`, the lockfile and fastlane listing. Flutter is pinned to **3.47.6**, matching release/CI workflows and Dart **3.13.5**. [Flutter’s split implementation](https://github.com/flutter/flutter/blob/3.47.6/packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt) adds `1000 × ABI index`: arm64’s index is 2, giving **2012**. Thus use `%c + 2000`, not `%c * 10 + 2`. Multiple ABIs would need separate blocks and a revised scheme that remains monotonic across releases. Connectivity covers controller communication; Multimedia covers animations. Both are [current categories](https://gitlab.com/fdroid/fdroiddata/-/blob/master/config/categories.yml). Donate is omitted because no donation destination is configured.

3. **Prepare the submission checkout.** Fork [fdroiddata](https://gitlab.com/fdroid/fdroiddata), clone your fork, branch from current `master` as `glyph`, and copy `docs/launch/fdroid/dev.spandankumar.glyph.yml` into `metadata/dev.spandankumar.glyph.yml`. Resolve TODOs in that copy. The recipe uses `$$flutter$$`, fetches packages into `.pub-cache` before scanning, deletes flagged cached binaries with `scandelete`, and builds with `--no-pub --android-project-arg fdroid=true`. Flutter 3.47.6 supports `--android-project-arg`, which forwards `fdroid=true` as Gradle’s `-Pfdroid=true`; this leaves the release APK unsigned for F-Droid signing or upstream signature copying. Do not blanket `scanignore` the cache. SDK cache exceptions in submodule examples do not apply to this external srclib. Only `ios` currently needs platform removal. Consult the [field reference](https://f-droid.org/docs/Build_Metadata_Reference/).

4. **Test using fdroidserver.** On Linux, or Docker Desktop with `--platform linux/amd64` on an ARM Mac, use the [official buildserver container](https://f-droid.org/en/docs/Submitting_to_F-Droid_Quick_Start_Guide/):

   ```sh
   git clone --depth=1 https://gitlab.com/fdroid/fdroidserver ~/fdroidserver
   docker run --rm -it --user vagrant --entrypoint /bin/bash \
     -v "$HOME/fdroiddata:/build" \
     -v "$HOME/fdroidserver:/home/vagrant/fdroidserver" \
     registry.gitlab.com/fdroid/fdroidserver:buildserver
   ```

   Inside the container:

   ```sh
   . /etc/profile
   export PATH=/home/vagrant/fdroidserver:$PATH
   export PYTHONPATH=/home/vagrant/fdroidserver
   export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
   cd /build
   fdroid readmeta
   fdroid rewritemeta dev.spandankumar.glyph
   fdroid lint dev.spandankumar.glyph
   fdroid checkupdates --allow-dirty dev.spandankumar.glyph
   fdroid build -v -l dev.spandankumar.glyph
   ```

   Fix scanner/build failures rather than bypassing checks. Confirm APK name/code and test it on hardware. Reproducible signing additionally needs successful signature verification, not just compilation.

5. **Check listing and declarations.** F-Droid imports descriptions, icon and screenshots from tagged `fastlane/metadata/android/en-US/`; no duplicate YAML description is needed. Changelog `2012.txt` matches the APK code and is identical to `12.txt`. TODO: remove the short description’s trailing dot in a future upstream change. Declare **NonFreeNet** for promoting Discord/GitHub and optional GitHub Pages catalog downloads. Optional links still count as promotion under [current rules](https://f-droid.org/en/docs/Anti-Features/). Open-Meteo alone does **not** warrant NonFreeNet: its server is [AGPL and self-hostable](https://github.com/open-meteo/open-meteo). Weather/air-quality requests happen only after the user chooses those cards/places. Disclose hardcoded endpoints for TetheredNet review. No evidence currently warrants Ads, Tracking or NonFreeDep; local playback works without proprietary players. Reviewers will ask about permissions, optional network traffic, plugin binaries/licenses, fonts/art provenance, versioning, signing and hardware testing.

6. **Open the merge request.** Remove drafting comments, commit only the metadata in your fork as `New App: Glyph`, push `glyph`, inspect/fix its GitLab CI pipeline, then open an MR targeting fdroiddata `master`. Include build logs, signing choice, declarations and this disclosure; respond to reviewers. Recheck AI rules: [interim proposal #699](https://gitlab.com/fdroid/admin/-/issues/699) explicitly concerns F-Droid contributions, not app-inclusion approval.

> Glyph was developed with substantial help from AI coding assistants—Claude Code and OpenAI Codex—under the maintainer’s direction and review. The code is released under the MIT license and is tested by CI and on real WLED hardware. The maintainer takes responsibility for reviewing the implementation, dependencies, licensing and submitted metadata, and for addressing review findings. This submission draft also used AI assistance.
