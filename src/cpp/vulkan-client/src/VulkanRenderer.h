#pragma once
#include <SDL2/SDL.h>
#include <vulkan/vulkan.h>
#include <glm/glm.hpp>
#include <vector>
#include <string>
#include <optional>
#include <algorithm> // Needed for std::clamp
#include <fstream>
#include <array>

// Toggle validation layers based on debug/release mode
#ifdef NDEBUG
    const bool enableValidationLayers = false;
#else
    const bool enableValidationLayers = true;
#endif

// A helper struct to hold the Swapchain compatibility data
struct SwapChainSupportDetails {
    VkSurfaceCapabilitiesKHR capabilities;
    std::vector<VkSurfaceFormatKHR> formats;
    std::vector<VkPresentModeKHR> presentModes;
};

// A helper struct to track if we found the necessary queue families
struct QueueFamilyIndices {
    std::optional<uint32_t> graphicsFamily;

    bool isComplete() {
        return graphicsFamily.has_value();
    }
};

// C++ Vertex representation
struct Vertex {
    float pos[2];      // x, y
    float texCoord[2]; // u, v

    // Tells Vulkan how many bytes between each vertex
    static VkVertexInputBindingDescription getBindingDescription() {
        VkVertexInputBindingDescription bindingDescription{};
        bindingDescription.binding = 0;
        bindingDescription.stride = sizeof(Vertex);
        bindingDescription.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;
        return bindingDescription;
    }

    // Tells Vulkan what the variables inside the vertex look like (matching our Shader layout)
    static std::array<VkVertexInputAttributeDescription, 2> getAttributeDescriptions() {
        std::array<VkVertexInputAttributeDescription, 2> attributeDescriptions{};

        // layout(location = 0) in vec2 inPosition;
        attributeDescriptions[0].binding = 0;
        attributeDescriptions[0].location = 0;
        attributeDescriptions[0].format = VK_FORMAT_R32G32_SFLOAT;
        attributeDescriptions[0].offset = offsetof(Vertex, pos);

        // layout(location = 1) in vec2 inTexCoord;
        attributeDescriptions[1].binding = 0;
        attributeDescriptions[1].location = 1;
        attributeDescriptions[1].format = VK_FORMAT_R32G32_SFLOAT;
        attributeDescriptions[1].offset = offsetof(Vertex, texCoord);

        return attributeDescriptions;
    }
};

// Group vertices by which texture they use
struct RenderBatch {
    uint32_t textureId;
    std::vector<Vertex> vertices;
};

// Encapsulate Vulkan texture resources
struct TextureData {
    VkImage image;
    VkDeviceMemory memory;
    VkImageView view;
    VkSampler sampler;
    VkDescriptorSet descriptorSet; 
};

// 52 cards * 6 vertices per card = 312 vertices maximum
const int MAX_VERTICES = 1000;
const int MAX_TEXTURES = 100;

class VulkanRenderer {
public:
    VulkanRenderer(const char* windowTitle, int width, int height);
    ~VulkanRenderer();
    SDL_Window* getWindow() const { return window; }

    // Dynamic loading methods returning a Texture ID
    uint32_t loadTexture(const std::string& filepath);
    uint32_t loadTextureFromPixels(unsigned char* pixels, int width, int height);

    // Draw a list of batches
    void drawFrame(const std::vector<RenderBatch>& batches, const glm::mat4& viewProj);

    // Waits for the GPU to finish before shutting down
    void waitIdle();

    // Inform of a Resize Event
    bool framebufferResized = false;

private:
    SDL_Window* window = nullptr;
    VkInstance instance = VK_NULL_HANDLE;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkDebugUtilsMessengerEXT debugMessenger = VK_NULL_HANDLE; // The debug handle
    // The physical GPU (or CPU in the case of llvmpipe)
    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
    // The Logical Device and Queue Handles
    VkDevice device = VK_NULL_HANDLE;
    VkQueue graphicsQueue = VK_NULL_HANDLE;
    // Swapchain Handles and Data
    VkSwapchainKHR swapChain = VK_NULL_HANDLE;
    std::vector<VkImage> swapChainImages;
    VkFormat swapChainImageFormat;
    VkExtent2D swapChainExtent;
    // Container for the Image Views
    std::vector<VkImageView> swapChainImageViews;
    // The Render Pass Handle
    VkRenderPass renderPass = VK_NULL_HANDLE;
    // Container for the Framebuffers
    std::vector<VkFramebuffer> swapChainFramebuffers;
    // Command Pool and Buffer
    VkCommandPool commandPool = VK_NULL_HANDLE;
    VkCommandBuffer commandBuffer = VK_NULL_HANDLE;
    // Synchronization Objects
    VkSemaphore imageAvailableSemaphore = VK_NULL_HANDLE;
    VkSemaphore renderFinishedSemaphore = VK_NULL_HANDLE;
    VkFence inFlightFence = VK_NULL_HANDLE;
    // Pipeline Handles
    VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
    VkPipeline graphicsPipeline = VK_NULL_HANDLE;
    // Descriptor Set Layout
    VkDescriptorSetLayout descriptorSetLayout = VK_NULL_HANDLE;

    // Vertex Buffer Handles
    VkBuffer vertexBuffer = VK_NULL_HANDLE;
    VkDeviceMemory vertexBufferMemory = VK_NULL_HANDLE;
    // Descriptor Pool
    VkDescriptorPool descriptorPool = VK_NULL_HANDLE;
    // Textures
    std::vector<TextureData> textures;

    // Helper to generate a texture from raw data
    uint32_t createTextureFromData(unsigned char* pixels, int width, int height);

    const std::vector<const char*> validationLayers = {
        "VK_LAYER_KHRONOS_validation"
    };

    const std::vector<const char*> deviceExtensions = {
        VK_KHR_SWAPCHAIN_EXTENSION_NAME
    };

    // Initialization, Instance, Surface and Debug Layer
    void initSDL(const char* title, int width, int height);
    void initVulkan();
    bool checkValidationLayerSupport();
    void createInstance();
    void setupDebugMessenger();
    void createSurface();

    // Physical Device selection
    void pickPhysicalDevice();
    bool isDeviceSuitable(VkPhysicalDevice device);
    QueueFamilyIndices findQueueFamilies(VkPhysicalDevice device);

    // Logical Device Creation
    void createLogicalDevice();

    // Swapchain Creation
    SwapChainSupportDetails querySwapChainSupport(VkPhysicalDevice device);
    VkSurfaceFormatKHR chooseSwapSurfaceFormat(const std::vector<VkSurfaceFormatKHR>& availableFormats);
    VkPresentModeKHR chooseSwapPresentMode(const std::vector<VkPresentModeKHR>& availablePresentModes);
    VkExtent2D chooseSwapExtent(const VkSurfaceCapabilitiesKHR& capabilities);
    void createSwapChain();
    void cleanupSwapChain();
    void recreateSwapChain();

    // Image View Creation
    void createImageViews();

    // Render Pass Creation
    void createRenderPass();
    // Descriptor Set Layout
    void createDescriptorSetLayout();

    // Graphics Pipeline & Shader loading
    void createGraphicsPipeline();
    VkShaderModule createShaderModule(const std::vector<char>& code);
    static std::vector<char> readFile(const std::string& filename);

    // Buffer & Memory Methods
    uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties);
    void createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties, VkBuffer& buffer, VkDeviceMemory& bufferMemory);
    void createVertexBuffer();

    // Image Methods
    void createImage(uint32_t width, uint32_t height, VkFormat format, VkImageTiling tiling, VkImageUsageFlags usage, VkMemoryPropertyFlags properties, VkImage& image, VkDeviceMemory& imageMemory);

    // Image Transfer & Setup Methods
    VkCommandBuffer beginSingleTimeCommands();
    void endSingleTimeCommands(VkCommandBuffer commandBuffer);
    void transitionImageLayout(VkImage image, VkFormat format, VkImageLayout oldLayout, VkImageLayout newLayout);
    void copyBufferToImage(VkBuffer buffer, VkImage image, uint32_t width, uint32_t height);
    
    // Descriptor creation methods
    void createDescriptorPool();
    //void createDescriptorSets();

    // Generic Vulkan handle generators
    VkImageView createImageViewHelper(VkImage image, VkFormat format);
    VkSampler createSamplerHelper();

    // Framebuffer Creation
    void createFramebuffers();

    // Command Pool and Buffer Creation
    void createCommandPool();
    void createCommandBuffer();

    // Sync objects and Drawing
    void createSyncObjects();
    void recordCommandBuffer(VkCommandBuffer commandBuffer, uint32_t imageIndex, const std::vector<RenderBatch>& batches, glm::mat4 viewProjMatrix);

    // The Vulkan debug callback function
    static VKAPI_ATTR VkBool32 VKAPI_CALL debugCallback(
        VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
        VkDebugUtilsMessageTypeFlagsEXT messageType,
        const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
        void* pUserData);
};