// TODO-2: implement the Forward+ fragment shader

// See naive.fs.wgsl for basic fragment shader setup; this shader should use light clusters instead of looping over all lights

// ------------------------------------
// Shading process:
// ------------------------------------
// Determine which cluster contains the current fragment.
// Retrieve the number of lights that affect the current fragment from the cluster’s data.
// Initialize a variable to accumulate the total light contribution for the fragment.
// For each light in the cluster:
//     Access the light's properties using its index.
//     Calculate the contribution of the light based on its position, the fragment’s position, and the surface normal.
//     Add the calculated contribution to the total light accumulation.
// Multiply the fragment’s diffuse color by the accumulated light contribution.
// Return the final color, ensuring that the alpha component is set appropriately (typically to 1).

@group(${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read> clusterLights: array<u32>;

@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

struct FragmentInput
{
    @builtin(position) fragPos: vec4f,
    @location(0) pos: vec3f,
    @location(1) nor: vec3f,
    @location(2) uv: vec2f
}

@fragment
fn main(in: FragmentInput) -> @location(0) vec4f
{
    let diffuseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    if (diffuseColor.a < 0.5f) {
        discard;
    }
    var clipPos = cameraUniforms.viewProjMat * vec4(in.pos, 1.0);
    clipPos = clipPos / clipPos.w;
    let x: u32 = u32((clipPos.x + 1) / 2 * f32(${clusterCountX}));
    let y: u32 = u32((clipPos.y + 1) / 2 * f32(${clusterCountY}));

    let viewPos = cameraUniforms.viewMat * vec4(in.pos, 1.0);
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
        totalLightContrib = totalLightContrib + calculateLightContrib(light, in.pos, normalize(in.nor));
    }

    var finalColor = totalLightContrib * diffuseColor.rgb;
    return vec4(finalColor, 1);
}
