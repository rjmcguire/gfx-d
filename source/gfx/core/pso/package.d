/// pipeline state objects (pso) embed a part of the pipeline state
/// in order to allow fast rendering context switches.
/// PSOs have a layout part and a data part.
/// the layout part is defined at compile time. when data is filled into a PSO,
/// it is checked at runtime that the data fits the layout.
/// pso embed the following layout:
///    program layout (inputs, uniforms, outputs)
///    vertex data layout (the type of vertex is specified at compile time and defines program input)
///    TODO: exhaustive description
/// backends that natively support psos are Vulkan and DX12 (none implemented at this stage)
/// for other backends, the pipeline switch is emulated
module gfx.core.pso;

import gfx.core :   Device, Resource, ResourceHolder, Primitive, Rect,
                    maxVertexAttribs, maxColorTargets, AttribMask, ColorTargetMask;
import gfx.core.rc : Rc, rcCode, RefCounted;
import gfx.core.typecons : Option, none, some;
import gfx.core.state : Rasterizer, ColorMask, ColorFlags, BlendChannel, Blend, Depth, Stencil;
import gfx.core.format : Format, SurfaceType, Formatted;
import gfx.core.buffer : RawBuffer;
import gfx.core.texture : Sampler;
import gfx.core.program : Program, VarType, ProgramVars;
import gfx.core.view : RawShaderResourceView, RawRenderTargetView, RawDepthStencilView;
import gfx.core.pso.meta : isMetaStruct;


// descriptor structs

struct StructField {
    VarType type;
    size_t offset;
    size_t size;
    size_t alignment;
    size_t stride;
}

struct VertexAttribDesc {
    string name;
    ubyte slot;
    StructField field;
    ubyte instanceRate;
}

struct ConstantBlockDesc {
    string name;
    ubyte slot;
}

struct ResourceViewDesc {
    string name;
    ubyte slot;
    Format format;
}

struct SamplerDesc {
    string name;
    ubyte slot;
}


struct ColorInfo {
    ColorMask mask;
    Option!Blend blend;

    this (ColorMask mask) {
        this.mask = mask;
        this.blend = none!Blend;
    }

    this(Blend blend) {
        this.mask = ColorMask(ColorFlags.All);
        this.blend = some(blend);
    }

    this(ColorMask mask, Blend blend) {
        this.mask = mask;
        this.blend = some(blend);
    }
}


struct ColorTargetDesc {
    string name;
    ubyte slot;
    Format format;
    ColorInfo info;
}

struct DepthStencilDesc {
    SurfaceType surface;

    Option!Depth depth;
    Option!Stencil stencil;

    this(SurfaceType surface, Depth depth) {
        this.surface = surface;
        this.depth = some(depth);
    }
    this(SurfaceType surface, Stencil stencil) {
        this.surface = surface;
        this.stencil = some(stencil);
    }
    this(SurfaceType surface, Depth depth, Stencil stencil) {
        this.surface = surface;
        this.depth = some(depth);
        this.stencil = some(stencil);
    }
}


struct PipelineDescriptor {
    Primitive   primitive;
    Rasterizer  rasterizer;
    bool        scissor;

    VertexAttribDesc[]      vertexAttribs;
    ConstantBlockDesc[]     constantBlocks;
    ResourceViewDesc[]      resourceViews;
    SamplerDesc[]           samplers;
    ColorTargetDesc[]       colorTargets;
    Option!DepthStencilDesc depthStencil;

    @property bool needsToFetchSlots() const {
        foreach(at; vertexAttribs) {
            if (at.slot == ubyte.max) return true;
        }
        foreach(cb; constantBlocks) {
            if (cb.slot == ubyte.max) return true;
        }
        foreach(rv; resourceViews) {
            if (rv.slot == ubyte.max) return true;
        }
        foreach(s; samplers) {
            if (s.slot == ubyte.max) return true;
        }
        foreach(ct; colorTargets) {
            if (ct.slot == ubyte.max) return true;
        }
        return false;
    }
}


// data structs

struct ResourceSet(ElemT, string fieldName) if (is(ElemT : RefCounted))
{
    import std.format : format;

    private ElemT[] _elems;
    mixin(format("@property inout(ElemT)[] %s() inout { return _elems; }", fieldName));

    void add(ElemT elem) {
        elem.addRef();
        _elems ~= elem;
    }

    this(this) {
        import std.algorithm : each;
        _elems.each!(e => e.addRef());
    }
    ~this() {
        import std.algorithm : each;
        _elems.each!(e => e.release());
    }
}

alias VertexBufferSet = ResourceSet!(RawBuffer, "buffers");
alias ConstantBlockSet = ResourceSet!(RawBuffer, "blocks");
alias ResourceViewSet = ResourceSet!(RawShaderResourceView, "views");
alias SamplerSet = ResourceSet!(Sampler, "samplers");


/// A complete set of render targets to be used for pixel export in PSO.
struct PixelTargetSet {

    /// Array of color target views
    RawRenderTargetView[] colors;

    /// Depth target view
    Rc!RawDepthStencilView depth;
    /// Stencil target view
    Rc!RawDepthStencilView stencil;
    /// Rendering dimensions
    ushort width;
    /// ditto
    ushort height;


    /// Add a color view to the specified slot
    void addColor(RawRenderTargetView view) {
        import gfx.core.rc : rc;
        import std.algorithm : max;

        view.addRef();
        colors ~= view;
    }

    this(this) {
        import std.algorithm : each;
        colors.each!(rtv => rtv.addRef());
    }

    ~this() {
        import std.algorithm : each;
        colors.each!(rtv => rtv.release());
    }
}


struct RawDataSet {
    VertexBufferSet vertexBuffers;
    ConstantBlockSet constantBlocks;
    ResourceViewSet resourceViews;
    SamplerSet samplers;
    PixelTargetSet pixelTargets;
    Rect scissor;
    float[4] blendRef;
    ubyte[2] stencilRef;
}


interface PipelineStateRes : Resource {
    void bind();
}

abstract class RawPipelineState : ResourceHolder {
    mixin(rcCode);

    PipelineDescriptor _descriptor;

    Rc!PipelineStateRes _res;
    Rc!Program _prog;

    this(Program program, Primitive primitive, Rasterizer rasterizer) {
        _prog = program;
        _descriptor.primitive = primitive;
        _descriptor.rasterizer = rasterizer;
    }

    final @property inout(PipelineStateRes) res() inout { return _res.obj; }

    final @property inout(Program) program() inout { return _prog.obj; }

    final @property const(PipelineDescriptor) descriptor() const { return _descriptor; }

    final void drop() {
        _prog.unload();
        _res.unload();
    }
}


class PipelineState(MS) : RawPipelineState if (isMetaStruct!MS)
{
    import gfx.core.pso.meta : PipelineInit, PipelineData;
    import std.traits : Fields, FieldNameTuple;

    alias Init = PipelineInit!MS;
    alias Data = PipelineData!MS;

    this(Program prog, Primitive primitive, Rasterizer rasterizer, Init initStruct=Init.init) {
        super(prog, primitive, rasterizer);
        initDescriptor(initStruct);
    }

    private void initDescriptor(in Init initStruct) {
        import gfx.core.pso.meta :  metaVertexInputFields,
                                    metaConstantBlockFields,
                                    metaResourceViewFields,
                                    metaResourceSamplerFields,
                                    metaColorOutputFields,
                                    metaBlendOutputFields,
                                    metaDepthOutputFields,
                                    metaStencilOutputFields,
                                    metaDepthStencilOutputFields,
                                    metaScissorFields;
        import std.format : format;
        foreach (vif; metaVertexInputFields!MS) {
            _descriptor.vertexAttribs ~= mixin(format("initStruct.%s[]", vif.name));
        }
        foreach (cbf; metaConstantBlockFields!MS) {
            _descriptor.constantBlocks ~= mixin(format("initStruct.%s", cbf.name));
        }
        foreach (rvf; metaResourceViewFields!MS) {
            _descriptor.resourceViews ~= mixin(format("initStruct.%s", rvf.name));
        }
        foreach (rsf; metaResourceSamplerFields!MS) {
            _descriptor.samplers ~= mixin(format("initStruct.%s", rsf.name));
        }
        foreach (cof; metaColorOutputFields!MS) {
            _descriptor.colorTargets ~= mixin(format("initStruct.%s", cof.name));
        }
        foreach (bof; metaBlendOutputFields!MS) {
            _descriptor.colorTargets ~= mixin(format("initStruct.%s", bof.name));
        }
        enum numDS = metaDepthOutputFields!MS.length +
                    metaStencilOutputFields!MS.length +
                    metaDepthStencilOutputFields!MS.length;
        static assert(numDS == 0 || numDS == 1,
                MS.stringof~" has too many depth-stencil targets (should be one at most)");
        foreach (dof; metaDepthOutputFields!MS) {
            alias Fmt = Formatted!(dof.FormatType);
            _descriptor.depthStencil = some(DepthStencilDesc(
                Fmt.Surface.surfaceType, mixin(format("initStruct.%s", dof.name))
            ));
        }
        foreach (sof; metaStencilOutputFields!MS) {
            alias Fmt = Formatted!(sof.FormatType);
            _descriptor.depthStencil = some(DepthStencilDesc(
                Fmt.Surface.surfaceType, mixin(format("initStruct.%s", sof.name))
            ));
        }
        foreach (sof; metaDepthStencilOutputFields!MS) {
            alias Fmt = Formatted!(sof.FormatType);
            _descriptor.depthStencil = some(DepthStencilDesc(
                Fmt.Surface.surfaceType,
                mixin(format("initStruct.%s[0]", dof.name)), mixin(format("initStruct.%s[1]", dof.name))
            ));
        }
        foreach (i, sf; metaScissorFields!MS) {
            static assert(i == 0, "one scissor field allowed");
            _descriptor.scissor = true;
        }
    }

    final void pinResources(Device device) {
        if (!_prog.pinned) _prog.pinResources(device);
        if (_descriptor.needsToFetchSlots) {
            import std.exception : enforce;
            import std.algorithm : find;
            import std.range : takeOne, empty, front;
            import std.format : format;

            enforce(device.caps.introspection);
            ProgramVars vars = _prog.fetchVars();

            foreach(ref at; _descriptor.vertexAttribs) {
                if (at.slot != ubyte.max) continue;
                auto var = vars.attributes
                        .find!(v => v.name == at.name)
                        .takeOne();
                enforce(!var.empty, format("cannot find attribute %s in pipeline %s", at.name, MS.stringof));
                at.slot = var.front.loc;
            }
            foreach(ref cb; _descriptor.constantBlocks) {
                if (cb.slot != ubyte.max) continue;
                auto var = vars.constBuffers
                        .find!(b => b.name == cb.name)
                        .takeOne();
                enforce(!var.empty, format("cannot find block %s in pipeline %s", cb.name, MS.stringof));
                cb.slot = var.front.loc;
            }
            foreach(ref srv; _descriptor.resourceViews) {
                if (srv.slot != ubyte.max) continue;
                auto var = vars.textures
                        .find!(v => v.name == srv.name)
                        .takeOne();
                enforce(!var.empty, format("cannot find texture %s in pipeline %s", srv.name, MS.stringof));
                srv.slot = var.front.loc;
            }
            foreach(ref sampler; _descriptor.samplers) {
                if (sampler.slot != ubyte.max) continue;
                auto var = vars.samplers
                        .find!(v => v.name == sampler.name)
                        .takeOne();
                enforce(!var.empty, format("cannot find sampler %s in pipeline %s", sampler.name, MS.stringof));
                sampler.slot = var.front.slot;
            }
            foreach(ref ct; _descriptor.colorTargets) {
                if (ct.slot != ubyte.max) continue;
                auto var = vars.outputs
                        .find!(v => v.name == ct.name)
                        .takeOne();
                enforce(!var.empty, format("cannot find color target %s in pipeline %s", ct.name, MS.stringof));
                ct.slot = var.front.index;
            }
            enforce(!_descriptor.needsToFetchSlots);
        }
        _res = device.factory.makePipeline(_prog.obj, _descriptor);
    }


    final RawDataSet makeDataSet(Data dataStruct) {
        import gfx.core.pso.meta :  metaVertexInputFields,
                                    metaConstantBlockFields,
                                    metaResourceViewFields,
                                    metaResourceSamplerFields,
                                    metaColorOutputFields,
                                    metaBlendOutputFields,
                                    metaDepthOutputFields,
                                    metaStencilOutputFields,
                                    metaDepthStencilOutputFields,
                                    metaScissorFields;
        import std.format : format;
        import std.traits : Fields;

        RawDataSet res;

        // each resource is added here in the order that it is declared in the pipeline meta struct
        // the same order is used in the descriptor and in the init struct
        // this how link is made between all structs

        foreach (vif; metaVertexInputFields!MS) {
            foreach (i, va; Fields!(vif.VertexType)) {
                res.vertexBuffers.add(mixin(format("dataStruct.%s", vif.name)));
            }
        }
        foreach (cbf; metaConstantBlockFields!MS) {
            res.constantBlocks.add(mixin(format("dataStruct.%s", cbf.name)));
        }
        foreach (rvf; metaResourceViewFields!MS) {
            res.resourceViews.add(mixin(format("dataStruct.%s", rvf.name)));
        }
        foreach (rsf; metaResourceSamplerFields!MS) {
            res.samplers.add(mixin(format("dataStruct.%s", rsf.name)));
        }
        foreach (cof; metaColorOutputFields!MS) {
            res.pixelTargets.addColor(mixin(format("dataStruct.%s", cof.name)));
        }
        foreach (bof; metaBlendOutputFields!MS) {
            res.pixelTargets.addColor(mixin(format("dataStruct.%s", bof.name)));
        }
        foreach (dof; metaDepthOutputFields!MS) {
            res.pixelTargets.depth = mixin(format("dataStruct.%s", dof.name));
        }
        foreach (sof; metaStencilOutputFields!MS) {
            res.pixelTargets.stencil = mixin(format("dataStruct.%s[0]", sof.name));
            res.stencilRef = mixin(format("dataStruct.%s[1]", sof.name));
        }
        foreach (dsof; metaDepthStencilOutputFields!MS) {
            res.pixelTargets.depth = mixin(format("dataStruct.%s[0]", dsof.name));
            res.pixelTargets.stencil = mixin(format("dataStruct.%s[0]", dsof.name));
            res.stencilRef = mixin(format("dataStruct.%s[1]", sof.name));
        }
        foreach (sf; metaScissorFields!MS) {
            res.scissor = mixin(format("dataStruct.%s", sf.name));
        }
        return res;
    }

}



