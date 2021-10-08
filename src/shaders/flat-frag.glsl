#version 300 es
precision highp float;

#define PI 3.14159265

#define MAT_SKY -1
#define MAT_GROUND 0
#define MAT_HILL 1

#define SUN_KEY_LIGHT vec3(0.67, 0.84, 0.902) * 1.5
#define SKY_FILL_LIGHT vec3(0.2, 0.7, 1.0) * 0.2
#define SUN_AMBIENT_LIGHT vec3(0.67, 0.84, 0.902) * 2.0
#define GAMMA 1

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;
const int MIN_RAY_STEPS = 0;
const int MAX_RAY_STEPS = 128;
const float FOV = 45.0;
const float EPSILON = 1e-6;

// const vec3 EYE = vec3(0.0, 0.0, 10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(-1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const vec3 LIGHT_DIR = vec3(-1.0, 1.0, -1.0);
const vec3 LIGHT_ORIGIN = vec3(-.750, 0.15, -1.0);

struct DirectionalLight
{
    vec3 dir;
    vec3 col;
};

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

struct hitObj
{
    float distance_t;
    int material_id;
};

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

float sdSphere(vec3 p, float s)
{
    return length(p) - s;
}

float planeSDF(vec3 queryPos, float height)
{
    return queryPos.y - height;
}

float capsuleSDF( vec3 queryPos, vec3 a, vec3 b, float r )
{
    vec3 pa = queryPos - a, ba = b - a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h ) - r;
}

float smoothUnion( float d1, float d2, float k ) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); }


float smoothSubtraction( float d1, float d2, float k ) 
{
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); 
}

float smoothIntersection( float d1, float d2, float k )
{
    float h = clamp( 0.5 - 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) + k*h*(1.0-h);
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float hemisphere(vec3 p, float r)
{
    float sphere = sdSphere(p, r);
    float plane = planeSDF(p, 0.f);
    return smoothSubtraction(plane, sphere, 0.25f);
}

hitObj sceneSDF(vec3 queryPos)
{
    // float dGround = heightField(queryPos, 0.0f);
    // return dGround;
    // float s1 = sdfSphere(queryPos, vec3(-2.f, -3.f, 0.f), 2.5);
    hitObj obj = hitObj(-1.f, -1);

    // float hillCenter = sdSphere(queryPos - vec3(0.f, 0.f, 20.f), 2.0f);
    float hillCenter = hemisphere(queryPos - vec3(0.f, 0.f, 10.f), 2.0f);
    float finalDist = hillCenter;
    int finalMat = MAT_HILL;
    float tempDist;

    float hillLeft1 = sdSphere(queryPos - vec3(-0.75f, 0.f, 15.f), 1.75);
    // if (hillLeft1 < finalDist) {
    //     finalDist = smoothUnion(finalDist, hillLeft1, 0.25f);
    //     finalMat = MAT_HILL;
    // }
    float ground = planeSDF(queryPos, -0.5f);
    finalDist = smoothUnion(ground, finalDist, 0.25f);
    // if (ground < finalDist) {
    //     finalDist = smoothUnion(finalDist, ground, 0.25f);
    //     finalMat = MAT_GROUND;
    // }
    // finalDist = smoothUnion

    obj.distance_t = finalDist;
    obj.material_id = finalMat;
    return obj;
    // return sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 0.2);
    // return smin(sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 0.2),
                // sdfSphere(queryPos, vec3(cos(u_Time) * 2.0, 0.0, 0.0), abs(cos(u_Time))), 0.2);
    // return smin(dGround,
    //             sdfSphere(queryPos, vec3(cos(u_Time) * 2.0, -1.0, -5.0), 1.0), 0.2);
    // return min(dGround,
                // sdfSphere(queryPos, vec3(cos(u_Time) * 2.0, -1.0, -5.0), 1.0));
    // return sdfSphere(queryPos, vec3(cos(u_Time) * 2.0, -1.0, 0.0), 1.0);
    // return dGround;
    
}

Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, u_Up));
    vec3 camera_UP = cross(camera_RIGHT, look);
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = u_Up * tan(FOV); 
    vec3 screen_horizontal = camera_RIGHT * aspect_ratio * tan(FOV);
    vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);
   
    return r;
}

vec3 estimateNorm(vec3 p)
{
    vec2 d = vec2(0.f, EPSILON);
    float x = sceneSDF(p + d.yxx).distance_t - sceneSDF(p - d.yxx).distance_t;
    float y = sceneSDF(p + d.xyx).distance_t - sceneSDF(p - d.xyx).distance_t;
    float z = sceneSDF(p + d.xxy).distance_t - sceneSDF(p - d.xxy).distance_t;
    
    return normalize(vec3(x, y, z));
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Intersection intersection;
    
    intersection.distance_t = -1.0;
    Ray ray = getRay(uv);
    float distance_t = 0.f;
    for (int step = MIN_RAY_STEPS; step < MAX_RAY_STEPS; ++step) {
        vec3 queryPoint = ray.origin + ray.direction * distance_t;
        hitObj obj = sceneSDF(queryPoint);
        if (obj.distance_t < EPSILON) {
            intersection.position = queryPoint;
            intersection.distance_t = distance_t;
            intersection.normal = estimateNorm(queryPoint);
            intersection.material_id = obj.material_id;
            return intersection;
        }
        distance_t += obj.distance_t;
    }
    return intersection;
}

float softShadow(vec3 rOrigin, vec3 rDir, float mint, float maxt, float k)
{
    float res = 1.0;
    for (float t = mint; t < maxt;) {
        hitObj h = sceneSDF(rOrigin + rDir * t);
        if (h.distance_t < 0.001) {
            return 0.0;
        }
        res = min(res, k * h.distance_t / t);
        t += h.distance_t;
    }
    return res;
}

vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}

vec3 getSceneColor(vec2 uv)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    Ray lightRay = Ray(LIGHT_DIR, LIGHT_ORIGIN);
    // if (intersection.distance_t > 0.0)
    // {
    //     return intersection.normal;
    // }
    if (intersection.distance_t > 0.0)
    {
    //     vec3 albedo = vec3(softShadow(lightRay.origin, lightRay.direction, float(MIN_RAY_STEPS), float(MAX_RAY_STEPS), 2.f));
        vec3 albedo = vec3(1.f);
        vec3 light_vec = normalize(LIGHT_DIR - intersection.position);
        return albedo * max(0.1, dot(light_vec, estimateNorm(intersection.position)));
        // vec3 diffuseColor = vec3(1.0);

        // // Calculate the diffuse term for Lambert shading
        // float diffuseTerm = dot(normalize(intersection.normal), normalize(light_vec));
        // // Avoid negative lighting values
        // diffuseTerm = clamp(diffuseTerm, 0.0, 1.0);

        // float ambientTerm = 0.2;

        // float lightIntensity = diffuseTerm + ambientTerm;   //Add a small float value to the color multiplier
        //                                                     //to simulate ambient lighting. This ensures that faces that are not
        //                                                     //lit by our point light are not completely black.

        // // Compute final shaded color
        // return vec3(diffuseColor * lightIntensity);
    }
    vec3 a = vec3(0.000, 0.500, 0.500);
    vec3 b = vec3(0.000, 0.500, 0.500);
    vec3 c = vec3(0.000, 0.218, -0.002);
    vec3 d = vec3(0.000, -0.032, 0.028);
    vec3 back_col = palette(distance(uv, LIGHT_ORIGIN.xy), a, b, c, d);
    #if GAMMA
    back_col = pow(back_col, vec3(1.f, 1.f, 1. / 2.2));
    #endif
    return back_col;
}

void main() {
    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fs_Pos;
    
    // Make symmetric [-1, 1]
    // uv = uv * 2.0 - 1.0;

    // Time varying pixel color
    vec3 col = getSceneColor(uv);

    // Output to screen
    out_Col = vec4(col,1.0);
    // out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
}
