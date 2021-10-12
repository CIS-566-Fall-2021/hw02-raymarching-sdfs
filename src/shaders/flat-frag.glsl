#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;

out vec4 out_Col;

const int MAX_MARCHING_STEPS = 255;
const float MIN_DIST = 0.0;
const float MAX_DIST = 100.0;

const int MAX_RAY_STEPS = 128;
const float FOV = 45.0;
const float EPSILON = 1e-5;


#define BLUE_CUBE 1
#define BLUE_PLANK 2
#define BLUE_SABER 3
#define RED_CUBE 11
#define RED_SABER 12
#define WHITE_TRIANGLE 666
#define TEST_SPHERE 0

#define TO_RADIAN 3.14159/180.0


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

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdRoundBox( vec3 p, vec3 b, float r )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float sdTriPrism( vec3 p, vec2 h )
{
  vec3 q = abs(p);
  return max(q.z-h.y,max(q.x*0.866025+p.y*0.5,-p.y)-h.x*0.5);
}

float sdCapsule( vec3 p, vec3 a, vec3 b, float r )
{
  vec3 pa = p - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
}


float dot2( in vec2 v ) { return dot(v,v); }
float dot2( in vec3 v ) { return dot(v,v); }
float ndot( in vec2 a, in vec2 b ) { return a.x*b.x - a.y*b.y; }

float udTriangle( vec3 p, vec3 a, vec3 b, vec3 c )
{
  vec3 ba = b - a; vec3 pa = p - a;
  vec3 cb = c - b; vec3 pb = p - b;
  vec3 ac = a - c; vec3 pc = p - c;
  vec3 nor = cross( ba, ac );

  return sqrt(
    (sign(dot(cross(ba,nor),pa)) +
     sign(dot(cross(cb,nor),pb)) +
     sign(dot(cross(ac,nor),pc))<2.0)
     ?
     min( min(
     dot2(ba*clamp(dot(ba,pa)/dot2(ba),0.0,1.0)-pa),
     dot2(cb*clamp(dot(cb,pb)/dot2(cb),0.0,1.0)-pb) ),
     dot2(ac*clamp(dot(ac,pc)/dot2(ac),0.0,1.0)-pc) )
     :
     dot(nor,pa)*dot(nor,pa)/dot2(nor) );
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float opUnion( float d1, float d2 ) { return min(d1,d2); }

float opSmoothUnion( float d1, float d2, float k ) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); }

float opSubtraction( float d1, float d2 ) { return max(-d1,d2); }

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); }

float opIntersection( float d1, float d2 ) { return max(d1,d2); }

// float opRep( in vec3 p, in vec3 c, in sdf3d primitive )
// {
//     vec3 q = mod(p+0.5*c,c)-0.5*c;
//     return primitive( q );
// }

vec3 rotateX(vec3 p, float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(1, 0, 0),
        vec3(0, c, -s),
        vec3(0, s, c)
    ) * p;
}

vec3 rotateZ(vec3 p, float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(c, -s, 0),
        vec3(s, c, 0),
        vec3(0, 0, 1.)
    ) * p;
}
    
vec3 rotateY(vec3 p, float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(c, 0, s),
        vec3(0, 1, 0),
        vec3(-s, 0, c)
    ) * p;
}

float bias(float b, float t) {
    return pow(t,log(b)/log(0.5f));
}

float gain(float g, float t) {
    if (t < 0.5f) 
        return bias(1.0-g, 2.0*t) / 2.0;
     else 
        return 1.0 - bias(1.0-g, 2.0-2.0*t) / 2.0;
}

float ease_in_quadratic(float t){
    return t*t;
}

float ease_in_out_quadratic(float t) {
    if (t<0.5)
        return ease_in_quadratic(t*2.0)/2.0;
    else  
        return 1.0 - ease_in_quadratic((1.0-t)*2.0);
}


#define LEFTP1 vec3(-4.f,5.f,-25.f)
#define LEFTP2 vec3(-1.3f,5.f,-25.f)
#define RIGHTP1 vec3(1.3f,5.f,-25.f)
#define RIGHTP2 vec3(4.f,5.f,-25.f)
#define TEST_SPHERE_SDF sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 0.5)
#define TEST_SPHERE_SDF2 sdfSphere(queryPos, vec3(cos(time) * 2.0, 0.0, 0.0), abs(cos(time)))
#define PLANK1 sdBox(queryPos + LEFTP1,vec3(1.f,0.2,20.f))
#define PLANK2 sdBox(queryPos + LEFTP2,vec3(1.f,0.2,20.f))
#define PLANK3 sdBox(queryPos + RIGHTP1,vec3(1.f,0.2,20.f))
#define PLANK4 sdBox(queryPos + RIGHTP2,vec3(1.f,0.2,20.f))

#define BC1 vec3(1.f,3.2f,-8.f * sin(time))
#define BC2 vec3(4.f,3.f,-30.f * cos(time))
#define RC1 vec3(-1.f,2.f,-25.f * sin(time))
#define RC2 vec3(-4.f,3.f,-18.f + time)

// #define BT1 vec3(1.f,4.f,-0.6f)
#define BT1 BC1 + vec3(0.f,-0.8f,1.4f)
#define BT2 BC2 + vec3(-0.8f,0.f,1.4f)
#define RT1 RC1 + vec3(0.f,-0.8f,1.4f)
#define RT2 RC2 + vec3(0.8f,0.f,1.4f)

#define BS vec3(6.f,8.f,-1.f) + rotateY(vec3(1.f,1.f,1.f), 90.0*TO_RADIAN*ease_in_quadratic(cos(time))) 
#define RS vec3(-6.f,6.f,-1.f) + rotateZ(vec3(1.f,1.f,1.f), 90.0*TO_RADIAN*sin(time)) 

#define BS1 vec3(10.f,5.f,0.f)
#define RS1 vec3(-10.f,5.f,0.f)

#define BCUBE1 sdRoundBox(queryPos + BC1,vec3(1.f,1.f,1.f),0.5)
#define BCUBE2 sdRoundBox(queryPos + BC2,vec3(1.f,1.f,1.f),0.5)
#define RCUBE1 sdRoundBox(queryPos + RC1,vec3(1.f,1.f,1.f),0.5)
#define RCUBE2 sdRoundBox(queryPos + RC2,vec3(1.f,1.f,1.f),0.5)
#define TRI11 sdTriPrism(queryPos + BT1, vec2(1,0.2))
#define TRI1 sdTriPrism(rotateZ(queryPos + BT1, 180.*TO_RADIAN), vec2(0.8,0.2))
#define TRI2 sdTriPrism(rotateZ(queryPos + BT2, 90.*TO_RADIAN), vec2(0.8,0.2))
#define TRI3 sdTriPrism(rotateZ(queryPos + RT1, 180.*TO_RADIAN), vec2(0.8,0.2))
#define TRI4 sdTriPrism(rotateZ(queryPos + RT2, 270.*TO_RADIAN), vec2(0.8,0.2))
#define BCUBE11 opSmoothUnion(BCUBE1, TRI1,0.5)
#define BCUBE22 opSmoothUnion(BCUBE2, TRI2,0.5)
#define RCUBE11 opSmoothUnion(RCUBE1, TRI3,0.5)
#define RCUBE22 opSmoothUnion(RCUBE2, TRI4,0.5)
// #define TRI1 udTriangle(queryPos + T1, vec3(0.0,1.0,1.0), vec3(0.0,2.0,3.0),vec3(0.0,3.0,5.0))

#define BSABER_U sdCapsule(queryPos + BS, vec3(0.2f,0.2f,1.f),vec3(5.f,5.f,1.f),0.3)
#define RSABER_U sdCapsule(queryPos + RS, vec3(1.f,1.f,1.f),vec3(-5.f,5.f,1.f),0.3)
#define BSABER_B sdCapsule(queryPos + BS, vec3(0.f,0.f,0.1f),vec3(5.f,5.f,1.f),0.2)
#define RSABER_B sdCapsule(queryPos + RS + vec3(0.f,0.f,0.1), vec3(0.5f,0.5f,0.5f),vec3(-5.f,5.f,1.f),0.2)
#define BSABER opIntersection(BSABER_U,BSABER_B)
#define RSABER opIntersection(RSABER_U,RSABER_B)

#define BSIDE1 sdCapsule(queryPos + BS1, vec3(0.2f,0.2f,60.f),vec3(0.f,0.f,0.f),0.4)
#define RSIDE1 sdCapsule(queryPos + RS1, vec3(0.2f,0.2f,60.f),vec3(0.f,0.f,0.f),0.4)


float sceneSDF(vec3 queryPos) 
{
    // float time = 1.0;
    float time = u_Time/30.f;
    // float time = 0.f;
    float t, t2;
    t = PLANK1;
    t2 = PLANK2;
    t = min(t,t2);
    t2 = PLANK3;
    t = min(t,t2);
    t2 = PLANK4;
    t = min(t,t2);
    t2 = BCUBE11;
    t = min(t,t2);
    t2 = BCUBE22;
    t = min(t,t2);
    t2 = RCUBE11;
    t = min(t,t2);
    t2 = RCUBE22;
    t = min(t,t2);
    t2 = BSABER;
    t = min(t,t2);
    t2 = RSABER;
    t = min(t,t2);
    t2 = BSIDE1;
    t = min(t,t2);
    t2 = RSIDE1;
    t = min(t,t2);
    return t;
}


float sceneSDF(vec3 queryPos, out int id) 
{
    float time = u_Time/30.f;
    // float time = 0.f;
    float t, t2;
    t = PLANK1;
    id = BLUE_PLANK;
    // 1. Evaluate all SDFs as material groups
    float white_t = min(min(TRI1,TRI4), min(TRI2, TRI3));
    float darkBlue_t = min(min(PLANK2, PLANK1), min(PLANK3,PLANK4));
    float bluecube_t = min(BCUBE1, BCUBE2);
    float redcube_t = min(RCUBE1, RCUBE2);
    if(white_t < t) {
        t = white_t;
        id = WHITE_TRIANGLE;
    }
    if(darkBlue_t < t) {
        t = darkBlue_t;
        id = BLUE_PLANK;
    }
    if(bluecube_t < t) {
        t = bluecube_t;
        id = BLUE_CUBE;
    }
    if(redcube_t < t){
        t = redcube_t;
        id = RED_CUBE;
    }
    // if((t2 = BSABER_B) < t){
    //     t = t2;
    //     id = BLUE_PLANK;
    // } 
    // if((t2 = RSABER_B) < t){
    //     t = t2;
    //     id = BLUE_PLANK;
    // } 
    if((t2 = BSABER) < t){
        t = t2;
        id = BLUE_SABER;
    } 
    if((t2 = RSABER) < t){
        t = t2;
        id = RED_SABER;
    } 
    if((t2 = BSIDE1) < t){
        t = t2;
        id = BLUE_SABER;
    } 
    if((t2 = RSIDE1) < t){
        t = t2;
        id = RED_SABER;
    } 
     
    return t;
}

// compute normal of arbitrary scene by using the gradient    
vec3 computeNormal(vec3 pos)
{
    vec3 epsilon = vec3(0.0, 0.001, 0.0);
    return normalize( vec3( sceneSDF(pos + epsilon.yxx) - sceneSDF(pos - epsilon.yxx),
                            sceneSDF(pos + epsilon.xyx) - sceneSDF(pos - epsilon.xyx),
                            sceneSDF(pos + epsilon.xxy) - sceneSDF(pos - epsilon.xxy)));
}

//transform from uv space to ray space
Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 ref = u_Ref;
    vec3 eye = u_Eye;
    
    vec3 F = normalize(ref - eye);
    vec3 U = u_Up;
    vec3 R = cross(F, U);
    float len = length(vec3(ref - eye));
    float alpha = FOV/2.f;
    vec3 V = U * len * tan(alpha);
    float aspect = u_Dimensions.x / u_Dimensions.y;
    vec3 H = R*len*aspect*tan(alpha);
    float sx = fs_Pos.x ;
    float sy = fs_Pos.y ;
    vec3 p = ref + sx * H + sy * V;

    vec3 dir = normalize(p - eye);

    r.origin = eye;
    r.direction = dir;
   
    return r;
}

float shadow(vec3 dir, vec3 origin, float min_t, float k, vec3 lightPos) {
    float res = 1.0;
    float t = min_t;
    for(int i = 0; i < MAX_RAY_STEPS; ++i) {
        float m = sceneSDF(origin + t * dir);
        if(m < 0.0001) {
            return 0.;
        }
        res = min(res, k * m / t);
        t += m;
    }
    return res;
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Intersection intersection;
    intersection.distance_t = -1.0;
    int material_id;
    Ray r = getRay(uv);
    float t = EPSILON; 
    for(int step; step < MAX_RAY_STEPS; ++step){
      vec3 queryPoint = r.origin + r.direction * t;
      
      float currDistance = sceneSDF(queryPoint, material_id);
      if (currDistance < EPSILON) {
        //if we hit something
        intersection.distance_t = t;
        intersection.normal = computeNormal(queryPoint);
        intersection.material_id = material_id;
        intersection.position = queryPoint;
        return intersection;
      }
      t += currDistance;
      // Stop marching after we get too far away from camera
      if(t > MAX_DIST) {
          return intersection;
      }
    }

    return intersection;
}

vec3 rgb(int r, int g, int b) {
  return vec3(float(r) / 255.f, float(g) / 255.f, float(b) / 255.f);
}

vec3 getSceneColor(vec2 uv)
{
    Intersection i = getRaymarchedIntersection(uv);
    vec3 diffuseColor = vec3(1.f);
    if (i.material_id == BLUE_PLANK) {
        diffuseColor = rgb(5,23,44);
     } else if (i.material_id == BLUE_CUBE) {
        diffuseColor = rgb(2,70,122);
     } else if (i.material_id == RED_CUBE) {
        diffuseColor = rgb(102,9,9);
     } else if (i.material_id == WHITE_TRIANGLE) {
        diffuseColor = rgb(255,255,255);
     }  else if (i.material_id == BLUE_SABER) {
        diffuseColor = rgb(163,219,250);
     }  else if (i.material_id == RED_SABER) {
        diffuseColor = rgb(236,138,147);
     }
     else if (i.material_id == TEST_SPHERE) {
        diffuseColor = i.normal;
     } else if (i.distance_t > 0.0f){
         diffuseColor = vec3(1.f);
     }

    //lambert shading
    vec3 lightPos = vec3(0.f, 10.f, -10.f);
    vec3 lightDir = lightPos - i.position;

    float diffuseTerm = dot(normalize(i.normal), normalize(lightDir));
    diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);
    float ambientTerm = 0.5;
    float lightIntensity = (diffuseTerm + ambientTerm);

    float K = 100.f;
    float sh = shadow(lightDir, i.position, 0.1, K, lightPos);
    vec3 col = diffuseColor.rgb * lightIntensity * sh;
    //col = sh > 0.5 ? vec3(1.) : vec3(1., 0., 1.);

    // col = i.normal * 0.5 + vec3(0.5);
     
     return col;
}

void main() {
    vec2 uv = fs_Pos;
    vec3 col = getSceneColor(uv);
//   out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
    out_Col = vec4(col, 1.0);
   
    //test ray casting function
    // Ray r = getRay(uv);
    // vec3 color = 0.5 * (r.direction + vec3(1.0, 1.0, 1.0));
    // out_Col = vec4(color, 1.0);


    //lambert shading

    // vec3 lightDir = vec3(0.f);

    // float diffuseTerm = dot(normalize(nor), normalize(lightDir));
    // // Avoid negative lighting values
    // diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);
    // float ambientTerm = 0.25*float(u_Light);
    // float lightIntensity = (diffuseTerm + ambientTerm);

    // out_Col = vec4(diffuseColor.rgb * lightIntensity, diffuseColor.a);

}