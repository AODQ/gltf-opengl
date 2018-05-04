module gltf2opengl.glshader;
import gltf2opengl.glgltf : GL_glTFRoot;
import derelict.opengl;
import gltf2;
import std.stdio;

struct ShaderInfo {
  int[glTFAttribute] v_indices;
  GL_glTFRoot.SubrootMaterial* material;
  bool has_colour_texture;
}

GLuint Generate_Shader ( ShaderInfo info ) {
  import std.string : format;

  string in_vs, uni_vs, out_vs, main_vs;
  string in_fs, uni_fs, out_fs, main_fs;

  int vert_idx = info.v_indices[glTFAttribute.Position],
      nor_idx  = info.v_indices[glTFAttribute.Normal],
      tc0_idx  = info.v_indices[glTFAttribute.TexCoord0],
      col_idx  = info.v_indices[glTFAttribute.Colour0];
  // -- uniform MVP matrix
  uni_vs ~= "layout(location = 0) uniform mat4 Model;\n";
  uni_vs ~= "layout(location = 1) uniform mat4 View;\n";
  uni_vs ~= "layout(location = 2) uniform mat4 Perspective;\n";
  // -- position (gaurunteed to exist )
  in_vs ~= "layout(location = %s) in vec3 in_vertex;\n".format(vert_idx);
  main_vs ~= "gl_Position = Perspective*View*Model*vec4(in_vertex, 1.0f);\n";
  out_vs ~= "out vec3 frag_Lo;\n";
  in_fs  ~= "in vec3 frag_Lo;\n";
  main_vs ~= "frag_Lo = vec3(20.0f, 50.0f, 20.0f);";
  main_vs ~= "frag_Lo = (vec4(frag_Lo, 1.0f)).xyz;\n";
  main_vs ~= "frag_Lo = normalize(frag_Lo - in_vertex.xyz);";
  // -- texcoord0 coordinates
  if ( tc0_idx >= 0 ) {
    in_vs ~= "layout(location = %s) in vec2 in_texcoord0;\n".format(tc0_idx);
    out_vs ~= "out vec2 frag_texcoord0;\n";
    in_fs ~= "in vec2 frag_texcoord0;\n";
    main_vs ~= "frag_texcoord0 = in_texcoord0;\n";
  }
  // -- colour0 coordinates
  if ( col_idx >= 0 ) {
    in_vs ~= "layout(location = %s) in vec3 in_colour0;\n".format(col_idx);
    out_vs ~= "out vec3 frag_colour0;\n";
    in_fs ~= "in vec3 frag_colour0;\n";
    main_vs ~= "frag_colour0 = in_colour0;\n";
  }
  // -- normal
  if ( nor_idx >= 0 ) {
    in_vs ~= "layout(location = %s) in vec3 in_nor;\n".format(nor_idx);
    out_vs ~= "out vec3 frag_N;\n";
    out_vs ~= "out vec3 frag_wi;\n";
    in_fs ~= "in vec3 frag_N;\n";
    in_fs ~= "in vec3 frag_wi;\n";
    main_vs ~= "frag_N = (View*Model*vec4(in_nor, 0.0f)).xyz;\n";
    main_vs ~= "frag_wi = normalize(-gl_Position.xyz);\n";
    // main_vs ~= "frag_wi *= vec3(1.0f, 1.0f, 1.0f);\n";
  }
  // -- constants
  uni_vs ~= "#define PI 3.14159265f\n";
  uni_fs ~= "#define PI 3.14159265f\n";
  // -- BRDF
  main_fs ~= "vec3 brdf = vec3(1.0f);\n";
  // -- material
  import std.variant, std.conv;
  if ( info.material !is null ) info.material.gltf.material.visit!(
    (glTFMaterialNil mat) {
      if ( nor_idx >= 0 ) {
        main_fs ~= "brdf = vec3(1.0f);";
      }
    },
    (glTFMaterialPBRMetallicRoughness mat) {
      out_fs ~= q{
        float GGX ( vec3 wi, vec3 H, float k ) {
          return dot(wi, H)/(dot(wi, H)*(1.0f-k)+k);
        }
        float sqr(float t){return t*t;}
      };
      if ( info.has_colour_texture ) {
        uni_fs ~= "layout(location = 10) uniform sampler2D col_tex;\n";
        main_fs ~= "vec3 col = texture(col_tex, frag_texcoord0).xyz;\n";
      } else {
        main_fs ~= "vec3 col = vec3(%s, %s, %s);\n".format(
          mat.colour_factor[0], mat.colour_factor[1], mat.colour_factor[2]);
      }
      if ( col_idx >= 0 ) {
        main_fs ~= "col *= frag_colour0;";
      }
      main_fs ~= q{
        float roughness = %s, metallic = %s;
        float alpha = sqr(roughness);
        const vec3 dielectricSpecular = vec3(0.04f);
        vec3 diff = mix(col * (1.0f - dielectricSpecular.r), col*0.5f,
                        metallic);
        vec3 F0 = mix(dielectricSpecular, col, metallic);
        vec3 wi = frag_wi,
             N = frag_N,
             wo = frag_Lo,
             H = normalize(wi+wo);
        diff = (1.0f-F0)*(diff/PI);
        // -- fresnel
        brdf = F0 + (vec3(1.0f)-F0)*pow(1.0f - dot(wi, H), 5.0f);
        // -- geometric
        float k = alpha*sqrt(2.0f/PI);
        // brdf *= vec3(1.0f)*GGX(wi, H, k)*GGX(wo, H, k);
        // -- distribution
        brdf *= vec3(1.0f)*(alpha)/(PI*sqr(sqr(dot(N, H))*(alpha-1.0f)+1.0f));

        // brdf /= (4.0f*dot(N, wo));
        brdf = clamp(brdf, vec3(0.0f), vec3(1.0f));
        // brdf *= clamp(dot(N, wo), 0.0f, 1.0f);
        brdf = col*(1.0f/PI) + brdf*col;
        // brdf = normalize(reflect(wi, normalize(N)));
        // brdf = vec3(wo);
      }.format(mat.roughness_factor, mat.metallic_factor);
    }
  );
  // -- frag colour
  import std.stdio;
  out_fs ~= "out vec4 colour;\n";
  main_fs ~= "colour = vec4(brdf, 1.0f);\n";

  // main_fs ~= "colour = vec4(vec3(frag_wo), 1.0f);\n";

  // -- build shader
  string core_shader = q{#version 330 core
    #extension GL_ARB_explicit_uniform_location : enable
    %s %s %s void main() { %s }};

  import std.stdio;
  writeln("--------------------------------");
  writeln(
        core_shader.format(in_vs, uni_vs, out_vs, main_vs), "\n\n",
                      core_shader.format(in_fs, uni_fs, out_fs, main_fs)
  );
  writeln("--------------------------------");
  return Load_Shaders(core_shader.format(in_vs, uni_vs, out_vs, main_vs),
                      core_shader.format(in_fs, uni_fs, out_fs, main_fs));
}

GLuint Load_Shaders(string vertex, string fragment) {
  import std.stdio, std.string;
  GLuint vshader = glCreateShader(GL_VERTEX_SHADER),
         fshader = glCreateShader(GL_FRAGMENT_SHADER);

  void Check ( string nam, GLuint sh ) {
    GLint res;
    int info_log_length;
    glGetShaderiv(sh, GL_COMPILE_STATUS, &res);
    glGetShaderiv(sh, GL_INFO_LOG_LENGTH, &info_log_length);
    if ( info_log_length > 0 ){
      char[] msg; msg.length = info_log_length+1;
      glGetShaderInfoLog(sh, info_log_length, null, msg.ptr);
      writeln(nam, ": ", msg);
      assert(false);
    }
  }

  immutable(char)* vertex_c   = toStringz(vertex),
                   fragment_c = toStringz(fragment);
  glShaderSource(vshader, 1, &vertex_c, null);
  glCompileShader(vshader);
  Check("vertex", vshader);

  glShaderSource(fshader, 1, &fragment_c, null);
  glCompileShader(fshader);
  Check("fragment", fshader);

  GLuint program_id = glCreateProgram();
  glAttachShader(program_id, vshader);
  glAttachShader(program_id, fshader);
  glLinkProgram(program_id);
  glDetachShader(program_id, vshader);
  glDetachShader(program_id, fshader);
  glDeleteShader(vshader);
  glDeleteShader(fshader);
  return program_id;
}
