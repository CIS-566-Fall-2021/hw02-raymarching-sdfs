#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

/* ---------------------- common -------------------------------------------- */
const int MAX_RAY_STEPS = 180;
const float FOV = 45.0;
const float EPSILON = 1e-2;

const vec3 EYE = vec3(0.0, 0.0, 10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const vec3 LIGHT_DIR = vec3(0.0, 0.1, -2.0);

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

float sdCone( vec3 p, vec2 c, float h )
{
    float q = length(p.xz);
    return max(dot(c.xy,vec2(q,p.y)),-h-p.y);
}

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdCappedCylinder( vec3 p, float h, float r )
{
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

float opSubtraction( float d1, float d2 ) { return max(-d1,d2); }

float toRad(float deg){
  return deg * 3.14159 / 180.0;
}

float bias(float t, float b){
  return pow(t, log(b) / log(0.5));
}

vec2 random2( vec2 p ) {
    return fract(sin(vec2(dot(p,vec2(127.1, 311.7)),
                          dot(p,vec2(269.5, 183.3))))
                 *43758.5453);
}

vec3 random3( vec3 p ) {
    return fract(sin(vec3(dot(p,vec3(127.1, 311.7, 191.999)),
                          dot(p,vec3(269.5, 183.3, 765.54)),
                          dot(p, vec3(420.69, 631.2,109.21))))
                 *43758.5453);
}

float surflet(vec2 p, vec2 gridPoint) {
    // Compute the distance between p and the grid point along each axis, and warp it with a
    // quintic function so we can smooth our cells
    vec2 t2 = abs(p - gridPoint);
    vec2 t = vec2(1.0) - 6.0 * vec2(pow(t2.x, 5.0), pow(t2.y, 5.0)) + 
                         15.0 * vec2(pow(t2.x, 4.0), pow(t2.y, 4.0)) - 
                         10.0 * vec2(pow(t2.x, 3.0), pow(t2.y, 3.0));

    vec2 gradient = random2(gridPoint) * 2.0 - vec2(1.0);
    // Get the vector from the grid point to P
    vec2 diff = p - gridPoint;
    // Get the value of our height field by dotting grid->P with our gradient
    float height = dot(diff, gradient);
    // Scale our height field (i.e. reduce it) by our polynomial falloff function
    return height * t.x * t.y;
}

float perlinNoise2D(vec2 p) {
	float surfletSum = 0.0;
	// Iterate over the four integer corners surrounding uv
	for(int dx = 0; dx <= 1; ++dx) {
		for(int dy = 0; dy <= 1; ++dy) {
				surfletSum += surflet(p, floor(p) + vec2(dx, dy));
		}
	}
	return surfletSum;
}

float Worley3D(vec3 p) {
    // Tile the space
    vec3 pointInt = floor(p);
    vec3 pointFract = fract(p);

    float minDist = 1.0; // Minimum distance initialized to max.

    // Search all neighboring cells and this cell for their point
    for(int z = -1; z <= 1; z++){
        for(int y = -1; y <= 1; y++){
            for(int x = -1; x <= 1; x++){
                vec3 neighbor = vec3(float(x), float(y), float(z));

                // Random point inside current neighboring cell
                vec3 point = random3(pointInt + neighbor);

                // Compute the distance b/t the point and the fragment
                // Store the min dist thus far
                vec3 diff = neighbor + point - pointFract;
                float dist = length(diff);
                minDist = min(minDist, dist);
            }
        }
    }
    return minDist;
}

float easeOutQuad(float x){
  return 1.0 - (1.0 - x) * (1.0 - x);
}

float easeInQuad(float x){
  return x * x;
}

float easeInOutQuad(float x) {
  return x < 0.5 ? 2.0 * x * x : 1.0 - ((-2.0*x + 2.0)*(-2.0*x + 2.0)) / 2.0;
}

float easeOutCubic(float x) {
  return 1.0 - pow(1.0 - x, 3.0);
}

float easeInCubic(float x) {
  return x * x ;
}

// take the radius and height and find the angle in radians
float getConeAngle(float h, float r){
  float hyp = sqrt(h*h + r*r);
  return acos(h / hyp);
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float cubicPulse(float c, float w, float x){
  x = abs(x-c);
  if (x>w) return 0.0;
  x /= w;
  return 1.0 - x*x*(3.0 - 2.0*x);
}

vec3 rotateX(vec3 p, float a){
    a = a * 3.14159 / 180.0;
    return vec3(p.x, cos(a) * p.y - sin(a) * p.z, sin(a) * p.y + cos(a) * p.z);
}
vec3 rotateY(vec3 p, float a){
    a = a * 3.14159 / 180.0;
    return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
}
vec3 rotateZ(vec3 p, float a){
    a = a * 3.14159 / 180.0;
    return vec3(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y, p.z);
}

float sdBox( in vec2 p, in vec2 b )
{
    vec2 d = abs(p)-b;
    return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}

float sdRoundBox( vec3 p, vec3 b, float r ){
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

/* ----------------------- Scene definition --------------------------------- */

const vec3 guideLightPos = vec3(-1.6, 0.0, 6.9); // point light to represent player
const vec3 guideLightColor = vec3(255.0, 200.0, 100.0) / 255.0;
const vec3 skyLight = vec3(1.0);
const vec3 skyLightPos = vec3(-3.0, 3.0, -6.0);
const float skyLightRadius = 7.5;

const vec4 skyColor = vec4(173.0, 229.0, 240.0, 255.0) / 255.0;
const vec4 fogColor = vec4(133.0, 190.0, 220.0, 255.0) / 255.0;

const vec3 templePos = vec3(-3.7, 0.0, 10.0);

// forest controls
const vec3 treePositions[6] = vec3[6](vec3(-2.7, -7.0, -6.0), // tree right
                                      vec3(3.6, -7.0, -6.8), 
                                      vec3(4.1, -7.0, -4.0), 
                                      vec3(3.9, -7.0, -1.5),
                                      vec3(3.3, -7.0, 3.0),
                                      vec3(-3.6, -7.0, -1.0) // tree right 2
                                      );
const float treeRadii[6] = float[6](1.0, 0.7, 0.7, 0.7 ,0.9, 0.9);
// fake trees (distant, less detailed trees)
const vec3 fakeTreePositions[4] = vec3[4](vec3(-0.5, 0.0, 25.0),
                                          vec3(-2.1, 0.0, 18.0),
                                          vec3(-5.5, 0.0, 19.0),
                                          vec3(5.5, 0.0, 40.0));
const float fakeTreeRadii[4] = float[4](0.8, 1.1, 0.9, 0.8);
// tree height constant across all trees
const float treeHeight = 10.0;


// terrain controls
const float groundHeight = -1.0;
const float pathX = 0.0; // place path in center of screen
const float pathColorWidth = 0.4; // how wide the colored/textured portion of the path is
const float pathPaveWidth = pathColorWidth + 0.3; // distance over which to interpolate b/w hills and flat path

// material ids
#define GROUND_MAT_ID 0
#define TREE_MAT_ID 1
#define PATH_MAT_ID 2
#define TEMPLE_MAT_ID 3

float getTerrainHeight(vec2 xzCoords, out bool isPath){
  isPath = false;

  // hill and path controls
  float hillFreq = 4.5;
  float hillOffset = 2.5;
  float hillHeight = 1.3;

  float waveStart = -1.5;
  float waveFreq = 2.5;
  float waveAmp = 0.78;

  // create hills
  float deformedHeight = hillHeight *perlinNoise2D((xzCoords / hillFreq) + hillOffset) + groundHeight;

  // displace path in shape of sin wave
  float wavyPath = pathX - waveAmp*sin((xzCoords.y - waveStart) / waveFreq) - 0.9;
  float distToPath = abs(xzCoords.x - wavyPath);
  if (distToPath < pathPaveWidth){    
    if (distToPath < pathColorWidth){
      isPath = true;
    }  
    return mix(groundHeight, deformedHeight, easeInOutQuad(distToPath / pathPaveWidth));
  }
  return deformedHeight;
}

// the distant trees with less detail
float fakeTreeSDF(vec3 queryPt, float r, vec3 treePos){
  float treeTrunk = sdCappedCylinder(queryPt + treePos, r, treeHeight + 12.0);
  return treeTrunk;
}

float treeSDF(vec3 queryPt, float r){
  // tree knot controls
  float treeKnotRadius = 0.8 * r;
  float treeKnotHeight = 0.25 * treeHeight;
  float treeKnotSmoothFactor = 0.7;

  // get angles to create tree knot cones
  float treeKnotAngle = getConeAngle(treeKnotHeight, treeKnotRadius);
  vec2 treeKnotAngles = vec2(cos(treeKnotAngle), sin(treeKnotAngle));

  // find tree knot displacements (relative to trunk)
  vec3 treeKnotDisplacement1 = vec3(r - 0.29*treeKnotRadius, treeHeight - treeKnotHeight, r - 0.29*treeKnotRadius);
  vec3 treeKnotDisplacement2 = vec3(-treeKnotDisplacement1.x, treeKnotDisplacement1.yz);
  vec3 treeKnotDisplacement3 = vec3(-treeKnotDisplacement1.x, treeKnotDisplacement1.y, -treeKnotDisplacement1.z);
  vec3 treeKnotDisplacement4 = vec3(treeKnotDisplacement1.x, treeKnotDisplacement1.y, -treeKnotDisplacement1.z);
  
  // tree knot sdf definitions
  float treeKnot1 = sdCone(queryPt + treeKnotDisplacement1, treeKnotAngles, treeKnotHeight);
  float treeKnot2 = sdCone(queryPt + treeKnotDisplacement2, treeKnotAngles, treeKnotHeight);
  float treeKnot3 = sdCone(queryPt + treeKnotDisplacement3, treeKnotAngles, treeKnotHeight);
  float treeKnot4 = sdCone(queryPt + treeKnotDisplacement4, treeKnotAngles, treeKnotHeight);
  float treeTrunk = sdCappedCylinder(queryPt, r, treeHeight);
  
  // smooth SDF between trunk and knots
  float res = smin(treeTrunk, treeKnot1, treeKnotSmoothFactor);
  res = smin(res, treeKnot2, treeKnotSmoothFactor);
  res = smin(res, treeKnot3, treeKnotSmoothFactor);
  res = smin(res, treeKnot4, treeKnotSmoothFactor);

  return res;
}

float forestSDF(vec3 queryPt){
  float minSDF = 10000000.0;
  for (int i = 0; i < treePositions.length(); i++){
    float rand = clamp(random2(vec2(i + 1, i)).x, 0.0, 1.0);
    float slightSkew = mix(-2.0, 2.0, rand);
    float rotY = mix(-180.0, 180.0, rand);
    minSDF = min(minSDF, treeSDF(rotateY(rotateZ(queryPt + treePositions[i], slightSkew), rotY), treeRadii[i]));
  }
  for (int i = 0; i < fakeTreePositions.length(); i++){
    minSDF = min(minSDF, fakeTreeSDF(queryPt, fakeTreeRadii[i], fakeTreePositions[i]));
  }
  return minSDF;
}

bool getRainColor(vec2 uv){
  uv = uv * 2.0;
  uv.y = uv.y + u_Time * 0.3;

  // use worley method to setup cell centers and see if points fall in rectangle
  // sdf with cell center as rectangle center
    vec2 pointInt = floor(uv);
    vec2 pointFract = fract(uv);
    vec2 boxDims = vec2(0.007, 0.5);

    float minDist = 1.0;
    vec2 minDiff = vec2(0.0);
    vec2 minCellCenter = vec2(0.0);

    // Search all neighboring cells and this cell for their point
        for(int y = -1; y <= 1; y++){
            for(int x = -1; x <= 1; x++){
                vec2 neighbor = vec2(float(x), float(y));

                // Random point inside current neighboring cell
                vec2 animatedPt = pointInt + neighbor;
                //animatedPt.y = animatedPt.y + u_Time*0.0001;
                vec2 cellCenter = random2(animatedPt);

                // Compute the distance b/t the point and the fragment
                // Store the min dist thus far
                vec2 diff = neighbor + cellCenter - pointFract;
                float dist = length(diff);
                if (dist < minDist){
                  minDist = dist;
                  minDiff = diff;
                  minCellCenter = cellCenter;
                }
            }
        }

    boxDims.y = mix(0.5, 1.0, random2(minCellCenter).x);
    if (minDist < 0.5 && abs(minDiff.x) <= (boxDims.x / 2.0) && abs(minDiff.y) <= (boxDims.y / 2.0)){
      return true;
    }
    return false;
}

float columnSDF(vec3 queryPt, vec3 columnPos){
  vec3 columnPt = queryPt + columnPos;

  float baseH = 0.1, baseW = 0.44;
  float stone1H = 0.56, stone1W = 0.28;
  float stone2H = 0.58, stone2W = 0.16;
  float stone3H = 0.1, stone3W = 0.25;

  float minSDF = sdBox(columnPt, vec3(0.44, 0.1, 0.44));
  minSDF = min( minSDF, sdRoundBox(columnPt + vec3(0.0, -(baseH + stone1H), 0.0), vec3(stone1W, stone1H, stone1W), 0.1) );
  minSDF = min( minSDF, sdRoundBox(columnPt + vec3(0.0, -(baseH + stone1H + stone2H + 0.6), 0.0), vec3(stone2W, stone2H, stone2W), 0.1) );
  minSDF = min( minSDF, sdRoundBox(columnPt + vec3(0.0, -(baseH + stone1H + stone2H + stone3H + 1.2), 0.0), vec3(stone3W, stone3H, stone3W), 0.05) );

  return minSDF;
}

float templeSDF(vec3 queryPt, vec3 translate, float scale){

  vec3 templePos = rotateY(queryPt + translate, 247.0) / scale;

  float minSDF = sdRoundBox(templePos, vec3(2.7, 0.15, 2.7), 0.05);

  // columns
  float columnPadding = 1.8;
  minSDF = min(minSDF, columnSDF(templePos, vec3(-columnPadding, -0.3, -columnPadding))); 
  minSDF = min(minSDF, columnSDF(templePos, vec3(-columnPadding, -0.3, columnPadding)));
  minSDF = min(minSDF, columnSDF(templePos, vec3(columnPadding, -0.3, columnPadding)));
  minSDF = min(minSDF, columnSDF(templePos, vec3(columnPadding, -0.3, -columnPadding)));

  // temple top
  minSDF = min( minSDF, sdRoundBox(templePos + vec3(0.0, -3.1, 0.0), vec3(2.2, 0.13, 2.2), 0.05) );
  minSDF = min( minSDF, sdRoundBox(templePos + vec3(0.0, -3.5, 0.0), vec3(2.5, 0.3, 2.5), 0.05) );
  minSDF = min( minSDF, sdRoundBox(templePos + vec3(0.0, -4.1, 0.0), vec3(1.9, 0.3, 1.9), 0.05) );
  minSDF = min( minSDF, sdRoundBox(templePos + vec3(0.0, -4.5, 0.0), vec3(1.5, 0.18, 1.5), 0.1) );

  return minSDF;
}

/* -------------------------------------------------------------------------- */

Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 look = normalize(u_Ref - u_Eye);
    float len = length(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, u_Up));
    vec3 camera_UP = cross(camera_RIGHT, look);
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = camera_UP * len * tan(FOV / 2.0); 
    vec3 screen_horizontal = camera_RIGHT * len * aspect_ratio * tan(FOV / 2.0);
    vec3 screen_point = (u_Ref + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);
   
    return r;
}

float sceneSDF(vec3 queryPt, out int material_id, out bool terminateRaymarch) 
{
    bool isPath = false;
    terminateRaymarch = false;
    float minSDF = queryPt.y - getTerrainHeight(queryPt.xz, isPath);
    minSDF = smin(minSDF, sdRoundBox(rotateZ(rotateY(queryPt + vec3(-4.0, 1.0, 10.0), 240.0),-3.0), vec3(2.2, 0.01, 2.2), 1.0),0.9);
    material_id = isPath ? PATH_MAT_ID : GROUND_MAT_ID;

    // if pt - terrainHeight is negative, pt is under land, terminate early
    if (minSDF < 0.0){
      terminateRaymarch = true;
      return -1.0;
    }

    float forestSDF = forestSDF(queryPt);
    if (forestSDF < minSDF){
      minSDF = forestSDF;
      material_id = TREE_MAT_ID;
    }

    float templeSDF = templeSDF(queryPt, templePos, 0.9);
    if (templeSDF < minSDF){
      minSDF = templeSDF;
      material_id = TEMPLE_MAT_ID;
    }

    return minSDF;   
}

float sceneSDF(vec3 queryPt) 
{
    bool isPath;
    float minSDF = queryPt.y - getTerrainHeight(queryPt.xz, isPath);
    minSDF = smin(minSDF, sdRoundBox(rotateZ(rotateY(queryPt + vec3(-4.0, 1.0, 10.0), 240.0),-3.0), vec3(2.2, 0.01, 2.2), 1.0),0.9);
    minSDF = min(minSDF, templeSDF(queryPt, templePos, 0.9));
    return min(minSDF, forestSDF(queryPt));
    
}

vec3 getNormal(vec3 queryPt){
  vec2 d = vec2(0.0, EPSILON);
  float x = sceneSDF(queryPt + d.yxx) - sceneSDF(queryPt - d.yxx);
  float y = sceneSDF(queryPt + d.xyx) - sceneSDF(queryPt - d.xyx);
  float z = sceneSDF(queryPt + d.xxy) - sceneSDF(queryPt - d.xxy);
  return normalize(vec3(x,y,z));
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Intersection intersection;    
    intersection.distance_t = -1.0;

    Ray r = getRay(uv);
    float dist_t = EPSILON;

    // values to be filled by sceneSDF
    bool terminateRaymarch = false;
    int material_id = 0;

    for (int step = 0; step < MAX_RAY_STEPS; ++step){
      // raymarch
      vec3 queryPt = r.origin + dist_t * r.direction;
      float curDist = sceneSDF(queryPt, material_id, terminateRaymarch);

      // if ray is under terrain, terminate marching
      if (terminateRaymarch){
        return intersection;
      }

      // if we hit something, return intersection
      if (curDist < EPSILON){
        intersection.distance_t = dist_t;
        intersection.position = queryPt;
        intersection.normal = getNormal(queryPt);
        intersection.material_id = material_id;
        return intersection;
      }
      dist_t += curDist;
    }
    return intersection;
}

vec4 getMaterial(vec3 n, int material_id, float zDepth, vec3 isectPt){
  vec3 lightVec = skyLightPos - isectPt;
  float lengthToSkyLight = length(lightVec);
  float diffuseTerm = 0.02;
  float falloffDist = 5.0;

  if (lengthToSkyLight < skyLightRadius + falloffDist){
    diffuseTerm = dot(normalize(lightVec), n);
    if (lengthToSkyLight > skyLightRadius){
      diffuseTerm = mix(diffuseTerm, 0.02, (lengthToSkyLight - skyLightRadius) / falloffDist);
    }
  }
  vec4 ambientTerm = vec4(0.03, 0.07, 0.09, 0.0);
  vec3 materialCol = vec3(1.0);

  if (material_id == GROUND_MAT_ID){
    materialCol = vec3(0.5, 0.9, 0.6);
  }
  if (material_id == TREE_MAT_ID){
    materialCol = vec3(161.0, 126.0, 104.0) / 255.0;
  }
  if (material_id == PATH_MAT_ID){
    materialCol = vec3(207.0, 183.0, 153.0) / 255.0;
  }
  if (material_id == TEMPLE_MAT_ID){
    materialCol = vec3(0.0);
  }

  // simulate what it will look like with low lighting at first
  float guideLightRadius = 1.5;
  float distToGuideLight = length(isectPt - guideLightPos);
  float guideLightT = easeOutQuad(distToGuideLight / guideLightRadius);
  vec3 guideLightFactor = distToGuideLight < guideLightRadius ? 
                          mix(guideLightColor, vec3(0.0), guideLightT) : vec3(0.0);

  //diffuseTerm += distToGuideLight < guideLightRadius ? mix(guideLightT, 0.0, guideLightT) : 0.0;
  vec4 lambert_color = vec4(materialCol * diffuseTerm + 2.0*guideLightFactor, 1.0) + ambientTerm;

  float fogStart = 7.0;
  float fogEnd = -15.0;
  float fogAlphaEnd = -55.0;

  // apply distance fog
  if (zDepth < fogEnd && zDepth > fogAlphaEnd){
    return mix(fogColor, skyColor, abs(zDepth - fogEnd) / abs(fogAlphaEnd - fogEnd));
  }
  if (zDepth < fogAlphaEnd){
    return skyColor;
  }
  if (zDepth < fogStart){
    vec4 blue_lambert = vec4(fogColor.rgb * diffuseTerm + 2.0*guideLightFactor, 1.0) + ambientTerm;
    return mix(lambert_color, fogColor, easeOutQuad(abs(zDepth - fogStart) / abs(fogStart - fogEnd)));
  }
  
  return lambert_color;
}

vec4 getSceneColor(vec2 uv){
  Intersection intersection = getRaymarchedIntersection(uv);
  if (intersection.distance_t > 0.0)
  { 
      return getMaterial(intersection.normal, intersection.material_id, intersection.position.z, intersection.position);
      return vec4(intersection.normal, 1.0);
  }
  return skyColor;
}

void main() {
  // get ndcs
  vec2 uv = fs_Pos.xy;

  // get the scene color
  vec4 col = getSceneColor(uv);
  Ray r = getRay(uv);
  
  bool isRain = getRainColor(uv);
  //bool isRain = false;
  if (isRain){
      out_Col = mix(col, vec4(1.0), 0.20);
  }
  else{
    out_Col = col;
  }
  
  //out_Col = vec4(0.5 * (r.direction + vec3(1.0, 1.0, 1.0)), 1.0);
}
