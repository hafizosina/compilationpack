shader_type canvas_item;

// The L3 world map, by biome or one field at a time, from its fields (WorldMap.fields_image): R height, G heat,
// B humidity, A lake, read
// smoothly so every edge is a curve. Sea by depth with a shallow band; land by the
// biome table, mountains and snow by height; land and mountains each keep a shaded crescent on the side
// away from the light (flat-vector lit copy). All of it painted on daluang: faded, warmed, fibres showing.

uniform sampler2D table : filter_nearest;
// The map mode: -1 biomes, else the field (0 height, 1 heat, 2 humidity) shown through `ramp`.
uniform int field = -1;
uniform sampler2D ramp : filter_nearest;
uniform float sea = 0.5;
uniform float mountain = 0.74;
uniform float snow = 0.84;
// The lit copy's shift, in cells, toward the bottom-right.
uniform vec2 light = vec2(0.45, 0.45);
uniform vec4 deep : source_color = vec4(0.16, 0.34, 0.53, 1.0);
uniform vec4 shallow : source_color = vec4(0.27, 0.49, 0.66, 1.0);
uniform vec4 sea_ice : source_color = vec4(0.84, 0.89, 0.93, 1.0);
uniform vec4 lake_water : source_color = vec4(0.31, 0.52, 0.67, 1.0);
uniform vec4 rock : source_color = vec4(0.50, 0.48, 0.44, 1.0);
uniform vec4 peak : source_color = vec4(0.94, 0.95, 0.97, 1.0);
uniform vec4 ink : source_color = vec4(0.29, 0.19, 0.11, 1.0);
uniform vec4 paper : source_color = vec4(0.95, 0.86, 0.68, 1.0);
// Thin lines along the shore and round the mountains, in a dark sea-blue and a dark earth-brown, never black.
uniform vec4 shore_line : source_color = vec4(0.17, 0.29, 0.38, 1.0);
uniform vec4 ridge_line : source_color = vec4(0.36, 0.27, 0.19, 1.0);
uniform float line = 0.8;

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
	vec4 f = texture(TEXTURE, UV);
	float h = f.r;
	float lit_h = texture(TEXTURE, UV + light * TEXTURE_PIXEL_SIZE).r;
	float edge = fwidth(h);
	vec4 col;
	if (field >= 0) {
		col = texture(ramp, vec2(clamp(f[field], 0.0, 0.999), 0.5));
		if (h >= sea && lit_h < sea) {
			col.rgb *= 0.8;
		}
	} else if (h < sea) {
		col = h > sea - 0.05 ? shallow : deep;
		if (f.g < 0.12) {
			col = sea_ice;
		}
	} else {
		col = texture(table, vec2(f.g, f.b));
		if (lit_h < sea) {
			col.rgb *= 0.8;
		}
		if (h > mountain) {
			col = h > snow ? peak : rock;
			if (lit_h < mountain) {
				col.rgb *= 0.78;
			}
		}
	}
	// Lakes stand on land; their edge is where the lake flag, read smoothly, crosses a half.
	if (h >= sea && f.a > 0.5 && field != 1) {
		col = lake_water;
	}
	if (h >= sea && field != 1 && abs(f.a - 0.5) < fwidth(f.a) * line * 0.5) {
		col = shore_line;
	}
	if (h >= sea && h - sea < edge * line) {
		col = shore_line;
	} else if (field < 0 && h >= mountain && h - mountain < edge * line) {
		col = ridge_line;
	}
	// Pigment on daluang: colours a little faded and warmed, bark fibres showing through.
	vec2 cells = UV / TEXTURE_PIXEL_SIZE;
	float fibre = noise(cells * vec2(0.5, 9.0)) * 0.6 + noise(cells * vec2(2.0, 22.0)) * 0.4;
	col.rgb = mix(col.rgb, col.rgb * paper.rgb, 0.45) * (fibre > 0.62 ? 0.92 : 1.0);
	COLOR = col;
}
