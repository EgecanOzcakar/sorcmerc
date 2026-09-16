// The overworld's ground and its fog, in one pass (scenes/world/world.gd
// _draw_ground). Every pixel of the map control is projected back to world
// space, the three painted seamless textures are blended by a soft
// cell-resolution mask (R forest, G water, B explored), and the fog goes over:
// never-explored is the flat unknown colour, remembered is a tint, and what
// the party can see right now is a smooth circle around it — no per-cell
// squares anywhere.
shader_type canvas_item;

uniform sampler2D grass_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D forest_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D water_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D mask_tex : repeat_disable, filter_linear;   // one texel per mask cell
uniform vec2 mask_texel = vec2(0.015625);   // one texel, in mask uv
uniform vec2 mask_min;      // world position of the mask's top-left texel
uniform vec2 mask_size;     // world extent the mask covers
uniform vec2 origin;        // world.gd _origin
uniform float zoom = 1.0;   // world.gd _zoom
uniform float yaw = 0.6109; // ISO_YAW in radians
uniform float gain = 1.85;  // ISO_GAIN
uniform float squash = 0.38;// ISO_SQUASH
uniform float tex_scale = 340.0;   // world units per texture repeat
uniform vec2 player;        // world position of the party
// The map control's size, in the units _origin / _zoom / _pix() are in. The
// projection below has to start from a coordinate in THAT space, and FRAGCOORD
// is not one: the project stretches its canvas (window/stretch/mode =
// "canvas_items"), so a fragment coordinate is in real framebuffer pixels while
// world.gd's numbers are in the stretched canvas's own units. At the 1280x800
// default the two agree, which is why this shipped looking right; on a
// 3840-wide window every pixel resolved to a world point ~2.6x too far from the
// camera, so the ground and the fog on it sat off behind the party instead of
// under it -- the map read as unlit everywhere the party actually was (#58).
// UV * rect_size is the coordinate _pix()/_unpix() speak at any window size,
// and it is relative to the control rather than to the window, so a map that
// does not start at the window's corner comes out right too.
uniform vec2 rect_size = vec2(1280.0, 800.0);
uniform float sight = 260.0;       // VISION_RADIUS
uniform float sight_feather = 60.0;
uniform vec3 fog_unknown = vec3(0.03, 0.03, 0.045);
uniform vec4 fog_remembered = vec4(0.05, 0.05, 0.09, 0.55);
uniform float time_s = 0.0;

vec2 to_world(vec2 sp) {
	vec2 v = (sp - origin) / zoom;
	v.y /= squash;
	float c = cos(-yaw);
	float s = sin(-yaw);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c) / gain;
}

void fragment() {
	vec2 w = to_world(UV * rect_size);
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
	col = mix(fog_unknown, col, explored);
	COLOR = vec4(col, 1.0);
}
