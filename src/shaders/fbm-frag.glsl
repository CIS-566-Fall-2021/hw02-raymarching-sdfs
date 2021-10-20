#version 300 es

// This is a fragment shader. If you've opened this file first, please
// open and read lambert.vert.glsl before reading on.
// Unlike the vertex shader, the fragment shader actually does compute
// the shading of geometry. For every pixel in your program's output
// screen, the fragment shader is run for every bit of geometry that
// particular pixel overlaps. By implicitly interpolating the position
// data passed into the fragment shader by the vertex shader, the fragment shader
// can compute what color to apply to its pixel based on things like vertex
// position, light position, and vertex color.
precision highp float;

uniform float u_Time;

uniform vec4 u_Color; // The color with which to render this instance of geometry.

// These are the interpolated values out of the rasterizer, so you can't know
// their specific values without knowing the vertices that contributed to them
in vec4 fs_Nor;
in vec4 fs_LightVec;
in vec4 fs_Col;
in vec4 fs_Pos;

out vec4 out_Col; // This is the final output color that you will see on your
                  // screen for the pixel that is currently being processed.


float dot(ivec3 a, ivec3 b) {
    return float(a.x * b.x + a.y * b.y + a.z * b.z);
}

float random(ivec3 p){
 	return abs(fract(184.421631 * sin(dot(p, ivec3(1932, 324, 6247)))));
    // vec3 k = vec3( 3.1415926, 2.71828,6.62607015);
 	// p = p*k + p.yzx;
 	// return fract( 131.673910 * fract( p.x*p.y*(p.x+p.y)) );
}


float smoothStep(float a, float b, float t) {
    //t = t*(t*(t * 5.0 - .23));
    //t = clamp(t, 0.0, 1.0);
    return mix(a,b,t);
}

float smootherStep(float a, float b, float t) {
    t = t*t*t*(t*(t*6.0 - 15.0) + 10.0);
    return mix(a, b, t);
}

float interpNoise3D(vec3 p) {
  int intX = int(floor(p.x));
  float fractX = fract(p.x);
  int intY = int(floor(p.y));
  float fractY = fract(p.y);
  int intZ = int(floor(p.z));
  float fractZ = fract(p.z);

  float v1 = random(ivec3(intX, intY, intZ));
  float v2 = random(ivec3(intX + 1, intY, intZ));
  float v3 = random(ivec3(intX, intY + 1, intZ));
  float v4 = random(ivec3(intX + 1, intY + 1, intZ));

  float v5 = random(ivec3(intX, intY, intZ + 1));
  float v6 = random(ivec3(intX + 1, intY, intZ + 1));
  float v7 = random(ivec3(intX, intY + 1, intZ + 1));
  float v8 = random(ivec3(intX + 1, intY + 1, intZ + 1));

  float i1 = smootherStep(v1, v2, fractX);
  float i2 = smootherStep(v3, v4, fractX);
  float result1 = smootherStep(i1, i2, fractY);

  float i3 = smootherStep(v5, v6, fractX);
  float i4 = smootherStep(v7, v8, fractX);
  float result2 = smootherStep(i3, i4, fractY);

  return smootherStep(result1, result2, fractZ);
}

float fbm(vec3 v) {
    v*= 1.2;
    int octave = 4;
    float a = 1.0;
    float val = 0.0;
    for (int i = 0; i < octave; ++i) {
		val += a * interpNoise3D(vec3(v.x, v.y, v.z));
        v *= 2.;
		a *= 0.5;
    }
	return val;
}

void main()
{
        vec4 noiseInput = fs_Pos;
        float noise = fbm(vec3(noiseInput.x * 0.1, noiseInput.y * cos(u_Tick / 100.) - 1., noiseInput.z * 0.1)); 
        float t = noise + sin(noiseInput.y * 7.0) * 0.1 - .8; 
    // Material base color (before shading)
        vec4 diffuseColor = vec4(207. / 255., 232. / 255., 223. / 255., t);

        // Calculate the diffuse term for Lambert shading
        float diffuseTerm = dot(normalize(fs_Nor), normalize(fs_LightVec));
        // Avoid negative lighting values
        // diffuseTerm = clamp(diffuseTerm, 0, 1);

        float ambientTerm = 0.2;

        float lightIntensity = diffuseTerm + ambientTerm;   //Add a small float value to the color multiplier
                                                            //to simulate ambient lighting. This ensures that faces that are not
                                                            //lit by our point light are not completely black.

        // Compute final shaded color
        out_Col = vec4(diffuseColor.rgb * lightIntensity, t);
}
