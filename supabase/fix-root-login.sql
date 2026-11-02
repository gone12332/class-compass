-- Fixes the admin login. Run in Supabase: SQL Editor > New query.
-- 1. Change NEW-PASSWORD-HERE below to the password you want.
-- 2. Run it. It confirms root@example.com and sets that password.
-- If it says "0 rows", the user doesn't exist yet: create it under
-- Authentication > Users > Add user > Create new user (email root@example.com), then run this again.
update auth.users
set encrypted_password = crypt('NEW-PASSWORD-HERE', gen_salt('bf')),
    email_confirmed_at = coalesce(email_confirmed_at, now()),
    updated_at = now()
where email = 'root@example.com';
