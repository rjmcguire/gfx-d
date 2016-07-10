module gfx.core.texture;

import gfx.core : Resource, ResourceHolder;
import gfx.core.rc : RefCounted, RcCode;
import gfx.core.context : Context;
import gfx.core.format;

import std.typecons : BitFlags;

enum TextureType {
    D1, D1Array,
    D2, D2Array, 
    D2Multisample, D2ArrayMultisample,
    D3, Cube, CubeArray
}

enum TextureUsage {
    None = 0,
    RenderTarget = 1,
    DepthStencil = 2,
    ShaderResource = 4,
    UnorderedAccess = 8,
}
alias TexUsageFlags = BitFlags!TextureUsage;

enum CubeFace {
    None,
    PosX, PosY, PosZ,
    NegX, NegY, NegZ,
}

struct ImageSliceInfo {
    ushort xoffset;
    ushort yoffset;
    ushort zoffset;
    ushort width;
    ushort height;
    ushort depth;
    ubyte level;
    CubeFace face;
}

struct ImageInfo {
    ushort width;
    ushort height;
    ushort depth;
    ushort numSlices;
    ubyte levels;
}


interface TextureRes : Resource {
    void bind();
    void update(ImageSliceInfo slice, const(ubyte)[] data);
}


/// untyped texture class
/// instanciate directly typed ones such as Texture2D!Rgba8 
abstract class RawTexture : ResourceHolder {
    mixin RcCode!();

    private TextureRes _res;
    private TextureType _type;
    private ImageInfo _imgInfo;
    private ubyte _samples;
    private Format _format;
    private ubyte _texelSize;
    private const(ubyte)[][] _initData; // deleted after pinResources is called

    private this(TextureType type, ImageInfo imgInfo, ubyte samples, Format format,
                ubyte texelSize, const(ubyte)[][] initData) {
        _type = type;
        _imgInfo = imgInfo;
        _format = format;
        _texelSize = texelSize;
        _initData = initData;
    }

    void drop() {
        if(_res) {
            _res.release();
            _res = null;
        }
    }

    final @property TextureType type() const { return _type; }
    final @property ImageInfo imgInfo() const { return _imgInfo; }
    final @property ushort width() const { return _imgInfo.width; }
    final @property ushort height() const { return _imgInfo.width; }
    final @property ushort depth() const { return _imgInfo.depth; }
    final @property ushort numSlices() const { return _imgInfo.numSlices; }
    final @property ubyte levels() const { return _imgInfo.levels; }
    final @property ubyte samples() const { return _samples; }
    final @property Format format() const { return _format; }
    final @property ubyte texelSize() const { return _texelSize; }

    final @property bool pinned() const { return _res !is null; }

    final void pinResources(Context context) {
        Context.TextureCreationDesc desc;
        desc.type = type;
        desc.format = format;
        desc.imgInfo = imgInfo;
        desc.samples = _samples;
        _res = context.makeTexture(desc, _initData);
        _res.addRef();
        _initData = [];
    }



    /// update part of the texture described by slice with the provided texels.
    /// binary layout of texels MUST match with the texture format
    final void updateRaw(ImageSliceInfo slice, const(ubyte)[] texels) {
        assert(pinned);
        assert(texels.length == _texelSize*slice.width*slice.height*slice.depth);
        assert(slice.xoffset+slice.width <= width);
        assert(slice.yoffset+slice.height <= height);
        assert(slice.zoffset+slice.depth <= depth);
        _res.update(slice, texels);
    }
}


abstract class Texture(TexelF) : RawTexture if (isFormatted!TexelF) {
    alias TexelFormat = Formatted!(TexelF);
    alias Texel = TexelFormat.Surface.DataType;

    /// the texture will be initialized with the provided texels.
    /// if no initialization is required, provide empty slice
    /// otherwise, texels must consists of one slice per provided image.
    /// 2 choices for mipmaps:
    ///  1. provide only level 0 and let the driver generate mipmaps
    ///     beware: gfx-d will not generate the mipmaps if the driver can't (TODO: quality/availability in driver)
    ///  2. provide one slice per mipmap level
    /// in both case, slices will be indexed in the following manner:
    /// [ (imgIndex*numFaces + faceIndex) * numMips * mipIndex ]
    /// where imgIndex will be 0 for non-array textures and
    /// numFaces and faceIndex will be 0 for non-cube textures
    this(TextureType type, ImageInfo imgInfo, ubyte samples, const(Texel)[][] texels) {
        alias format = gfx.core.format.format;
        super(type, imgInfo, samples, format!TexelF, cast(ubyte)Texel.sizeof, untypeSlices(texels));
    }

    /// update part of the texture described by slice with the provided texels.
    final void update(ImageSliceInfo slice, const(Texel)[] texels) {
        updateRaw(slice, cast(ubyte[])texels);
    }
}

class Texture1D(TexelF) : Texture!TexelF {
    this(ubyte levels, ushort width, const(Texel)[][] texels=[]) {
        super(TextureType.D1, ImageInfo(width, 1, 1, 1, levels), 1, texels);
    }
}

class Texture1DArray(TexelF) : Texture!TexelF {
    this(ubyte levels, ushort width, ushort numSlices, const(Texel)[][] texels=[]) {
        super(TextureType.D1Array, ImageInfo(width, 1, 1, numSlices, levels), 1, texels);
    }
}

class Texture2D(TexelF) : Texture!TexelF {
    this(ubyte levels, ushort width, ushort height, const(Texel)[][] texels=[]) {
        super(TextureType.D2, ImageInfo(width, height, 1, 1, levels), 1, texels);
    }
}

class Texture2DArray(TexelF) : Texture!TexelF {
    this(ubyte levels, ushort width, ushort height, ushort numSlices, const(Texel)[][] texels=[]) {
        super(TextureType.D2Array, ImageInfo(width, height, 1, numSlices, levels), 1, texels);
    }
}

class Texture2DMultisample(TexelF) : Texture!TexelF {
    this(ubyte levels, ushort width, ushort height, ubyte samples, const(Texel)[][] texels=[]) {
        super(TextureType.D2Multisample, ImageInfo(width, height, 1, 1, levels), samples, texels);
    }
}

class Texture2DArrayMultisample(TexelF) : Texture!TexelF {
    this(ubyte levels, ushort width, ushort height, ushort numSlices, ubyte samples, const(Texel)[][] texels=[]) {
        super(TextureType.D2ArrayMultisample, ImageInfo(width, height, 1, numSlices, levels), samples, texels);
    }
}

class Texture3D(TexelF) : Texture!TexelF {
    this(ubyte levels, ushort width, ushort height, ushort depth, const(Texel)[][] texels=[]) {
        super(TextureType.D3, ImageInfo(width, height, depth, 1, levels), 1, texels);
    }
}

class TextureCube(TexelF) : Texture!TexelF {
    this(ubyte levels, ushort width, const(Texel)[][] texels=[]) {
        super(TextureType.Cube, ImageInfo(width, width, 6, 1, levels), 1, texels);
    }
}

class TextureCubeArray(TexelF) : Texture!TexelF {
    this(ubyte levels, ushort width, ushort numSlices, const(Texel)[][] texels=[]) {
        super(TextureType.CubeArray, ImageInfo(width, width, 6, numSlices, levels), 1, texels);
    }
}
unittest {
    import gfx.backend.dummy;
    auto ctx = new DummyContext;
    auto tex = new TextureCube!Rgba8(3, 1);
}

