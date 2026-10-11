# Community drawings

Draw on Glyph's canvas, tap **Share with the community**, and review the
prefilled GitHub issue before submitting it. You'll need a GitHub account.
The form includes the drawing as one `glyph-design:1:` text token. Leave
that field as Glyph filled it in; you can choose a credit name or leave it
empty to use your GitHub username.

The drawing is released under CC0 1.0: anyone may use it, without requiring
credit. Glyph still shows a friendly creator credit. Share only work you drew
yourself, without trademarked or copyrighted characters, logos, hateful or
adult content.

## From drawing to everyone's library

1. The `community-design` issue form records the name, token, optional
   credit and required authorship/licensing confirmations.
2. `community-check.yml` validates the token and posts or updates one preview
   comment. Valid submissions receive `ready-for-review`; damaged or unusable
   drawings receive `needs-changes` and instructions to share again.
3. A repository admin or maintainer reviews the work and adds `approved`.
   Other users' approval labels are removed. An issue edit removes approval,
   so changed work needs another review.
4. `community-approve.yml` rechecks the approved body, parses credit in Dart,
   adds the sprite to `community.json`, regenerates the sprite data and
   catalog, validates and tests them, and opens a `community/<issue>` PR.
   Its body links and closes the submission, and includes the preview.
5. The maintainer reviews the diff and merges. The bot has already bumped
   the content revision.
   The existing protected catalog workflow signs and publishes the catalog
   after a separate maintainer approval. See [catalog delivery](CATALOG_DELIVERY.md).
6. Apps receive the drawing on their next successful catalog check: manually,
   or on a due daily check if enabled. No app release is needed.

The CLI creates the Community pack only on its first addition. The category
appears first when populated. IDs use `community-<title slug>-<issue number>`;
the slug is at most 30 ASCII letters/digits with single dashes. Duplicate IDs
are refused. Colliding titles gain ` by <creator>` (and an issue-number
suffix if that also collides). Credit strips markup and controls and is
limited to 40 characters. The original issue is the public provenance record;
Community sources omit imported-file download/hash fields.

## Moderation runbook

Before adding `approved`, review the actual issue body and animated preview:

- Confirm the authorship and CC0 boxes are checked and the drawing is their
  own work. A valid token alone does not prove authorship or permission.
- Reject trademarked/copyrighted characters, logos, text slurs, hateful or
  adult content. Review every frame, including brief flashes.
- Check that the subject reads at 16×16; fine details and dark fills can
  disappear on LEDs. Prefer a simple shape and a clean loop.
- Check the title and requested credit for impersonation, spam or abusive
  language. The encoded title is the catalog title; the form's name field
  does not override it.

**Approve:** add `approved`. Review the generated PR, including its source
notice and every generated change. The bot bumps `revision` in
`assets/catalog/content_revision.json`; if another catalog change merged
after the PR opened, bump it once more so it stays above the published
revision. Merge several submissions one at a time. Full CI is
not triggered by PRs opened using `GITHUB_TOKEN`; the approval workflow runs
analysis, sprite validation and sprite/library/tool tests itself. A maintainer
push can trigger the normal CI workflow. Approving the issue does not approve
catalog signing or publication.

**Needs a fix:** comment with a concrete suggestion. Ask the creator to open
the drawing in Glyph and share again, replacing the issue's design field.
The bot updates its preview comment after edits. Remove/re-add `approved`
only after reviewing the new submission.

**Reject:** explain briefly, then close the issue with **not planned**.

**Takedown after publishing:** add the catalog item ID or `sprite:<sprite-id>`
to `assets/catalog/revoked.json`, bump the content revision, and follow the
[takedown runbook](CATALOG_DELIVERY.md#runbook). Keep the ID revoked as directed
there; clients hide it on their next check.

If a workflow fails, inspect its Actions log, fix the cause and rerun it.
An existing PR is reused rather than overwritten; update that PR manually if
its drawing must change. Never overwrite another maintainer's branch work.

## Repository setup

Enable Actions and **Allow GitHub Actions to create and approve pull requests**
in Settings → Actions → General. The workflows create `needs-changes`,
`ready-for-review` and `approved` if missing; create `community-design` once
so the issue form can apply it. `approved` is an admin/maintainer action.

Previews are published to the orphan `community-previews` branch at
`<issue>/<run-id>-<attempt>.gif` and embedded from raw.githubusercontent.com.
The branch contains public GIFs only; it has no app code or main history.
Keep main's normal protections. Branch rules must permit the Actions token to
write `community-previews` and create `community/*` branches, and permit the
bot PR to be reviewed with the approval workflow's checks. GitHub's contents
permission is repository-wide; the check workflow's writes are explicitly
restricted in code to the preview branch. No additional secret is needed.

## Privacy and limits

Submitting publishes the drawing, title and credit on GitHub under your
account. Glyph only opens the prefilled URL; the app sends nothing itself.
GitHub stores the public issue and preview. Share no personal details you
want to keep private. There is no Glyph submission server, account system
or telemetry.

The shared token supports dimensions from 1×1 through 64×64 (at most 4,096
pixels), up to 48 frames, up to 62 non-black colours, a title of at most 40
characters, and frame delays from 20 to 10,000 ms. Black pixels are off;
excess colours are merged by Glyph when sharing. The token is limited to
60,000 encoded characters and 400,000 inflated bytes. When a design is too
long for a link, Glyph copies it and asks you to paste it into the Design
box. Previews enlarge pixels up to eight times, reducing that
scale for maximum-size animations to fit the encoder's memory budget.
Blank or entirely near-black drawings are refused. Three consecutive
apostrophes in a title are refused by the existing sprite compiler; rename
and share again. Sent device GIFs cap each frame delay at one second.

Moderation is manual; validation checks the format, not content or rights.
Catalog-wide limits and publication size budgets still apply. Publication
can wait for review and is never guaranteed.
