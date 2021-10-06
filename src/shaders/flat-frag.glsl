#version 300 es

//****** Data *******/

#define tmax 5
#define EPSILON 1e-6
#define PI2 6.283185
#define MAX_DIS 10000.0
precision highp float;
uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

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

//******* Data End*******/
mat4 rotation3d(vec3 axis, float angle) {
  axis = normalize(axis);
  float s = sin(angle);
  float c = cos(angle);
  float oc = 1.0 - c;

  return mat4(
		oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,  0.0,
    oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,  0.0,
    oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c,           0.0,
		0.0,                                0.0,                                0.0,                                1.0
	);
}

/******* SDF Geometry *******/

// smooth blend
float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float smax( float a, float b, float k )
{
    float h = max(k-abs(a-b),0.0);
    return max(a, b) + h*h*0.25/k;
}

float boxSDF( vec3 query_position, vec3 r )
{
    return length( max(abs(query_position)-r,0.0) );
}
float sphereSDF(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}
float ringSDF(vec3 p){
    float d = abs(length(p.xz)-0.2)-0.03; 
    d = smax(d,abs(p.y)-0.03,0.01);// minus height of ring
    return d;
}

float cylinderSDF( vec3 p, float r, float h )
{
  vec2 d = abs(vec2(length(p.xy),p.z)) - vec2(r,h);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

// operation
float intersectSDF(float distA, float distB) {
    return smax(distA, distB, 0.02);
}

float unionSDF(float distA, float distB) {
    return smin(distA, distB, 0.02);
}

float differenceSDF(float distA, float distB) {
    return smax(distA, -distB, 0.02);
}
/******* SDF Geometry End *******/

/******* SceneSDF *******/

mat3 setCamera( vec3 ro, vec3 ta, float cr )
{
	vec3 cw = normalize(ta-ro);
	vec3 cp = vec3(sin(cr), cos(cr),0.0);
	vec3 cu = normalize( cross(cw,cp) );
	vec3 cv =          ( cross(cu,cw) );
    return mat3( cu, cv, cw );
}

#define GEAR_SECTOR 12.0
float gear(vec3 p) {

    float t = 0.01*u_Time;
    
    p.xz = mat2(cos(t),-sin(t),
                sin(t),cos(t)) * p.xz;
    //gear teeth calculation
    float angle_sector = PI2/GEAR_SECTOR;
    float ang = atan(p.z,p.x);
    float sector = round(ang/angle_sector);
    vec3 q = p;
    float an = sector*angle_sector;
    q.xz = mat2(cos(an),-sin(an),
                sin(an),cos(an)) * q.xz;

    // box maded gear teeth
    //float d1 = boxSDF(q-vec3(1.8,0.,0.),vec3(0.2+0.4*abs(sin(0.01*u_Time))*sin((ang-an)/angle_sector*PI2+PI2/4.0),0.18,0.34))-0.06;
    float d1 = boxSDF(q-vec3(0.25,0.,0.),vec3(0.04,0.03,0.05))-0.001;

    // ring shape
    float d2 = ringSDF(p);
    d2 = unionSDF(d1,d2);
    return d2;
}
#define GEAR_NUM 6.0

vec4 multQuat(vec4 a, vec4 b)
{
    return vec4(cross(a.xyz,b.xyz) + a.xyz*b.w + b.xyz*a.w, a.w*b.w - dot(a.xyz,b.xyz));
}

vec3 transformVecByQuat( vec3 v, vec4 q )
{
    return v + 2.0 * cross( q.xyz, cross( q.xyz, v ) + q.w*v );
}

vec4 axAng2Quat(vec3 ax, float ang)
{
    return vec4(normalize(ax),1)*sin(vec2(ang*.5)+vec2(0,PI2*.25)).xxxy;
}

float gearRing(vec3 p){

    float d = MAX_DIS;
    float dang=PI2/(12.0);
    float s = 1.0;
    float R = 6.0* 0.5 / PI2;
    for(int i = 0; i<12;i++){
        float ang = float(i)*dang;
        vec3 pos=vec3(cos(ang)*R,sin(ang)*R,0);

    }
    return d;
}
float sceneSDF(vec3 p){

    // gear teeth calculation
    float d = gearRing(p);

    return d;
}
/******* SceneSDF End*******/

/******* Ray march*******/

Ray getRay(vec2 p){
  float fov = 45.;
  float len = length(u_Ref - u_Eye);
  float aspect = u_Dimensions.x / u_Dimensions.y;

  vec3 look = normalize(u_Ref - u_Eye);
  vec3 R = normalize(cross(look, u_Up));
  vec3 U = cross(R, look);
  
  vec3 V = U*len*tan(fov/2.);
  vec3 H = R*len*aspect*tan(fov/2.); 

  vec3 sp =  look + p.x * H + p.y * V;

  Ray r;
  r.direction = normalize(sp-u_Eye);
  r.origin = u_Eye;

  return r;
}

vec3 estimateNormal(vec3 p) {
    return normalize(vec3(
        sceneSDF(vec3(p.x + EPSILON, p.y, p.z)) - sceneSDF(vec3(p.x - EPSILON, p.y, p.z)),
        sceneSDF(vec3(p.x, p.y + EPSILON, p.z)) - sceneSDF(vec3(p.x, p.y - EPSILON, p.z)),
        sceneSDF(vec3(p.x, p.y, p.z  + EPSILON)) - sceneSDF(vec3(p.x, p.y, p.z - EPSILON))
    ));
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Ray r = getRay(uv);
    Intersection intersection;
    int MAX_MARCHING_STEPS = 128;
    float depth = 0.0;

    for (int i = 0; i < MAX_MARCHING_STEPS; i++) {
        vec3 p = r.origin + depth * r.direction;
        float dist = sceneSDF(p);
        if (dist < EPSILON) {
            // We're inside the scene surface!
            intersection.position = p;
            intersection.distance_t = depth;
            intersection.normal = estimateNormal(p);// to be done: calculate normal
            return intersection;
        }
        // Move along the view ray
        depth += dist;
    }
    intersection.distance_t = -1.0;
    return intersection;
}

vec3 phongContribForLight(vec3 k_d, vec3 k_s, float alpha, vec3 p, vec3 eye,
                          vec3 lightPos, vec3 lightIntensity) {
    vec3 N = estimateNormal(p);
    vec3 L = normalize(lightPos - p);
    vec3 V = normalize(eye - p);
    vec3 R = normalize(reflect(-L, N));
    
    float dotLN = dot(L, N);
    float dotRV = dot(R, V);
    
    if (dotLN < 0.0) {
        // Light not visible from this point on the surface
        return vec3(0.0, 0.0, 0.0);
    } 
    
    if (dotRV < 0.0) {
        // Light reflection in opposite direction as viewer, apply only diffuse
        // component
        return lightIntensity * (k_d * dotLN);
    }
    return lightIntensity * (k_d * dotLN + k_s * pow(dotRV, alpha));
}

/**
 * Lighting via Phong illumination.
 * 
 * The vec3 returned is the RGB color of that point after lighting is applied.
 * k_a: Ambient color
 * k_d: Diffuse color
 * k_s: Specular color
 * alpha: Shininess coefficient
 * p: position of point being lit
 * eye: the position of the camera
 *
 * See https://en.wikipedia.org/wiki/Phong_reflection_model#Description
 */
vec3 phongIllumination(vec3 k_a, vec3 k_d, vec3 k_s, float alpha, vec3 p, vec3 eye) {
    const vec3 ambientLight = 0.5 * vec3(1.0, 1.0, 1.0);
    vec3 color = ambientLight * k_a;
    
    vec3 light1Pos = vec3(4.0 * sin(0.01*u_Time),
                          2.0,
                          4.0 * cos(0.01*u_Time));
    vec3 light1Intensity = vec3(0.4, 0.4, 0.4);
    
    color += phongContribForLight(k_d, k_s, alpha, p, eye,
                                  light1Pos,
                                  light1Intensity);
    
    vec3 light2Pos = vec3(2.0 * sin(0.02 * u_Time),
                          2.0 * cos(0.02 * u_Time),
                          2.0);
    vec3 light2Intensity = vec3(0.4, 0.4, 0.4);
    
    color += phongContribForLight(k_d, k_s, alpha, p, eye,
                                  light2Pos,
                                  light2Intensity);    
    return color;
}

void main() {
    
  Intersection i = getRaymarchedIntersection(fs_Pos);
  Ray r = getRay(fs_Pos);
  vec3 eye = r.origin;
  vec3 dir = r.direction;
  if(i.distance_t==-1.0){
      // background
      out_Col=vec4(1.0);
  }
  else{
    // blinn-phong test! 
    //   vec3 p = eye + i.distance_t * dir;
    //   vec3 K_a = vec3(0.2, 0.2, 0.2);
    //   vec3 K_d = vec3(0.7, 0.2, 0.2);
    //   vec3 K_s = vec3(1.0, 1.0, 1.0);
    //   float shininess = 10.0;
        
    //   vec3 color = phongIllumination(K_a, K_d, K_s, shininess, p, eye);
    
    vec3 col = 0.5 + 0.5*i.normal;
    out_Col = vec4(col, 1.0);
  }
}
