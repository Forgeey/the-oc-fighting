shader_type canvas_item;
render_mode unshaded;

// 与其他场景相同：相机节点是配置入口，这里接收运行时输出。
group_uniforms CameraRuntime;
uniform vec2 screen_size;
uniform vec2 camera_ground;
uniform float camera_height;
uniform float focal_length;
uniform float horizon;
group_uniforms;

uniform sampler2D front_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D side_texture : source_color, filter_nearest, repeat_disable;
uniform mat3 side_reference_map;
uniform vec4 tint : source_color = vec4(1.0);
uniform float side_brightness : hint_range(0.0, 1.5) = 1.0;
uniform vec3 box_min;
uniform vec3 box_size;

void fragment() {
	vec3 origin = vec3(camera_ground.x, camera_height, camera_ground.y);
	vec3 ray = vec3((FRAGCOORD.x - screen_size.x * 0.5) / focal_length,
		(horizon - FRAGCOORD.y) / focal_length, 1.0);
	vec3 box_max = box_min + box_size;
	vec3 hit = origin + ray * (box_min.z - origin.z);
	vec2 face_uv = vec2((hit.x - box_min.x) / box_size.x,
		(box_max.y - hit.y) / box_size.y);
	bool front = hit.x >= box_min.x && hit.x <= box_max.x &&
		hit.y >= box_min.y && hit.y <= box_max.y;
	bool side = false;

	if (!front && (origin.x < box_min.x || origin.x > box_max.x) && ray.x != 0.0) {
		float side_x = origin.x < box_min.x ? box_min.x : box_max.x;
		float depth = (side_x - origin.x) / ray.x;
		hit = origin + ray * depth;
		side = depth > 0.0 && hit.z >= box_min.z && hit.z <= box_max.z &&
			hit.y >= box_min.y && hit.y <= box_max.y;
		// 两侧都使用近端=0、远端=1。左墙由空间映射自然镜像，不能再次倒置参考角点。
		face_uv = vec2((hit.z - box_min.z) / box_size.z,
			(box_max.y - hit.y) / box_size.y);
	}

	COLOR = vec4(0.0);
	if (front) {
		COLOR = texture(front_texture, face_uv) * tint;
	} else if (side) {
		// H_ref * H_now^-1：求交已完成当前画面 → 局部面，再映射到预绘参考图。
		vec3 reference = side_reference_map * vec3(face_uv, 1.0);
		vec2 reference_uv = reference.xy / reference.z;
		if (all(greaterThanEqual(reference_uv, vec2(0.0))) &&
			all(lessThanEqual(reference_uv, vec2(1.0)))) {
			vec4 art = texture(side_texture, reference_uv);
			COLOR = vec4(art.rgb * tint.rgb * side_brightness, art.a * tint.a);
		}
	}
}