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

const vec3 EYE = vec3(0.0, 0.0, -10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const vec3 LIGHT_DIR = vec3(-1.0, -1.0, -2.0);


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
    return sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 1.0);
}

Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 look = normalize(ORIGIN - EYE);
    vec3 camera_RIGHT = normalize(cross(WORLD_UP, look));
    vec3 camera_UP = cross(camera_RIGHT, look);
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = camera_UP * tan(FOV); 
    vec3 screen_horizontal = camera_RIGHT * aspect_ratio * tan(FOV);
    vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = EYE;
    r.direction = normalize(screen_point - EYE);
   
    return r;
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Intersection intersection;    
    intersection.distance_t = -1.0;
    
    float distancet = 0.0f;
    
    Ray r = getRay(uv);
    for(int step; step < MAX_RAY_STEPS; ++step)
    {
        vec3 queryPoint = r.origin + r.direction * distancet;
        float currentDistance = sceneSDF(queryPoint);
        if(currentDistance < EPSILON)
        {
            // We hit something
            intersection.distance_t = distancet;
            
            //intersection.normal = estimateNormal(queryPoint);
            
            return intersection;
        }
        distancet += currentDistance;
        
    }
    
    return intersection;
}

vec3 getSceneColor(vec2 uv)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    if (intersection.distance_t > 0.0)
    { 
        return vec3(1.0);
    }
    return vec3(0.0);
}

void main()
{
    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fs_Pos/u_Dimensions.xy;
    
    // Make symmetric [-1, 1]
    uv = uv * 2.0 - 1.0;

    // Time varying pixel color
    vec3 col = getSceneColor(uv);

    // Output to screen
    out_Col = vec4(col,1.0);
}

/*
void main() 
{
  out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
}
*/

