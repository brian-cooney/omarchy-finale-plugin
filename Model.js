// Pure helpers for the Finale MTB trail-status widget and its panel.
// Qt-free so it can be unit tested under node (see test/model-test.js);
// the QML owns rendering, timers, and the curl fetch.

var MS_PER_MIN = 60000;

// Compact status tokens shown after the glyph in the bar label.
var TOKEN_OPEN = "✓";    // check mark
var TOKEN_CLOSED = "✗";  // ballot X
var TOKEN_UNKNOWN = "…"; // horizontal ellipsis
var SPACE = " ";

// Parse the status.json payload. Returns null on anything unparseable so the
// widget can keep showing the previous good value.
function parseStatus(raw) {
  try {
    var data = JSON.parse(String(raw || ""));
    if (!data || typeof data !== "object") return null;
    var summary = data.summary && typeof data.summary === "object" ? data.summary : {};
    return {
      generatedAt: typeof data.generated_at === "string" ? data.generated_at : "",
      source: typeof data.source === "string" ? data.source : "",
      asOfDate: typeof data.as_of_date === "string" ? data.as_of_date : "",
      state: normalizeState(summary.state),
      closedCount: intOr(summary.closed_count, Array.isArray(data.closed_trails) ? data.closed_trails.length : 0),
      closedTrails: Array.isArray(data.closed_trails) ? data.closed_trails.filter(isTrail) : [],
      notices: Array.isArray(data.notices) ? data.notices.filter(isNotice) : []
    };
  } catch (e) {
    return null;
  }
}

function isTrail(t) { return t && typeof t === "object" && typeof t.trail === "string" && t.trail !== ""; }
function isNotice(n) { return n && typeof n === "object" && (typeof n.text === "string" || typeof n.title === "string"); }

function intOr(value, fallback) {
  var n = parseInt(value, 10);
  return isFinite(n) && n >= 0 ? n : fallback;
}

function normalizeState(state) {
  var s = String(state || "").toLowerCase();
  return (s === "open" || s === "partial" || s === "closed" || s === "unknown") ? s : "unknown";
}

// Minutes since generatedAt, or Infinity when it can't be read.
function ageMinutes(generatedAtIso, now) {
  var then = Date.parse(String(generatedAtIso || ""));
  if (!isFinite(then)) return Infinity;
  return (now.getTime() - then) / MS_PER_MIN;
}

function isStale(generatedAtIso, now, staleMinutes) {
  var limit = intOr(staleMinutes, 180) || 180;
  return ageMinutes(generatedAtIso, now) > limit;
}

// Effective state for display: stale data can't be trusted to still be current.
function displayState(status, now, staleMinutes) {
  if (!status) return "unknown";
  if (isStale(status.generatedAt, now, staleMinutes)) return "stale";
  return status.state;
}

// Colour for a display state. `colors` carries the theme tokens
// { foreground, urgent, muted } so this stays Qt-free.
function stateColor(displayStateValue, colors) {
  var c = colors || {};
  switch (displayStateValue) {
    case "open":    return c.foreground;
    case "partial": return c.urgent;
    case "closed":  return c.urgent;
    default:        return c.muted; // unknown / stale
  }
}

// Short bar label: an icon glyph followed by a compact status token.
function barLabel(status, displayStateValue, glyph) {
  var icon = glyph || "";
  var token;
  switch (displayStateValue) {
    case "open":    token = TOKEN_OPEN; break;
    case "partial": token = String(status ? status.closedCount : "?"); break;
    case "closed":  token = TOKEN_CLOSED; break;
    default:        token = TOKEN_UNKNOWN; break;
  }
  return icon ? icon + SPACE + token : token;
}

// One-line summary for the panel header and the tooltip.
function summaryLine(status, displayStateValue) {
  switch (displayStateValue) {
    case "open":
      return "All trails open";
    case "partial":
      var n = status ? status.closedCount : 0;
      return n === 1 ? "1 trail closed" : n + " trails closed";
    case "closed":
      return "Full network closure";
    case "stale":
      return "Status may be out of date";
    default:
      return "Trail status unavailable";
  }
}

// "just now" / "12 min ago" / "3 h ago" / "2 days ago".
function relativeTime(fromIso, now) {
  var mins = ageMinutes(fromIso, now);
  if (!isFinite(mins)) return "";
  if (mins < 1) return "just now";
  if (mins < 60) return Math.round(mins) + " min ago";
  var hours = mins / 60;
  if (hours < 24) return Math.round(hours) + " h ago";
  var days = Math.round(hours / 24);
  return days === 1 ? "1 day ago" : days + " days ago";
}

// Group the flat closed-trail list by area, preserving first-seen order.
function groupByArea(closedTrails) {
  var order = [];
  var byArea = {};
  var list = closedTrails || [];
  for (var i = 0; i < list.length; i++) {
    var area = String(list[i].area || "OTHER").toUpperCase();
    if (!byArea[area]) { byArea[area] = []; order.push(area); }
    byArea[area].push({ trail: String(list[i].trail || ""), note: String(list[i].note || "") });
  }
  return order.map(function (area) { return { area: area, trails: byArea[area] }; });
}

// Collapse the source's separator runs / hard wraps into readable paragraphs.
// The source uses runs of "*" both as inline area separators ("AREA: x***
// AREA: y") and as a standalone divider bar before the boilerplate.
function noticeParagraphs(text) {
  return String(text || "")
    .replace(/\r\n?/g, "\n")
    .split(/\n{2,}|\*{2,}/)
    .map(function (p) { return p.replace(/\s*\n\s*/g, " ").trim(); })
    .filter(function (p) { return p !== "" && !/^[\s*]+$/.test(p); });
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    ageMinutes: ageMinutes,
    isStale: isStale,
    displayState: displayState,
    stateColor: stateColor,
    barLabel: barLabel,
    summaryLine: summaryLine,
    relativeTime: relativeTime,
    groupByArea: groupByArea,
    noticeParagraphs: noticeParagraphs
  };
}
