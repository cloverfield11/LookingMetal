//! Metal Shading Language (MSL) shader definitions for LookingMetal.
//! When miniquad runs on Apple platforms with AppleGfxApi::Metal,
//! these MSL programs are loaded instead of legacy GLSL.

use macroquad::prelude::ShaderSource;

pub fn is_metal() -> bool {
    #[cfg(target_vendor = "apple")]
    {
        macroquad::miniquad::window::apple_gfx_api() == macroquad::miniquad::conf::AppleGfxApi::Metal
    }
    #[cfg(not(target_vendor = "apple"))]
    {
        false
    }
}

pub fn make_source<'a>(
    vertex_glsl: &'a str,
    fragment_glsl: &'a str,
    msl_program: &'a str,
) -> ShaderSource<'a> {
    if is_metal() {
        ShaderSource::Msl {
            program: msl_program,
        }
    } else {
        ShaderSource::Glsl {
            vertex: vertex_glsl,
            fragment: fragment_glsl,
        }
    }
}

/// Common MSL header and utility functions (fog slabs, dynamic lighting).
pub const MSL_COMMON_HEADER: &str = r#"
#include <metal_stdlib>
using namespace metal;

struct LightDesc {
    packed_float4 FxLight;
    packed_float4 FxColor;
};

static float slab(float p, float d, float lo, float hi, thread float& enter, thread float& leave) {
    if (abs(d) < 0.00001) {
        if (p < lo || p > hi) return 0.0;
        return 1.0;
    }
    float a = (lo - p) / d;
    float b = (hi - p) / d;
    enter = max(enter, min(a, b));
    leave = min(leave, max(a, b));
    return 1.0;
}

static float fogLength(float3 worldPosition, float3 fogEye, float3 lo, float3 hi) {
    float3 d = worldPosition - fogEye;
    float a = 0.0;
    float b = 1.0;
    float valid = slab(fogEye.x, d.x, lo.x, hi.x, a, b) *
                  slab(fogEye.y, d.y, lo.y, hi.y, a, b) *
                  slab(fogEye.z, d.z, lo.z, hi.z, a, b);
    return max(0.0, b - a) * length(d) * valid;
}
"#;

pub const SAVE_SCREEN_MSL: &str = r#"
#include <metal_stdlib>
using namespace metal;

struct __attribute__((packed)) Uniforms {
    float4x4 Projection;
    float4x4 Model;
    packed_float4 _Time;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
    float4 color0   [[attribute(2)]];
    float4 normal   [[attribute(3)]];
};

struct RasterizerData {
    float4 position [[position]];
    float4 color [[user(locn0)]];
    float2 uv [[user(locn1)]];
};

vertex RasterizerData vertexShader(VertexIn v [[stage_in]], constant Uniforms& uniforms [[buffer(0)]]) {
    RasterizerData out;
    out.position = uniforms.Projection * uniforms.Model * float4(v.position, 1.0);
    out.color = v.color0 / 255.0;
    out.uv = v.texcoord;
    return out;
}

fragment float4 fragmentShader(
    RasterizerData in [[stage_in]],
    texture2d<float> Texture [[texture(0)]],
    sampler smp [[sampler(0)]]
) {
    return Texture.sample(smp, in.uv) * in.color;
}
"#;

pub const CAMERA_PORTAL_MSL: &str = r#"
#include <metal_stdlib>
using namespace metal;

struct __attribute__((packed)) Uniforms {
    float4x4 Projection;
    float4x4 Model;
    packed_float4 _Time;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
    float4 color0   [[attribute(2)]];
    float4 normal   [[attribute(3)]];
};

struct RasterizerData {
    float4 position [[position]];
    float4 screenPosition [[user(locn0)]];
};

vertex RasterizerData vertexShader(VertexIn v [[stage_in]], constant Uniforms& uniforms [[buffer(0)]]) {
    RasterizerData out;
    out.position = uniforms.Projection * uniforms.Model * float4(v.position, 1.0);
    out.screenPosition = out.position;
    return out;
}

fragment float4 fragmentShader(
    RasterizerData in [[stage_in]],
    texture2d<float> Texture [[texture(0)]],
    sampler smp [[sampler(0)]]
) {
    float2 uv = in.screenPosition.xy / in.screenPosition.w * 0.5 + 0.5;
    uv.y = 1.0 - uv.y;
    return float4(Texture.sample(smp, uv).rgb, 1.0);
}
"#;

pub const WORLD_MSL: &str = r#"
#include <metal_stdlib>
using namespace metal;

struct LightDesc {
    packed_float4 FxLight;
    packed_float4 FxColor;
};

struct __attribute__((packed)) WorldUniforms {
    float4x4 Projection;
    float4x4 Model;
    packed_float4 _Time;
    packed_float2 AtlasGrid;
    float Fullbright;
    float Lit;
    float ClampUV;
    float Cutout;
    float CutoutReference;
    packed_float4 Gain;
    float FogMode;
    packed_float2 SkySize;
    float SkyFade;
    float FxModel;
    packed_float4 FxAppearance;
    LightDesc Lights[8];
    packed_float3 FogEye;
    packed_float4 DistanceFog;
    packed_float4 LiquidFog;
    packed_float3 FogAMin;
    packed_float3 FogAMax;
    packed_float4 FogA;
    packed_float3 FogBMin;
    packed_float3 FogBMax;
    packed_float4 FogB;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
    float4 color0   [[attribute(2)]];
    float4 normal   [[attribute(3)]];
};

struct RasterizerData {
    float4 position [[position]];
    float2 uv [[user(locn0)]];
    float3 lm [[user(locn1)]];
    float4 color [[user(locn2)]];
    float3 worldPosition [[user(locn3)]];
};

static float slab(float p, float d, float lo, float hi, thread float& enter, thread float& leave) {
    if (abs(d) < 0.00001) {
        if (p < lo || p > hi) return 0.0;
        return 1.0;
    }
    float a = (lo - p) / d;
    float b = (hi - p) / d;
    enter = max(enter, min(a, b));
    leave = min(leave, max(a, b));
    return 1.0;
}

static float fogLength(float3 worldPosition, float3 fogEye, float3 lo, float3 hi) {
    float3 d = worldPosition - fogEye;
    float a = 0.0;
    float b = 1.0;
    float valid = slab(fogEye.x, d.x, lo.x, hi.x, a, b) *
                  slab(fogEye.y, d.y, lo.y, hi.y, a, b) *
                  slab(fogEye.z, d.z, lo.z, hi.z, a, b);
    return max(0.0, b - a) * length(d) * valid;
}

static float3 fogged(float3 rgb, float additive, float3 worldPosition, constant WorldUniforms& u) {
    float3 neutral = additive > 2.5 ? float3(0.5) : float3(1.0);
    float dist = length(worldPosition - float3(u.FogEye));
    if (u.DistanceFog.w > 0.0) {
        float a = clamp((dist - u.DistanceFog.w * 0.35) / (u.DistanceFog.w * 0.65), 0.0, 1.0);
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.DistanceFog.xyz) * (1.0 - additive), a);
    }
    if (u.FogA.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogAMin), float3(u.FogAMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogA.xyz) * (1.0 - additive), clamp(l / u.FogA.w, 0.0, 1.0));
    }
    if (u.FogB.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogBMin), float3(u.FogBMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogB.xyz) * (1.0 - additive), clamp(l / u.FogB.w, 0.0, 1.0));
    }
    if (u.LiquidFog.w > 0.0) {
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.LiquidFog.xyz) * (1.0 - additive), clamp(0.12 + dist / u.LiquidFog.w, 0.0, 0.96));
    }
    return rgb;
}

static float3 dynamicLight(float3 position, constant WorldUniforms& u) {
    float3 light = float3(0.0);
    for (int i = 0; i < 8; i++) {
        if (u.Lights[i].FxColor.w > 0.5) {
            float dist = distance(position, float3(u.Lights[i].FxLight.xyz));
            float radius = max(u.Lights[i].FxLight.w, 0.001);
            light += float3(u.Lights[i].FxColor.xyz) * max(0.0, 1.0 - dist / radius);
        }
    }
    return light;
}

vertex RasterizerData vertexShader(VertexIn v [[stage_in]], constant WorldUniforms& uniforms [[buffer(0)]]) {
    RasterizerData out;
    out.worldPosition = (uniforms.Model * float4(v.position, 1.0)).xyz;
    out.position = uniforms.Projection * float4(out.worldPosition, 1.0);
    out.uv = v.texcoord;
    out.lm = v.normal.xyz;
    out.color = v.color0 / 255.0;
    return out;
}

fragment float4 fragmentShader(
    RasterizerData in [[stage_in]],
    constant WorldUniforms& u [[buffer(0)]],
    texture2d<float> Texture [[texture(0)]],
    sampler smp [[sampler(0)]],
    texture2d<float> LightAtlas [[texture(2)]],
    sampler atlasSmp [[sampler(2)]],
    texture2d<float> SkyBackdrop [[texture(3)]],
    sampler skySmp [[sampler(3)]]
) {
    float2 fragCoord = in.position.xy;
    if (u.FxAppearance.x > 0.0 && (fmod(floor(fragCoord.x) * 3.0 + floor(fragCoord.y) * 5.0, 16.0) + 0.5) / 16.0 < u.FxAppearance.x) {
        discard_fragment();
    }
    if (u.FxAppearance.y > 0.5 && fmod(floor(fragCoord.x) + floor(fragCoord.y), 4.0) > 0.5) {
        discard_fragment();
    }
    float2 coords = mix(in.uv, clamp(in.uv, float2(0.001), float2(0.999)), u.ClampUV);
    float4 diffuse = Texture.sample(smp, coords);
    float alpha = diffuse.a * u.Gain.w * in.color.a;

    if ((u.Cutout > 0.5 && u.Cutout < 1.5 && alpha <= 0.0) ||
        (u.Cutout > 1.5 && u.Cutout < 2.5 && alpha < 0.5) ||
        (u.Cutout > 2.5 && u.Cutout < 3.5 && alpha >= 0.5) ||
        (u.Cutout > 3.5 && u.Cutout < 4.5 && alpha < 0.35)) {
        discard_fragment();
    }
    if ((u.Cutout > 4.5 && u.Cutout < 5.5 && alpha < u.CutoutReference) ||
        (u.Cutout > 5.5 && u.Cutout < 6.5 && alpha <= u.CutoutReference) ||
        (u.Cutout > 6.5 && u.Cutout < 7.5 && alpha >= u.CutoutReference) ||
        (u.Cutout > 7.5 && alpha > u.CutoutReference)) {
        discard_fragment();
    }

    float3 lighting = max(in.color.rgb, float3(0.18));
    if (in.lm.z > 0.5 && u.FxModel < 0.5) {
        float index = floor(in.lm.z - 1.0 + 0.1);
        float2 tile = float2(fmod(index, u.AtlasGrid.x), floor(index / u.AtlasGrid.x));
        float2 sampleUV = (tile + clamp(in.lm.xy, float2(0.5 / 128.0), float2(127.5 / 128.0))) / float2(u.AtlasGrid);
        lighting = min(float3(1.0), LightAtlas.sample(atlasSmp, sampleUV).rgb * 2.0);
    }
    float3 rgb = diffuse.rgb * mix(float3(1.0), lighting, u.Lit * (1.0 - u.Fullbright)) * float3(u.Gain.xyz);
    if (u.FxModel > 0.5 && u.Lit < 0.5) {
        rgb *= in.color.rgb;
    }
    rgb += diffuse.rgb * dynamicLight(in.worldPosition, u) * float3(u.Gain.xyz);
    if (u.FxAppearance.z > 1.5) {
        rgb = mix(rgb, rgb * float3(0.65, 1.15, 0.7), 0.6);
    } else if (u.FxAppearance.z > 0.5) {
        rgb = mix(rgb, rgb * float3(1.3, 0.55, 0.4), 0.6);
    }
    if (u.FxAppearance.w > 0.0) {
        rgb = mix(rgb, float3(1.0), u.FxAppearance.w);
    } else if (u.FxAppearance.w < 0.0) {
        rgb = mix(rgb, float3(0.5), -u.FxAppearance.w);
    }

    if (u.FogMode > 3.5) {
        float visible = fogged(float3(1.0), 1.0, in.worldPosition, u).r;
        rgb = mix(float3(1.0), rgb, visible);
        alpha *= visible;
    } else if (u.FogMode >= 0.0) {
        rgb = fogged(rgb, u.FogMode, in.worldPosition, u);
    }

    if (u.SkyFade > 0.5 && u.FogMode >= 0.0 && u.FogMode < 0.5) {
        float a = u.FogA.w > 0.0 ? clamp(fogLength(in.worldPosition, float3(u.FogEye), float3(u.FogAMin), float3(u.FogAMax)) / u.FogA.w, 0.0, 1.0) : 0.0;
        float b = u.FogB.w > 0.0 ? clamp(fogLength(in.worldPosition, float3(u.FogEye), float3(u.FogBMin), float3(u.FogBMax)) / u.FogB.w, 0.0, 1.0) : 0.0;
        rgb += SkyBackdrop.sample(skySmp, fragCoord / float2(u.SkySize)).rgb * (1.0 - (1.0 - a) * (1.0 - b));
    }

    return float4(rgb, alpha);
}
"#;

pub const CHARACTER_MSL: &str = r#"
#include <metal_stdlib>
using namespace metal;

struct __attribute__((packed)) CharacterUniforms {
    float4x4 Projection;
    float4x4 Model;
    packed_float4 _Time;
    packed_float3 FogEye;
    packed_float4 DistanceFog;
    packed_float4 LiquidFog;
    packed_float3 FogAMin;
    packed_float3 FogAMax;
    packed_float4 FogA;
    packed_float3 FogBMin;
    packed_float3 FogBMax;
    packed_float4 FogB;
    float Dissolve;
    float Ghost;
    float Power;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
    float4 color0   [[attribute(2)]];
    float4 normal   [[attribute(3)]];
};

struct RasterizerData {
    float4 position [[position]];
    float2 uv [[user(locn0)]];
    float4 color [[user(locn1)]];
    float3 worldPosition [[user(locn2)]];
};

static float slab(float p, float d, float lo, float hi, thread float& enter, thread float& leave) {
    if (abs(d) < 0.00001) {
        if (p < lo || p > hi) return 0.0;
        return 1.0;
    }
    float a = (lo - p) / d;
    float b = (hi - p) / d;
    enter = max(enter, min(a, b));
    leave = min(leave, max(a, b));
    return 1.0;
}

static float fogLength(float3 worldPosition, float3 fogEye, float3 lo, float3 hi) {
    float3 d = worldPosition - fogEye;
    float a = 0.0;
    float b = 1.0;
    float valid = slab(fogEye.x, d.x, lo.x, hi.x, a, b) *
                  slab(fogEye.y, d.y, lo.y, hi.y, a, b) *
                  slab(fogEye.z, d.z, lo.z, hi.z, a, b);
    return max(0.0, b - a) * length(d) * valid;
}

static float3 fogged(float3 rgb, float additive, float3 worldPosition, constant CharacterUniforms& u) {
    float3 neutral = additive > 2.5 ? float3(0.5) : float3(1.0);
    float dist = length(worldPosition - float3(u.FogEye));
    if (u.DistanceFog.w > 0.0) {
        float a = clamp((dist - u.DistanceFog.w * 0.35) / (u.DistanceFog.w * 0.65), 0.0, 1.0);
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.DistanceFog.xyz) * (1.0 - additive), a);
    }
    if (u.FogA.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogAMin), float3(u.FogAMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogA.xyz) * (1.0 - additive), clamp(l / u.FogA.w, 0.0, 1.0));
    }
    if (u.FogB.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogBMin), float3(u.FogBMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogB.xyz) * (1.0 - additive), clamp(l / u.FogB.w, 0.0, 1.0));
    }
    if (u.LiquidFog.w > 0.0) {
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.LiquidFog.xyz) * (1.0 - additive), clamp(0.12 + dist / u.LiquidFog.w, 0.0, 0.96));
    }
    return rgb;
}

vertex RasterizerData vertexShader(VertexIn v [[stage_in]], constant CharacterUniforms& uniforms [[buffer(0)]]) {
    RasterizerData out;
    out.worldPosition = (uniforms.Model * float4(v.position, 1.0)).xyz;
    out.position = uniforms.Projection * float4(out.worldPosition, 1.0);
    out.uv = v.texcoord;
    out.color = v.color0 / 255.0;
    return out;
}

fragment float4 fragmentShader(
    RasterizerData in [[stage_in]],
    constant CharacterUniforms& u [[buffer(0)]],
    texture2d<float> Texture [[texture(0)]],
    sampler smp [[sampler(0)]]
) {
    float2 fragCoord = in.position.xy;
    if (u.Dissolve > 0.0 && (fmod(floor(fragCoord.x) * 3.0 + floor(fragCoord.y) * 5.0, 16.0) + 0.5) / 16.0 < u.Dissolve) {
        discard_fragment();
    }
    float4 t = Texture.sample(smp, in.uv);
    if (t.a < 0.35) {
        discard_fragment();
    }
    if (u.Ghost > 0.5 && fmod(floor(fragCoord.x) + floor(fragCoord.y), 4.0) > 0.5) {
        discard_fragment();
    }
    float3 c = t.rgb * in.color.rgb;
    if (u.Power > 1.5) {
        c = mix(c, c * float3(0.65, 1.15, 0.7), 0.6);
    } else if (u.Power > 0.5) {
        c = mix(c, c * float3(1.3, 0.55, 0.4), 0.6);
    }
    return float4(fogged(c, 0.0, in.worldPosition, u), 1.0);
}
"#;

pub const PARTICLE_MSL: &str = r#"
#include <metal_stdlib>
using namespace metal;

struct __attribute__((packed)) ParticleUniforms {
    float4x4 Projection;
    float4x4 Model;
    packed_float4 _Time;
    packed_float3 FogEye;
    packed_float4 DistanceFog;
    packed_float4 LiquidFog;
    packed_float3 FogAMin;
    packed_float3 FogAMax;
    packed_float4 FogA;
    packed_float3 FogBMin;
    packed_float3 FogBMax;
    packed_float4 FogB;
    float Additive;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
    float4 color0   [[attribute(2)]];
    float4 normal   [[attribute(3)]];
};

struct RasterizerData {
    float4 position [[position]];
    float2 uv [[user(locn0)]];
    float4 color [[user(locn1)]];
    float3 worldPosition [[user(locn2)]];
};

static float slab(float p, float d, float lo, float hi, thread float& enter, thread float& leave) {
    if (abs(d) < 0.00001) {
        if (p < lo || p > hi) return 0.0;
        return 1.0;
    }
    float a = (lo - p) / d;
    float b = (hi - p) / d;
    enter = max(enter, min(a, b));
    leave = min(leave, max(a, b));
    return 1.0;
}

static float fogLength(float3 worldPosition, float3 fogEye, float3 lo, float3 hi) {
    float3 d = worldPosition - fogEye;
    float a = 0.0;
    float b = 1.0;
    float valid = slab(fogEye.x, d.x, lo.x, hi.x, a, b) *
                  slab(fogEye.y, d.y, lo.y, hi.y, a, b) *
                  slab(fogEye.z, d.z, lo.z, hi.z, a, b);
    return max(0.0, b - a) * length(d) * valid;
}

static float3 fogged(float3 rgb, float additive, float3 worldPosition, constant ParticleUniforms& u) {
    float3 neutral = additive > 2.5 ? float3(0.5) : float3(1.0);
    float dist = length(worldPosition - float3(u.FogEye));
    if (u.DistanceFog.w > 0.0) {
        float a = clamp((dist - u.DistanceFog.w * 0.35) / (u.DistanceFog.w * 0.65), 0.0, 1.0);
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.DistanceFog.xyz) * (1.0 - additive), a);
    }
    if (u.FogA.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogAMin), float3(u.FogAMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogA.xyz) * (1.0 - additive), clamp(l / u.FogA.w, 0.0, 1.0));
    }
    if (u.FogB.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogBMin), float3(u.FogBMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogB.xyz) * (1.0 - additive), clamp(l / u.FogB.w, 0.0, 1.0));
    }
    if (u.LiquidFog.w > 0.0) {
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.LiquidFog.xyz) * (1.0 - additive), clamp(0.12 + dist / u.LiquidFog.w, 0.0, 0.96));
    }
    return rgb;
}

vertex RasterizerData vertexShader(VertexIn v [[stage_in]], constant ParticleUniforms& uniforms [[buffer(0)]]) {
    RasterizerData out;
    out.worldPosition = (uniforms.Model * float4(v.position, 1.0)).xyz;
    out.position = uniforms.Projection * float4(out.worldPosition, 1.0);
    out.uv = v.texcoord;
    out.color = v.color0 / 255.0;
    return out;
}

fragment float4 fragmentShader(
    RasterizerData in [[stage_in]],
    constant ParticleUniforms& u [[buffer(0)]],
    texture2d<float> Texture [[texture(0)]],
    sampler smp [[sampler(0)]]
) {
    float4 t = Texture.sample(smp, in.uv) * in.color;
    if (u.Additive > 0.5) {
        t.rgb *= t.a;
    }
    return float4(fogged(t.rgb, u.Additive, in.worldPosition, u), t.a);
}
"#;

pub const WEAPON_EFFECT_MSL: &str = r#"
#include <metal_stdlib>
using namespace metal;

struct __attribute__((packed)) WeaponUniforms {
    float4x4 Projection;
    float4x4 Model;
    packed_float4 _Time;
    packed_float3 FogEye;
    packed_float4 DistanceFog;
    packed_float4 LiquidFog;
    packed_float3 FogAMin;
    packed_float3 FogAMax;
    packed_float4 FogA;
    packed_float3 FogBMin;
    packed_float3 FogBMax;
    packed_float4 FogB;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
    float4 color0   [[attribute(2)]];
    float4 normal   [[attribute(3)]];
};

struct RasterizerData {
    float4 position [[position]];
    float2 uv [[user(locn0)]];
    float4 color [[user(locn1)]];
    float3 worldPosition [[user(locn2)]];
};

static float slab(float p, float d, float lo, float hi, thread float& enter, thread float& leave) {
    if (abs(d) < 0.00001) {
        if (p < lo || p > hi) return 0.0;
        return 1.0;
    }
    float a = (lo - p) / d;
    float b = (hi - p) / d;
    enter = max(enter, min(a, b));
    leave = min(leave, max(a, b));
    return 1.0;
}

static float fogLength(float3 worldPosition, float3 fogEye, float3 lo, float3 hi) {
    float3 d = worldPosition - fogEye;
    float a = 0.0;
    float b = 1.0;
    float valid = slab(fogEye.x, d.x, lo.x, hi.x, a, b) *
                  slab(fogEye.y, d.y, lo.y, hi.y, a, b) *
                  slab(fogEye.z, d.z, lo.z, hi.z, a, b);
    return max(0.0, b - a) * length(d) * valid;
}

static float3 fogged(float3 rgb, float additive, float3 worldPosition, constant WeaponUniforms& u) {
    float3 neutral = additive > 2.5 ? float3(0.5) : float3(1.0);
    float dist = length(worldPosition - float3(u.FogEye));
    if (u.DistanceFog.w > 0.0) {
        float a = clamp((dist - u.DistanceFog.w * 0.35) / (u.DistanceFog.w * 0.65), 0.0, 1.0);
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.DistanceFog.xyz) * (1.0 - additive), a);
    }
    if (u.FogA.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogAMin), float3(u.FogAMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogA.xyz) * (1.0 - additive), clamp(l / u.FogA.w, 0.0, 1.0));
    }
    if (u.FogB.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogBMin), float3(u.FogBMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogB.xyz) * (1.0 - additive), clamp(l / u.FogB.w, 0.0, 1.0));
    }
    if (u.LiquidFog.w > 0.0) {
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.LiquidFog.xyz) * (1.0 - additive), clamp(0.12 + dist / u.LiquidFog.w, 0.0, 0.96));
    }
    return rgb;
}

vertex RasterizerData vertexShader(VertexIn v [[stage_in]], constant WeaponUniforms& uniforms [[buffer(0)]]) {
    RasterizerData out;
    out.worldPosition = (uniforms.Model * float4(v.position, 1.0)).xyz;
    out.position = uniforms.Projection * float4(out.worldPosition, 1.0);
    out.uv = v.texcoord;
    out.color = v.color0 / 255.0;
    return out;
}

fragment float4 fragmentShader(
    RasterizerData in [[stage_in]],
    constant WeaponUniforms& u [[buffer(0)]],
    texture2d<float> Texture [[texture(0)]],
    sampler smp [[sampler(0)]]
) {
    float4 c = in.color * Texture.sample(smp, in.uv);
    return float4(fogged(c.rgb, 1.0, in.worldPosition, u), c.a);
}
"#;

pub const LOOT_MSL: &str = r#"
#include <metal_stdlib>
using namespace metal;

struct __attribute__((packed)) LootUniforms {
    float4x4 Projection;
    float4x4 Model;
    packed_float4 _Time;
    packed_float3 FogEye;
    packed_float4 DistanceFog;
    packed_float4 LiquidFog;
    packed_float3 FogAMin;
    packed_float3 FogAMax;
    packed_float4 FogA;
    packed_float3 FogBMin;
    packed_float3 FogBMax;
    packed_float4 FogB;
    float FogMode;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
    float4 color0   [[attribute(2)]];
    float4 normal   [[attribute(3)]];
};

struct RasterizerData {
    float4 position [[position]];
    float2 uv [[user(locn0)]];
    float4 color [[user(locn1)]];
    float3 worldPosition [[user(locn2)]];
};

static float slab(float p, float d, float lo, float hi, thread float& enter, thread float& leave) {
    if (abs(d) < 0.00001) {
        if (p < lo || p > hi) return 0.0;
        return 1.0;
    }
    float a = (lo - p) / d;
    float b = (hi - p) / d;
    enter = max(enter, min(a, b));
    leave = min(leave, max(a, b));
    return 1.0;
}

static float fogLength(float3 worldPosition, float3 fogEye, float3 lo, float3 hi) {
    float3 d = worldPosition - fogEye;
    float a = 0.0;
    float b = 1.0;
    float valid = slab(fogEye.x, d.x, lo.x, hi.x, a, b) *
                  slab(fogEye.y, d.y, lo.y, hi.y, a, b) *
                  slab(fogEye.z, d.z, lo.z, hi.z, a, b);
    return max(0.0, b - a) * length(d) * valid;
}

static float3 fogged(float3 rgb, float additive, float3 worldPosition, constant LootUniforms& u) {
    float3 neutral = additive > 2.5 ? float3(0.5) : float3(1.0);
    float dist = length(worldPosition - float3(u.FogEye));
    if (u.DistanceFog.w > 0.0) {
        float a = clamp((dist - u.DistanceFog.w * 0.35) / (u.DistanceFog.w * 0.65), 0.0, 1.0);
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.DistanceFog.xyz) * (1.0 - additive), a);
    }
    if (u.FogA.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogAMin), float3(u.FogAMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogA.xyz) * (1.0 - additive), clamp(l / u.FogA.w, 0.0, 1.0));
    }
    if (u.FogB.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogBMin), float3(u.FogBMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogB.xyz) * (1.0 - additive), clamp(l / u.FogB.w, 0.0, 1.0));
    }
    if (u.LiquidFog.w > 0.0) {
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.LiquidFog.xyz) * (1.0 - additive), clamp(0.12 + dist / u.LiquidFog.w, 0.0, 0.96));
    }
    return rgb;
}

vertex RasterizerData vertexShader(VertexIn v [[stage_in]], constant LootUniforms& uniforms [[buffer(0)]]) {
    RasterizerData out;
    out.worldPosition = (uniforms.Model * float4(v.position, 1.0)).xyz;
    out.position = uniforms.Projection * float4(out.worldPosition, 1.0);
    out.uv = v.texcoord;
    out.color = v.color0 / 255.0;
    return out;
}

fragment float4 fragmentShader(
    RasterizerData in [[stage_in]],
    constant LootUniforms& u [[buffer(0)]],
    texture2d<float> Texture [[texture(0)]],
    sampler smp [[sampler(0)]]
) {
    float3 texRgb = Texture.sample(smp, fract(in.uv)).rgb;
    return float4(fogged(texRgb, u.FogMode, in.worldPosition, u), 1.0);
}
"#;

pub const DEPTH_CHECK_MSL: &str = r#"
#include <metal_stdlib>
using namespace metal;

struct __attribute__((packed)) DepthCheckUniforms {
    float4x4 Projection;
    float4x4 Model;
    packed_float4 _Time;
    packed_float3 FogEye;
    packed_float4 DistanceFog;
    packed_float4 LiquidFog;
    packed_float3 FogAMin;
    packed_float3 FogAMax;
    packed_float4 FogA;
    packed_float3 FogBMin;
    packed_float3 FogBMax;
    packed_float4 FogB;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
    float4 color0   [[attribute(2)]];
    float4 normal   [[attribute(3)]];
};

struct RasterizerData {
    float4 position [[position]];
    float4 color [[user(locn0)]];
    float3 worldPosition [[user(locn1)]];
};

static float slab(float p, float d, float lo, float hi, thread float& enter, thread float& leave) {
    if (abs(d) < 0.00001) {
        if (p < lo || p > hi) return 0.0;
        return 1.0;
    }
    float a = (lo - p) / d;
    float b = (hi - p) / d;
    enter = max(enter, min(a, b));
    leave = min(leave, max(a, b));
    return 1.0;
}

static float fogLength(float3 worldPosition, float3 fogEye, float3 lo, float3 hi) {
    float3 d = worldPosition - fogEye;
    float a = 0.0;
    float b = 1.0;
    float valid = slab(fogEye.x, d.x, lo.x, hi.x, a, b) *
                  slab(fogEye.y, d.y, lo.y, hi.y, a, b) *
                  slab(fogEye.z, d.z, lo.z, hi.z, a, b);
    return max(0.0, b - a) * length(d) * valid;
}

static float3 fogged(float3 rgb, float additive, float3 worldPosition, constant DepthCheckUniforms& u) {
    float3 neutral = additive > 2.5 ? float3(0.5) : float3(1.0);
    float dist = length(worldPosition - float3(u.FogEye));
    if (u.DistanceFog.w > 0.0) {
        float a = clamp((dist - u.DistanceFog.w * 0.35) / (u.DistanceFog.w * 0.65), 0.0, 1.0);
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.DistanceFog.xyz) * (1.0 - additive), a);
    }
    if (u.FogA.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogAMin), float3(u.FogAMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogA.xyz) * (1.0 - additive), clamp(l / u.FogA.w, 0.0, 1.0));
    }
    if (u.FogB.w > 0.0) {
        float l = fogLength(worldPosition, float3(u.FogEye), float3(u.FogBMin), float3(u.FogBMax));
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.FogB.xyz) * (1.0 - additive), clamp(l / u.FogB.w, 0.0, 1.0));
    }
    if (u.LiquidFog.w > 0.0) {
        rgb = mix(rgb, additive > 1.5 ? neutral : float3(u.LiquidFog.xyz) * (1.0 - additive), clamp(0.12 + dist / u.LiquidFog.w, 0.0, 0.96));
    }
    return rgb;
}

vertex RasterizerData vertexShader(VertexIn v [[stage_in]], constant DepthCheckUniforms& uniforms [[buffer(0)]]) {
    RasterizerData out;
    out.worldPosition = (uniforms.Model * float4(v.position, 1.0)).xyz;
    out.position = uniforms.Projection * float4(out.worldPosition, 1.0);
    out.color = v.color0 / 255.0;
    return out;
}

fragment float4 fragmentShader(
    RasterizerData in [[stage_in]],
    constant DepthCheckUniforms& u [[buffer(0)]]
) {
    return float4(fogged(in.color.rgb, 0.0, in.worldPosition, u), in.color.a);
}
"#;
