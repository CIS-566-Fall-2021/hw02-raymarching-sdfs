#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

float FOV = radians(30.);

// Toolbox functions
float bias(float b, float t) {
    return (t/((((1.0/b)-2.0)*(1.0-t))+1.0));
}

// Transform functions
vec3 rotateAroundY(vec3 p, float a){
    a = radians(a);
    return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
}

vec3 rotateAroundX(vec3 p, float a){
    a = radians(a);
    return vec3(p.x, cos(a) * p.y - sin(a) * p.z, sin(a) * p.y + cos(a) * p.z);
}

vec3 rotateAroundZ(vec3 p, float a){
    a = radians(a);
    return vec3(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y, p.z);
}

// Smooth functions
// From: https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm
float opSmoothUnion(float d1, float d2, float k){
	float h = clamp(0.5 + 0.5 * (d2 - d1)/k, 0.0, 1.0);
	return mix(d2, d1, h) - k * h * (1.0 - h);
}

float opSmoothSubtraction(float d1, float d2, float k){
    float h = clamp(0.5 - 0.5 * (d2 + d1)/k, 0.0, 1.0);
    return mix(d2, -d1, h) + k * h * (1.0 - h); 
}

float opSmoothIntersection(float d1, float d2, float k){
	float h = clamp(0.5 - 0.5 * (d2 - d1)/k, 0.0, 1.0);
	return mix(d2, d1, h) + k * h * (1.0 - h);
}

// SDF functions
float sdSphere(vec3 p, float s){
    return length(p) - s;
}

float sdBox(vec3 p, vec3 b){
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdCapsule(vec3 p, float h, float r){
  p.y -= clamp(p.y, 0.0, h);
  return length(p) - r;
}

float sdRoundedCylinder(vec3 p, float ra, float rb, float h){
  vec2 d = vec2(length(p.xz) - 2.0 * ra + rb, abs(p.y) - h);
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rb;
}

float sdWhiteGuy(vec3 pos){
    float head = sdSphere(pos, 1.5);
    float body = sdCapsule(pos + vec3(0., 4., 0.), 2., 0.8);
    float rightHand = sdCapsule(rotateAroundZ(pos + vec3(0.4, 2.5, 0.3), -50.), 3., 0.2);
    float leftHand = sdCapsule(rotateAroundZ(pos + vec3(0.4, 2.5, -1.), -40.), 3., 0.2);
    float rightLeg = sdCapsule(rotateAroundZ(pos + vec3(1., 7., 0.5), 15.), 3., 0.4);
    float leftLeg = sdCapsule(rotateAroundZ(pos + vec3(-2., 6., -0.7), -45.), 3., 0.4);
    float cap = sdSphere(pos + vec3(0., -0.5, 0.), 1.6);
    float capFront = sdRoundedCylinder(pos + vec3(1., -1., -1.), 0.5, 0.1, 0.02);

    head = opSmoothUnion(head, body, 0.3);
    head = opSmoothUnion(head, rightHand, 0.9);
    head = opSmoothUnion(head, leftHand, 0.9);
    head = opSmoothUnion(head, rightLeg, 0.9);
    head = opSmoothUnion(head, leftLeg, 0.9);
    head = min(head, opSmoothSubtraction(head, cap, 0.5));
    head = opSmoothUnion(head, capFront, 0.3);

    return head;
}

struct Intersection{
    float t;
    vec3 color;
    vec3 position;
    int objectIdx;
};

const int RAY_STEPS = 64;

// All the primitives
#define Ground1_SDF sdBox(rotateAroundY(pos + vec3(7., 5., -9.), 45.), vec3(13., 1.5, 8.))
#define Ground1_ID 0

#define Backwall_SDF sdBox(rotateAroundY(pos + vec3(9., -2., -11.), 45.), vec3(13., 6., 0.1))
#define Backwall_ID 1

#define Bridge_SDF sdBox(rotateAroundX(rotateAroundY(pos + vec3(2.3, 0.3, -4.), 55.), 10. + 50. * (bias(0.9, (sin(0.1 * u_Time) + 1.)/2.))), vec3(3., 0.2, 7.))
#define Bridge_ID 2

#define Cylinder_SDF sdRoundedCylinder(pos + vec3(15., -3.75, -2.), 1., 0.3, 7.)
#define Cylinder_ID 3

#define WhiteGuy_SDF sdWhiteGuy(rotateAroundY(pos + vec3(-12., -1.6, -6.), -30.))
#define WhiteGuy_ID 4

float sceneSDF(vec3 pos){
    float t = Ground1_SDF;

    t = min(t, Backwall_SDF);
    t = min(t, Bridge_SDF);
    t = min(t, Cylinder_SDF);
    t = min(t, WhiteGuy_SDF);
    
    return t;
}

vec3 computeNormal(vec3 pos){
    vec3 epsilon = vec3(0.0, 0.001, 0.0);
    return normalize(vec3(sceneSDF(pos + epsilon.yxx) - sceneSDF(pos - epsilon.yxx),
                          sceneSDF(pos + epsilon.xyx) - sceneSDF(pos - epsilon.xyx),
                          sceneSDF(pos + epsilon.xxy) - sceneSDF(pos - epsilon.xxy)));
}

void myScene(vec3 pos, out float t, out int obj){
    t = Ground1_SDF;
    obj = Ground1_ID;
    float tempT;
    
    if ((tempT = Ground1_SDF) < t){
        t = tempT;
        obj = Ground1_ID;
    }
    if ((tempT = Backwall_SDF) < t){
        t = tempT;
        obj = Backwall_ID;
    }
    if ((tempT = Bridge_SDF) < t){
        t = tempT;
        obj = Bridge_ID;
    }
    if ((tempT = Cylinder_SDF) < t){
        t = tempT;
        obj = Cylinder_ID;
    }
    if ((tempT = WhiteGuy_SDF) < t){
        t = tempT;
        obj = WhiteGuy_ID;
    }
}

void rayMarch(vec3 origin, vec3 dir, out float t, out int objHit){
    t = 0.001;
    
    for (int i = 0; i < RAY_STEPS; i++){
        float m;
        vec3 pos = origin + t * dir;
        
        myScene(pos, m, objHit);
        if (m < 0.01){
            return;
        }
        t += m;
    }
    
    t = -1.;
    objHit = -1;
}

float shadowMap(vec3 pos){
    float t = Bridge_SDF;

    t = min(t, WhiteGuy_SDF);

    return t;
}

float softShadow(vec3 dir, vec3 origin, float t_exp, float k){
    float result = 1.;
    float t = t_exp;
    
    for (int i = 0; i < RAY_STEPS; i++){
        float m = shadowMap(origin + t * dir);
        
        if (m < 0.0001){
            return 0.;
        }
        
        result = min(result, k * m / t);
        t += m;
    }

    return result;
}

vec3 myColor(int objHit, vec3 pos, vec3 nor, vec3 lightVec, vec3 view){
    float lambert = dot(-lightVec, nor);
    
    switch (objHit){
        case Ground1_ID:
        return vec3(0.72, 0.68, 0.59) * lambert;
        break;
        case Backwall_ID:
        return vec3(0.72, 0.68, 0.59) * lambert;
        break;
        case Bridge_ID:
        return vec3(0.69, 0.29, 0.23) * lambert;
        break;
        case Cylinder_ID:
        return vec3(0.32, 0.32, 0.35) * lambert;
        break;
        case WhiteGuy_ID:
        return vec3(1., 1., 1.) * lambert;
        break;
        case -1:
        return vec3(0.78, 0.79, 0.82);
        break;
    }
}

Intersection sdf(vec3 dir){
    float t;
    int objHit;
    
    rayMarch(u_Eye, dir, t, objHit);

    vec3 m_intersection  = u_Eye + t * dir;
    vec3 nor = computeNormal(m_intersection);
    vec3 lightPos = vec3(0., 6., 1.);
    vec3 lightDir = normalize(m_intersection  - lightPos);
    float softshadowCoeff = softShadow(-lightDir, m_intersection, 0.5, 14.);

    vec3 color = softshadowCoeff * myColor(objHit, m_intersection , nor, lightDir,
                 normalize(u_Eye - m_intersection));

    return Intersection(t, color, m_intersection, objHit);
}


vec3 GetRayCastDirection() {
  vec3 look = normalize(u_Ref - u_Eye);
  vec3 camera_RIGHT = normalize(cross(look, u_Up));
  vec3 camera_UP = cross(camera_RIGHT, look);

  float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
  vec3 screen_vertical = camera_UP * tan(FOV) * length(u_Ref - u_Eye);
  vec3 screen_horizontal = camera_RIGHT * aspect_ratio * tan(FOV) * length(u_Ref - u_Eye);
  vec3 screen_point = u_Ref + fs_Pos.x * screen_horizontal + fs_Pos.y * screen_vertical;

  vec3 dir = normalize(screen_point - u_Eye);

  return dir;
}

void main(){   
    vec3 dir = GetRayCastDirection();
    Intersection m_intersection = sdf(dir);
    
    // Ray casting check
    // vec3 color = 0.5 * (dir + vec3(1.0, 1.0, 1.0));
 
    out_Col = vec4(m_intersection.color, 1.0);
}
