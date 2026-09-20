// The woods (scenes/world/scatter3d.gd): one lit, vertex-coloured shader for
// every tree on the map, drawn as two MultiMeshes.
//
// It exists rather than a StandardMaterial3D for one reason: the fog. The
// ground under a tree fades toward the "remembered" tint the moment the party
// walks out of sight of it (ground3d.gdshader), and a wood standing at full
// brightness on faded ground is exactly the mismatch the three-tier fog was
// built to remove. Doing that fade here, from the same player position and the
// same sight radius the ground reads, means the trees can never disagree with
// the ground they stand on — and costs nothing per frame, because it is two
// uniforms rather than a rebuild of every instance.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec2 player;
uniform float sight = 260.0;
uniform float sight_feather = 60.0;
uniform vec4 fog_remembered = vec4(0.05, 0.05, 0.09, 0.55);

varying vec3 tint;
varying vec2 map_xy;

void vertex() {
	// COLOR is the MultiMesh's per-instance colour: a small hue/brightness
	// jitter so a stand of trees is not one flat green. The two-tone trunk and
	// canopy come from the mesh's own vertex colours, baked once.
	tint = COLOR.rgb;
	map_xy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float vis = 1.0 - smoothstep(sight - sight_feather, sight + sight_feather, distance(map_xy, player));
	ALBEDO = mix(tint, fog_remembered.rgb, fog_remembered.a * (1.0 - vis));
	ROUGHNESS = 1.0;
}
