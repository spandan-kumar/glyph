Glyph’s F-Droid submission draft targets **v1.4.0, arm64 only**. It follows the current [Flutter template](https://gitlab.com/fdroid/fdroiddata/-/blob/master/templates/build-flutter.yml), [Flutter srclib](https://gitlab.com/fdroid/fdroiddata/-/blob/master/srclibs/flutter.yml), and examples from [LocalSend](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/org.localsend.localsend_app.yml), [Ente Photos](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/io.ente.photos.fdroid.yml) and [Energize](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/com.flasskamp.energize.yml). This is an untested packaging draft, not proof of a successful F-Droid build.

1. **Choose signing before publication.** Recommend attempting reproducible builds with Glyph’s existing release signature first: users can update between GitHub/Obtainium and F-Droid, and F-Droid verifies the release against source. The YAML’s baseline uses F-Droid signing while testing the recipe. For upstream signing, uncomment `Binaries` and `AllowedAPKSigningKeys`, replace the TODO with the release certificate’s SHA-256 fingerprint (64 lowercase hex digits), and verify the APK is production-signed; the release workflow now fails if signing secrets are absent or the tag differs from the pubspec version. Read it with `apksigner verify --print-certs glyph-1.4.0-arm64-v8a.apk`; the `.sha256` download is a file hash, not a certificate fingerprint. Match CI’s project/SDK paths, JDK, NDK and lockfile where differences require it; inspect failures with diffoscope. Never give F-Droid the private key. If reproducibility remains impractical, leave both fields absent and choose F-Droid signing, accepting that switching signatures requires uninstall/reinstall and data backup. Failed verification with `Binaries` prevents publication; it does not silently fall back. See [reproducible builds](https://f-droid.org/en/docs/Reproducible_Builds/).

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
