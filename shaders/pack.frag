#version 440
// Booster pack wrapper: crinkled metallic foil, crimped seals with zig-zag
// cut edges, and a sheen that follows tilt.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 tilt;
    float time;
    float aspect;
    vec4 colA; // top colour
    vec4 colB; // bottom colour
};

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

vec3 spectrum(float h) { return 0.5 + 0.5 * cos(6.28318 * (h + vec3(0.0, 0.33, 0.67))); }

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 P = uv * vec2(aspect, 1.0);
    const float crimp = 0.045;

    // zig-zag cut along top and bottom
    float teeth = abs(fract(uv.x * aspect * 22.0) - 0.5) * 2.0;
    float cut = teeth * 0.012;
    float alpha = step(cut, uv.y) * step(cut, 1.0 - uv.y);

    float n = noise(P * 14.0) * 0.6 + noise(P * 35.0) * 0.4;
    vec3 col = mix(colA.rgb, colB.rgb, smoothstep(0.0, 1.0, uv.y + (n - 0.5) * 0.08));
    col *= 0.7 + 0.45 * n;

    float h = uv.x * 0.7 + uv.y * 0.9 + tilt.x * 0.9 + n * 0.3 + time * 0.02;
    col = 1.0 - (1.0 - col) * (1.0 - spectrum(h) * 0.12);

    float s = uv.x * 0.65 + uv.y * 0.35 - (0.5 + tilt.x * 0.55 + tilt.y * 0.2) + (n - 0.5) * 0.12;
    col += exp(-s * s * 60.0) * vec3(1.0, 0.97, 0.9) * 0.35;

    if (uv.y < crimp || uv.y > 1.0 - crimp) {
        float ridge = 0.5 + 0.5 * sin(uv.x * aspect * 260.0);
        col = mix(col, col * 0.6 + 0.25, 0.35) * (0.8 + 0.3 * ridge);
    }

    col *= 0.6 + 0.4 * smoothstep(0.0, 0.04, uv.x) * smoothstep(0.0, 0.04, 1.0 - uv.x);
    fragColor = vec4(col, 1.0) * alpha * qt_Opacity;
}
