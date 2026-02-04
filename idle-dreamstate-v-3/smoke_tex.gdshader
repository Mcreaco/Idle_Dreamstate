shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D smoke_tex : source_color;
uniform float alpha_strength = 1.2
;         // increase for stronger fog
uniform vec3 tint = vec3(0.7, 0.4, 1.0);    // purple tint
uniform bool invert = false;                // set true if your texture is dark-on-light

void fragment() {
    vec4 t = texture(smoke_tex, UV);

    // brightness -> alpha (removes non-transparent backgrounds + kills square edges)
    float lum = max(t.r, max(t.g, t.b));
    float a = invert ? (1.0 - lum) : lum;

    ALBEDO = tint;
    ALPHA  = a * alpha_strength;
}
