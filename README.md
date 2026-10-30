# Class Compass

A phone web app that points kids to their next classroom with a big arrow, the distance in steps, and written directions. Retro amber-terminal look.

- **App:** https://gone12332.github.io/class-compass/
- **Admin:** https://gone12332.github.io/class-compass/admin/ (needs the Supabase setup below)

## Files

| Path | What it is |
|---|---|
| `index.html` | The whole app: HTML, CSS and JS in one file, no build step. |
| `admin/index.html` | Admin dashboard: login, stats, posters, phone list with ban/unban, QR poster maker, dev console. |
| `config.js` | Supabase URL and anon key. Empty means stats are off. |
| `supabase/setup.sql` | Database tables and functions. Run once in the Supabase SQL Editor. |
| `sw.js` | Service worker so the app works offline. Bump `CACHE` when you change files. |
| `manifest.webmanifest`, `icon-*.png`, `apple-touch-icon.png` | Home-screen app icon and settings. |
| `HANDOFF.md` | Notes for anyone (or any AI) continuing the project. |

## Turn on stats and the admin login

1. Make a free account at supabase.com and create a project.
2. SQL Editor > New query > paste all of `supabase/setup.sql` > Run.
3. Authentication > Users > Add user: email `root@example.com`, pick a password, tick Auto confirm. On the admin page you log in as `root` with that password.
4. Project Settings > API: copy the Project URL and the `anon` `public` key into `config.js`, commit, and push.

The password lives only in Supabase. Never put it in this repo: the repo is public.

## Deploy

GitHub Pages serves the `gh-pages` branch. After committing on `main`:

```
git push origin main main:gh-pages
```
