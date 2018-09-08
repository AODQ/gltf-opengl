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
  struct Buffer    { this ( uint idx, Root obj) {} }
  struct Image     { this ( uint idx, Root obj) {} }
  struct Material  { this ( uint idx, Root obj) {} }
  // ----- accessor ------------------------------------------------------------
  // TODO probably have two versions of this, one for sparse that allocates its
  //  own. might have to change how glTF works fundamentally.
  // either.. Accessor => BufferView => Buffer => Data
  // or SparseAccessor => Buffer => Data
  struct Accessor {
    GLuint gl_buffer;
    GLuint gl_target;
    uint index;
    uint stride;

    this ( uint idx, Root obj) {
      index = idx;
      auto gltf = &obj.accessors[idx].gltf;
      auto buffer_view = &obj.buffer_views[gltf.buffer_view];
      gl_target = buffer_view.gl.target;
      stride = buffer_view.gl.stride;
      if ( gl_target == glTFBufferViewTarget.NonGPU ) return;
      glGenBuffers(1, &gl_buffer);
      glBindBuffer(gl_target, gl_buffer);

      // TODO use slices that don't copy
      auto ptr = buffer_view.gltf.BufferPtrWithAccessor(obj, gltf);

      auto component_len = glTFComponentType_Info(gltf.component_type).size;
      auto type_len = glTFType_Info(gltf.type).count;
      auto element_size = component_len*type_len;
      int length =  gltf.count * element_size;

      // CHECK floats must not ben NaN/inf
      if ( gltf.component_type == glTFComponentType.Float ) {
        foreach ( fl; cast(float[])ptr[0 .. length] ) {
          assert ( !(fl == float.nan), "float component type is of type NaN");
          assert ( !(fl == float.infinity || fl == -float.infinity),
                   "float component typei s of type infinity");
          }
      }

      // CHECK each offset (accessor, accessor+bufferview) must be a multiple of component_type
      assert((gltf.offset) % component_len == 0,
             "accessor offset must be a multiple of componentType");
      assert((gltf.offset+buffer_view.gltf.offset) % component_len == 0,
             "accessor + buffer_view offset must be a multiple of componentType");

      // CHECK byteStride is a multiple of accessor type
      assert(stride % component_len == 0, "byteStride must be a multiple of componentType");

      // CHECK each accessor must fit its bufferView,
      assert(gltf.offset + stride*(gltf.count-1) + element_size <= buffer_view.gltf.length,
             "Accessor must fit into bufferView");

      // CHECK each element that will be applied to vertex attribute must be multiple of 4
      assert(gltf.byte_offset % 4 == 0, "Accessor byte offset must be a multiple of 4");
      assert(stride % 4 == 0,           "Accessor byte stride must be a multiple of 4");

      // TODO support MAT2 1 byte, MAT3 1 byte and MAT3 2 byte
      //      (4 byte alignment issue)


      glBufferData(gl_target, length, ptr, GL_STATIC_DRAW);
    }

    void Bind ( ) { glBindBuffer(gl_target, gl_buffer); }
    void ApplyVertexAttribute(GLuint index, GLint size, GLenum type,
                              GLboolean normalized, uint offset) {
      Bind();
      glEnableVertexAttribArray(index);
      glVertexAttribPointer(index, size, type, normalized, stride, cast(void*)offset);
    }
  }
  // ----- animation -----------------------------------------------------------
  struct Animation {
    uint index;

    this ( uint idx, Root obj ) {
      index = idx;
    }

    void PostInitialize ( Root obj ) {
      auto gltf = &obj.animations[index].gltf;
      // iterate through channels
      foreach ( ref channel; gltf.channels ) {
        // auto sampler = &gltf.samplers[channel.sampler];
        // auto targetNode = &gltf.nodes[channel.target.node];
        // targetNode.SetAnimation
      }
    }
  }
  // ----- buffer view ---------------------------------------------------------
  struct BufferView {
    GLenum target;
    uint stride;

    this ( uint idx, Root obj ) {
      auto gltf = &obj.buffer_views[idx].gltf;
      target = GL_glTFBufferViewTarget_Info(gltf.target).gl_target;
      stride = gltf.stride;
    }

    void Bind ( GLuint gl_buffer ) { glBindBuffer(target, gl_buffer); }
  }
  // ----- cameras -------------------------------------------------------------
  struct Camera {
    float4x4 projection_matrix;

    this ( uint idx, Root obj ) {
      import std.math : tan;
      auto gltf = &obj.cameras[idx].gltf;
      projection_matrix = gltf.camera.visit!(
        (glTFCameraPerspective p) {
          float a = p.aspect_ratio,
                y = p.yfov, n = p.znear, f = p.zfar;
          float tanfov = tan(0.5f*y);
          return float4x4(
            1.0f/(a*tanfov), 0f,        0f,          0f,
            0f,              1f/tanfov, 0f,          0f,
            0f,              0f,        (f+n)/(n-f), (2f*f*n)/(n-f),
            0f,              0f,        -1f,         0f
          );
        },
        (glTFCameraOrthographic o) {
          return float4x4(-1.0f);
        }
      );
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
        obj.accessors[accessor.buffer_index].gl.ApplyVertexAttribute(
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
        auto index_accessor = gltf.RAccessor(glTFAttribute.Index);
        render_gl_enum = GL_glTFComponentType_Info(index_accessor.component_type).gl_type;
        render_length = index_accessor.count;
        obj.accessors[index_accessor.buffer_index].gl.Bind();
      } else {
        render_length = gltf.RAccessor(glTFAttribute.Position).count;
      } render_mode = GL_glTFMode_Info(gltf.mode).gl_mode;
      glBindVertexArray(0);
      foreach ( i; 0 .. idx )
        glDisableVertexAttribArray(i);
    }

    // version(glTFViewer)
    void Render ( float4x4 view_proj, float4x4 persp_proj, float4x4 model) {
      glUseProgram(render_program);
      glBindVertexArray(render_vao);
      glUniformMatrix4fv(0, 1, GL_TRUE, model.value_ptr);
      glUniformMatrix4fv(1, 1, GL_TRUE, view_proj.value_ptr);
      glUniformMatrix4fv(2, 1, GL_TRUE, persp_proj.value_ptr);
      // glUniform1f(3, delta);
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
    uint index;

    this ( uint idx, Root obj ) {
      index = idx;
    }

    float4x4 RModel_Matrix ( Root obj ) {
      auto gltf = &obj.nodes[index].gltf;
      return gltf.transform.visit!(
        (glTFMatrix matrix) { return float4x4(matrix.data); },
        (glTFTRSMatrix matrix) {
          float4x4 translation = float4x4(
            1f, 0f, 0f, matrix.translation[0],
            0f, 1f, 0f, matrix.translation[1],
            0f, 0f, 1f, matrix.translation[2],
            0f, 0f, 0f, 1f
          );
          float[] mr = matrix.rotation;
          float4x4 rotation = Quaternion!float(mr[0], mr[1], mr[2], mr[3])
                              .to_matrix!(4, 4);
          float[] ms = matrix.scale;
          float4x4 scale = float4x4.scaling(ms[0], ms[1], ms[2]);
          return translation * rotation * scale;
        }
      );
    }

    void Render ( Root obj, float4x4 view_proj, float4x4 persp_proj,
                            float4x4 model_base ) {
      auto gltf = &obj.nodes[index].gltf;
      float4x4 model = RModel_Matrix(obj);
      model_base = model_base*model;
      if ( gltf.Has_Mesh ) {
        obj.meshes[gltf.mesh].gl.Render(view_proj, persp_proj, model_base);
      }
      foreach ( child; gltf.children ) {
        obj.nodes[child].gl.Render(obj, view_proj, persp_proj, model_base);
      }
    }

    float4x4 RCascaded_Model ( Root obj ) {
      auto top = &obj.nodes[index];
      float4x4 model = RModel_Matrix(obj);
      Matrix!(float, 4, 4) tmodel = model;
      while ( top.Has_Node_Parent ) {
        top = &obj.nodes[top.node_parent];
        tmodel = top.gl.RModel_Matrix(obj) * tmodel;
      }
      return tmodel;
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
      // glUniform1i(bind_loc, idx);
    }
  }
  // ----- texture info --------------------------------------------------------
  struct MaterialTexture {
  }

}
