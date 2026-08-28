shader_type canvas_item;

uniform vec4 fill_color : source_color = vec4(0.96, 0.9, 0.78, 1.0);
uniform float blur : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float shape = max(c.a, 1.0 - smoothstep(0.02, 0.55, lum));
	if (shape < 0.04) {
		discard;
	}
	vec3 rgb = fill_color.rgb;
	float alpha = fill_color.a * shape;
	if (blur > 0.05) {
		rgb = mix(rgb, vec3(0.55, 0.72, 0.92), blur * 0.65);
		alpha *= 0.45 + blur * 0.35;
	}
	COLOR = vec4(rgb, alpha);
}
