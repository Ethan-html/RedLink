// Netlify build step: copies the site into dist/ and writes dist/config.js from env vars.
// Only the public site files are published (not migrations, scripts or SQL).
//
// On Netlify this script REFUSES to deploy if the two Supabase values are missing or look
// wrong (swapped, secret key, wrong kind of URL, set in the wrong place). A broken site
// never goes live looking like it worked.
const fs = require("fs");

const onNetlify = process.env.NETLIFY === "true";
const allowDemo = process.env.REDLINK_ALLOW_DEMO === "1"; // escape hatch: deploy a demo on purpose

// Tidy up common copy/paste slips: spaces, quotes, and a pasted "NAME=" prefix.
const unquote = (v) => v.trim().replace(/^["'`]+|["'`]+$/g, "").trim();
const clean = (v, name) =>
  unquote(unquote(v || "").replace(new RegExp("^" + name + "\\s*=\\s*", "i"), ""));

let url = clean(process.env.SUPABASE_URL, "SUPABASE_URL");
let key = clean(process.env.SUPABASE_ANON_KEY, "SUPABASE_ANON_KEY");

const problems = [];

function jwtRole(k) {
  try { return JSON.parse(Buffer.from(k.split(".")[1], "base64url").toString()).role; } catch { return null; }
}
function looksSecret(k) {
  return k.startsWith("sb_secret_") || (k.startsWith("eyJ") && jwtRole(k) === "service_role");
}

// ---- SUPABASE_URL ----
if (!url) {
  problems.push("SUPABASE_URL is empty or not visible to the build.");
} else if (!url.includes("://") && /^(sb_|eyJ)/.test(url)) {
  problems.push("SUPABASE_URL contains a KEY. The URL and key look swapped. SUPABASE_URL must be the Project URL (https://xxxx.supabase.co).");
} else {
  try {
    const u = new URL(url);
    if (u.protocol !== "https:") problems.push("SUPABASE_URL must start with https://");
    else if (u.hostname === "supabase.com" || u.hostname.endsWith(".supabase.com"))
      problems.push("SUPABASE_URL is the Supabase DASHBOARD address. Use the Project URL from Project Settings > API (https://xxxx.supabase.co).");
    else url = u.origin; // drops any trailing slash or /rest/v1 someone pasted on the end
  } catch {
    problems.push("SUPABASE_URL is not a valid web address. It should look like https://xxxx.supabase.co");
  }
}

// ---- SUPABASE_ANON_KEY ----
if (!key) {
  problems.push("SUPABASE_ANON_KEY is empty or not visible to the build.");
} else if (key.startsWith("http")) {
  problems.push("SUPABASE_ANON_KEY contains a URL. The URL and key look swapped. Use the Publishable key here.");
} else if (looksSecret(key)) {
  problems.push("SUPABASE_ANON_KEY is a SECRET / service_role key. Never use that. Use the Publishable (anon) key.");
} else if (/\s/.test(key) || key.length < 20) {
  problems.push("SUPABASE_ANON_KEY does not look like a complete key (it has spaces or is too short). Copy it again.");
} else if (!key.startsWith("sb_publishable_") && !(key.startsWith("eyJ") && jwtRole(key) === "anon")) {
  problems.push("SUPABASE_ANON_KEY does not look like a Publishable (anon) key. It should start with sb_publishable_ (or eyJ for older projects).");
}

const mask = (v) => (v ? "set, " + v.length + " characters" : "NOT FOUND");

if (problems.length) {
  const lines = [
    "",
    "==============================================================",
    " REDLINK SETUP PROBLEM: the site was NOT deployed",
    "==============================================================",
    ...problems.map((p) => " x " + p),
    "",
    " What the build can see right now:",
    "   SUPABASE_URL       : " + mask(process.env.SUPABASE_URL),
    "   SUPABASE_ANON_KEY  : " + mask(process.env.SUPABASE_ANON_KEY),
    "",
    " How to fix it:",
    "   1. Netlify > Site configuration > Environment variables",
    "      (NOT the Build command box, NOT netlify.toml).",
    "   2. Add or edit both variables. Under Scopes make sure \"Builds\" is ticked,",
    "      and pick \"Same value for all deploy contexts\".",
    "   3. Deploys > Trigger deploy > Clear cache and deploy site.",
    "==============================================================",
    "",
  ];
  if (onNetlify && !allowDemo) {
    console.error(lines.join("\n"));
    process.exit(1);
  }
  console.warn(lines.join("\n"));
  console.warn("Continuing in DEMO mode (not on Netlify, or REDLINK_ALLOW_DEMO=1). Nothing will be saved.\n");
  url = "";
  key = "";
} else {
  console.log("RedLink: using " + url + " with a publishable key (" + key.length + " characters). Looks good.");
}

fs.rmSync("dist", { recursive: true, force: true });
fs.mkdirSync("dist");
for (const f of ["index.html", "icon.svg", "REDLINK.png", "REDLINKnoBG.png", "_redirects"]) {
  if (fs.existsSync(f)) fs.copyFileSync(f, "dist/" + f);
}
fs.writeFileSync("dist/config.js", "window.REDLINK_CONFIG=" + JSON.stringify({ url, key }) + ";\n");
