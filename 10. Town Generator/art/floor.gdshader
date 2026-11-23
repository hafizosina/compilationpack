shader_type canvas_item;

// Floors: `map` (the sprite's texture) holds one pixel a cell, the floor's draw order + 1 (0 = none), 128 added on a wall
// or door cell. Each floor's large texture is placed by world position, as the ground's. A wall's quarter shows the
// highest floor of the open cells round its corner, so a floor runs under a wall to its middle. A built floor ends
// in a rigid square edge, unshaded; a path (bit set in `soft_mask`) fades out with a ragged edge, as the ground does.

uniform sampler2D map : filter_nearest;
uniform sampler2DArray surfaces : source_color, filter_linear_mipmap, repeat_enable;
uniform int count = 1;
uniform int soft_mask = 0;
uniform float cell = 32.0;
uniform float cells_per_texture = 8.0;
uniform float spread = 0.45;
uniform float sharp = 5.0;
uniform float jag = 0.35;

const int MAX = 16;

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

int raw(ivec2 at, ivec2 size) {
	if (at.x < 0 || at.y < 0 || at.x >= size.x || at.y >= size.y) {
		return 0;
	}
	return int(texelFetch(map, at, 0).r * 255.0 + 0.5);
}

// The floor drawn at point `p` (in cells): its draw order, or -1.
int shown(vec2 p, ivec2 size) {
	ivec2 c = ivec2(floor(p));
	int v = raw(c, size);
	if (v < 128) {
		return v - 1;
	}
	ivec2 d = ivec2(fract(p.x) < 0.5 ? -1 : 1, fract(p.y) < 0.5 ? -1 : 1);
	int best = -1;
	int a = raw(c + ivec2(d.x, 0), size);
	int b = raw(c + ivec2(0, d.y), size);
	int e = raw(c + d, size);
	if (a < 128) best = max(best, a - 1);
	if (b < 128) best = max(best, b - 1);
	if (e < 128) best = max(best, e - 1);
	return best;
}

bool soft(int r) {
	return r >= 0 && ((soft_mask >> r) & 1) == 1;
}

void fragment() {
	ivec2 size = textureSize(map, 0);
	vec2 p = UV * vec2(size);
	vec2 w = world / cell;
	vec2 uv = w / cells_per_texture;
	int own = shown(p, size);
	if (own >= 0 && !soft(own)) {
		vec4 col = texture(surfaces, vec3(uv, float(own)));
		COLOR = vec4(col.rgb, 1.0);
	} else {
		// Paths: each path's share of the open cells round, roughened, against bare ground.
		ivec2 c = ivec2(floor(p));
		float shares[MAX];
		for (int r = 0; r < MAX; r++) {
			shares[r] = 0.0;
		}
		float bare = 0.0;
		float total = 0.0;
		for (int k = 0; k < 25; k++) {
			ivec2 at = c + ivec2(k % 5 - 2, k / 5 - 2);
			int v = raw(clamp(at, ivec2(0), size - 1), size);
			int r = v - 1;
			if (v >= 128) {
				// A wall or door cell counts as the path its quarter nearest this point shows, else not at all.
				r = shown(clamp(p, vec2(at) + 0.01, vec2(at) + 0.99), size);
				if (!soft(r)) {
					continue;
				}
			}
			if (r >= 0 && !soft(r)) {
				continue;
			}
			vec2 d = p - (vec2(at) + 0.5);
			float weight = exp(-dot(d, d) / (2.0 * spread * spread));
			total += weight;
			if (r < 0) {
				bare += weight;
			} else {
				shares[min(r, MAX - 1)] += weight;
			}
		}
		vec3 col = vec3(0.0);
		float paths = 0.0;
		float n0 = noise(w * 2.1) * 0.5 + noise(w * 5.3) * 0.3 + noise(w * 13.0) * 0.2;
		float none = pow(clamp(bare / max(total, 0.0001) + jag * (n0 - 0.5) * 2.0, 0.001, 1.0), sharp);
		for (int r = 0; r < count && r < MAX; r++) {
			if (shares[r] <= 0.0001) {
				continue;
			}
			vec2 q = w + float(r) * 17.3 + 5.1;
			float n = noise(q * 2.1) * 0.5 + noise(q * 5.3) * 0.3 + noise(q * 13.0) * 0.2;
			float e = pow(clamp(shares[r] / total + jag * (n - 0.5) * 2.0, 0.001, 1.0), sharp);
			col += texture(surfaces, vec3(uv, float(r))).rgb * e;
			paths += e;
		}
		if (paths <= 0.0001) {
			COLOR = vec4(0.0);
		} else {
			COLOR = vec4(col / paths, paths / (paths + none));
		}
	}
}
