#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

// Ray Constants
const float PI = 3.141592653589793238;
const int MAX_RAY_STEPS = 150;
const float EPSILON = 0.0001;

// Useful ray structs
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

struct DirectionalLight 
{
    vec3 dir;
    vec3 color;
    float ambient;
    float specular; // ranges 0 to 1 depending on how much specularity you want
    int hasShadow; // 1 if it casts a shadow, 0 if it doesn't cast a shadow
};

struct Material
{
    vec3 color;
    float specular;
    float shininess;
};

struct Object
{
    Material material;
    int id;
};

// Operations

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); }

float smin(float a, float b, float k)
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float opSmoothIntersection( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) + k*h*(1.0-h);
}

vec3 opRep( in vec3 p, in vec3 c)
{
    vec3 q = mod(p+0.5*c,c)-0.5*c;
    return q;
}

vec3 opRepLim( vec3 pos, vec3 freq, vec3 limitA, vec3 limitB)
{
    vec3 q = pos - freq*clamp(round(pos/freq), limitA, limitB);
    return q;
}

float sawtooth_wave(float x, float freq, float amplitude)
{
    return (x * freq - floor(x * freq)) * amplitude;
}

float cubicPulse( float c, float w, float x )
{
    x = abs(x - c);
    if (x > w) return 0.0;
    x /= w;
    return 1.0 - x * x *(3.0 - 3.0 *x);
}

float pcurve( float x, float a, float b )
{
    float k = pow(a + b, a + b) / (pow(a, a) * pow(b,b));
    return k * pow(x, a) * pow(1.0 - x, b);
}

mat3 rotationX( in float angle ) {
	return mat3(	1.0,		0,			0,
			 		0, 	cos(angle),	-sin(angle),
					0, 	sin(angle),	 cos(angle));
}

mat3 rotationY( in float angle ) {
	return mat3(	cos(angle),		0,	sin(angle),
			 		0, 	            1.0,	        0,
					-sin(angle), 	0,	 cos(angle));
}

mat3 rotationZ( in float angle ) {
	return mat3(	cos(angle),		-sin(angle),    0,
			 		sin(angle), 	 cos(angle),    0,
					        0,          0,          1.0);
}

vec3 rgb(vec3 color) {
    return vec3(color.x / 255.0, color.y / 255.0, color.z / 255.0);
}

// SDF objects

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

float sdfBox(vec3 query_position, vec3 pos, vec3 size)
{
  vec3 q = abs(query_position - pos) - size;
  return min(max(q.x,max(q.y,q.z)), 0.0) + length(max(q,0.0));
}

float sdfPlane(vec3 query_position, vec3 pos, vec3 norm, float h )
{
  vec3 q = query_position - pos;
  return dot(q,normalize(norm)) + h;
}

float sdfRoundBox( vec3 query_position, vec3 pos, vec3 size, float round )
{
  vec3 q = abs(query_position - pos) - size;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - round;
}

float sdfRoundedCylinder( vec3 query_position, vec3 p, float ra, float rb, float h )
{
    vec3 q = query_position - p;
    vec2 d = vec2( length(q.xz)-2.0*ra+rb, abs(q.y) - h );
    return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
}

float sdfCapsule( vec3 query_position, vec3 p, vec3 a, vec3 b, float r )
{
    vec3 q = query_position - p;
    vec3 pa = q - a, ba = b - a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h ) - r;
}

float sdfPendulum(vec3 query_position, vec3 position, float amp, float radius)
{
    float swingDisplacementY = 1.6;
    float swingDisplacementX = 8.0 / 1.8;
    
    float pulse_a = -1.8;
    float pulse_b = 1.0;
    float pulse_v = smoothstep(pulse_a, pulse_b,cos( 0.5 * 0.05 * u_Time ));
    float pulse_h = amp * cos(0.25 * 0.05 * u_Time );

    vec3 pendulumBottom = vec3(0.0);
    vec3 pendulumTop = vec3(0.0, 8.0, 0.0);

    pendulumBottom = vec3(pendulumBottom.x, pulse_v * swingDisplacementY, pulse_h * swingDisplacementX);

    float cap = sdfCapsule(query_position, position, pendulumBottom, pendulumTop, radius);
    float sphere = sdfSphere(query_position, pendulumBottom + position, radius * 10.0);

    return smin(cap, sphere, 0.1);
}

float sdCappedTorus(vec3 query_position, vec3 pos, vec2 sc, float ra, float rb)
{
    vec3 q = query_position - pos;
    q.x = abs(q.x);
    float k = (sc.y*q.x>sc.x*q.y) ? dot(q.xy,sc) : length(q.xy);
    return sqrt( dot(q,q) + ra*ra - 2.0*ra*k ) - rb;
}

float sdfGong(vec3 query_position, vec3 pos, mat3 gongTransform, out float innerGong, out float baseGong, out float beams) {
    float gongRadius = 0.7;
    float gongDepth = 0.1;

    vec3 gongPos = gongTransform * pos;
    vec3 gongQuery = gongTransform * query_position;
    baseGong = sdfRoundedCylinder(gongQuery, gongPos, gongRadius, 0.05, gongDepth);
    innerGong = sdfRoundedCylinder(gongQuery, vec3(gongPos.x, gongPos.y - 0.1, gongPos.z), gongRadius * 0.7, 0.05, gongDepth * 1.2);

    vec3 beamSize_h = vec3(2.3, 0.1, 0.15);
    vec3 beamSize_v = vec3(0.08, 3.0, 0.08);
    float beam_h1 = sdfRoundBox(query_position, vec3(pos.x, pos.y - 2.0, pos.z), beamSize_h, 0.03);
    float beam_h2 = sdfRoundBox(query_position, vec3(pos.x, pos.y + 2.0, pos.z), beamSize_h, 0.03);
    float beam_h3 = sdfRoundBox(query_position, vec3(pos.x, pos.y + 2.6, pos.z), beamSize_h, 0.03);
    float beam_v1 = sdfRoundBox(query_position, vec3(pos.x - 1.8, pos.y, pos.z), beamSize_v, 0.03);
    float beam_v2 = sdfRoundBox(query_position, vec3(pos.x + 1.8, pos.y, pos.z), beamSize_v, 0.03);

    float gong =  min(baseGong, innerGong);
    float beamsHorizontal = min(beam_h1, min(beam_h2, beam_h3));
    float beamsVertical = min(beam_v1, beam_v2);
    beams = smin(beamsVertical, beamsHorizontal, 0.05);
    return min(gong, beams);
}

float sceneSDF(vec3 queryPos, out Object obj) 
{
    vec3 center = vec3(0.0, 0.0, 0.0);
    vec3 floorPos = vec3(0.0, 0.0, 0.0);
    float floorHeight = 1.0;
    float floorPlane = sdfPlane(queryPos, floorPos, vec3(0.0, 1.0, 0.0), floorHeight);
    float zPlane = sdfPlane(queryPos, vec3(floorPos.x + 50.0, floorPos.y, floorPos.z), vec3(-1.0, 0.0, 0.0), floorHeight);
    float yPlane = sdfPlane(queryPos, vec3(floorPos.x, floorPos.y, floorPos.z - 50.0), vec3(0.0, 0.0, 1.0), floorHeight);
    float walls = smin(yPlane, zPlane, 0.5);
    float floorAndWalls = smin(floorPlane, walls, 0.5);

    obj.id = 1;

    // Implement bounding sphere to optimize
    float bounding_box= sdfBox(queryPos, center, vec3(10.0));
    if (bounding_box < EPSILON) {

        // Repeating box size parameters
        float cylinderBlockSize = 4.0;

        // Set bounds of the repeating shelf blocks
        vec3 limitA = vec3(-1.0, 0.0, -1.0) * cylinderBlockSize;
        vec3 limitB = vec3(1.0, 0.0, 1.0) * cylinderBlockSize;
        float repSpace = 0.9;
        vec3 repeatingPos = opRepLim(queryPos, vec3(repSpace), limitA, limitB);
        
        vec3 floorCylinder_p = vec3(0.0, -1.0, 0.0);
        float floorCylinder_h = 2.0;
        float floorCylinder_r = 0.15;
        float floorCylinder_edge = 0.1;
        float floorCylinders = sdfRoundedCylinder(repeatingPos, floorCylinder_p, floorCylinder_r, floorCylinder_edge, floorCylinder_h);

        vec3 cylinder_p = vec3(0.0, -1.0, 0.0);
        float cylinder_r = floorCylinder_r * 0.9;
        float stair_length = repSpace;
        float stair_freq = 0.5;
        float stair_val = 0.05 * u_Time + floor((queryPos.x - (repSpace + cylinder_r * 2.0) - 0.02) / stair_length) + 2.0;
        float dynamic_height = cos(stair_freq* stair_val);
        float cylinder_h = 1.0 + dynamic_height;
        float cylinder_edge = 0.05;

        float cylinders = sdfRoundedCylinder(repeatingPos, cylinder_p, cylinder_r, cylinder_edge, cylinder_h);
        
        // Create a swinging pendulum
        vec3 pendulumPos = vec3(0.0, 0.0, 0.0);
        float pendulum = sdfPendulum(queryPos, pendulumPos, 1.1, 0.05);

        // Create gongs
        vec3 gong1Pos = vec3(0.0, 1.5, 5.6);
        mat3 gong1Transform = rotationX(PI/2.0);
        vec3 gong2Pos = vec3(0.0, 1.5, -5.6);
        mat3 gong2Transform = rotationX(3.0 * PI / 2.0);

        float innerGong1;
        float baseGong1;
        float beams1;
        float gong1 = sdfGong(queryPos, gong1Pos, gong1Transform, innerGong1, baseGong1, beams1);
        
        float innerGong2;
        float baseGong2;
        float beams2;
        float gong2 = sdfGong(queryPos, gong2Pos, gong2Transform, innerGong2, baseGong2, beams2);

        // Put it all together
        floorPlane = opSmoothSubtraction(floorCylinders, floorPlane, 0.05);
        floorAndWalls = smin(floorPlane, walls, 1.0);
        float allCylinders = min(cylinders, floorAndWalls);
        float innerGongs = min(innerGong1, innerGong2);
        float baseGongs = min(baseGong1, baseGong2);
        float beams = min(beams1, beams2);
        float gongs = min(gong1, gong2);
        float pendulumAndGongs = min(pendulum, gongs);

        // Assign object materials
        float final = min(allCylinders, pendulumAndGongs);

        if (final == floorPlane) { obj.id = 1;}
        else if (final == cylinders) {obj.id = 2;}
        else if (final == innerGongs) {obj.id = 3;}
        else if (final == baseGongs) {obj.id = 4;}
        else if (final == beams) {obj.id = 5;}
        else if (final == pendulum) {obj.id = 6;}

        return final;
    }
    return floorAndWalls;
}

Ray getRay(vec2 uv)
{
    Ray r;

    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = cross(look, u_Up);

    float FOV = PI / 4.0;
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = u_Up * tan(FOV); 
    vec3 screen_horizontal = camera_RIGHT * aspect_ratio * tan(FOV);
    vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Ref);
   
    return r;
}

vec3 estimateNormal(vec3 p, out Object obj)
{
    vec2 d = vec2(0.0, EPSILON);
    float x = sceneSDF(p + d.yxx, obj) - sceneSDF(p - d.yxx, obj);
    float y = sceneSDF(p + d.xyx, obj) - sceneSDF(p - d.xyx, obj);
    float z = sceneSDF(p + d.xxy, obj) - sceneSDF(p - d.xxy, obj);

    return normalize(vec3(x, y, z));
}

// Light and Shadows
float shadow(vec3 ro, vec3 rd, float maxt, float k, out Object obj)
{
    float res = 1.0;
    for(float t=0.015; t<maxt;) 
    {
        vec3 queryPoint = ro + rd * t;
        float currDistance = sceneSDF(queryPoint, obj);

        if (currDistance < 0.001){
            return 0.0;
        }

        res = min(res, k*currDistance/t);
        t += currDistance;
    }
    return res;
}

// Gets light for directional lights. If hasShadow == 1 then shadows are on, otherwise they are off 
float getDirLight(Intersection intersection, DirectionalLight light, out Object obj)
{
    // Diffuse shading
    float diffuse = dot(normalize(intersection.normal), light.dir);
    diffuse = clamp(diffuse, 0.0, 1.0);

    // Specular shading
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 reflectDir = reflect(light.dir, intersection.normal);  
    float spec = pow(max(dot(reflectDir, look), 0.0), 1.0 / obj.material.shininess); // why is my shininess inverted...?
    float specular = light.specular * obj.material.specular * spec;

    // Calculate shadows
    float shadowVal = 1.0;
    if (light.hasShadow == 1) {
        shadowVal = shadow(intersection.position, light.dir, 50.0, 30.0, obj);
        shadowVal = clamp(shadowVal, 0.3, 1.0);
    }

    return (diffuse + light.ambient + specular) * shadowVal;
}

vec3 computeMaterial(Intersection intersection, out Object obj) {

    vec3 warmCol = vec3(1.0, 0.88, 0.8);
    DirectionalLight warmLight = DirectionalLight(normalize(vec3(1.0, 0.5, 1.0)),
                                warmCol, 0.2, 0.0, 0);

    vec3 coolCol = vec3(0.8, 0.88, 1.0);                           
    DirectionalLight coolLight = DirectionalLight(normalize(vec3(-3.0, 0.5, -2.0)),
                                coolCol, 0.2, 1.0, 1);

    vec3 topCol = vec3(0.8, 0.88, 0.9);
    DirectionalLight topLight = DirectionalLight(normalize(vec3(0.0, 0.5, 0.0)),
                                topCol, 0.2, 0.0, 0);
                                
    vec3 albedo;

    // Create materials
    Material floorMat = Material(rgb(vec3(230.0, 189.0, 181.0)), 0.0, 0.0);
    Material cylinderMat = Material(rgb(vec3(235.0, 126.0, 126.0)), 1.0, 0.04);
    Material innerGongMat = Material(rgb(vec3(250.0, 250.0, 250.0)), 1.0, 0.1);
    Material baseGongMat = Material(rgb(vec3(50.0, 50.0, 50.0)), 1.0, 0.1);
    Material beamMat = Material(rgb(vec3(241.0, 187.0, 147.0)), 1.0, 0.1);
	Material pendulumMat = Material(rgb(vec3(241.0, 187.0, 147.0)), 2.0, 0.015);

    switch(obj.id)
    {
        case -1: // not any object
            obj.material = floorMat;
            break;
            
        case 1: // floor
            obj.material = floorMat;
            break;

        case 2: // cylinders
            obj.material = cylinderMat;
            break;

        case 3: // inner gongs
            obj.material = innerGongMat;
            break;

        case 4: // base gongs
            obj.material = baseGongMat;
            break;

        case 5: // beams
            obj.material = beamMat;
            break;

        case 6: // pendulum
            obj.material = pendulumMat;
            break;
    }

    vec3 totalLight = 0.7 * warmLight.color * getDirLight(intersection, warmLight, obj);

    totalLight += 0.9 * coolLight.color * getDirLight(intersection, coolLight, obj);
    totalLight += 0.4 * topLight.color * getDirLight(intersection, topLight, obj);

    vec3 color = obj.material.color * totalLight;
    return color;
}


Intersection getRaymarchedIntersection(vec2 uv)
{
    Intersection intersection;
    intersection.distance_t = -1.0;

    Ray r = getRay(uv);
    float t = 0.0;
    Object obj;

    for(int step; step < MAX_RAY_STEPS; ++step) 
    {
        vec3 queryPoint = r.origin + r.direction * t;
        float currDistance = sceneSDF(queryPoint, obj);
        if (currDistance < EPSILON) {
            // found an intersection
            intersection.distance_t = t;
            intersection.normal = estimateNormal(queryPoint, obj);
            intersection.position = queryPoint;
            vec3 material = computeMaterial(intersection, obj);
            intersection.color = material;
            return intersection;
        }
        t += currDistance;
    }
    return intersection;
}

vec3 getSceneColor(vec2 uv)
{
    float t = 0.0;
    Intersection intersection = getRaymarchedIntersection(uv);

    if (intersection.distance_t > 0.0)
    {
        return intersection.color;
     }

     return vec3(0.0f);
}

void main() {
    vec2 uv = vec2(fs_Pos.x, fs_Pos.y);
    out_Col = vec4(getSceneColor(uv), 1.0);
    Ray r = getRay(uv);
    //out_Col = vec4(0.5 * (r.direction + vec3(1.0, 1.0, 1.0)), 1.0);
}