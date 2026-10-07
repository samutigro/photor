#include <metal_stdlib>
using namespace metal;
struct PhotoVertex { float2 position; float2 uv; };
struct RasterVertex { float4 position [[position]]; float2 uv; };
vertex RasterVertex photoVertex(uint id [[vertex_id]], constant PhotoVertex *vertices [[buffer(0)]]) {
    RasterVertex out;
    out.position = float4(vertices[id].position, 0.0, 1.0);
    out.uv = vertices[id].uv;
    return out;
}
fragment float4 photoFragment(RasterVertex in [[stage_in]], texture2d<float> photo [[texture(0)]]) {
    constexpr sampler photoSampler(filter::linear, address::clamp_to_edge);
    return float4(photo.sample(photoSampler, in.uv).rgb, 1.0);
}
