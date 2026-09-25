# D7 — placement: which counter posts which kind of job, and how far a
# settlement's interest in a target reaches. The point of the feature is that
# two settlements on the same map do NOT post the same list, so most of what is
# checked here is what a place does not offer.
#   godot --headless --path . -s tests/test_quest_posting.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Visit = preload("res://core/settlement_visit.gd")
const Posting = preload("res://core/quest_posting.gd")
const Quest = preload("res://core/quest.gd")
const Party = preload("res://core/party.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ladder = preload("res://core/ladder.gd")
const Regions = preload("res://core/regions.gd")
const RNG = preload("res://core/rng.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	FactionOpinion.reset()
	test_kinds_are_declared_once()
	test_counters_decide_what_a_place_posts()
	test_a_camp_is_not_a_city()
	test_reach_keeps_a_job_local()
	test_supply_orders()
	test_deliver_and_scout()
	test_rescue_offer()
	test_raid_premium_and_rescue()
	test_patron_and_renown()
	test_the_whole_settlement_can_run_out_of_work()
	test_quest_xp_is_the_countrys_fights()
	FactionOpinion.reset()
	print("test_quest_posting: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- fixtures --------------------------------------------------------------

# Riverhold (city) at the centre with a town, a camp and a hostile city around
# it; one hostile band and two lairs, one of them deliberately far enough out to
# be nobody's problem.
func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(420, -180), "elf", "town"))
	w.add_settlement(World.Settlement.new("dun-arrow", Vector2(-360, 260), "dwarf", "camp"))
	w.add_settlement(World.Settlement.new("ashfell", Vector2(160, 470), "orc", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	w.add_party(World.RoamingParty.new("raiders", Vector2(200, 200), "bandit"))
	w.add_lair(World.Lair.new("warren", Vector2(-300, 300), "goblinoid"))
	w.add_lair(World.Lair.new("far-barrow", Vector2(4000, 4000), "undead"))
	return w

func _party() -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

func _at(s, party, w) -> Array:
	return Visit.quest_offers(s, party, w)

func _kinds(job_offers: Array) -> Array:
	var out: Array = []
	for q in job_offers:
		if not out.has(q["kind"]):
			out.append(String(q["kind"]))
	out.sort()
	return out

func _by_id(job_offers: Array, prefix: String) -> Dictionary:
	for q in job_offers:
		if String(q["id"]).begins_with(prefix):
			return q
	return {}

# --- the tables ------------------------------------------------------------

func test_kinds_are_declared_once() -> void:
	for kind in Quest.KINDS:
		check(Posting.PLACEMENT.has(kind), "%s has a placement rule" % kind)
		check(Quest.TARGET_FIELD.has(kind), "%s names its target field" % kind)
	for kind in Posting.PLACEMENT:
		check(Quest.KINDS.has(kind), "%s is a kind the log can track" % kind)
		check(not Posting.PLACEMENT[kind]["counters"].is_empty(),
			"%s has somebody to post it" % kind)

# --- placement -------------------------------------------------------------

func test_counters_decide_what_a_place_posts() -> void:
	var w := _world()
	var party := _party()
	var city := _at(w.settlements[0], party, w)
	var town := _at(w.settlements[1], party, w)

	# Every job knows whose it is, and that counter is standing in the building.
	for q in city:
		check(Visit.services(w.settlements[0]).has(String(q["counter"])),
			"%s is posted by a counter the city actually has" % q["id"])
		check(Posting.PLACEMENT[q["kind"]]["counters"].has(String(q["counter"])),
			"%s is posted by a counter its kind allows" % q["id"])

	# A town has no armourer, librarian or healer, so it never has their orders.
	var town_counters: Array = []
	for q in town:
		if not town_counters.has(String(q["counter"])):
			town_counters.append(String(q["counter"]))
	for missing in ["armorsmith", "librarian", "healer"]:
		check(not town_counters.has(missing), "a town posts nothing at the %s it does not have" % missing)

	# Ordering a settlement sacked is a city's business only — and, since
	# contracts (core/contracts.gd), only for a company that city's people know.
	check(not _kinds(city).has("raid_settlement"), "the city does not post war work to strangers")
	Ladder.deed(w.settlements[0].faction, Ladder.RUNG_AT[Ladder.KNOWN])
	city = _at(w.settlements[0], party, w)
	check(_kinds(city).has("raid_settlement"), "the city posts the raid to a company it knows")
	check(not _kinds(town).has("raid_settlement"), "the town does not")
	Ladder.reset()
	city = _at(w.settlements[0], party, w)
	# ...and a city does not need telling what the next ring out looks like.
	check(not _kinds(city).has("scout_region"), "the city posts no scouting")
	check(_kinds(town).has("scout_region"), "the town, with its back to it, does")

func test_a_camp_is_not_a_city() -> void:
	var w := _world()
	var party := _party()
	var camp = w.settlements[2]
	check(Visit.services(camp) == ["generalist"], "a camp is one counter deep")
	var jobs := _at(camp, party, w)
	check(not jobs.is_empty(), "...which is not the same as having no work")
	for q in jobs:
		check(String(q["counter"]) == "generalist", "everything at a camp is the generalist's")
	var kinds := _kinds(jobs)
	# No innkeeper, so none of the innkeeper's kinds — the whole mechanism.
	for gone in ["kill_count", "collect_item", "hunt_party", "raid_settlement"]:
		check(not kinds.has(gone), "a camp has no innkeeper and so no %s job" % gone)
	# The lair down the valley is still everybody's problem, generalist or not.
	check(kinds.has("clear_lair"), "the lair nearby is still the camp's problem")
	check(kinds.has("deliver_goods") and kinds.has("scout_region"),
		"a camp carts and scouts")

func test_reach_keeps_a_job_local() -> void:
	var w := _world()
	var party := _party()
	var city = w.settlements[0]
	var near := _at(city, party, w)
	check(not _by_id(near, "world:clear_lair:warren").is_empty(),
		"the lair inside reach is posted")
	check(_by_id(near, "world:clear_lair:far-barrow").is_empty(),
		"the one four thousand units out is not")

	# Walk the band out past the innkeeper's reach and the bounty comes down.
	check(not _by_id(near, "world:hunt_party:raiders").is_empty(), "the band nearby is hunted")
	w.parties[1].position = Vector2(0, Posting.PLACEMENT["hunt_party"]["reach"] + 50.0)
	check(_by_id(_at(city, party, w), "world:hunt_party:raiders").is_empty(),
		"a band that has ridden out of reach is no longer this town's problem")

# --- the three new kinds ---------------------------------------------------

func test_supply_orders() -> void:
	var w := _world()
	var party := _party()
	var city = w.settlements[0]
	var order := _by_id(_at(city, party, w), "supply:riverhold:armorsmith")
	check(not order.is_empty(), "the armourer has an order out")
	check(order["kind"] == "supply_item" and order.has("target_item_id"), "...for a specific item")
	check(int(order["reward"]["gold"]) > 0, "...and pays for it")
	check(order["id"] == Posting.supply_offer(city, "armorsmith")["id"],
		"the same counter asks for the same thing every time you walk back in")

	# Progress is a reading of the pack, both ways.
	var item := String(order["target_item_id"])
	var need := int(order["required"])
	check(Quest.accept(party, order), "the order can be taken")
	Quest.record_stash(party)
	check(int(order["progress"]) == 0, "nothing in the pack, no progress")
	party.stash_add(item, need)
	Quest.record_stash(party)
	check(int(order["progress"]) == need and order["state"] == "complete", "the goods complete it")
	party.stash_remove(item, 1)
	Quest.record_stash(party)
	check(order["state"] == "active", "selling one on the way back un-completes it")
	party.stash_add(item, 1)
	Quest.record_stash(party)
	var gold0: int = party.gold
	check(Quest.turn_in(party, order, city.faction), "handing the goods over pays")
	check(party.gold > gold0, "...in gold")
	check(party.stash_count(item) == 0, "...and the goods are handed over, not kept")

	# A counter whose catalog has nothing in the errand price range posts nothing.
	check(Posting.supply_candidates("innkeeper").is_empty(), "the innkeeper stocks nothing to fetch")
	check(Posting.supply_offer(city, "innkeeper").is_empty(), "...and so orders nothing")
	# Wording: an order for one is an order for one, and the plural goes on the
	# head noun, not the tail.
	check(Posting.want("Chain Mail", 1) == "a Chain Mail", "one reads as one")
	check(Posting.want("Arrow", 3) == "3 Arrows", "three read as three")
	check(Posting.want("Potion of Climbing", 5) == "5 Potions of Climbing",
		"the plural lands on the potion, not the climbing")

func test_deliver_and_scout() -> void:
	var w := _world()
	var party := _party()
	var town = w.settlements[1]
	var run := _by_id(_at(town, party, w), "deliver:greenmarch:")
	check(not run.is_empty(), "the generalist has a crate to move")
	check(Quest.get_quest(party, String(run["id"])).is_empty(), "...that is not already logged")
	var dest := String(run["target_settlement_id"])
	check(dest != town.id, "a crate does not get carried to where it already is")
	var civilized := false
	for s in w.settlements:
		if s.id == dest:
			civilized = s.faction in ["human", "elf", "dwarf", "soldier"]
	check(civilized, "...and it goes somewhere that will take delivery")
	Quest.accept(party, run)
	Quest.record_settlement_visited(party, town.id)
	check(run["state"] == "active", "walking back in the door you left by delivers nothing")
	Quest.record_settlement_visited(party, dest)
	check(run["state"] == "complete", "walking in the far gate is the job")

	var scout := _by_id(_at(town, party, w), "scout:greenmarch:")
	check(not scout.is_empty(), "the town wants the next ring out looked at")
	var here: String = Regions.band_of(w, town.position)
	check(String(scout["target_region_id"]) != here, "it is sent somewhere the town is not")
	Quest.accept(party, scout)
	Quest.record_region_reached(party, here)
	check(scout["state"] == "active", "standing at home is not scouting")
	Quest.record_region_reached(party, String(scout["target_region_id"]))
	check(scout["state"] == "complete", "riding out into the band is")

	# A settlement in the last band has nothing further to ask about.
	var edge = World.Settlement.new("world-s-end", Vector2(9000, 9000), "human", "town")
	w.add_settlement(edge)
	check(Posting.scout_offer(edge, w).is_empty(), "the far deeps send nobody further out")

# --- the floor -------------------------------------------------------------

func test_the_whole_settlement_can_run_out_of_work() -> void:
	var w := _world()
	var party := _party()
	var city = w.settlements[0]
	check(not _at(city, party, w).is_empty(), "a neutral city has work")
	FactionOpinion.set_opinion(city.faction, FactionOpinion.QUEST_MIN - 1.0)
	check(_at(city, party, w).is_empty(),
		"a faction that dislikes you has no work for you at ANY of its counters")
	FactionOpinion.reset()

	# Taking every job leaves the place empty rather than re-offering them.
	var taken := 0
	for q in _at(city, party, w):
		if Quest.accept(party, q):
			taken += 1
	check(taken > 0, "the city's jobs can all be taken (%d)" % taken)
	for q in _at(city, party, w):
		check(Quest.get_quest(party, String(q["id"])).is_empty(),
			"%s is offered again after being taken" % q["id"])

func test_rescue_offer() -> void:
	var Site = load("res://core/site.gd")
	var w := _world()
	var p := _party()
	# a lair with captives in it, near the city, and a spent one beside it
	var held = null
	for i in 400:
		var l = World.Lair.new("pens-%d" % i, Vector2(120, 60), "goblinoid")
		if Site.pens_ahead(l):
			held = l
			break
	check(held != null, "a lair with pens exists")
	w.add_lair(held)
	var city = w.settlements[0]
	var q: Dictionary = Posting.rescue_offer(city, w, p)
	check(q["kind"] == "rescue" and q["target_lair_id"] == held.id and q["title"].begins_with("Bring back "),
		"the city posts a rescue about it: %s" % q.get("title", ""))
	check(int(q["reward"]["gold"]) >= Posting.RESCUE_BASE, "...that pays at least the base")
	check(_kinds(_at(city, p, w)).has("rescue"), "...on its board")
	held.looted = true
	check(Posting.rescue_offer(city, w, p).is_empty(), "a spent lair holds nobody")
	held.looted = false
	held.position = Vector2(0, Posting.PLACEMENT["rescue"]["reach"] + 50.0)
	check(Posting.rescue_offer(city, w, p).is_empty(), "out of reach, out of mind")

func test_raid_premium_and_rescue() -> void:
	var Site = load("res://core/site.gd")
	var w := _world()
	var p := _party()
	var city = w.settlements[0]
	var warren = w.lairs[0]
	var rng_a = RNG.new(7)
	var plain: Dictionary = Quest._world_quest_from_pick(
		{"kind": "clear_lair", "id": warren.id, "name": warren.sname, "faction": warren.faction}, city, p, rng_a)
	city.raided_by = warren.id
	var rng_b = RNG.new(7)
	var dear: Dictionary = Quest._world_quest_from_pick(
		{"kind": "clear_lair", "id": warren.id, "name": warren.sname, "faction": warren.faction}, city, p, rng_b)
	check(int(dear["reward"]["gold"]) == int(int(plain["reward"]["gold"]) * Quest.RAID_PREMIUM),
		"the raiding lair's job pays RAID_PREMIUM (%d -> %d)" % [plain["reward"]["gold"], dear["reward"]["gold"]])
	var rng_c = RNG.new(7)
	var other: Dictionary = Quest._world_quest_from_pick(
		{"kind": "clear_lair", "id": "far-barrow", "name": "Far Barrow", "faction": "undead"}, city, p, rng_c)
	check(int(other["reward"]["gold"]) == int(plain["reward"]["gold"]), "another lair's job does not")
	# the rescue names the raider, even when a nearer lair has pens too. The
	# interior is seeded off the lair's id (core/site.gd), so each is found by
	# trying ids until one has pens — never renamed after the fact.
	var near = null
	var far = null
	for i in 400:
		var l = World.Lair.new("pens-%d" % i, Vector2(120, 60), "goblinoid")
		if Site.pens_ahead(l):
			near = l
			break
	for i in 400:
		var l = World.Lair.new("raider-%d" % i, Vector2(500, 0), "goblinoid", "the Raider Hole")
		if Site.pens_ahead(l):
			far = l
			break
	check(near != null and far != null, "two lairs with pens")
	w.add_lair(near)
	w.add_lair(far)
	city.raided_by = far.id
	var q: Dictionary = Posting.rescue_offer(city, w, p)
	check(q["target_lair_id"] == far.id and q["title"] == "Bring back the people taken in the raid from the Raider Hole",
		"the rescue is from the raiding lair, and says who (%s)" % q.get("title", ""))
	city.raided_by = ""
	check(Posting.rescue_offer(city, w, p)["target_lair_id"] == near.id, "lifted, the nearest pens win again")

# The design audit §5.3: a job's XP is N typical fights of the posting's own
# country (Quest.XP_FIGHTS x Regions.fight_xp at the level a fight there is
# pinned to), not its purse x2 — so renown and regard, which multiply the
# purse, leave it alone, and the same job pays more XP further out.
func test_quest_xp_is_the_countrys_fights() -> void:
	Ladder.reset()
	FactionOpinion.reset()
	var w := _world()
	var p := _party()
	var city = w.settlements[0]
	var jobs: Array = _at(city, p, w)
	check(not jobs.is_empty(), "the city posts work")
	var fx: int = Regions.fight_xp(Regions.level_here(w, city.position, p))
	check(fx > 0, "a fight here is worth something (%d XP)" % fx)
	var all_stamped := true
	for q in jobs:
		var want: int = Quest.xp_for(String(q["kind"]), fx, int(q.get("chain_tier", 0)))
		if int(q["reward"].get("xp", -1)) != want or Quest.xp_reward(q) != want:
			all_stamped = false
			printerr("    %s: xp %s, want %d" % [q["id"], q["reward"].get("xp"), want])
	check(all_stamped, "every job carries N fights of this country's XP")
	# Renown multiplies the gold; the XP stays.
	Ladder.deed("elf", 6)                             # Hirelings, +10 % gold
	var dear: Array = _at(city, p, w)
	var same := dear.size() == jobs.size()
	for i in mini(dear.size(), jobs.size()):
		same = same and int(dear[i]["reward"]["xp"]) == int(jobs[i]["reward"]["xp"])
	check(same, "renown raises the purse and not the lesson")
	Ladder.reset()
	# Fight XP grows with the level a country pins a fight to, so the same kind
	# of job teaches more in the Deeps than in the Heartland.
	check(Regions.fight_xp(10) > 3 * Regions.fight_xp(1), "a level-10 fight is worth over three level-1 fights (%d vs %d)" % [Regions.fight_xp(10), Regions.fight_xp(1)])
	check(Quest.xp_for("clear_lair", Regions.fight_xp(1)) == 3 * Regions.fight_xp(1), "clearing a lair is three fights' worth")
	check(Quest.xp_for("clear_lair", 100, 2) == 500, "...and a chain's third job five")
	# Turning it in pays exactly that, split the way a fight's is.
	var q: Dictionary = jobs[0].duplicate(true)
	q["state"] = "complete"
	q["progress"] = int(q["required"])
	if q["kind"] in ["collect_item", "supply_item"]:
		p.stash_add(String(q["target_item_id"]), int(q["required"]))
	var before := 0
	for ch in p.party_characters():
		before += int(ch.xp)
	check(Quest.turn_in(p, q, city.faction), "the job turns in")
	var after := 0
	for ch in p.party_characters():
		after += int(ch.xp)
	var share: int = Quest.xp_reward(q) / p.party_characters().size()
	check(after - before == share * p.party_characters().size(), "turn-in pays the stamped XP (%d of %d)" % [after - before, Quest.xp_reward(q)])
	# A job with no stamp — a save from before, the linear run's curated list,
	# a pack's story — pays the old purse rate.
	check(Quest.xp_reward({"reward": {"gold": 120}}) == 120 * Quest.XP_PER_GOLD, "an unstamped job pays gold x2, as it always did")
	check(Quest.xp_reward({"reward": {"gold": 120, "xp": 55}}) == 55, "a stamped one pays its stamp")

func test_patron_and_renown() -> void:

	Ladder.reset()
	var w := _world()
	var p := _party()
	var city = w.settlements[0]                       # riverhold, human, city
	var far = w.lairs[1]                               # far-barrow at (4000, 4000): out of any reach
	check(Posting.chief_settlement(w, "human") == city, "the city is the humans' chief settlement")
	check(not Posting.is_patron(city, w), "a stranger has no patron")
	var ids0: Array = _at(city, p, w).map(func(q): return q["id"])
	check(not ids0.any(func(id): return String(id).contains(far.id)), "the far barrow is nobody's problem")
	Ladder.deed("human", 12)
	check(Posting.is_patron(city, w), "Trusted: the patron's table")
	var ids1: Array = _at(city, p, w).map(func(q): return q["id"])
	check(ids1.any(func(id): return String(id).contains(far.id)), "...posts work about the far barrow")
	var town = w.settlements[1]                       # greenmarch, elf — not the humans', and not chief
	var ids2: Array = _at(town, p, w).map(func(q): return q["id"])
	check(not ids2.any(func(id): return String(id).contains(far.id)), "a town of another people does not")
	# a second human settlement that is only a camp is not the chief
	w.add_settlement(World.Settlement.new("h-camp", Vector2(300, 300), "human", "camp"))
	check(Posting.chief_settlement(w, "human") == city and not Posting.is_patron(w.settlements[-1], w), "the camp is not the patron")
	# renown's premium on every job (opinion back to neutral, so the people's own
	# regard — core/contracts.gd pay_mult — stays out of this arithmetic)
	Ladder.reset()
	FactionOpinion.reset()
	var plain: Array = _at(city, p, w)
	Ladder.deed("elf", 6)                             # Hirelings, +10 %
	var dear: Array = _at(city, p, w)
	check(plain.size() == dear.size() and plain.size() > 0, "same board")
	var ok := true
	for i in plain.size():
		if int(dear[i]["reward"]["gold"]) != int(int(plain[i]["reward"]["gold"]) * 1.1):
			ok = false
	check(ok, "every job pays +10 % at Hirelings")
	Ladder.reset()
