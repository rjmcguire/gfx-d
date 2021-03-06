module gfx.core.util;


/// down cast of a reference to a child class reference
/// runtime check is disabled in release build
U unsafeCast(U, T)(T obj)
        if ((is(T==class) || is(T==interface)) &&
            (is(U==class) || is(U==interface)) &&
            is(U : T))
{
    debug {
        auto uObj = cast(U)obj;
        assert(uObj, "unsafeCast from "~T.stringof~" to "~U.stringof~" failed");
        return uObj;
    }
    else {
        static if (is(T == interface) && is(U == class)) {
            return cast(U)(cast(void*)(cast(Object)obj));
        }
        else {
            return cast(U)(cast(void*)obj);
        }
    }
}

/// ditto
const(U) unsafeCast(U, T)(const(T) obj)
        if ((is(T==class) || is(T==interface)) &&
            (is(U==class) || is(U==interface)) &&
            is(U : T))
{
    debug {
        auto uObj = cast(const(U))obj;
        assert(uObj, "unsafeCast from "~T.stringof~" to "~U.stringof~" failed");
        return uObj;
    }
    else {
        static if (is(T == interface) && is(U == class)) {
            return cast(const(U))(cast(const(void*))(cast(const(Object))obj));
        }
        else {
            return cast(const(U))(cast(const(void*))obj);
        }
    }
}



/// cast a typed slice into a blob of bytes
/// (same representation; no copy is made)
ubyte[] untypeSlice(T)(T[] slice) if(!is(T == const)) {
    if (slice.length == 0) return [];
    auto loc = cast(ubyte*)slice.ptr;
    return loc[0 .. slice.length*T.sizeof];
}

/// ditto
const(ubyte)[] untypeSlice(T)(const(T)[] slice) {
    if (slice.length == 0) return [];
    auto loc = cast(const(ubyte)*)slice.ptr;
    return loc[0 .. slice.length*T.sizeof];
}

/// cast a blob of bytes into a typed slice
T[] retypeSlice(T)(ubyte[] slice) if (!is(T == const)){
    if(slice.length == 0) return [];
    assert((slice.length % T.sizeof) == 0);
    auto loc = cast(T*)slice.ptr;
    return loc[0 .. slice.length / T.sizeof];
}

/// ditto
const(T)[] retypeSlice(T)(const(ubyte)[] slice) {
    if(slice.length == 0) return [];
    assert((slice.length % T.sizeof) == 0);
    auto loc = cast(const(T)*)slice.ptr;
    return loc[0 .. slice.length / T.sizeof];
}

unittest {
    int[] slice = [1, 2, 3, 4];
    auto bytes = untypeSlice(slice);
    auto ints = retypeSlice!int(bytes);
    assert(bytes.length == 16);
    version(LittleEndian) {
        assert(bytes == [
            1, 0, 0, 0,
            2, 0, 0, 0,
            3, 0, 0, 0,
            4, 0, 0, 0,
        ]);
    }
    else {
        assert(bytes == [
            0, 0, 0, 1,
            0, 0, 0, 2,
            0, 0, 0, 3,
            0, 0, 0, 4,
        ]);
    }
    assert(ints.length == 4);
    assert(ints == slice);
    assert(ints.ptr == slice.ptr);
}

/// cast an array of typed slices to another array of blob of bytes
/// an allocation is performed for the top container (the array of arrays)
/// but the underlying data is moved without allocation
ubyte[][] untypeSlices(T)(T[][] slices) if (!is(T == const)) {
    ubyte[][] res = new ubyte[][slices.length];
    foreach(i, s; slices) {
        res[i] = untypeSlice(s);
    }
    return res;
}

/// ditto
const(ubyte)[][] untypeSlices(T)(const(T)[][] slices) {
    const(ubyte)[][] res = new const(ubyte)[][slices.length];
    foreach(i, s; slices) {
        res[i] = untypeSlice(s);
    }
    return res;
}

unittest {
    int[][] texels = [ [1, 2], [3, 4] ];
    auto bytes = untypeSlices(texels);
    assert(bytes.length == 2);
    assert(bytes[0].length == 8);
    assert(bytes[1].length == 8);
    version(LittleEndian) {
        assert(bytes == [
            [   1, 0, 0, 0,
                2, 0, 0, 0, ],
            [   3, 0, 0, 0,
                4, 0, 0, 0, ],
        ]);
    }
    else {
        assert(bytes == [
            [   0, 0, 0, 1,
                0, 0, 0, 2, ],
            [   0, 0, 0, 3,
                0, 0, 0, 4, ],
        ]);
    }
}
