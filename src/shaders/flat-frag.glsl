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

const float PI = 3.14159265359;

const float FAR_CLIP = 1e10;

const float AMBIENT = 0.2;

const vec3 EYE = vec3(0.0, 0.0, -10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const vec3 LIGHT_DIR = vec3(-1.0, 1.0, 2.0);


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


// Operation functions

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}


vec3 rotateAboutX(vec3 point, float theta)
{
    float cosTheta = cos(theta);
    float sinTheta = sin(theta);
    point.yz = mat2(cosTheta, -sinTheta, sinTheta, cosTheta) * point.yz;
    return point;
}


vec3 rotateAboutY(vec3 point, float theta)
{
    float cosTheta = cos(theta);
    float sinTheta = sin(theta);
    point.xz = mat2(cosTheta, -sinTheta, sinTheta, cosTheta) * point.xz;
    return point;
}

vec3 rotateAboutZ(vec3 point, float theta)
{
    float cosTheta = cos(theta);
    float sinTheta = sin(theta);
    point.xy = mat2(cosTheta, -sinTheta, sinTheta, cosTheta) * point.xy;
    return point;
}


vec3 rotateXYZ(vec3 point, float thetaX, float thetaY, float thetaZ)
{
    point = rotateAboutX(point, thetaX);
    point = rotateAboutY(point, thetaY);
    point = rotateAboutZ(point, thetaZ);

    return point;
}


float unionSDF(float distance1, float distance2)
{
    return min(distance1, distance2);
}

float smoothSubtraction( float d1, float d2, float k ) 
{
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); 
}


float cubicPulse(float c, float w, float x)
{
    x = abs(x - c);
    if(x > w) return 0.0f;
    x /= w;
    return 1.0f - x * x * (3.0f - 2.0f * x);
}


float polyImpulse(float k, float n, float x)
{
    return (n / (n - 1.0)) * pow((n - 1.0) * k, 1.0 / n) * x / (1.0 + k * pow(x, n));
}


float quaImpulse( float k, float x )
{
    return 2.0*sqrt(k)*x/(1.0+k*x*x);
}


// SDF primitives

// Creates a box with dimensions dimensions
float sdfBox( vec3 position, vec3 dimensions )
{
    vec3 d = abs(position) - dimensions;
    return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

// Creates a sphere
float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}


float sdfRoundedCylinder( vec3 p, float ra, float rb, float h )
{
  vec2 d = vec2( length(p.xz)-2.0*ra+rb, abs(p.y) - h );
  return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
}


// Creates a plane
float heightField(vec3 queryPos, float planeHeight)
{
    return queryPos.y - planeHeight;
}

float sdfCapsule( vec3 point, vec3 pointA, vec3 pointB, float radius )
{
	vec3 pa = point - pointA;
    vec3 ba = pointB - pointA;
	float h = clamp( dot(pa, ba) / dot(ba, ba), 0.0, 1.0 );
	return length( pa - ba * h ) - radius;
}


float sdfTorus( vec3 point, float radius, float thickness)
{
    return length(vec2(length(point.xy)- radius, point.z)) - thickness;
}


// Describe the scene using sdf functions
float sceneSDF(vec3 queryPos) 
{
    float closestPointDistance = 1e10;

    // Add floor
    closestPointDistance = unionSDF(heightField(queryPos, -2.0), closestPointDistance);

    // Bounding box to improve performance
    if(sdfBox(queryPos, vec3(5.0, 5.0, 5.0) ) < closestPointDistance)
    {
        // Add body
        vec3 bodyPos = rotateXYZ(queryPos, PI / 10.0,  PI / 4.0, 0.0);
        float cube = sdfBox(bodyPos, vec3(0.5, 0.5, 0.5));
        closestPointDistance = unionSDF(cube, closestPointDistance);
        
        // Add head
        closestPointDistance = unionSDF(sdfSphere(queryPos, vec3(0.0, 1.3, 0.3), 0.6), closestPointDistance);

        // Add face
        vec3 shiftedFace = queryPos - vec3(-0.13, 1.3, 0.6);
        shiftedFace = rotateAboutX(shiftedFace, PI / 2.0);
        // Make robot abruptly turn head to look at camera
        shiftedFace = rotateAboutZ(shiftedFace, PI / 5.0 - quaImpulse(2.0, clamp(sin(u_Time * 0.05), 0.0, 1.0)) / 2.0);


        float scubaMask = sdfRoundedCylinder(shiftedFace, 0.2, 0.1, 0.2);
        float negMask = sdfRoundedCylinder(shiftedFace, 0.15, 0.05, 0.5);
        scubaMask = smoothSubtraction(negMask, scubaMask, 0.0);

        closestPointDistance = unionSDF(scubaMask, closestPointDistance);

        // Add right upper arm
        closestPointDistance = unionSDF(sdfCapsule(queryPos - vec3(-0.8, -0.4, -0.4), 
                                                    vec3(-0.6, 0.3, 0.1), 
                                                    vec3(0.2, 0.8, 0.2), 0.1), 
                                                    closestPointDistance);

        // Add right lower arm
        closestPointDistance = unionSDF(sdfCapsule(queryPos - vec3(-0.8, -0.4, -0.4), 
                                                    vec3(-0.6, 0.3, 0.1), 
                                                    vec3(-0.9, 0.3, 0.9), 0.1), 
                                                    closestPointDistance);


        // Upper left arm
        closestPointDistance = unionSDF(sdfCapsule(queryPos - vec3(0.8, 0.0, 0.2), 
                                                    vec3(-0.4, 0.3, 0.3), 
                                                    vec3(0.6, 0.2, -0.4), 0.1), 
                                                    closestPointDistance);

        // Lower left arm
        closestPointDistance = unionSDF(sdfCapsule(queryPos - vec3(0.8, -0.6, 0.2), 
                                                vec3(0.4, 0.0, 0.5), 
                                                  vec3(0.6, 0.8, -0.4), 0.1), 
                                                  closestPointDistance);


        // Add right upper leg
        closestPointDistance = unionSDF(sdfCapsule(queryPos - vec3(-0.8, -1.4, -0.4), 
                                                    vec3(0.2, 0.4, 0.1), 
                                                    vec3(0.6, 1.0, -0.2), 0.1), 
                                                    closestPointDistance);

        // Add right lower leg
        float rightLowerLeg = sdfCapsule(queryPos - vec3(-0.8, -1.4, -0.4), 
                                                    vec3(0.2, 0.4, 0.1), 
                                                    vec3(0.38, -0.2, -0.1), 0.1);


        // Add left upper leg
        closestPointDistance = unionSDF(sdfCapsule(queryPos - vec3(-0.4, -1.6, 0.1), 
                                                    vec3(0.8, 0.7, -0.4), 
                                                    vec3(0.6, 1.0, 0.0), 0.1), 
                                                    closestPointDistance);

        // Add left lower leg
        float leftLowerLeg = sdfCapsule(queryPos - vec3(-0.4, -1.6, 0.1), 
                                                    vec3(0.8, 0.7, -0.4), 
                                                    vec3(1.2, 0.85, -0.9), 0.1);


        // Right wheel
        vec3 rightWheelPos = rotateAboutY(queryPos - vec3(-0.4, -1.8, -0.5), -PI / 4.0);
        float rightWheel = sdfTorus(rightWheelPos, 0.18, 0.07);

        // Smooth blend the lower leg and the foot/wheel
        float rightLegAndWheel = smin(rightLowerLeg, rightWheel, 0.1);

        closestPointDistance = unionSDF(rightLegAndWheel, closestPointDistance);

        // Left wheel
        vec3 leftWheelPos = rotateAboutY(queryPos - vec3(0.9, -0.7, -0.9), -PI / 4.0);
        float leftWheel = sdfTorus(leftWheelPos, 0.18, 0.07);

        // Smooth blend the lower leg and the foot/wheel
        float leftLegAndWheel = smin(leftLowerLeg, leftWheel, 0.1);

        closestPointDistance = unionSDF(leftLegAndWheel, closestPointDistance);

        // Add antenna ball
        vec3 antennaPos = vec3(0.0, 1.0, 0.0);
        antennaPos = rotateAboutX(antennaPos, cos(u_Time * 0.4) / 10.0 + 0.1);
        antennaPos = rotateAboutZ(antennaPos, cos(u_Time * 0.4) / 10.0 + 0.1);
        antennaPos += vec3(0.0, 1.3, 0.4);
        closestPointDistance = unionSDF(sdfSphere(queryPos, antennaPos, 0.1), closestPointDistance);

        // Add antenna
        closestPointDistance = unionSDF(sdfCapsule(queryPos, 
                                                    vec3(0.0, 1.8, 0.5), 
                                                    antennaPos, 0.01), 
                                                    closestPointDistance);

    }

    return closestPointDistance;

    /*
    return smin(sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 0.2),
                sdfSphere(queryPos, vec3(cos(u_Time / 100.0) * 2.0, 0.0, 0.0), 0.2), 0.2);//abs(cos(u_Time / 100.0))), 0.2);
    */
}

Ray getRay(vec2 uv)
{    
    // Rachel's implemenation
    /*
    Ray r;

    vec3 look = normalize(ORIGIN - EYE);
    vec3 camera_RIGHT = normalize(cross(forward, WORLD_UP));
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
    vec3 right = normalize(cross(forward, u_Up));

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
    normal[0] = sceneSDF(vec3(p.x + EPSILON, p.y, p.z)) - sceneSDF(vec3(p.x - EPSILON, p.y, p.z));
    normal[1] = sceneSDF(vec3(p.x, p.y + EPSILON, p.z)) - sceneSDF(vec3(p.x, p.y - EPSILON, p.z));
    normal[2] = sceneSDF(vec3(p.x, p.y, p.z + EPSILON)) - sceneSDF(vec3(p.x, p.y, p.z - EPSILON));

    return normalize(normal);
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


float softShadow(vec3 rayOrigin, vec3 rayDirection, float minT, float maxT, float k)
{
    float result = 1.0;
    for(float t = minT; t < maxT; )
    {
        float h = sceneSDF(rayOrigin + rayDirection * t);
        if(h < EPSILON)
        {
            return 0.0;
        }
        result = min(result, k * h / t);
        t += h;
    }

    return result;
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

            intersection.position = queryPoint;
            
            return intersection;
        }
        distancet += currentDistance;
        
    }
    
    return intersection;
}

vec3 getSceneColor(vec2 uv)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    
    // Note that I flipped the camera to be at (0, 0, 3) instead of (0, 0, -10)
    // So that we are closer to the scene and so that positive blue normals face towards camera
    //return 0.5 * (getRay(uv).direction + vec3(1.0, 1.0, 1.0));

    if (intersection.distance_t > 0.0)
    { 
        //return intersection.normal;//vec3(1.0);

        // Material base color
        vec3 diffuseColor = vec3(0.7, 0.4, 0.3);

        // Lambert shading
        // Calculate the diffuse term
        float diffuseTerm = dot(normalize(intersection.normal), normalize(LIGHT_DIR));
        
        diffuseTerm = clamp(diffuseTerm, 0.0f, 1.0f);

        float lightIntensity = diffuseTerm;  

        // Compute lambert color
        vec3 lambertColor = diffuseColor * lightIntensity;

        // Compute shadow
        float shadowFactor = hardShadow(intersection.position, normalize(LIGHT_DIR), EPSILON * 100.0, 10.0);
        
        vec3 colorMinusShadowing = (shadowFactor + AMBIENT) * lambertColor;

        return colorMinusShadowing;

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

