shader_type canvas_item;

// The ground: the sprite's texture holds one pixel a cell, the terrain's draw order + 1 (0 = none, drawn as the
// first). Each terrain's large texture is placed by world position, so it runs on across chunks. A point shows each
// terrain by its share of the cells round it (weighted by a falloff of `spread` cells); noise pushes each share
// up or down by up to `jag`, so the edge line is ragged, and the shares raised to `sharp` set how soft it fades.

uniform sampler2DArray grounds : source_color, filter_linear_mipmap, repeat_enable;
uniform int count = 1;
uniform float cell = 32.0;
uniform float cells_per_texture = 8.0;
uniform float spread = 0.45;
uniform float sharp = 5.0;
uniform float jag = 0.3;

const int MAX = 8;

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
	ivec2 size = textureSize(TEXTURE, 0);
	vec2 p = UV * vec2(size);
	ivec2 c = ivec2(floor(p));
	float shares[MAX];
	float total = 0.0;
	for (int r = 0; r < MAX; r++) {
		shares[r] = 0.0;
	}
	for (int k = 0; k < 25; k++) {
		ivec2 at = c + ivec2(k % 5 - 2, k / 5 - 2);
		int id = clamp(int(texelFetch(TEXTURE, clamp(at, ivec2(0), size - 1), 0).r * 255.0 + 0.5) - 1, 0, MAX - 1);
		vec2 d = p - (vec2(at) + 0.5);
		float weight = exp(-dot(d, d) / (2.0 * spread * spread));
		shares[id] += weight;
		total += weight;
	}
	vec2 w = world / cell;
	vec2 uv = w / cells_per_texture;
	vec4 col = vec4(0.0);
	float sum = 0.0;
	for (int r = 0; r < count && r < MAX; r++) {
		if (shares[r] <= 0.0001) {
			continue;
		}
		vec2 q = w + float(r) * 17.3;
		float n = noise(q * 2.1) * 0.5 + noise(q * 5.3) * 0.3 + noise(q * 13.0) * 0.2;
		float e = pow(clamp(shares[r] / total + jag * (n - 0.5) * 2.0, 0.001, 1.0), sharp);
		col += texture(grounds, vec3(uv, float(r))) * e;
		sum += e;
	}
	COLOR = col / max(sum, 0.0001);
}
