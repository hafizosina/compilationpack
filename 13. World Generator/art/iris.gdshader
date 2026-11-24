shader_type canvas_item;

// The L2-L1 transition cover: everything outside a circle is a flat dark fill, with a hard ink rim.
// `center` and `radius` are in screen pixels; `size` is the rect's size in pixels.

uniform vec2 size = vec2(1612.0, 720.0);
uniform vec2 center = vec2(806.0, 360.0);
uniform float radius = 2000.0;
uniform float rim = 6.0;
uniform vec4 fill : source_color = vec4(0.11, 0.10, 0.09, 1.0);
uniform vec4 ink : source_color = vec4(0.36, 0.30, 0.22, 1.0);

void fragment() {
	float d = distance(UV * size, center);
	if (d < radius) {
		COLOR = vec4(0.0);
	} else if (d < radius + rim) {
		COLOR = ink;
	} else {
		COLOR = fill;
	}
}
