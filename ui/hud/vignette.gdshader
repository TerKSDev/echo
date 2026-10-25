shader_type canvas_item;

uniform vec4 vignette_color : source_color = vec4(0.01, 0.035, 0.07, 0.7);
uniform float inner_radius : hint_range(0.0, 1.0) = 0.4;
uniform float outer_radius : hint_range(0.0, 1.5) = 0.92;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	// Correct for 720:1280 (9:16) portrait aspect ratio
	uv.y *= 1.7778;
	float dist = length(uv);
	float vignette = smoothstep(inner_radius, outer_radius, dist);
	COLOR = vec4(vignette_color.rgb, vignette_color.a * vignette);
}

