shader_type canvas_item;
// FOCUSED 状态的“锁定”标记：轻微扫描线 + 边缘暗角。
// Alpha 由 shader 输出，叠加在 ZoomView 的 TextureRect 之上。

uniform float scanline_density : hint_range(40.0, 400.0) = 180.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.22;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.6;
uniform vec4 scanline_color : source_color = vec4(0.02, 0.03, 0.05, 1.0);
uniform vec4 edge_color : source_color = vec4(0.0, 0.02, 0.04, 1.0);

void fragment() {
	vec2 uv = UV;
	float scan = sin(uv.y * scanline_density * 3.14159265) * 0.5 + 0.5;
	float scan_alpha = pow(scan, 3.0) * scanline_strength;
	float arm = length(uv - vec2(0.5)) * 1.35;
	float vignette = smoothstep(0.32, 0.95, arm) * vignette_strength;
	vec3 tint = mix(scanline_color.rgb, edge_color.rgb, clamp(vignette * 1.5, 0.0, 1.0));
	COLOR = vec4(tint, clamp(scan_alpha + vignette, 0.0, 0.85));
}
