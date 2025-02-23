import * as renderer from '../renderer';
import * as shaders from '../shaders/shaders';
import { Scene } from '../stage/scene';
import { Stage } from '../stage/stage';

export class ClusteredDeferredRenderer extends renderer.Renderer {
    // TODO-3: add layouts, pipelines, textures, etc. needed for Forward+ here
    // you may need extra uniforms such as the camera view matrix and the canvas resolution
    sceneUniformsBindGroupLayout: GPUBindGroupLayout;
    sceneUniformsBindGroup: GPUBindGroup;

    depthTexture: GPUTexture;
    depthTextureView: GPUTextureView;

    gBufferTextures: { position: GPUTexture, normal: GPUTexture, albedo: GPUTexture};
    gBufferTextureViews: { position: GPUTextureView, normal: GPUTextureView, albedo: GPUTextureView};
    gBufferPipeline: GPURenderPipeline;

    fullscreenPipeline: GPURenderPipeline;
    gBufferTexturesBindGroupLayout: GPUBindGroupLayout;
    gBufferTexturesBindGroup: GPUBindGroup;

    constructor(stage: Stage) {
        super(stage);

        // TODO-3: initialize layouts, pipelines, textures, etc. needed for Forward+ here
        // you'll need two pipelines: one for the G-buffer pass and one for the fullscreen pass

        this.sceneUniformsBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "scene uniforms bind group layout",
            entries: [
                { 
                    // camera
                    binding: 0,
                    visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
                    buffer: { type: "uniform" }
                },
                { 
                    // lightSet
                    binding: 1,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: { type: "read-only-storage" }
                },
                {
                    // clusterLights 
                    binding: 2,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: { type: "read-only-storage" }
                }
            ]
        });

        this.sceneUniformsBindGroup = renderer.device.createBindGroup({
            label: "scene uniforms bind group",
            layout: this.sceneUniformsBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: { buffer: this.camera.uniformsBuffer }
                },
                {
                    binding: 1,
                    resource: { buffer: this.lights.lightSetStorageBuffer }
                },
                {
                    binding: 2,
                    resource: { buffer: this.lights.clusterLightsStorageBuffer}
                }
            ]
        });

        const Width = renderer.canvas.width;
        const Height = renderer.canvas.height;

        this.gBufferTextures = {
            position: renderer.device.createTexture({
                size: [Width, Height],
                format: 'rgba16float',
                usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
            }),
            normal: renderer.device.createTexture({
                size: [Width, Height],
                format: 'rgba16float',
                usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
            }),
            albedo: renderer.device.createTexture({
                size: [Width, Height],
                format: 'rgba8unorm',
                usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
            }),
        }
        this.gBufferTextureViews = {
            position: this.gBufferTextures.position.createView(),
            normal: this.gBufferTextures.normal.createView(),
            albedo: this.gBufferTextures.albedo.createView(),
        }

        this.depthTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "depth24plus",
            usage: GPUTextureUsage.RENDER_ATTACHMENT
        });
        this.depthTextureView = this.depthTexture.createView();

        this.gBufferTexturesBindGroupLayout = renderer.device.createBindGroupLayout({
            entries: [
                { binding: 0, visibility: GPUShaderStage.FRAGMENT, texture: {} },
                { binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: {} },
                { binding: 2, visibility: GPUShaderStage.FRAGMENT, texture: {} },
            ]
        });
        this.gBufferTexturesBindGroup = renderer.device.createBindGroup({
            layout: this.gBufferTexturesBindGroupLayout,
            entries: [
                { binding: 0, resource: this.gBufferTextures.position.createView() },
                { binding: 1, resource: this.gBufferTextures.normal.createView() },
                { binding: 2, resource: this.gBufferTextures.albedo.createView() },
            ]
        });
        this.gBufferPipeline = renderer.device.createRenderPipeline( {
            layout: renderer.device.createPipelineLayout({
                label: "clustered deferred G-buffer pipeline layout",
                bindGroupLayouts: [
                    this.sceneUniformsBindGroupLayout,
                    renderer.modelBindGroupLayout,
                    renderer.materialBindGroupLayout
                ]
            }),
            depthStencil: {
                depthWriteEnabled: true,
                depthCompare: "less",
                format: "depth24plus"
            },
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "clustered deferred G-buffer vert shader",
                    code: shaders.naiveVertSrc
                }),
                entryPoint: "main",
                buffers: [ renderer.vertexBufferLayout ]
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "clustered deferred G-buffer frag shader",
                    code: shaders.clusteredDeferredFragSrc,
                }),
                entryPoint: "main",
                targets: [
                    { format: 'rgba16float' }, 
                    { format: 'rgba16float' }, 
                    { format: 'rgba8unorm' },  
                ],
            }
        });


        this.fullscreenPipeline = renderer.device.createRenderPipeline({
            layout: renderer.device.createPipelineLayout({
                label: "clustered deferred fullscreen pipeline layout",
                bindGroupLayouts: [
                    this.sceneUniformsBindGroupLayout,
                    this.gBufferTexturesBindGroupLayout,
                ]
            }),
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "clustered deferred fullscreen vert shader",
                    code: shaders.clusteredDeferredFullscreenVertSrc
                }),
                entryPoint: "main",
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "clustered deferred fullscreen frag shader",
                    code: shaders.clusteredDeferredFullscreenFragSrc
                }),
                entryPoint: "main",
                targets: [
                    {
                        format: renderer.canvasFormat,
                    }
                ],
            }
        });

    }

    override draw() {
        // TODO-3: run the Forward+ rendering pass:
        // - run the clustering compute shader
        // - run the G-buffer pass, outputting position, albedo, and normals
        // - run the fullscreen pass, which reads from the G-buffer and performs lighting calculations
        const encoder = renderer.device.createCommandEncoder();
        const canvasTextureView = renderer.context.getCurrentTexture().createView();
        this.lights.doLightClustering(encoder);
        const gBufferRenderPass = encoder.beginRenderPass({
            label:  "gBuffer render pass",
            colorAttachments: [
                {
                    view: this.gBufferTextureViews.position,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store",
                },
                {
                    view: this.gBufferTextureViews.normal,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store",
                },
                {
                    view: this.gBufferTextureViews.albedo,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store",
                },
            ],
            depthStencilAttachment: {
                view: this.depthTextureView,
                depthClearValue: 1.0,
                depthLoadOp: "clear",
                depthStoreOp: "store"
            }
        });

        gBufferRenderPass.setPipeline(this.gBufferPipeline);
        gBufferRenderPass.setBindGroup(shaders.constants.bindGroup_scene, this.sceneUniformsBindGroup);
        this.scene.iterate(node => {
            gBufferRenderPass.setBindGroup(shaders.constants.bindGroup_model, node.modelBindGroup);
        }, material => {
            gBufferRenderPass.setBindGroup(shaders.constants.bindGroup_material, material.materialBindGroup);
        }, primitive => {
            gBufferRenderPass.setVertexBuffer(0, primitive.vertexBuffer);
            gBufferRenderPass.setIndexBuffer(primitive.indexBuffer, 'uint32');
            gBufferRenderPass.drawIndexed(primitive.numIndices);
        });
        
        gBufferRenderPass.end();

        const fullscreenRenderPass = encoder.beginRenderPass({
            label: "fullscreen render pass",
            colorAttachments: [
                {
                    view: canvasTextureView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store",
                },
            ],
        });
        fullscreenRenderPass.setPipeline(this.fullscreenPipeline);
        fullscreenRenderPass.setBindGroup(shaders.constants.bindGroup_scene, this.sceneUniformsBindGroup);
        fullscreenRenderPass.setBindGroup(1, this.gBufferTexturesBindGroup);

        fullscreenRenderPass.draw(3);

        fullscreenRenderPass.end();

        renderer.device.queue.submit([encoder.finish()]);  
    }
}
