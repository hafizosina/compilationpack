shader_type canvas_item;

// Past L3's poles: mottled parchment, and along each map edge a printed border, a thick ink line, a bar of
// alternating ink and paper every `segment` cells, a paper gap and a thin outer line.

uniform float cell = 32.0;
uniform float map_height = 4096.0;
uniform float segment = 8.0;
uniform vec4 paper : source_color = vec4(0.906, 0.839, 0.675, 1.0);
uniform vec4 aged : source_color = vec4(0.80, 0.70, 0.50, 1.0);
uniform vec4 ink : source_color = vec4(0.165, 0.125, 0.086, 1.0);

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
	vec2 c = world / cell;
	float d = world.y < 0.0 ? -c.y : c.y - map_height / cell;
	float n = noise(c / 6.0) * 0.55 + noise(c / 1.7) * 0.3 + noise(c * 1.3) * 0.15;
	vec4 col = mix(paper, aged, smoothstep(0.5, 0.85, n) * 0.6);
	if (d < 0.35) {
		col = ink;
	} else if (d < 1.55) {
		bool dark = mod(floor(c.x / segment), 2.0) < 1.0;
		col = (d < 0.5 || d > 1.4) ? ink : (dark ? ink : paper);
	} else if (d > 1.9 && d < 2.05) {
		col = ink;
	}
	COLOR = col;
}
