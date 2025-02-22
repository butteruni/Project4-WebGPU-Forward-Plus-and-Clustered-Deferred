// TODO-2: implement the light clustering compute shader

// ------------------------------------
// Calculating cluster bounds:
// ------------------------------------
// For each cluster (X, Y, Z):
//     - Calculate the screen-space bounds for this cluster in 2D (XY).
//     - Calculate the depth bounds for this cluster in Z (near and far planes).
//     - Convert these screen and depth bounds into view-space coordinates.
//     - Store the computed bounding box (AABB) for the cluster.

// write similar to move_lights.cs.wgsl
@group(${bindGroup_scene}) @binding(0) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(1) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_scene}) @binding(2) var<storage, read_write> clusterLights: array<u32>;
const clusterCountX = ${clusterCountX};
const clusterCountY = ${clusterCountY};
const clusterCountZ = ${clusterCountZ};

const numClusters = clusterCountX * clusterCountY * clusterCountZ;
const maxLightsPerCluster = ${maxLightsPerCluster};


@compute
@workgroup_size(4, 4, 4)
fn main(@builtin(global_invocation_id) global_id: vec3u) {
    if(global_id.x >= clusterCountX || global_id.y >= clusterCountY || global_id.z >= clusterCountZ) {
        return;
    }

    let clusterIdx = global_id.x + global_id.y * clusterCountX + global_id.z * clusterCountX * clusterCountY;
    let clusterOffset = clusterIdx * (maxLightsPerCluster + 1u);

    let screenPosX = 2.0 / f32(clusterCountX);
    let screenPosY = 2.0 / f32(clusterCountY);

    let xMin = -1.0 + f32(global_id.x) * screenPosX;
    let xMax = -1.0 + f32(global_id.x + 1u) * screenPosX;
    let yMin = -1.0 + f32(global_id.y) * screenPosY;
    let yMax = -1.0 + f32(global_id.y + 1u) * screenPosY;
    let ndcMin = vec2<f32>(xMin, yMin);
    let ndcMax = vec2<f32>(xMax, yMax);

    let near = cameraUniforms.nearPlane;
    let far = cameraUniforms.farPlane;
    let logRatio = log(far / near);
    let minZ = near * exp2(f32(global_id.z) / f32(clusterCountZ) * logRatio);
    let maxZ = near * exp2(f32(global_id.z + 1u) / f32(clusterCountZ) * logRatio);

    let projMat = cameraUniforms.viewProjMat;
    let minZNDC = ((projMat[2][2] * minZ) + projMat[3][2]) / ((projMat[2][3] * minZ) + projMat[3][3]);
    let maxZNDC = ((projMat[2][2] * maxZ) + projMat[3][2]) / ((projMat[2][3] * maxZ) + projMat[3][3]);

    var frustumCorners = array<vec3f, 8>();
    let invProjMat = cameraUniforms.invProjMat;

    var ndcPos = array<vec4f, 8> (
        vec4<f32>(ndcMin.x, ndcMin.y, minZNDC, 1.0),
        vec4<f32>(ndcMax.x, ndcMin.y, minZNDC, 1.0),
        vec4<f32>(ndcMin.x, ndcMax.y, minZNDC, 1.0),
        vec4<f32>(ndcMax.x, ndcMax.y, minZNDC, 1.0),
        vec4<f32>(ndcMin.x, ndcMin.y, maxZNDC, 1.0),
        vec4<f32>(ndcMax.x, ndcMin.y, maxZNDC, 1.0),
        vec4<f32>(ndcMin.x, ndcMax.y, maxZNDC, 1.0),
        vec4<f32>(ndcMax.x, ndcMax.y, maxZNDC, 1.0),
    );

    for(var i = 0u; i < 8u; i = i + 1u) {
        var corner = ndcPos[i];
        var viewPos = invProjMat * corner;
        viewPos = viewPos / viewPos.w;
        frustumCorners[i] = viewPos.xyz;
    }

    var clusterMin = frustumCorners[0];
    var clusterMax = frustumCorners[0];
    for(var i = 1u; i < 8u; i = i + 1u) {
        clusterMin = min(clusterMin, frustumCorners[i]);
        clusterMax = max(clusterMax, frustumCorners[i]);
    }

    clusterLights[clusterIdx] = 0u;
    var lightCnt = 0u;
    let radius:f32 = ${lightRadius};
    for(var lightIdx = 0u; lightIdx < lightSet.numLights; lightIdx = lightIdx + 1u) {
        let light = lightSet.lights[lightIdx];
        let lightPos = (cameraUniforms.viewMat * vec4<f32>(light.pos, 1.0)).xyz;
        let sphereMin = lightPos - vec3f(radius);
        let sphereMax = lightPos + vec3f(radius);

        let intersectMin = max(clusterMin, sphereMin);
        let intersectMax = min(clusterMax, sphereMax);

        let overlap = all(intersectMin <= intersectMax);
        if(overlap) {
            var numlights = clusterLights[clusterOffset];
            if(numlights < maxLightsPerCluster) {
                clusterLights[clusterOffset + 1u + numlights] = lightIdx;
                lightCnt = lightCnt + 1u;
                clusterLights[clusterOffset] = lightCnt;
            }else {
                break;
            }
        }
    }

}