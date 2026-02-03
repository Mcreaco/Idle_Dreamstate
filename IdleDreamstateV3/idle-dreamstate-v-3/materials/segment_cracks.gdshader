shader_type spatial;

uniform sampler2D crack_mask;

uniform vec4 base_color : source_color = vec4(0.10, 0.10, 0.12, 1.0);
uniform vec4 crack_color : source_color = vec4(0.55, 0.25, 1.0, 1.0);

uniform float instab01 = 0.0;
uniform float glow_energy = 2.0;
uniform float uv_scale = 1.0;
uniform float scroll_speed = 0.03;

instance uniform vec2 uv_offset = vec2(0.0, 0.0);
instance uniform float time_offset = 0.0;

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	float t = TIME + time_offset;
	uv += vec2(t * scroll_speed, t * (scroll_speed * 0.7));

	float n = texture(crack_mask, uv).r;

	// --- stronger curve: high instab ramps harder ---
	float s = smoothstep(0.15, 1.0, instab01); // 0..1 but eased

	// threshold opens up more (so more of the mask becomes "cracks")
	float crack_threshold = mix(0.985, 0.65, s);

	// anti-alias the edge so it's not crunchy
	float w = fwidth(n) * 3.0;

	// core crack mask
	float cracks = smoothstep(crack_threshold - w, 1.0, n);

	// widen + intensify with instability
	cracks = pow(cracks, mix(2.0, 0.8, s));   // thinner early, thicker later
	cracks *= mix(0.0, 2.0, s);               // make high instab *really* visible

	ALBEDO = base_color.rgb;
	EMISSION = crack_color.rgb * cracks * glow_energy;
}
