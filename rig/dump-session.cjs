// Dump session-route state for the rig sessions from the state SQLite DB.
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync(process.argv[2], { readOnly: true });
for (const t of ["session_state_heads", "session_state_events"]) {
  try {
    const cols = db.prepare(`PRAGMA table_info(${t})`).all().map((c) => c.name);
    console.log(`== ${t}: ${cols.join(",")}`);
    const rows = db.prepare(`SELECT * FROM ${t}`).all();
    for (const r of rows) {
      const s = JSON.stringify(r);
      if (s.includes("rig-a") || s.includes("route") || rows.length < 20) {
        console.log(s.length > 2000 ? s.slice(0, 2000) + "…" : s);
      }
    }
  } catch (e) {
    console.log(`${t}: ${e.message}`);
  }
}
