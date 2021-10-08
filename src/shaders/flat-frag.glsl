#version 300 es
precision highp float;
const float TO_RADIANS = 3.1415 / 180.0;
const int RAY_STEPS = 256;
const vec3 LIGHT_POS = vec3(0., 6., -3.);

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

struct Intersection
{
    float t;
    vec3 color;
    vec3 p;
    int object;
};

float plane( vec3 p, vec4 n )
{
  return dot(p,n.xyz) + n.w;
}

float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
	vec3 ab = b-a;
    vec3 ap = p-a;
    
    float t = dot(ab, ap) / dot(ab, ab);
    t = clamp(t, 0., 1.);
    
    vec3 c = a + t*ab;
    
    return length(p-c)-r;
}

float sdCappedCylinder( vec3 p, float h, float r )
{
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

float sdCappedCone(vec3 p, vec3 a, vec3 b, float ra, float rb)
{
    float rba  = rb-ra;
    float baba = dot(b-a,b-a);
    float papa = dot(p-a,p-a);
    float paba = dot(p-a,b-a)/baba;
    float x = sqrt( papa - paba*paba*baba );
    float cax = max(0.0,x-((paba<0.5)?ra:rb));
    float cay = abs(paba-0.5)-0.5;
    float k = rba*rba + baba;
    float f = clamp( (rba*(x-ra)+paba*baba)/k, 0.0, 1.0 );
    float cbx = x-ra - f*rba;
    float cby = paba - f;
    float s = (cbx < 0.0 && cay < 0.0) ? -1.0 : 1.0;
    return s*sqrt( min(cax*cax + cay*cay*baba,
                       cbx*cbx + cby*cby*baba) );
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

float smin( float a, float b, float k ) {
    float h = clamp( 0.5+0.5*(b-a)/k, 0., 1. );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float opU( float d1, float d2 )
{
    return min( d1, d2 );
}

vec3 rotateX(vec3 p, float a) {
    return vec3(p.x, cos(a) * p.y + -sin(a) * p.z, sin(a) * p.y + cos(a) * p.z);
} 

vec3 rotateY(vec3 p, float a) {
    return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
} 

vec3 rotateZ(vec3 p, float a) {
    return vec3(cos(a) * p.x + -sin(a) * p.y, sin(a) * p.x + cos(a) * p.y, p.z);
} 

vec3 mirror(vec3 pos) {
    vec3 sym = vec3(-(pos.x), pos.yz);
    return rotateY(sym, 50. * TO_RADIANS) + vec3(-2.0, 0.1, 0.0);
}

vec3 rgb (float r, float g, float b) {
    return vec3(r / 255.0, g / 255.0, b / 255.0);
}

float bias(float b, float t) {
    return (t/((((1.0/b)-2.0)*(1.0-t))+1.0));
}

float gain(float g, float t){
    if (t < 0.5){
        return bias(1.0-g, 2.0*t)/2.0;
    }
    else{
        return 1.0 - bias(1.0-g, 2.0-2.0*t)/2.0;
    }
}

float opSubtraction( float d1, float d2 ) { return max(-d1,d2); }

// left arm 
#define LEFTUPPERARM sdCappedCone(pos-vec3( 2.0,0.1,-1.0), vec3(0.1,-0.5,2.0), vec3(-1.,1.0,2.5), 0.44, 0.3)
#define LEFTLOWERARM sdCappedCone(pos-vec3( 2.0,0.1,-1.0), vec3(0.5,-1.7,1.5), vec3(-0.03,-0.26,2.1), 0.5, 0.45)
#define ARM opU(LEFTUPPERARM, LEFTLOWERARM)

// pupils
#define LEFTPUPIL sdCapsule(pos + vec3(0.7, -1.7, -0.8),vec3(0,0.0,0.),vec3(0,-0.3,0), clamp(bias(0.8, sin(u_Time * 0.005)) + 0.95, 0., .1))
#define RIGHTPUPIL sdCapsule(pos + vec3(1.3, -1.7, -1.3),vec3(0,0.0,0.),vec3(0,-0.3,0), clamp(bias(0.8, sin(u_Time * 0.005)) + 0.95, 0., .1))

#define LEFTLEG sdCapsule(pos + vec3(-0.5, 2.8, -1.7),vec3(0,0.0,0.),vec3(0,-0.5,0), .4)
#define RIGHTLEG sdCapsule(pos + vec3(0.5, 2.8, -2.5),vec3(0,0.0,0.),vec3(0,-0.5,0), .4)

// stand
#define STAND sdCappedCylinder(pos + vec3(0.0, 4.7, -2.0) , 3., 1.)

// face and body
#define ACTUALFACE sdCappedCylinder(rotateX(rotateZ(pos + vec3(0.94, -1.5, -1.0), -90. * TO_RADIANS), 49. * TO_RADIANS), 0.95, 0.02)
#define FACE sdCappedCylinder(rotateX(rotateZ(pos + vec3(1.3, -1.5, -0.5), -90. * TO_RADIANS), 49. * TO_RADIANS), 1.0, 0.6)
#define CYLINDERBODY sdCapsule(pos ,vec3(0,2.0,2),vec3(0,-1.2,2), 1.7)
#define BODY smin(FACE, CYLINDERBODY, 0.1)

// four fingers on left arm
#define FINGER_ONE sdRoundCone(rotateZ(pos - vec3( 2.0,0.1,-1.0) - vec3(.1,-2.3,1.4), 10. * TO_RADIANS), .2, 0.3, 0.5)
#define FINGER_TWO sdRoundCone(rotateX(rotateZ(pos - vec3( 2.0,0.1,-1.0) - vec3(0.5,-2.1,0.9), -10. * TO_RADIANS), -30. * TO_RADIANS) , .2, 0.25, 0.5)
#define FINGER_THREE sdRoundCone(rotateX(rotateZ(pos - vec3( 2.22,0.1,-0.85) - vec3(.7,-2.0,0.9), -20. * TO_RADIANS), -30. * TO_RADIANS) , .2, 0.25, 0.5)
#define FINGER_FOUR sdRoundCone(rotateX(rotateZ(pos - vec3( 2.22,0.1,-0.85) - vec3(.8,-1.7,1.3), -30. * TO_RADIANS), -30. * TO_RADIANS) , .15, 0.2, 0.2)

// right arm and four fingers 
#define RIGHTUPPERARM sdCappedCone(mirror(pos)-vec3( 2.0,0.1,-1.0), vec3(0.1,-0.5,2.0), vec3(-1.,1.0,2.5), 0.44, 0.3)
#define RIGHTLOWERARM sdCappedCone(mirror(pos)-vec3( 2.0,0.1,-1.0), vec3(0.5,-1.7,1.5), vec3(-0.03,-0.26,2.1), 0.5, 0.45)
#define RIGHTARM opU(RIGHTUPPERARM, RIGHTLOWERARM)
#define RIGHT_FINGER_ONE sdRoundCone(rotateZ(mirror(pos) - vec3( 2.0,0.1,-1.0) - vec3(.1,-2.3,1.4), 10. * TO_RADIANS), .2, 0.3, 0.5)
#define RIGHT_FINGER_TWO sdRoundCone(rotateX(rotateZ(mirror(pos) - vec3( 2.0,0.1,-1.0) - vec3(0.5,-2.1,0.9), -10. * TO_RADIANS), -30. * TO_RADIANS) , .2, 0.25, 0.5)
#define RIGHT_FINGER_THREE sdRoundCone(rotateX(rotateZ(mirror(pos) - vec3( 2.22,0.1,-0.85) - vec3(.7,-2.0,0.9), -20. * TO_RADIANS), -30. * TO_RADIANS) , .2, 0.25, 0.5)
#define RIGHT_FINGER_FOUR sdRoundCone(rotateX(rotateZ(mirror(pos) - vec3( 2.22,0.1,-0.85) - vec3(.8,-1.7,1.3), -30. * TO_RADIANS), -30. * TO_RADIANS) , .15, 0.2, 0.2)
#define WHOLE_RIGHT_ARM smin(smin(smin(smin(RIGHTARM, RIGHT_FINGER_ONE, 0.1), RIGHT_FINGER_TWO, 0.1), RIGHT_FINGER_THREE, 0.1), RIGHT_FINGER_FOUR, 0.1)

// back plane
#define BACK_WALL plane(pos, vec4(0.0, 0.0, -1.0, 7.0))
#define BACK_WALL_ID 1

#define BOTTOM_STAND STAND
#define BOTTOM_STAND_ID 2

#define FACE_PART ACTUALFACE
#define FACE_PART_ID 3

#define BODY_N_LARM smin(smin(smin(smin(smin(smin(smin(smin(opSubtraction(FACE, CYLINDERBODY), ARM, 0.1), FINGER_ONE, 0.1), FINGER_TWO, 0.1), FINGER_THREE, 0.1), FINGER_FOUR, 0.1), LEFTLEG, 0.1), RIGHTLEG, 0.1), WHOLE_RIGHT_ARM, 0.1)
#define BODY_N_LARM_ID 4

#define RIGHT_ARM_PART WHOLE_RIGHT_ARM
#define RIGHT_ARM_PART_ID 5

#define LEFT_PUPIL LEFTPUPIL
#define LEFT_PUPIL_ID 6

#define RIGHT_PUPIL RIGHTPUPIL
#define RIGHT_PUPIL_ID 7

void fetchObject(vec3 pos, out float t, out int obj)
{
    t = BACK_WALL;
    obj = BACK_WALL_ID;
    
    float t2 = BOTTOM_STAND;
    if(t2 < t)
    {
        t = t2;
        obj = BOTTOM_STAND_ID;
    }
    t2 = FACE_PART;
    if(t2 < t)
    {
        t = t2;
        obj = FACE_PART_ID;
    }
    t2 = BODY_N_LARM;
    if(t2 < t)
    {
        t = t2;
        obj = BODY_N_LARM_ID;
    }
    t2 = RIGHT_ARM_PART;
    if(t2 < t)
    {
        t = t2;
        obj = RIGHT_ARM_PART_ID;
    }
    t2 = LEFT_PUPIL;
    if(t2 < t)
    {
        t = t2;
        obj = LEFT_PUPIL_ID;
    }
    t2 = RIGHT_PUPIL;
    if(t2 < t)
    {
        t = t2;
        obj = RIGHT_PUPIL_ID;
    }
}

float fetchObjectTwo(vec3 pos)
{
    float t = BACK_WALL;
    return min(min(min(min(min(min(t, BOTTOM_STAND), FACE_PART), 
                BODY_N_LARM), RIGHT_ARM_PART), LEFT_PUPIL), RIGHT_PUPIL);
}

vec3 computeNormal(vec3 pos)
{
    vec3 epsilon = vec3(0.0, 0.001, 0.0);
    return normalize( vec3( fetchObjectTwo(pos + epsilon.yxx) - fetchObjectTwo(pos - epsilon.yxx),
                            fetchObjectTwo(pos + epsilon.xyx) - fetchObjectTwo(pos - epsilon.xyx),
                            fetchObjectTwo(pos + epsilon.xxy) - fetchObjectTwo(pos - epsilon.xxy)));
}

float shadowMap3D(vec3 pos)
{
    float t = BOTTOM_STAND;
    t = min(t, BODY_N_LARM);
    t = min(t, RIGHT_ARM_PART);
    return t;
}

float shadow(vec3 dir, vec3 origin, float min_t, float k) {
    float res = 1.0;
    float t = min_t;
    for(int i = 0; i < RAY_STEPS; ++i) {
        float m = shadowMap3D(origin + t * dir);
        if(m < 0.0001) {
            return 0.0;
        }
        res = min(res, k * m / t);
        t += m;
    }
    return res;
}


vec3 lambertian(int hitObj, vec3 p, vec3 n, vec3 lightDir)
{
    float cosine = dot(-lightDir, n);
    switch(hitObj){
        case LEFT_PUPIL_ID:
        return vec3(0., 0., 0.) * cosine;
        break;
        case RIGHT_PUPIL_ID:
        return vec3(0., 0., 0.) * cosine;
        break;
        case BACK_WALL_ID:
        return vec3(1., 0.7411765, 0.) * cosine;
        break;
        case BOTTOM_STAND_ID:
        return rgb(234., 96., 218.) * cosine * shadow(-lightDir, p, 0.1, 10.0);
        break;
        case FACE_PART_ID:
        return rgb(249., 203., 250.) * cosine;
        break;
        case BODY_N_LARM_ID:
        return rgb(49., 131., 249.) * cosine;
        break;
        case RIGHT_ARM_PART_ID:
        return vec3(1., 1., 1.) * cosine;
        break;
        case -1:
        return vec3(0., 0., 0.);
    }
}

void march(vec3 origin, vec3 dir, out float t, out int objectID)
{
    t = 0.001;
    for(int i = 0; i < RAY_STEPS; ++i)
    {
        vec3 pos = origin + t * dir;
    	float m;
        fetchObject(pos, m, objectID);
        if(m < 0.01)
        {
            return;
        }
        t += m;
    }
    t = -1.;
    objectID = -1;
}

Intersection sdf(vec3 dir, vec3 eye)
{
    float t;
    int objectID;
    march(eye, dir, t, objectID);
    vec3 intersection = eye + t * dir;
    vec3 normal = computeNormal(intersection);
    vec3 lightDir = normalize(intersection - LIGHT_POS);
    vec3 color = lambertian(objectID, intersection, normal, lightDir);
    return Intersection(t, color, intersection, objectID);
}


vec3 shootRay(vec3 eye, vec3 ref, vec2 ndc)
{
    vec3 eye2Ref  = ref - eye;
    float n = length(eye2Ref);
    
    vec3 worldUp = vec3(0.0, 1.0, 0.0);
    vec3 right  = normalize(cross(eye2Ref, worldUp));
    
    vec3 U = normalize(cross(right, eye2Ref));
    vec3 V = U * n * tan(radians(45.0));
    
    float aspect = u_Dimensions.x / u_Dimensions.y;
    vec3 H = right * n * tan(radians(45.0)) * aspect;
  
    vec3 p = ref + ndc.x * H + ndc.y * V;
    return normalize(p - eye);
}

void main() {
  vec3 direction = shootRay(u_Eye, u_Ref, fs_Pos);
  Intersection it = sdf(direction, u_Eye);
  out_Col = vec4(it.color, 1.0);
}
