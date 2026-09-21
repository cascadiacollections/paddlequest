shader_type spatial;
// Comfort tunnelling. A quad parented to the XR camera, so it rides the head
// and both eyes get the same thing.
//
// unshaded    - it is an overlay, not geometry in the scene
// cull_disabled, depth_test_disabled, depth_draw_never
//             - it must draw over the court regardless of where the head is
//               and never occlude or write depth itself
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// 0 is fully open (invisible), 1 is fully closed in.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Radius of the clear centre at amount = 1, in UV units from the middle.
uniform float inner_radius : hint_range(0.05, 1.0) = 0.28;
// How soft the edge of the tunnel is. Hard edges read as a black ring rather
// than as peripheral vision falling away, and are their own kind of nasty.
uniform float softness : hint_range(0.01, 1.0) = 0.35;
uniform vec3 tint : source_color = vec3(0.0, 0.0, 0.0);

void fragment() {
	// Distance from the centre of the quad, 0 in the middle.
	float dist = length(UV - vec2(0.5)) * 2.0;

	// Open all the way up when amount is 0: push the aperture past the
	// corners so nothing is drawn at all rather than relying on the falloff.
	float aperture = mix(2.0, inner_radius, amount);
	float alpha = smoothstep(aperture, aperture + softness, dist);

	ALBEDO = tint;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
