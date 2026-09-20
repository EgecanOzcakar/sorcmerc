// The overworld's ground, as real geometry (scenes/world/terrain3d.gd).
//
// This replaces ground.gdshader, the canvas_item version that painted the map
// by projecting every screen pixel back to a world position by hand. That
// inverse projection was the whole reason #58 existed: the shader had to
// re-derive world.gd's camera from uniforms, and the two drifted the moment
// the window was not 1280x800. There is nothing to re-derive here — the ground
// is a mesh lying in the same 3D world the camera is in, so a fragment's world
// position arrives as a varying and the camera can rotate, tilt, pan and zoom
// without this file knowing that it did.
//
// What it still owns, unchanged, is the LOOK: the three painted seamless
// textures blended by the cell-resolution mask world.gd builds (R forest,
// G water, B explored), and the fog over it — never-explored flat and
// near-black, remembered a dark tint, currently-visible a smooth circle
// around the party.
shader_type spatial;
// Fog and daylight are the same numbers the 2D version used, but the light
// that carries them is now the map's own sun (scenes/world/world_view3d.gd),
// which is also what makes a town cast a shadow across the field it stands in.
// So this is a LIT shader, and the time of day has exactly one owner: the sun
// and ambient in the rig. The one thing that must not answer to it is the
// unexplored fog — a black hole in the map is black at noon and at midnight —
// so that goes in EMISSION, which no light touches.
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D grass_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D forest_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D water_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D mask_tex : repeat_disable, filter_linear;   // one texel per mask cell
uniform vec2 mask_texel = vec2(0.015625);   // one texel, in mask uv
uniform vec2 mask_min;      // world position of the mask's top-left texel
uniform vec2 mask_size;     // world extent the mask covers
uniform float tex_scale = 340.0;   // world units per texture repeat
uniform vec2 player;        // world position of the party
uniform float sight = 260.0;       // VISION_RADIUS
uniform float sight_feather = 60.0;
uniform vec3 fog_unknown = vec3(0.03, 0.03, 0.045);
uniform vec4 fog_remembered = vec4(0.05, 0.05, 0.09, 0.55);
uniform float time_s = 0.0;

// The map's own coordinates. core/world.gd is 2D and calls them (x, y); the
// 3D map lays that plane out as (x, z) with y up, so every conversion in this
// file and in world.gd is that one swap and nothing else.
varying vec2 map_xy;

void vertex() {
	map_xy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 w = map_xy;
	vec2 m = (w - mask_min) / mask_size;
	// A soft mask read: the linear sample plus four diagonal taps a texel out,
	// which is a ~2-cell blur for the price of five fetches — every edge on
	// the ground (shore, tree line, the fog's memory) is painted, not tiled.
	vec2 d = mask_texel * 0.9;
	vec4 k = (texture(mask_tex, m) * 2.0
		+ texture(mask_tex, m + vec2(d.x, d.y)) + texture(mask_tex, m + vec2(-d.x, d.y))
		+ texture(mask_tex, m + vec2(d.x, -d.y)) + texture(mask_tex, m + vec2(-d.x, -d.y))) / 6.0;
	bool inside = m.x >= 0.0 && m.x <= 1.0 && m.y >= 0.0 && m.y <= 1.0;
	float explored = inside ? k.b : 0.0;
	vec2 uv = w / tex_scale;
	vec3 g = texture(grass_tex, uv).rgb;
	vec3 f = texture(forest_tex, uv * 1.6).rgb;
	// water drifts a little, the one thing on the map that moves on its own
	vec3 wa = texture(water_tex, uv * 0.8 + vec2(time_s * 0.004, time_s * 0.002)).rgb * vec3(0.72, 0.86, 0.98);
	vec3 col = mix(g, f, k.r);
	col = mix(col, wa, k.g);
	float vis = 1.0 - smoothstep(sight - sight_feather, sight + sight_feather, distance(w, player));
	col = mix(col, fog_remembered.rgb, fog_remembered.a * (1.0 - vis));
	// Unexplored ground is not dark ground, it is no ground: albedo goes to
	// zero so no light can lift it, and the flat unknown colour is emitted
	// instead. Explored ground is the other way round — lit, and emitting
	// nothing — so the sun's day/night is the only thing dimming it.
	ALBEDO = col * explored;
	EMISSION = fog_unknown * (1.0 - explored);
	// Water is the one wet surface on the map, and the only reason to give the
	// ground a specular response at all: it is what tells a rotating camera
	// that the lake is a surface and the grass is not.
	//
	// Every term below is multiplied by `explored`, and that is not tidiness.
	// A specular highlight is ADDED to a surface, so it does not care that the
	// albedo under it went to zero: without this, the sun's reflection off a
	// lake goes on being drawn across ground the party has never seen, and
	// what you get is a soft grey lobe hanging in the middle of the black —
	// a light on a map with nothing on it to be lit.
	// Kept deliberately dull. A mirror-smooth lake under a directional sun is a
	// white bar across the map the moment the camera tilts toward the light,
	// and at map scale a lake is read for its shape, not its shine.
	float wet = k.g * explored;
	ROUGHNESS = mix(0.96, 0.52, wet);
	SPECULAR = mix(0.04, 0.22, wet) * explored;
	// Two crossed swells, in world units so they do not swim when the ground
	// mesh is recentred under the camera. Perturbing the normal rather than
	// displacing the mesh keeps the water exactly where core/world.gd thinks
	// it is — water is a walkability rule there, not a height.
	vec3 ripple = normalize(vec3(
		sin(w.x * 0.045 + time_s * 0.8) * 0.06, 1.0,
		cos(w.y * 0.038 + time_s * 0.6) * 0.06));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(ripple, 0.0)).xyz, wet));
}
