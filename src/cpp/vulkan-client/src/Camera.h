#pragma once

// Configure GLM for Vulkan's coordinate system
#define GLM_FORCE_RADIANS
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

class Camera {
public:
    glm::vec2 position = {0.0f, 0.0f}; // Where we are looking
    float zoom = 1.0f;                 // How close we are

    // Calculate the View-Projection Matrix
    glm::mat4 getViewProjectionMatrix(float screenWidth, float screenHeight) {
        float aspectRatio = screenWidth / screenHeight;

        // 1. The Projection: Defines the size of our viewport in "World Units"
        // We use an orthographic projection for flat 2D strategy games.
        // We multiply by 'zoom' to make the world appear larger or smaller.
        float orthoHeight = 1.0f * zoom;
        float orthoWidth = aspectRatio * zoom;

        // Vulkan's Y-axis points DOWN. So top is -orthoHeight, bottom is +orthoHeight.
        glm::mat4 proj = glm::ortho(-orthoWidth, orthoWidth, -orthoHeight, orthoHeight, -1.0f, 1.0f);

        // 2. The View: Moves the world in the opposite direction of the camera
        glm::mat4 view = glm::translate(glm::mat4(1.0f), glm::vec3(-position.x, -position.y, 0.0f));

        // Multiply them together to give to the shader
        return proj * view;
    }
};
