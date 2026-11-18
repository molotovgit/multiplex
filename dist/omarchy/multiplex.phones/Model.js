// What the Multiplex bar widget knows and decides, apart from how it looks,
// so that it can be tested with node (tests/model.test.js).
//
// Everything about a phone comes from `multiplex devices --json`, and a
// phone's name is whatever the phone called itself: it is bounded here,
// shown only as plain text, and only ever handed to a command as one
// argument, never through a shell.

var MAX_PHONES = 16
var MAX_NAME = 200
var SHOWN_NAME = 48
var LOW_BATTERY = 15

var GLYPH = {
  phone: String.fromCodePoint(0xF011C),
  noPhone: String.fromCodePoint(0xF0950),
  send: String.fromCodePoint(0xF048A),
  ring: String.fromCodePoint(0xF009E),
  pair: String.fromCodePoint(0xF0432),
  open: String.fromCodePoint(0xF03CC)
}

// A name fit for one line of a list: no control characters, not endless.
function shownName(name) {
  var text = String(name).replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]+/g, " ").trim()
  var letters = Array.from(text)
  if (letters.length > SHOWN_NAME) text = letters.slice(0, SHOWN_NAME - 1).join("") + "…"
  return text === "" ? "?" : text
}

// The paired phones from what the command printed. Anything that is not
// what the command prints is left out, so a broken answer shows as no
// phones, not as garbage.
function parseDevices(raw) {
  var list
  try {
    list = JSON.parse(String(raw === undefined || raw === null ? "" : raw))
  } catch (e) {
    return []
  }
  if (!(list instanceof Array)) return []
  var phones = []
  for (var i = 0; i < list.length && phones.length < MAX_PHONES; i++) {
    var one = list[i]
    if (!one || typeof one !== "object" || typeof one.name !== "string") continue
    if (one.name === "" || one.name.length > MAX_NAME) continue
    var known = typeof one.battery === "number" && isFinite(one.battery)
    phones.push({
      name: one.name,
      label: shownName(one.name),
      connected: one.connected === true,
      battery: known ? Math.max(0, Math.min(100, Math.round(one.battery))) : null,
      charging: one.charging === true
    })
  }
  return phones
}

function isLow(phone) {
  return !!phone && phone.connected && phone.battery !== null && phone.battery <= LOW_BATTERY && !phone.charging
}

// The whole picture, for the bar icon and the panel's first line. `found`
// is false when the command itself could not be run.
function summary(phones, found) {
  var connected = 0
  var first = null
  var low = false
  for (var i = 0; i < phones.length; i++) {
    if (!phones[i].connected) continue
    connected++
    if (first === null) first = phones[i]
    if (isLow(phones[i])) low = true
  }
  return { found: found !== false, paired: phones.length, connected: connected, first: first, low: low }
}

function icon(state) {
  return state.connected > 0 ? GLYPH.phone : GLYPH.noPhone
}

// Which of the widget's sentences says where things stand: the key, and
// the number that goes with it when it counts something.
function statusKey(state) {
  if (!state.found) return { key: "missing", count: -1 }
  if (state.paired === 0) return { key: "none", count: -1 }
  if (state.connected === 0) return { key: "away", count: -1 }
  return { key: "connected", count: state.connected }
}

// The battery of the first connected phone beside the icon, when asked for.
function barLabel(state, show) {
  if (!show || state.first === null || state.first.battery === null) return ""
  return state.first.battery + "%"
}

// How many of this computer's coding agents wait for an answer, from
// what `multiplex agents` prints (a list with each one's status).
// Anything else is none.
function agentsWaiting(raw) {
  var list
  try {
    list = JSON.parse(String(raw === undefined || raw === null ? "" : raw))
  } catch (e) {
    return 0
  }
  if (!(list instanceof Array)) return 0
  var waiting = 0
  for (var i = 0; i < list.length; i++) {
    if (list[i] && typeof list[i] === "object" && list[i].status === "blocked") waiting++
  }
  return Math.min(waiting, 99)
}

// The bar's words with agents waiting put first: they are the news.
function withWaiting(label, waitingWords) {
  if (!waitingWords) return label
  return label ? waitingWords + " \u00b7 " + label : waitingWords
}

function phoneStatusKey(phone) {
  if (!phone.connected) return "phone.away"
  if (phone.battery === null) return "phone.connected"
  if (phone.charging) return "phone.charging"
  return isLow(phone) ? "phone.low" : "phone.battery"
}

// The places the keyboard can be: one row per phone with Send files and
// Make it ring, then a last row with Pair a phone and Open Multiplex.
function rows(phones) {
  return phones.length + 1
}

// A phone that is not connected cannot be rung, so its row has one place.
function columns(phones, row) {
  if (row >= phones.length) return 2
  return phones[row].connected ? 2 : 1
}

function move(phones, row, col, dx, dy) {
  var nextRow = Math.max(0, Math.min(rows(phones) - 1, row + dy))
  var nextCol = Math.max(0, Math.min(columns(phones, nextRow) - 1, col + dx))
  return { row: nextRow, col: nextCol }
}

function placeAt(phones, row, col) {
  if (row < 0 || row >= rows(phones) || col < 0 || col >= columns(phones, row)) return null
  if (row === phones.length) return { kind: col === 0 ? "pair" : "open" }
  return { kind: col === 0 ? "send" : "ring", phone: phones[row].name }
}

// The command for a place, as separate arguments. Nothing here is ever
// joined into one line for a shell.
function command(bin, place) {
  if (!place || !bin) return []
  if (place.kind === "open") return [bin, "open"]
  if (place.kind === "pair") return [bin, "open", "--pair"]
  if (typeof place.phone !== "string" || place.phone === "") return []
  if (place.kind === "show") return [bin, "open", "--phone", place.phone]
  if (place.kind === "send") return [bin, "open", "--send", place.phone]
  if (place.kind === "ring") return [bin, "ring", "--to", place.phone]
  return []
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_PHONES: MAX_PHONES,
    LOW_BATTERY: LOW_BATTERY,
    GLYPH: GLYPH,
    shownName: shownName,
    parseDevices: parseDevices,
    isLow: isLow,
    summary: summary,
    icon: icon,
    statusKey: statusKey,
    barLabel: barLabel,
    agentsWaiting: agentsWaiting,
    withWaiting: withWaiting,
    phoneStatusKey: phoneStatusKey,
    rows: rows,
    columns: columns,
    move: move,
    placeAt: placeAt,
    command: command
  }
}
