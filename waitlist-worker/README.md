# Aurora waitlist worker

The signup endpoint behind the waitlist form on aurora.nmapaye.com.

- Runs on Cloudflare Workers (free plan).
- Takes one field, an email address, only from `https://aurora.nmapaye.com`.
- Checks a Cloudflare Turnstile token on every signup, so bots can't fill the list.
- Stores addresses in the D1 database `aurora-waitlist`. Nothing reads them back over HTTP; view them in the Cloudflare dashboard (D1 > aurora-waitlist > Console: `SELECT * FROM signups ORDER BY created_at;`).
- The Turnstile secret lives only in the Worker's secrets, never in the site.

## Setup

1. D1: create a database named `aurora-waitlist` and run `schema.sql` in its console.
2. Turnstile: add a widget for the hostname `aurora.nmapaye.com` (Managed mode). Keep the site key and the secret key.
3. Worker: create a Worker named `aurora-waitlist` with `src/index.js`, bind the D1 database as `DB`, and add the secret `TURNSTILE_SECRET`.
4. Site: set `waitlistEndpoint` (the Worker URL + `/signup`) and `turnstileSiteKey` in `website/src/App.tsx`, then publish the site.

## Deleting data

`DELETE FROM signups WHERE email = 'someone@example.com';` in the D1 console. Drop the table within 30 days after the App Store launch, as the privacy policy says.
