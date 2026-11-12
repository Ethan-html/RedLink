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

> **Bottom line:** even the person running the database can't read your messages.

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

**You need:** a free [Supabase](https://supabase.com) account and a free [Netlify](https://netlify.com) account. About 10 minutes.

### Step 1: Create the database

1. In Supabase, click **New project** and wait for it to finish starting.
2. Open **SQL Editor** in the left menu.
3. Run these three files **in order**. Open each one, copy everything, paste it in, click **Run**:
   1. `supabase/migrations/0001_schema.sql`
   2. `supabase/migrations/0002_functions.sql`
   3. `supabase/migrations/0003_cleanup_job.sql`

All three are safe to run more than once.

> 💡 If you see a notice about `pg_cron` in step 3, that's fine. Expired links are hidden automatically and cleaned up whenever someone creates a link.

### Step 2: Choose who can create links

Opening a link is always possible with the passkey. This setting controls who can **create** them. Run **one** of these in the SQL Editor:

**🌍 Open: anyone can create**
```sql
select public.redlink_mode('open');
```

**🔢 PIN: people need a PIN first** (use your own, 4+ characters)
```sql
select public.redlink_mode('pin', 'your-pin-here');
```

**👤 Auth: only approved accounts can create** (best for private use)
```sql
insert into public.redlink_users (email) values (lower('you@example.com')) on conflict do nothing;
select public.redlink_mode('auth');
```
Then in Supabase go to **Authentication → Users → Invite user** and invite that same email. Also turn off public sign-ups under **Authentication → Sign In / Providers** so nobody else can register.

> ⚠️ Until you pick a mode, the site defaults to `auth` with no approved users, so nobody can create links. That's intentional.

### Step 3: Grab your two keys

In Supabase go to **Project Settings → API** and copy:

- **Project URL** → this is `SUPABASE_URL`
- **Publishable key** (also called the *anon* key) → this is `SUPABASE_ANON_KEY`

> 🛑 **Never use the `secret` or `service_role` key.** The build will stop with an error if you do.

### Step 4: Deploy on Netlify

1. Put this folder in a GitHub repo (or use Netlify's drag-and-drop for the folder).
2. In Netlify: **Add new site → Import an existing project** and pick the repo.
3. The build settings are already in `netlify.toml`, so leave them as they are.
4. Before deploying, open **Site configuration → Environment variables** and add:

| Name | Value |
|---|---|
| `SUPABASE_URL` | your Project URL |
| `SUPABASE_ANON_KEY` | your Publishable key |

5. Click **Deploy**.

### Step 5: Test it ✅

1. Open your new site and create a test message.
2. Copy the link and the passkey.
3. Open the link in a private/incognito window and enter the passkey.
4. Confirm you can read it, and that opening the link again says it's gone.

If the site loads but shows demo behaviour, the two environment variables are missing. Add them and redeploy.

---

## 🧰 Managing links (auth mode)

Signed-in approved accounts get a **Manage links** button, or visit `yoursite.com/admin`. It lists every live link (never the message) and lets you **burn** any of them early.

`admin` is a reserved name and can't be used as a link name.

---

## 📁 What's in the box

```
redlink/
├── index.html                  ← the entire website
├── netlify.toml                ← build + security headers
├── docs/readme-logo.png        ← logo used in this README
├── _redirects                  ← routing for link URLs
├── scripts/make-config.js      ← build step: writes config, publishes only public files
├── supabase/
│   ├── migrations/             ← run these 3 in order
│   └── post-deploy-modes.sql   ← reference notes for the create modes
├── tools/
│   └── migrate-existing-db.sql ← only for an older database (see below)
├── setup/redlink.project.json  ← optional automated-installer recipe
└── icon.svg, REDLINK*.png      ← branding
```

Only the website files get published. Your SQL and scripts are never exposed.

---

## ❓ Troubleshooting

| Problem | Fix |
|---|---|
| Build fails with *"is a secret/service_role key"* | You used the wrong key. Use the **publishable/anon** key. |
| Nobody can create links | You haven't chosen a mode yet (Step 2), or in auth mode your email isn't in `redlink_users`. |
| "Couldn't save to the database" | Make sure all three migrations ran, in order, with no errors. |
| Changed the env variables but nothing changed | Trigger a new deploy. The values are baked in at build time. |
| Upgrading an old database | Run the three migrations first, then `tools/migrate-existing-db.sql` once. |

---

<div align="center">

**RedLink** · made by **Codered** 🔴

</div>
