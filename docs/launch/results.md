# Launch results

What each post or pitch did, from public counts only (Glyph has no
analytics). Add a row the day something goes out, then fill in the 7-day
deltas a week later. Plan and targets: [OUTREACH.md](OUTREACH.md#metrics-public-counts-only-no-analytics-ever).

How to read the counts:

```bash
gh api repos/spandan-kumar/glyph/traffic/views --jq '"views \(.count) uniques \(.uniques)"'
gh api repos/spandan-kumar/glyph/traffic/popular/referrers
gh api repos/spandan-kumar/glyph --jq .stargazers_count
gh api repos/spandan-kumar/glyph/releases --jq '[.[].assets[]|select(.name|endswith(".apk"))|.download_count]|add'
```

GitHub keeps traffic for 14 days only, so record it within the week.

## Baseline

| Date | Stars | 14-day views / uniques | APK downloads (current releases) | Discord members |
|---|---|---|---|---|
| 22 Oct 2026 | 2 | 83 / 14 | 24 | — |

## Posts and pitches

| Date | Venue | Link | Asset | Comments / replies | Stars +7d | Uniques +7d | Downloads +7d | Notes |
|---|---|---|---|---|---|---|---|---|
| 19 Oct | WLED-Docs compatible software | [wled/WLED-Docs#383](https://github.com/wled/WLED-Docs/pull/383) | — | maintainer review, open | | | | listing pending; moved to Sources |

## Gatekeeper wins

Creator videos, vendor or kit-maker links, docs listings. One line each with
the date and link.

- (none yet)
