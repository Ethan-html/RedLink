<div align="center">

<img src="docs/readme-logo.png" alt="RedLink" width="110">

# 🛡️ RedLink Security

### How your message stays private, in plain English

[← Back to the README](README.md)

</div>

---

## The idea in one minute

RedLink is built so that **the places your message passes through never get to read it**.

Your message is locked **on your own device**, using a passkey that is **never sent anywhere**. What gets stored is scrambled text that is useless without that passkey. When the recipient opens the link and proves they know the passkey, they get the scrambled text, their browser unlocks it, and the stored copy is **deleted on the spot**.

Everything below explains the layers that make this work, who can see what, and, just as important, **where the limits are**.

---

## 📦 How a message travels

| Step | What happens | Where |
|---|---|---|
| **1. Lock** | You type a message. Your browser makes a random passkey and locks the message with it. | Your device only |
| **2. Store** | Only the locked text is uploaded, plus a way to check a passkey later **without** revealing it. | Database |
| **3. Share** | You send the link, and the passkey either inside the link or separately. | You choose |
| **4. Open** | The recipient presses **View message** and the passkey is checked. | Their device and the database |
| **5. Burn** | If the passkey is right, the stored copy is deleted and the message is unlocked in their browser. | Both |

At no point does a readable message, or the passkey itself, reach the website host or the database.

---

## 🧱 The layers of protection

### 🔐 Encryption happens in your browser
Messages are locked with **AES-256-GCM**, a modern, widely reviewed standard that is built into every current browser. It does two jobs: it hides the message, and it **detects tampering**. If anyone changes even one character of the stored text, unlocking fails instead of showing altered content. Each locked message is also tied to its own link name, so it can't be copied under a different link and still open.

### 🙈 The passkey never leaves your device
The passkey is run through **PBKDF2 (600,000 rounds)** in your browser. That step is deliberately slow. It turns a short passkey into a strong key, and it makes mass guessing expensive. Part of the result locks the message. A separate part is used to prove you know the passkey, so the database can confirm a match **without ever seeing the passkey or the key that unlocks the message**.

### 🔥 Read once, then gone
The instant a link is opened with the right passkey, the stored copy is deleted. A second visit finds nothing. This also works as an alarm: **if the real recipient finds a link already gone, someone else opened it first**, and you should treat the message as exposed and change whatever it contained.

### 🚫 Guessing is shut down quickly
After **5 wrong passkeys**, the message is destroyed. Passkeys also have to match one exact format in the browser before they are even sent, so junk guesses are never counted or processed.

### ⏳ Nothing lives forever
Unopened links expire after **7 days**. Expired links are invisible to the site immediately and are cleaned up automatically.

### 🖱️ A click is required to open
Opening a link doesn't use it up. The recipient first sees a *"can only be viewed once"* screen and must press **View message**. That stops chat apps, email scanners and link-preview bots from burning the link by accident.

### 🔗 The passkey inside a full link stays on the device
In a full link, the passkey sits after the `#`. Browsers **never send that part to any server**, so it isn't in hosting logs or database requests. The page also removes it from the address bar as soon as it loads, and it is kept only in that tab's temporary memory.

> 📌 The passkey in a full link is **encoded, not encrypted**. Anyone who holds the full link can read the message. See *Limits* below.

### 🧱 A locked-down database
All database tables are closed to the public. The website can only use a short list of fixed, purpose-built actions, none of which can read stored messages in bulk or return anything readable. The database also enforces **who is allowed to create links** on its own, so editing the page in a browser doesn't get anyone around it.

### 🧭 Who can create links is your choice
- **Open**: anyone can create links.
- **PIN**: creators need a PIN, and repeated wrong PINs are temporarily blocked.
- **Approved accounts only**: creators must sign in with an account you approved. Only those accounts can use the admin page.

Opening a link always needs only the passkey, whichever mode you pick.

### 🧰 The admin page can't read messages
The admin page lists live links (name, times, how many wrong guesses) and lets approved accounts **burn** them early. It never shows a message and has no way to unlock one.

### 🔑 Only the public key ever goes in the site
The build **refuses to deploy** if it sees a secret/`service_role` key, and it checks that both Supabase values are present and correct, so a broken or unsafe setup doesn't go live quietly.

### 🧾 Hardened delivery
The site is served over HTTPS and sends security headers that stop content-type guessing and don't leak the page address to other sites.

---

## 👀 Who can see what

| Who | Can they read your message? | What they may see |
|---|---|---|
| **You** (sender) | Yes, while you have the passkey | Your own message |
| **The recipient** | Yes, once, with the passkey | The message, one time |
| **Someone with only the link** (no passkey) | **No** | That a link exists |
| **Someone with the full link** | **Yes**, same as the recipient | Everything the recipient can see |
| **The website host** (Netlify) | **No** | Normal web traffic: that someone visited |
| **The database** (Supabase) | **Not in readable form** | Locked text, link name, timestamps, wrong-guess count |
| **Someone watching the network** | **No** | Traffic is HTTPS-encrypted, and the part after `#` is never sent |
| **Approved admins** | **No** | Link names, times, wrong-guess counts, and the ability to burn |

---

## ⚖️ Honest limits

No tool is perfect, and a security page that hides its limits isn't doing its job. These are the things RedLink **does not** protect against.

- **Anyone with the full link can read the message.** The full-link option trades some safety for convenience. For anything very sensitive, send the link and the passkey through **two different channels**.
- **The passkey is easy to say and type, on purpose.** That makes it practical, and it is the right fit for short-lived, read-once sharing. It is **not** meant to protect a message that sits around for a long time, or to hold up against a determined attacker who has obtained a copy of the stored data. Use RedLink for things that will be **opened soon and then changed or discarded**, like a temporary password or a one-time code.
- **A compromised device is a compromised message.** Malware, a hostile browser extension or someone looking over a shoulder can see a message once it is on screen. RedLink can't protect what is already unlocked on a device that isn't safe.
- **You trust the site you're visiting.** As with every website that encrypts in the browser, the page itself is code delivered to you. Run your own copy, and keep the accounts that control it safe.
- **Some information is visible.** The link name, creation time and whether someone failed to open it are stored in readable form. **Don't put secrets in the link name.**
- **Copying defeats read-once.** Once a message is unlocked, the person who opened it can copy, screenshot or forward it.

---

## ✅ Good habits

- Use the **two-channel** option for anything sensitive.
- Pick a **forgettable link name** that doesn't describe the secret.
- **Change a shared password afterward** whenever you can.
- If a recipient says *"it's already gone"*, treat the message as read by someone else and replace what it protected.
- Choose **PIN** or **approved accounts only** unless you really want anyone to create links.

---

## 🏠 If you run your own copy

- Use the **publishable** key only and never the secret key.
- In approved-accounts mode, **turn off public sign-ups** in Supabase.
- Turn on **two-factor sign-in** for your GitHub, Netlify and Supabase accounts, since these control your site and your database.
- Use a strong, unique password for the approved account.
- Don't add new database tables or change permissions in the dashboard unless you know why. The provided setup file already locks everything down.
- Re-run `supabase/setup.sql` and redeploy after updates from this project.

---

## 🐞 Found a problem?

Please report it privately instead of posting it publicly. On GitHub, open the repository's **Security** tab and choose **Report a vulnerability**. (If you don't see that option, the repository owner needs to switch on *Private vulnerability reporting* in **Settings → Code security**.)

---

<div align="center">

**RedLink** · made by **Codered** 🔴

[← Back to the README](README.md)

</div>
