shader_type canvas_item;

// Rotating gradient spinner (3/4 circle with alpha gradient)
uniform float rotation_speed : hint_range(0.0, 10.0) = -2.0;

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	vec2 pos = UV - center;

	// Calculate angle and distance from center
	float angle = atan(pos.y, pos.x);
	float dist = length(pos);

	// Normalize angle to 0-2π and rotate based on time
	float normalized_angle = angle + PI;
	float rotated_angle = mod(normalized_angle + TIME * rotation_speed, TAU);

	// Create ring (donut shape)
	float outer_radius = 0.45;
	float inner_radius = 0.30;
	float ring = smoothstep(inner_radius - 0.02, inner_radius, dist) *
	             smoothstep(outer_radius + 0.02, outer_radius, dist);

	// Create 3/4 circle (270 degrees)
	float arc_coverage = TAU * 0.75; // 3/4 of circle
	float arc = smoothstep(0.0, 0.1, mod(rotated_angle, TAU)) *
	            smoothstep(arc_coverage + 0.1, arc_coverage, mod(rotated_angle, TAU));

	// Gradient alpha along the arc
	float alpha_gradient = smoothstep(0.0, arc_coverage, mod(rotated_angle, TAU));

	// Combine ring, arc, and gradient
	float final_alpha = ring * arc * alpha_gradient;

	// Output white color with gradient alpha
	COLOR = vec4(1.0, 1.0, 1.0, final_alpha);
}
