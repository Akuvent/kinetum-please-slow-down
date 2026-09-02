shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
// Horizontal UV shift from top to bottom; match separator parallelogram slant (8px / 480px).
uniform float fill_skew : hint_range(0.0, 0.1) = 0.0167;
uniform vec4 tint : source_color = vec4(1.0);
uniform float scroll_speed : hint_range(0.0, 4.0) = 0.50;
uniform float cell_size : hint_range(4.0, 80.0) = 14.0;
uniform float dash_length : hint_range(0.02, 0.4) = 0.36;
uniform float dash_thickness : hint_range(0.02, 0.25) = 0.055;
uniform float scatter : hint_range(0.0, 1.0) = 0.9;
uniform float gap : hint_range(0.0, 0.2) = 0.06;
uniform float darken : hint_range(0.0, 1.0) = 0.75;
uniform float grid_rotation : hint_range(0.0, 360.0) = 8.0;
uniform float move_angle : hint_range(0.0, 360.0) = 180.0;

varying vec2 v_pixel;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash22(vec2 p) {
	return vec2(hash12(p), hash12(p + 19.17));
}

void vertex() {
	v_pixel = VERTEX;
}

void fragment() {
	// Slanted fill front parallel to separator bars: top row leads, bottom catches up at full.
	float threshold = progress * (1.0 + fill_skew);
	float fill_coord = UV.x + UV.y * fill_skew;
	float fill_mask = smoothstep(0.0, 0.003, threshold - fill_coord);
	if (fill_mask <= 0.0) {
		discard;
	}

	vec4 base = texture(TEXTURE, UV);

	float rot = radians(grid_rotation);
	mat2 rot_mat = mat2(vec2(cos(rot), -sin(rot)), vec2(sin(rot), cos(rot)));
	vec2 pattern = v_pixel * rot_mat;

	float move = radians(move_angle);
	vec2 dir = vec2(cos(move), sin(move));
	vec2 perp = vec2(-dir.y, dir.x);
	pattern += dir * TIME * scroll_speed * 60.0;

	vec2 grid_uv = pattern / cell_size;
	vec2 cell_id = floor(grid_uv);
	vec2 cell = fract(grid_uv) - 0.5;

	float half_len = dash_length;

	vec2 half_ext = abs(dir) * half_len + abs(perp) * dash_thickness;
	vec2 max_off = max(vec2(0.5 - gap) - half_ext, vec2(0.0));
	vec2 jitter = (hash22(cell_id + 7.3) * 2.0 - 1.0) * scatter;
	cell -= jitter * max_off;

	float along = abs(dot(cell, dir));
	float across = abs(dot(cell, perp));
	float aa = 0.012;
	float dash_mask = (1.0 - smoothstep(half_len, half_len + aa, along))
			* (1.0 - smoothstep(dash_thickness, dash_thickness + aa, across));

	vec4 dash_color = vec4(base.rgb * darken, base.a);
	COLOR = mix(base, dash_color, dash_mask);
	COLOR.rgb *= tint.rgb;
	COLOR.a *= fill_mask;
}
