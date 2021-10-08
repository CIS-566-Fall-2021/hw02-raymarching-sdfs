#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 256;
const float MAX_RAY_DISTANCE = 50.;
const float FOV = 45.0;
const float EPSILON = 1e-5;

// const vec3 EYE = vec3(0.0, 0.0, 10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(-1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
// const vec3 LIGHT_DIR = vec3(-1.0, 1.0, 2.0);
// const vec3 LIGHT_DIR = vec3(1.0, 1.0, 2.0);
const vec4 LIGHT_COL_1 = vec4(.5, .7, 1., 1.);
const vec4 LIGHT_COL_2 = vec4(.5, .7, 1., 1.);
const vec3 LIGHT_DIR_1 = vec3(1.0, 1.0, 1.0);
const vec3 LIGHT_DIR_2 = vec3(-1.0, 1.0, -1.0);

// The higher the value, the smaller the penumbra
const float SHADOW_HARDNESS = 7.0;
// 0 for no, 1 for yes
#define SHADOW 1
#define ANIMATION 1
// 0 for penumbra shadows, 1 for hard shadows
#define HARD_SHADOW 0


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

//------------------------------------------------------------------

//TRANSFORMATIONS

vec3 rotateX(vec3 p, float a) {
    return vec3(p.x, cos(a) * p.y - sin(a) * p.z, sin(a) * p.y + cos(a) * p.z);
}

vec3 rotateY(vec3 p, float a) {
    return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
}

vec3 rotateZ(vec3 p, float a) {
    return vec3(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y, p.z);
}

//------------------------------------------------------------------

//TOOLBOX FUNCTIONS & ADDITIONAL OPERATIONS

float ease_in_quadratic(float t)
{
  return t * t;
}

float ease_out_quadratic(float t)
{
  return 1. - ease_in_quadratic(1. - t);
}

float ease_in_out_quadratic(float t)
{
  if (t < .5) {
    return ease_in_quadratic(t * 2.) / 2.;
  }
  else {
    return 1. - ease_in_quadratic((1. - t) * 2.) / 2.; 
  }
}

float displacement(vec3 p)
{
    //no easing
    // p[0] += u_Time / 100.;
    // p[1] += u_Time / 80.;
    // p[2] += u_Time / 120.;
    // return sin(.5*p.x)*cos(.5*p.y)*sin(.5*p.z);

    //weird blobs dripping down
    // p[0] += u_Time / 100.;
    // p[1] += u_Time / 80.;
    // p[2] += u_Time / 120.;
    // return 2. * (1. - ease_in_out_quadratic(sin(.5*p.x)*cos(.5*p.y)*sin(.5*p.z)));

    //with easing
    #if ANIMATION
    float u_Time_new = ease_in_out_quadratic(sin(u_Time / 50.) * 20.);
    p[0] += u_Time_new / 100.;
    p[1] += u_Time_new / 80.;
    p[2] += u_Time_new / 120.;
    #endif
    return sin(.5*p.x)*cos(.5*p.y)*sin(.5*p.z);
}

//add result to primitive(p)
float opDisplace(vec3 p)
{
    float d2 = displacement(p);
    return d2;
}

//result = primitive(q)
vec3 opCheapBend(vec3 p)
{
    const float k = 10.0; // or some other amount
    float c = cos(k*p.x);
    float s = sin(k*p.x);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
}

//result = primitive(q)
vec3 opRep(vec3 p, vec3 c)
{
    vec3 q = mod(p+0.5*c,c)-0.5*c;
    return q;
}

//------------------------------------------------------------------

float plane(vec3 p, vec4 n)
{
    return dot(p,n.xyz) + n.w;
}

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

float sdEllipsoid( vec3 p, vec3 r )
{
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return k0*(k0-1.0)/k1;
}

float sdRoundCone(vec3 p, float r1, float r2, float h)
{
    vec2 q = vec2( length(p.xz), p.y );
    
    float b = (r1-r2)/h;
    float a = sqrt(1.0-b*b);
    float k = dot(q,vec2(-b,a));
    
    if( k < 0.0 ) return length(q) - r1;
    if( k > a*h ) return length(q-vec2(0.0,h)) - r2;
        
    return dot(q, vec2(a,b) ) - r1;
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

float sdCone( vec3 p, vec2 c, float h )
{
  // c is the sin/cos of the angle, h is height
  // Alternatively pass q instead of (c,h),
  // which is the point at the base in 2D
  vec2 q = h*vec2(c.x/c.y,-1.0);
    
  vec2 w = vec2( length(p.xz), p.y );
  vec2 a = w - q*clamp( dot(w,q)/dot(q,q), 0.0, 1.0 );
  vec2 b = w - q*vec2( clamp( w.x/q.x, 0.0, 1.0 ), 1.0 );
  float k = sign( q.y );
  float d = min(dot( a, a ),dot(b, b));
  float s = max( k*(w.x*q.y-w.y*q.x),k*(w.y-q.y)  );
  return sqrt(d)*sign(s);
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float sceneSDF(vec3 queryPos) 
{
    //TEMP TraNSLate
    // queryPos = queryPos + vec3(2., 0., 4.);
    // return smin(sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 0.2),
                // sdfSphere(queryPos, vec3(cos(u_Time) * 2.0, 0.0, 0.0), abs(cos(u_Time))), 0.2);
    // return min(sdfSphere(queryPos, vec3(.0, .0, .0), 0.5), plane(queryPos, vec4(0., 1., 0., 0.)));

    //floor
    // float t = plane(queryPos, vec4(0., 2., 0., 4.));

  //BODY
    //chest
    // t = smin(t, sdfSphere(queryPos, vec3(.0, .0, .0), 0.5), .05);
    // t = smin(t, sdfSphere(queryPos, vec3(-.05, .0, -.05), 0.55), .05);
    float t = sdfSphere(queryPos, vec3(-.05, .0, -.05), 0.55);
    //test // float t = sdfSphere(queryPos, vec3(-.0, -.0, -.0), 0.55);
    //torso
    t = smin(t, sdEllipsoid(rotateY(queryPos - vec3(-.35, -.1, -.35), .7), vec3(.8, .6, .6)), .05);
    //hindquarters
    t = smin(t, sdfSphere(queryPos, vec3(-.85, .0, -.85), 0.6), .05);

  //FRONT LEGS
    //front-right shoulder
    t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(-.2, -.25, .2), .25), .15), 0.25, .25, .6), .05);
    //front-right leg upper
    t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(-.35, -1., .35), .4), .2), 0.1, .15, .5), .05);
    //front-right leg knee
    t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.4, -1.1, .4), .3), .1), vec3(0.1, .15, .1)), .05);
    //front-right leg lower
    t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(-.45, -1.7, .7), .55), .05), 0.11, .08, .5), .05);
    //front-right leg hoof
    // t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.3, -1.9, .7), .3), .1), vec3(0.15, .1, .15)), .05);
    t = smin(t, sdCappedCone(queryPos - vec3(-.7, -1.8, .6), vec3(0.15, -.1, .15), vec3(0.2, .0, .2), .15, .05), .05);

    //front-left shoulder
    t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(.25, -.25, .0), .05), -.2), 0.25, .25, .6), .05);
    //front-left leg upper
    vec3 offset = vec3(.4, .0, -.4);
    t = smin(t, sdRoundCone(queryPos - vec3(-.15, -1., .35) - offset, 0.1, .15, .5), .05);
    //front-left leg knee
    t = smin(t, sdEllipsoid(queryPos - vec3(-.15, -1.1, .35) - offset, vec3(0.1, .15, .1)), .05);
    //front-left leg lower
    t = smin(t, sdRoundCone(queryPos - vec3(-.15, -1.7, .35) - offset, 0.11, .08, .5), .05);
    //front-left leg hoof
    // t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.3, -1.9, .7), .3), .1), vec3(0.15, .1, .15)), .05);
    t = smin(t, sdCappedCone(queryPos - vec3(-.25, -1.8, .25) - offset, vec3(0.15, -.1, .15), vec3(0.2, .0, .2), .15, .05), .05);

  //BACK LEGS
    vec3 back_offset = vec3(-1., 0., -1.);
    //back-right shoulder
    // t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(.2, -.2, .2) - back_offset, -.25), -.15), 0.2, .3, .6), .05);
    //back-right leg upper
    t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(-.35, -1., .35) - back_offset, .4), .2), 0.1, .2, .5), .05);
    //back-right leg knee
    t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.4, -1.1, .4) - back_offset, .3), .1), vec3(0.1, .15, .1)), .05);
    //back-right leg lower
    t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(-.45, -1.7, .7) - back_offset, .55), .05), 0.11, .08, .5), .05);
    //back-right leg hoof
    // t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.3, -1.9, .7), .3), .1), vec3(0.15, .1, .15)), .05);
    t = smin(t, sdCappedCone(queryPos - vec3(-.7, -1.8, .6) - back_offset, vec3(0.15, -.1, .15), vec3(0.2, .0, .2), .15, .05), .05);

    //back-left shoulder
    // t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(.25, -.2, .05) - back_offset, .05), -.2), 0.3, .25, .6), .05);
    //back-left leg upper
    t = smin(t, sdRoundCone(queryPos - vec3(-.15, -1., .35) - back_offset - offset, 0.1, .2, .5), .05);
    //back-left leg knee
    t = smin(t, sdEllipsoid(queryPos - vec3(-.15, -1.1, .35) - back_offset - offset, vec3(0.1, .15, .1)), .05);
    //back-left leg lower
    t = smin(t, sdRoundCone(queryPos - vec3(-.15, -1.7, .35) - back_offset - offset, 0.11, .08, .5), .05);
    //back-left leg hoof
    // t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.3, -1.9, .7), .3), .1), vec3(0.15, .1, .15)), .05);
    t = smin(t, sdCappedCone(queryPos - vec3(-.25, -1.8, .25) - back_offset - offset, vec3(0.15, -.1, .15), vec3(0.2, .0, .2), .15, .05), .05);


    //NECK
    t = smin(t, sdRoundCone(rotateX(queryPos - vec3(0., .3, 0.), -.5), 0.41, .28, .55), .05);
    t = smin(t, sdRoundCone(rotateX(queryPos - vec3(-.05, .9, .35), -1.), 0.24, .22, .35), .1);

    //HEAD
    t = smin(t, sdfSphere(queryPos, vec3(-.07, .95, .6), .25), .05);
    t = smin(t, sdRoundCone(rotateX(queryPos - vec3(-.07, .9, .6), -3.), 0.24, .15, .35), .05);
    t = smin(t, sdRoundCone(rotateX(queryPos - vec3(-.07, .8, .6), -3.), 0.14, .1, .35), .05);

    //EARS
    // t = smin(t, sdRoundCone(rotateY(rotateZ(rotateX(queryPos - vec3(-.07, 1., .6), -2.), -1.5), -10.), 0.07, .05, .5), .05);
    t = smin(t, sdRoundCone(rotateX(queryPos - vec3(-.2, 1.2, .8), -1.), 0.07, .01, .25), .05);
    t = smin(t, sdRoundCone(rotateX(queryPos - vec3(.1, 1.2, .7), -1.), 0.07, .01, .25), .05);

    //FLOOR
    // float t = plane(queryPos, vec4(0., 1., 0.2, 4.)) + displacement(queryPos);
    t = min(t, plane(queryPos, vec4(0., 1., 0.2, 4.)) + displacement(queryPos));

    // float t = sdfSphere(opRep(queryPos, vec3(5.)), vec3(-1.), .5);
    // t = min(t, sdfSphere(opRep(queryPos, vec3(5.)), vec3(-1.), .5));
    // t = min(t, sdCone(opRep(queryPos - vec3(.7, .1, .1), vec3(7.)), vec2(1., 10.), 4.));

    return t;
}

//------------------------------------------------------------------------------------------------------------------

Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, WORLD_UP));
    vec3 camera_UP = cross(camera_RIGHT, look);
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = camera_UP * tan(FOV); 
    vec3 screen_horizontal = camera_RIGHT * aspect_ratio * tan(FOV);
    vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);

    return r;
}

vec3 calcNormal(vec3 pos)
{
  vec3 eps = vec3(EPSILON,0.0,0.0);
	return normalize( vec3(
           sceneSDF(pos+eps.xyy) - sceneSDF(pos-eps.xyy),
           sceneSDF(pos+eps.yxy) - sceneSDF(pos-eps.yxy),
           sceneSDF(pos+eps.yyx) - sceneSDF(pos-eps.yyx) ) );
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Ray ray = getRay(uv);
    float distance = EPSILON;
    Intersection intersection;
    for (int steps = 0; steps < MAX_RAY_STEPS; steps++) {
      if (distance > MAX_RAY_DISTANCE) {
        break;
      }
      vec3 test_point = ray.origin + distance * ray.direction;
      float remaining_dist = sceneSDF(test_point);
      if (remaining_dist <= EPSILON) {
        intersection.position = test_point;
        intersection.distance_t = distance;
        intersection.normal = calcNormal(test_point);
        //intersection.material_id
        return intersection;
      } else {
        distance += remaining_dist;
      }
    }
    intersection.distance_t = -1.0;
    return intersection;
}

float hardShadow(vec3 dir, vec3 origin, float min_t) {
    float t = min_t;
    for(int i = 0; i < MAX_RAY_STEPS; ++i) {
        float m = sceneSDF(origin + t * dir);
        if(m < EPSILON) {
            return 0.0;
        }
        t += m;
    }
    return 1.0;
}

float softShadow(vec3 dir, vec3 origin, float min_t, float k) {
    // float res = 1.0;
    // float t = min_t;
    // for(int i = 0; i < MAX_RAY_STEPS; ++i) {
    //     float m = sceneSDF(origin + t * dir);
    //     if(m < EPSILON) {
    //         return 0.0;
    //     }
    //     res = min(res, k * m / t);
    //     t += m;
    // }
    // return res;

    float res = 1.0;
    float t = min_t;
    for( int i=0; i<50; i++ )
    {
        float h = sceneSDF(origin + dir*t);
        res = min( res, smoothstep(0.0,1.0,k*h/t) );
		t += clamp( h, 0.01, 0.25 );
		if( res<0.005 || t>10.0 ) break;
    }
    return clamp(res,0.0,1.0);
}

float shadow(vec3 dir, vec3 origin, float min_t) {
    #if HARD_SHADOW
    return hardShadow(dir, origin, min_t);
    #else
    return softShadow(dir, origin, min_t, SHADOW_HARDNESS);
    #endif
}

vec3 getLambertColor(Intersection intersection, vec4 diffuseColor, vec3 diffuseDirection, float ambientTerm)
{ 
    // Calculate the diffuse term for Lambert shading
    float diffuseTerm = dot(normalize(intersection.normal), normalize(diffuseDirection));
    // Avoid negative lighting values
    diffuseTerm = clamp(diffuseTerm, 0., 1.);

    float lightIntensity = diffuseTerm + ambientTerm;   //Add a small float value to the color multiplier
                                                        //to simulate ambient lighting. This ensures that faces that are not
                                                        //lit by our point light are not completely black.

    // Compute final shaded color
    return diffuseColor.rgb * lightIntensity;
}

vec3 getSceneColor(vec2 uv)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    if (intersection.distance_t > 0.0)
    {
        //return vec3(1.0f);
        // return intersection.normal;

        // vec3 finalColor = (getLambertColor(intersection, LIGHT_COL_1, LIGHT_DIR_1, .2) + getLambertColor(intersection, LIGHT_COL_2, LIGHT_DIR_2, .2)) / 2.;
        // for (int i = 0; i < 3; i++) {
        //   finalColor[i] = clamp(finalColor[i], 0., 1.);
        // }
        // return finalColor;
        
        // + intersection.normal * .001
        #if SHADOW
        return getLambertColor(intersection, LIGHT_COL_1, LIGHT_DIR_1, .2) * shadow(LIGHT_DIR_1, intersection.position + normalize(intersection.normal) * EPSILON, .1);
        #else
        return getLambertColor(intersection, LIGHT_COL_1, LIGHT_DIR_1, .2);
        #endif
     }
     return vec3(0.0f);
}

void main() {
      // out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
      // vec2 ndc = vec2(((2. * fs_Pos.x / u_Dimensions.x) - 1.), 1. - (2. * fs_Pos.y / u_Dimensions.y));
    // float len = length(u_Ref - u_Eye);
    // float a = (u_Dimensions.y / 2.) / len;
    // vec3 V = normalize(u_Up * len * a);
    // vec3 u_Forward = normalize(u_Ref - u_Eye);
    // vec3 u_Right = normalize(cross(u_Forward, u_Up));
    // float aspect = u_Dimensions.x / u_Dimensions.y;
    // vec3 H = normalize(u_Right * len * aspect * a);
    // vec3 point = u_Ref + fs_Pos.x * H + fs_Pos.y * V;
      // out_Col = vec4(0.5 * (vec3(point - u_Eye) + vec3(1.0, 1.0, 1.0)), 1.f);
    out_Col = vec4(getSceneColor(vec2(fs_Pos)),1.);
}
