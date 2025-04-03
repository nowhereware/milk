# Roadmap

Naturally, Milk Engine is not a completely finished product. There's still several features that are planned to be implemented in both the short-term and long-term.

## Short-Term

### ECS Improvements

The current ECS implementation is primarily implemented as a sparse set, using "Signature"s for storing Entity composition data and storing individual component data in their own individual Storages within an array within the World. While additional optimizations have been made to improve performance in the form of the query caching system, sparse-set ECSes unfortunately still have an inherent limitation in not being terribly cache-friendly. Every time we gather an array of a specific component's data corresponding to a list of entities, we have to grab the entity's index in the array and then the actual data, switching between the two arrays for each data access. For a much larger project with many more entities, this is a design flaw that cannot be easily alleviated within a strictly sparse-set implementation. Therefore, a desired goal is to switch from strictly sparse-set to a hybrid implementation, where components can be selectively registered to either be stored in an archetype or a sparse set. Component data that is read and modified frequently should be stored in an archetype, whereas data that is added and removed frequently should be stored in a sparse set. This makes querying much more cache-friendly as archetype data is stored in its own array per archetype, so there's no need to grab the index of an entity's data first, the data is simply iterated through.

### Asset System Testing

While the current implementation of the asset system should work in theory, major testing has not been completed and like the rest of the engine it most likely needs another pass. Specifically, a current issue is in regards to file loading: files loaded using the provided proc file_load may panic on deletion for an as of yet unknown reason.

### Documentation

Much of Milk's documentation is either lacking or simply doesn't exist. The goal is to add documentation to every struct and most procedures if possible, save for some smaller, simpler procedures that likely don't need an intense amount of documentation. Additionally, there should ideally be more general documentation (and perhaps even tutorials) in the /docs folder.

### Vulkan Renderer

Right now, the main renderer that exists in Milk is an OpenGL-based renderer. While files do exist for a Vulkan-based renderer which are indeed older than the OpenGL-based renderer, this renderer was temporarily put on hold while GL was given more focus in order to get quicker results. The GL-based renderer however is highly based on a Vulkan design (for example, the OpenGL command pool is designed to mimic the functionality of the Vulkan command pool) and ideally will be replaced by an actual Vulkan renderer, with the GL files being removed.

### Performance Pass

For a majority of Milk's development up until the writing of this document, Milk has been written primarily by a single developer. While I try and plan ahead in design and ensure wherever I can that things are running smoothly, I'm not omnipotent and there is most likely areas that need cleaning up or simply don't work like they should. Having more sets of eyes looking over and using Milk Engine will help immensely in locating issues, and if you do please don't hesitate to open an issue on GitHub.

## Long-Term

### Milk Editor

Ideally at some point we'd like to have a full GUI-based editor for Milk. This editor would be used primarily to edit JSON-based scene files that a game written in Milk would load and use at runtime.
