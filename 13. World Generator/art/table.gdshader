shader_type canvas_item;

// Round L3's map: the daluang sheet's margin with a tumpal border (a row of batik triangles in indigo and
// red ochre between sepia lines), a rough torn edge, its shadow, then a teak table of planks, drawn flat:
// grain in hard bands, dark seams, staggered plank ends.

uniform float cell = 32.0;
uniform vec2 map_size = vec2(8192.0, 4096.0);
// Margin from the map's edge to where the sheet is torn, in cells, and how much the tear wanders.
uniform float margin = 4.2;
uniform float tear = 0.45;
uniform float plank = 7.0;
uniform vec4 paper : source_color = vec4(0.84, 0.74, 0.56, 1.0);
uniform vec4 sepia : source_color = vec4(0.29, 0.19, 0.11, 1.0);
uniform vec4 indigo : source_color = vec4(0.20, 0.25, 0.40, 1.0);
uniform vec4 ochre : source_color = vec4(0.62, 0.30, 0.18, 1.0);
uniform vec4 teak : source_color = vec4(0.42, 0.26, 0.15, 1.0);

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

// Bark fibres, running along the sheet.
vec4 daluang(vec2 c) {
	float fibre = noise(c * vec2(0.5, 9.0)) * 0.6 + noise(c * vec2(2.0, 22.0)) * 0.4;
	return mix(paper, paper * 0.86, step(0.62, fibre));
}

vec4 wood(vec2 c) {
	float row = floor(c.y / plank);
	float x = c.x + hash(vec2(row, 3.0)) * 40.0;
	float end = mod(x, 37.0 + hash(vec2(row, 7.0)) * 20.0);
	float grain = noise(vec2(x * 0.12, c.y * 2.2) + row * 13.0) * 0.7 + noise(vec2(x * 0.5, c.y * 7.0)) * 0.3;
	vec4 col = teak * (grain > 0.62 ? 0.82 : (grain > 0.4 ? 1.0 : 1.1));
	col *= 0.9 + hash(vec2(row, 1.0)) * 0.2;
	float seam = min(fract(c.y / plank), 1.0 - fract(c.y / plank)) * plank;
	if (seam < 0.12 || end < 0.12) {
		col = teak * 0.45;
	}
	col.a = 1.0;
	return col;
}

void fragment() {
	vec2 c = world / cell;
	vec2 map = map_size / cell;
	// How far outside the map (cells, by the nearest side), and the coordinate along that side.
	vec2 past = max(-c, c - map);
	if (max(past.x, past.y) <= 0.0) {
		discard;
	}
	bool sideways = past.x > past.y;
	float d = sideways ? past.x : past.y;
	float along = sideways ? c.y : c.x;
	float side = sideways ? (c.x < 0.0 ? 2.0 : 3.0) : (c.y < 0.0 ? 1.0 : 5.0);
	float edge = margin + (noise(vec2(along * 1.3, side)) - 0.5) * 2.0 * tear
		+ (noise(vec2(along * 6.0, side + 9.0)) - 0.5) * 0.25;
	// The torn edge's corners are cut round, so the sheet's corners aren't sharp.
	vec2 corner = max(past, vec2(0.0));
	float round_d = length(corner);
	vec4 col;
	if (d < edge && round_d < edge + 0.6) {
		col = daluang(c);
		if (d < 0.18 || (d > 2.5 && d < 2.66)) {
			col = sepia;
		} else if (d < 2.5) {
			float u = fract(along / 3.0);
			float rise = (d - 0.18) / 2.32;
			if (rise < 1.0 - abs(u - 0.5) * 2.0) {
				col = mod(floor(along / 3.0), 2.0) < 1.0 ? indigo : ochre;
				if (rise > 0.9 - abs(u - 0.5) * 2.0) {
					col = sepia;
				}
			}
		}
	} else {
		col = wood(c);
		float lift = max(d - edge, round_d - edge - 0.6);
		if (lift < 0.6) {
			col.rgb *= mix(0.55, 1.0, clamp(lift / 0.6, 0.0, 1.0));
		}
	}
	COLOR = col;
}
