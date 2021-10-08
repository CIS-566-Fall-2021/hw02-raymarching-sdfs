#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const float FOV = 45.0;
const int MAX_RAY_STEPS = 100;
const float EPSILON = 0.1;
const vec3 LIGHT = vec3(0.4, 1.0, -0.5);

float triangle_wave(float x, float freq, float amp) {
    float a = abs(x * freq);
    float r = a - amp * floor(a/amp);
    return (r - (0.5 * amp));
}


float parabola(float x, float k){
  return pow(4.0 * x * (1.0 - x), k);
}

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

vec3 getDir(vec2 uv)
{   
  vec3 look = normalize(u_Ref - u_Eye);
  vec3 camera_UP = normalize(u_Up);
  vec3 camera_RIGHT = normalize(cross(camera_UP, look));
  float len = length(u_Ref - u_Eye);
    
  float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
  vec3 screen_vertical = camera_UP * len * tan(FOV / 2.0); 
  vec3 screen_horizontal = camera_RIGHT * len * aspect_ratio * tan(FOV / 2.0);
  vec3 screen_point = (u_Ref + uv.x * screen_horizontal + uv.y * screen_vertical);
  return normalize(screen_point - u_Eye);
}

//SDF functions
float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

float sdRoundCone(vec3 p, vec3 a, vec3 b, float r1, float r2)
{
  // sampling independent computations (only depend on shape)
  vec3  ba = b - a;
  float l2 = dot(ba,ba);
  float rr = r1 - r2;
  float a2 = l2 - rr*rr;
  float il2 = 1.0/l2;
    
  // sampling dependant computations
  vec3 pa = p - a;
  float y = dot(pa,ba);
  float z = y - l2;
  float x2 = dot( pa*l2 -ba*y, pa*l2 -ba*y );
  float y2 = y*y*l2;
  float z2 = z*z*l2;

  // single square root!
  float k = sign(rr)*rr*rr*x2;
  if( sign(z)*a2*z2 > k ) return  sqrt(x2 + z2)        *il2 - r2;
  if( sign(y)*a2*y2 < k ) return  sqrt(x2 + y2)        *il2 - r1;
                          return (sqrt(x2*a2*il2)+y*rr)*il2 - r1;
  return 0.0;
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
  return mix( d2, d1, h ) - k*h*(1.0-h); 
}

vec3 rotation(vec3 p, vec3 axis, float angle)
{
    // taken from http://www.neilmendoza.com/glsl-rotation-about-an-arbitrary-axis/
    angle = radians(angle);
    axis = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    
    mat4 rot =  mat4(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,  0.0,
                oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,  0.0,
                oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c,           0.0,
                0.0,                                0.0,                                0.0,                                1.0);
    return (rot*vec4(p, 1.)).xyz;
}

float boundSDF(vec3 p) {
  float bound = sdfSphere(p - vec3(-1.0, 0.0, 0.0), vec3(0.0), 4.5);
  float ball = sdfSphere(p, vec3(4.75, -1.35, 0.0), 1.0);
  float plane = planeSDF(p, -2.0);
  return min(ball, min(bound, plane));
}

//SCENE *********************************************
float sceneSDF(vec3 p){
  float speed = 0.3;
  float plane = planeSDF(p, -1.75);
  vec3 butt_p = rotation(p, vec3(0.0, 1.0, 1.0), 35.0 * triangle_wave(float(u_Time) * 0.25, 0.005, 1.0) * sin(u_Time) * 0.05);
  float head = sdfSphere(p, vec3(1.8, -0.3, 0.0), 0.75);
  float mouth = sdRoundCone(p, vec3(2.0, -0.5, 0.0), vec3(2.45, -0.75, 0.0), 0.5, 0.25);
  float neck = capsuleSDF(p, vec3(0.0, -0.1, 0.0), vec3(1.5, -0.20, 0.0), 0.35);
  float body = capsuleSDF(p, vec3(0.5, 0.0, 0.0), vec3(-1.5, 0.25, 0.00 + 0.40 * sin(float(u_Time * speed))), 1.0);
  float butt = capsuleSDF(butt_p, vec3(-1.75, 0.25, 0.0 + 0.40 * sin(float(u_Time * speed))), vec3(-1.5, 0.2, 0.40 * sin(float(u_Time * speed))), 1.25);
  
  float thigh1 = sdRoundCone(butt_p, vec3(-1.75, 0.0, -0.45+ 0.30 * sin(float(u_Time * speed))), vec3(-1.70, -0.75, -0.45+ 0.30 * sin(float(u_Time * speed))), 1.0, 0.5);
  float leg1 = capsuleSDF(p, vec3(-1.70, -1.20, -0.45 + 0.20 * sin(float(u_Time * speed))),  vec3(-0.5, -1.50, -0.45), 0.15);

  float thigh2 = sdRoundCone(butt_p, vec3(-1.75, 0.0, 0.45+ 0.30 * sin(float(u_Time * speed))), vec3(-1.70, -0.75, 0.45+ 0.30 * sin(float(u_Time * speed))), 1.0, 0.5);
  float leg2 = capsuleSDF(p, vec3(-1.70, -1.20, 0.45 + 0.20 * sin(float(u_Time * speed))),  vec3(-0.5, -1.50, 0.45), 0.15);

  float thighf1 = sdRoundCone(p, vec3(0.0, 0.0, -0.45), vec3(0.25, -1.25, -0.45+ 0.05 * cos(float(u_Time) * speed)), 0.75, 0.25);
  float legf1 = capsuleSDF(p, vec3(0.25, -1.25, -0.45 + 0.15 * cos(float(u_Time) * speed)), vec3(1.5, -1.5, -0.45), 0.15);

  float thighf2 = sdRoundCone(p, vec3(0.0, 0.0, 0.45), vec3(0.25, -1.25, 0.45+ 0.05 * cos(float(u_Time) * speed)), 0.75, 0.25);
  float legf2 = capsuleSDF(p, vec3(0.25, -1.25, 0.45+ 0.15 * cos(float(u_Time) * speed)), vec3(1.5, -1.5, 0.45), 0.15);

  float ear1 = sdBox(p + vec3(-1.85, -0.45, 0.65), vec3(0.005, 0.15, 0.1));
  float ear2 = sdBox(p + vec3(-1.85, -0.45, -0.65), vec3(0.005, 0.15, 0.1));

  float tail1 = capsuleSDF(p, vec3(-3.00, 0.20, 0.0 + 0.20 * sin(float(u_Time * speed))),  vec3(-3.75, -0.90, -0.45 + 0.15 * sin(float(u_Time * speed))), 0.15);
  float tail2 = capsuleSDF(p, vec3(-3.85, -1.0, -0.75 + 0.15 * sin(float(u_Time * speed))), vec3(-3.95, -1.10, -1.45 + 0.1 * sin(float(u_Time * speed))), 0.15);

  vec3 box_p = rotation(p - vec3(4.75, -1.25, 0.0), vec3(0.0, 1.0, 0.0), 45.0 * parabola(sin(float(u_Time)) * 0.25, 3.0));
  float box = sdBox(box_p, vec3(0.25));
  //smoothUnions
  float body_neck = smoothUnion(body, neck, 0.25);
  float u_butt = smoothUnion(body_neck, butt, 0.25);
  float u_head = smoothUnion(u_butt, head, 0.25);
  float u_mouth = smoothUnion(u_head, mouth, 0.25);
  float u_thigh1 = smoothUnion(u_mouth, thigh1, 0.15);
  float u_thigh2 = smoothUnion(u_thigh1, thigh2, 0.15);
  float u_leg1 = smoothUnion(u_thigh2, leg1, 0.25);
  float u_leg2 = smoothUnion(u_leg1, leg2, 0.25);
  float u_thighf1 = smoothUnion(u_leg2, thighf1, 0.25);
  float u_legf1 = smoothUnion(u_thighf1, legf1, 0.25);
  float u_thighf2 = smoothUnion(u_legf1, thighf2, 0.25);
  float u_legf2 = smoothUnion(u_thighf2, legf2, 0.25);
  float u_ear1 = smoothUnion(u_legf2, ear1, 0.25);
  float u_ear2 = smoothUnion(u_ear1, ear2, 0.25);
  float u_tail1 = smoothUnion(u_ear2, tail1, 0.25);
  float u_tail2 = smoothUnion(u_tail1, tail2, 0.25);
  return min(plane, min(box, u_tail2));
}

float shadow(vec3 ro, vec3 rd, float mint, float maxt, float k) {
  float res = 1.0;
  for(float t = mint; t < maxt;) {
    float h = sceneSDF(ro + rd * t);
    if(h < 0.001) return 0.0;
    res = min(res, k * h / t);
    t += h;
  }
  return res;
}

vec3 estimateNormal(vec3 p) {
  vec2 d = vec2(0.0, EPSILON);
  float x = sceneSDF(p + d.yxx) - sceneSDF(p - d.yxx);
  float y = sceneSDF(p + d.xyx) - sceneSDF(p - d.xyx);
  float z = sceneSDF(p + d.xxy) - sceneSDF(p - d.xxy);
  return normalize(vec3(x, y, z));
}

vec4 intersect(vec2 uv) {
  vec4 intersection = vec4(0.0);
  vec3 rayDir = getDir(uv);
  float t = 0.0;
  for(int step = 0; step < MAX_RAY_STEPS; step ++) {
    vec3 queryPoint = u_Eye + rayDir * t;
    float currentDistanceb = boundSDF(queryPoint);
    if(currentDistanceb <= EPSILON) {
      float currentDistance = sceneSDF(queryPoint);
      if(currentDistance <= EPSILON) {
        vec3 normal = estimateNormal(queryPoint);
        intersection  = vec4(normal, t);
        return intersection;
      }
      t += currentDistance;
    }
    if(currentDistanceb > EPSILON){
      t += currentDistanceb;
    }
    
  }
  return intersection;
}

void main() {
  vec3 diffuseColor = vec3(0.0);
  vec4 intersection = intersect(fs_Pos);
  if(intersection.w > 0.0 && length(intersection.xyz) > 0.0) {
    vec3 rayDir = getDir(fs_Pos);
    vec3 p = u_Eye + rayDir * intersection.w;
    float s = shadow(p, LIGHT, 0.0, 1.0, 0.5);
    diffuseColor = vec3(0.9) * s;
  }

  // Calculate the diffuse term for Lambert shading
  float diffuseTerm = dot(normalize(intersection.xyz), normalize(LIGHT));
  // Avoid negative lighting values
  diffuseTerm = clamp(diffuseTerm, 0.0, 1.0);

  float ambientTerm = 0.2;

  float lightIntensity = diffuseTerm + ambientTerm;

  // Compute final shaded color
  out_Col = vec4(diffuseColor.rgb * lightIntensity, 1.0);
}
