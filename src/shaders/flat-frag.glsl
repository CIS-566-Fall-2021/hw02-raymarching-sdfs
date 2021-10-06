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

const vec3 EYE = vec3(0.0, 0.0, 10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(-1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const vec3 LIGHT_DIR = vec3(-1.0, 1.0, -1.0);

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

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float sceneSDF(vec3 queryPos) 
{
    float s1 = sdfSphere(queryPos, vec3(-2.f, -3.f, 0.f), 2.5);
    // return s1;
    // return sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 0.2);
    return smin(sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 0.2),
                sdfSphere(queryPos, vec3(cos(u_Time) * 2.0, 0.0, 0.0), abs(cos(u_Time))), 0.2);
    
}

Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 look = normalize(ORIGIN - EYE);
    vec3 camera_RIGHT = normalize(cross(look, WORLD_UP));
    vec3 camera_UP = cross(camera_RIGHT, look);
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = camera_UP * tan(FOV); 
    vec3 screen_horizontal = camera_RIGHT * aspect_ratio * tan(FOV);
    vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = EYE;
    r.direction = normalize(screen_point - EYE);
   
    return r;
}

vec3 estimateNorm(vec3 p)
{
    vec2 d = vec2(0.f, EPSILON);
    float x = sceneSDF(p + d.yxx) - sceneSDF(p - d.yxx);
    float y = sceneSDF(p + d.xyx) - sceneSDF(p - d.xyx);
    float z = sceneSDF(p + d.xxy) - sceneSDF(p - d.xxy);
    
    return normalize(vec3(x, y, z));
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Intersection intersection;
    
    intersection.distance_t = -1.0;
    Ray ray = getRay(uv);
    float distance_t = 0.f;
    for (int step = 0; step < MAX_RAY_STEPS; ++step) {
        vec3 queryPoint = ray.origin + ray.direction * distance_t;
        float currDist = sceneSDF(queryPoint);
        if (currDist < EPSILON) {
            intersection.position = queryPoint;
            intersection.distance_t = distance_t;
            intersection.normal = estimateNorm(queryPoint);
            return intersection;
        }
        distance_t += currDist;
    }
    return intersection;
}

float softShadow(vec3 ro, vec3 rd, float mint, float maxt, float k)
{
    float res = 1.0;
    for (float t = mint; t < maxt;) {
        float h = sceneSDF(ro + rd * t);
        if (h < 0.001) {
            return 0.0;
        }
        res = min(res, k * h / t);
        t += h;
    }
    return res;
}

vec3 getSceneColor(vec2 uv)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    // if (intersection.distance_t > 0.0)
    // {
    //     return intersection.normal;
    // }
    // return vec3(0.0f);
    if (intersection.distance_t > 0.0)
    {
        vec3 light_vec = normalize(LIGHT_DIR - intersection.position);
        return vec3(1.0) * max(0.1, dot(light_vec, estimateNorm(intersection.position)));
    }
    return vec3(0.0f);
}

// void mainImage( out vec4 fragColor, in vec2 fragCoord )
// {
//     // Normalized pixel coordinates (from 0 to 1)
//     vec2 uv = fragCoord/iResolution.xy;
    
//     // Make symmetric [-1, 1]
//     uv = uv * 2.0 - 1.0;

//     // Time varying pixel color
//     vec3 col = getSceneColor(uv);

//     // Output to screen
//     fragColor = vec4(col,1.0);
// }

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
