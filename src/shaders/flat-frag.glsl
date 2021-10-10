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


const vec3 LIGHT_DIR = vec3(-1.0, 1.0, 2.0);
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
float sdfPlane(vec3 query_position, float h)
{
    return query_position.y - h;
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


#define GEAR_SECTOR 12.0
float gearSDF(vec3 p, float speed)
{
    // float t = speed*0.05*sin(0.1*u_Time);
    // p.xy = mat2(cos(t),-sin(t),
    //            sin(t),cos(t)) * p.xy;
    //gear teeth calculation
    int numTeeth = 12;
    float w = 0.25;
    float lpxy=length(p.xy);
    float d=10000.;
    float ang=atan(p.y,p.x);
    float outer_radius = 0.8;
    float height = 0.1;
    float inner_radius = 0.5;

    d=min(d,length(p+vec3(p.xy/lpxy,0.)*.1*sin(ang*GEAR_SECTOR))-outer_radius);
    d=max(d,abs(p.z)-height);
    d=max(d,inner_radius-lpxy);
    return d;
}
vec4 inverseQuat(vec4 q)
{
    return vec4(-q.xyz,q.w);
}

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
#define Z_AXIS vec3(0.0,0.0,1.0)
#define X_AXIS vec3(1.0,0.0,0.0)
#define Y_AXIS vec3(0.0,1.0,1.0)
float gearRepeat(vec3 p){

    vec3 p1 = p;
    vec4 q1 = axAng2Quat(Z_AXIS,0.05*u_Time);
    vec4 q2 = axAng2Quat(X_AXIS,PI2/2.*sin(0.01*u_Time));
    q2 = multQuat(q1,q2);
    p1 = transformVecByQuat(p1,q2);
    float g1 = gearSDF(p1,1.0);
    float dis = 1.55;
    vec3 p2 = p - vec3(dis,0.0,0.0);
    q1 = axAng2Quat(Z_AXIS,-0.05*u_Time);
    q2 = axAng2Quat(X_AXIS,PI2/2.*sin(0.01*u_Time));
    q2 = multQuat(q1,q2);
    p2 = transformVecByQuat(p2,q2);
    float g2 = gearSDF(p2,-1.0);
    
    vec3 p3 = p + vec3(dis,0.0,0.0);
    p3 = transformVecByQuat(p3,q2);
    float g3 = gearSDF(p3,-1.0);
    return min(g1,min(g2,g3));
}
float sceneSDF(vec3 p){
    float s = sdfPlane(p,-4.0);
    float size =  3.1;
    
    float mod_z = mod(p.z,2.0)-1.0;
    float rot = floor(abs(p.z/2.0));
    vec4 q = axAng2Quat(Z_AXIS,PI2/8.0);
    p = transformVecByQuat(p,q);
    float mod_x = mod(p.x,size)-size/2.;
    vec3 mod_p = vec3(mod_x,p.y,mod_z);
    return min(gearRepeat(mod_p),s);
}

float hardShadow(vec3 rayOrigin, vec3 rayDirection, float minT, float maxT)
{
    for(float t = minT; t < maxT; )
    {
        float h = sceneSDF(rayOrigin + rayDirection * t);
        if(h < EPSILON)
        {
            return 0.0;
        }
        t += h;
    }

    return 1.0;
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
            if(intersection.material_id==0)
                intersection.normal = estimateNormal(p);
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
    
    float shadowFactor = hardShadow(p, normalize(LIGHT_DIR), EPSILON * 100.0, 10.0);
    if (dotLN < 0.0) {
        // Light not visible from this point on the surface
        return vec3(0.0, 0.0, 0.0);
    } 
    
    if (dotRV < 0.0) {
        // Light reflection in opposite direction as viewer, apply only diffuse
        // component
        return lightIntensity * (k_d * dotLN);
    }
    return lightIntensity * (k_d * dotLN * shadowFactor + k_s * pow(dotRV, alpha));
}

/**
 * Lighting via Phong illumination.
 * https://en.wikipedia.org/wiki/Phong_reflection_model#Description
 */
vec3 phongIllumination(vec3 k_a, vec3 k_d, vec3 k_s, float alpha, vec3 p, vec3 eye) {
    const vec3 ambientLight = 0.5 * vec3(1.0, 1.0, 1.0);
    vec3 color = ambientLight * k_a;
    
    vec3 light1Pos = vec3(-4.0 * sin(0.01*u_Time),
                          2.0,
                          4.0 * cos(0.01*u_Time));
    vec3 light1Intensity = vec3(0.4, 0.4, 0.4);
    
    color += phongContribForLight(k_d, k_s, alpha, p, eye,
                                  light1Pos,
                                  light1Intensity);
    
    vec3 light2Pos = vec3(20.*sin(0.01*u_Time),20.*sin(0.01*u_Time),20.*sin(0.01*u_Time));
    vec3 light2Intensity = vec3(2.0);
    
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
    // Blinn-phong
       vec3 p = eye + i.distance_t * dir;
       vec3 K_a = vec3(0.3255, 0.1294, 0.1294);
       vec3 K_d = vec3(0.7, 0.2, 0.2);
       vec3 K_s = vec3(1.0, 1.0, 1.0);
       float shininess = 10.0;
        
      vec3 color = phongIllumination(K_a, K_d, K_s, shininess, p, eye);
     //Lambertian Shading

      vec3 col = color;
     out_Col = vec4(col, 1.0);
  }
  
}
