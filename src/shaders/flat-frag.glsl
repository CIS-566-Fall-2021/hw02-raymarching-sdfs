#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;
const int MAX_RAY_STEPS = 128;
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
    int object;
    int material_id;
};

#define RADIANS (3.14158 / 180.0)
#define SHADOW_HARDNESS 10.0
#define RAY_LENGTH 50.f
#define groundPlane sdHeightField(pos, 2.f, vec3(0.f, -10.0, 1.0), rotateX(-10.0 * (3.14158 / 180.0)))
#define frontRocks rock(pos, vec3(0.f, 0.25f, 1.f), identity())
#define rotateWhole sdBridge(pos, vec3(-1.f, 0.f, 3.f), rotateY(30.f * RADIANS))
#define frontBigSquare sdRoundBox(pos, vec3(1.5f, .0f, -2.f), rotateY(25.0 * (3.14158 / 180.0)), vec3(.33f, 2.3f, .0001f), .1)
#define testSphere sdfSphere(pos, vec3(0.0, 0.0, 0.0), 1.0)



//https://inspirnathan.com/posts/54-shadertoy-tutorial-part-8/
// Rotation matrix around the X axis.
mat3 rotateX(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(1, 0, 0),
        vec3(0, c, -s),
        vec3(0, s, c)
    );
}

// Rotation matrix around the Y axis.
mat3 rotateY(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(c, 0, s),
        vec3(0, 1, 0),
        vec3(-s, 0, c)
    );
}

// Rotation matrix around the Z axis.
mat3 rotateZ(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(c, -s, 0),
        vec3(s, c, 0),
        vec3(0, 0, 1)
    );
}

// Identity matrix.
mat3 identity() {
    return mat3(
        vec3(1, 0, 0),
        vec3(0, 1, 0),
        vec3(0, 0, 1)
    );
}


vec3 opCheapBend(in vec3 p, float k)
{
   k = .8;
    float c = cos(k*p.y);
    float s = sin(k*p.y);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
} 


vec3 opSymX( in vec3 p)
{
    p.z = abs(p.z);
    return p;
}


vec3 opRepLim(in vec3 p, in float c, in vec3 l)
{
    vec3 q = p-c*clamp(round(p/c),-l,l);
    return q;
}
float opSmoothUnion( float d1, float d2, float k ) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); }

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); }

float opSmoothIntersection( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) + k*h*(1.0-h); }

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float easeInQuadratic(float f)
{
  return f * f;
}

float sdCappedTorus(in vec3 p, in vec2 sc, in float ra, in float rb)
{
  p.x = abs(p.x);
  float k = (sc.y*p.x>sc.x*p.y) ? dot(p.xy,sc) : length(p.xy);
  return sqrt( dot(p,p) + ra*ra - 2.0*ra*k ) - rb;
}

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}
//capsule
float sdCapsule( vec3 p, vec3 a, vec3 b, float r )
{
  vec3 pa = p - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
}
//cylinder
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
float sdBox( vec3 p, vec3 offset, mat3 transform, vec3 b )
{
  p = (p - offset) *transform;
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdRoundBox( vec3 p, vec3 offset, mat3 transform, vec3 b, float r )
{
  p = (p - offset) *transform;
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float sdCone( vec3 p, vec2 c, float h, vec3 offset, mat3 transform)
{
  p = (p - offset) * transform;
  float q = length(p.xz);
  return max(dot(c.xy,vec2(q,p.y)),-h-p.y);
}

float sdVerticalCables(vec3 p, vec3 offset, mat3 transform)
{
    p = (p - offset) *transform * (1.f /  vec3(1.f, 1.f, 1.f));
    vec3 newP = opRepLim(p, .9f, vec3(13.f, 0.f, 0.f));
    float pole = sdVerticalCapsule(newP, 3.f, .01f);
    return pole;
}
float extraCable(vec3 p)
{
  vec3 newP = (p - vec3(-3.95f, 9.5f, 7.5f)) * rotateY(120.f * RADIANS) * rotateZ(180.f * RADIANS) * (1.f /  vec3(1.f, 1.2f, 1.f));
  float an = 42.f * RADIANS;
  vec2 c = vec2(sin(an),cos(an));
  float cable = sdCappedTorus(newP, c, 8.f, .01);
  vec3  newP2 = (p - vec3(-3.4f, 9.5f, 7.9f)) * rotateY(120.f * RADIANS) * rotateZ(180.f * RADIANS) * (1.f /  vec3(1.f, 1.2f, 1.f));
  float cable2 = sdCappedTorus(newP2, c, 8.f, .01);
  
  //cable = min(cable, subtractSphere);
  return min(cable, cable2);
}
float sdCables(vec3 p, vec3 offset, mat3 transform)
{
    p = (p - offset) *transform * (1.f /  vec3(1.08f, 1.f, 1.f));
    float an = 42.f * RADIANS;
    vec2 c = vec2(sin(an),cos(an));
   // vec3 newP = opRepLim(p, .5f, vec3(0.f, 0.f, 1.f));
    vec3 newP = opSymX(p);
    float topCable = sdCappedTorus(p, c, 13.f,.03f);
    topCable = smin(topCable, sdVerticalCables(p, vec3(0.f, 10.f, 0.f), identity()), .08);
    topCable = smin(topCable, sdVerticalCables(p, vec3(0.f, 10.f, .5f), identity()), .08);
    topCable = smin(topCable, sdCappedTorus((p - vec3(0.f, 0.f, .5f)), c, 13.f, .03f), .08);
   // topCable = min(topCable, sdCappedTorus((p - vec3(5.f, 0.f, 0.f)), c, 13.f, .03f));
    //subraction sphere
    p = p * (1.f / vec3(1.6f, 1.f, 1.f));
    float subtractSphere = sdfSphere(p, vec3(0.f, 6.6f, 0.f), 6.f);
    float subtractSphere2 = sdfSphere(p, vec3(-7.8f, 10.1f, 0.5f), 1.6f);
    //float subtractSphere2 = sdfSphere((p + vec3(), vec3(0.f, 6.6f, 0.f), 6.f);
    topCable = opSmoothSubtraction(subtractSphere, topCable, .25);
    float topCable2 = opSmoothSubtraction(subtractSphere2, topCable, .25);
    //topCable = min(subtractSphere2, topCable);
    return topCable2;   
}
float sdHeightField(vec3 pos, float planeHeight, vec3 offset, mat3 transform)
{
  float waveHeight = 0.2;
  float waveFrequency = .50f;
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
 
  //smoothstep
  
  float newZ = pos.y + cos(pos.z + easeInQuadratic(u_Time * .01)) * .1;
  float newX = pos.y + cos(pos.x + (u_Time * .1)) * .1;
  
  return mix(mix(pos.y, newZ, .2), newZ, .6);
  //return (pos.y - cos(u_Time * .01 * waveFrequency * (pos.x - pos.z)) * waveHeight);

}
float rock(vec3 pos, vec3 offset, mat3 transform)
{
   pos = (pos - offset) *transform * (1.f /  vec3(1.0f, 1.f, 1.f));
   float rock = sdRoundBox(pos, vec3(-2.f, -1.5f, 6.5f), rotateZ(-2.f * RADIANS) * rotateX(-10.f * RADIANS), vec3(.5f, .5f, 1.f), .15);
   float curvePart = sdRoundBox(pos, vec3(-1.f, -1.7f, 6.5f), rotateZ(20.f * RADIANS) * rotateX(-10.f * RADIANS), vec3(.6f, .5f, 1.f), .15);
   return smin(rock, curvePart, .25);
}
float sdRoadSide(vec3 pos, vec3 offset, mat3 transform)
{
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  float bottom = sdBox(pos, vec3(0.25f, -1.15f, -12.f), identity(), vec3(.03f, .02f, 15.f));
  return bottom;
}
float sdRoad(vec3 pos, vec3 offset, mat3 transform)
{
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  float road = sdBox(pos, vec3(0.f, -.99f, -11.f), identity(), vec3(.30, .02f, 13.0));
  road = min(road, sdRoadSide(pos, vec3(0.f), identity()));
  return road;
}
float sdCross(vec3 pos, vec3 offset, mat3 transform)
{
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  float segment1 = sdBox(pos, vec3(0.f, -1.4f, 0.f), rotateZ(55.0 * RADIANS), vec3(.03, .4, .03));
  float segment2 = sdBox(pos, vec3(0.f, -1.4f, 0.f), rotateZ(-55.0 * RADIANS), vec3(.03, .4, .03));
  float segment3 = sdBox(pos, vec3(0.f, -1.7f, 0.f), rotateZ(-90.0 * RADIANS), vec3(.03, .4, .03));
  float cross1 = min(segment1, segment2);
  float bottom = min(cross1, segment3);
  return bottom;
}
float sdBridgeEnd(vec3 pos, vec3 offset, mat3 transform)
{
  vec3 p = pos;
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  float bigBase = sdRoundBox(pos, vec3(0.f, -.15, 0.f), identity(), vec3(.33f, 2.5f, .0001f), .08);
  float topSquare = sdRoundBox(pos, vec3(0.f, 1.9f, 0.0), identity(), vec3(.15, .15, .01), .1);
  float top2Square = sdRoundBox(pos, vec3(0.f, 1.15f, 0.0), identity(), vec3(.15, .15, .01), .1);
  float middleSquare = sdRoundBox(pos, vec3(0.f, .3f, 0.0), identity(), vec3(.15, .21, .01), .1);
  float bottomSquare = sdRoundBox(pos, vec3(0.f, -1.55f, 0.0), identity(), vec3(.15, 1.1, .01), .1);
  float subtractTop2 = opSmoothSubtraction(middleSquare, bigBase, .25);
  float subtractTop1 = opSmoothSubtraction(topSquare, subtractTop2, .25);
  float subtractTop  = opSmoothSubtraction(top2Square, subtractTop1, .25);
  float subtractBottom = opSmoothSubtraction(bottomSquare, subtractTop, .25);
  float addCross = min(subtractBottom, sdCross(pos, vec3(0.f, 0.f, 0.f), identity()));
  float addCross2 = min(addCross, sdCross(pos, vec3(0.f, -.6f, 0.f), identity()));
  return addCross2;
  
}

float sdBridge(vec3 pos, vec3 offset, mat3 transform)
{
  vec3 p = pos;
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  float bridgeFront = sdBridgeEnd(pos, vec3(0.f), identity());
  float bridgeBack = sdBridgeEnd(pos, vec3(0.f, 0.f, -20.f), identity());
  float bridge = min(min(bridgeFront, bridgeBack), sdRoad(pos, vec3(0.f), identity()));
  bridge = min(bridge, sdCables(pos, vec3(0.3f, 12.f, -9.5f), rotateX(-180.f * RADIANS) * rotateY(90.f * RADIANS)));
  return bridge;
}


float sceneSDF(vec3 pos)
{
  float t = groundPlane;
  //t = min(t, frontBigSquare);
  //t = min(t, bigBase);
  t = min(t, rotateWhole);
  t = min(t, frontRocks);
  t = min(t, extraCable(pos));
  return t;
}
void sceneSDF(vec3 pos, out float t, out int obj, vec3 lightPos) 
{
    t = groundPlane;
    float t2;
    obj = 0;

    if((t2 = rotateWhole) < t)
    {
      t = t2;
    } 
    if((t2 = frontRocks) < t)
    {
      t = t2;
    } 
    if((t2 = extraCable(pos)) < t)
    {
      t = t2;
    }
    //return 
    
}

float softShadow(vec3 dir, vec3 origin, float min_t, float k) {
    float res = 1.0;
    for(float t = min_t; t < 128.f;) {
        float m = sceneSDF(origin + t * dir);
        if(m < 0.001) {
           return 0.0;
         } 
        res = min(res, k * m / t);
        t += m;
    }
    return res;
}

Ray getRay(vec2 uv)
{
    Ray r;

    float sx = uv.x;
    float sy = uv.y;
    vec3 localForward = normalize(u_Ref - u_Eye);
    vec3 localRight = cross(localForward, vec3(0.f, 1.f, 0.f));
    vec3 localUp = cross(localRight, localForward);
    //vec3 localUp = vec3(u_Up);
    float len = length(u_Ref - u_Eye);
    float fov = 45.0;
    fov = fov * (3.14159265358972 / 180.f);
    float tant = tan(fov/2.f);
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 V = normalize(localUp) * len * tant;

    vec3 H =  normalize(localRight) * len * aspect_ratio * tant;


    vec3 p = u_Ref + sx * H + sy * V;
    //p = normalize(p);
    vec3 d = normalize(p - u_Eye);
    r.origin = u_Eye;
    r.direction = d; 
  
   
    return r;
}


vec3 estimateNormal(vec3 p)
{
  vec2 d = vec2(0., .1);
  float x = sceneSDF(p + d.yxx) - sceneSDF(p - d.yxx);
  float y = sceneSDF(p + d.xyx) - sceneSDF(p - d.xyx);
  float z = sceneSDF(p + d.xxy) - sceneSDF(p - d.xxy);

  return normalize(vec3(x, y, z));
}
Intersection getRaymarchedIntersection(vec2 uv)
{
    Intersection intersection;    
    intersection.distance_t = -1.0;

    Ray r = getRay(uv);
    float distancet = 0.f;

    for(int step; step < MAX_RAY_STEPS; step++)
    {
      if(distancet > RAY_LENGTH)
      {
        return intersection;
      }
      vec3 point = r.origin + r.direction * distancet;
      float currDistance;
      int obj;
      vec3 lightPos = vec3(0.f);
      sceneSDF(point, currDistance, obj, lightPos);
      if(currDistance < 0.001)
      {
        //wohoo intersection
        intersection.distance_t = currDistance;
        intersection.normal = estimateNormal(point);
        intersection.position = point;
        return intersection;
      
      }
      distancet += currDistance;
    }
    return intersection;
}

vec3 getSceneColor(vec2 uv, vec3 lightPos)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    if (intersection.distance_t > 0.0)
    { 
         vec3 diffuseCol = vec3(.8f, .8f, .8f);
         float shadow = softShadow(lightPos, intersection.position, .01, 10.f);
         float lambert = clamp(dot(intersection.normal, lightPos), 0.0, 1.0) + 0.30;
         return diffuseCol * lambert * shadow;
         //return intersection.normal;
    }
    return vec3(.30);
}


void main() {
vec2 uv = fs_Pos;

  Ray r = getRay(fs_Pos);

  //out_Col = vec4(0.5 * (r.direction + vec3(1.0, 1.0, 1.0)), 1.0);
  vec3 lightPos = vec3(5.0, 1.0, -1.0);
  out_Col = vec4(getSceneColor(uv, lightPos), 1.f);
  //out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
}
