# Localization. One language at a time, chosen in the settings overlay and
# stored in user://settings.json; "en" is the source language and costs nothing
# (every lookup short-circuits to the English string the call site already
# passes as its fallback).
#
# A translation is data, not code: everything lives under  data/loc/<lang>/
# and is loaded lazily, one file at a time, the first time something asks for it.
#
#   ui.json        UI chrome, keyed by a dotted key   ("title.play")
#   terms.json     the keyword glossary, grouped      ("condition" -> "prone")
#   features.json  feature id -> name                 ("fighter-second-wind")
#   names.json     every other bare id that reaches a label: resource pools
#                  ("rage"), choice types ("skill-choice"), class ids
#   records/<file>.json
#                  per data/*.json overrides, id -> the fields to replace
#                  ({"barbarian": {"name": "Barbar"}}) — folded into the
#                  records themselves by core/rules/catalog.gd, so every
#                  existing reader of record["name"] gets the translation
#                  without knowing this file exists
#
# Nothing here ever fails loudly: a missing file, a missing key, a language
# with no table at all — each of them falls through to the English text the
# caller supplied. A half-finished translation is a playable game.
#
# Tests and tools pin the language with the SORCMERC_LANG env var, the same
# debug-gate shape as SORCMERC_SEED/SORCMERC_FAST; it wins over the setting.
extends RefCounted

const Settings = preload("res://core/settings.gd")

const DIR := "res://data/loc/"
const DEFAULT := "en"

# What the settings picker offers. `label` is the language's own name — the one
# thing on that screen that must never be translated.
const LANGS := [
	{"id": "en", "label": "English"},
	{"id": "tr", "label": "Türkçe"},
]

static var _lang := ""
static var _tables := {}          # section path -> Dictionary (missing file caches as {})

static func codes() -> Array:
	var out := []
	for l in LANGS:
		out.append(String(l["id"]))
	return out

static func supported(code: String) -> bool:
	return code in codes()

static func label_of(code: String) -> String:
	for l in LANGS:
		if l["id"] == code:
			return String(l["label"])
	return code

# The language in force. Cached, because it is read on nearly every string.
static func lang() -> String:
	if _lang == "":
		var env := OS.get_environment("SORCMERC_LANG")
		_lang = env if supported(env) else Settings.current().language
		if not supported(_lang):
			_lang = DEFAULT
	return _lang

# Switch languages: drops every cached table AND the catalog's parsed data,
# since the record overlay is folded in at parse time. Catalog is loaded rather
# than preloaded — it preloads *this* file, and a cycle between the two would
# not resolve.
static func set_lang(code: String) -> void:
	if not supported(code) or code == lang():
		return
	_lang = code
	_tables.clear()
	load("res://core/rules/catalog.gd").reset()

# Drop the caches without changing language (a test that rewrote a table, a
# language file edited while the game is open).
static func reload() -> void:
	_lang = ""
	_tables.clear()

static func _table(section: String) -> Dictionary:
	var l := lang()
	if l == DEFAULT:
		return {}
	var key := l + "/" + section
	if not _tables.has(key):
		var txt := FileAccess.get_file_as_string(DIR + key + ".json")
		var d = JSON.parse_string(txt) if not txt.is_empty() else null
		_tables[key] = d if d is Dictionary else {}
	return _tables[key]

# --- strings ---------------------------------------------------------------

# UI chrome. `fallback` is the English text, so a call site reads as the string
# it displays:  Loc.t("title.play", "New campaign")
static func t(key: String, fallback := "") -> String:
	var s = _table("ui").get(key)
	return String(s) if s is String and s != "" else (fallback if fallback != "" else key)

# The same, with a format string's arguments applied after the lookup. The
# translation must keep the placeholders and may reorder them.
static func tf(key: String, fallback: String, args: Array) -> String:
	return t(key, fallback) % args

# A glossary word: a condition, a damage type, an ability, a school. Grouped so
# "light" the armour category and "light" the weapon property can differ, which
# in Turkish they do ("hafif zırh" vs "hafif silah" share a word; "keen" and
# "charmed" do not).
static func term(group: String, id: String, fallback := "") -> String:
	var g = _table("terms").get(group)
	if g is Dictionary:
		var s = g.get(id)
		if s is String and s != "":
			return String(s)
	return fallback if fallback != "" else id

# The display name for a bare id — a feature ("fighter-second-wind" -> "İkinci
# Nefes"), a resource pool ("rage"), a choice type ("skill-choice"): everything
# that would otherwise reach a humanize() that just knocks the hyphens out.
# Empty when the language has no name for it, which is what keeps humanize()
# as the fallback rather than the exception.
static func name_of(id: String) -> String:
	var s = _table("features").get(id)
	if s is String and s != "":
		return String(s)
	s = _table("names").get(id)
	return String(s) if s is String else ""

# --- records ---------------------------------------------------------------

# `data` as it should read in this language. Called by catalog.gd once per data
# file, after the content packs have had their turn, so a pack's own record is
# translated too when the language names its id.
#
# Array files (spells, classes, monsters) match on the record's `id`;
# dictionary files (skills, conditions) on the key. Only the fields the
# translation actually carries are replaced — a table that gives a name and no
# description leaves the English description in place.
static func localize_records(file: String, data):
	if lang() == DEFAULT or data == null:
		return data
	var tbl := _table("records/" + file.get_basename())
	if tbl.is_empty():
		return data
	if data is Dictionary:
		var out := {}
		for k in data:
			out[k] = _merged(data[k], tbl.get(k))
		return out
	if data is Array:
		var list := []
		for r in data:
			list.append(_merged(r, tbl.get(r["id"]) if r is Dictionary and r.has("id") else null))
		return list
	return data

static func _merged(record, fields):
	if not (record is Dictionary) or not (fields is Dictionary) or fields.is_empty():
		return record
	var out: Dictionary = record.duplicate()
	out.merge(fields, true)
	return out
