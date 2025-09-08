# AURORA

Caffeine + sleep tracker with a computed alertness score and aurora background.

## Contribution graph "Starry Night" (optional)

Generate a 7×52 pixel grid inspired by Starry Night and (optionally) paint your GitHub contribution graph using backdated commits.

Preview grid:

```
npm run contrib:grid
```

Plan for a given year:

```
YEAR=2025 npm run contrib:plan
```

Paint (creates many commits, dry‑run without `--yes`):

```
node scripts/paint-contribs.js --year=2025         # dry-run
node scripts/paint-contribs.js --year=2025 --yes   # performs commits in this repo
```

Tip: Use a dedicated repo if you don’t want to clutter this project’s history.
