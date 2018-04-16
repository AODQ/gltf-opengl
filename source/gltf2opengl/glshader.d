module gltf2opengl.glshader;
import derelict.opengl;
import gltf2;

GLuint Generate_Shader ( glTFPrimitive* primitive ) {
  return Load_Shaders(q{#version 330 core
      #extension GL_ARB_explicit_uniform_location : enable
      layout(location = 0) in vec3 in_vertex;
      layout(location = 1) in vec3 in_normal;

      layout(location = 0)  uniform mat4 Model;
      layout(location = 1) uniform mat4 View_projection;

      out float frag_theta;

      void main ( ) {
        gl_Position = View_projection*Model*vec4(in_vertex, 1.0f);
        frag_theta = clamp(dot(in_normal, normalize(vec3(1.0f, 3.0f, 4.0f))), 0.0f, 1.0f);
      }
  }, q{#version 330 core
    in float frag_theta;
    out vec4 colour;
    void main() {
      colour = vec4(vec3(1.0f)*frag_theta, 1.0f);
    }
  });
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
