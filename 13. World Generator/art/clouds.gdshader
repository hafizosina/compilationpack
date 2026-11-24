shader_type canvas_item;

// The L3-L2 transition cover: Perlin noise read as a height map, cloud where it rises above `level`. As
// `cover` goes 0 -> 1 the level falls, so clouds grow out of the noise until they fill the screen. Drawn
// flat-vector: hard edges, an ink rim, each tier's lit copy shifted toward the light (top-left) leaving a
// shaded crescent, and a higher tier of puffs on top.

uniform sampler2D height : repeat_enable, filter_linear;
uniform vec2 size = vec2(1612.0, 720.0);
uniform float cover = 0.0;
// Noise tiles a screen height this many times; lower is bigger clouds.
uniform float scale = 0.4;
uniform vec2 drift = vec2(0.012, 0.004);
// How far the lit copy sits from the shape, in noise units.
uniform vec2 light = vec2(0.003, 0.003);
uniform float rim = 0.016;
uniform float tier = 0.14;
uniform vec4 lit : source_color = vec4(0.96, 0.97, 1.0, 1.0);
uniform vec4 shade : source_color = vec4(0.80, 0.84, 0.92, 1.0);
uniform vec4 ink : source_color = vec4(0.36, 0.42, 0.51, 1.0);

float h(vec2 p) {
	return texture(height, p).r;
}

void fragment() {
	vec2 p = UV * vec2(size.x / size.y, 1.0) * scale + drift * TIME;
	float level = mix(1.02, -0.25, cover);
	float here = h(p);
	if (here < level) {
		COLOR = vec4(0.0);
	} else {
		float up = h(p + light);
		vec4 col = up >= level ? lit : shade;
		if (here < level + rim) {
			col = ink;
		} else if (here >= level + tier) {
			col = up >= level + tier ? lit : shade;
			if (here < level + tier + rim * 0.7) {
				col = mix(col, ink, 0.55);
			}
		}
		COLOR = col;
	}
}
