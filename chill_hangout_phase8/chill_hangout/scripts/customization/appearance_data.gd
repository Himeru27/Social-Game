class_name AppearanceData
extends RefCounted
## Single source of truth for avatar options. Appearance is a flat Dictionary of ints/floats/strings
## (JSON- and network-friendly): colors are palette INDICES, never raw colors.
## sanitize() and validate_username() are what the server calls in Phase 5 - never trust clients.

const MIN_NAME_LEN := 2
const MAX_NAME_LEN := 16

const HAIR_STYLES: Array[String] = ["Short", "Long", "Curly", "Straight", "Spiky", "Medium", "Ponytail"]
const EYE_SHAPES: Array[String] = ["Round", "Wide", "Narrow", "Sleepy"]
const EYEBROWS: Array[String] = ["Thin", "Thick", "Angled", "None"]
const MOUTHS: Array[String] = ["Smile", "Neutral", "Open", "Smirk"]
const EXPRESSIONS: Array[String] = ["Neutral", "Happy", "Serious", "Surprised"]
const NOSES: Array[String] = ["Small", "Medium", "Long", "Wide"]
const FACE_DETAILS: Array[String] = ["None", "Freckles", "Mustache", "Beard", "Blush"]
const SHIRTS: Array[String] = ["T-shirt", "Long sleeve", "Tank top"]
const PANTS: Array[String] = ["Long pants", "Shorts", "Capri"]
const SHOES: Array[String] = ["Sneakers", "Boots", "Sandals"]
const ACCESSORIES: Array[String] = ["Glasses", "Cap", "Backpack", "Scarf"] # bit 0..3 of "accessories"

const SKIN_TONES: Array[Color] = [
	Color("#f5d7c3"), Color("#ecc09b"), Color("#e0ac7d"), Color("#c9a07a"),
	Color("#b07e57"), Color("#8d5a3b"), Color("#6b4228"), Color("#4a2e1d"),
]
const HAIR_COLORS: Array[Color] = [
	Color("#1e1a18"), Color("#3b2a20"), Color("#6b4429"), Color("#a8743c"), Color("#e6cf6a"),
	Color("#c2452d"), Color("#b8b8bc"), Color("#f2f2f2"), Color("#4a6fd1"), Color("#d65fa0"), Color("#4fb58a"),
]
const EYE_COLORS: Array[Color] = [
	Color("#5a3a22"), Color("#1d1d22"), Color("#3f78c8"), Color("#3f9a63"), Color("#7d8791"), Color("#b8803a"),
]
const CLOTH_COLORS: Array[Color] = [
	Color("#e0605a"), Color("#e8894a"), Color("#e6cf6a"), Color("#6fb26c"), Color("#4dd0c4"),
	Color("#4a7fc1"), Color("#7c9aa8"), Color("#7e62c1"), Color("#d65fa0"), Color("#f4f1ea"),
	Color("#9aa0a6"), Color("#2e2e38"), Color("#1d1d22"), Color("#8b5e3c"),
]

## Body proportion limits keep avatars sane. The collision capsule is fixed on purpose,
## so customization can never change movement, collision or animation timing.
const RANGES := {
	"height": Vector2(0.9, 1.1),
	"width": Vector2(0.88, 1.15),
	"thickness": Vector2(0.88, 1.2),
	"arm_length": Vector2(0.9, 1.1),
	"leg_length": Vector2(0.9, 1.1),
}

const BLOCKED_WORDS: Array[String] = ["fuck", "shit", "bitch", "cunt", "nazi", "rape"]
const RESERVED_NAMES: Array[String] = ["admin", "moderator", "system", "server", "staff", "owner", "host"]


static func _limits() -> Dictionary:
	return {
		"skin_tone": SKIN_TONES.size(), "hair_style": HAIR_STYLES.size(), "hair_color": HAIR_COLORS.size(),
		"eye_shape": EYE_SHAPES.size(), "eye_color": EYE_COLORS.size(), "eyebrows": EYEBROWS.size(),
		"mouth": MOUTHS.size(), "expression": EXPRESSIONS.size(), "nose": NOSES.size(),
		"face_detail": FACE_DETAILS.size(), "shirt_style": SHIRTS.size(), "shirt_color": CLOTH_COLORS.size(),
		"pants_style": PANTS.size(), "pants_color": CLOTH_COLORS.size(), "shoes_style": SHOES.size(),
		"shoes_color": CLOTH_COLORS.size(), "accessory_color": CLOTH_COLORS.size(),
	}


static func default_for(kind: String) -> Dictionary:
	var d := {
		"gender": "male", "skin_tone": 3, "hair_style": 0, "hair_color": 1,
		"eye_shape": 0, "eye_color": 1, "eyebrows": 0, "mouth": 1, "expression": 0, "nose": 1, "face_detail": 0,
		"height": 1.0, "width": 1.0, "thickness": 1.0, "arm_length": 1.0, "leg_length": 1.0,
		"shirt_style": 0, "shirt_color": 6, "pants_style": 1, "pants_color": 11,
		"shoes_style": 0, "shoes_color": 12, "accessories": 0, "accessory_color": 5,
	}
	if kind == "female":
		d["gender"] = "female"
		d["hair_style"] = 1
		d["hair_color"] = 4
		d["eye_color"] = 0
		d["mouth"] = 0
		d["nose"] = 0
		d["shirt_color"] = 0
		d["pants_style"] = 0
		d["pants_color"] = 5
		d["shoes_color"] = 0
	return d


static func randomized(kind: String) -> Dictionary:
	var d := default_for(kind)
	var lim := _limits()
	for k in lim:
		d[k] = randi() % int(lim[k])
	for k in RANGES:
		var r: Vector2 = RANGES[k]
		d[k] = snappedf(randf_range(r.x, r.y), 0.01)
	d["accessories"] = randi() % 16 if randf() < 0.5 else 0
	return d


## Returns a complete, in-range appearance no matter what was passed in.
static func sanitize(src: Dictionary) -> Dictionary:
	var out := default_for("male")
	var g := str(src.get("gender", "male"))
	out["gender"] = g if g == "male" or g == "female" else "male"
	var lim := _limits()
	for k in lim:
		if src.has(k) and (src[k] is int or src[k] is float):
			var f := float(src[k])
			if not is_nan(f) and not is_inf(f):
				out[k] = clampi(int(f), 0, int(lim[k]) - 1)
	for k in RANGES:
		if src.has(k) and (src[k] is int or src[k] is float):
			var f := float(src[k])
			var r: Vector2 = RANGES[k]
			if not is_nan(f) and not is_inf(f):
				out[k] = snappedf(clampf(f, r.x, r.y), 0.01)
	if src.has("accessories") and (src["accessories"] is int or src["accessories"] is float):
		var f := float(src["accessories"])
		if not is_nan(f) and not is_inf(f):
			out["accessories"] = clampi(int(f), 0, 15)
	return out


## Lowercase letters/digits only, with look-alike digits mapped - used to compare names.
static func name_key(n: String) -> String:
	var map := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t"}
	var out := ""
	for c in n.to_lower():
		if c in map:
			out += map[c]
		elif (c >= "a" and c <= "z"):
			out += c
	return out


## Returns "" when valid, otherwise a user-facing error message.
## Uniqueness within a server is enforced by the server in Phase 5 using name_key().
static func validate_username(n: String) -> String:
	if n != n.strip_edges():
		return "No spaces at the start or end."
	if n.is_empty():
		return "Enter a username."
	if n.length() < MIN_NAME_LEN:
		return "At least %d characters." % MIN_NAME_LEN
	if n.length() > MAX_NAME_LEN:
		return "At most %d characters." % MAX_NAME_LEN
	var rx := RegEx.new()
	rx.compile("^[A-Za-z0-9_ -]+$")
	if rx.search(n) == null:
		return "Use letters, numbers, spaces, - and _ only."
	if "  " in n:
		return "No double spaces."
	var key := name_key(n)
	if key.is_empty():
		return "Include at least one letter or number."
	for w in BLOCKED_WORDS:
		if w in key:
			return "That name isn't allowed."
	for w in RESERVED_NAMES:
		if key == w:
			return "That name is reserved."
	return ""
