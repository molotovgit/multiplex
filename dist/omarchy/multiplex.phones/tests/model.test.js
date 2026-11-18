// Run with: node --test dist/omarchy/multiplex.phones/tests/
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const M = require("../Model.js")

const two = () => M.parseDevices(JSON.stringify([
  { name: "Sam's Pixel", connected: true, battery: 81, charging: true },
  { name: "Old tablet", connected: false, battery: null, charging: null },
]))

test("the command's list becomes the phones", () => {
  assert.deepEqual(two(), [
    { name: "Sam's Pixel", label: "Sam's Pixel", connected: true, battery: 81, charging: true },
    { name: "Old tablet", label: "Old tablet", connected: false, battery: null, charging: false },
  ])
  assert.deepEqual(M.parseDevices("[]"), [])
})

test("an answer that is not the command's is no phones, not garbage", () => {
  for (const raw of ["", "not json", "{}", "null", "42", '"text"', undefined, null, '[1,"a",null,{},{"name":7},{"name":""}]'])
    assert.deepEqual(M.parseDevices(raw), [], String(raw))
})

test("what a phone says about itself is bounded", () => {
  const many = Array.from({ length: 40 }, (_, i) => ({ name: "Phone " + i, connected: true }))
  assert.equal(M.parseDevices(JSON.stringify(many)).length, M.MAX_PHONES)
  // A battery outside 0 to 100, or not a number, is not believed as it is.
  const odd = M.parseDevices(JSON.stringify([
    { name: "a", connected: true, battery: 250 }, { name: "b", connected: true, battery: -3 },
    { name: "c", connected: true, battery: "81" }, { name: "d", connected: true, battery: 49.6 },
    { name: "e", connected: "yes", charging: "yes" },
  ]))
  assert.deepEqual(odd.map(p => p.battery), [100, 0, null, 50, null])
  assert.equal(odd[4].connected, false)
  assert.equal(odd[4].charging, false)
  // A name too long to be one is left out; a long one is cut for showing only.
  assert.deepEqual(M.parseDevices(JSON.stringify([{ name: "x".repeat(5000), connected: true }])), [])
  const long = M.parseDevices(JSON.stringify([{ name: "N".repeat(120), connected: true }]))[0]
  assert.equal(long.name.length, 120)
  assert.equal(Array.from(long.label).length, 48)
  assert.ok(long.label.endsWith("…"))
})

test("a name with line breaks or markup stays one plain line, and the real name is kept for the command", () => {
  const name = "Evil\n<img src=\"https://example.invalid/t\">\u0007\u2028phone"
  const phone = M.parseDevices(JSON.stringify([{ name, connected: true }]))[0]
  assert.equal(phone.name, name)
  assert.equal(phone.label, 'Evil <img src="https://example.invalid/t"> phone')
  assert.ok(!/[\u0000-\u001f\u2028]/.test(phone.label))
  assert.equal(M.shownName(" \n "), "?")
  // The name goes to the command as one argument, whatever is in it.
  assert.deepEqual(M.command("multiplex", { kind: "ring", phone: "a; rm -rf ~ $(x) `y`" }), ["multiplex", "ring", "--to", "a; rm -rf ~ $(x) `y`"])
})

test("the bar icon says whether a phone is connected", () => {
  const none = M.summary([], true)
  assert.deepEqual([none.paired, none.connected, none.first, none.low], [0, 0, null, false])
  assert.equal(M.icon(none), M.GLYPH.noPhone)
  const state = M.summary(two(), true)
  assert.deepEqual([state.paired, state.connected, state.first.name, state.low], [2, 1, "Sam's Pixel", false])
  assert.equal(M.icon(state), M.GLYPH.phone)
  const away = M.summary(M.parseDevices('[{"name":"a","connected":false,"battery":50}]'), true)
  assert.equal(M.icon(away), M.GLYPH.noPhone)
})

test("the sentence for where things stand", () => {
  assert.deepEqual(M.statusKey(M.summary([], false)), { key: "missing", count: -1 })
  assert.deepEqual(M.statusKey(M.summary([], true)), { key: "none", count: -1 })
  assert.deepEqual(M.statusKey(M.summary(M.parseDevices('[{"name":"a","connected":false}]'), true)), { key: "away", count: -1 })
  assert.deepEqual(M.statusKey(M.summary(two(), true)), { key: "connected", count: 1 })
  const both = M.parseDevices('[{"name":"a","connected":true},{"name":"b","connected":true}]')
  assert.deepEqual(M.statusKey(M.summary(both)), { key: "connected", count: 2 })
})

test("a low battery is one that is running down", () => {
  const at = (battery, charging, connected = true) => M.parseDevices(JSON.stringify([{ name: "a", connected, battery, charging }]))[0]
  assert.equal(M.isLow(at(15, false)), true)
  assert.equal(M.isLow(at(16, false)), false)
  assert.equal(M.isLow(at(5, true)), false)
  assert.equal(M.isLow(at(5, false, false)), false)
  assert.equal(M.isLow(at(null, false)), false)
  assert.equal(M.summary([at(9, false)]).low, true)
  assert.deepEqual([at(9, false), at(60, false), at(60, true), at(null, false), at(60, false, false)].map(M.phoneStatusKey),
    ["phone.low", "phone.battery", "phone.charging", "phone.connected", "phone.away"])
})

test("the battery beside the icon is the first connected phone's, when asked for", () => {
  assert.equal(M.barLabel(M.summary(two()), true), "81%")
  assert.equal(M.barLabel(M.summary(two()), false), "")
  assert.equal(M.barLabel(M.summary([]), true), "")
  // Agents that wait for an answer come first in the bar's words.
  const agents = JSON.stringify([{ status: "blocked" }, { status: "working" }, { status: "blocked" }, null, { status: 3 }])
  assert.equal(M.agentsWaiting(agents), 2)
  assert.equal(M.agentsWaiting("[]"), 0)
  assert.equal(M.agentsWaiting("not json"), 0)
  assert.equal(M.agentsWaiting('{"status":"blocked"}'), 0)
  assert.equal(M.agentsWaiting(undefined), 0)
  assert.equal(M.withWaiting("81%", "2 waiting"), "2 waiting \u00b7 81%")
  assert.equal(M.withWaiting("", "2 waiting"), "2 waiting")
  assert.equal(M.withWaiting("81%", ""), "81%")
  assert.equal(M.barLabel(M.summary(M.parseDevices('[{"name":"a","connected":true}]')), true), "")
})

test("the keyboard moves over each phone's actions and the last row", () => {
  const phones = two()
  assert.equal(M.rows(phones), 3)
  assert.deepEqual([0, 1, 2].map(row => M.columns(phones, row)), [2, 1, 2])
  assert.deepEqual(M.move(phones, 0, 0, 1, 0), { row: 0, col: 1 })
  assert.deepEqual(M.move(phones, 0, 1, 1, 0), { row: 0, col: 1 })
  // Down from Make it ring onto a phone that cannot be rung: its one place.
  assert.deepEqual(M.move(phones, 0, 1, 0, 1), { row: 1, col: 0 })
  assert.deepEqual(M.move(phones, 1, 0, 1, 0), { row: 1, col: 0 })
  assert.deepEqual(M.move(phones, 1, 0, 0, 1), { row: 2, col: 0 })
  assert.deepEqual(M.move(phones, 2, 1, 0, 1), { row: 2, col: 1 })
  assert.deepEqual(M.move(phones, 0, 0, 0, -1), { row: 0, col: 0 })
  assert.deepEqual(M.move([], 0, 0, 1, 1), { row: 0, col: 1 })
})

test("each place is one command, as separate arguments", () => {
  const phones = two()
  const at = (row, col) => M.command("/usr/bin/multiplex", M.placeAt(phones, row, col))
  assert.deepEqual(at(0, 0), ["/usr/bin/multiplex", "open", "--send", "Sam's Pixel"])
  assert.deepEqual(at(0, 1), ["/usr/bin/multiplex", "ring", "--to", "Sam's Pixel"])
  assert.deepEqual(at(1, 0), ["/usr/bin/multiplex", "open", "--send", "Old tablet"])
  // A phone that is not connected has no Make it ring.
  assert.equal(M.placeAt(phones, 1, 1), null)
  assert.deepEqual(at(1, 1), [])
  assert.deepEqual(at(2, 0), ["/usr/bin/multiplex", "open", "--pair"])
  assert.deepEqual(at(2, 1), ["/usr/bin/multiplex", "open"])
  assert.deepEqual(M.command("multiplex", { kind: "show", phone: "Old tablet" }), ["multiplex", "open", "--phone", "Old tablet"])
  for (const bad of [null, {}, { kind: "ring" }, { kind: "ring", phone: "" }, { kind: "ring", phone: 7 }, { kind: "erase", phone: "a" }])
    assert.deepEqual(M.command("multiplex", bad), [], JSON.stringify(bad))
  assert.deepEqual(M.command("", { kind: "open" }), [])
})

test("the widget has a sentence for everything it can say, and shows phone text as plain text only", () => {
  const dir = path.join(__dirname, "..")
  const strings = JSON.parse(fs.readFileSync(path.join(dir, "i18n", "en.json"), "utf8"))
  for (const key of ["missing", "none", "away", "connected"]) {
    assert.ok(strings["status." + key], "status." + key)
    assert.ok(strings["tooltip." + key], "tooltip." + key)
  }
  for (const key of ["phone.away", "phone.connected", "phone.battery", "phone.charging", "phone.low"]) assert.ok(strings[key], key)
  const qml = fs.readFileSync(path.join(dir, "Panel.qml"), "utf8")
  // Every key the panel asks for exists.
  for (const [, key] of qml.matchAll(/strings\.tn?\("([^"]+)"\s*[,)]/g)) assert.ok(strings[key], "en.json lacks " + key)
  // Every Text of the panel's own says it is plain text: a phone's name
  // must never be read as markup.
  const texts = qml.split(/\n\s*Text \{/).slice(1)
  assert.ok(texts.length > 3)
  for (const one of texts) assert.ok(/textFormat: Text\.PlainText/.test(one.split("}")[0] + one.slice(0, 400)), "a Text without PlainText: " + one.slice(0, 80))
  // A phone's name is never handed to a tooltip, whose text format is not ours.
  for (const line of qml.split("\n")) if (/tooltipText:/.test(line)) assert.ok(!/label|\.name|phone\./.test(line), line)
  // The manifest and the panel agree on who they are.
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"))
  assert.equal(manifest.id, "multiplex.phones")
  assert.ok(qml.includes('moduleName: "' + manifest.id + '"'))
  assert.equal(manifest.entryPoints.barWidget, "Panel.qml")
})
