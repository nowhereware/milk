# Milk Engine
A general-purpose game engine written entirely in Odin.

## Notice
Milk is currently in a *very* pre-alpha state. While most of the described functionality below is available in a form, it's not widely tested and may have breaking bugs depending on platform.
Symbols may regularly change name, location, or functionality, so keep an eye on what runs and keep Odin happy.

The areas that need the most work as of writing are the modules, which are not as feature-complete as desired. Additionally, most of the core milk/ folder could probably do with another
pass on organization. However, the engine is still usable for the most part and most of the core organization has been set, although contributions are welcome!

## Design
Milk is designed to be endlessly upgradable. All modules within Milk (located in the /mod folder) can be enabled or disabled at will, and swapped out when desired for your own needs.
The core of the engine is built off of SDL3, a custom multi-backend renderer (currently just Vulkan), and a complete sparse-set ECS implementation. The engine also includes a complete
asset management system along with a scene system for organization.

## Usage
To get started, clone (or submodule) Milk into the working directory of your project. All the core functionality you'll need to get started is located within the /milk subfolder,
however once you have your Context and a Scene setup you can load modules from the /mod subfolders to get functionality such as rendering and physics running. A simple `main.odin`
using Milk looks something like this:

```odin
package example

import "milk/milk"

// Custom scene data can be defined within these procedures, use scene_load to load assets, modules, and register systems for the ECS to run
scene_load :: proc(scene: ^Scene) {}
scene_unload :: proc(scene: ^Scene) {}

main :: proc() {
    // Creates a new Context_Config filled with default values
    conf := milk.context_config_new()

    // Sets the title of the SDL window as well as the project itself
    conf.title = "Welcome to Milk!"

    // Creates, but doesn't start, the context given the Context_Config
    ctx := milk.context_new(&conf)

    // Creates a new scene given a pair of load and unload procedures
    scene := milk.scene_new(&ctx, scene_load, scene_unload)
    // Runs the scene's load procedure on itself
    scene.scene_load(&scene)

    // Sets the loaded scene to be the scene run after the Context starts
    milk.context_set_startup_scene(&ctx, scene)

    // Starts the context's run loop
    milk.context_run(&ctx)
}
```