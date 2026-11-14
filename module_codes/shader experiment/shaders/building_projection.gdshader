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

uniform sampler2D wall_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 box_min;
uniform vec3 box_size;

void fragment() {
	vec3 origin = vec3(camera_ground.x, camera_height, camera_ground.y);
	vec3 ray = vec3((FRAGCOORD.x - screen_size.x * 0.5) / focal_length,
		(horizon - FRAGCOORD.y) / focal_length, 1.0);
	vec3 box_max = box_min + box_size;

	// 先求与正面 Z 平面的交点。
	vec3 hit = origin + ray * (box_min.z - origin.z);
	vec2 wall_uv = vec2((hit.x - box_min.x) / box_size.x,
		(box_max.y - hit.y) / box_size.y);
	bool visible = hit.x >= box_min.x && hit.x <= box_max.x &&
		hit.y >= box_min.y && hit.y <= box_max.y;
	float shade = 1.0;

	// 相机在建筑左侧时看左墙，在右侧时看右墙。
	if (!visible && (origin.x < box_min.x || origin.x > box_max.x) && ray.x != 0.0) {
		float side_x = origin.x < box_min.x ? box_min.x : box_max.x;
		float distance_z = (side_x - origin.x) / ray.x;
		hit = origin + ray * distance_z;
		visible = distance_z > 0.0 && hit.z >= box_min.z && hit.z <= box_max.z &&
			hit.y >= box_min.y && hit.y <= box_max.y;
		wall_uv = vec2((hit.z - box_min.z) / box_size.z,
			(box_max.y - hit.y) / box_size.y);
		if (origin.x < box_min.x) {
			wall_uv.x = 1.0 - wall_uv.x;
		}
		shade = 0.6;
	}

	COLOR = vec4(0.0);
	if (visible) {
		vec4 tile = texture(wall_texture, wall_uv);
		// 墙是实心面：图标透明圆角填底色，不穿透看到另一栋建筑。
		vec3 wall = mix(vec3(0.16, 0.19, 0.25), tile.rgb, tile.a);
		COLOR = vec4(wall * tint.rgb * shade, 1.0);
	}
}