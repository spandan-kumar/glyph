# F-Droid submission

**Submitted 18 October 2026:** [fdroid/fdroiddata!53046](https://gitlab.com/fdroid/fdroiddata/-/merge_requests/53046)
from the `glyph` branch of `spandankumar9/fdroiddata`. The fork's pipeline
can't run until a maintainer triggers it (new GitLab accounts get no shared
runners without identity verification); a note on the MR asks for that.

The recipe is [`fdroid/dev.spandankumar.glyph.yml`](fdroid/dev.spandankumar.glyph.yml).
It targets **v1.4.9**, arm64, and is checked by the manual **F-Droid check**
workflow (`.github/workflows/fdroid-check.yml`), which runs fdroiddata's own
lint, `rewritemeta` and `fdroid build --on-server` steps in F-Droid's
buildserver image against any commit. Run it from the Actions tab before every
recipe change.

## Decisions (October 2026)

- **F-Droid signs its build.** fdroidserver rejects APKs whose v2 and v3
  certificates differ, which is exactly our rotated signature
  ([SIGNING.md](../SIGNING.md)), and an F-Droid build isn't byte-identical to
  the GitHub APK anyway. The recipe therefore has no `Binaries` or
  `AllowedAPKSigningKeys`. Moving between the GitHub/Obtainium build and the
  F-Droid build needs an uninstall and reinstall; say so in the README once
  the listing is live.
- **The imported collection is included** and declared as **NonFreeAssets**:
  it's shared with its creator's permission, not under a free licence, and
  may show third-party characters. Reviewers may ask about it; the answer is
  the paragraph under "Merge request" below.
- **NonFreeNet** covers the Discord and GitHub links and the optional GitHub
  Pages catalog. Open-Meteo is AGPL and self-hostable, so it doesn't count.
- **`scanignore: catalog_assets/imported`**: the scanner flags every gzip file
  as an archive. These 12,273 files are GLC1 animation data (a header plus
  raw RGB frames, gzip-compressed), documented in
  [IMPORTED_COLLECTION.md](../IMPORTED_COLLECTION.md); nothing in them is
  executed.
- **First version: 1.4.9**: the first release without the collection's former
  source name in code or assets (1.4.8) and with the permanent Discord invite. F-Droid builds the tagged source exactly.
- Version codes: Flutter's `--split-per-abi` gives arm64 `2000 + N`
  (`VercodeOperation: '%c + 2000'`), matching the `changelogs/<2000+N>.txt`
  files the release checklist already writes.

## Steps

1. **Release 1.4.9** per AGENTS.md, then run the F-Droid check on `v1.4.9`.
   It must finish with a built APK.
2. **Fork** <https://gitlab.com/fdroid/fdroiddata> (needs a GitLab account),
   branch `glyph`, and add `metadata/dev.spandankumar.glyph.yml` exactly as in
   this repo (no drafting comments).
   ```bash
   git clone --depth 50 https://gitlab.com/<your-gitlab-username>/fdroiddata.git
   cd fdroiddata && git checkout -b glyph
   cp ~/github.com/spandan-kumar/glyph/docs/launch/fdroid/dev.spandankumar.glyph.yml metadata/
   git add metadata/dev.spandankumar.glyph.yml
   git commit -m "New App: dev.spandankumar.glyph"
   git push -u origin glyph
   ```

3. **Commit** as `New App: dev.spandankumar.glyph` and open the merge request
   with the text below. fdroiddata's pipeline builds it again; fix anything it
   reports here first, rerun the check, then update the fork.
4. **Answer review** promptly. After merge, F-Droid publishes within a few
   days, and `AutoUpdateMode: Version` picks up each new `vX.Y.Z` tag.

## Merge request

Title: `New App: Glyph (dev.spandankumar.glyph)`

> Glyph is a free, open-source (MIT) Android app for WLED LED matrices: guided
> device setup, live streaming of effects over the local network, a pixel
> editor, clocks, a music visualiser and games. No account, no tracking.
>
> - Source: https://github.com/spandan-kumar/glyph · Flutter 3.47.6, built from
>   source with the `flutter` srclib. All 124 pub dependencies are FLOSS; no
>   Google Play Services, Firebase or proprietary SDKs.
> - Listing text, icon and screenshots come from upstream fastlane metadata.
> - **NonFreeAssets:** the app bundles an imported pixel-art collection
>   (12,361 animations, stored as 12,273 distinct files) included with its creator's permission but not under
>   a free licence. The code and the rest of the art (original, CC0 and
>   public-domain) are free.
> - **scanignore `catalog_assets/imported`:** those files are animation data,
>   gzip-compressed RGB frames in a documented format
>   (`docs/IMPORTED_COLLECTION.md`), not code or libraries.
> - **NonFreeNet:** links to Discord and GitHub; optional catalog updates from
>   GitHub Pages. Device control works fully offline on the local network.
> - Builds arm64 only for now. Built and verified in fdroidserver's
>   buildserver image with fdroiddata's CI steps before submission.
> - I'm the developer and agree to the inclusion.

Tick the merge request template's checklist items honestly; the "builds from
source" and "no proprietary dependencies" items are true.
