shader_type canvas_item;

// L3's river lines in the map shader's water: the same shallow colour, faded onto daluang with the same bark
// fibres at the same place, so a river runs into a lake or the sea with no seam.

uniform vec4 water : source_color = vec4(0.27, 0.49, 0.66, 1.0);
uniform vec4 paper : source_color = vec4(0.95, 0.86, 0.68, 1.0);
uniform float cell = 32.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 cells = world / cell;
	float fibre = noise(cells * vec2(0.5, 9.0)) * 0.6 + noise(cells * vec2(2.0, 22.0)) * 0.4;
	COLOR.rgb = mix(water.rgb, water.rgb * paper.rgb, 0.45) * (fibre > 0.62 ? 0.92 : 1.0);
}
