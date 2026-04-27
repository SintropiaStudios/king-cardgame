#version 450

// Input straight from the Vertex Shader
layout(location = 0) in vec2 fragTexCoord;

// The final color painted to the screen
layout(location = 0) out vec4 outColor;

// Our cards.png image atlas
layout(binding = 0) uniform sampler2D texSampler;

void main() {
    // Sample the exact color from the atlas using the coordinates
    outColor = texture(texSampler, fragTexCoord);
    // Output pure white so we can see the shape of the card!
    // outColor = vec4(1.0, 1.0, 1.0, 1.0);
}
