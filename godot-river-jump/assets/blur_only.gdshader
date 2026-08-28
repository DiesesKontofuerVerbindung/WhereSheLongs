shader_type canvas_item;

uniform float blur : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb, c.a * (1.0 - blur * 0.35));
}
