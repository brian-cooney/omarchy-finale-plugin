// Run: node test/model-test.js
const M = require("../Model.js");

let failures = 0;
function check(name, cond, detail) {
  const ok = !!cond;
  console.log(`[${ok ? "ok  " : "FAIL"}] ${name}${!ok && detail ? " - " + detail : ""}`);
  if (!ok) failures++;
}

const NOW = new Date("2026-08-28T18:00:00Z");

const sample = JSON.stringify({
  generated_at: "2026-08-28T15:40:00Z",
  source: "https://www.finaleoutdoor.com/en/live/bike",
  as_of_date: "2026-08-28",
  summary: { state: "partial", closed_count: 2 },
  closed_trails: [
    { area: "NATO BASE AREA", trail: "101 Ingegnere", note: "until 2pm" },
    { area: "manie area", trail: "3 Ca du Puncin", note: "" }
  ],
  notices: [
    { date: "2026-08-28", title: "TRAIL STATUS", text: "a\n\nb***\n\nc" }
  ]
});

const s = M.parseStatus(sample);
check("parse: state partial", s.state === "partial");
check("parse: closedCount 2", s.closedCount === 2);
check("parse: 2 trails kept", s.closedTrails.length === 2);
check("parse: bad json -> null", M.parseStatus("{not json") === null);
check("parse: unknown state normalised", M.parseStatus('{"summary":{"state":"weird"}}').state === "unknown");
check("parse: checkedAt falls back to generated_at", s.checkedAt === "2026-08-28T15:40:00Z");

const withCheck = M.parseStatus(JSON.stringify({
  generated_at: "2026-08-20T00:00:00Z",   // closures 8 days unchanged
  checked_at: "2026-08-28T17:50:00Z",     // but re-checked 10 min ago
  summary: { state: "partial", closed_count: 1 }
}));
check("parse: checkedAt read when present", withCheck.checkedAt === "2026-08-28T17:50:00Z");

check("stale: fresh not stale", M.isStale("2026-08-28T17:30:00Z", NOW, 180) === false);
check("stale: 3h30m old is stale at 180m", M.isStale("2026-08-28T14:30:00Z", NOW, 180) === true);
check("stale: missing ts is stale", M.isStale("", NOW, 180) === true);

check("displayState: stale wins over partial", M.displayState(s, NOW, 60) === "stale");
check("displayState: fresh keeps partial", M.displayState(s, NOW, 600) === "partial");
check("displayState: fresh checkedAt keeps state despite old generatedAt",
  M.displayState(withCheck, NOW, 720) === "partial");

const colors = { foreground: "#fff", urgent: "#a55", muted: "#788" };
check("stateColor: open -> foreground", M.stateColor("open", colors) === "#fff");
check("stateColor: partial -> urgent", M.stateColor("partial", colors) === "#a55");
check("stateColor: stale -> muted", M.stateColor("stale", colors) === "#788");

check("barLabel: partial shows count", M.barLabel(s, "partial", "B") === "B 2", JSON.stringify(M.barLabel(s, "partial", "B")));
check("barLabel: open shows check", M.barLabel(s, "open", "B") === "B ✓");
check("barLabel: closed shows cross", M.barLabel(s, "closed", "B") === "B ✗");
check("barLabel: stale shows ellipsis", M.barLabel(s, "stale", "B") === "B …");
check("barLabel: no glyph -> token only", M.barLabel(s, "partial", "") === "2");

check("summaryLine: partial plural", M.summaryLine(s, "partial") === "2 trails closed");
check("summaryLine: partial singular", M.summaryLine({ closedCount: 1 }, "partial") === "1 trail closed");
check("summaryLine: open", M.summaryLine(s, "open") === "All trails open");

check("relativeTime: 140 min -> 2 h ago", M.relativeTime("2026-08-28T15:40:00Z", NOW) === "2 h ago");
check("relativeTime: <1 min -> just now", M.relativeTime("2026-08-28T17:59:40Z", NOW) === "just now");

const groups = M.groupByArea(s.closedTrails);
check("groupByArea: 2 areas", groups.length === 2);
check("groupByArea: area upper-cased", groups[1].area === "MANIE AREA");
check("groupByArea: note carried", groups[0].trails[0].note === "until 2pm");

const paras = M.noticeParagraphs("Please note the following:\n\nMANIE AREA: 3 Ca du Puncin***NATO BASE AREA: 101 Ingegnere\n\n****************\n\nThank you.");
check("noticeParagraphs: asterisk runs dropped", paras.every(p => !p.includes("*")));
check("noticeParagraphs: split on inline *** and blank lines", paras.length === 4, JSON.stringify(paras));
check("noticeParagraphs: area line intact", paras[1] === "MANIE AREA: 3 Ca du Puncin");

console.log();
if (failures) { console.log(`${failures} failing`); process.exit(1); }
console.log("all green");
