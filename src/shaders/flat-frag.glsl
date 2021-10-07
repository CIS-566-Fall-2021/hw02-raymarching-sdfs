#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int RAY_STEPS = 256;
#define DEG_TO_RAD 3.14159 / 180.0
#define LIGHT_POS vec3(-8.0, 40.0, -12.0)
#define MAX_RAY_Z 50.0;

////////// GEOMETRY //////////
#define CENTER_TRI_SDF triangularPrism(rotateX(pos + vec3(0.0, 0.0, 0.0), -75.0), vec2(8.0, 1.0))
#define MIDDLE_TRI_SDF triangularPrism(rotateX(pos + vec3(0.0, -0.25, 0.0), -75.0), vec2(6.0, 1.0))
#define SWORD_HOLDER_SDF triangularPrism(rotateX(pos + vec3(0.0, -0.5, 0.0), 105.0), vec2(2.0, 1.0))
#define SWORD_BLADE_SDF box(pos + vec3(0.0, -3.0, 0.5), vec3(0.15, 1.8, 0.05))
#define SWORD_GUARD_SDF box(pos + vec3(0.0, -4.9, 0.5), vec3(0.3, 0.1, 0.1))
#define SWORD_HILT_SDF box(pos + vec3(0.0, -5.4, 0.5), vec3(0.1, 0.5, 0.08))
#define SWORD_QUAD_SDF box(rotateZ(pos + vec3(0.0, -3.8, 0.5), 45.0), vec3(0.22, 0.22, 0.05))

#define TOP_STEP_SDF roundBox(rotateX(rotateZ(pos + vec3(0.4, 1.95, 4.0), 2.0), 3.0), vec3(4.2, 1.0, 0.5), 0.25)
#define TOP_STEP_CONNECTOR_SDF roundedCylinder(rotateX(pos + vec3(-3.5, 2.3, 4.5), 3.0), 0.5, 0.7, 0.5)
#define MID_STEP_SDF roundBox(rotateX(rotateY(pos + vec3(0.0, 2.9, 4.8), -8.0), 3.0), vec3(4.2, 1.0, 0.5), 0.25)
#define BOT_STEP_SDF roundBox(rotateX(pos + vec3(0.4, 3.1, 5.2), 3.0), vec3(3.4, 0.4, 1.2), 0.25)
#define STEPS_SDF smoothBlend(TOP_STEP_SDF, smoothBlend(TOP_STEP_CONNECTOR_SDF, smoothBlend(MID_STEP_SDF, BOT_STEP_SDF, 0.1), 0.25), 0.25)

#define LEFT_FRONT_STONE_SDF roundBox(rotateX(pos + vec3(-7.5, 2.6, 4.0), 1.0), vec3(2.5, 1.5, 1.5), 0.2)
#define RIGHT_FRONT_STONE_SDF roundBox(rotateX(pos + vec3(7.5, 2.6, 4.0), 1.0), vec3(2.5, 1.5, 1.5), 0.5)

#define FLOOR_SDF plane(rotateX(pos + vec3(0.0, 1.6, 0.0), 5.0), vec4(0.0, 1.0, 0.0, 1.0))

#define BACK_BOTTOM_STEP_SDF roundBox(pos + vec3(0.0, -1.0, -20.0), vec3(7.0, 4.0, 1.5), 0.25)
#define BACK_TOP_STEP_SDF roundBox(pos + vec3(0.0, -5.0, -24.0), vec3(4.0, 4.0, 1.5), 0.25)
#define FLOATING_ROCK_SDF ellipsoid(pos + vec3(0.0, -23.0, -24.0) + vec3(0.0, 5.0, 0.0) * bias(0.8f, cos(u_Time / 4.f)), vec3(4.0, 8.0, 4.0))

// May add additional elements later
// #define RIGHT_TREE_TRUNK_SDF roundedCylinder(pos + vec3(14.0, 0.0, 0.0), 0.6, 0.8, 7.5)
// #define RIGHT_TREE_BRANCH1_SDF roundedCylinder(rotateZ(pos + vec3(20.0, -10.0, 0.5), -60.0), 0.4, 0.6, 7.0)
// #define RIGHT_TREE_BRANCH2_SDF roundedCylinder(rotateX(rotateZ(pos + vec3(13.0, -7.0, -2.0), 90.0), -60.0), 0.3, 0.5, 3.0)
// #define RIGHT_TREE_BRANCH3_SDF roundedCylinder(rotateZ(pos + vec3(8.0, -10.0, 0.0), 60.0), 0.3, 0.5, 7.0)
// #define RIGHT_TREE_SDF smoothBlend(RIGHT_TREE_BRANCH1_SDF, smoothBlend(RIGHT_TREE_BRANCH2_SDF, smoothBlend(RIGHT_TREE_BRANCH3_SDF, RIGHT_TREE_TRUNK_SDF, 1.0), 1.0), 1.0)

// #define TOP_ROOT1_SDF capsule(pos + vec3(2.0, -12.0, -4.0), vec3(-10.0, 0.0, 0.0), vec3(5.0, -2.2, 0.0), 2.5)
// #define TOP_ROOT2_SDF capsule(pos + vec3(-4.5, -9.0, -5.0), vec3(0.0, 0.0, -0.8), vec3(5.0, -6.0, 0.0), 2.3)
// #define TOP_ROOT_SDF smoothBlend(TOP_ROOT1_SDF, TOP_ROOT2_SDF, 1.0)
////////// GEOMETRY ENDS //////////

#define CENTER_TRI 0
#define MIDDLE_TRI 1
#define SWORD_HOLDER 2
#define SWORD_BLADE 3
#define SWORD_QUAD 4
#define SWORD_GUARD 5
#define SWORD_HILT 6
#define FLOOR 7
#define STEPS 8
#define LEFT_FRONT_STONE 9
#define RIGHT_FRONT_STONE 10
#define BACK_BOTTOM_STEP 11
#define BACK_TOP_STEP 12
#define FLOATING_ROCK 13

////////// SDFS //////////
float sphere(vec3 p, float s) {
  return length(p) - s;
}

float box(vec3 p, vec3 b) {
  return length(max(abs(p) - b, 0.0));
}

float plane(vec3 p, vec4 n) {
  return dot(p, n.xyz) + n.w;
}

float triangularPrism(vec3 p, vec2 h) {
  vec3 q = abs(p);
  return max(q.z - h.y, max(q.x * 0.866025 + p.y * 0.5, -p.y) - h.x * 0.5);
}

float roundBox(vec3 p, vec3 b, float r)
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float roundedCylinder(vec3 p, float ra, float rb, float h) {
  vec2 d = vec2(length(p.xz) - 2.0 * ra + rb, abs(p.y) - h);
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rb;
}

float roundCone(vec3 p, float r1, float r2, float h) {
  vec2 q = vec2(length(p.xz), p.y);
    
  float b = (r1 - r2) / h;
  float a = sqrt(1.0 - b * b);
  float k = dot(q, vec2(-b, a));
    
  if(k < 0.0) return length(q) - r1;
  if(k > a * h) return length(q - vec2(0.0, h)) - r2;
        
  return dot(q, vec2(a, b)) - r1;
}

float capsule( vec3 p, vec3 a, vec3 b, float r ) {
  vec3 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba)/dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

float verticalCapsule(vec3 p, float h, float r) {
  p.y -= clamp(p.y, 0.0, h);
  return length(p) - r;
}

float ellipsoid(vec3 p, vec3 r) {
  float k0 = length(p / r);
  float k1 = length(p / (r * r));
  return k0 * (k0 - 1.0) / k1;
}

float smoothBlend(float sdf1, float sdf2, float k) {
    float h = clamp(0.5f + 0.5f * (sdf2 - sdf1) / k, 0.0f, 1.0f);
    return mix(sdf2, sdf1, h) - k * h * (1.0f - h);
}
////////// SDFS END //////////

////////// TRANSFORMATIONS //////////
// Rotate a-degrees along the X-axis
vec3 rotateX(vec3 p, float a) {
    a = DEG_TO_RAD * a;
    return vec3(p.x, cos(a) * p.y + -sin(a) * p.z, sin(a) * p.y + cos(a) * p.z);
}

// Rotate a-degrees along the Y-axis
vec3 rotateY(vec3 p, float a) {
    a = DEG_TO_RAD * a;
    return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
}

// Rotate a-degrees along the Z-axis
vec3 rotateZ(vec3 p, float a) {
    a = DEG_TO_RAD * a;
    return vec3(cos(a) * p.x + -sin(a) * p.y, sin(a) * p.x + cos(a) * p.y, p.z);
}
////////// TRANSFORMATIONS END //////////

////////// TOOLBOX FUNCTIONS //////////
float bias(float b, float t) {
  return pow(t, log(b) / log(0.5f));
}

float gain(float g, float t) {
  if (t < 0.5f) {
    return bias(1.f - g, 2.f * t) / 2.f;
  } else {
    return 1.f - bias(1.f - g, 2.f - 2.f * t);
  }
}
////////// TOOLBOX FUNCTIONS END //////////


////////// NOISE FUNCTIONS //////////
float noise1D( vec2 p ) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) *
                 43758.5453);
}

float interpNoise2D(float x, float y) {
    int intX = int(floor(x));
    float fractX = fract(x);
    int intY = int(floor(y));
    float fractY = fract(y);

    float v1 = noise1D(vec2(intX, intY));
    float v2 = noise1D(vec2(intX + 1, intY));
    float v3 = noise1D(vec2(intX, intY + 1));
    float v4 = noise1D(vec2(intX + 1, intY + 1));

    float i1 = mix(v1, v2, fractX);
    float i2 = mix(v3, v4, fractX);
    return mix(i1, i2, fractY);
}


float fbm(float x, float y) {
    float total = 0.0;
    float persistence = 0.5;
    int octaves = 4;

    for(int i = 1; i <= octaves; i++) {
        float freq = pow(2.0, float(i));
        float amp = pow(persistence, float(i));

        total += interpNoise2D(x * freq,
                               y * freq) * amp;
    }
    return total;
}

vec2 random2( vec2 p ) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)),
                 dot(p, vec2(269.5,183.3))))
                 * 43758.5453);
}

float worley(vec2 uv) {
    uv *= 10.0; 
    vec2 uvInt = floor(uv);
    vec2 uvFract = fract(uv);
    float minDist = 1.0;
    for(int y = -1; y <= 1; ++y) {
        for(int x = -1; x <= 1; ++x) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 point = random2(uvInt + neighbor); 
            vec2 diff = neighbor + point - uvFract;
            float dist = length(diff);
            minDist = min(minDist, dist);
        }
    }
    return minDist;
}

vec3 random3(vec3 p) {
    return fract(sin(vec3(dot(p,vec3(127.1, 311.7, 147.6)),
                          dot(p,vec3(269.5, 183.3, 221.7)),
                          dot(p, vec3(420.6, 631.2, 344.2))
                    )) * 43758.5453);
}

float surflet(vec3 p, vec3 gridPoint) {
    vec3 t2 = abs(p - gridPoint);
    vec3 t = vec3(1.0) - 6.0 * pow(t2, vec3(5.0)) + 15.0 * pow(t2, vec3(4.0)) - 10.0 * pow(t2, vec3(3.0));
    vec3 gradient = random3(gridPoint) * 2.0 - vec3(1.0);
    vec3 diff = p - gridPoint;
    float height = dot(diff, gradient);
    return height * t.x * t.y * t.z;
}

float perlin(vec3 p) {
  float surfletSum = 0.0;
  for(int dx = 0; dx <= 1; ++dx) {
    for(int dy = 0; dy <= 1; ++dy) {
      for(int dz = 0; dz <= 1; ++dz) {
        surfletSum += surflet(p, floor(p) + vec3(dx, dy, dz));
      }
    }
  }
  return surfletSum;
}
////////// NOISE FUNCTIONS END //////////


////////// RAY MARCHING //////////
struct Ray {
    vec3 origin;
    vec3 direction;
};

struct Intersection {
    float t;
    vec3 color;
    vec3 p;
    int object;
};

Ray raycast(vec2 uv) {
  Ray r;
  
  vec3 look = normalize(u_Ref - u_Eye);
  vec3 right = normalize(cross(look, u_Up));
  vec3 up = cross(right, look);

  float len = length(u_Ref - u_Eye);
  float aspectRatio = u_Dimensions.x / u_Dimensions.y;
  float fov = 90.f;
  float alpha = fov / 2.f;

  vec3 screenVertical = up * len * tan(alpha);
  vec3 screenHorizontal = right * len * aspectRatio * tan(alpha);
  vec3 screenPoint = u_Ref + uv.x * screenHorizontal + uv.y * screenVertical;

  r.origin = u_Eye;
  r.direction = normalize(screenPoint - u_Eye);
  return r;
}

bool isRayTooLong(vec3 queryPoint, vec3 origin) {
    return length(queryPoint - origin) > MAX_RAY_Z;
}

float findClosestObject(vec3 pos, vec3 lightPos) {
    float t = CENTER_TRI_SDF;
    t = min(t, SWORD_HOLDER_SDF);
    t = min(t, SWORD_BLADE_SDF);
    t = min(t, SWORD_GUARD_SDF);
    t = min(t, SWORD_HILT_SDF);
    t = min(t, SWORD_QUAD_SDF);
    t = min(t, STEPS_SDF);
    t = min(t, LEFT_FRONT_STONE_SDF);
    t = min(t, RIGHT_FRONT_STONE_SDF);
    t = min(t, FLOOR_SDF);
    t = min(t, MIDDLE_TRI_SDF);
    t = min(t, BACK_BOTTOM_STEP_SDF);
    t = min(t, BACK_TOP_STEP_SDF);
    t = min(t, FLOATING_ROCK_SDF);
    return t;
}

void findClosestObject(vec3 pos, out float t, out int obj, vec3 lightPos) {
    t = CENTER_TRI_SDF;
    obj = CENTER_TRI;
    
    float t2;
    float bounding_sphere_dist = sphere(pos, 50.0);
    if(bounding_sphere_dist <= 0.00001f) {
      if((t2 = SWORD_HOLDER_SDF) < t) {
          t = t2;
          obj = SWORD_HOLDER;
      }
      if((t2 = SWORD_BLADE_SDF) < t) {
          t = t2;
          obj = SWORD_BLADE;
      }
      if((t2 = SWORD_GUARD_SDF) < t) {
          t = t2;
          obj = SWORD_GUARD;
      }
      if((t2 = SWORD_HILT_SDF) < t) {
          t = t2;
          obj = SWORD_HILT;
      }
      if((t2 = SWORD_QUAD_SDF) < t) {
          t = t2;
          obj = SWORD_QUAD;
      }
      if((t2 = STEPS_SDF) < t) {
          t = t2;
          obj = STEPS;
      }
      if((t2 = LEFT_FRONT_STONE_SDF) < t) {
          t = t2;
          obj = LEFT_FRONT_STONE;
      }
      if((t2 = RIGHT_FRONT_STONE_SDF) < t) {
          t = t2;
          obj = RIGHT_FRONT_STONE;
      }
      if((t2 = FLOOR_SDF) < t) {
          t = t2;
          obj = FLOOR;
      }
      if((t2 = MIDDLE_TRI_SDF) < t) {
          t = t2;
          obj = MIDDLE_TRI;
      }
      if((t2 = BACK_BOTTOM_STEP_SDF) < t) {
          t = t2;
          obj = BACK_BOTTOM_STEP;
      }
      if((t2 = BACK_TOP_STEP_SDF) < t) {
          t = t2;
          obj = BACK_TOP_STEP;
      }
      if((t2 = FLOATING_ROCK_SDF) < t) {
          t = t2;
          obj = FLOATING_ROCK;
      }
    } else {
      t = bounding_sphere_dist;
      obj = -1;
    }
}

float hardShadow(vec3 dir, vec3 origin, float min_t, vec3 lightPos) {
    float t = min_t;
    for(int i = 0; i < RAY_STEPS; i++) {
        float m = findClosestObject(origin + t * dir, lightPos);
        if(m < 0.0001) {
            return 0.0;
        }
        t += m;
    }
    return 1.0;
}

void march(vec3 origin, vec3 dir, out float t, out int hitObj, vec3 lightPos) {
    t = 0.001;
    for(int i = 0; i < RAY_STEPS; i++) {
        vec3 pos = origin + t * dir;
        float m;
        if(isRayTooLong(pos, origin)) {
          break;
        }
        findClosestObject(pos, m, hitObj, lightPos);
        if(m < 0.01) {
            return;
        }
        t += m;
    }
    t = -1.0;
    hitObj = -1;
}

vec3 computeNormal(vec3 pos, vec3 lightPos) {
    vec3 epsilon = vec3(0.0, 0.001, 0.0);
    return normalize(vec3(findClosestObject(pos + epsilon.yxx, lightPos) - findClosestObject(pos - epsilon.yxx, lightPos),
                          findClosestObject(pos + epsilon.xyx, lightPos) - findClosestObject(pos - epsilon.xyx, lightPos),
                          findClosestObject(pos + epsilon.xxy, lightPos) - findClosestObject(pos - epsilon.xxy, lightPos)));
}

vec3 getSceneColor(int hitObj, vec3 p, vec3 n, vec3 light, vec3 view) {
    float lambert = dot(n, light) + 0.3;
    switch(hitObj) {
        case CENTER_TRI:
        case SWORD_HOLDER:
        case SWORD_BLADE:
        case SWORD_GUARD:
        case SWORD_HILT:
        case STEPS:
        case LEFT_FRONT_STONE:
        case RIGHT_FRONT_STONE:
        case FLOOR:
        case MIDDLE_TRI:
        case SWORD_QUAD:
        case BACK_TOP_STEP:
        case BACK_BOTTOM_STEP:
        case FLOATING_ROCK:
        return vec3(0.85, 0.8, 0.7) * lambert;
        break;
    }
    return vec3(0.0);
}

Intersection getIntersection(vec3 dir, vec3 eye, vec3 lightPos) {
    float t;
    int hitObj;
    march(eye, dir, t, hitObj, lightPos);
    
    vec3 isect = eye + t * dir;
    vec3 nor = computeNormal(isect, lightPos);
    vec3 surfaceColor = vec3(1.0);
    
    vec3 lightDir = normalize(lightPos - isect);
    
    surfaceColor *= getSceneColor(hitObj, isect, nor, lightDir, normalize(isect - eye)) * hardShadow(lightDir, isect, 0.1, lightPos);
    
    return Intersection(t, surfaceColor, isect, hitObj);
}
////////// RAY MARCHING END //////////


void main() {
  Ray r = raycast(fs_Pos);
  Intersection i = getIntersection(r.direction, r.origin, LIGHT_POS);
  // vec3 color = 0.5 * (r.direction + vec3(1.0, 1.0, 1.0));

  // out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
  out_Col = vec4(i.color, 1.0);
}

