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
    //return sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 1.0);

    return smin(sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 0.2),
                sdfSphere(queryPos, vec3(cos(u_Time / 100.0) * 2.0, 0.0, 0.0), 0.2), 0.2);//abs(cos(u_Time / 100.0))), 0.2);
}

Ray getRay(vec2 uv)
{    
    // Rachel's implemenation
    /*
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
    */

    Ray r;

    vec3 forward = u_Ref - u_Eye;
    float len = length(forward);
    forward = normalize(forward);
    vec3 right = normalize(cross(u_Up, forward));
    
    float tanAlpha = tan(FOV / 2.0);
    float aspectRatio = u_Dimensions.x / u_Dimensions.y;

    vec3 V = u_Up * len * tanAlpha;
    vec3 H = right * len * aspectRatio * tanAlpha;

    vec3 pointOnScreen = u_Ref + uv.x * H + uv.y * V;

    vec3 rayDirection = normalize(pointOnScreen - u_Eye);

    r.origin = u_Eye;
    r.direction = rayDirection;

    return r;
}

vec3 estimateNormal(vec3 p)
{
    vec3 normal = vec3(0.0, 0.0, 0.0);
    normal[0] = sceneSDF(vec3(p.x - EPSILON, p.y, p.z)) - sceneSDF(vec3(p.x + EPSILON, p.y, p.z));
    normal[1] = sceneSDF(vec3(p.x, p.y - EPSILON, p.z)) - sceneSDF(vec3(p.x, p.y + EPSILON, p.z));
    normal[2] = sceneSDF(vec3(p.x, p.y, p.z - EPSILON)) - sceneSDF(vec3(p.x, p.y, p.z + EPSILON));

    return normalize(normal);
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
            
            intersection.normal = estimateNormal(queryPoint);
            
            return intersection;
        }
        distancet += currentDistance;
        
    }
    
    return intersection;
}

vec3 getSceneColor(vec2 uv)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    
    
    //return 0.5 * (getRay(uv).direction + vec3(1.0, 1.0, 1.0));

    if (intersection.distance_t > 0.0)
    { 
        return intersection.normal;//vec3(1.0);
    }
    return vec3(0.0);
}

void main()
{
    // Time varying pixel color
    vec3 col = getSceneColor(fs_Pos);

    // Output to screen
    out_Col = vec4(col,1.0);
}

