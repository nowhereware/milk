package milk

import pt "platform"

// # Texture Asset
// A loaded texture, stored within the renderer's internal data buffers
Texture_Asset :: struct {
    internal: pt.Texture_Internal,
    commands: pt.Texture_Commands,
}

texture_asset_load :: proc(server: ^Asset_Server, path: string) {
    
}