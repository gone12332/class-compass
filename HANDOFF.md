# Handoff notes

For anyone picking up Class Compass, including another AI assistant. Read this before changing code.

## What it is

A static web app for kids who have trouble finding classrooms. A kid saves each classroom by standing at its door (GPS), then picks a class and follows an arrow (phone compass + GPS). Hosted on GitHub Pages. No build step and no framework; everything is plain HTML/CSS/JS.

## Rules that must not break

1. **Never lose saved data.** Classes live in `localStorage["classCompass.v1"]` as an array of `{id, name, lat, lon, acc, notes, time, floor, color, days, kind}` (`kind` is `"stairs"`, `"elevator"` or missing for a class). Do not rename the key or change existing fields; only add optional ones. Prefs (arrow style, stars, current floor, elevator preference) are in `classCompass.v1.prefs`; the anonymous phone ID is in `classCompass.v1.device`.
2. **No secrets in the repo.** It's public. The admin password lives only in Supabase Auth. The anon key in `config.js` is public by design and can only call `cc_track()`.
3. **Kids' privacy.** Stats are anonymous: a random phone ID, event kinds (`open`, `scan`, `trip`, `arrive`), the poster spot name, phone type. Never send names, GPS coordinates or class names.
4. **Needs HTTPS.** Phones only allow GPS and compass on https pages. Opening the file directly won't work.
5. **Deploy = push to `gh-pages`:** `git push origin main main:gh-pages`. Bump `CACHE` in `sw.js` on every release so phones pick up changes.

## How the pieces fit

- `index.html` sections: `#home` (class list, Next up card, stars), `#compass` (dial, arrow skins, distance, trip bar, on-time check), `#edit` (add/edit class, "Save this spot" averages GPS for up to 15 s), `#menu` (share link + QR, arrow picker, paste-a-link import, tips).
- Heading: Android uses `deviceorientationabsolute` (heading = 360 - alpha); iPhone uses `webkitCompassHeading` and needs `DeviceOrientationEvent.requestPermission()` on a tap (the Start button).
- GPS is smoothed with a small Kalman-style filter in `onPos()`. Arrival radius is `max(6, min(accuracy, 15))` meters.
- Share links: `#rooms=<base64url JSON>`, packed by `packClasses()` and read by `checkImport()`.
- Poster QR codes open `/?src=<spot>`; the app reports a `scan` with that spot, then removes `?src` from the address.
- Stats: `track(kind, src)` POSTs to Supabase `rpc/cc_track`. If the reply says `banned`, the app shows the "Access paused" screen.
- Admin (`admin/index.html`): logs in through Supabase Auth (`root` becomes `root@example.com`), then calls `cc_admin_stats`, `cc_admin_devices` and `cc_admin_ban`. All three check `cc_is_admin()` in SQL, so they're useless without the admin login.
- Floors: GPS can't tell floors, so the app remembers the floor you're on (asked once, then set on every arrival or when you tap "I'm on floor X now"). If the room is on another floor, `planRoute()` picks the stairs/elevator spot that makes here -> stairs -> room shortest, and the trip runs in 3 steps: walk to stairs, go up/down (button confirms), walk to room. `floorNum()` reads floors like 2, G, B1.
- QR codes use `qrcode-generator@1.4.4` from jsDelivr.

## Testing

There's no test suite in the repo. What was used: Playwright with Chromium, a local static server, mocked geolocation (`context.setGeolocation`), fake compass events (`window.dispatchEvent(new Event("deviceorientationabsolute"))` with `alpha` set), and a fake Supabase via `context.route`. `supabase/setup.sql` was tested on a local Postgres 16 with stand-in `anon`/`authenticated` roles and an `auth.jwt()` function.

## Ideas not done yet

- Automatic floor detection (phones' web browsers don't expose the barometer, so the kid confirms the floor change).
- Teacher-made room lists for the whole school, loaded from Supabase instead of per phone.
- Indoor accuracy: Bluetooth beacons or Wi-Fi positioning would beat GPS but need hardware.
