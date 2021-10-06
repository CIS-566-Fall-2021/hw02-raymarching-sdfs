#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 128;
const float FOV = 45.0;
const float FOV_TAN = tan(45.0);
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

float sdfSphere(vec3 query_position, vec3 position, float radius) {
  return length(query_position - position) - radius;
}

float sdfRoundBox(vec3 p, vec3 b, float r) {
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float sdfBox( vec3 p, vec3 b ) {
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

const float keyScale = 2.7f;
float sdfIvoryKey(vec3 p) {
  return sdfBox(p, vec3(0.05, 0.45, 0.18) / keyScale);
}

float sdfEBKey(vec3 p) {
  vec3 pt = p + vec3(0.061, -0.27f, 0.f) / keyScale;
  return max(-sdfBox(pt, vec3(0.04, 0.45, 0.121) / keyScale), sdfBox(p, vec3(0.1, 0.71, 0.12) / keyScale));
}

float sdfCFKey(vec3 p) {
  return sdfEBKey(p - vec3(p.x * 2.f, 0.f, 0.f));
}

float sdfDKey(vec3 p) {
  vec3 pt = p + vec3(0.085, -0.27f, 0.f) / keyScale;
  float leftBox = sdfBox(pt, vec3(0.02, 0.45, 0.121) / keyScale);
  pt = p + vec3(-0.089, -0.27f, 0.f) / keyScale;
  float rightBox = sdfBox(pt, vec3(0.02, 0.45, 0.121) / keyScale);
  return max(-rightBox, max(-leftBox, sdfBox(p, vec3(0.1, 0.71, 0.12) / keyScale)));
}

float sdfGKey(vec3 p) {
  vec3 pt = p + vec3(0.085, -0.27f, 0.f) / keyScale;
  float leftBox = sdfBox(pt, vec3(0.018, 0.45, 0.121) / keyScale);
  pt = p + vec3(-0.076, -0.27f, 0.f) / keyScale;
  float rightBox = sdfBox(pt, vec3(0.025, 0.45, 0.121) / keyScale);
  return max(-rightBox, max(-leftBox, sdfBox(p, vec3(0.1, 0.71, 0.12) / keyScale)));
}

float sdfAKey(vec3 p) {
  return sdfGKey(p - vec3(p.x * 2.f, 0.f, 0.f));
}

const float keyPadding = 0.011f;
float sdfOctave(vec3 p, out vec3 p2) {
  vec3 ip = p - vec3(0.08, 0.28, -0.063) / keyScale;
  float c = sdfCFKey(p);
  p -= vec3(0.2f + keyPadding, 0.f, 0.f) / keyScale;
  float cs = sdfIvoryKey(ip);
  ip.x -= 0.255 / keyScale;
  float d = sdfDKey(p);
  p -= vec3(0.2f + keyPadding, 0.f, 0.f) / keyScale;
  float ds = sdfIvoryKey(ip);
  ip.x -= 0.38 / keyScale;
  float e = sdfEBKey(p);
  p -= vec3(0.2f + keyPadding, 0.f, 0.f) / keyScale;
  float f = sdfCFKey(p);
  p -= vec3(0.2f + keyPadding, 0.f, 0.f) / keyScale;
  float fs = sdfIvoryKey(ip);
  ip.x -= 0.24 / keyScale;
  float g = sdfGKey(p);
  p -= vec3(0.2f + keyPadding, 0.f, 0.f) / keyScale;
  float gs = sdfIvoryKey(ip);
  ip.x -= 0.23 / keyScale;
  float a = sdfAKey(p);
  p -= vec3(0.2f + keyPadding, 0.f, 0.f) / keyScale;
  float as = sdfIvoryKey(ip);
  float b = sdfEBKey(p);
  p -= vec3(0.2f + keyPadding, 0.f, 0.f) / keyScale;
  p2 = p;
  return min(b, min(min(as, a), min(min(gs, g), min(min(fs, f), min(e, min(min(ds, d), min(cs, c)))))));
}

vec3 flipX(vec3 p) {
  return vec3(-p.x, p.y, p.z);
}

float sdfFrame(vec3 p) {
  vec3 mainB = vec3(7.f, 2.f, 6.f) / 4.f;
  vec3 sideB = vec3(0.05, 0.9, 0.9);
  vec3 frontB = vec3(mainB.x, sideB.x, 0.2);
  return min(sdfBox(p + vec3(0.f, mainB.y + sideB.y - frontB.y * 3.f, 0.f), frontB), min(
    sdfRoundBox(p - flipX(mainB) + flipX(sideB), sideB, 0.01), 
    min(
      sdfRoundBox(p - mainB + sideB, sideB, 0.01),
      sdfBox(p, mainB))));
}

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

mat3 rotationMatrix(vec3 axis, float angle)
{
    axis = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    
    return mat3(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
                oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
                oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c);
}

vec3 translateTo(vec3 p, vec3 c) {
  return p - c;
}

vec3 rotateAround(vec3 p, vec3 axis, float angle) {
  return rotationMatrix(axis, angle) * p;
}

float sdfKeys(vec3 p, int octaves) {
  float v = 999999.f;
  vec3 p2 = p;
  for (int i = 0; i < octaves; i++) {
    v = min(v, sdfOctave(p2, p2));
  }

  return v;
}

float sceneSDF(vec3 queryPos) {
  float keys = sdfKeys(queryPos + vec3(1.6f, 0.95f, 0.2f), 6);
  // vec3 q2 = rotateAround(
  //       queryPos,
  //       vec3(0.0, 0.1f,0.1f),
  //       0.5f);

  // return sdfBox(
  //   q2, 
  //   vec3(0.5f, 0.5f, 0.5f));

  //return sdfOctave(queryPos);
  vec3 p;
  float o1 = sdfFrame(queryPos);//sdfOctave(queryPos, p);
  //float o2 = sdfOctave(p, p);
  //return min(o1, o2);
  return min(keys, o1);
}

const float d = 0.001f;
vec3 sceneSDFGrad(vec3 queryPos) {
  vec3 diffVec = vec3(d, 0.f, 0.f);
  return normalize(vec3(
      sceneSDF(queryPos + diffVec) - sceneSDF(queryPos - diffVec),
      sceneSDF(queryPos + diffVec.yxz) - sceneSDF(queryPos - diffVec.yxz),
      sceneSDF(queryPos + diffVec.zyx) - sceneSDF(queryPos - diffVec.zyx)
    ));
}

Ray getRay(vec2 uv)
{
  Ray r;
  
  vec3 look = normalize(u_Ref - u_Eye);
  vec3 camera_RIGHT = normalize(cross(u_Up, look));
  vec3 camera_UP = u_Up;
  
  float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
  vec3 screen_vertical = camera_UP * FOV_TAN; 
  vec3 screen_horizontal = camera_RIGHT * aspect_ratio * FOV_TAN;
  vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
  
  r.origin = (screen_point + u_Eye) / 2.f;
  r.direction = normalize(screen_point - u_Eye);

  return r;
}

const float MIN_STEP = EPSILON * 2.f;
Intersection getRaymarchedIntersection(vec2 uv)
{
  Intersection intersection;
  intersection.distance_t = -1.0;
  Ray ray = getRay(uv);

  float distance_t = 0.f;
  float prevDist = 99999.f;
  for (int step = 0; step < MAX_RAY_STEPS; step++) {
    vec3 point = ray.origin + ray.direction * distance_t;
    float dist = sceneSDF(point);
    // if (isinf(point.x) || isinf(point.y) || isinf(point.z)) {
    //   break;
    // }

    // if (dist > prevDist) {
    //   break;
    // }

    if (dist < EPSILON) {
      intersection.distance_t = dist;
      intersection.position = point;
      intersection.normal = sceneSDFGrad(point);

      return intersection;
    }

    distance_t += max(dist, MIN_STEP);

    if (distance_t > 999.f) {
      break;
    }
  }

  return intersection;
}

const vec3 light = vec3(10.f, 14.f, 3.f);
vec3 getSceneColor(vec2 uv) {
  Intersection intersection = getRaymarchedIntersection(uv);
  // if (uv.x > 0.3f && uv.y < -0.3f) {
  //   if (abs(intersection.distance_t) < EPSILON) {
  //     if (isinf(intersection.position.x)) {
  //       return vec3(1.f, 0.f, 0.f);
  //     }
  //   }
  //   return vec3(0.f, 0.f, 1.f);
  // }

  if (abs(intersection.distance_t) < EPSILON)
  {
      float diffuseTerm = dot(intersection.normal, normalize(u_Eye - intersection.position));
      diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);

      return vec3(1.0) * (diffuseTerm + 0.2);
  }

  return vec3(0.7, 0.2, 0.2);
}

void main() {
  // Time varying pixel color
  vec3 col = getSceneColor(fs_Pos);

  // Output to screen
  out_Col = vec4(col, 1.0);//vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
}