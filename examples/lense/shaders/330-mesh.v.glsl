#version 330

in vec3 a_Pos;
in vec3 a_Normal;
in vec2 a_TexCoord;

out vec3 v_Normal;
out vec2 v_TexCoord;

uniform Matrices {
	mat4 u_mvpMat;
	mat4 u_normalMat;
};

void main() {
	v_Normal = (u_normalMat * vec4(a_Normal, 0.0)).xyz;
	v_TexCoord = a_TexCoord;
    gl_Position = u_mvpMat * vec4(a_Pos, 1.0);
}
