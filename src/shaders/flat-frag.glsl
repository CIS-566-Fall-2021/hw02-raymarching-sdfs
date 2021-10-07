#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 70;
const float FOV = 45.0;
const float EPSILON = 1e-5;

// const vec3 EYE = vec3(0.0, 0.0, 10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
// const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(-1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const vec3 LIGHT_DIR = vec3(-1.0, 2.0, 15.0);

struct Ray {
  vec3 origin;
  vec3 direction;
};

struct Intersection {
  vec3 position;
  vec3 normal;
  float distance_t;
  int material_id;
};

/*
NOISE FUNCTIONS
*/

float random1( vec3 p ) {
  return fract(sin((dot(p, vec3(127.1,
  311.7,
  191.999)))) *
  18.5453);
}

float smootherStep(float a, float b, float t) {
    t = t*t*t*(t*(t*6.0 - 15.0) + 10.0);
    return mix(a, b, t);
}

float interpNoise3D(float x, float y, float z) {
  x *= 2.;
  y *= 2.;
  z *= 2.;
  float intX = floor(x);
  float fractX = fract(x);
  float intY = floor(y);
  float fractY = fract(y);
  float intZ = floor(z);
  float fractZ = fract(z);
  float v1 = random1(vec3(intX, intY, intZ));
  float v2 = random1(vec3(intX + 1., intY, intZ));
  float v3 = random1(vec3(intX, intY + 1., intZ));
  float v4 = random1(vec3(intX + 1., intY + 1., intZ));

  float v5 = random1(vec3(intX, intY, intZ + 1.));
  float v6 = random1(vec3(intX + 1., intY, intZ + 1.));
  float v7 = random1(vec3(intX, intY + 1., intZ + 1.));
  float v8 = random1(vec3(intX + 1., intY + 1., intZ + 1.));

  float i1 = smootherStep(v1, v2, fractX);
  float i2 = smootherStep(v3, v4, fractX);
  float result1 = smootherStep(i1, i2, fractY);
  float i3 = smootherStep(v5, v6, fractX);
  float i4 = smootherStep(v7, v8, fractX);
  float result2 = smootherStep(i3, i4, fractY);
  return smootherStep(result1, result2, fractZ);
}

float fbm(float x, float y, float z, float octaves) {
  float total = 0.;
  float persistence = 0.5f;
  for(float i = 1.; i <= octaves; i++) {
    float freq = pow(2., i);
    float amp = pow(persistence, i);
    total += interpNoise3D(x * freq, y * freq, z * freq) * amp;
  }
  return total;
}

/*
TRANSFORMATION FUNCTIONS
*/
#define DEG_TO_RAD 3.141592 / 180.

mat4 inverseRotate(vec3 rotate) { 
    rotate.x = radians(rotate.x);
    rotate.y = radians(rotate.y);
    rotate.z = radians(rotate.z);
    mat4 r_x;
    r_x[0] = vec4(1., 0., 0., 0.);
    r_x[1] = vec4(0., cos(rotate.x), sin(rotate.x), 0.);
    r_x[2] = vec4(0., -sin(rotate.x), cos(rotate.x), 0.);
    r_x[3] = vec4(0., 0., 0., 1.);                            
    mat4 r_y;
    r_y[0] = vec4(cos(rotate.y), 0., -sin(rotate.y), 0.);
    r_y[1] = vec4(0., 1, 0., 0.);
    r_y[2] = vec4(sin(rotate.y), 0., cos(rotate.y), 0.);
    r_y[3] = vec4(0., 0., 0., 1.);
    mat4 r_z;
    r_z[0] = vec4(cos(rotate.z), sin(rotate.z), 0., 0.);
    r_z[1] = vec4(-sin(rotate.z), cos(rotate.z), 0., 0.);
    r_z[2] = vec4(0., 0., 1., 0.);
    r_z[3] = vec4(0., 0., 0., 1.);
    return r_x * r_y * r_z;
}

vec3 rotateX(in vec3 p, float a) {
    a = DEG_TO_RAD * a;
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

vec3 rotateY(vec3 p, float a) {
    a = DEG_TO_RAD * a;
	float c = cos(a);
	float s = sin(a);
	return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

vec3 rotateZ(in vec3 p, float a) {
    a = DEG_TO_RAD * a;
	float c = cos(a);
	float s = sin(a);
	return vec3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

float GetBias(float bias)
{
  return (u_Time / ((((1.0/bias) - 2.0)*(1.0 - u_Time))+1.0));
}

/*
SDF FUNCTIONS
*/

float dot2(vec2 v) {
  return dot(v, v);
}

float dot2(vec3 v) {
  return dot(v, v);
}

float opSmoothUnion( float d1, float d2, float k ) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); }

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); }

float opSmoothIntersection( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) + k*h*(1.0-h); }

float opSubtraction( float d1, float d2 ) { return max(-d1,d2); }

float opUnion( float d1, float d2 ) { return min(d1,d2); }


/*
SDF FORMULAS
*/

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdCappedCone( vec3 p, float h, float r1, float r2 )
{
  vec2 q = vec2( length(p.xz), p.y );
  vec2 k1 = vec2(r2,h);
  vec2 k2 = vec2(r2-r1,2.0*h);
  vec2 ca = vec2(q.x-min(q.x,(q.y<0.0)?r1:r2), abs(q.y)-h);
  vec2 cb = q - k1 + k2*clamp( dot(k1-q,k2)/dot2(k2), 0.0, 1.0 );
  float s = (cb.x<0.0 && ca.y<0.0) ? -1.0 : 1.0;
  return s*sqrt( min(dot2(ca),dot2(cb)) );
}

float sdCappedCylinder( vec3 p, float h, float r )
{
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}


float sdfSphere(vec3 query_position, vec3 position, float radius) {
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
    float x2 = dot2( pa*l2 - ba*y );
    float y2 = y*y*l2;
    float z2 = z*z*l2;

    // single square root!
    float k = sign(rr)*rr*rr*x2;
    if( sign(z)*a2*z2 > k ) return  sqrt(x2 + z2)        *il2 - r2;
    if( sign(y)*a2*y2 < k ) return  sqrt(x2 + y2)        *il2 - r1;
                            return (sqrt(x2*a2*il2)+y*rr)*il2 - r1;
}

float sdEllipsoid( vec3 p, vec3 r )
{
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return k0*(k0-1.0)/k1;
}

float sdTorus( vec3 p, vec2 t )
{
  vec2 q = vec2(length(p.xz)-t.x,p.y);
  return length(q)-t.y;
}

/*
DRAW SDF
*/

//TOWER
#define TOWER_NECK sdCappedCone(queryPos, 1.5, 0.6, 0.4)
#define TOWER_WINDOW  sdBox(vec3(vec4(queryPos, 1.0) * inverseRotate(vec3(0., 60., 0.))) + vec3(0., -2.5, 0.0), vec3(1.3, .25, .2))
#define TOWER_ROOM  sdCappedCone(queryPos + vec3(0., -1.6, 0.), 0.4, 0.4, 1.1)
#define NECK_ROOM_BLEND opSmoothUnion(TOWER_NECK, TOWER_ROOM, 1.3)
#define TOWER_CYL sdCappedCylinder(queryPos + vec3(0., -2.5, 0.), 1.2, 0.6)
#define TOWER_SUBTRACT opSubtraction(TOWER_WINDOW, TOWER_CYL)
#define CYL_ROOM_BLEND opSmoothUnion(TOWER_SUBTRACT, NECK_ROOM_BLEND, 0.5)

#define TOWER_ROOF sdCappedCone(queryPos + vec3(0., -3.4, 0.), 0.3, 1.6, 0.6)
#define TOWER_TIP sdCappedCone(queryPos + vec3(0., -4.5, 0.), 1.5, 0.7, 0.01)
#define TOWER_TOP opSmoothUnion(TOWER_ROOF, TOWER_TIP, 0.5)
#define FINAL_TOWER opSmoothUnion(TOWER_TOP, CYL_ROOM_BLEND, 0.2)

#define BOTTOM sdCappedCone(queryPos + vec3(0., 3., 0.), 2., 1.5, 0.48)
#define BOTTOM_2 sdCappedCone(queryPos + vec3(0., 4.5, 0.), .3, 2., 1.2)
#define BOTTOM_BLEND opSmoothUnion(BOTTOM, BOTTOM_2, 1.1)
#define NECK_BOTTOM_BLEND opSmoothUnion(BOTTOM_BLEND,TOWER_NECK, 0.01)

#define TOWER_CONNECT opSmoothUnion(FINAL_TOWER, NECK_BOTTOM_BLEND, 0.5)

// TOWER DETAILS
#define TOWER_RING_2 sdTorus(queryPos + vec3(0., -1., 0.0), vec2(0.8, 0.1))
#define TOWER_RING_1 sdTorus(queryPos + vec3(0., -1.9, 0.0), vec2(1.25, 0.1))
#define TOWER_RING_12 opUnion(TOWER_RING_2, TOWER_RING_1)
#define TOWER_RING_3 sdTorus(queryPos + vec3(0., -2.2, 0.0), vec2(1.25, 0.08))
#define TOWER_RING_123 opUnion(TOWER_RING_12, TOWER_RING_3)
#define TOWER_DEETS opUnion(TOWER_RING_123, TOWER_CONNECT)

#define TOWER_CHIMNEY sdBox(vec3(vec4(queryPos, 1.0) * inverseRotate(vec3(0., 60., 0.))) + vec3(-0.1, -3.5, -1.35), vec3(0.1, 0.4, 0.1))
#define TOWER_SIDE_1 sdBox(vec3(vec4(queryPos, 1.0) * inverseRotate(vec3(0., 20., 0.))) + vec3(-0.0, -2.6, -1.3), vec3(0.1, 0.7, 0.05))
#define TOWER_SIDE_CONNECT opUnion(TOWER_DEETS, TOWER_SIDE_1)
#define TOWER_CHIMNEY_CONNECT opUnion(TOWER_SIDE_CONNECT, TOWER_CHIMNEY)

#define TOWER_DIAG_BASE rotateX(queryPos, -23.)
#define TOWER_DIAG_1 sdBox(rotateZ(rotateY(rotateX(queryPos, -23.), 0.), 0.)  + vec3(-0.0, -1.7, -0.39), vec3(0.1, 0.5, 0.05))
#define TOWER_DIAG_2 sdBox(rotateZ(rotateY(rotateX(queryPos, -28.), 30.), -10.)  + vec3(0.2, -1.7, -0.37), vec3(0.1, 0.5, 0.05))
#define TOWER_DIAG_3 sdBox(rotateZ(rotateY(rotateX(queryPos, -28.), -30.), 10.)  + vec3(-0.2, -1.7, -0.37), vec3(0.1, 0.5, 0.05))
#define TOWER_D opUnion(TOWER_DIAG_1, TOWER_DIAG_2)
#define TOWER_D1 opUnion(TOWER_D, TOWER_DIAG_3)

#define TOWER_D_CONNECT opUnion(TOWER_D1, TOWER_CHIMNEY_CONNECT)

//FLOOR
#define ROCK_FBM fbm(queryPos.x / 15., queryPos.y / 15., queryPos.z / 15., 6.)
#define ROCK_FBM_2 fbm(queryPos.x / 10., queryPos.y / 10., queryPos.z / 10., 6.)
#define FRONT_ROCK sdEllipsoid(vec3(vec4(queryPos + vec3(4., 6., 0.), 1.) * inverseRotate(vec3(0., 0., -10.))), vec3(10., 2., 3.))//+ ROCK_FBM
#define FRONT_RIGHT sdEllipsoid(vec3(vec4(queryPos + vec3(-4., 7., 0.), 1.) * inverseRotate(vec3(0., 0., -7.))), vec3(7., 2., 3.))// + ROCK_FBM
#define FRONT_FLOOR opSmoothUnion(FRONT_ROCK, FRONT_RIGHT, 0.5)
#define FRONT_CONNECTING sdEllipsoid(vec3(vec4(queryPos + vec3(2., 6., 0.), 1.) * inverseRotate(vec3(0., 0., 10.))), vec3(4., 2., 3.)) //+ ROCK_FBM
#define FRONT_CONNECTING_FLOOR opSmoothUnion(FRONT_CONNECTING, FRONT_FLOOR, 0.5)
#define TOWER_FLOOR opSmoothUnion(TOWER_DEETS, FRONT_CONNECTING_FLOOR, 1.5)

#define ROCK_1 sdEllipsoid(rotateY(queryPos + vec3(-0.8, 4.5, -0.8), 20.), vec3(1., 1.2, 1.)) //+ ROCK_FBM_2
#define ROCK_2 sdEllipsoid(rotateY(queryPos + vec3(1.2, 4.5, -1.2), 20.), vec3(0.6, 1., 0.6))// + ROCK_FBM_2
#define ROCK_C1 opSmoothUnion(ROCK_1, ROCK_2, 0.3)
#define FIN_FRONT opSmoothUnion(ROCK_C1, TOWER_FLOOR, 1.1)

// BACKGROUND
#define LEFT_WALL1 sdBox(vec3(vec4(queryPos + vec3(13., -0.5,3.), 1.) * inverseRotate(vec3(0., 40., 10.))), vec3(5., 8., 1.)) // + ROCK_FBM
#define WALL_C opSmoothUnion(FIN_FRONT, LEFT_WALL1, 5.5)

#define BACK_WALL sdBox(vec3(vec4(queryPos + vec3(6., -2.,11.), 1.) * inverseRotate(vec3(-10., 60., 10.))), vec3(5., 13., 0.4))
#define BACK_WALL_C opSmoothUnion(BACK_WALL, WALL_C, 5.5)

#define BACK_WALL_1 sdBox(vec3(vec4(queryPos + vec3(-1., -2.,15.), 1.) * inverseRotate(vec3(0., 0., 0.))), vec3(5., 13., 0.4))
#define BACK_WALL_C_2 opSmoothUnion(BACK_WALL_1, BACK_WALL_C, 1.5)


#define MID_WALL sdBox(vec3(vec4(queryPos + vec3(-11., -2.,13.), 1.) * inverseRotate(vec3(0., -30., 0.))), vec3(9., 13., 0.4))
#define MID_WALL_C opSmoothUnion(MID_WALL, BACK_WALL_C_2, 3.5)

#define RIGHT_WALL sdBox(vec3(vec4(queryPos + vec3(-12., -2. ,10.), 1.) * inverseRotate(vec3(0., -80., 0.))), vec3(9., 13., 1.)) // + ROCK_FBM
#define RIGHT_WALL_C opSmoothUnion(RIGHT_WALL , MID_WALL_C, 2.5)

//BIRDS

float sdBird(vec3 queryPos, float amp, float y, float z) {
  float xShift = (u_Time * 0.001 * amp - floor(u_Time * 0.001 * amp)) * 30.;
  float yShift = 2. * sin(u_Time / 200.);
  yShift = GetBias(yShift);
  vec3 birdTranslate = queryPos - vec3(16., y, z) + vec3(xShift, yShift, 0.);
  float birdBody = sdEllipsoid(birdTranslate, vec3(0.3, 0.1, 0.081));
  float birdWingBase1 = sdEllipsoid(rotateX(birdTranslate,  -30. * sin(u_Time/ 10.)) + vec3(0.0, 0.0, -0.2), vec3(0.1, 0.06, 0.35)) ;
  float birdWingBase2  = sdEllipsoid(rotateX(birdTranslate, 30. * sin(u_Time/ 10.)) + vec3(0.0, 0.0, 0.2), vec3(0.1, 0.06, 0.35));
  float birdCom1 = opUnion(birdWingBase2, birdWingBase1);
  float birdCom = opSmoothUnion(birdCom1, birdBody, 0.1);
  return birdCom;
}


float sceneSDF(vec3 queryPos, out int objHit) {

  float x = 1e+6;
  float t = RIGHT_WALL_C;
  if (t < x) {
    x = t;
    objHit = 1;
  }
  t = TOWER_D_CONNECT;
  if (t < x) {
    x = t;
    objHit = 2;
  }
  t = sdBird(queryPos, 6., 2.,  3.);
  if (t < x) {
    x = t;
    objHit = 3;
  }
  t = sdBird(queryPos, 5., -2., 4.);
  if (t < x) {
    x = t;
    objHit = 4;
  }

  t = sdBird(queryPos, 4., 4., 5.);
  if (t < x) {
    x = t;
    objHit = 5;
  }

  return x;
}

Ray getRay(vec2 uv) {
  Ray r;
  vec3 F = normalize(u_Ref - u_Eye);
  vec3 R = normalize(cross(F, u_Up));
  float len = length(vec3(u_Ref - u_Eye));
  float alpha = FOV / 2.f;
  vec3 V = u_Up * len * tan(alpha);
  float aspect = u_Dimensions.x / u_Dimensions.y;
  vec3 H = R * len * aspect * tan(alpha);
  vec3 p = u_Ref + fs_Pos.x * H + fs_Pos.y * V;
  r.origin = u_Eye;
  r.direction = normalize(p - u_Eye);

  return r;
}

vec3 estimateNormals(vec3 p) {
  vec2 d = vec2(0., EPSILON);
  int obj;
  float x = sceneSDF(p + d.yxx, obj) - sceneSDF(p - d.yxx, obj);
  float y = sceneSDF(p + d.xyx, obj) - sceneSDF(p - d.xyx, obj);
  float z = sceneSDF(p + d.xxy, obj) - sceneSDF(p - d.xxy, obj);

  return normalize(vec3(x, y, z));

}

Intersection getRaymarchedIntersection(vec2 uv) {
  Intersection intersection;
  float distanceT = 0.0;

  intersection.distance_t = -1.0;
  Ray r = getRay(uv);
  for(int step; step <= MAX_RAY_STEPS; ++step) {
    vec3 queryPoint = r.origin + r.direction * distanceT;
    int objHit;
    float sdf = sceneSDF(queryPoint, objHit);
    if(sdf < EPSILON) {
      intersection.distance_t = distanceT;
      intersection.normal = estimateNormals(queryPoint);
      intersection.position = queryPoint;
      intersection.material_id = objHit;
      return intersection;
    }
    distanceT += sdf;
  }
  return intersection;
}

float hardShadow(vec3 dir, vec3 origin) {
    float distanceT = 0.001;
    for(int i = 0; i < MAX_RAY_STEPS; ++i) {
        vec3 queryPoint = origin + dir * distanceT;
        int objHit;
        float m = sceneSDF(queryPoint, objHit);
        if(m < EPSILON) {
            return 0.0;
        }
        distanceT += m;
    }
    return 1.0;
}

vec3 getSceneColor(vec2 uv) {
    Intersection intersection = getRaymarchedIntersection(uv);
    if (intersection.distance_t > 0.0)
    { 
        float diffuseTerm = dot(intersection.normal, normalize(LIGHT_DIR - intersection.position));
        diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);
        float ambientTerm = 0.;
        float lightIntensity = diffuseTerm + ambientTerm;
        vec3 color = vec3(1);
        float shadow = hardShadow(normalize(LIGHT_DIR - intersection.position), intersection.position);
        return color * lightIntensity * shadow;
        // return color * intersection.normal;
    }
    return vec3(0.);
}

void main() {
  vec3 col = getSceneColor(fs_Pos);
  out_Col = vec4(col, 1.0);
}
