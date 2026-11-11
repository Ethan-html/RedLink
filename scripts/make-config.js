// Netlify build step: copies the site into dist/ and writes dist/config.js from env vars.
// Only the public site files are published (not migrations, scripts or SQL).
const fs = require("fs");
const url = (process.env.SUPABASE_URL || "").trim();
const key = (process.env.SUPABASE_ANON_KEY || "").trim();

function looksSecret(k) {
  if (k.startsWith("sb_secret_")) return true;
  if (k.startsWith("eyJ")) {
    try { return JSON.parse(Buffer.from(k.split(".")[1], "base64url").toString()).role === "service_role"; }
    catch { return false; }
  }
  return false;
}
if (looksSecret(key)) { console.error("SUPABASE_ANON_KEY is a secret/service_role key. Use the publishable key."); process.exit(1); }
if (!url || !key) console.warn("SUPABASE_URL / SUPABASE_ANON_KEY not set: site will run in demo mode.");

fs.rmSync("dist", { recursive: true, force: true });
fs.mkdirSync("dist");
for (const f of ["index.html", "icon.svg", "REDLINK.png", "REDLINKnoBG.png", "_redirects"]) {
  if (fs.existsSync(f)) fs.copyFileSync(f, "dist/" + f);
}
fs.writeFileSync("dist/config.js", "window.REDLINK_CONFIG=" + JSON.stringify({ url, key }) + ";\n");
