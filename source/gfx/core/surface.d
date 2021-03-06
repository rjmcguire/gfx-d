module gfx.core.surface;

import gfx.core : Device, Resource, ResourceHolder, MaybeBuiltin;
import gfx.core.rc : Rc, rcCode;
import gfx.core.factory : Factory;
import gfx.core.format : isFormatted, Formatted, Format, Swizzle, isRenderSurface, isDepthOrStencilSurface;
import gfx.core.view : RenderTargetView, DepthStencilView;

import std.typecons : BitFlags;


enum SurfaceUsage {
    None            = 0,
    RenderTarget    = 1,
    DepthStencil    = 2,
}
alias SurfUsageFlags = BitFlags!SurfaceUsage;


interface SurfaceRes : Resource {
    void bind();
}

/// surface that is created by the window
interface BuiltinSurfaceRes : SurfaceRes {
    void updateSize(ushort w, ushort w);
}

abstract class RawSurface : ResourceHolder, MaybeBuiltin {
    mixin(rcCode);

    Rc!SurfaceRes _res;
    SurfUsageFlags _usage;
    ushort _width;
    ushort _height;
    Format _format;
    ubyte _samples;

    this(SurfUsageFlags usage, ushort width, ushort height, Format format, ubyte samples) {
        _usage = usage;
        _width = width;
        _height = height;
        _format = format;
        _samples = samples;
    }

    final @property inout(SurfaceRes) res() inout { return _res.obj; }


    final void pinResources(Device device) {
        Factory.SurfaceCreationDesc desc;
        desc.usage = _usage;
        desc.width = _width;
        desc.height = _height;
        desc.format = _format;
        desc.samples = _samples;
        _res = device.factory.makeSurface(desc);
    }

    final void drop() {
        _res.unload();
    }

    @property bool builtin() const {
        return false;
    }
}


class Surface(T) : RawSurface if (isFormatted!T) {
    alias Fmt = Formatted!T;

    static assert (isRenderSurface!(Fmt.Surface) || isDepthOrStencilSurface!(Fmt.Surface),
            "what is this surface for?");

    this(ushort width, ushort height, ubyte samples) {
        import gfx.core.format : format;
        SurfUsageFlags usage;
        static if (isRenderSurface!(Fmt.Surface)) {
            usage |= SurfaceUsage.RenderTarget;
        }
        static if (isDepthOrStencilSurface!(Fmt.Surface)) {
            usage |= SurfaceUsage.DepthStencil;
        }
        super(usage, width, height, format!T(), samples);
    }

    final RenderTargetView!T viewAsRenderTarget() {
        import gfx.core.view : SurfaceRenderTargetView;
        return new SurfaceRenderTargetView!T(this);
    }

    final DepthStencilView!T viewAsDepthStencil() {
        import gfx.core.view : SurfaceDepthStencilView;
        return new SurfaceDepthStencilView!T(this);
    }
}

class BuiltinSurface(T) : Surface!T
{
    this(BuiltinSurfaceRes res, ushort width, ushort height, ubyte samples) {
        super(width, height, samples);
        _res = res;
    }

    final void updateSize(ushort width, ushort height) {
        import gfx.core.util : unsafeCast;
        _width = width; _height = height;
        unsafeCast!BuiltinSurfaceRes(_res.obj).updateSize(width, height);
    }

    final override @property bool builtin() const {
        return true;
    }
}