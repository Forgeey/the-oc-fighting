shader_type canvas_item;
render_mode unshaded;

// 由 MapCamera 写入的运行时数据。请在相机节点修改，不在材质修改。
group_uniforms CameraRuntime;
uniform vec2 screen_size;
uniform vec2 camera_ground;
uniform float camera_height;
uniform float focal_length;
uniform float horizon;
group_uniforms;

uniform sampler2D ground_texture : source_color, filter_nearest, repeat_enable;
uniform vec2 ground_min = vec2(-1260.0, -1000.0);
uniform vec2 ground_max = vec2(1260.0, 1100.0);
uniform float tile_size = 128.0;

// 世界 Z 标线，默认与角色战斗线 Z=0 重合；只用于观察。
uniform bool show_guide = true;
uniform float guide_z = 0.0;
uniform float guide_half_width : hint_range(1.0, 40.0) = 12.0;

// 计算屏幕像素所在伪3D空间的位置，并进行渲染
void fragment() {
	vec3 ray = vec3((FRAGCOORD.x - screen_size.x * 0.5) / focal_length,
		(horizon - FRAGCOORD.y) / focal_length, 1.0);
	if (ray.y >= 0.0) {
		COLOR = vec4(0.0);
	} else {
		// 射线与 Y=0 地面求交；与建筑使用相同的观察射线。
		float depth = -camera_height / ray.y;
		vec2 ground = camera_ground + ray.xz * depth;
		if (ground.x < ground_min.x || ground.x > ground_max.x ||
			ground.y < ground_min.y || ground.y > ground_max.y) {
			COLOR = vec4(0.0);
		} else {
			vec4 tile = texture(ground_texture, (ground - ground_min) / tile_size);
			vec3 color = mix(vec3(0.10, 0.15, 0.20), tile.rgb, tile.a);
			// 标线厚度使用世界单位，投影后也会随远近变化，不参与碰撞。
			float line = show_guide ? 1.0 - smoothstep(guide_half_width,
				guide_half_width * 2.0, abs(ground.y - guide_z)) : 0.0;
			COLOR = vec4(mix(color * 0.7, vec3(0.55, 0.85, 1.0), line), 1.0);
		}
	}
}
