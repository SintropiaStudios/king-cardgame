#include "Font.h"
#include "Logger.h"
#include <fstream>

Font::~Font() {
    if (textureData) {
        delete[] textureData;
    }
}

bool Font::load(const std::string& ttfPath, float fontSize) {
    // 1. Read the raw TTF file into memory
    std::ifstream file(ttfPath, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        Logger::log(LogLevel::ERROR, "Failed to open font: ", ttfPath);
        return false;
    }
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<unsigned char> ttfBuffer(size);
    if (!file.read((char*)ttfBuffer.data(), size)) return false;

    // 2. Bake the font into a 1-channel alpha bitmap
    std::vector<unsigned char> tempBitmap(textureWidth * textureHeight);
    stbtt_BakeFontBitmap(ttfBuffer.data(), 0, fontSize, tempBitmap.data(), textureWidth, textureHeight, 32, 96, charData);

    // 3. Convert to 4-channel RGBA for easy Vulkan compatibility (White text, variable alpha)
    textureData = new unsigned char[textureWidth * textureHeight * 4];
    for (int i = 0; i < textureWidth * textureHeight; ++i) {
        textureData[i * 4 + 0] = 255; // R
        textureData[i * 4 + 1] = 255; // G
        textureData[i * 4 + 2] = 255; // B
        textureData[i * 4 + 3] = tempBitmap[i]; // A
    }

    Logger::log(LogLevel::INFO, "Font baked successfully: ", ttfPath);
    return true;
}

void Font::addTextToBatch(std::vector<Vertex>& batch, const std::string& text, float startX, float startY, float scale) const {
    float cursorX = 0.0f; 
    float cursorY = 0.0f;

    for (char c : text) {
        if (c >= 32 && c < 128) {
            stbtt_aligned_quad q;
            stbtt_GetBakedQuad(charData, textureWidth, textureHeight, c - 32, &cursorX, &cursorY, &q, 1);

            // 2. Scale the pixel output down, THEN add your world coordinates!
            float x0 = startX + (q.x0 * scale); 
            float x1 = startX + (q.x1 * scale);
            float y0 = startY + (q.y0 * scale); 
            float y1 = startY + (q.y1 * scale);

            batch.push_back({{x0, y0}, {q.s0, q.t0}});
            batch.push_back({{x1, y0}, {q.s1, q.t0}});
            batch.push_back({{x1, y1}, {q.s1, q.t1}});
            batch.push_back({{x1, y1}, {q.s1, q.t1}});
            batch.push_back({{x0, y1}, {q.s0, q.t1}});
            batch.push_back({{x0, y0}, {q.s0, q.t0}});
        }
    }
}

void Font::getTextBounds(const std::string& text, float scale, float& outWidth, float& outHeight) const {
    float x = 0.0f; float y = 0.0f;
    float minX = 10000.0f, minY = 10000.0f, maxX = -10000.0f, maxY = -10000.0f;

    for (char c : text) {
        if (c >= 32 && c < 128) {
            stbtt_aligned_quad q;
            stbtt_GetBakedQuad(charData, textureWidth, textureHeight, c - 32, &x, &y, &q, 1);
            if (q.x0 < minX) minX = q.x0; if (q.y0 < minY) minY = q.y0;
            if (q.x1 > maxX) maxX = q.x1; if (q.y1 > maxY) maxY = q.y1;
        }
    }
    outWidth = (maxX - minX) * scale;
    outHeight = (maxY - minY) * scale;
}
