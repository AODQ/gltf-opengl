module gltf2opengl.glgltfenum;
import gltf2, gltf2opengl.glutil;

auto GL_glTFComponentType_Info ( glTFComponentType type ) {
  struct Info { string name; uint label; uint size; GLenum gl_type; }
  alias CT = glTFComponentType;
  immutable GLenum[glTFComponentType] To_Info = [
    CT.Byte:  GL_BYTE,  CT.Ubyte:  GL_UNSIGNED_BYTE,
    CT.Short: GL_SHORT, CT.Ushort: GL_UNSIGNED_SHORT,
    CT.Int:   GL_INT,   CT.Uint:   GL_UNSIGNED_INT, CT.Float: GL_FLOAT,
  ];
  auto base = glTFComponentType_Info(type);
  return Info(base.name, base.label, base.size, To_Info[type]);
}

auto GL_glTFMode_Info ( glTFMode mode ) {
  import std.conv : to;
  struct Info { string name; GLenum gl_mode; }
  immutable GLenum[glTFMode] To_Info = [
    glTFMode.Points:    GL_POINTS,    glTFMode.Lines:         GL_LINES,
    glTFMode.LineLoop:  GL_LINE_LOOP, glTFMode.LineStrip:     GL_LINE_STRIP,
    glTFMode.Triangles: GL_TRIANGLES, glTFMode.TriangleStrip: GL_TRIANGLE_STRIP,
    glTFMode.TriangleFan: GL_TRIANGLE_FAN,
  ];
  return Info(mode.to!string, To_Info[mode]);
}

auto GL_glTFBufferViewTarget_Info ( glTFBufferViewTarget target ) {
  import std.conv : to;
  struct Info { string name; GLenum gl_target; }
  return Info(target.to!string, (target == glTFBufferViewTarget.Array) ?
                            GL_ARRAY_BUFFER : GL_ELEMENT_ARRAY_BUFFER);
}
