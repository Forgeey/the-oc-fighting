shader_type canvas_item;

uniform float blur_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE;
	float sigma = blur_strength * 6.0 + 0.01;
	vec4 blur = vec4(0.0);
	float total = 0.0;
	
	for (int x = -4; x <= 4; x++) {
		for (int y = -4; y <= 4; y++) {
			float d = float(x*x + y*y);
			float w = exp(-d / (2.0 * sigma * sigma));
			blur += texture(TEXTURE, UV + vec2(float(x), float(y)) * ps * sigma) * w;
			total += w;
		}
	}
	
	COLOR = blur / total;
}
