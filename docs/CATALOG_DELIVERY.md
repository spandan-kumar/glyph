# Animation catalog delivery

Signed, static, offline-first. A manifest signed with Ed25519 authenticates a
payload; the app verifies both before parsing anything. The client ships
switched on (`RemoteCatalog.defaultUrl` is the Pages site) but stays inert
until the maintainer replaces the placeholder public key in
`lib/library/catalog_key.dart` (see Maintainer setup). No APK version bump or
release is part of this work.

## In the app

Glyph menu → New animations offers a manual check and a daily-check toggle
(off by default). Checks contact the named static host, without device IDs,
notification content, analytics or accounts. The only request headers are the
standard `If-None-Match` conditional header. Downloaded looks are cached and
available offline.

Daily means at most one automatic attempt per 24 hours, persisted across
restarts, including unsuccessful attempts. Checks run while Glyph is open or
on resume when due; there is no background service, wakeup or notification.

Bundled content paints first. Startup then re-verifies the cache (signature
and hash) without contacting the host. `CatalogStore` installs the staged
sprites and rebuilds AppScope. Favourites, recents, Glance rotations,
creations, current playback and live streams keep working: every lookup of a
catalog item is null-safe, so a retired item is skipped (Glance shows
"Unavailable", rails omit it) and reappears if a later catalog restores it.

## Delivery format

Site layout (all under `https://spandan-kumar.github.io/glyph/`):

| File | Purpose |
| --- | --- |
| `manifest-v1.json` | Signed metadata: `schema`, `revision`, `epoch`, `minApp`, `payload`, `sha256`, `size`, `revoked`, `published` |
| `manifest-v1.json.sig` | Base64 Ed25519 signature over `"glyph-catalog-manifest-v1\n"` + the exact manifest bytes |
| `payload/<sha256>.json` | The catalog (schema `version: 1`), content-addressed so a CDN can never pair a new manifest with an old payload |
| `previous-manifest-v1.json(.sig)` | The previously published signed manifest, kept for rollback; its payload stays in `payload/` |
| `index.html`, `.nojekyll` | Landing page |

Client check order: fetch the manifest (with `If-None-Match`; a 304 ends the
check), fetch the signature, verify the signature with the compiled-in key,
apply the `minApp` gate and freshness rule, then download the payload only if
its `sha256` differs from the cache, verify size and SHA-256, and only then
parse. Verification and parsing run in `Isolate.run` (pure-Dart Ed25519 from
the `cryptography` package); the UI isolate never decodes the catalog. The
cache holds raw verified bytes (`remote_catalog.meta` plus
`remote_catalog.<sha>.payload`, switched by one atomic rename).

Rules the client enforces:

- **Freshness**: accept only `revision` greater than the cached one, or the
  same `revision` with a higher `epoch` (the rollback path). Anything else is
  treated as stale and ignored; the cache is kept.
- **minApp**: a manifest needing a newer app is refused ("needs a newer
  version of Glyph"); the library is untouched.
- **Takedown**: `revoked` lists item ids or generator ids (`sprite:x`).
  Matching items are hidden whether they are downloaded or bundled, so
  infringing bundled art can be pulled without an app update.
- **No overrides**: a downloaded item whose id already exists in the bundled
  catalog is ignored; the only way to change or remove bundled content is
  `revoked`. A downloaded sprite that conflicts with a bundled drawing is
  dropped with its items.
- **Per-entry rejection**: an invalid or conflicting item, sprite, pack or
  category is dropped and listed (Glyph menu → New animations shows the
  count); the rest of the catalog still applies. Only schema and resource-limit
  violations reject the whole document.
- **One baseline**: validation always uses the bundled catalog, on cold start
  and in session.
- **HTTP**: https redirects only, to the same host or `*.github.io`, at most
  three hops; every body is capped while streaming (decoded bytes, so gzip
  bombs are cut off); eight-second total deadline; manifest at most 64 KiB,
  payload at most 2 MiB and exactly `size` bytes.

Schema bounds: 2,000 items, 32 packs, 512 sprites, 8,192 frames overall, 64
frames per sprite, 256 sequence steps, 2 Mi decoded pixels overall; rows at
most 256×64 and 8,192 pixels per frame; parts, colours, patches, metadata and
nesting are bounded before sprite expansion. Device GIF encoding still caps
each wait at one second. Unknown generators, palettes and asset types are
skipped with reasons.

## Building

`revision` and `minApp` live in `assets/catalog/content_revision.json`;
takedowns in `assets/catalog/revoked.json`.

```sh
python3 skills/glyph-animation/scripts/validate_sprite.py --all
dart run tool/build_sprites.dart
dart run tool/build_catalog.dart
dart run tool/build_remote_catalog.dart --published build/published
```

`--published` is a mirror of the live site (`tool/fetch_published_catalog.sh`
creates it; a 404 means "nothing published yet", any other failure aborts so a
hosting hiccup cannot discard the previous artifact). The builder verifies the
published manifests against the app key, enforces that a changed catalog or
takedown bumps `revision`, that published sprite and item ids keep their
meaning (changed art needs new ids), and that `revoked` ids are never silently
dropped (`--allow-unrevoke` for a deliberate restore). It keeps the previous
signed set as `previous-*`. It writes an **unsigned** manifest to
`build/catalog-site/`; `tool/catalog_sign.dart` signs it in the protected job
and verifies the result against the key compiled into the app.

Size budget: the full payload is about 0.94 MiB against the 2 MiB cap. CI
prints a warning at 70% and fails at 90%. We publish the full catalog rather
than a delta against the bundled one because installed apps have different
bundled contents; when the warning fires, split the payload.

`minApp` is the lowest `X.Y.Z` allowed to use the payload. Set it to the first
release that contains the verifying client, and raise it for content that
needs newer generators.

## Maintainer setup (one time, by hand)

1. Generate the signing key on a trusted machine:
   `dart run tool/catalog_keygen.dart` (or `--out path`). The private key
   (base64 32-byte seed) goes only to that file, default
   `./catalog-signing-key.txt`, which is git-ignored; it is never printed. The
   tool prints the public key.
2. Paste the public key into `lib/library/catalog_key.dart`
   (`catalogPublicKey`) and commit it. While the placeholder is there, the
   client does not contact the host and ignores any cache, and the workflow
   cannot sign.
3. In GitHub: Settings → Environments → New environment `catalog`. Add
   **required reviewers** (and yourself), restrict **deployment branches** to
   `main`, and add the secret `CATALOG_SIGNING_KEY` with the key file's
   contents to this environment only (not a repository secret). Back the key
   up in a password manager, then delete the local file.
4. Settings → Pages → Source: **GitHub Actions**. The `github-pages`
   environment should also be limited to `main`.
5. Optionally pin the actions in `catalog.yml` to commit SHAs.

Key rotation: generate a new pair, ship an app release with the new public key
first, wait for adoption, then switch the secret. Older apps stop trusting new
catalogs, so keep the old key for as long as you want them updated.

## Runbook

**Publish.** Merge catalog changes to `main` with a bumped `revision`. The
workflow validates and tests (`build` job, no secrets), then pauses at the
`catalog` environment until a reviewer approves; `sign` signs and verifies;
`deploy` publishes to Pages. Check
`https://spandan-kumar.github.io/glyph/manifest-v1.json` afterwards. A manual
run (Actions → Animation catalog → mode **publish**, branch main) does the
same. Identical reruns keep the existing signed manifest.

**Takedown** (infringing or harmful art, bundled or downloaded): add the item
ids (or `sprite:<id>`) to `assets/catalog/revoked.json`, remove the content if
it is downloaded-only, bump `revision`, merge, approve. Clients hide the items
on their next check (within a day if daily checks are on). Bundled art should
also be removed in the next app release; keep the id revoked until then.

**Rollback.** Actions → Animation catalog → Run workflow on `main` → mode
**rollback**. No HEAD build or tests run. The job mirrors the live site,
verifies both sets, and re-signs the previous content with the same `revision`
and `epoch + 1` (union of both `revoked` lists, so nothing is un-revoked),
then waits for `catalog` approval and deploys. Clients accept it because the
epoch is higher; they never accept an older epoch. A second rollback restores
the other content. The next normal publish needs `revision` above the rolled
back one. For older recovery, restore a retained Actions artifact
(`catalog-signed-<run>`, 90 days) through the same process.

**Sequencing with app releases.** Ship the app that contains the verifying
client and the real public key first; only then publish the first catalog
(until then nothing consumes it). For content that needs new generators or
sprite features, release the app first and publish the catalog with a higher
`minApp` afterwards; older apps then keep their current library and show the
"needs a newer version" message instead of dropping entries. Never publish
content that a released app cannot handle without raising `minApp`.

## Staging and tests

A test build can target another deployment and key:

```sh
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=GLYPH_CATALOG_URL=https://example.github.io/glyph-staging/ \
  --dart-define=GLYPH_CATALOG_PUBLIC_KEY=<base64 test public key>
```

Tests (`test/library`, `test/tool`) use ephemeral test keys and cover: valid,
invalid, tampered and placeholder-key signatures; hash and size mismatch;
revision/epoch ordering and replay; `minApp`; 304 and payload skipping; the
redirect policy; byte caps including a real gzip bomb; revoked bundled and
downloaded items; per-entry rejection; no bundled overrides; cache
re-verification and source binding; publication rules, previous retention and
rollback; keygen never printing the private key; and a retired favourite used
in a Glance rotation.

GitHub execution of the workflow, the environment approval and the live HTTPS
artifact remain unverified until the maintainer completes setup.
