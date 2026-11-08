class_name PlaceholderAvatar
extends RefCounted
## Phase 1 stand-in avatar built from low-poly boxes, with separate pivots for arms and legs.
## Faces -Z (Godot forward). Phase 2 replaces this with the full customizable character.
## Returned node has meta "parts": { "arm_l", "arm_r", "leg_l", "leg_r" } (Node3D pivots).


static func build(opts: Dictionary) -> Node3D:
	var skin: Color = opts.get("skin", Color("#c9a07a"))
	var shirt: Color = opts.get("shirt", Color("#7c9aa8"))
	var legs_col: Color = opts.get("legs", Color("#2e2e38"))
	var shoes: Color = opts.get("shoes", Color("#202028"))
	var hair: Color = opts.get("hair", Color("#2b2220"))
	var shorts: bool = opts.get("shorts", false)
	var long_hair: bool = opts.get("long_hair", false)

	var root := Node3D.new()
	var parts := {}

	LowPoly.box(root, Vector3(0.5, 0.6, 0.28), shirt, Vector3(0, 1.15, 0))

	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(0.13 * side, 0.85, 0)
		root.add_child(hip)
		if shorts:
			LowPoly.box(hip, Vector3(0.22, 0.36, 0.24), legs_col, Vector3(0, -0.18, 0))
			LowPoly.box(hip, Vector3(0.15, 0.42, 0.17), skin, Vector3(0, -0.57, 0))
		else:
			LowPoly.box(hip, Vector3(0.2, 0.78, 0.22), legs_col, Vector3(0, -0.39, 0))
		LowPoly.box(hip, Vector3(0.2, 0.1, 0.3), shoes, Vector3(0, -0.8, -0.04))
		parts["leg_r" if side > 0 else "leg_l"] = hip

		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.34 * side, 1.4, 0)
		root.add_child(shoulder)
		LowPoly.box(shoulder, Vector3(0.15, 0.26, 0.17), shirt, Vector3(0, -0.1, 0))
		LowPoly.box(shoulder, Vector3(0.12, 0.46, 0.13), skin, Vector3(0, -0.43, 0))
		parts["arm_r" if side > 0 else "arm_l"] = shoulder

	LowPoly.box(root, Vector3(0.1, 0.1, 0.1), skin, Vector3(0, 1.5, 0))
	LowPoly.box(root, Vector3(0.3, 0.34, 0.3), skin, Vector3(0, 1.7, 0))

	var dark := Color("#2a2420")
	LowPoly.box(root, Vector3(0.04, 0.05, 0.01), dark, Vector3(-0.07, 1.72, -0.151))
	LowPoly.box(root, Vector3(0.04, 0.05, 0.01), dark, Vector3(0.07, 1.72, -0.151))
	LowPoly.box(root, Vector3(0.08, 0.015, 0.01), dark.lightened(0.15), Vector3(0, 1.62, -0.151))

	LowPoly.box(root, Vector3(0.34, 0.1, 0.34), hair, Vector3(0, 1.88, 0))
	LowPoly.box(root, Vector3(0.34, 0.08, 0.06), hair, Vector3(0, 1.82, -0.14))
	if long_hair:
		LowPoly.box(root, Vector3(0.36, 0.55, 0.1), hair, Vector3(0, 1.62, 0.15))
		LowPoly.box(root, Vector3(0.06, 0.4, 0.28), hair, Vector3(-0.17, 1.68, 0.02))
		LowPoly.box(root, Vector3(0.06, 0.4, 0.28), hair, Vector3(0.17, 1.68, 0.02))
	else:
		LowPoly.box(root, Vector3(0.34, 0.2, 0.1), hair, Vector3(0, 1.78, 0.13))

	root.set_meta("parts", parts)
	return root


static func male() -> Node3D:
	return build({
		"skin": Color("#c9a07a"), "shirt": Color("#7c9aa8"), "legs": Color("#2e2e38"),
		"shoes": Color("#202028"), "hair": Color("#2b2220"), "shorts": true, "long_hair": false,
	})


static func female() -> Node3D:
	return build({
		"skin": Color("#c9a982"), "shirt": Color("#e0605a"), "legs": Color("#4a7fc1"),
		"shoes": Color("#d9433a"), "hair": Color("#e6cf6a"), "shorts": false, "long_hair": true,
	})
