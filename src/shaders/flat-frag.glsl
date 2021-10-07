#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 128;
const float MAX_RAY_DISTANCE = 20.;
const float FOV = 45.0;
const float MIN_STEP = 1e-4;
const float EPSILON = 1e-6;

const vec3 EYE = vec3(0.0, 0.0, 10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(-1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const vec3 LIGHT_DIR = vec3(2.0, 8.0, 2.0);

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
    vec3 color;
};

float getBias(float bias, float t)
{
	return (t / ((( (1.0/bias) - 2.0 ) * (1.0 - t)) + 1.0));
}

float getGain(float gain, float t)
{
  if(t < 0.5){
    return getBias(t * 2.0, gain)/2.0;
  } else {
    return getBias(t * 2.0 - 1.0,1.0 - gain)/2.0 + 0.5;
  }
}

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
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


float sdCapsule( vec3 p, vec3 a, vec3 b, float r )
{
  vec3 pa = p - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float dot2(in vec3 v ) { return dot(v,v); }
float sdRoundCone(vec3 p, vec3 a, vec3 b, float r1, float r2)
{
    // sampling independent computations (only depend on shape)
    vec3  ba = b - a;
    float l2 = dot(ba,ba);
    float rr = r1 - r2;
    float a2 = l2 - rr*rr;
    float il2 = 1.0/l2;
    
    // sampling dependant computations
    vec3 pa = p - a;
    float y = dot(pa,ba);
    float z = y - l2;
    float x2 = dot2( pa*l2 - ba*y );
    float y2 = y*y*l2;
    float z2 = z*z*l2;

    // single square root!
    float k = sign(rr)*rr*rr*x2;
    if( sign(z)*a2*z2 > k ) return  sqrt(x2 + z2)        *il2 - r2;
    if( sign(y)*a2*y2 < k ) return  sqrt(x2 + y2)        *il2 - r1;
                            return (sqrt(x2*a2*il2)+y*rr)*il2 - r1;
}

float fourMax(float a, float b, float c, float d) {
    return max(max(max(a, b), c), d);
}

float fourMin(float a, float b, float c, float d) {
    return min(min(min(a, b), c), d);
}

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float udQuad( vec3 p, vec3 a, vec3 b, vec3 c, vec3 d )
{
  float xmax = fourMax(a.x, b.x, c.x, d.x);
  float xmin = fourMin(a.x, b.x, c.x, d.x);
  float ymax = fourMax(a.y, b.y, c.y, d.y);
  float ymin = fourMin(a.y, b.y, c.y, d.y);
  float zmax = fourMax(a.z, b.z, c.z, d.z);
  float zmin = fourMin(a.z, b.z, c.z, d.z);

//   if (xmax > p.x || xmin < p.x || ymax > p.y || ymin < p.y || zmax > p.z || zmin < p.z) {
//       return sdBox(p - vec3((xmax-xmin) / 2.,(ymax-ymin) / 2.,(zmax-zmin) / 2.),  vec3((xmax-xmin),(ymax-ymin),(zmax-zmin)));
//   }

  vec3 ba = b - a; vec3 pa = p - a;
  vec3 cb = c - b; vec3 pb = p - b;
  vec3 dc = d - c; vec3 pc = p - c;
  vec3 ad = a - d; vec3 pd = p - d;
  vec3 nor = cross( ba, ad );

  return sqrt(
    (sign(dot(cross(ba,nor),pa)) +
     sign(dot(cross(cb,nor),pb)) +
     sign(dot(cross(dc,nor),pc)) +
     sign(dot(cross(ad,nor),pd))<3.0)
     ?
     min( min( min(
     dot2(ba*clamp(dot(ba,pa)/dot2(ba),0.0,1.0)-pa),
     dot2(cb*clamp(dot(cb,pb)/dot2(cb),0.0,1.0)-pb) ),
     dot2(dc*clamp(dot(dc,pc)/dot2(dc),0.0,1.0)-pc) ),
     dot2(ad*clamp(dot(ad,pd)/dot2(ad),0.0,1.0)-pd) )
     :
     dot(nor,pa)*dot(nor,pa)/dot2(nor) );
}

float sdRoundBox( vec3 p, vec3 b, float r )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float sceneSDF(vec3 queryPos) 
{   
    //fusalage
    float vary = getGain(abs((sin(u_Time))), .8) * 1.;
    float compareval = sdCapsule(queryPos, vec3(-3.0 + vary, 2.0, 3.0 + vary), vec3(2.0 + vary, 2.0, -2.0 + vary), .5);
    //toppart
    float minval = sdCapsule(queryPos, vec3(-2.8 + vary, 2.4, 2.8 + vary), vec3(-2. + vary,  2.3, 2. + vary), .5);
    minval = smin(minval, compareval, .3);
    minval = smin(minval, sdCapsule(queryPos, vec3(-2. + vary,  2.3, 2. + vary), vec3(-1. + vary,  2.0, 1. + vary), .5), .05);
    //end of fusalage
    minval = min(minval, sdRoundCone(queryPos, vec3(2.0 + vary, 2.0, -2.0 + vary),  vec3(5.0 + vary, 2.4, -5.0 + vary), .5, .2));
    minval = smin(minval, sdRoundCone(queryPos, vec3(2.0 + vary, 1.9, -2.0 + vary),  vec3(5.0 + vary, 2.3, -5.0 + vary), .5, .2), .1);
    //minval = smin(minval, sdRoundBox(queryPos, vec3(3.5, 2.3, -3.5), 4.), .1);

    // bot fusalage
    minval = smin(minval, sdCapsule(queryPos, vec3(-3.0 + vary, 1.8, 3.0 + vary), vec3(1.8 + vary, 1.8, -1.8 + vary), .5), .2);
    //nose
    minval = smin(minval, sdRoundCone(queryPos, vec3(-2.8 + vary, 2.3, 2.8 + vary),  vec3(-3.2 + vary, 2.0, 3.2 + vary), .5, .2), .2);
    minval = smin(minval, sdRoundCone(queryPos, vec3(-3.0 + vary, 2.0, 3.0 + vary),  vec3(-3.5 + vary, 1.8, 3.5 + vary), .4, .2), .5);

    float fuselage = minval;

    //tail
    float tail =  udQuad(queryPos, vec3(3.0 + vary, 2.5, -3.0 + vary),  vec3(5.0 + vary, 2.5, -5.0 + vary), vec3(5.5 + vary, 4.0, -5.5 + vary), vec3(4.5 + vary, 4.0, -4.5 + vary)) - .05;
    
    minval = min(tail, fuselage);

    // //left fin
    // float finOff1 = 2.5;
    // float finOff2 = -.25;
    // float finOff3 = 3.;
    // float finOff4 = 0.;
    // float lfin = udQuad(queryPos, vec3(4.0, 2.2, -4.0),  vec3(5.0, 2.2, -5.0), vec3(5.0+finOff1, 2.5, -5.0+finOff2), vec3(4.0+finOff3, 2.5, -4.0+finOff4)) - .05;   
    // minval = min(minval, lfin);

    // float rfin = udQuad(queryPos, vec3(3.0, 2.2, -3.0),  vec3(5.0, 2.2, -5.0), vec3(5.0+finOff2, 2.5, -5.0+finOff1), vec3(3.0+finOff4, 2.5, -3.0+finOff3)) - .05;
    // minval = min(minval, rfin);

    // //left wing
    // float wingOff1 = 8.;
    // float wingOff2 = -1.2;
    // float wingOff3 = 7.8;
    // float wingOff4 = -2.2;
    // float lwing = udQuad(queryPos, vec3(-2.0, 1.5, 2.0),  vec3(0.0, 1.5, 0.0), vec3(0.0+wingOff1, 1.5, 0.0+wingOff2), vec3(-2.0+wingOff3, 1.5, 2.0+wingOff4)) - .09;
    // minval = min(minval, lwing);

    // float rwing = udQuad(queryPos, vec3(-2.0, 1.5, 2.0),  vec3(0.0, 1.5, 0.0), vec3(0.0+wingOff2, 1.5, 0.0+wingOff1), vec3(-2.0-wingOff4, 1.5, 2.0+wingOff3)) - .09;
    // minval = min(minval, rwing);

    return minval;    
}

Ray getRay(vec2 uv)
{
    Ray r;
    vec3 look = normalize(ORIGIN - EYE);
    vec3 camera_RIGHT = normalize(cross(look, WORLD_UP));
    vec3 camera_UP = cross(camera_RIGHT, look);
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = WORLD_UP * length(ORIGIN - EYE)* tan(FOV/2.); 
    vec3 screen_horizontal = camera_RIGHT * length(ORIGIN - EYE) * aspect_ratio * tan(FOV/2.);
    vec3 screen_point = (ORIGIN + uv.x * screen_horizontal + uv.y * screen_vertical);
    r.origin = EYE;
    r.direction = normalize(screen_point - EYE);
    return r;
}

Intersection getNormal(Intersection intersection) {
    vec2 d = vec2(0., EPSILON);
    vec3 p = intersection.position;
    float x = sceneSDF(p + d.yxx) - sceneSDF(p - d.yxx);
    float y = sceneSDF(p + d.xyx) - sceneSDF(p - d.xyx);
    float z = sceneSDF(p + d.xxy) - sceneSDF(p - d.xxy);

    intersection.normal = normalize(vec3(x, y, z));

    return intersection;
}

Intersection getIntersectionFromRay(Ray ray) {
    Intersection intersection;
    float t = 0.; 
    for (int i = 0; i < MAX_RAY_STEPS; i++) {
      vec3 p = ray.origin + ray.direction * t;
      float dist = sceneSDF(p);
      if (dist < EPSILON) {
        intersection.position = ray.origin + ray.direction * t;
        intersection.distance_t = 1.;
        return getNormal(intersection);
      }

      if (dist > MIN_STEP) {
        t += dist;
      } else {
        t += MIN_STEP;
      }

    } 
    intersection.distance_t = -1.0;
    
    intersection.color = clamp(ray.direction, 0., 1.);
    return intersection;
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Ray ray = getRay(uv);
    return getIntersectionFromRay(ray);
}

//returns true if in shadow
bool checkInShadow(Intersection inte) {
    vec3 p = inte.position;
    Ray ray;
    ray.direction = normalize(LIGHT_DIR - p);
    ray.origin = p + ray.direction * 1e-3;
    Intersection intersection = getIntersectionFromRay(ray);
    if(intersection.distance_t > 0.) {
        return true;
    }
    return false;

}

vec3 getSceneColor(vec2 uv)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    //return vec3(intersection.color.z);
    //return intersection.color;
    if (intersection.distance_t > 0.0)
    {
        float diffuseTerm = clamp(dot(normalize(intersection.normal), normalize(LIGHT_DIR - intersection.position)), 0., 1.);

        if (checkInShadow(intersection)) {
            //return vec3 (1.0, 0., 0.);
            diffuseTerm = 0.;
        }

        float ambientTerm = 0.1;

        float lightIntensity = diffuseTerm + ambientTerm;
        vec3 col = vec3(1.);
        vec3(clamp(col * lightIntensity, 0.0, 1.0));
        return vec3(clamp(col * lightIntensity, 0.0, 1.0));
     }
     return vec3(0., .2, .5f);
}

void main()
{
    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fs_Pos;
    
    // Make symmetric [-1, 1]
    //uv = uv * 2.0 - 1.0;

    // Time varying pixel color
    vec3 col = getSceneColor(uv);

    // Output to screen
    out_Col = vec4(col,1.0);
}
