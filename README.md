<div align="center">

<img src="docs/readme-logo.png" alt="RedLink" width="170">

# 🔴 RedLink

### Share a secret once. Then it's gone.

Encrypted, self-destructing links.
Your message is locked **in your browser** before it ever leaves your device.

![Encryption](https://img.shields.io/badge/encryption-AES--256--GCM-ff4d5e?style=for-the-badge)
![Expires](https://img.shields.io/badge/expires-7%20days-ff8a5b?style=for-the-badge)
![Read](https://img.shields.io/badge/read-once-5fe3b0?style=for-the-badge)
![Hosting](https://img.shields.io/badge/hosting-Netlify%20%2B%20Supabase-3d2b34?style=for-the-badge)

*made by **Codered***

</div>

---

## ✨ What is it?

RedLink lets you send a password, API key, or private note without leaving it sitting in someone's chat history or inbox.

1. You type your message and pick a link.
2. RedLink encrypts it and gives you a **link** plus a **passkey** like `Maple-River-Cloud-482`.
3. You share it, either as one **full link** (click and go) or as a link and passkey sent separately.
4. The recipient opens it, clicks **View message**, reads it, and **it's deleted**.

It's a static website (one HTML file) backed by a small Supabase database. No server to maintain.

---

## 🛡️ Why it's safe

| | |
|---|---|
| 🔐 **Encrypted in your browser** | Messages are locked with AES-256-GCM before upload. The database only ever stores scrambled text. |
| 🙈 **The server never sees the passkey** | The passkey is stretched with PBKDF2 (600,000 rounds). The database can check it's right without ever learning it. |
| 🔥 **Read once** | The moment a link is opened successfully, it is deleted. |
| 🚫 **5 wrong guesses and it burns** | Too many wrong passkeys and the link is destroyed. |
| ⏳ **Auto-expires after 7 days** | Unopened links are cleaned up automatically. |
| 🧱 **Locked-down database** | Tables are closed to the public. The site can only call a small set of fixed functions. |
| 🔑 **Only the public key is used** | The build refuses to deploy if you accidentally paste a secret / `service_role` key. |

> **Bottom line:** the database and the website host only ever hold scrambled text, never a readable message or the passkey.
>
> 📖 **For more detailed Security infomation** See **[SECURITY.md](SECURITY.md)**.

---

## 🔗 Sharing options

After you create a link you get three copy buttons (plus a small **Which one?** dropdown that explains them):

| Button | What you get | Best for |
|---|---|---|
| **Copy full link** | `yoursite.com/my-link#V2ludGVyLVRpbWJlci1UaWdlci0zMDg` | One click to open. Easy to paste into an email. |
| **Copy link only** | `yoursite.com/my-link` | Sending the link and passkey through **different** channels. |
| **Copy passkey** | `Maple-River-Cloud-482` | The second half of the separate-channels option. |

**Opening a full link:** nothing is opened or deleted just by clicking it. The recipient first sees a *"This message can only be viewed once"* screen and has to press **View message**. That also stops chat apps and email scanners from burning the link while they make a preview.

**Is the passkey in the link safe?** The part after the `#` is never sent over the internet. Your browser keeps it locally, so the server, hosting and logs never see it, and it's removed from the address bar the moment the page loads. It's held only in that browser tab's memory (so a reload still works) and is cleared when the message is viewed or the tab is closed. The passkey is also base64-encoded so it isn't sitting there as readable words. Note that encoding only hides it at a glance and is not encryption, so anyone who has the full link can read the message. Use separate channels for anything extra sensitive.

---

## 🚀 Setup

**You need:** a free [Supabase](https://supabase.com) account, a free [Netlify](https://netlify.com) account, and a free GitHub account. About 10 minutes.

### Step 1: Create the Supabase project

In Supabase click **New project** and wait for it to finish starting.

### Step 2: Run the SQL file (and pick who can create links)

Everything lives in: `supabase/setup.sql`.

1. Open `supabase/setup.sql` in any text editor and scroll to the bottom to **PART 4: CHOOSE WHO CAN CREATE LINKS**. Edit the three values:

   ```sql
   v_mode   text := 'auth';   -- 'open', 'pin' or 'auth'
   v_pin    text := '';       -- only for 'pin'
   v_admins text := '';       -- only for 'auth', e.g. 'you@example.com'
   ```

2. Fill them in using the table below. Keep the quote marks.

   | Security type | Who can create links | Set these |
   |---|---|---|
   | 🌍 `'open'` | Anyone | Nothing else. Leave `v_pin` and `v_admins` empty. |
   | 🔢 `'pin'` | People who know the PIN | `v_pin := 'your-pin'` (4 or more characters) |
   | 👤 `'auth'` | Only approved accounts (best for private use) | `v_admins := 'you@example.com'` (several emails: `'a@x.com, b@x.com'`) |

3. In Supabase open **SQL Editor → New query**, paste the **whole file**, and click **Run**.
4. Check the result table at the bottom. `create_mode` should be what you chose. In `auth` mode `approved_emails` should list your email.

> If PART 4 has a mistake (empty email, PIN too short, a typo in the mode) the script stops with a plain-English error and **changes nothing**. Fix the value and run it again. The whole file is safe to run any number of times.

> 💡 A notice about `pg_cron` is fine. Expired links are hidden automatically and cleaned up whenever someone creates a link.

#### Extra steps for `auth` mode (the admin user)

`v_admins` only says who is **allowed**. The account itself must also exist in Supabase, and the site signs in with **email + password**, so create it with a password. Do **not** use *Invite user*, because that sends a link to a page this site doesn't have.

1. In Supabase go to **Authentication → Users → Add user → Create new user**.
2. Enter the **same email** you put in `v_admins`, and choose a password.
3. Turn **Auto Confirm User** on, then click **Create user**.
4. Go to **Authentication → Sign In / Providers** and turn **off** *Allow new users to sign up* so nobody else can register.

That account signs in on your site, creates links, and gets the **Manage links** button (also at `yoursite.com/admin`).

#### Changing it later

Edit the three values in PART 4 and run the file again, or run one line on its own:

```sql
select public.redlink_mode('open');                  -- anyone
select public.redlink_mode('pin', 'new-pin');        -- PIN
select public.redlink_mode('auth');                  -- approved accounts only
insert into public.redlink_users (email) values ('another@example.com') on conflict do nothing;   -- add an admin
delete from public.redlink_users where email = 'old@example.com';                                  -- remove an admin
```

> ⚠️ Until a mode is chosen the site defaults to `auth` with no approved users, so nobody can create links. That's intentional.

### Step 3: Copy your two Supabase values

In Supabase go to **Project Settings → API** and keep that tab open. You'll paste two things in the next step:

- **Project URL** → looks like `https://xxxx.supabase.co`
- **Publishable key** (also called the *anon* key) → starts with `sb_publishable_`

> 🛑 **Never use the `secret` or `service_role` key.** The build stops with an error if you do.

### Step 4: Deploy with the Netlify button

1. Put this folder in a **public** GitHub repo (the button needs to be able to read it).
2. Click the button. It's already pointed at `Ethan-html/RedLink`:

   [![Deploy to Netlify](https://www.netlify.com/img/deploy/button.svg)](https://app.netlify.com/start/deploy?repository=https://github.com/Ethan-html/RedLink)

   (If you fork or rename the repo, change the address at the end of that link to match.)
3. Netlify connects to GitHub, copies the project, and **asks you for two values** in a form. Paste:

   | Form field | Paste |
   |---|---|
   | `SUPABASE_URL` | the Project URL |
   | `SUPABASE_ANON_KEY` | the Publishable key |

4. Click **Save & Deploy**. Build settings are already in `netlify.toml`.

#### Why this can't go wrong silently

Pasting the values in the wrong place (a build setting instead of a site environment variable, only for one scope, URL and key swapped, a stray quote or the secret key) used to produce a site that deployed fine but didn't work. Now the build **checks both values and refuses to deploy**, with a message in the deploy log that says what's wrong and where to fix it. A broken site never goes live.

If you set it up by hand instead of the button, add the two variables under **Site configuration → Environment variables** (not the *Build command* box, not `netlify.toml`). Set **Scopes** to include **Builds** and use **Same value for all deploy contexts**. Then **Deploys → Trigger deploy → Clear cache and deploy site**.

### Step 5: Test it ✅

1. Open your new site and create a test message. (In `auth` mode, sign in first.)
2. Copy the link and the passkey.
3. Open the link in a private/incognito window and enter the passkey.
4. Confirm you can read it, and that opening the link again says it's gone.

---

## 🧰 Managing links (auth mode)

Signed-in approved accounts (the emails in `v_admins`) get a **Manage links** button, or visit `yoursite.com/admin`. It lists every live link (never the message) and lets you **burn** any of them early.

`admin` is a reserved name and can't be used as a link name.

---

## 📁 What's in the box

```
redlink/
├── index.html                  ← the entire website
├── SECURITY.md                 ← detailed, plain-English security page
├── netlify.toml                ← build, security headers, deploy-button form
├── docs/readme-logo.png        ← logo used in this README
├── _redirects                  ← routing for link URLs
├── scripts/make-config.js      ← build step: checks your two values, writes config, publishes only public files
├── supabase/setup.sql          ← ONE file: database + who can create links
├── setup/redlink.project.json  ← optional automated-installer recipe
└── icon.svg, REDLINK*.png      ← branding
```

Only the website files get published. Your SQL and scripts are never exposed.

---

## ❓ Troubleshooting

| Problem | Fix |
|---|---|
| Netlify build fails with **"REDLINK SETUP PROBLEM"** | Read the lines marked `x` in the deploy log. They say exactly what's wrong (missing, swapped, wrong key type). Fix it under **Site configuration → Environment variables**, with **Builds** ticked in Scopes, then **Clear cache and deploy site**. |
| Build says it is a *secret/service_role key* | Use the **publishable/anon** key, never the secret one. |
| `setup.sql` stops with an error about PART 4 | The error says which value to fix (mode, PIN, or email). Nothing was changed, so fix it and run the file again. |
| Nobody can create links | Check the result table at the bottom of `setup.sql`: is `create_mode` what you want? In `auth` mode, is your email in `approved_emails`? |
| Can't sign in (`auth` mode) | The user must be created with a password under **Authentication → Users → Add user → Create new user** (Auto Confirm on), using the same email as `v_admins`. |
| "Couldn't save to the database" | Run the whole `supabase/setup.sql` again and look for errors. |
| Changed the env variables but nothing changed | Trigger a new deploy. The values are baked in at build time. |
| Upgrading an old database that has the unused "sites" tables | In `supabase/setup.sql`, remove the `/*` and `*/` around the OPTIONAL block at the very bottom, then run the file again. |

---

<div align="center">

**RedLink** · made by **Codered** 🔴

</div>
