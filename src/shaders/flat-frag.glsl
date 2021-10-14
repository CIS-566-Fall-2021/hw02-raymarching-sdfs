#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

// CONSTANTS
int MAX_RAY_STEPS = 128;
float FOV = 45.0;
float EPSILON = 1e-3;
vec3 LIGHT_DIR = vec3(-1.0, 5.0, -5.0);
vec3 LIGHT_DIR2 = vec3(2.0, 5.0, 5.0);
const float HALF_PI = 3.14159 * 0.5;

// OBJ IDS
int TABLE = 0;
int SOUPFACE = 1;
int SOUPEYES = 2;
int BOWL = 3;
int SOUPMOUTH = 4;
int CARROT = 5;
int PEA = 6;

// COLORS
vec3 LIGHT2COLOR = vec3(0.5, 0.0, 0.0);
vec3 LIGHTCOLOR = vec3(0.0,0.0,0.5);

vec3 AMBIENTCOLOR = vec3(0.3);
vec3 SOUPCOLOR = vec3(255.0, 246.0, 196.0) / 255.0;
vec3 TABLECOLOR = vec3(150.0, 13.0, 0.0) / 255.0;
vec3 BOWLCOLOR = vec3(237.0, 236.0, 232.0) / 255.0;
vec3 SOUPEYECOLOR = vec3(255.0, 252.0, 245.0) / 255.0;
vec3 SOUPIRISCOLOR = vec3(235.0, 149.0, 52.0) / 255.0;
vec3 SOUPMOUTHCOLOR = vec3(230.0, 203.0, 165.0) / 255.0;
vec3 SOUPTEXTURECOLOR = vec3(247.0, 216.0, 74.0) / 255.0;
vec3 CARROTCOLOR = vec3(214.0, 94.0, 2.0) / 255.0;
vec3 PEACOLOR = vec3(0.0, 148.0, 7.0) / 255.0;

// SDF CONSTANTS
float S1RADIUS = 7.0;
float S2RADIUS = 6.6;
float SOUPRADIUS = 9.0;
vec3 TABLEDIMS = vec3(20.0, 3.0, 20.0);
vec3 BOUNDINGBOXDIMS = vec3(25.0, 20.0, 25.0);
vec3 CARROTDIMS = vec3(0.8);
float IRISRADIUS = 0.52;
vec2 IRISOFFSET = vec2(0.5, 1.0); // vec2(x, z) not vec2(x, y)

// NOISY SOUP COLOR
//FBM NOISE FIRST VARIANT
float random3D(vec3 p) {
    return sin(length(vec3(fract(dot(p, vec3(161.1, 121.8, 160.2))), 
                            fract(dot(p, vec3(120.5, 161.3, 160.4))),
                            fract(dot(p, vec3(161.4, 161.2, 122.5))))) * 4390.906);
}

float interpolateNoise3D(float x, float y, float z)
{
    int intX = int(floor(x));
    float fractX = fract(x);
    int intY = int(floor(y));
    float fractY = fract(y);
    int intZ = int(floor(z));
    float fractZ = fract(z);

    float v1 = random3D(vec3(intX, intY, intZ));
    float v2 = random3D(vec3(intX + 1, intY, intZ));
    float v3 = random3D(vec3(intX, intY + 1, intZ));
    float v4 = random3D(vec3(intX + 1, intY + 1, intZ));

    float v5 = random3D(vec3(intX, intY, intZ + 1));
    float v6 = random3D(vec3(intX + 1, intY, intZ + 1));
    float v7 = random3D(vec3(intX, intY + 1, intZ + 1));
    float v8 = random3D(vec3(intX + 1, intY + 1, intZ + 1));


    float i1 = mix(v1, v2, fractX);
    float i2 = mix(v3, v4, fractX);

    //mix between i1 and i2
    float i3 = mix(i1, i2, fractY);

    float i4 = mix(v5, v6, fractX);
    float i5 = mix(v7, v8, fractX);

    //mix between i3 and i4
    float i6 = mix(i4, i5, fractY);

    //mix between i3 and i6
    float i7 = mix(i3, i6, fractZ);

    return i7;
}

float fbmNoise(vec3 v)
{
    float total = 0.0;
    float persistence = 0.3;
    float frequency = 1.0;
    float amplitude = 2.0;
    int octaves = 3;

    for (int i = 1; i <= octaves; i++) {
        total += amplitude * interpolateNoise3D(frequency * v.x, frequency * v.y, frequency * v.z);
        frequency *= 2.7;
        amplitude *= persistence;
    }
    return total;
}

float getAnimation() {
    return sin(float(u_Time) * 0.01) * 2.0;
}

vec3 getSoupFaceColor(vec3 pos) {
  //return clamp(fbmNoise(pos), 0.1, 0.3) * SOUPTEXTURECOLOR + SOUPCOLOR;
  vec3 noiseInput = pos + getAnimation();
  float noiseFac = clamp(fbmNoise(noiseInput), 0.0, 1.0);
  return mix(SOUPCOLOR, SOUPTEXTURECOLOR, noiseFac);
}

float random3D2(vec3 p) {
    return sin(length(vec3(fract(dot(p, vec3(6.1, 2.8, 6.2))), 
                            fract(dot(p, vec3(2.5, 6.3, 6.4))),
                            fract(dot(p, vec3(6.4, 6.2, 2.5))))) * 459.0906);
}

float interpolateNoise3D2(float x, float y, float z)
{
    int intX = int(floor(x));
    float fractX = fract(x);
    int intY = int(floor(y));
    float fractY = fract(y);
    int intZ = int(floor(z));
    float fractZ = fract(z);

    float v1 = random3D2(vec3(intX, intY, intZ));
    float v2 = random3D2(vec3(intX + 1, intY, intZ));
    float v3 = random3D2(vec3(intX, intY + 1, intZ));
    float v4 = random3D2(vec3(intX + 1, intY + 1, intZ));

    float v5 = random3D2(vec3(intX, intY, intZ + 1));
    float v6 = random3D2(vec3(intX + 1, intY, intZ + 1));
    float v7 = random3D2(vec3(intX, intY + 1, intZ + 1));
    float v8 = random3D2(vec3(intX + 1, intY + 1, intZ + 1));


    float i1 = mix(v1, v2, fractX);
    float i2 = mix(v3, v4, fractX);

    //mix between i1 and i2
    float i3 = mix(i1, i2, fractY);

    float i4 = mix(v5, v6, fractX);
    float i5 = mix(v7, v8, fractX);

    //mix between i3 and i4
    float i6 = mix(i4, i5, fractY);

    //mix between i3 and i6
    float i7 = mix(i3, i6, fractZ);

    return i7;
}

float fbmNoise2(vec3 v) {
    float total = 0.0;
    float persistence = 0.5;
    float frequency = 5.0;
    float amplitude = 5.0;
    int octaves = 5;

    for (int i = 1; i <= octaves; i++) {
        total += amplitude * interpolateNoise3D2(frequency * v.x, frequency * v.y, frequency * v.z);
        frequency *= 3.6;
        amplitude *= persistence;
    }
    return total;
}

// SCENE STRUCTS
struct Ray 
{
    vec3 origin;
    vec3 direction;
};

struct Intersection 
{
    vec3 position;
    vec3 normal;
    float distance_t;
    int objectHit;
    int material_id;
};

// SDF FUNCTIONS
float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

float sdCappedTorus(in vec3 p, in vec2 sc, in float ra, in float rb)
{
  p.x = abs(p.x);
  float k = (sc.y*p.x>sc.x*p.y) ? dot(p.xy,sc) : length(p.xy);
  return sqrt( dot(p,p) + ra*ra - 2.0*ra*k ) - rb;
}

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdSolidAngle(vec3 p, vec2 c, float ra)
{
  // c is the sin/cos of the angle
  vec2 q = vec2( length(p.xz), p.y );
  float l = length(q) - ra;
  float m = length(q - c*clamp(dot(q,c),0.0,ra) );
  return max(l,m*sign(c.y*q.x-c.x*q.y));
}

float sdEllipsoid( vec3 p, vec3 r )
{
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return k0*(k0-1.0)/k1;
}

float sdPyramid( vec3 p, float h)
{
  float m2 = h*h + 0.25;
    
  // tweaked values to resize the bottom o the nose
  p.xz = abs(p.xz);
  p.xz = (p.z>p.x) ? p.zx : p.xz;
  p.xz -= 0.5;

  vec3 q = vec3( p.z, h*p.y - 0.5*p.x, h*p.x + 0.5*p.y);
   
  float s = max(-q.x,0.0);
  float t = clamp( (q.y-0.5*p.z)/(m2+0.25), 0.0, 1.0 );
    
  float a = m2*(q.x+s)*(q.x+s) + q.y*q.y;
  float b = m2*(q.x+0.5*t)*(q.x+0.5*t) + (q.y-m2*t)*(q.y-m2*t);
    
  float d2 = min(q.y,-q.x*m2-q.y*0.5) > 0.0 ? 0.0 : min(a,b);
    
  return sqrt( (d2+q.z*q.z)/m2 ) * sign(max(q.z,-p.y));
}

float sdCappedCylinder( vec3 p, float h, float r )
{
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

float sdVerticalCapsule( vec3 p, float h, float r )
{
  p.y -= clamp( p.y, 0.0, h );
  return length( p ) - r;
}

float rounding( in float d, in float h )
{
    return d - h;
}

float planeSDF(vec3 queryPos, float height)
{
    return height - queryPos.y;
}

// CSG FUNCTIONS
// Once again courtesy of IQ

float opUnion( float d1, float d2 ) { return min(d1,d2); }

float opSubtraction( float d1, float d2 ) { return max(-d1,d2); }

float opIntersection( float d1, float d2 ) { return max(d1,d2); }

// SMOOTH CSG FUNCTIONS
// Once again thank you IQ

float opSmoothUnion( float d1, float d2, float k ) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); }

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); }

float opSmoothIntersection( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) + k*h*(1.0-h); }

// TRANSFORMATION FUNCTIONS
// From cis 462

mat4 rotateY(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    return mat4(
        vec4(c, 0, s, 0),
        vec4(0, 1, 0, 0),
        vec4(-s, 0, c, 0),
        vec4(0, 0, 0, 1)
    );
}

mat4 rotateX(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    return mat4(
        vec4(1, 0, 0, 0),
        vec4(0, c, -s, 0),
        vec4(0, s, c, 0),
        vec4(0, 0, 0, 1)
    );
}

mat4 rotateZ(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    return mat4(
        vec4(c, -s, 0, 0),
        vec4(s, c, 0, 0),
        vec4(0, 0, 1, 0),
        vec4(0, 0, 0, 1)
    );
}

// COMMON FUNCTIONS
float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

//SOUP FUNCTIONS

float faceSDF(vec3 queryPos, inout int objHit) {
    float soupBase = sdSolidAngle(queryPos + vec3(0.0, 7.0, 0.0), vec2(0.8), SOUPRADIUS);

    // soup face construction

    // left eyelid
    mat4 lEyeRotMat = rotateZ(0.0 * 3.14159 / 180.0) * rotateX(9.5 * 3.14159 / 180.0) * rotateY(0.0 * 3.14159 / 180.0);
    vec4 lEyePos = vec4(queryPos - vec3(-0.5, 1.5, 2.0), 1.0);
    vec4 lEyelidSubtractPos = vec4(vec3(lEyePos) - vec3(0.4, 0.1, 0.0), 1.0);

    // right eyelid
    mat4 rEyeRotMat = rotateZ(0.0 * 3.14159 / 180.0) * rotateX(-9.5 * 3.14159 / 180.0) * rotateY(0.0 * 3.14159 / 180.0);
    vec4 rEyePos = vec4(queryPos - vec3(-0.5, 1.5, -2.0), 1.0);
    vec4 rEyelidSubtractPos = vec4(vec3(rEyePos) - vec3(0.4, 0.1, 0.0), 1.0);

    //each eyelid subtracted
    float soupLEyelid = sdEllipsoid(vec3(lEyeRotMat * lEyePos), vec3(1.0, 0.5, 1.6));
    float soupLEyelidSubtract = sdEllipsoid(vec3(lEyeRotMat * lEyelidSubtractPos), vec3(1.1, 0.5, 1.6));
    soupLEyelid = opSubtraction(soupLEyelidSubtract, soupLEyelid);
    soupLEyelid = opSmoothUnion(soupLEyelid, soupBase, 0.1);

    float soupREyelid = sdEllipsoid(vec3(rEyeRotMat * rEyePos), vec3(1.0, 0.5, 1.6));
    float soupREyelidSubtract = sdEllipsoid(vec3(rEyeRotMat * rEyelidSubtractPos), vec3(1.1, 0.5, 1.6));
    soupREyelid = opSubtraction(soupREyelidSubtract, soupREyelid);
    soupREyelid = opSmoothUnion(soupREyelid, soupBase, 0.1);

    // eyeballs translated slightly down
    float soupLEyeBall = sdEllipsoid(vec3(lEyeRotMat * lEyePos) + vec3(0.0, 0.05, 0.1), vec3(1.0, 0.5, 1.4));
    float soupREyeBall = sdEllipsoid(vec3(rEyeRotMat * rEyePos) + vec3(0.0, 0.05, -0.1), vec3(1.0, 0.5, 1.4));
    
    // nose got oddly rotated??
    mat4 noseRotMat = rotateZ(100.0 * 3.14159 / 180.0) * rotateX(45.0 * 3.14159 / 180.0);
    float nose = sdPyramid((vec3(noseRotMat * vec4(queryPos - vec3(2.0, 1.9, 0.0), 1.0))), 3.0);
    nose = rounding(nose, 0.1);

    //cheek lines
    float lcheek = sdfSphere(queryPos, vec3(1.7, -1.5, 2.5), 2.9);
    float lCheekFaceBlend = opSmoothUnion(soupBase, lcheek, 0.5);

    float rcheek = sdfSphere(queryPos, vec3(1.7, -1.5, -2.5), 2.9);
    float rCheekFaceBlend = opSmoothUnion(soupBase, rcheek, 0.5);

    //lips
    float toplip = sdEllipsoid(queryPos - vec3(3.2, 0.5, 0.0), vec3(0.7, 1.3, 1.5));
    float bottomlip = sdEllipsoid(queryPos - vec3(3.9, 0.05, 0.0), vec3(0.7, 1.3, 1.5));
    float smoothlip = opSmoothUnion(toplip, bottomlip, 0.5);

    float smoothlip2 = opSmoothUnion(soupBase, smoothlip, 0.2);
    
    float t = soupBase;
    objHit = SOUPFACE;
    t = min(t, soupLEyelid);
    t = min(t, soupREyelid);
    t = min(t, soupLEyeBall);
    t = min(t, soupREyeBall);
    if (t == soupLEyeBall || t == soupREyeBall) {
      objHit = SOUPEYES;
    }
    t = min(t, nose);
    t = min(t, lCheekFaceBlend);
    t = min(t, rCheekFaceBlend);
    t = min(t, smoothlip);
    if (t == smoothlip) {
      objHit = SOUPMOUTH;
    }
    t = min(t, smoothlip2);

    return t;//mix(t, soupBase, clamp(cos(u_Time * 0.1), 0.0, 1.0));
    //return mix(t, soupBase, clamp(cos(u_Time * 0.1), 0.0, 1.0));
}

float sceneSDF(vec3 queryPos, inout int objHit) 
{
  float boundingBoxDist = sdBox(queryPos, BOUNDINGBOXDIMS);

  if (boundingBoxDist < EPSILON) {
    float table = sdBox(queryPos + vec3(0.0, 8.0, 0.0), TABLEDIMS);
    
    float sphere1 = sdfSphere(queryPos, vec3(0.0), S1RADIUS); 
    float innerSphere1 = sdfSphere(queryPos, vec3(0.0), S2RADIUS);
    float sphereSlicePlane = planeSDF(queryPos + vec3(0.0, 5.0, 0.0), 5.0);

    float bowl = opSubtraction(innerSphere1, sphere1);
    bowl = opSubtraction(sphereSlicePlane, bowl);

    //When soup is not being crazy -- Credit to Sam for helping me figure this out
    float normalSoup = sdfSphere(queryPos, vec3(0.0), S1RADIUS);
    normalSoup = max(normalSoup, queryPos.y + 0.5);

    //mix flat soup with OWO soup
    float face = mix(faceSDF(queryPos, objHit), normalSoup, clamp(cos(u_Time * 0.05), 0.0, 1.0));

    //soup bits
    //vec3 inputPosition = vec3(queryPos.x, sin(u_Time * 0.001), queryPos.z);
    float carrot1 = sdBox(vec3(rotateZ(40.0 * 3.14159 / 180.0) * rotateX(30.0 * 3.14159 / 180.0) * (vec4(queryPos, 1.0) + vec4(-1.0, 0.5, 5.0, 1.0))), CARROTDIMS);
    float carrot2 = sdBox(vec3(rotateX(50.0 * 3.14159 / 180.0) * (vec4(queryPos, 1.0) + vec4(3.0, 0.5, 4.0, 1.0))), CARROTDIMS * 0.7);
    float carrot3 = sdBox(vec3(rotateY(70.0 * 3.14159 / 180.0) * rotateZ(30.0 * 3.14159 / 180.0) * (vec4(queryPos, 1.0) + vec4(-2.0, 0.5, -4.0, 1.0))), CARROTDIMS * 0.7);
    float carrotSmooth = opSmoothUnion(carrot1, face, 0.3);
    carrotSmooth = opSmoothUnion(carrot2, carrotSmooth, 0.3);
    carrotSmooth = opSmoothUnion(carrot3, carrotSmooth, 0.3);

    float pea1 = sdfSphere(vec3(queryPos + vec3(4.0, 0.5, 0.0)), vec3(0.0), 0.5);
    float pea2 = sdfSphere(vec3(queryPos + vec3(-5.0, 0.5, 3.0)), vec3(0.0), 0.5);
    float pea3 = sdfSphere(vec3(queryPos + vec3(-3.0, 0.5, -3.0)), vec3(0.0), 0.5);
    float pea4 = sdfSphere(vec3(queryPos + vec3(3.0, 0.5, 3.0)), vec3(0.0), 0.5);

    /* the max function slices sphere in half
    * courtesy of IQ's demo here: https://www.shadertoy.com/view/MlcBDj
    */
    float t = min(table, bowl);
    t = min(t, face);
    t = min(t, carrot1);
    t = min(t, carrot2);
    t = min(t, carrot3);
    t = min(t, pea1);
    t = min(t, pea2);
    t = min(t, pea3);
    t = min(t, pea4);

    if (t == table) {
      objHit = TABLE;
    }
    if (t == bowl) {
      objHit = BOWL;
    }
    if (t == carrot1 || t == carrot2 || t == carrot3) {
      objHit = CARROT;
    }
    if (t == pea1 || t == pea2 || t == pea3 || t == pea4) {
      objHit = PEA;
    }

    t = min(t, carrotSmooth);

    return t;
  }
  objHit = -1;
  return boundingBoxDist;
}
// SHADOW
float shadow(vec3 rayOrigin, inout int objHit, vec3 rayDirection, float min_t, float max_t) {
  for (float t = min_t; t < max_t; ) {
    float h = sceneSDF(rayOrigin + rayDirection * t, objHit);
    if (h < EPSILON) {
      return 0.0;
    }
    t += h;
  }
  return 1.0;
}

float softShadow(vec3 rayOrigin, inout int objHit, vec3 rayDirection, float min_t, float max_t, float k) {
  float res = 1.0;
  for (float t = min_t; t < max_t; ) {
    float h = sceneSDF(rayOrigin + rayDirection * t, objHit);
    if (h < EPSILON) {
      return 0.0;
    }
    res = min(res, k * h / t);
    t += h;
  }
  return 1.0;
}

Ray getRay(vec2 ndcPos) {
  Ray r;

  vec3 look = normalize(u_Ref - u_Eye);
  vec3 cameraRight = normalize(cross(look, u_Up));
  vec3 cameraUp = cross(cameraRight, look);

  float aspectRatio = u_Dimensions.x / u_Dimensions.y;

  float len = length(u_Ref - u_Eye);
  vec3 screenV = cameraUp * len * tan(FOV);
  vec3 screenH = cameraRight * len * aspectRatio * tan(FOV);

  vec3 screenPos = u_Ref + fs_Pos.x * screenH + fs_Pos.y * screenV;

  r.direction = normalize(screenPos - u_Eye);
  r.origin = u_Eye;

  return r; 
}

vec3 estimateNormal(vec3 p, inout int objHit)
{
    vec2 d = vec2(0.0, EPSILON);
    float x = sceneSDF(p + d.yxx, objHit) - sceneSDF(p - d.yxx, objHit);
    float y = sceneSDF(p + d.xyx, objHit) - sceneSDF(p - d.xyx, objHit);
    float z = sceneSDF(p + d.xxy, objHit) - sceneSDF(p - d.xxy, objHit);
    
    return normalize(vec3(x,y,z));
}

Intersection getRaymarchedIntersection(vec2 uv) {
  Intersection intersection;
  intersection.distance_t = -1.0;

  Ray r = getRay(uv);
  float dist_t = 0.0;
  for (int st; st < MAX_RAY_STEPS; ++st) {
    vec3 queryPoint = r.origin + r.direction * dist_t;
    int objHit;
    float distFromScene = sceneSDF(queryPoint, objHit);

    if (distFromScene < EPSILON) {
      //we've hit something
      intersection.position = queryPoint;
      intersection.distance_t = distFromScene;
      intersection.objectHit = objHit;
      intersection.normal = estimateNormal(queryPoint, objHit);
      return intersection;
    }

    dist_t += distFromScene;
  }

  return intersection;
}

//blinn phong specular intensity
float bpSpecIntensity(Intersection inter) {
  vec3 V = normalize(vec3(u_Eye) - vec3(inter.position));
  vec3 L = normalize(LIGHT_DIR - vec3(inter.position));
  vec4 avg_h = vec4((V + L) / 2.0, 0.0);
  float specIntensity = max(pow(clamp(dot(avg_h, vec4(inter.normal, 0.0)), 0.0, 1.0), 10.0), 0.0);

  vec3 L2 = normalize(LIGHT_DIR2 - vec3(inter.position));
  vec4 avg_h2 = vec4((V + L2) / 2.0, 0.0);
  specIntensity += max(pow(clamp(dot(avg_h2, vec4(inter.normal, 0.0)), 0.0, 1.0), 10.0), 0.0);

  //specIntensity *= LIGHT2COLOR;
  return specIntensity;
}

vec3 getSceneColor(vec2 uv) {
  Intersection intersection = getRaymarchedIntersection(uv);
  if (intersection.distance_t > 0.0)
  { 
      // CALCULATE ALL LIGHTING
      // LAMBERTIAN LIGHTING
      float diffuseTerm = dot(intersection.normal, normalize(LIGHT_DIR));
      float ambientTerm = 0.1;

      diffuseTerm = clamp(diffuseTerm, 0.0, 1.0);

      float lambertIntensity = diffuseTerm + ambientTerm;

      // CALCULATE ALL COLOR
      int shadowHitObject;
      //float shadowFactor = shadow(intersection.position, shadowHitObject, normalize(LIGHT_DIR), 0.1, 7.0);
      float shadowFactor = softShadow(intersection.position, shadowHitObject, normalize(LIGHT_DIR), 0.1, 7.0, 0.5);
      vec3 materialColor = AMBIENTCOLOR;
      if (intersection.objectHit == SOUPFACE) {
        materialColor = getSoupFaceColor(intersection.position);
        // CALCULATE BLINN PHONG LIGHTING FOR SOUP FACE
        float specIntensity = bpSpecIntensity(intersection);
        materialColor = getSoupFaceColor(intersection.position) * (lambertIntensity + specIntensity);
      } else if (intersection.objectHit == TABLE) {
        materialColor = TABLECOLOR * lambertIntensity;
      } else if (intersection.objectHit == BOWL) {
        materialColor = BOWLCOLOR * lambertIntensity;
      } else if (intersection.objectHit == SOUPEYES) {

        // POLKA DOT PATTERN 
        // courtesy of https://weber.itn.liu.se/~stegu/webglshadertutorial/shadertutorial.html 
        float frequency = 0.5;
        vec2 nearest = 2.0 * fract(frequency * (vec2(intersection.position.x, intersection.position.z) - IRISOFFSET)) - 1.0;
        float dist = length(nearest);
        float radius = IRISRADIUS;
        materialColor = mix(SOUPIRISCOLOR, SOUPEYECOLOR, step(radius, dist)) * lambertIntensity;
      } else if (intersection.objectHit == SOUPMOUTH) {
        materialColor = mix(SOUPMOUTHCOLOR, SOUPCOLOR, intersection.position.y) * lambertIntensity;
      } else if (intersection.objectHit == CARROT) {
        materialColor = CARROTCOLOR * lambertIntensity;
      } else if (intersection.objectHit == PEA) {
        materialColor = PEACOLOR * lambertIntensity;
      }
      vec3 finalcolor = materialColor * shadowFactor;
      return finalcolor;
    }
  return vec3(clamp(fbmNoise2(vec3(uv, 1.0) + getAnimation()), 0.0, 0.06));
}

//MAIN
void main() {
  vec3 colorOutput = getSceneColor(fs_Pos);
  out_Col = vec4(colorOutput, 1.0);
}
