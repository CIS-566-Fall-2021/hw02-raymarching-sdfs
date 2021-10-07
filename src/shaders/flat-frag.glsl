#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 128;
const float FOV = 45.0;
const float EPSILON = 1e-5;

const vec3 EYE = vec3(0.0, 0.0, 10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(-1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const vec3 LIGHT_POS = vec3(-1.0, 1.0, 2.0);

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
    int material_id;
};

float sdEllipsoid( vec3 p, vec3 r )
{
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return k0*(k0-1.0)/k1;
}

float sdRoundCone( vec3 p, float r1, float r2, float h )
{
  vec2 q = vec2( length(p.xz), p.y );
    
  float b = (r1-r2)/h;
  float a = sqrt(1.0-b*b);
  float k = dot(q,vec2(-b,a));
    
  if( k < 0.0 ) return length(q) - r1;
  if( k > a*h ) return length(q-vec2(0.0,h)) - r2;
        
  return dot(q, vec2(a,b) ) - r1;
}

float ndot(vec2 a, vec2 b ) { return a.x*b.x - a.y*b.y; }

float sdRhombus(vec3 p, float la, float lb, float h, float ra)
{
  p = abs(p);
  vec2 b = vec2(la,lb);
  float f = clamp( (ndot(b,b-2.0*p.xz))/dot(b,b), -1.0, 1.0 );
  vec2 q = vec2(length(p.xz-0.5*b*vec2(1.0-f,1.0+f))*sign(p.x*b.y+p.z*b.x-b.x*b.y)-ra, p.y-h);
  return min(max(q.x,q.y),0.0) + length(max(q,0.0));
}

vec3 rotateX(vec3 p, float a) {
    return vec3(p.x, cos(a) * p.y - sin(a) * p.z, sin(a) * p.y + cos(a) * p.z);
}

vec3 rotateY(vec3 p, float a) {
    return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
}

vec3 rotateZ(vec3 p, float a) {
    return vec3(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y, p.z);
}

float opRound( float p, float rad )
{
    return p - rad;
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float opUnion( float d1, float d2 ) { return min(d1,d2); }

float bias( float value, float biasVal)
{
  return (value / ((((1.0/biasVal) - 2.0)*(1.0 - value))+1.0));
}

float gain(float value, float gainVal)
{
  if(value < 0.5)
    return bias(value * 2.0,gainVal)/2.0;
  else
    return bias(value * 2.0 - 1.0,1.0 - gainVal)/2.0 + 0.5;
}

float remapVal(float val, float min1, float max1, float min2, float max2) {
    return val - (min1 - min2) * (max2 - min2) / (max1 - min1);
}

float kirbyBounce(float val) {
    return bias(gain(val, .8), .1);
}

#define KIRBY_ROT_VAL_X -.2
#define KIRBY_ROT_VAL_Y .4
#define KIRBY_ROT_VAL_Z .0

float starSDF(vec3 queryPos) 
{   
    float scale = .6;
    float starRot = 1.25;
    vec3 starCenter = rotateX(queryPos, -.2);
    vec3 starOffset = scale * vec3(-1.0, 0.0, 0.0);
    float axis1 = 1. * scale;
    float axis2 = .7 * scale;
    float thick = .02 * scale;
    float round = .02 * scale;

    vec3 armPos1 = starCenter - starOffset;
    vec3 armPos2 = rotateY(starCenter, starRot) - starOffset;
    vec3 armPos3 = rotateY(starCenter, starRot * 2.0) - starOffset;
    vec3 armPos4 = rotateY(starCenter, starRot * 3.0) - starOffset;
    vec3 armPos5 = rotateY(starCenter, starRot * 4.0) - starOffset;
    
    float arm1 = sdRhombus(armPos1, axis1, axis2, thick, round);
    float arm2 = sdRhombus(armPos2, axis1, axis2, thick, round);
    float arm3 = sdRhombus(armPos3, axis1, axis2, thick, round);
    float arm4 = sdRhombus(armPos4, axis1, axis2, thick, round);
    float arm5 = sdRhombus(armPos5, axis1, axis2, thick, round);

    float centerBulge = sdEllipsoid(starCenter, scale * vec3(1.1, .25, 1.1));

    float star = smin(arm1, arm2, .02);
    star = smin(star, arm3, .02);
    star = smin(star, arm4, .02);
    star = smin(star, arm5, .02);
    star = smin(star, centerBulge, .1);

    return opRound(star, .1);
}

float kirbyStarSDF(vec3 queryPos) {
    vec3 starOffset = vec3(0.0, -.70, 0.0);

    float armDownRemap = remapVal(sin(u_Time * .5) * .3, -.3, .3, 0.0, 1.0);
    float armBobDown = kirbyBounce(armDownRemap) * 1.5;
    float armUpRemap = remapVal(sin(u_Time * .5) * .2, -.2, .2, 0.0, 1.0);
    float armBobUp = kirbyBounce(armUpRemap) * 1.5;

    float bodyDeformTime = sin(u_Time * .5) * .05;
    float bodyDeform = kirbyBounce(bodyDeformTime);

    vec3 bodyPos = rotateZ(rotateY(rotateX(queryPos + vec3(0.0, -bodyDeform, 0.0), KIRBY_ROT_VAL_X), KIRBY_ROT_VAL_Y), KIRBY_ROT_VAL_Z);
    vec3 feetBasePos = rotateZ(rotateY(rotateX(queryPos, KIRBY_ROT_VAL_X), KIRBY_ROT_VAL_Y), KIRBY_ROT_VAL_Z);
    
    vec3 leftEyePos = bodyPos - normalize(vec3(-.175, 0.0 + bodyDeform, 1.0)) * .6;
    vec3 rightEyePos = bodyPos - normalize(vec3(.175, 0.0 + bodyDeform, 1.0)) * .6;
    
    vec3 armDownPos = rotateX(rotateY(bodyPos - normalize(vec3(-1.5, -.75 + armBobDown, 1.2)) * .65, .3), -.3);
    vec3 armUpPos = rotateX(rotateY(bodyPos - normalize(vec3(1.5, 1.0 + armBobUp, -1.0)) * .65, .6), -.3);
    
    vec3 leftFootPos = rotateZ(rotateX(feetBasePos - normalize(vec3(-1., -.9, 0.2)) * .6, -2.3), -.9);
    vec3 rightFootPos = rotateZ(rotateX(feetBasePos - normalize(vec3(1., -.9, 0.2)) * .6, -2.3), .9);

    vec3 bodyScale = vec3(0.65, 0.6 + bodyDeform, 0.65);
    vec3 eyeScale = vec3(.15, .2, .05);
    vec3 armScale = vec3(.15, .15, .3);

    float kirbyBody = sdEllipsoid(bodyPos, bodyScale);
    float kirbyLeftEye = sdEllipsoid(leftEyePos, eyeScale);
    float kirbyRightEye = sdEllipsoid(rightEyePos, eyeScale);
    float kirbyDownArm = sdEllipsoid(armDownPos, armScale);
    float kirbyUpArm = sdEllipsoid(armUpPos, armScale);
    float kirbyLeftFoot = sdRoundCone(leftFootPos, .22, .15, .2);
    float kirbyRightFoot = sdRoundCone(rightFootPos, .22, .15, .2);
    
    float kirby = smin(kirbyBody, kirbyDownArm, .01);
    kirby = smin(kirby, kirbyLeftFoot, .01);
    kirby = smin(kirby, kirbyRightFoot, .01);    
    kirby = opUnion(kirby, kirbyLeftEye);
    kirby = opUnion(kirby, kirbyRightEye);
    kirby = smin(kirby, kirbyUpArm, .01);
    kirby = opUnion(kirby, starSDF(feetBasePos - starOffset));
    return kirby;
}

float sceneSDF(vec3 queryPos) 
{
    vec3 shaking = vec3(sin(u_Time * .2) * .1, cos(u_Time * .4) * .1, sin((u_Time + 100.0) * .3));
    float kirbyStar = kirbyStarSDF(queryPos + shaking);
    return kirbyStar;
}

Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, u_Up));
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = u_Up * tan(FOV); 
    vec3 screen_horizontal = camera_RIGHT * aspect_ratio * tan(FOV);
    vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);
   
    return r;
}

vec3 getNormal(vec3 point) {
    vec2 dVec = vec2(0.0, EPSILON);
    float x = sceneSDF(point + dVec.yxx) - sceneSDF(point - dVec.yxx);
    float y = sceneSDF(point + dVec.xyx) - sceneSDF(point - dVec.xyx);
    float z = sceneSDF(point + dVec.xxy) - sceneSDF(point - dVec.xxy);

    return normalize(vec3(x, y, z));
}

float shadow(vec3 rayOrigin, vec3 rayDirection, float maxT) {
    for (float t = 0.015; t <= maxT; ++t) {
        float h = sceneSDF(rayOrigin + rayDirection * t);
        if (h < 0.001) {
            return 0.3;
        }
        t += h;
    }
    return 1.0;
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Ray ray = getRay(uv);
    Intersection intersection;
    
    intersection.distance_t = -1.0;
    float t = 0.0;

    for (int step = 0; step < MAX_RAY_STEPS; ++step) {
        vec3 queryPos = ray.origin + ray.direction * t;
        float currDist = sceneSDF(queryPos);
        if (currDist < EPSILON) {
            intersection.distance_t = t;
            intersection.normal = getNormal(queryPos);
            intersection.position = queryPos;
            return intersection;
        }
        t += currDist;
    }
    return intersection;
}

vec3 getSceneColor(vec2 uv)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    if (intersection.distance_t > 0.0)
    {
        float shadows = shadow(intersection.position, normalize(LIGHT_POS - intersection.position), 10.0);
        vec4 diffuseColor = vec4(1.0);

        // Calculate the diffuse term for Lambert shading
        float diffuseTerm = dot(normalize(intersection.normal), normalize(LIGHT_POS));
        // Avoid negative lighting values
        diffuseTerm = clamp(diffuseTerm, 0.0, 1.0);

        float ambientTerm = 0.2;

        float lightIntensity = diffuseTerm + ambientTerm;   //Add a small float value to the color multiplier
                                                            //to simulate ambient lighting. This ensures that faces that are not
                                                            //lit by our point light are not completely black.
        return vec3(diffuseColor.rgb * lightIntensity) * shadows;
    }
    return vec3(0.0f);
}

void main() {
    out_Col = vec4(getSceneColor(fs_Pos.xy), 1.0);
}
