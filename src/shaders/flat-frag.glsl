#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 70;
const int MAX_SMOKE_STEPS = 1;
const float FOV = 0.25 * 3.141569;
const float EPSILON = .001;
const vec3 LIGHT = vec3(5, 3, 5);

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
    vec4 color;
};

Ray getRay(vec2 uv) {
    Ray r;
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, u_Up));
    vec3 camera_UP = cross(camera_RIGHT, look);
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = u_Up * length(u_Ref - u_Eye)* tan(FOV/2.); 
    vec3 screen_horizontal = camera_RIGHT * length(u_Ref - u_Eye) * aspect_ratio * tan(FOV/2.);
    vec3 screen_point = (u_Ref + uv.x * screen_horizontal + uv.y * screen_vertical);
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);
    return r;
}

mat4 inverseRotateY(float y) {
  y = radians(y);
  mat4 r_y;
  r_y[0] = vec4(cos(y), 0., -sin(y), 0.);
  r_y[1] = vec4(0., 1, 0., 0.);
  r_y[2] = vec4(sin(y), 0., cos(y), 0.);
  r_y[3] = vec4(0., 0., 0., 1.);
  return r_y;
}

// takes in radians (kinda messed up but don't wanna change the values)
mat4 inverseRotateZ(float z) {
  mat4 r_z;
  r_z[0] = vec4(cos(z), sin(z), 0., 0.);
  r_z[1] = vec4(-sin(z), cos(z), 0., 0.);
  r_z[2] = vec4(0., 0., 1., 0.);
  r_z[3] = vec4(0., 0., 0., 1.);
  return r_z;
}

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
    
mat4 inverseScale(vec3 scale) {
    mat4 s;
    s[0] = vec4(scale.x, 0., 0., 0.);
    s[1] = vec4(0., scale.y, 0., 0.);
    s[2] = vec4(0., 0., scale.z, 0.);
	s[3] = vec4(0., 0., 0., 1.);
    return s;   
}

float sdfSphere(vec3 query_position, vec3 position, float radius) {
    return length(query_position - position) - radius;
}

float dot2( in vec2 v ) { return dot(v,v); }
float dot2( in vec3 v ) { return dot(v,v); }

// h = height, r1 = bottom radius, r2 = top radius
float sdCappedCone(vec3 p, float h, float r1, float r2) {
  vec2 q = vec2( length(p.xz), p.y );
  vec2 k1 = vec2(r2,h);
  vec2 k2 = vec2(r2-r1,2.0*h);
  vec2 ca = vec2(q.x-min(q.x,(q.y<0.0)?r1:r2), abs(q.y)-h);
  vec2 cb = q - k1 + k2*clamp( dot(k1-q,k2)/dot2(k2), 0.0, 1.0 );
  float s = (cb.x<0.0 && ca.y<0.0) ? -1.0 : 1.0;
  return s*sqrt( min(dot2(ca),dot2(cb)) );
}

// ra = radius of cynlinder, rb = roundess of edges, h = height
float sdRoundedCylinder(vec3 p, float ra, float rb, float h) {
  vec2 d = vec2( length(p.xz)-2.0*ra+rb, abs(p.y) - h );
  return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
}

// a = left end position, b = right end position, r1 = left end radius, r2 = right end radius
float sdRoundCone(vec3 p, vec3 a, vec3 b, float r1, float r2) {
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

// b = dimensions of box
float sdBox(vec3 p, vec3 b) {
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdCappedCylinder(vec3 p, float h, float r) {
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

float sdHalfEllipsoid(vec3 p, vec3 r) {
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return max(k0*(k0-1.0)/k1, p.y);
}

float sdEllipsoid(vec3 p, vec3 r) {
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return k0*(k0-1.0)/k1;
}

float sdfHalfSphere(vec3 p, vec3 center, float radius) {
    return max(length(p - center) - radius, p.y);
}

float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); 
}
float opSmoothSubtraction(float d1, float d2, float k) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); 
}

vec3 opCheapBend(vec3 p, float k) {
    float c = cos(k*p.y);
    float s = sin(k*p.y);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
}

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

float fbm(float x, float y, float z) {
  float total = 0.;
  float persistence = 0.5f;
  for(float i = 1.; i <= 6.; i++) {
    float freq = pow(2., i);
    float amp = pow(persistence, i);
    total += interpNoise3D(x * freq, y * freq, z * freq) * amp;
  }
  return total;
}

float bowl(vec3 p) {
  p.x += .5;
  return opSmoothUnion(max(abs(sdCappedCone(p, .7, .7, .85) - .25) - .02, p.y),
                      sdRoundedCylinder(p + vec3(0, 1, 0), .26, .05, .2), .2);
}

float soup(vec3 p) {
  p.x += .5;
  return max(sdCappedCone(p, .7, .7, .85) - .25, p.y + .2);
}

float chopsticks(vec3 p) {
  float box = sdBox(vec3(inverseRotateY(-50.) * vec4(p - vec3(1.8, -1, -.3), 1)), vec3(.4, .22, 1.3));
  if (box > EPSILON) {
    return box;
  }
  p.y -= .15;
  mat4 invRotate = inverseRotateY(-30.);
  return min(min(sdRoundCone(p, vec3(1., -.96, -1), vec3(2.6, -1.37, .2), .02 ,.05),
              sdRoundCone(p, vec3(1.1, -.96, -.9), vec3(2.8, -1.37, .2), .02 ,.05)),
              opSmoothSubtraction( 
                          sdBox(vec3(invRotate * vec4(p - vec3(1.3, -1., -.8), 1)), vec3(.15, .07, .5)) - .05,
                          sdBox(vec3(invRotate * vec4(p - vec3(1.3, -1.2, -.8), 1)), vec3(.3, .15, .23)) - .05, .05));
}

// lima = left end position of repition block, limb = right end
float enoki(vec3 p, float s, vec3 lima, vec3 limb) {
  vec3 q = p-s*clamp(round(p/s),lima,limb);
  return opSmoothUnion(sdRoundedCylinder(opCheapBend(q, .2), .012, .06, .4),
                      sdCappedCone(vec3(inverseRotateZ(-25.) * vec4(q - vec3(-.06, .5, 0), 1)), .01, .025, .01) - .06, .02);
}

float enoki2(vec3 p, float s, vec3 lima, vec3 limb) {
  vec3 q = p-s*clamp(round(p/s),lima,limb);
  return opSmoothUnion(sdRoundedCylinder(opCheapBend(q, -.1), .01, .04, .3),
                      sdCappedCone(vec3(inverseRotateZ(15.) * vec4(q - vec3(0.02, .35, 0), 1)), .005, .008, .004) - .04, .01);
}

float enoki3(vec3 p, float s, vec3 lima, vec3 limb) {
  vec3 q = p-s*clamp(round(p/s),lima,limb);
  return opSmoothUnion(sdRoundedCylinder(opCheapBend(q, -.1), .01, .04, .3),
                      sdCappedCone(vec3(inverseRotateZ(15.) * vec4(q - vec3(0.02, .35, 0), 1)), .005, .008, .004) - .04, .01);
}

float enokis(vec3 p) {
  float box = sdBox(vec3(inverseRotateY(-50.) * vec4(p - vec3(-.9, .05, -.35), 1)), vec3(.5, .34, .35));
  if (box > EPSILON) {
    return box;
  }
  p = vec3(inverseRotate(vec3(50, -60, 0)) * vec4(p - vec3(-.93, -.05, -.6), 1));
  return min(min(enoki(vec3(inverseRotate(vec3(0, 0, -5)) * vec4(p - vec3(-.05, -.1, 0), 1)), .3, vec3(-1, 0, 0), vec3(1, 0, 0)), 
              enoki2(vec3(inverseRotate(vec3(0, 3, 12)) * vec4(p - vec3(-.1, 0,.05), 1)), .2, vec3(-2., 0, .5), vec3(1., 0, .5))),
              enoki3(vec3(inverseRotate(vec3(12, 15, -2)) * vec4(p - vec3(-.02, -.2, 0), 1)), .14, vec3(-3., 0, 1.), vec3(2., 0, 1.)));
}

// 2 egg whites
float eggWhite(vec3 p) {
  vec3 a = vec3(inverseRotate(vec3(-20, -10, 0)) * vec4(p - vec3(-.07, .02, -.1), 1));
  float egg1 = sdHalfEllipsoid(a, vec3(.3, .25, .2));
  // left
  vec3 b = vec3(inverseRotate(vec3(-5, 10, 0)) * vec4(p - vec3(-.9, -.04, .2), 1));
  float egg2 = sdHalfEllipsoid(b, vec3(.3, .25, .2));
  return min(egg1, egg2);
}

// 2 egg yolks
float eggYolk(vec3 p) {
  vec3 a = vec3(inverseRotate(vec3(-20, -10, 0)) * vec4(p - vec3(-.05, .04, -.1), 1));
  float egg1 = sdfHalfSphere(a, vec3(0, 0, 0), .17);
  vec3 b = vec3(inverseRotate(vec3(-5, 10, 0)) * vec4(p - vec3(-.9, -.02, .2), 1));
  float egg2 = sdfHalfSphere(b, vec3(0, 0, 0), .17);
  return min(egg1, egg2);
}

float table(vec3 p) {
    p.y += 1.45;
    return sdBox(p, vec3(6, .2, 3));
}

float noodle(vec3 p) {
  float box = sdBox(vec3(inverseRotateY(45.) * vec4(p - vec3(-.54, -.15, 0), 1)), vec3(.8, .06, .8));
  if (box > EPSILON) {
    return box;
  }
  float y = radians(50.);
  mat4 r_z;
  r_z[0] = vec4(cos(y), sin(y), 0., 0.);
  r_z[1] = vec4(-sin(y), cos(y), 0., 0.);
  r_z[2] = vec4(0., 0., 1., 0.);
  r_z[3] = vec4(0., 0., 0., 1.);

  float s = .2;
  vec3 a = vec3(inverseRotate(vec3(95, 50, 0)) * vec4(p - vec3(-.52, -.21, 0), 1));
  a = a-s*clamp(round(a/s),vec3(-2, 0, 0),vec3(3, 0, 0));
  a.x += .02 * cos(15.*a.y);
  a.z -= .1 * cos(2.*a.y - .7);
  float group1 = sdRoundedCylinder(a, .013, .1, .75);

  s = .15;
  vec3 b = vec3(inverseRotate(vec3(95, 30, 0)) * vec4(p - vec3(-.43, -.23, 0), 1));
  b = b-s*clamp(round(b/s),vec3(-2, 0, 0),vec3(3, 0, 0));
  b.x += .02 * cos(12.*b.y);
  b.z -= .09 * cos(2.*b.y - .7);
  float group2 = sdRoundedCylinder(b, .013, .1, .8);
  return min(group1, group2);
}

float sausages(vec3 p) {
  float box = sdBox(vec3(inverseRotateY(-80.) * vec4(p - vec3(-1.3, .03, .1), 1)), vec3(.35, .3, .07));
  if (box > EPSILON) {
    return box;
  }
  vec3 a = vec3(inverseRotate(vec3(90, -80, -20)) * inverseScale(vec3(1, .7 , 1)) * vec4(p - vec3(-1.35, 0, .2), 1));
  float front = sdCappedCylinder(a, .2, .02) - .02;
  vec3 b = vec3(inverseRotate(vec3(90, -60, 0)) * inverseScale(vec3(.7, 1. , 1)) * vec4(p - vec3(-1.35, 0, -.08), 1));
  float back = sdCappedCylinder(b, .18, .01) - .02;
  return min(front, back);
}

float mushroom(vec3 p) {
  float box = sdBox(p - vec3(.05, .14, -.5), vec3(.2, .25, .25));
  if (box > EPSILON) {
    return box;
  }
  p.x -= .2;
  p.y += .05;
  p.z += .65;
  vec4 rotated = inverseRotate(vec3(10, -70, 15)) * vec4(p, 1); 
  vec4 rotated2 = inverseRotate(vec3(20, -120, 15)) * vec4(p, 1); 
  return opSmoothUnion(sdBox(vec3(rotated - vec4(-.06, .1, -.11, 0)), vec3(.0005, .25, .08)) - .02, 
        // mushroom top
        opSmoothSubtraction(sdEllipsoid(p - vec3(.05, .2, .02), vec3(.3, .05, .3)),
                            max(max(sdCappedCone(p - vec3(0, .3, 0), .002, .3, .3) - .12, rotated2.x), rotated.z), .02), .01); 
}

float mushroom2(vec3 p) {
  float box = sdBox(p - vec3(-.3, .14, -.4), vec3(.3, .35, .3));
  if (box > EPSILON) {
    return box;
  }
  p = vec3(inverseRotate(vec3(10, -20, -10)) * vec4(p - vec3(-.4, .3, -.7), 1));
  return opSmoothUnion(sdCappedCone(p, .002, .15, .1) - .07,
                    sdBox(p - vec3(0, -.3, 0), vec3(.1, .3, .05)), .05);
}

float noise(vec3 p) {
  float f = fbm(p.x, p.y, p.z);
  vec4 pos = vec4(p, 1.0);
  pos += f; 
  return fbm(pos.x - .05*float(u_Time), pos.y - .05*float(u_Time), pos.z);
}

float GetBias(float time, float bias) {
  return (time / ((((1.0/bias) - 2.0)*(1.0 - time))+1.0));
}

float GetGain(float time, float gain) {
  if(time < 0.5)
    return GetBias(time * 2.0,gain)/2.0;
  else
    return GetBias(time * 2.0 - 1.0,1.0 - gain)/2.0 + 0.5;
}

float smoke(vec3 p, vec3 dir, out bool hit) {
  float box = sdBox(p - vec3(.2, 1, 0), vec3(.8, 1, 1));
  if (box > EPSILON) {
    return box;
  }
  p.y *= .7;
  p.y += .1;
  float d = sdfSphere(p, vec3(0, 1, 0), 1.);
  float t = 0.01;
  if (d < EPSILON) {
    float sum = 0.;
    for (int step = 0; step < 200; step++) {
      p = p + dir * t;
      if (sdfSphere(p, vec3(0, 1, 0), 1.) > EPSILON) {
        break;
      }
      float den = noise(p);
      sum += clamp((den * den * den) / 350., 0. , .01);
      t += .001;
    }
    hit = true;
    sum = mix(0., sum * sum * 30., GetGain(1. - abs(p.x), .6));
    return clamp(20. * sum, 0.0, 1.0);    
  } else {
    hit = false;
    return d;
  }
}

float sceneSDF(vec3 p, out int objHit) {
  float x = 10000000.;
  float t = bowl(p);
  if (t < x) {
    x = t;
    objHit = 1;
  }
  t = chopsticks(p);
  if (t < x) {
    x = t;
    objHit = 2;
  }
  t = enokis(p);
  if (t < x) {
    x = t;
    objHit = 3;
  }
  t = eggWhite(p);
  if (t < x) {
    x = t;
    objHit = 4;
  }
  t = eggYolk(p);
  if (t < x) {
    x = t;
    objHit = 5;
  }
  t = table(p);
  if (t < x) {
    x = t;
    objHit = 6;
  }
  t = soup(p);
  if (t < x) {
    x = t;
    objHit = 7;
  }
  t = noodle(p);
  if (t < x) {
    x = t;
    objHit = 8;
  }
  t = sausages(p);
  if (t < x) {
    x = t;
    objHit = 9;
  }
  t = mushroom(p);
  if (t < x) {
    x = t;
    objHit = 9;
  }
  t = mushroom2(p);
  if (t < x) {
    x = t;
    objHit = 10;
  }
  return x;
}

vec3 normal(vec3 p) {
  vec2 q = vec2(0, EPSILON);
  int obj;
  return normalize(vec3(sceneSDF(p + q.yxx, obj) - sceneSDF(p - q.yxx, obj),
              sceneSDF(p + q.xyx, obj) - sceneSDF(p - q.xyx, obj),
              sceneSDF(p + q.xxy, obj) - sceneSDF(p - q.xxy, obj)));
}

float shadow(vec3 dir, vec3 origin) {
    float t = 0.01;
    for(int i = 0; i < MAX_RAY_STEPS; ++i) {
        int obj;
        float m = sceneSDF(origin + t * dir, obj);
        if(m < EPSILON) {
            return 0.0;
        }
        t += m;
    }
    return 1.0;
}

Intersection getRaymarchedIntersection(vec2 uv) {
    Intersection intersection;    
    intersection.distance_t = -1.0;
    Ray r = getRay(uv);
    float t = 0.0;
    for (int step = 0; step < MAX_RAY_STEPS; ++step) {
      vec3 queryPoint = r.origin + r.direction * t;
      int objHit;
      float currentDist = sceneSDF(queryPoint, objHit);
      if (currentDist < EPSILON) {
        intersection.distance_t = t;
        intersection.normal = normal(queryPoint);
        intersection.position = queryPoint;
        intersection.material_id = objHit;
        return intersection;
      }
      t += currentDist;
    }
    return intersection;
}

Intersection getRaymarchedIntersectionSmoke(vec2 uv) {
    Intersection intersection;    
    intersection.distance_t = -1.0;
    Ray r = getRay(uv);
    float t = 0.0;
    for (int step = 0; step < MAX_RAY_STEPS; ++step) {
      vec3 queryPoint = r.origin + r.direction * t;
      bool hit;
      float currentDist = smoke(queryPoint, r.direction, hit);
      if (hit) {
        intersection.distance_t = currentDist;
        intersection.position = queryPoint;
        return intersection;
      }
      t += currentDist;
    }
    return intersection;
}

vec4 getSceneColor(vec2 uv) {
    vec3 color = vec3(0);
    Intersection intersection = getRaymarchedIntersection(uv);
    if (intersection.distance_t > 0.0) { 
      float diffuseTerm = dot(intersection.normal, normalize(LIGHT - intersection.position));
      diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);
      float ambientTerm = 0.2;
      float lightIntensity = diffuseTerm + ambientTerm;
      // color = vec3(1., .88, .7); 
      color = vec3(1., .9, .8); 
      // putting to power of > 1 darkens shadows- gamma correction
      // pow(color, vec4(1/2.2))  // use with darker material colors for photorealistic
      // color = pow(1.4 * color, vec3(1.5, 1.2, 1));
      
      color = color * lightIntensity * shadow(normalize(LIGHT - intersection.position), intersection.position);
    }
    Intersection smoke = getRaymarchedIntersectionSmoke(uv);
    if (smoke.distance_t > 0.0) {
      return vec4(color, 1. - (smoke.distance_t) * 1.);
    }
    return vec4(color, 1);
}

void main() {
  // Normalized pixel coordinates (from 0 to 1)
  vec2 uv = fs_Pos;
    
  vec4 col = getSceneColor(uv);
  
  // Output to screen
  out_Col = col;
  
  // out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
}
