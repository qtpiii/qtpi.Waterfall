shader_type spatial;
render_mode depth_draw_always; //, unshaded;

uniform vec4 albedo: hint_color;
uniform vec4 albedo2: hint_color;
uniform float alpha = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;
uniform vec3 emission = vec3(1.0, 1.0, 1.0);
uniform float normal_scale = 1.0;

uniform sampler2D wave_tex;
uniform sampler2D texture_normal;
uniform sampler2D texture_normal2;

uniform vec2 wave_direction = vec2(2.0, 0.0);
uniform vec2 wave_direction2 = vec2(0.0, 1.0);
uniform float wave_scale = 1.0;
uniform float normal_time_scale = 1.0;
uniform float wave_time_scale :  hint_range(0.0, 0.2, 0.005) = 0.025;
uniform float noise_scale = 10.0;
uniform float height_scale = 0.15;

// Dirx, Dirz, Steepness, Wavelength
uniform vec4 gersner_wave_a = vec4(1.0, 0.0, 0.5, 50.0);
uniform vec4 gersner_wave_b = vec4(1.0, 0.0, 0.5, 50.0);
uniform vec4 gersner_wave_c = vec4(1.0, 0.0, 0.5, 50.0);
uniform vec4 gersner_wave_d = vec4(1.0, 0.0, 0.5, 50.0);
uniform vec4 gersner_wave_e = vec4(1.0, 0.0, 0.5, 50.0);

uniform float ocean_intensity = 1.0;
uniform float wave_time = 1.0;

uniform vec4 color_deep : hint_color;
uniform vec4 color_shallow : hint_color;
uniform float beers_law = 2.0;
uniform float depth_offset = -0.75;

uniform float edge_scale = 0.1;
uniform float near = 1.0;
uniform float far = 100.0;
uniform vec4 foam_color : hint_color;
uniform float foam_amt = 0.15;
uniform float foam_scale = 1.0;
uniform float edge_foam = 1.0;

uniform sampler2D foam_noise;
uniform float foam_threshold = 0.85;

uniform float upper_wave_mult = 0.7;
uniform vec4 upper_wave_color : hint_color;

uniform float whitecap_min = 0.7;
uniform float whitecap_max = 0.7;
uniform vec4 whitecap_color : hint_color;

uniform vec2 player_position;
uniform bool underwater_vision = false;

varying float height;
varying vec3 world_pos;

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}
float edge(float depth) {
	depth = 2.0 * depth - 1.0;
	return near * far / (far + depth * (near - far));
}
vec3 gerstner_wave(vec4 wave, vec3 vert, vec3 tangent, vec3 binormal) {
	float PI = 3.14159265358979323;
	float steepness = wave.z * ocean_intensity;
	float wavelength = wave.a;
	
	float k = 2.0 * PI / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(wave.xy);
	float f = k * (dot(d, vert.xz) - c * (TIME*wave_time));
	float a  = steepness / k;
	
	tangent += vec3(
		-d.x * d.x * (steepness * sin(f)),
		d.x * (steepness * cos(f)),
		-d.x * d.y * (steepness * sin(f))
	);
	
	binormal += vec3(
		-d.x * d.y * (steepness * sin(f)),
		d.y * (steepness * cos(f)),
		-d.y * d.y * (steepness * sin(f))
	);
	
	return vec3(
		d.x * (a * cos(f)),
		a * sin(f),
		d.y * (a * cos(f))
	);
	
}


void vertex() {
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	vec2 point = world_pos.xz / 40.0;
	//height = texture(wave_tex, point).r;
	float nheight = texture(wave_tex, point / noise_scale + TIME * wave_time_scale).r;
	VERTEX.y += nheight * height_scale * ocean_intensity;
	
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	VERTEX += gerstner_wave(gersner_wave_a, world_pos, tangent, binormal);
	VERTEX += gerstner_wave(gersner_wave_b, world_pos, tangent, binormal);
	VERTEX += gerstner_wave(gersner_wave_c, world_pos, tangent, binormal);
	VERTEX += gerstner_wave(gersner_wave_d, world_pos, tangent, binormal);
	VERTEX += gerstner_wave(gersner_wave_e, world_pos, tangent, binormal);
	NORMAL = normalize(cross(binormal, tangent));
	
	height = VERTEX.y;
}

void fragment() {
	// Depth Variables
	vec3 color = color_shallow.rgb;
	
	// Edge Calc
	float z_dif = 1.0;
	if (!underwater_vision) {
		float z_depth = edge(texture(DEPTH_TEXTURE, SCREEN_UV).x);
		float z_pos = edge(FRAGCOORD.z);
		z_dif = z_depth - z_pos;
	}
	
	// Normals Time Calc
	vec2 time = (TIME * wave_direction) * normal_time_scale;
	vec2 time2 = (TIME * wave_direction2) * normal_time_scale;
	// Blend
	vec3 normal_blend = mix(texture(texture_normal, (world_pos.xz * wave_scale) + time).rgb, texture(texture_normal2, (world_pos.xz * wave_scale) + time2).rgb, 0.5);
	
	// Freh-nel (Fresnel)
	float fresnel = fresnel(7.5, NORMAL, VIEW);
	vec4 surface_color = mix(albedo, albedo2, fresnel);
	
	// Wave Color Diff
	float upper = clamp(height * upper_wave_mult, 0.0, 1.0);
	vec4 upper_wave_mix = mix(surface_color, upper_wave_color, upper);
	
	// Whitecaps
	float wcap_min = whitecap_min; // * ocean_intensity + 2.0; //Eventually add whitecaps w low intensity
	float wcap_max = whitecap_max; // * ocean_intensity + 6.0; 
	float wcheck = (height + texture(wave_tex, world_pos.xz / noise_scale + TIME * wave_time_scale).r);
	if (wcheck > wcap_min) {
		float amt = (wcheck-wcap_min)/(wcap_max-wcap_min);
		upper_wave_mix = mix(upper_wave_mix, whitecap_color, min(1.0, amt));
	}
	
	// Beers Law
	float depth_texture = texture(DEPTH_TEXTURE, SCREEN_UV).r * 2.0 - 1.0;
	float depth = PROJECTION_MATRIX[3][2] / (depth_texture + PROJECTION_MATRIX[2][2]);
	float depth_blend = exp((depth + VERTEX.z + depth_offset) * -beers_law);
	depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);
	float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

	vec3 screen_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, depth_blend_power * 2.5).rgb;
	vec3 depth_color = mix(color_shallow.rgb, color_deep.rgb, depth_blend_power);
	color = mix(screen_color * depth_color, depth_color * 0.25, depth_blend_power * 0.5);
	upper_wave_mix.rgb = mix(upper_wave_mix.rgb, color, 0.25);
	
	// Foam Noise
	vec4 foam_set = (texture(foam_noise, world_pos.xz / foam_scale + TIME * wave_time_scale)) * foam_color;
	upper_wave_mix = mix(upper_wave_mix, foam_set, foam_amt);
	
	if (step(edge_scale, z_dif - (foam_set.r * edge_foam)) < 1.0) {
		upper_wave_mix.rgb = foam_color.rgb;
	}
	
	ALBEDO = clamp(upper_wave_mix.rgb, vec3(0.0), vec3(1.0));
	//if (!underwater_vision) { ALPHA = alpha; }
	METALLIC = metallic;
	ROUGHNESS = roughness;
	NORMALMAP = normal_blend;
	NORMALMAP_DEPTH = normal_scale;
	EMISSION = emission;
}