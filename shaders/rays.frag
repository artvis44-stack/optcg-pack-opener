#version 440
// Rotating god-rays + glow core behind a big pull. Premultiplied output.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec4 color;
};

void main() {
    vec2 p = qt_TexCoord0 - 0.5;
    float a = atan(p.y, p.x);
    float r = length(p);

    float rays = pow(0.5 + 0.5 * sin(a * 14.0 + time * 0.8), 6.0)
               + 0.6 * pow(0.5 + 0.5 * sin(a * 9.0 - time * 0.5), 8.0);
    float v = rays * smoothstep(0.5, 0.05, r) * 0.8 + exp(-r * r * 18.0) * 0.9;

    fragColor = vec4(color.rgb * v, v) * clamp(v, 0.0, 1.0) * qt_Opacity;
}
