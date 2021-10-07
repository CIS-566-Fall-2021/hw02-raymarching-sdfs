#version 300 es
precision highp float;

const int MAX_RAY_STEPS = 256;
const float EPSILON = 1e-4;
const float FOV = 60.0;
const float MAX_DISTANCE = 20.0;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

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

// HELPERS //
vec3 rgb(vec3 col)
{
  return col / 255.0;
}

float triangleWave(float x, float freq, float amplitude)
{
  return abs(mod(x * freq, amplitude) - (0.5 * amplitude));
}

// SDF CODE //
mat4 rotateX(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    mat4 m = mat4(
        vec4(c, 0, s, 0),
        vec4(0, 1, 0, 0),
        vec4(-s, 0, c, 0),
        vec4(0, 0, 0, 1)
    );
    return inverse(m);
}

mat4 rotateY(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    mat4 m = mat4(
        vec4(1, 0, 0, 0),
        vec4(0, c, -s, 0),
        vec4(0, s, c, 0),
        vec4(0, 0, 0, 1)
    );
    return inverse(m);
}

mat4 rotateZ(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    mat4 m = mat4(
        vec4(c, -s, 0, 0),
        vec4(s, c, 0, 0),
        vec4(0, 0, 1, 0),
        vec4(0, 0, 0, 1)
    );
    return inverse(m);
}

vec3 bendPoint(vec3 p, float k)
{
    float c = cos(k*p.y);
    float s = sin(k*p.y);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
}

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

// from IQ
float sdCylinder(vec3 p, vec3 a, vec3 b, float r)
{
  vec3  ba = b - a;
  vec3  pa = p - a;
  float baba = dot(ba,ba);
  float paba = dot(pa,ba);
  float x = length(pa*baba-ba*paba) - r*baba;
  float y = abs(paba-baba*0.5)-baba*0.5;
  float x2 = x*x;
  float y2 = y*y*baba;
  float d = (max(x,y)<0.0)?-min(x2,y2):(((x>0.0)?x2:0.0)+((y>0.0)?y2:0.0));
  return sign(d)*sqrt(abs(d))/baba;
}

float sdRoundBox( vec3 p, vec3 b, float r )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float plane(vec3 p, vec4 n)
{
  return dot(p,n.xyz) + n.w;
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

// from IQ
vec3 opRep(vec3 p, vec3 c)
{
    return mod(p+0.5*c,c)-0.5*c;
}

vec3 opRepLim(vec3 p, float c, vec3 l)
{
    return p-c*clamp(round(p/c),-l,l);
}

vec3 opTwist( vec3 p )
{
    const float k = 10.0; // or some other amount
    float c = cos(k*p.y);
    float s = sin(k*p.y);
    mat2  m = mat2(c,-s,s,c);
    return vec3(m*p.xz,p.y);
}

vec3 opRevolution( in vec3 p, float o )
{
    return vec3( length(p.xz) - o, p.y , 0);
}

float pillar(vec3 pos, float rotation)
{
  return sdCylinder(pos, (rotateX(rotation) * vec4(0.57, -0.3, 0.0, 1.0)).xyz, 
    (rotateX(rotation) * vec4(0.57, 0.3, 0.0, 1.0)).xyz, 0.02);
}

float towerFloor(vec3 pos)
{
  float rotation = radians(45.0);
  float tFloor = sdCylinder(pos, vec3(0.0, -0.05, 0.0), vec3(0.0, 0.05, 0.0), 0.64);
  float p1 = pillar(pos, 0.0);
  float p2 = pillar(pos, rotation * 1.0);
  float p3 = pillar(pos, rotation * 2.0);
  float p4 = pillar(pos, rotation * 3.0);
  float p5 = pillar(pos, rotation * 4.0);
  float p6 = pillar(pos, rotation * 5.0);
  float p7 = pillar(pos, rotation * 6.0);
  float p8 = pillar(pos, rotation * 7.0);

  return smin(tFloor, min(p1, min(p2, min(p3, min(p4, min(p5, min(p6, min(p7, p8))))))), 0.05);
}

float towerBody(vec3 pos)
{
  vec3 displacement = vec3(0.0, 0.4, 0.0);
  float middle = sdCylinder(pos, vec3(0.0, -1.5, 0.0), vec3(0.0, 1.9, 0.0), 0.5);
  float levels = towerFloor(opRepLim(pos, 0.5, vec3(0.0, 2.0, 0.0)));
  float top = sdCylinder(pos + vec3(0.0, -1.3, 0.0), vec3(0.0, -0.05, 0.0), vec3(0.0, 0.05, 0.0), 0.64);
  return smin(middle, min(levels, top), 0.05);
}

float towerBase(vec3 pos)
{
  float middle = sdCylinder(pos, vec3(0.0, -0.5, 0.0), vec3(0.0, 0.5, 0.0), 0.64);
  return middle;
}

float tower(vec3 pos)
{
  float rotation = radians(-25.0) * (sin(u_Time / 50.0) + 1.0) / 2.0;
  vec3 rotatedPos = (rotateZ(rotation) * vec4(pos + vec3(0.0, 3.0, 0.0), 1.0)).xyz + vec3(0.0, -3.0, 0.0) + vec3(0.0, 0.2, 0.0);
  return min(towerBody(rotatedPos), towerBase(rotatedPos + vec3(0.0, 1.8, 0.0)));
}

float people(vec3 pos, float size)
{
  vec3 movement = vec3(0.0, 0.08, 0.0) * triangleWave((u_Time + 3.5 * fs_Pos.x + 1.2 * fs_Pos.y) / 25.0, 10.0, 2.0);
  float crowd = sdCylinder(opRepLim(pos + vec3(0.0, 2.4, 0.0) + movement, 0.25, vec3(size, 0.0, size)), vec3(0.0, 0.0,0.0), vec3(0.0,0.05,0.0), 0.02);
  return crowd;
}

// SCENE //
#define FLOOR plane(queryPos, vec4(0.0, 1.0, 0.0, 2.5))
#define BODY tower(queryPos + vec3(0.0, 0.2, 0.0))
#define THING min(people(queryPos + vec3(-1.3, 0.0, 1.2), 3.0), min(people(queryPos + vec3(2.0, 0.0, -2.4), 2.0), people(queryPos + vec3(-1.5, 0.0, -1.5), 4.0)))

#define FLOOR_NUM 0
#define BODY_NUM 2
#define THING_NUM 3

float sceneSDF(vec3 queryPos)
{
  float dist = FLOOR;
  dist = min(dist, BODY);
  dist = min(dist, THING);
  return dist;
}

void sceneSDF(vec3 queryPos, out float dist, out int material_id) 
{
  dist = FLOOR;
  float dist2;
  material_id = FLOOR_NUM;
  if ((dist2 = BODY) < dist)
  {
    dist = dist2;
    material_id = BODY_NUM;
  }
  if ((dist2 = THING) < dist)
  {
    dist = dist2;
    material_id = THING_NUM;
  }
}

vec3 sdfNormal(vec3 pos)
{
  vec2 epsilon = vec2(0.0, EPSILON);
  return normalize( vec3( sceneSDF(pos + epsilon.yxx) - sceneSDF(pos - epsilon.yxx),
                            sceneSDF(pos + epsilon.xyx) - sceneSDF(pos - epsilon.xyx),
                            sceneSDF(pos + epsilon.xxy) - sceneSDF(pos - epsilon.xxy)));
}

// RAYMARCH CODE //
Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, u_Up));
    vec3 camera_UP = cross(camera_RIGHT, look);
    float len = distance(u_Eye, u_Ref);
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = camera_UP * len * tan(FOV); 
    vec3 screen_horizontal = camera_RIGHT * len * aspect_ratio * tan(FOV);
    vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);
   
    return r;
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Ray ray = getRay(uv);
    Intersection intersection;
    
    intersection.distance_t = -1.0;
    intersection.position = u_Eye;
    intersection.normal = vec3(0, 0, 0);
    intersection.material_id = -1;

    float t = 0.0;
    for (int i = 0; i < MAX_RAY_STEPS; i++)
    {
      // get position
      vec3 pos = ray.origin + t * ray.direction;
      if (t > MAX_DISTANCE)
      {
        break;
      }

      float dist;
      int material_id;
      sceneSDF(pos, dist, material_id);
      // if dist is on surface of sdf, then we're done
      if (dist < EPSILON)
      {
        intersection.position = pos;
        intersection.distance_t = t;
        intersection.normal = sdfNormal(intersection.position);
        intersection.material_id = material_id;
        break;
      }
      t += dist;
    }

    return intersection;
}

float hardShadow(vec3 origin, vec3 dir, float min_t, float max_t) {
    for(float t = min_t; t < max_t;) 
    {
        vec3 pos = origin + t * dir;
        float dist = sceneSDF(origin + t * dir);
        if(dist < EPSILON) 
        {
            return 0.0;
        }
        t += dist;
    }
    return 1.0;
}

vec3 calculateMaterial(int material_id, vec3 normal, vec3 lightDir)
{
  float ambient = 0.2;
  float lambert = max(0.0, dot(normal, lightDir)) + ambient;

  switch (material_id)
  {
    case FLOOR_NUM:
      return rgb(vec3(82, 143, 47)) * lambert;
      break;
    case BODY_NUM:
      return rgb(vec3(226, 227, 200)) * lambert;
      break;
    case THING_NUM:
      return rgb(vec3(88, 230, 232)) * lambert;
      break;
    case -1:
      return rgb(vec3(149, 228, 252));
      break;
  }
  return rgb(vec3(153, 139, 83));
}

vec3 getSceneColor(vec2 uv, vec3 lightPos)
{
  Intersection intersection = getRaymarchedIntersection(uv);
  vec3 lightDir = normalize(lightPos - intersection.position);
  vec3 light_t = (lightPos - intersection.position) / lightDir;
  float hardShadow = hardShadow(intersection.position, lightDir, 0.1, light_t.x);
  vec3 col = calculateMaterial(intersection.material_id, intersection.normal, lightDir);
  return col * hardShadow;
}

void main() {
  vec3 lightPos = vec3(-5.0, 7.45, -5.0);

  vec2 uv = fs_Pos;

  vec3 col = getSceneColor(uv, lightPos);

  out_Col = vec4(col, 1.0);
}
