module gltf2opengl;
import gltf2;
public import gltf2opengl.glgltf, gltf2opengl.glgltfenum;

GL_glTFObject GL_glTF_Load_File ( string filename ) {
  glTFObject object = glTF_Load_File(filename);
  return new GL_glTFObject(object);
}
