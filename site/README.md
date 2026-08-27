# Landing page

Single-file marketing site for Sift, hosted on Vercel from this folder.

- Source of truth: [`index.html`](index.html)
- Live at: https://sift.akakika.com (Vercel project `sift-site`, team `dot-realitytests-projects`; fallback https://sift-site-two.vercel.app)
- DNS: Cloudflare CNAME `sift` → `cname.vercel-dns.com`, DNS-only
- Config: [`vercel.json`](vercel.json) — `/Sift.dmg` and `/download` redirect to the
  current versioned DMG in [`downloads/`](downloads/)

The sift repo is private and the plan does not allow GitHub Pages on private repos,
so the page is deployed with the Vercel CLI instead (no separate public repo needed).

## Publish a change

```bash
cd site
vercel deploy --prod --yes      # first time: vercel link --yes --project sift-site
```

## On each release

`Scripts/release.sh` does steps 1–2 for you; only the deploy is by hand.

1. Copy the notarized DMG to `site/downloads/Sift-X.Y.Z.dmg` (it is committed — `.gitignore`
   un-ignores `site/downloads/*.dmg`) and regenerate `appcast.xml`.
2. Point both redirects in `vercel.json` at the new file.
3. Deploy as above. The download buttons on the page use `/Sift.dmg`, so they keep working,
   and the deploy is what makes the Sparkle update visible.
