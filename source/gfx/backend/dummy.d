module gfx.backend.dummy;

import gfx.core : Device;
import gfx.core.context : Context;
import gfx.core.rc : RcCode;
import gfx.core.format : Format;
import gfx.core.buffer;
import gfx.core.texture;
import gfx.core.program;
import gfx.core.shader_resource;


class DummyDevice : Device {
    @property Context context() {
        return new DummyContext();
    }
}


class DummyContext : Context {
    TextureRes makeTexture(TextureCreationDesc, const(ubyte)[][]) {
        return new DummyTexture();
    }
    BufferRes makeBuffer(BufferCreationDesc, const(ubyte)[]) {
        return new DummyBuffer();
    }
    ShaderRes makeShader(ShaderStage, string) {
        return new DummyShader();
    }
    ProgramRes makeProgram(ShaderRes[], out ProgramVars) {
        return new DummyProgram();
    }
    ShaderResourceViewRes viewAsShaderResource(RawBuffer) {
        return null;
    }
    ShaderResourceViewRes viewAsShaderResource(RawTexture, TexSRVCreationDesc desc) {
        return null;
    }
}


class DummyTexture : TextureRes {
    mixin RcCode!();
    void drop() {}
    void bind() {}
    void update(in ImageSliceInfo slice, const(ubyte)[] data) {}
}

class DummyBuffer : BufferRes {
    mixin RcCode!();
    void drop() {}
    void bind() {}
    void update(BufferSliceInfo slice, const(ubyte)[] data) {}
}

class DummyShader : ShaderRes {
    mixin RcCode!();
    void drop() {}
    @property ShaderStage stage() const { return ShaderStage.Vertex; }
}

class DummyProgram : ProgramRes {
    mixin RcCode!();
    void drop() {}
    void bind() {}
}