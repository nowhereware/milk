struct VSOutput {
    float3 color : COLOR;
    float4 sv_position : SV_Position;
};

struct VSInput {
    float2 position;
    float3 color : COLOR;
};

// Uniforms
struct UniformBufferObject {
    float4x4 model;
    float4x4 view;
    float4x4 proj;
}

[vk_binding(0)] ConstantBuffer<UniformBufferObject> Params;

[shader("vertex")]
VSOutput vertex_main(uint id: SV_VertexID, VSInput input : VSInput) {
    VSOutput out = VSOutput(0);

    out.color = input.color;
    out.sv_position = mul(Params.proj * Params.view * Params.model, float4(input.position, 0.0, 1.0));

    return out;
};

[shader("fragment")]
float4 pixel_main(VSOutput vert_in : VSOutput) : SV_Target {
    return float4(vert_in.color, 1.0);
};