module gltf2opengl.glutil;
import gltf2, gltf2opengl.glgltfenum;
public import gltf2opengl.glshader;
public import derelict.opengl;


GLuint GL_glTFCreate_Buffer ( GLenum target ) {
  GLuint buffer;
  glGenBuffers(1, &buffer);
  glBindBuffer(target, buffer);
  return buffer;
}

// GLuint GL_glTFCreate_Buffer ( glTFAccessor acc ) {
//   // -- create and buffer buffer
//   glTFBufferView* view = acc.buffer_view;
//   auto target = GL_glTFBufferViewTarget_Info(view.target).gl_target;
//   GLuint buffer = GL_glTFCreate_Buffer(target);
//   glBufferData(target, view.length,
//                view.buffer.raw_data.ptr + view.offset + acc.offset,
//                GL_STATIC_DRAW);
//   return buffer;
// }
