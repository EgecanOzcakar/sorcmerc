// The footprint under a landmark: the soft shadow, the lit disc and the ring
// around it, all on one flat quad lying on the ground.
//
// These three used to be draw calls in World._draw() — _soft_shadow(), _fan()
// and _ring() — painted as screen-space ellipses over the map. That worked
// while the map WAS a flat painting. It cannot survive a camera that tilts and
// turns: a ring is a circle on the ground, not an ellipse on the screen, and a
// 2D one drawn after the map would also sit on top of the very building it is
// supposed to be drawn around. So the footprint became geometry. It lies on the
// ground, it turns with the camera because it is not drawn in screen space at
// all, and the depth buffer puts the town in front of its own ring.
//
// One MultiMesh draws every footprint on the map in one call, so everything
// that differs per landmark rides in per-instance data:
//   COLOR     the faction/lair tint, with alpha carrying the fog fade
//   CUSTOM0.x how much of the radius the ring takes (0 = no ring)
//   CUSTOM0.y disc fill strength — 0 for a party, which only wants a shadow
//   CUSTOM0.z shadow strength
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

// Where the light comes from, in the map's own coordinates — the direction the
// disc's bright side faces. Kept as World.LIGHT was: a look, not a physical
// light, which is why this quad is unshaded and the ground under it is not.
uniform vec2 light_dir = vec2(-0.66, -0.75);

varying vec4 tint;
varying vec3 shape;      // ring width, fill strength, shadow strength

void vertex() {
	tint = COLOR;
	shape = INSTANCE_CUSTOM.xyz;
}

void fragment() {
	// The quad is built as a unit circle's bounding square, so UV maps to
	// [-1, 1] on both axes and `r` is the distance from the centre in radii.
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	// The shadow reaches past the disc and fades out, the way the three
	// stacked ellipses of the old _soft_shadow() did, but continuously.
	float shadow = shape.z * 0.30 * (1.0 - smoothstep(0.25, 1.0, r));
	// The disc, brighter on the side the light comes from: the old _fan()'s
	// off-centre apex, as a gradient.
	float lit = 0.5 - 0.5 * dot(normalize(p + vec2(0.0001)), normalize(light_dir)) * smoothstep(0.0, 0.9, r);
	vec3 disc = tint.rgb * mix(0.38, 0.72, lit);
	float ring_w = max(shape.x, 0.0001);
	float ring = smoothstep(1.0 - ring_w, 1.0 - ring_w * 0.5, r) * (1.0 - smoothstep(0.985, 1.0, r));
	float fill = shape.y * (1.0 - smoothstep(1.0 - ring_w, 1.0, r));
	vec3 col = mix(vec3(0.02, 0.01, 0.04), disc, fill);
	col = mix(col, tint.rgb * 0.85, ring * step(0.0001, shape.x));
	float a = max(max(shadow, fill), ring * step(0.0001, shape.x));
	ALBEDO = col;
	ALPHA = a * tint.a;
}
