// TODO-3: implement the Clustered Deferred fullscreen fragment shader

// Similar to the Forward+ fragment shader, but with vertex information coming from the G-buffer instead.
@group(${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read> clusterLights: array<u32>;

@group(1) @binding(0) var positionTex: texture_2d<f32>;
@group(1) @binding(1) var normalTex: texture_2d<f32>;
@group(1) @binding(2) var albedoTex: texture_2d<f32>;

@fragment
fn main(@builtin(position) fragCoord: vec4f)-> @location(0) vec4f {

    let width = cameraUniforms.width;
    let height = cameraUniforms.height;

    let uv01 = vec2f(fragCoord.x / f32(width), fragCoord.y / f32(height));
    let uvScreen = vec2i(i32(fragCoord.x), i32(fragCoord.y));

    let position = textureLoad(positionTex, uvScreen, 0).xyz;
    let norm = textureLoad(normalTex, uvScreen, 0).xyz;
    let albedo = textureLoad(albedoTex, uvScreen, 0).xyz;

    let x = u32(uv01.x * f32(${clusterCountX}));
    let y = u32((1.0 - uv01.y) * f32(${clusterCountY}));
    
    let viewPos = cameraUniforms.viewMat * vec4(position, 1.0);
    let depth = -viewPos.z;

    let near = cameraUniforms.nearPlane;
    let far = cameraUniforms.farPlane;
    let logRatio = log(far / near);
    let depthClamped = clamp(depth, near, far);
    var z:u32 = u32(floor(log(depthClamped / near) / logRatio * f32(${clusterCountZ})));

    let clusterIdX = clamp(x, 0u, ${clusterCountX} - 1u);
    let clusterIdY = clamp(y, 0u, ${clusterCountY} - 1u);
    let clusterIdZ = clamp(z, 0u, ${clusterCountZ} - 1u);
    let clusterIdx = clusterIdX + 
    clusterIdY * ${clusterCountX}u + clusterIdZ * ${clusterCountX}u * ${clusterCountY}u;

    let clusterOffset = clusterIdx * (${maxLightsPerCluster}u + 1u);
    let numLights = clusterLights[clusterOffset];

    var totalLightContrib = vec3<f32>(0.0, 0.0, 0.0);
    for(var i = 0u; i < numLights; i = i + 1u) {
        let lightIdx = clusterLights[clusterOffset + i + 1u];
        let light = lightSet.lights[lightIdx];
        totalLightContrib = totalLightContrib + calculateLightContrib(light, position, norm);
    }
    var finalColor = totalLightContrib * albedo;
    return vec4(finalColor, 1);
};