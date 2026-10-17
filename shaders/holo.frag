#version 440
// Card face: rounded corners + holo foil, sparkles and a glare band that
// all move with the card's tilt. intensity 0 = plain card, 1 = full foil.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 tilt;       // -1..1 on each axis
    float time;      // seconds
    float intensity; // foil strength 0..1
    float gold;      // 0 = rainbow foil, 1 = gold foil
    float aspect;    // width / height
    float radius;    // corner radius, in height units
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 spectrum(float h) { return 0.5 + 0.5 * cos(6.28318 * (h + vec3(0.0, 0.33, 0.67))); }

void main() {
    vec2 uv = qt_TexCoord0;
    vec4 base = texture(source, uv);

    // rounded-rect mask
    vec2 size = vec2(aspect, 1.0);
    vec2 q = abs(uv * size - size * 0.5) - (size * 0.5 - radius);
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float mask = 1.0 - smoothstep(-0.002, 0.002, d);

    vec3 col = base.rgb;
    float lum = dot(col, vec3(0.299, 0.587, 0.114));

    if (intensity > 0.0) {
        // diagonal foil bands, rippled like diffraction foil
        float h = uv.x * 0.9 + uv.y * 1.3 + tilt.x * 0.8 - tilt.y * 0.6 + time * 0.03;
        h += 0.08 * sin(uv.y * 24.0 + uv.x * 9.0);
        vec3 goldc = mix(vec3(1.0, 0.72, 0.28), vec3(1.0, 0.96, 0.75), 0.5 + 0.5 * sin(h * 6.28318));
        vec3 foil = mix(spectrum(h), goldc, gold);
        float foilMask = 0.3 + 0.7 * smoothstep(0.12, 0.85, lum);
        col = 1.0 - (1.0 - col) * (1.0 - foil * intensity * 0.5 * foilMask);

        // twinkling sparkles on a grid, phase shifted by tilt
        vec2 g = uv * size * 70.0;
        float r = hash(floor(g));
        float tw = max(sin(time * 3.0 + r * 40.0 + (tilt.x + tilt.y) * 12.0), 0.0);
        float s = step(0.86, r) * smoothstep(0.35, 0.0, length(fract(g) - 0.5)) * tw;
        col += s * intensity * mix(spectrum(r + h), vec3(1.0), 0.5);

        // glare band sweeping across with tilt
        float band = uv.x * 0.7 + uv.y * 0.3 - (0.5 + tilt.x * 0.6 + tilt.y * 0.3);
        col += exp(-band * band * 90.0) * (0.12 + 0.25 * intensity);
    }

    // soft specular so even commons catch the light
    vec2 lp = vec2(0.5 + tilt.x * 0.5, 0.35 + tilt.y * 0.5);
    col += 0.08 * exp(-dot(uv - lp, uv - lp) * 6.0);

    fragColor = vec4(col, 1.0) * base.a * mask * qt_Opacity;
}
