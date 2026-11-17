shader_type spatial;
// 地面网格：按世界坐标 xz 画抗锯齿网格线。
render_mode unshaded, cull_back;

uniform vec4 base_color : source_color = vec4(0.09, 0.10, 0.13, 1.0);
uniform vec4 line_color : source_color = vec4(0.30, 0.42, 0.55, 1.0);
uniform float cell_size = 1.0;
uniform float line_power : hint_range(1.0, 8.0) = 1.6;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 coord = world_pos.xz / cell_size;
	vec2 deriv = max(fwidth(coord), vec2(0.0001));
	vec2 grid = abs(fract(coord - 0.5) - 0.5) / deriv;
	float line = 1.0 - min(min(grid.x, grid.y), 1.0);
	line = pow(line, line_power);
	ALBEDO = mix(base_color.rgb, line_color.rgb, line);
}
