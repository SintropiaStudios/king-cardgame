#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 0) out vec2 fragTexCoord;

// Expect a 4x4 Matrix for our Camera
layout(push_constant) uniform PushConstants {
    mat4 viewProj;
} push;

void main() {
    // Multiply the world position by the camera matrix to get the screen position
    gl_Position = push.viewProj * vec4(inPosition, 0.0, 1.0);
    fragTexCoord = inTexCoord;
}