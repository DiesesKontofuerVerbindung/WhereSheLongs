shader_type canvas_item;

uniform float cutoff : hint_range(0.0, 0.3, 0.001) = 0.07;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	if (lum < cutoff) {
		discard;
	}
	COLOR = c;
}
