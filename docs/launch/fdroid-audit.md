# Glyph F-Droid inclusion audit

2026-10-11 · `dev.spandankumar.glyph` · `1.4.0+12` (`pubspec.yaml:19`). **Likely eligible; reproducibility unproven.** [Policy](https://f-droid.org/docs/Inclusion_Policy/) permits official Flutter/Android binaries and freely licensed trusted-Maven artifacts, forbids proprietary SDKs, and requires licensed assets.

## Dependency audit

All 124 lock entries reviewed against cached source/licenses: MIT/BSD/Apache, except `dbus` MPL-2.0; SDK packages are Flutter BSD. No GMS, Firebase, Play Core, ML Kit, analytics/crash SDK, or proprietary runtime binary found. `leak_tracker` is test tooling, not telemetry. Complete inventory below: `package@version:pubspec.lock-line`; **OK** applies to each, including non-Android implementations/interfaces.

```text
android_file_picker@2.0.0:4 archive@4.3.0:12 args@2.7.0:20 async@2.13.1:28 bonsoir@7.1.5:36
bonsoir_android@7.1.3:44 bonsoir_darwin@7.1.1:52 bonsoir_linux@7.1.0:60 bonsoir_platform_interface@7.0.0:68 bonsoir_windows@7.3.0:76
boolean_selector@2.1.2:84 characters@1.4.1:92 clock@1.1.3:100 code_assets@1.2.1:108 collection@1.19.1:116
cross_file@0.3.5+5:124 crypto@3.0.7:132 cryptography@2.9.0:140 cupertino_icons@1.0.9:148 dbus@0.7.15:156
fake_async@1.3.3:164 ffi@2.2.0:172 ffi_leak_tracker@0.1.2:180 fftea@1.5.0+1:188 file@7.0.1:196
file_picker@13.1.0:204 file_picker_darwin@2.1.2:212 file_picker_linux@2.0.0:220 file_picker_platform_interface@4.0.0:228 file_picker_web@4.0.0:236
fixnum@1.1.1:244 flutter@0.0.0:252 flutter_foreground_task@11.0.3:257 flutter_lints@6.0.0:265 flutter_test@0.0.0:273
flutter_web_plugins@0.0.0:278 home_widget@0.10.0:283 hooks@2.0.2:291 http@1.6.0:299 http_parser@4.1.2:307
image@4.10.1:315 jni@1.1.0:323 jni_flutter@1.0.3:331 jni_util@1.0.0:339 leak_tracker@11.0.2:347
leak_tracker_flutter_testing@3.0.10:355 leak_tracker_testing@3.0.2:363 lints@6.1.0:371 logging@1.3.0:379 matcher@0.12.20:387
material_color_utilities@0.13.0:395 meta@1.18.3:403 mime@2.1.0:411 objective_c@9.5.0:419 package_config@3.0.0:427
package_info_plus@10.2.2:435 package_info_plus_platform_interface@4.1.0:443 path@1.9.1:451 path_provider@2.1.6:459 path_provider_android@2.3.1:467
path_provider_foundation@2.6.0:475 path_provider_linux@2.2.2:483 path_provider_platform_interface@2.1.3:491 path_provider_windows@2.3.0:499 permission_handler@13.0.2:507
permission_handler_android@13.0.1:515 permission_handler_apple@9.6.2:523 permission_handler_html@0.1.4+1:531 permission_handler_platform_interface@4.4.1:539 permission_handler_windows@0.2.2:547
petitparser@7.0.2:555 platform@3.2.0:563 plugin_platform_interface@2.1.8:571 posix@6.5.2:579 pub_semver@2.2.1:587
record@7.1.1:595 record_android@2.2.0:603 record_ios@2.1.1:611 record_linux@2.1.2:619 record_macos@2.1.1:627
record_platform_interface@2.1.0:635 record_use@0.6.0:643 record_web@2.1.3:651 record_windows@2.3.0:659 share_plus@13.3.1:667
share_plus_platform_interface@7.2.0:675 shared_preferences@2.5.5:683 shared_preferences_android@2.4.28:691 shared_preferences_foundation@2.5.7:699 shared_preferences_linux@2.4.1:707
shared_preferences_platform_interface@2.4.2:715 shared_preferences_web@2.4.3:723 shared_preferences_windows@2.4.1:731 sky_engine@0.0.0:739 source_span@1.10.2:744
stack_trace@1.12.2:752 stream_channel@2.1.4:760 string_scanner@1.4.1:768 term_glyph@1.2.2:776 test_api@0.7.12:784
typed_data@1.4.0:792 url_launcher@6.3.3:800 url_launcher_android@6.3.33:808 url_launcher_ios@6.4.2:816 url_launcher_linux@3.2.3:824
url_launcher_macos@3.2.6:832 url_launcher_platform_interface@2.3.2:840 url_launcher_web@2.4.3:848 url_launcher_windows@3.1.6:856 uuid@4.6.0:864
vector_math@2.4.0:872 vm_service@15.3.0:880 wakelock_plus@1.8.0:888 wakelock_plus_platform_interface@1.7.0:896 web@1.1.1:904
webview_flutter@4.14.1:912 webview_flutter_android@4.14.1:920 webview_flutter_platform_interface@2.15.1:928 webview_flutter_wkwebview@3.27.0:936 win32@6.4.0:944
windows_file_picker@2.0.0:952 xdg_directories@1.1.0:960 xml@7.0.1:968 yaml@3.1.4:976
```

Android evidence: `G(p)` = `~/.pub-cache/hosted/pub.dev/<p>-<locked-version>/android/build.gradle` (`.kts` where applicable). Wrappers inherit their implementation verdict. No proprietary-dependency exclusion flag needed.

| Plugin/implementation | Verdict | Gradle evidence; packaged dependencies |
|---|---|---|
| android_file_picker | OK | G:90; core/core-ktx 1.18.0, annotation 1.10.0, lifecycle-runtime 2.10.0 |
| bonsoir_android | OK | G:11; platform NSD |
| flutter_foreground_task | OK | G:46; coroutines 1.9.0, core-ktx 1.15.0 |
| home_widget | OK | G:61; Kotlin 1.9.0, Glance 1.2.0, core 1.13.1, Work 2.11.2, coroutines 1.10.2 |
| jni | OK; needs Gradle flag if differing | G:52; source CMake, see reproducibility |
| jni_flutter | OK | G:20; source Java bridge |
| package_info_plus | OK | G:25; platform APIs |
| path_provider_android | OK | pubspec.yaml:16,21; Dart JNI, no Android Gradle file |
| permission_handler_android | OK | G:22; platform permissions, no GMS location |
| record_android | OK | G:49; platform audio, test-only dependencies |
| share_plus | OK | G:66; core-ktx 1.16.0, annotation 1.9.1, coroutines 1.11.0 |
| shared_preferences_android | OK | G:61; Datastore 1.1.7, preference 1.2.1 |
| url_launcher_android | OK | G:73; core 1.17.0, annotation 1.10.0, browser 1.9.0 |
| wakelock_plus | OK | G:38; test-only dependencies |
| webview_flutter_android | OK | G:55; annotation 1.10.0, WebKit 1.15.0; platform WebView |

AndroidX/Kotlin dependencies are FLOSS; `google()` alone does not mean Play Services. Build/test dependencies are FLOSS, excluded from APK runtime: JUnit 4.13.2; Mockito 5.0.0/5.2.0/5.23.0; Robolectric 4.14.1/4.16; MockK 1.14.11; JUnit-Vintage 5.11.4; AndroidX-test core/core-ktx 1.7.0, junit-ktx 1.3.0; kotlin-test inherits Kotlin.

Complete cached Maven inventory (151 coordinate/version combinations; slash-separated versions reflect different plugin graphs): **OK**. Evidence: `build/<plugin>/intermediates/lint_model/release/generateReleaseLintModel/release-artifact-dependencies.xml:3` and matching `~/.gradle/caches/modules-2/files-2.1/<group>/<artifact>/<version>/*/*.pom` licenses. 147 Apache, two protobuf BSD; Guava/Flutter POMs omit licenses, but upstream licenses are Apache/BSD. These caches accompany **1.3.6**, not a fresh 1.4.0 resolution (`build/app/outputs/apk/release/output-metadata.json:19`); revalidate before submission.

```text
androidx.activity:activity@1.8.1/1.9.0 androidx.activity:activity-ktx@1.8.1 androidx.annotation:annotation-experimental@1.4.0/1.4.1
androidx.annotation:annotation-jvm@1.10.0/1.8.1/1.9.1 androidx.appcompat:appcompat@1.1.0 androidx.appcompat:appcompat-resources@1.1.0
androidx.arch.core:core-common@2.2.0 androidx.arch.core:core-runtime@2.2.0 androidx.asynclayoutinflater:asynclayoutinflater@1.0.0
androidx.browser:browser@1.9.0 androidx.collection:collection@1.1.0 androidx.collection:collection-jvm@1.4.2/1.4.3/1.4.4
androidx.collection:collection-ktx@1.1.0/1.4.3/1.4.4 androidx.compose.runtime:runtime-android@1.7.8 androidx.compose.ui:ui-geometry-android@1.6.0/1.6.8
androidx.compose.ui:ui-graphics-android@1.6.0/1.6.8 androidx.compose.ui:ui-unit-android@1.6.0/1.6.8 androidx.compose.ui:ui-util-android@1.6.8
androidx.concurrent:concurrent-futures@1.1.0 androidx.concurrent:concurrent-futures-ktx@1.1.0 androidx.coordinatorlayout:coordinatorlayout@1.0.0
androidx.core:core@1.13.1/1.15.0/1.16.0/1.17.0/1.18.0 androidx.core:core-ktx@1.13.1/1.15.0/1.16.0/1.17.0/1.18.0/1.2.0/1.9.0 androidx.core:core-remoteviews@1.1.0
androidx.core:core-viewtree@1.0.0 androidx.cursoradapter:cursoradapter@1.0.0 androidx.customview:customview@1.0.0/1.1.0
androidx.datastore:datastore@1.0.0 androidx.datastore:datastore-android@1.1.7 androidx.datastore:datastore-core@1.0.0
androidx.datastore:datastore-core-android@1.1.7 androidx.datastore:datastore-core-okio-jvm@1.1.7 androidx.datastore:datastore-preferences@1.0.0
androidx.datastore:datastore-preferences-android@1.1.7 androidx.datastore:datastore-preferences-core@1.0.0 androidx.datastore:datastore-preferences-core-android@1.1.7
androidx.datastore:datastore-preferences-external-protobuf@1.1.7 androidx.datastore:datastore-preferences-proto@1.1.7 androidx.documentfile:documentfile@1.0.0
androidx.drawerlayout:drawerlayout@1.0.0 androidx.exifinterface:exifinterface@1.4.1 androidx.fragment:fragment@1.7.1
androidx.fragment:fragment-ktx@1.7.1 androidx.glance:glance@1.2.0 androidx.glance:glance-appwidget@1.2.0
androidx.glance:glance-appwidget-external-protobuf@1.2.0 androidx.glance:glance-appwidget-proto@1.2.0 androidx.interpolator:interpolator@1.0.0
androidx.legacy:legacy-support-core-ui@1.0.0 androidx.legacy:legacy-support-core-utils@1.0.0 androidx.lifecycle:lifecycle-common@2.7.0
androidx.lifecycle:lifecycle-common-java8@2.10.0/2.7.0 androidx.lifecycle:lifecycle-common-jvm@2.10.0 androidx.lifecycle:lifecycle-livedata@2.10.0/2.7.0
androidx.lifecycle:lifecycle-livedata-core@2.10.0/2.7.0 androidx.lifecycle:lifecycle-livedata-core-ktx@2.10.0/2.7.0 androidx.lifecycle:lifecycle-process@2.10.0/2.7.0
androidx.lifecycle:lifecycle-runtime@2.7.0 androidx.lifecycle:lifecycle-runtime-android@2.10.0 androidx.lifecycle:lifecycle-runtime-ktx@2.7.0
androidx.lifecycle:lifecycle-service@2.7.0 androidx.lifecycle:lifecycle-viewmodel@2.10.0/2.7.0 androidx.lifecycle:lifecycle-viewmodel-android@2.10.0
androidx.lifecycle:lifecycle-viewmodel-ktx@2.7.0 androidx.lifecycle:lifecycle-viewmodel-savedstate@2.7.0 androidx.lifecycle:lifecycle-viewmodel-savedstate-android@2.10.0
androidx.loader:loader@1.0.0 androidx.localbroadcastmanager:localbroadcastmanager@1.0.0 androidx.preference:preference@1.2.1
androidx.print:print@1.0.0 androidx.profileinstaller:profileinstaller@1.3.1/1.4.0 androidx.recyclerview:recyclerview@1.0.0
androidx.room:room-common-jvm@2.7.0 androidx.room:room-runtime-android@2.7.0 androidx.savedstate:savedstate@1.2.1
androidx.savedstate:savedstate-android@1.4.0 androidx.savedstate:savedstate-ktx@1.2.1 androidx.slidingpanelayout:slidingpanelayout@1.2.0
androidx.sqlite:sqlite-android@2.5.0 androidx.sqlite:sqlite-framework-android@2.5.0 androidx.startup:startup-runtime@1.1.1
androidx.swiperefreshlayout:swiperefreshlayout@1.0.0 androidx.tracing:tracing@1.2.0 androidx.tracing:tracing-ktx@1.2.0
androidx.transition:transition@1.4.1 androidx.vectordrawable:vectordrawable@1.1.0 androidx.vectordrawable:vectordrawable-animated@1.1.0
androidx.versionedparcelable:versionedparcelable@1.1.1 androidx.viewpager:viewpager@1.0.0 androidx.webkit:webkit@1.15.0
androidx.window.extensions.core:core@1.0.0 androidx.window:window@1.2.0 androidx.window:window-java@1.2.0
androidx.work:work-runtime@2.11.2 androidx.work:work-runtime-ktx@2.11.2 com.getkeepsafe.relinker:relinker@1.4.5
com.google.guava:listenablefuture@1.0 com.squareup.okio:okio-jvm@3.4.0 io.flutter:flutter_embedding_release@1.0.0-692136cb6582dbfc5af3fb33c2515a069f2f66d0
org.jetbrains.kotlin:kotlin-android-extensions-runtime@1.9.22 org.jetbrains.kotlin:kotlin-parcelize-runtime@1.9.22 org.jetbrains.kotlin:kotlin-stdlib@2.1.20/2.4.0
org.jetbrains.kotlin:kotlin-stdlib-jdk7@1.8.20/1.9.0 org.jetbrains.kotlin:kotlin-stdlib-jdk8@1.8.20/1.9.0 org.jetbrains.kotlinx:kotlinx-coroutines-android@1.10.2/1.11.0/1.7.1/1.7.3/1.8.1/1.9.0
org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm@1.10.2/1.11.0/1.7.1/1.7.3/1.8.1/1.9.0 org.jetbrains.kotlinx:kotlinx-serialization-core-jvm@1.7.3 org.jetbrains:annotations@23.0.0
org.jspecify:jspecify@1.0.0
```

## Anti-features

[Rules](https://f-droid.org/docs/Anti-Features/): **NonFreeNet likely** from promoted Discord invites (`lib/app/community.dart:15,24`); GitHub feedback/roadmap links also warrant disclosure (`:48,22`). Ordinary source links alone are weaker evidence. [Open-Meteo is AGPL/self-hostable](https://github.com/open-meteo/open-meteo), so not inherently NonFreeNet. Hardcoded weather endpoints (`lib/features/glance/weather_api.dart:122,177`; `air_quality_service.dart:33`) warrant endpoint configurability; optional cards mean Glyph does not depend entirely on them, making TetheredNet unlikely.

**Tracking: none identified.** Catalog checks default off (`lib/library/catalog_store.dart:61,78`), disclose IP visibility (`lib/ui/community/catalog_updates_screen.dart:102`); weather requires user-selected places and discloses requests (`glance_screen.dart:1173`). Feedback is user-triggered, not automatic crash reporting. Add fuller consent covering coordinates/IP/app-version. No Ads/NonFreeDep expected: WLED is FLOSS; Now Playing supports any player. Asset licensing still needs provenance verification.

## Reproducibility and signing

Exact Flutter **3.47.6**, Dart **3.13.5**: release/CI/catalog workflows `:24/:24/:49`; no `.fvmrc`/`.flutter-version`. `pubspec.yaml:22` and `pubspec.lock:984` constrain versions, not pin Flutter. Local SDK reports framework `5fc346839b5d0eef006ed8404392afb4dfae428d`, engine `692136cb6582dbfc5af3fb33c2515a069f2f66d0` (`~/development/flutter/bin/cache/flutter.version.json:5,7`); verify public tag correspondence.

Gradle **9.3.1** (`android/gradle/wrapper/gradle-wrapper.properties:5`), root AGP **9.1.0**/Kotlin **2.4.0** (`android/settings.gradle.kts:22`); plugins additionally declare AGP 8.0.2/8.1.2/8.5.2/8.6.0/8.12.1/8.13.1/**9.2.1**, Kotlin 1.8.22/1.9.0/2.2.0/2.3.0/2.3.20. Preserve resolved toolchains. Flutter defaults SDK/target **36**, minimum **24**, NDK **28.2.13676358** (`FlutterExtension.kt:23,26,34,42`); cached JNI used CMake **3.22.1**. JDK17/`ubuntu-latest` float (`release.yml:12,20`); Maven has no committed locks/checksums. Pub hashes are locked, but CI lacks `--enforce-lockfile` (`:60`).

Split arm64 adds 2000: **2012**, not 12 (`android/app/build.gradle.kts:34`; `release.yml:63`). Preserve this for signature-compatible updates; `VercodeOperation: ['2000 + %c']` with pubspec `UpdateCheckData`. Dropping splits to code 12 would downgrade existing installations.

[Current Flutter template](https://gitlab.com/fdroid/fdroiddata/-/raw/master/templates/build-flutter.yml) uses scanned project-local PUB_CACHE, enforced lockfile, SDK scan exceptions and cache scandelete; [srclib](https://gitlab.com/fdroid/fdroiddata/-/raw/master/srclibs/flutter.yml) clones public Flutter. Pin `flutter@3.47.6`, build the same arm64 command/output, and preserve scanner coverage. [LocalSend today](https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/org.localsend.localsend_app.yml) demonstrates matched paths, ABI builds and upstream signing.

[Reproducibility guidance](https://f-droid.org/docs/Reproducible_Builds/): compare clean Linux builds before claiming success. Cached APK contains baseline.prof/profm, VCS metadata, libapp/libflutter/libdartjni/libdatastore_shared_counter.so. JNI is source-built; Datastore native code is Apache. Check embedded paths/timestamps/build IDs, native stripping, CPU-sensitive profiles/R8, ZIP ordering and icon-font subsets (`pubspec.yaml:76`). Runtime DateTime/UUIDs do not imply build nondeterminism. Match SDK/CMake/NDK/paths; if JNI differs, configure its CMake linker `-Wl,--build-id=none` and prefix maps on both builds. Disable ArtProfile tasks or icon tree-shaking only if diffs justify it.

## Metadata

Under `fastlane/metadata/android/en-US`: title 5/50, short 73/80, full 3302/4000 characters; changelogs 5–12 are ≤500 (12.txt:389), but **2012.txt absent**. Images: icon 512×512, featureGraphic 1024×500, screenshots 1–8 PNG 450×1000. Valid [F-Droid formats/layout](https://f-droid.org/docs/All_About_Descriptions_Graphics_and_Screenshots/); no documented Play-style screenshot dimension restriction. Reword “no cloud” (`full_description.txt:33`) to disclose optional hosted services.

## Priorities / exact next steps

- **Must:** choose signing route. Own signature ([metadata fields](https://f-droid.org/docs/Build_Metadata_Reference/#allowedapksigningkeys)): fail CI when secrets absent (`release.yml:48`), add `fdroid=true` Gradle-property mode setting `signingConfig=null` instead of debug fallback (`android/app/build.gradle.kts:55`), build/sign from clean tag, add `Binaries: https://github.com/spandan-kumar/glyph/releases/download/v%v/glyph-%v-arm64-v8a.apk` and lowercase certificate SHA256 `AllowedAPKSigningKeys` from `apksigner verify --print-certs`. Validate with apksigcopier/diffoscope; pin external signing to build-tools34 per current warning. F-Droid signing: same unsigned recipe, omit Binaries/AllowedAPKSigningKeys; separate certificate prevents cross-channel updates. Matching upstream APK bytes is unnecessary for F-Droid signing; source buildability remains required. Secrets stay upstream.
- **Must:** submit fdroiddata recipe/license/source/AntiFeatures; freshly resolve `:app:dependencies --configuration releaseRuntimeClasspath`, run source/APK scans, verify every resolved license. Copy `12.txt` to `2012.txt`; retain base-code notes for GitHub.
- **Should:** pin Linux/JDK/SDK/CMake; commit Gradle locks/verification and wrapper checksum; enforce pub lock; make tag mismatch fatal (`release.yml:35`); perform two clean rebuilds and signature-copy verification. Declare NonFreeNet or remove/replace Discord promotion in both upstream and reproducible build.
- **Nice:** configurable weather/catalog endpoints, fuller privacy text, additional locale for Latest-tab eligibility.
