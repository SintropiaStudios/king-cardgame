#pragma once
#include <string>
#include <vector>
#include "stb_truetype.h"
#include "VulkanRenderer.h" // For your Vertex struct

class Font {
public:
    Font() = default;
    ~Font();

    // Bakes the TTF into an RGBA pixel array we can send to Vulkan
    bool load(const std::string& ttfPath, float fontSize);

    // Generates the geometry for a string of text
    void addTextToBatch(std::vector<Vertex>& batch, const std::string& text, float startX, float startY, float scale) const;

    // Calculates the clickable bounding box (AABB) of the text
    void getTextBounds(const std::string& text, float scale, float& outWidth, float& outHeight) const;

    // The raw RGBA pixels to hand to Vulkan
    unsigned char* textureData = nullptr;
    int textureWidth = 512;
    int textureHeight = 512;

private:
    stbtt_bakedchar charData[96]; // ASCII 32..126
};
