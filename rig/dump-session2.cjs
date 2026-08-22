// List non-empty tables and rows mentioning rig sessions or delivery routes.
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync(process.argv[2], { readOnly: true });
const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all();
for (const { name } of tables) {
  let n = 0;
  try {
    n = db.prepare(`SELECT COUNT(*) c FROM "${name}"`).get().c;
  } catch { continue; }
  if (!n) continue;
  console.log(`== ${name}: ${n} rows`);
  if (n > 400) continue;
  try {
    const rows = db.prepare(`SELECT * FROM "${name}"`).all();
    for (const r of rows) {
      const s = JSON.stringify(r, (k, v) => (typeof v === "string" && v.length > 600 ? v.slice(0, 600) + "…" : v));
      if (/rig-a|lastTo|deliveryContext|"route"|orchestrator/.test(s)) {
        console.log(s.length > 1500 ? s.slice(0, 1500) + "…" : s);
      }
    }
  } catch (e) { console.log(`  err: ${e.message}`); }
}
