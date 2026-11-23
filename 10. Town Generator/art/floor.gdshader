shader_type canvas_item;

// Floors: `map` (the sprite's texture) holds one pixel a cell, the floor's draw order + 1 (0 = none), 128 added on a wall
// or door cell. Each floor's large texture is placed by world position, as the ground's. A wall's quarter shows the
// highest floor of the open cells round its corner, so a floor runs under a wall to its middle. A built floor's edge
// is cut round its pieces (`pieces`), a lower floor running on under a higher; earthy floors sit in a jagged earth
// margin, each built floor casts a small shadow, and by a wall the cut is the plain cell line. A path (bit set in
// `soft_mask`) fades out with a ragged edge, as the ground does.

uniform sampler2D map : filter_nearest;
uniform sampler2DArray surfaces : source_color, filter_linear_mipmap, repeat_enable;
// Per floor: R, G the offset (cells, stored * 0.5 + 0.5) to the point that decides its piece; B its reach; A its stray chance.
uniform sampler2DArray pieces : filter_nearest, repeat_enable;
uniform sampler2D earth : source_color, filter_linear_mipmap, repeat_enable;
uniform int count = 1;
uniform int soft_mask = 0;
uniform int earthy_mask = 0;
uniform int hem_mask = 0;
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

bool has(int mask, int r) {
	return r >= 0 && r < MAX && ((mask >> r) & 1) == 1;
}

// Every built (not soft) floor, a bit per draw order.
int hard_mask() {
	return ((1 << min(count, MAX)) - 1) & ~soft_mask;
}

// The region floor `f` is drawn over: itself and every built floor above it.
int above(int f) {
	return hard_mask() & ~((1 << f) - 1);
}

vec4 over(vec4 top, vec4 under) {
	float a = top.a + under.a * (1.0 - top.a);
	if (a <= 0.0001) {
		return vec4(0.0);
	}
	return vec4((top.rgb * top.a + under.rgb * under.a * (1.0 - top.a)) / a, a);
}

float box_distance(vec2 q, vec2 lo, vec2 hi) {
	return length(max(max(lo - q, q - hi), vec2(0.0)));
}

// Whether a cell `at` showing floor `r` is in the region of the floors in `mask`. With `own` >= 0, a floor other
// than `own` counts only when a side neighbour holds `own`: a lower floor runs under a higher one it touches, no further.
bool member(ivec2 at, int r, int mask, int own, ivec2 size) {
	if (!has(mask, r)) {
		return false;
	}
	if (own < 0 || r == own) {
		return true;
	}
	ivec2 sides[4] = {ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1)};
	for (int k = 0; k < 4; k++) {
		int v = raw(at + sides[k], size);
		if (v < 128 && v - 1 == own) {
			return true;
		}
	}
	return false;
}

// Signed distance (cells) from `q` to the outline of the floors in `mask` (see member() for `own`), positive inside,
// from the 3x3 cells round it, a wall or door cell by its quarters; 1.5 when none differs.
float sd_mask(vec2 q, int mask, int own, ivec2 size) {
	ivec2 c = ivec2(floor(q));
	bool inside = member(c, shown(q, size), mask, own, size);
	float best = 1.5;
	for (int k = 0; k < 9; k++) {
		ivec2 at = c + ivec2(k % 3 - 1, k / 3 - 1);
		int v = raw(at, size);
		if (v < 128) {
			if (member(at, v - 1, mask, own, size) != inside) {
				best = min(best, box_distance(q, vec2(at), vec2(at) + 1.0));
			}
		} else {
			for (int h = 0; h < 4; h++) {
				vec2 lo = vec2(at) + vec2(float(h % 2), float(h / 2)) * 0.5;
				if (member(at, shown(lo + 0.25, size), mask, own, size) != inside) {
					best = min(best, box_distance(q, lo, lo + 0.5));
				}
			}
		}
	}
	return inside ? best : -best;
}

// Floor `f`'s piece data at world point `qw` (in cells), read exactly.
vec4 piece(vec2 qw, int f) {
	ivec2 n = textureSize(pieces, 0).xy;
	ivec2 t = ivec2(floor(fract(qw / cells_per_texture) * vec2(n)));
	return texelFetch(pieces, ivec3(clamp(t, ivec2(0), n - ivec2(1)), f), 0);
}

// Whether built floor `f` covers point `q` (cells; `qw` the same point in world cells). `sd` is its piece's
// signed distance to the floor's outline; `plain` (by a wall) cuts on the cell line, no reach, no strays.
bool cover(vec2 q, vec2 qw, int f, bool plain, ivec2 size, out float sd) {
	int mask = above(f);
	if (plain) {
		sd = sd_mask(q, mask, f, size);
		return sd > 0.0;
	}
	vec4 k = piece(qw, f);
	sd = sd_mask(q + (k.rg - 0.5) * 2.0, mask, f, size);
	if (!has(earthy_mask, f)) {
		return sd > 0.0;
	}
	if (sd + (k.b - 0.5) * 2.0 * 0.14 > 0.0) {
		return true;
	}
	return sd > -0.5 && k.a < 0.55 * pow(1.0 + sd / 0.5, 1.5);
}

// Paths: each path's share of the open cells round, roughened, against bare ground; straight alpha.
vec4 paths_at(vec2 p, vec2 w, vec2 uv, vec2 gx, vec2 gy, ivec2 size) {
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
		col += textureGrad(surfaces, vec3(uv, float(r)), gx, gy).rgb * e;
		paths += e;
	}
	if (paths <= 0.0001) {
		return vec4(0.0);
	}
	return vec4(col / paths, paths / (paths + none));
}

void fragment() {
	ivec2 size = textureSize(map, 0);
	vec2 p = UV * vec2(size);
	vec2 w = world / cell;
	vec2 uv = w / cells_per_texture;
	vec2 gx = dFdx(uv);
	vec2 gy = dFdy(uv);
	ivec2 c = ivec2(floor(p));
	int centre = raw(c, size);
	bool same = centre > 0 && centre < 128 && !soft(centre - 1);
	// The floors in the 3x3 cells round, and whether a wall or door stands among them.
	int present = 0;
	bool walled = false;
	for (int k = 0; k < 9; k++) {
		ivec2 at = c + ivec2(k % 3 - 1, k / 3 - 1);
		int v = raw(at, size);
		same = same && v == centre;
		if (v < 128) {
			if (v > 0 && v <= MAX) {
				present |= 1 << (v - 1);
			}
		} else {
			walled = true;
			for (int h = 0; h < 4; h++) {
				int r = shown(vec2(at) + vec2(float(h % 2), float(h / 2)) * 0.5 + 0.25, size);
				if (r >= 0 && r < MAX) {
					present |= 1 << r;
				}
			}
		}
	}
	if (same) {
		COLOR = vec4(textureGrad(surfaces, vec3(uv, float(centre - 1)), gx, gy).rgb, 1.0);
	} else {
		int hard = present & hard_mask();
		vec3 dirt = textureGrad(earth, uv, gx, gy).rgb;
		float jn = noise(w * 2.0) * 0.55 + noise(w * 5.5) * 0.30 + noise(w * 13.7) * 0.15 - 0.5;
		float fade = clamp(0.75 + jn, 0.4, 1.0);
		vec4 col = vec4(0.0);
		if (hard != 0) {
			// Earth under everything: a jagged bed round earthy floors, a light ring round every built one.
			float bed = 0.0;
			if ((hard & earthy_mask) != 0) {
				float se = sd_mask(p, hard_mask() & earthy_mask, -1, size);
				bed = clamp((se + 0.45 + jn * 0.30) / 0.10, 0.0, 1.0) * 0.85 * fade;
			}
			float sh = sd_mask(p, hard_mask(), -1, size);
			float ring = clamp((sh + 0.22 + jn * 0.16) / 0.10, 0.0, 1.0) * 0.45 * fade;
			col = vec4(dirt, max(bed, ring));
		}
		col = over(paths_at(p, w, uv, gx, gy, size), col);
		if (hard != 0) {
			bool floored = has(hard_mask(), shown(p, size));
			float grain = noise(w * 7.3 + 3.1);
			float stripe = mod(floor((w.x + w.y) * 15.0), 2.0);
			for (int f = 0; f < count && f < MAX; f++) {
				if (!has(hard, f)) {
					continue;
				}
				float sd = 0.0;
				if (cover(p, w, f, walled, size, sd)) {
					vec3 s = textureGrad(surfaces, vec3(uv, float(f)), gx, gy).rgb;
					if (sd < 0.0 && !floored) {
						// A piece past the outline, on bare ground, sinks into the earth.
						s = mix(s, dirt, clamp(-sd / 0.5, 0.0, 1.0) * 0.65);
					} else if (sd >= 0.0 && has(earthy_mask, f)) {
						s = mix(s, dirt, clamp(1.0 - sd / 0.35, 0.0, 1.0) * 0.25 * grain);
					}
					if (has(hem_mask, f)) {
						float e = sd_mask(p, above(f), f, size);
						if (e > 0.0 && e < 0.10) {
							s *= stripe < 0.5 ? 0.62 : 0.72;
						}
					}
					col = vec4(s, 1.0);
				} else {
					// Its shadow, down and right, on whatever lies under it.
					float sa = 0.0;
					float sb = 0.0;
					vec2 o1 = vec2(0.04, 0.05);
					vec2 o2 = vec2(0.08, 0.10);
					float a = cover(p - o1, w - o1, f, walled, size, sa) ? 1.0 : 0.0;
					float b = cover(p - o2, w - o2, f, walled, size, sb) ? 1.0 : 0.0;
					col = over(vec4(0.0, 0.0, 0.0, (a + b) * 0.5 * 0.42), col);
				}
			}
		}
		COLOR = col;
	}
}
