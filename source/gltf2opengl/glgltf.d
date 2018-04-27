module gltf2opengl.glgltf;
import gltf2opengl.glutil, gltf2, gltf2opengl.glgltfenum;
import std.stdio;
    import std.variant : visit;
import std.algorithm, std.array, std.range;
/*version(glTFViewer)*/ import gl3n.linalg;
// ----- glTF (root object) ----------------------------------------------------
alias GL_glTFRoot = glTFRootObj!("gl", GL_glTF);
private alias Root = GL_glTFRoot;
private alias float4x4 = Matrix!(float, 4, 4);

struct GL_glTF {
  struct Accessor  { this ( uint idx, Root obj) {} }
  struct Animation { this ( uint idx, Root obj) {} }
  struct Buffer    { this ( uint idx, Root obj) {} }
  struct Image     { this ( uint idx, Root obj) {} }
  struct Material  { this ( uint idx, Root obj) {} }
  // ----- buffer view ---------------------------------------------------------
  struct BufferView {
    GLuint buffer;
    GLenum target;
    uint stride;

    this ( uint idx, Root obj ) {
      auto gltf = &obj.buffer_views[idx].gltf;
      target = GL_glTFBufferViewTarget_Info(gltf.target).gl_target;
      if ( target == glTFBufferViewTarget.NonGPU ) return;
      buffer = GL_glTFCreate_Buffer(target);
      stride = gltf.stride;
      glBufferData(target, gltf.length, gltf.buffer.raw_data.ptr + gltf.offset,
                   GL_STATIC_DRAW);
    }

    void Bind ( ) { glBindBuffer(target, buffer); }
    void Vertex_Attrib_Pointer(GLuint index, GLint size, GLenum type,
                               GLboolean normalized, uint offset) {
      glBindBuffer(target, buffer);
      glEnableVertexAttribArray(index);
      glVertexAttribPointer(index, size, type, normalized, stride,
                            cast(void*)offset);
    }
  }
  // ----- mesh ----------------------------------------------------------------
  struct Primitive {
    GLuint render_vao, render_program, render_mode;
    bool has_index;
    uint render_length, render_gl_enum;

    this(MObj)( uint prim_idx, Root obj, ref MObj mesh ) {
      ShaderInfo sh_info;
      auto gltf = &mesh.gltf.primitives[prim_idx];

      void Create_Buffer ( ref uint idx, glTFAttribute atr ) {
        auto accessor = gltf.RAccessor(atr);
        if ( accessor is null ) {
          sh_info.v_indices[atr] = -1;
          return;
        }
        auto buffer_view = &obj.buffer_views[accessor.buffer_view];
        buffer_view.gl.Vertex_Attrib_Pointer(
          idx, glTFType_Info(accessor.type).count,
          GL_glTFComponentType_Info(accessor.component_type).gl_type,
          GL_FALSE, accessor.offset);
        sh_info.v_indices[atr] = idx;
        idx += 1;
      }
      // -- generate buffers & fill vao data
      glGenVertexArrays(1, &render_vao);
      glBindVertexArray(render_vao);
      uint idx = 0; // count gl vertex attrib
      Create_Buffer(idx, glTFAttribute.Position);
      Create_Buffer(idx, glTFAttribute.Normal);
      Create_Buffer(idx, glTFAttribute.TexCoord0);
      Create_Buffer(idx, glTFAttribute.Colour0);
      has_index = gltf.Has_Index();


      // generate program/shaders
      sh_info.material = null;
      sh_info.has_colour_texture = false;
      if ( gltf.material != -1 ) {
        sh_info.material = &obj.materials[gltf.material];
        sh_info.material.gltf.material.visit!(
          (glTFMaterialNil mat){},
          (glTFMaterialPBRMetallicRoughness mat) {
            if ( mat.base_colour_texture.Exists ) {
              writeln("::", mat.base_colour_texture.texture);
              writeln("::", obj.textures);
              sh_info.has_colour_texture = true;
              obj.textures[mat.base_colour_texture.texture].gl.Bind(0, 10);
            }
          }
        );
      }
      // sh_info.has_texture = obj.RGL_glTFTexture(sh_info.m
      // -- operate on textures
      render_program = Generate_Shader(sh_info);

      // -- index buffer & misc data
      if ( has_index ) {
        auto acc = gltf.RAccessor(glTFAttribute.Index);
        render_gl_enum = GL_glTFComponentType_Info(acc.component_type).gl_type;
        render_length = acc.count;
        obj.buffer_views[acc.buffer_view].gl.Bind();
      } else {
        render_length = gltf.RAccessor(glTFAttribute.Position).count;
      }
      render_mode = GL_glTFMode_Info(gltf.mode).gl_mode;
      glBindVertexArray(0);
      foreach ( i; 0 .. idx )
        glDisableVertexAttribArray(i);
    }

    // version(glTFViewer)
    void Render ( float4x4 view_proj, float4x4 persp_proj, float4x4 model ) {
      glUseProgram(render_program);
      glBindVertexArray(render_vao);
      glUniformMatrix4fv(0, 1, GL_TRUE, model.value_ptr);
      glUniformMatrix4fv(1, 1, GL_TRUE, view_proj.value_ptr);
      glUniformMatrix4fv(2, 1, GL_TRUE, persp_proj.value_ptr);
      if ( !has_index ) glDrawArrays(render_mode, 0, render_length);
      else glDrawElements(render_mode, render_length, render_gl_enum, null);
    }
  }
  struct Mesh {
    Primitive[] primitives;

    this( uint idx, Root obj ) {
      foreach ( it, ref prim; obj.meshes[idx].gltf.primitives )
        primitives ~= Primitive(cast(uint)it, obj, obj.meshes[idx]);
    }

    // version(glTFViewer)
    void Render ( float4x4 view_proj, float4x4 persp_proj, float4x4 model ) {
      primitives.each!(i => i.Render(view_proj, persp_proj, model));
    }
  }
  // ----- node ----------------------------------------------------------------
  struct Node {
    Matrix!(float, 4, 4) model;
    uint index;

    this ( uint idx, Root obj ) {
      index = idx;
      auto gltf = &obj.nodes[idx].gltf;
      model = Matrix!(float, 4, 4)(
        gltf.matrix[0],  gltf.matrix[1],  gltf.matrix[2],  gltf.matrix[3],
        gltf.matrix[4],  gltf.matrix[5],  gltf.matrix[6],  gltf.matrix[7],
        gltf.matrix[8],  gltf.matrix[9],  gltf.matrix[10], gltf.matrix[11],
        gltf.matrix[12], gltf.matrix[13], gltf.matrix[14], gltf.matrix[15],
      );
      // model.transpose;
    }
    void Render ( Root obj, float4x4 view_proj, float4x4 persp_proj ) {
      auto gltf = &obj.nodes[index].gltf;
      // view_proj = view_proj*model;
      if ( gltf.Has_Mesh ) {
        obj.meshes[gltf.mesh].gl.Render(view_proj, persp_proj, model);
      }
      foreach ( child; gltf.children ) {
        // view_proj = view_proj*model;
        obj.nodes[child].gl.Render(obj, view_proj, persp_proj);
      }
    }
  }
  // --- sampler ---------------------------------------------------------------
  struct Sampler {
    this ( uint idx, Object obj ) {}
  }
  // --- scene -----------------------------------------------------------------
  struct Scene {
    this ( uint idx, Object obj ) {}
  }
  // --- skin ------------------------------------------------------------------
  struct Skin {
    this ( uint idx, Object obj ) {}
  }
  // --- texture ---------------------------------------------------------------
  struct Texture {
    GLuint gl_texture;
    this ( uint idx, Root obj ) {
      auto gltf = obj.textures[idx].gltf;
      glGenTextures(1, &gl_texture);
      glBindTexture(GL_TEXTURE_2D, gl_texture);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, gltf.image.width,
                   gltf.image.height, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                   gltf.image.raw_data.ptr);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    }

    void Bind ( int idx, int bind_loc ) {
      glActiveTexture(GL_TEXTURE0 + idx);
      glBindTexture(GL_TEXTURE_2D, gl_texture);
      glUniform1i(bind_loc, idx);
    }
  }
  // ----- texture info --------------------------------------------------------
  struct MaterialTexture {
  }

}
