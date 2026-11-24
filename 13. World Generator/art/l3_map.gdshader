shader_type canvas_item;

// The L3 world map from its fields (WorldPlaceholder.l3_fields): R height, G temperature, B moisture, read
// smoothly so every edge is a curve. Sea by depth with a shallow band; land by the
// biome table, mountains and snow by height; land and mountains each keep a shaded crescent on the side
// away from the light (flat-vector lit copy); a faint grid of meridians and parallels over it all.

uniform sampler2D table : filter_nearest;
uniform float sea = 0.5;
uniform float mountain = 0.74;
uniform float snow = 0.84;
// The lit copy's shift, in cells, toward the bottom-right.
uniform vec2 light = vec2(0.45, 0.45);
uniform vec4 deep : source_color = vec4(0.16, 0.34, 0.53, 1.0);
uniform vec4 shallow : source_color = vec4(0.27, 0.49, 0.66, 1.0);
uniform vec4 sea_ice : source_color = vec4(0.84, 0.89, 0.93, 1.0);
uniform vec4 rock : source_color = vec4(0.50, 0.48, 0.44, 1.0);
uniform vec4 peak : source_color = vec4(0.94, 0.95, 0.97, 1.0);
uniform vec4 ink : source_color = vec4(0.16, 0.14, 0.12, 1.0);
// A faint grid of meridians and parallels every this many cells, the equator stronger.
uniform float grid = 16.0;

void fragment() {
	vec4 f = texture(TEXTURE, UV);
	float h = f.r;
	float lit_h = texture(TEXTURE, UV + light * TEXTURE_PIXEL_SIZE).r;
	float edge = fwidth(h);
	vec4 col;
	if (h < sea) {
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
			if (h - mountain < edge * 1.0) {
				col.rgb = mix(col.rgb, ink.rgb, 0.5);
			}
		}
	}
	vec2 cells = UV / TEXTURE_PIXEL_SIZE;
	vec2 near = abs(fract(cells / grid + 0.5) - 0.5) * grid / fwidth(cells);
	if (min(near.x, near.y) < 0.6) {
		col.rgb = mix(col.rgb, ink.rgb, 0.18);
	}
	float equator = abs(cells.y - 0.5 / TEXTURE_PIXEL_SIZE.y) / fwidth(cells.y);
	if (equator < 0.9) {
		col.rgb = mix(col.rgb, ink.rgb, 0.4);
	}
	COLOR = col;
}
