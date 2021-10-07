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

// SDF CONSTANTS
float S1RADIUS = 7.0;
float S2RADIUS = 6.6;
float SOUPRADIUS = 9.0;
vec3 TABLEDIMS = vec3(50.0, 3.0, 20.0);

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

float sdCapsule( vec3 p, vec3 a, vec3 b, float r )
{
  vec3 pa = p - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
}

float rounding( in float d, in float h )
{
    return d - h;
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

float faceSDF(vec3 queryPos) {
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
    smoothlip = opSmoothUnion(soupBase, smoothlip, 0.2);
    
    //Irises
    float riris = sdfSphere(vec3(0.0), vec3(lEyePos), 3.0);

    //chicken soup bits
    float t = soupBase;
    t = min(t, soupLEyelid);
    t = min(t, soupREyelid);
    t = min(t, soupLEyeBall);
    t = min(t, soupREyeBall);
    t = min(t, nose);
    t = min(t, lCheekFaceBlend);
    t = min(t, rCheekFaceBlend);
    t = min(t, smoothlip);

    return t;//mix(t, soupBase, clamp(cos(u_Time * 0.1), 0.0, 1.0));
}

float sceneSDF(vec3 queryPos) 
{
    float table = sdBox(queryPos + vec3(0.0, 8.0, 0.0), TABLEDIMS);
    float sphere1 = sdfSphere(queryPos, vec3(0.0), S1RADIUS); 
    float innerSphere1 = sdfSphere(queryPos, vec3(0.0), S2RADIUS);
    float bowl = opSubtraction(innerSphere1, sphere1);

    //When soup is not being crazy -- Credit to Sam for helping me figure this out
    float normalSoup = sdfSphere(queryPos, vec3(0.0), S1RADIUS);
    normalSoup = max(normalSoup, queryPos.y + 0.5);

    //mix flat soup with OWO soup
    float face = mix(faceSDF(queryPos), normalSoup, clamp(cos(u_Time * 0.1), 0.0, 1.0));
    
    /* the max function slices sphere in half
    * courtesy of IQ's demo here: https://www.shadertoy.com/view/MlcBDj
    */
    float t = max(min(table, bowl), queryPos.y);
    t = min(t, face);

    return t;
}

// SHADOW
float shadow(vec3 rayOrigin, vec3 rayDirection, float min_t, float max_t) {
  for (float t = min_t; t < max_t; ) {
    float h = sceneSDF(rayOrigin + rayDirection * t);
    if (h < EPSILON) {
      return 0.0;
    }
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

vec3 estimateNormal(vec3 p)
{
    vec2 d = vec2(0.0, EPSILON);
    float x = sceneSDF(p + d.yxx) - sceneSDF(p - d.yxx);
    float y = sceneSDF(p + d.xyx) - sceneSDF(p - d.xyx);
    float z = sceneSDF(p + d.xxy) - sceneSDF(p - d.xxy);
    
    return normalize(vec3(x,y,z));
}

Intersection getRaymarchedIntersection(vec2 uv) {
  Intersection intersection;
  intersection.distance_t = -1.0;

  Ray r = getRay(uv);
  float dist_t = 0.0;
  for (int st; st < MAX_RAY_STEPS; ++st) {
    vec3 queryPoint = r.origin + r.direction * dist_t;
    float distFromScene = sceneSDF(queryPoint);

    if (distFromScene < EPSILON) {
      //we've hit something
      intersection.position = queryPoint;
      intersection.distance_t = distFromScene;
      intersection.normal = estimateNormal(queryPoint);
      return intersection;
    }

    dist_t += distFromScene;
  }

  return intersection;
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
        float shadowFactor = shadow(intersection.position, normalize(LIGHT_DIR), 0.1, 7.0);
        vec3 color = vec3(1.0) * shadowFactor;
        return color * lambertIntensity;
        //return vec3(shadowFactor);
    }
    return vec3(0.0);
}

//MAIN
void main() {
  vec3 colorOutput = getSceneColor(fs_Pos);
  out_Col = vec4(colorOutput, 1.0);
}
