# Roadmap

Naturally, Milk Engine is not a completely finished product. There's still several features that are planned to be implemented in both the short-term and long-term.

## Short-Term

### Documentation

Much of Milk's documentation is either lacking or simply doesn't exist. The goal is to add documentation to every struct and most procedures if possible, save for some smaller, simpler procedures that likely don't need an intense amount of documentation. Additionally, there should ideally be more general documentation (and perhaps even tutorials) in the /docs folder.

### Vulkan Renderer

Right now, the main renderer that exists in Milk is an OpenGL-based renderer. While files do exist for a Vulkan-based renderer which are indeed older than the OpenGL-based renderer, this renderer was temporarily put on hold while GL was given more focus in order to get quicker results. The GL-based renderer however is highly based on a Vulkan design (for example, the OpenGL command pool is designed to mimic the functionality of the Vulkan command pool) and ideally will be replaced by an actual Vulkan renderer, with the GL files being removed.

### Performance Pass

For a majority of Milk's development up until the writing of this document, Milk has been written primarily by a single developer. While I try and plan ahead in design and ensure wherever I can that things are running smoothly, I'm not omnipotent and there is most likely areas that need cleaning up or simply don't work like they should. Having more sets of eyes looking over and using Milk Engine will help immensely in locating issues, and if you do please don't hesitate to open an issue on GitHub.

## Long-Term

### Milk Editor

Ideally at some point we'd like to have a full GUI-based editor for Milk. This editor would be used primarily to edit JSON-based scene files that a game written in Milk would load and use at runtime.