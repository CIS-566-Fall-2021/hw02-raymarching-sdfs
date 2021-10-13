#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 128;
const float FOV = 45.0;
const float EPSILON = 1e-6;

const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(-1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const float HALF_PI = 1.570796327;
const float MAX_RAY_LENGTH = 12.0;

// COLORS
const vec3 MUG_COLOR = vec3(140.0, 150.0, 170.0) / 255.0 * 0.8;
const vec3 SCISSORS_COLOR = vec3(196.0, 202.0, 206.0) / 255.0;
const vec3 FLOOR_COLOR = vec3(91.0, 96.0, 101.0) / 255.0 * 0.5;
const vec3 GOLD_COLOR = vec3(215.0, 190.0, 105.0) / 255.0;
const vec3 backgroundColor = vec3(0.2);

// LIGHTS
const vec3 LIGHT_POS = vec3(-1.0, 3.0, 2.0);
const vec3 LIGHT_COLOR = vec3(1.0, .88, .7);
const vec3 FILL_LIGHT_DIR = vec3(0.0, 1.0, 0.0);
const vec3 FILL_LIGHT_COLOR = vec3(0.7, 0.2, 0.7) * 0.2;
const vec3 AMBIENT_LIGHT_DIR = normalize(-vec3(15.0, 0.0, 10.0));
const vec3 AMBIENT_LIGHT_COLOR = vec3(0.6, 1.0, 0.4) * 0.2;


// structs
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

// TOOLBOX FUNCTIONS -------------------------------------------------------
float GetBias(float t, float bias)
{
  return (t / ((((1.0/bias) - 2.0)*(1.0 - t))+1.0));
}


float GetGain(float t, float gain)
{
  if(t < 0.5)
    return GetBias(t * 2.0,gain)/2.0;
  else
    return GetBias(t * 2.0 - 1.0,1.0 - gain)/2.0 + 0.5;
}

// SDF functions ----------------------------------------------------------

float sdfPlane( vec3 p, vec3 n, float h )
{
  // n must be normalized
  return dot(p,n) + h;
  // return queryPos.y - h;
}

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

float sdRoundBox( vec3 p, vec3 b, float r )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdTorus( vec3 p, vec2 t )
{
  vec2 q = vec2(length(p.xz)-t.x,p.y);
  return length(q)-t.y;
}

float sdRoundedCylinder( vec3 p, float ra, float rb, float h )
{
  vec2 d = vec2( length(p.xz)-2.0*ra+rb, abs(p.y) - h );
  return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
}

float sdCappedCone( vec3 p, float h, float r1, float r2 )
{
  vec2 q = vec2( length(p.xz), p.y );
  vec2 k1 = vec2(r2,h);
  vec2 k2 = vec2(r2-r1,2.0*h);
  vec2 ca = vec2(q.x-min(q.x,(q.y<0.0)?r1:r2), abs(q.y)-h);
  vec2 cb = q - k1 + k2*clamp( dot(k1-q,k2)/dot(k2, k2), 0.0, 1.0 );
  float s = (cb.x<0.0 && ca.y<0.0) ? -1.0 : 1.0;
  return s*sqrt( min(dot(ca, ca),dot(cb, cb)) );
}

float sdHexPrism( vec3 p, vec2 h )
{
  const vec3 k = vec3(-0.8660254, 0.5, 0.57735);
  p = abs(p);
  p.xy -= 2.0*min(dot(k.xy, p.xy), 0.0)*k.xy;
  vec2 d = vec2(
       length(p.xy-vec2(clamp(p.x,-k.z*h.x,k.z*h.x), h.x))*sign(p.y-h.x),
       p.z-h.y );
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}


// SDF Modifiers-------------------------------------------------------------
float opRound(float sdf, float rad )
{
    return sdf - rad;
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); 
}

vec3 opElongate(in vec3 p, in vec3 h )
{
    vec3 q = p - clamp( p, -h, h );
    return q;
}

float sphereRep( vec3 p, vec3 c )
{
    vec3 q = mod(p+0.5*c,c)-0.5*c;
    return sdfSphere( q, vec3(0.0), 1.0 );
}

// from https://github.com/dmnsgn/glsl-rotate/blob/master/rotation-3d-x.glsl
mat3 rotation3dX(float angle) {
	float s = sin(angle);
	float c = cos(angle);

	return mat3(
		1.0, 0.0, 0.0,
		0.0, c, s,
		0.0, -s, c
	);
}

// from https://github.com/dmnsgn/glsl-rotate/blob/master/rotation-3d-y.glsl
mat3 rotation3dY(float angle) {
	float s = sin(angle);
	float c = cos(angle);

	return mat3(
		c, 0.0, -s,
		0.0, 1.0, 0.0,
		s, 0.0, c
	);
}

// from https://github.com/dmnsgn/glsl-rotate/blob/master/rotation-3d-z.glsl
mat3 rotation3dZ(float angle) {
	float s = sin(angle);
	float c = cos(angle);

	return mat3(
		c, s, 0.0,
		-s, c, 0.0,
		0.0, 0.0, 1.0
	);
}

// Scene Building-------------------------------------------------------------------------

// Build for the Scissors
float sceneSDFScissors(vec3 queryPos) {
    vec3 scissorsPos = vec3(-0.6, -1.95, 1.0);
    queryPos += scissorsPos;
    queryPos = transpose(rotation3dY(-HALF_PI/2.0)) * queryPos;
    queryPos = transpose(rotation3dX(-3.0 * HALF_PI/9.0)) * queryPos;
    // oval loop
    float t = sdRoundedCylinder(transpose(rotation3dX(HALF_PI)) * opElongate(queryPos, vec3(0.0, 0.45, 0.0)), 0.17, 0.1, 0.05);    
    float innerLoop = sdRoundedCylinder(transpose(rotation3dX(HALF_PI)) * opElongate(queryPos, vec3(0.0, 0.4, 0.0)), 0.12, 0.1, 0.08);    
    t = opSmoothSubtraction(innerLoop, t, 0.125);
    
    // circle loop
    vec3 circleLoopOffset = queryPos + vec3(-.8, -0.15, 0.0);
    float outerCircleLoop = sdRoundedCylinder(transpose(rotation3dX(HALF_PI)) * 
                                                opElongate(circleLoopOffset, vec3(0.0, .15, 0.0)), .19, 0.1, .05);
    float innerCircleLoop = sdRoundedCylinder(transpose(rotation3dX(HALF_PI)) * 
                                                opElongate(circleLoopOffset, vec3(0.0, .10, 0.0)), 0.14, 0.1, .06);
    float circleLoop = opSmoothSubtraction(innerCircleLoop, outerCircleLoop, 0.125);
    t = min(t, circleLoop);

    // prism connecter 1
    vec3 prism1_offset = transpose(rotation3dZ(HALF_PI / 4.0)) * (queryPos + vec3(-0.43, .75, 0.0));
    float prism1 = sdRoundBox(prism1_offset, vec3(.05, .15, .05), .05);
    t = smin(t, prism1, .25);

    // prism connecter 2
    vec3 prism2_offset = transpose(rotation3dZ(-HALF_PI / 6.0)) * (queryPos + vec3(-0.55, .75, 0.0));
    float prism2 = sdRoundBox(prism2_offset, vec3(.03, .35, .03), .05);
    t = smin(t, prism2, .25);

    // base of blades
    vec3 bladeBase_offset = queryPos + vec3(-0.5, 1.25, 0.0);
    float bladeBase = sdRoundBox(bladeBase_offset, vec3(0.06, .35, 0.06), .05);
    t = smin(t, bladeBase, .05);

    // screw
    vec3 screw_offset = bladeBase_offset;
    float screw = sdRoundedCylinder(transpose(rotation3dX(HALF_PI)) * screw_offset, .03, .03, 0.1);
    t = smin(t, screw, .05);

    // blades
    vec3 blade_offset = screw_offset + vec3(0.0, 1.45, 0.0);
    float blades = sdCappedCone(blade_offset, 1.0, .08, .12);
    opRound(blades, .05);
    t = smin(t, blades, .15);

    return t;
}

float sceneSDFMugLip(vec3 queryPos) {
    // Capped Cone Lip
    vec3 lipOffset = vec3(0.0, -1.05, 0.0);
    float Lip = sdCappedCone(queryPos + lipOffset, 0.10, 1.05, 1.00);
    Lip = opRound(Lip, 0.07);

    // Cut out inner cylinder
     vec3 innerCylinderOffset = vec3(0.0, -0.25, 0.0);
    Lip = opSmoothSubtraction(sdRoundedCylinder(queryPos + innerCylinderOffset, 0.45, 0.10, 1.0), Lip, 0.15);
    return Lip;
}

// Build for the Mug
float sceneSDFMug(vec3 queryPos) {

    queryPos = transpose(rotation3dY(5.0 * HALF_PI / 3.0)) * queryPos;
    // Outer cylinder
    float t = sdRoundedCylinder(queryPos, 0.5, 0.15, 1.0);

    // Capped Cone Base
    vec3 baseOffset = vec3(0.0, 1.05, 0.0);
    float Base = sdCappedCone(queryPos + baseOffset, 0.10, 1.01, 0.9);
    Base = opRound(Base, 0.02);
    t = smin(t, Base, .65);

    // Add ring detail from mug
    vec3 RingOffset1 = vec3(0.0, 0.0, 0.0);
    vec3 RingOffset2 = vec3(0.0, 0.67, 0.0);
    for (float i = 0.0; i < 4.0; i++) {
        // cut out upper rings
        float UpperRing = sdRoundedCylinder(queryPos + RingOffset1, 0.5025, .005, .01);
        t = smin(t, UpperRing, .025);
        RingOffset1 += vec3(0.0, 0.05, 0.0);
        // cut out lower rings
        float LowerRing = sdRoundedCylinder(queryPos + RingOffset2, 0.54 + i * 0.02, .005, .01);
        t = min(t, LowerRing);
        RingOffset2 += vec3(0.0, 0.15, 0.0);
    }

    // HANDLE
    float h;
    // Handle Outer Ring
    vec3 handleOffset = vec3(1.1, -0.2, 0.0);
    float HandleOuter = sdHexPrism(queryPos + handleOffset, vec2(0.5, 0.01));
    h = opRound(HandleOuter, 0.25);
    // Handle Inner Ring
    float HandleInner = sdRoundedCylinder(transpose(rotation3dX(HALF_PI)) * (queryPos + handleOffset + vec3(0.0, .025, 0.0)), 0.25, 0.15, 1.0);
    // Cut Inner Ring, Combine with Mug
    h = opSmoothSubtraction(HandleInner, h, 0.15);
    t = smin(t, h, .17);

    // Cut out inner cylinder
     vec3 innerCylinderOffset = vec3(0.0, -0.25, 0.0);
    t = opSmoothSubtraction(sdRoundedCylinder(queryPos + innerCylinderOffset, 0.45, 0.10, 1.0), t, 0.15);
    
    return t;
}

vec3 animateHorizontal(vec3 p) {
     return p + vec3(8.0, 0.0, 0.0) * (GetBias(sin(u_Time * .025) + 1.0, 0.7) - 0.5);
}

vec3 animateYRotation(vec3 p) {
    return transpose(rotation3dY(GetGain((.5 * sin(u_Time * .025) + 0.5), 0.7) * 6.0)) * p;
}

float sceneSDF(vec3 queryPos, out int hitObj) 
{   
    // PLANE
    float t = sdfPlane(queryPos, WORLD_UP, 1.5);
    hitObj = 2;
    
    // Bounding sphere, so we only have to check for geometry within certain bounds
    float bounding_box_dist = sdBox(queryPos, vec3(12.0));
    if(bounding_box_dist <= .00001) {

    // MUG
    float t2 = sceneSDFMug(animateHorizontal((queryPos)));
    if (t2 < t) {
        t = t2;
        hitObj = 0;
    }
   
    // SCISSORS
    t2 = min(t, sceneSDFScissors(animateYRotation(animateHorizontal(queryPos))));
    if (t2 < t) {
        t = t2;
        hitObj = 1;
    }

    

    // MUG LIP
    t2 = smin(t, sceneSDFMugLip(animateHorizontal((queryPos))), .05);
    if (t2 < t) {
        t = t2;
        hitObj = 3;
    }

    return t;
    }
    hitObj = -2;
    return bounding_box_dist;
}

vec3 estimateNormal(vec3 p, out int hitObj) {
    vec2 d = vec2(0.0, EPSILON);
    float x = sceneSDF(p + d.yxx, hitObj) - sceneSDF(p - d.yxx, hitObj);
    float y = sceneSDF(p + d.xyx, hitObj) - sceneSDF(p - d.xyx, hitObj);
    float z = sceneSDF(p + d.xxy, hitObj) - sceneSDF(p - d.xxy, hitObj);
    return normalize(abs(vec3(x, y, z)));
}

Ray getRay(vec2 uv)
{
    Ray r;
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    float len = length(u_Ref - u_Eye);

    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, u_Up));
    
    vec3 screen_vertical = u_Up * len * tan(FOV / 2.0); 
    vec3 screen_horizontal = camera_RIGHT * len * aspect_ratio * tan(FOV / 2.0);
    vec3 screen_point = (u_Ref + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);
   
    return r;
}

bool isRayTooLong(vec3 queryPoint, vec3 origin)
{
    return length(queryPoint - origin) > MAX_RAY_LENGTH;
}

Intersection getRaymarchedIntersection(vec2 uv, out int hitObj)
{
    Intersection intersection;    
    intersection.distance_t = -1.0;

    Ray r = getRay(uv);
    float distancet = 0.0;

    for (int step; step < MAX_RAY_STEPS; step++) {
        vec3 qPoint = r.origin + r.direction * distancet;
        if(isRayTooLong(qPoint, r.origin)) {
           break; 
        } 
        float currentDistance = sceneSDF(qPoint, hitObj);
        if (currentDistance < EPSILON) { 
            // something was hit by our ray!
            intersection.distance_t = distancet;
            intersection.normal = estimateNormal(qPoint, hitObj);
            intersection.position = r.origin + distancet * r.direction;
            return intersection;
        }
        distancet += currentDistance;
        
    }

    return intersection;
}

// SHADING ------------------------------------------------------------------------------------------------------------

float softShadow(vec3 dir, vec3 origin, float min_t, out int hitObj) {
    float k = 20.0;
    float res = 1.0;
    float t = min_t;
    for(float i = min_t; i < float(100.0); i+=1.0) {
        float m = sceneSDF(origin + t * dir, hitObj);
        if(m < 0.0001) {
            return 0.0;
        }
        if (hitObj != -2) {
        res = min(res, k * m / t);
        }
        t += m;
    }
    return res;
}

float shadeLambert(vec3 norm, vec3 lightVec) {
    // Calculate the diffuse term for Lambert shading
    float diffuseTerm = dot(normalize(norm), normalize(lightVec));

    // Avoid negative lighting values
    diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);

    // add ambient lighting
    float ambientTerm = 0.2;
    float lightIntensity = diffuseTerm + ambientTerm;   

    return lightIntensity;
}

vec3 computeMaterial(int hitObj, vec3 p, vec3 n) {
    float t;
    
    vec3 albedo;
    switch(hitObj) {
        case 0: // Mug
        albedo = MUG_COLOR;
        break;
        case 1: // Scissors
        albedo = SCISSORS_COLOR;
        break;
        case 2: // Floor
        albedo = FLOOR_COLOR;
        break; // Background
        case 3: // Mug Lip
        albedo = GOLD_COLOR;
        break;
        case -1:
        return backgroundColor;
        break;
        case -2: 
        return backgroundColor;
        break;
    }
    
    // create shadows
    vec3 color = vec3(0.0);

    color = albedo *
                 LIGHT_COLOR *
                 max(0.0, dot(n, normalize(LIGHT_POS - p))) *
                 softShadow(normalize(LIGHT_POS - p), p, 1.0, hitObj);


    // fake global illumination
    color += albedo * LIGHT_COLOR * max(0.0, dot(n, normalize(LIGHT_POS - p))); // shadow-casting light
    color += albedo * AMBIENT_LIGHT_COLOR * max(0.0, dot(n, AMBIENT_LIGHT_DIR));
    color += albedo * FILL_LIGHT_COLOR * max(0.0, dot(n, FILL_LIGHT_DIR));

    return color;
}

vec3 getSceneColor(vec2 uv)
{
    int hitObj = -1;
    Intersection intersection = getRaymarchedIntersection(uv, hitObj);
    if (intersection.distance_t > 0.0)
    { 
        // shade everything with lambert
        float lightIntensity = shadeLambert(intersection.normal, LIGHT_POS - intersection.position);
        return lightIntensity * computeMaterial(hitObj, intersection.position, intersection.normal);
    }
    return backgroundColor;
}

// MAIN --------------------------------------------------------------------------------------------------------------

void main() {
    // Pink/Blue test coloring: 
    // Ray r = getRay(fs_Pos);
    // vec3 rayOrigin = r.origin;//u_Eye;
    // vec3 rayDirection = r.direction;//normalize(p - u_Eye);
    // out_Col = vec4(0.5 * (rayDirection + vec3(1.0, 1.0, 1.0)), 1.0); 
    
    // Original coloring:
    // out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
    
    // Using Raymarching:
    vec3 col = getSceneColor(fs_Pos);
    // Output to screen
    out_Col = vec4(col,1.0);
}