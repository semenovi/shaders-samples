#version 300 es

precision highp float;
precision highp sampler2D;

in vec2 uv;
out vec4 out_color;

uniform vec2 u_resolution;
uniform float u_time;
uniform vec4 u_mouse;
uniform sampler2D u_textures[16];

const int MAX_ITERATIONS = 8;
const float BAILOUT = 2.0;
const int AO_SAMPLES = 5;
const float AO_STRENGTH = 0.5;

const float ANIM_AVG_TIME = 2000.0; // Среднее время в миллисекундах для полного изменения размера
const float ANIM_AVG_AMPLITUDE = 0.2; // Средняя амплитуда изменения размера в процентах от общего размера

mat2 rotate2D(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c);
}

vec3 rotate3D(vec3 p, vec2 angle) {
    p.yz = rotate2D(angle.y) * p.yz;
    p.xz = rotate2D(angle.x) * p.xz;
    return p;
}

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float mandelbulb(vec3 pos, vec2 angle, float power, float time, float randomSpeed, float randomAmplitude) {
    vec3 z = rotate3D(pos, angle);
    float dr = 1.0;
    float r = 0.0;

    for (int i = 0; i < MAX_ITERATIONS; i++) {
        r = length(z);
        if (r > BAILOUT) break;

        float theta = acos(z.z / r);
        float phi = atan(z.y, z.x);
        dr = pow(r, power - 1.0) * power * dr + 1.0;

        float zr = pow(r, power);
        theta = theta * power;
        phi = phi * power;

        z = zr * vec3(sin(theta) * cos(phi), sin(phi) * sin(theta), cos(theta));

        // Применение случайных изменений к координатам z с замедлением в 20 раз
        z += pos + vec3(
            sin(time * randomSpeed * 0.01 + pos.x * 0.1) * randomAmplitude,
            sin(time * randomSpeed * 0.012 + pos.y * 0.15) * randomAmplitude,
            sin(time * randomSpeed * 0.008 + pos.z * 0.2) * randomAmplitude
        );
    }

    return 0.5 * log(r) * r / dr;
}

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float ambientOcclusion(vec3 pos, vec2 angle, float power, float time, float randomSpeed, float randomAmplitude) {
    float ao = 0.0;
    float weight = 1.0;
    float scale = 1.0;
    for (int i = 0; i < AO_SAMPLES; i++) {
        float dist = scale * 0.1 * (float(i) +1.0);
        ao += weight * (dist - mandelbulb(pos + normalize(vec3(rand(pos.xy), rand(pos.yz), rand(pos.xz))) * dist, angle, power, time, randomSpeed, randomAmplitude));
        weight *= 0.5;
        scale *= 2.0;
    }
    return clamp(1.0 - AO_STRENGTH * ao, 0.0, 1.0);
}

float animateShape(vec2 st, float time) {
    st = st * 2.0 - 1.0;

    float a = atan(st.x, st.y) * 0.1;
    float r = length(st) * 0.5;

    float shape = cos(a * 3.0 + time * 2.0) * cos(a * 4.0 - time * 1.5) * sin(r * 2.0 - time * 1.2) * sin(r * 3.0 + time * 0.8);
    shape = smoothstep(0.0, 0.2, shape);

    return shape;
}

vec3 calculateGlow(vec3 color, float intensity) {
    vec3 glowColor = vec3(1.000, 0.024, 0.024); // Цвет свечения (черный)
    float glowThreshold = 0.5; // Порог яркости для применения свечения
    float glowIntensity = smoothstep(glowThreshold, 0.9, intensity);
    return mix(color, glowColor, glowIntensity);
}

vec3 calculateColor(float frac) {
    vec3 color1 = vec3(1.000, 0.000, 0.000); // Красный цвет для самых ярких частей
    vec3 color2 = vec3(0.0); // Черный цвет для менее ярких частей

    float smoothFrac = smoothstep(0.0, 1.0, frac);
    return mix(color1, color2, smoothFrac);
}

vec3 calculateNormal(vec3 pos, vec2 angle, float power, float time, float randomSpeed, float randomAmplitude) {
    const float epsilon = 0.0001;
    vec3 normal = vec3(
        mandelbulb(pos + vec3(epsilon, 0.000, 0.000), angle, power, time, randomSpeed, randomAmplitude) - mandelbulb(pos - vec3(epsilon, 0.000, 0.000), angle, power, time, randomSpeed, randomAmplitude),
        mandelbulb(pos + vec3(0.000, epsilon, 0.000), angle, power, time, randomSpeed, randomAmplitude) - mandelbulb(pos - vec3(0.000, epsilon, 0.000), angle, power, time, randomSpeed, randomAmplitude),
        mandelbulb(pos + vec3(0.000, 0.000, epsilon), angle, power, time, randomSpeed, randomAmplitude) - mandelbulb(pos - vec3(0.000, 0.000, epsilon), angle, power, time, randomSpeed, randomAmplitude)
    );
    return normalize(normal);
}

// God rays function based on the "Screen-Space God Rays" article by Evgenii Golubev:
// https://www.shadertoy.com/view/XdXGW8
vec3 calculateGodRays(vec2 uv, vec3 color, vec2 resolution) {
    vec2 p = (2.0 * uv - 1.0) * resolution.xy / min(resolution.x, resolution.y);
    vec2 q = p / resolution.xy;

    float weight = 1.0;
    float decay = 0.96;
    float sampleDistance = 0.5;
    float maxDistance = 50.0;vec3 godRaysColor = vec3(0.0);

for (int i = 0; i < 8; ++i) {
vec2 t = q + sampleDistance * vec2(float(i), 0.0);
float d = length(p - resolution.xy * t);
if (d > maxDistance) break;

float s = texture(u_textures[0], t).r;
float intensity = 1.0 - smoothstep(0.1, 0.0, s);
godRaysColor += weight * intensity * color;

weight *= decay;
}

return godRaysColor;
}


void main() {
vec2 st = (2.0 * uv - 1.0) * vec2(u_resolution.x / u_resolution.y, 1.0);

vec2 mouse = u_mouse.xy / u_resolution;
mouse.x = 1.0 - mouse.x;
mouse.x = mouse.x * 2.0;
mouse.y = mouse.y * 2.0;
vec2 angle = mouse * vec2(3.14, 1.57);

vec3 cam_pos = vec3(0.0, 0.0, 2.5);
vec3 ray_dir = normalize(vec3(st, -1.5));

float power = 8.0 + sin(u_time * 0.5) * 4.0;

// Генерация случайных значений для управления анимацией с замедлением в 20 раз
float randomSpeed = rand(vec2(u_time * 0.0025, 0.0)) * 0.0000000000000000000000000000001 + 100.06; // Случайная скорость изменений (0.01 - 0.06)
float randomAmplitude = rand(vec2(u_time * 0.005, 0.0)) * 0.01 + 0.6; // Случайная амплитуда изменений (0.001 - 0.006)

float dist = 0.0;
vec3 pos = cam_pos;
for (int i = 0; i < 64; i++) {
dist = mandelbulb(pos, angle, power, u_time, randomSpeed, randomAmplitude);
pos += ray_dir * dist;
if (dist < 0.001) break;
}

float light = clamp(1.0 - length(pos) / 2.0, 0.0, 1.0);

vec2 center = vec2(0.5);
float time = u_time * 0.5;
float spot = animateShape(uv - center, time);

vec3 bg_color = mix(vec3(0.0), vec3(0.278, 0.000, 0.000), spot);

vec3 color = vec3(1.0);
if (dist < 0.001) {
vec3 normal = calculateNormal(pos, angle, power, u_time, randomSpeed, randomAmplitude);
float ao = ambientOcclusion(pos, angle, power, u_time, randomSpeed, randomAmplitude);
float frac = clamp(dist / BAILOUT, 0.0, 1.0);
float brightness = 1.0 - pow(frac, 0.1);
color = calculateColor(frac);
color = calculateGlow(color, brightness);

// Применение сглаживания нормалей
vec3 smoothedNormal = vec3(1.0);
const int smoothingIterations = 5;
for (int i = 0; i < smoothingIterations; i++) {
vec3 offsetPos = pos + normal * (float(i) * 0.01);
smoothedNormal += calculateNormal(offsetPos, angle, power, u_time, randomSpeed, randomAmplitude);
}
smoothedNormal = normalize(smoothedNormal / float(smoothingIterations));

float diffuse = max(dot(smoothedNormal, vec3(0.694, 0.765, 1.000)), 0.0);
color *= diffuse;
color *= ao;
} else {
color = bg_color;
}


// Calculate god rays
vec3 godRaysColor = calculateGodRays(uv, color, u_resolution.xy);
out_color = vec4(color + godRaysColor, 1.0);

}
