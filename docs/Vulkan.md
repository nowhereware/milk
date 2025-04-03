# Vulkan

Milk's graphics system ideally targets multiple graphics APIs depending on the desired platform, among which is Vulkan. Vulkan is the preferred API when running on Linux/BSD platforms, and is usually an optional platform when running on Windows.
Vulkan is used for several reasons, and has several advantages over older traditional APIs such as OpenGL. Vulkan is able to be highly parallelized, which fits in well with the desired structure of Milk.
Milk attempts to mimic modern GPU architectures internally, and Vulkan is designed to fulfil this goal (along with DirectX12 and Metal). Additionally, it's supported across most modern platforms and should make porting
of Milk to other platforms much easier.

## Feature Usage

When writing Vulkan code for Milk, most features are free-reign, which a select few exceptions. Most modern GPUs support Vulkan 1.3 at minimum, which contains most if not all features that Milk uses. Ideally, any code
written should fit within this version and the extensions it made core. Additional extensions are typically used in cases of mandatory platform support, for example surfaces. SDL usually requests these features automatically,
and they're supported on most platforms anyway. If SDL somehow fails to get these features, then you're most likely running Milk on something that couldn't handle a game anyway. As Milk grows, some additional higher-level features may also be exposed for end-users to enable at will.
For these features, Vulkan can query for related extension support and, if supported, toggle a flag in the corresponding GPU's Graphics_Device.