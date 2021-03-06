module triangle;

import gfx.core : Rect, Primitive;
import gfx.core.rc : Rc, rc, makeRc;
import gfx.core.typecons : Option, none, some;
import gfx.core.format : Rgba8, Depth32F;
import gfx.core.buffer : VertexBuffer, VertexBufferSlice;
import gfx.core.program : ShaderSet, Program;
import gfx.core.pso.meta;
import gfx.core.pso : PipelineDescriptor, PipelineState, VertexBufferSet;
import gfx.core.state : Rasterizer;
import gfx.core.draw : clearColor, Instance;
import gfx.core.encoder : Encoder;

import gfx.window.glfw : gfxGlfwWindow;

import std.stdio : writeln;


struct Vertex {
    @GfxName("a_Pos")   float[2] pos;
    @GfxName("a_Color") float[3] color;
}

struct PipeMeta {
                        VertexInput!Vertex input;
    @GfxName("o_Color") ColorOutput!Rgba8 output;
}

alias PipeState = PipelineState!PipeMeta;



immutable triangle = [
    Vertex([-0.5, -0.5], [1.0, 0.0, 0.0]),
    Vertex([ 0.5, -0.5], [0.0, 1.0, 0.0]),
    Vertex([ 0.0,  0.5], [0.0, 0.0, 1.0]),
];

immutable float[4] backColor = [0.1, 0.2, 0.3, 1.0];



int main()
{
    /// window with a color buffer and no depth/stencil buffer
    auto window = rc(gfxGlfwWindow!Rgba8("gfx-d - Triangle", 640, 480, 4));
    auto colRtv = rc(window.colorSurface.viewAsRenderTarget());
    {
        auto vbuf = makeRc!(VertexBuffer!Vertex)(triangle);
        auto slice = VertexBufferSlice(vbuf.count);
        auto prog = makeRc!Program(ShaderSet.vertexPixel(
            import("130-triangle.v.glsl"),
            import("130-triangle.f.glsl"),
        ));
        auto pso = makeRc!PipeState(prog.obj, Primitive.Triangles, Rasterizer.fill.withSamples());

        auto data = PipeState.Data.init;
        data.input = vbuf;
        data.output = colRtv;

        auto encoder = Encoder(window.device.makeCommandBuffer());

        // will quit on any key hit (as well as on close by 'x' click)
        window.onKey = (int, int, int, int) {
            window.shouldClose = true;
        };

        window.onFbResize = (ushort w, ushort h) {
            encoder.setViewport(Rect(0, 0, w, h));
        };

        import std.datetime : StopWatch;

        size_t frameCount;
        StopWatch sw;
        sw.start();

        /* Loop until the user closes the window */
        while (!window.shouldClose) {

            encoder.clear!Rgba8(colRtv, backColor);
            encoder.draw!PipeMeta(slice, pso, data);
            encoder.flush(window.device);

            /* Swap front and back buffers */
            window.swapBuffers();

            /* Poll for and process events */
            window.pollEvents();

            frameCount += 1;
        }

        auto ms = sw.peek().msecs();
        writeln("FPS: ", 1000.0f*frameCount / ms);
    }

    return 0;
}
