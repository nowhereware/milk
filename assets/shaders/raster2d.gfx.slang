struct Vertex {
    float3 position;
    float2 uv;
    float3 normal;
};

[gl_binding(0)] ConstantBuffer<Vertex[]> SSBO;

// Uniforms
struct UniformBufferObject {
    float4x4 model;
    float4x4 view;
    float4x4 proj;
}

[gl_binding(1)] ConstantBuffer<UniformBufferObject> Params;

struct VSOutput {
    float3 color : COLOR;
    float4 sv_position : SV_Position;
    float3 normal;
};

float3 get_position(int index) {
    return SSBO[index].position;
}

float2 get_uv(int index) {
    return SSBO[index].uv;
}

float3 get_normal(int index) {
    return SSBO[index].normal;
}

[shader("vertex")]
VSOutput vertex_main(uint id: SV_VertexID) {
    VSOutput out = VSOutput(0);

    out.color = get_normal(id);
    out.sv_position = mul(Params.proj * Params.view * Params.model, float4(get_position(id), 1.0));
    out.normal = get_normal(id);

    return out;
};

[shader("fragment")]
float4 pixel_main(VSOutput vert_in : VSOutput) : SV_Target {
    return float4(vert_in.color, 1.0);
};