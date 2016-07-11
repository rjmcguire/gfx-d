module gfx.core.context;

import gfx.core.buffer;
import gfx.core.format;
import gfx.core.texture;
import gfx.core.program;

interface Context {

    struct BufferCreationDesc {
        BufferRole role;
        BufferUsage usage;
        size_t size;
    }
    BufferRes makeBuffer(BufferCreationDesc desc, const(ubyte)[] data);
    

    struct TextureCreationDesc {
        TextureType type = TextureType.D1;
        Format format;
        ImageInfo imgInfo;
        ubyte samples;
        TexUsageFlags usage;
    }
    TextureRes makeTexture(TextureCreationDesc desc, const(ubyte)[][] data);

    ShaderRes makeShader(ShaderStage stage, string code);

    ProgramRes makeProgram(ShaderRes[] shaders, out ProgramVars info);
}