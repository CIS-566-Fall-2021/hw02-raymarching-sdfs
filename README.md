# Serena Gandhi (gserena), Raymarching SDFs 
# Link:
https://gserena01.github.io/hw02-raymarching-sdfs/
# Images:

![image](https://user-images.githubusercontent.com/60444726/137232616-f34e94f8-cda8-42d9-be07-123af8428b9e.png)

https://user-images.githubusercontent.com/60444726/137233322-90720e27-26cc-41b0-b562-e14f65ca7399.mp4

Source Image:

![image](https://user-images.githubusercontent.com/60444726/136303143-f7881cd9-7931-42ab-ad39-ae02c3236569.png)




# Overview:
- uses signed distance functions to model a mug, a pair of scissors, and the ground plane
- SDFs are combined using smooth blending and smooth subtraction operations
- features several different colors of materials
- Lambertian shading is applied to all materials
- soft shadows are cast by SDF primitives
- Scissors and objects are animated by moving their local origins according to time modified by Bias and Gain functions, for smoother, non-linear motion.
- Features three different lights: one to cast shadows, one to provide ambient light, and one to serve as a fill light
- Rendering optimized to allow for smoother animation by limiting how long rays can extend during ray-marching and only checking for scene geometry (during ray-marching and shadow-marching) within a bounding box


# External Sources:
- https://github.com/dmnsgn/glsl-rotate for rotation matrices used to rotate primitives
- http://demofox.org/biasgain.html for bias and gain functions used to transition during animation
- https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm for sdf functions to create, smooth blend, and transform primitives
- https://www.iquilezles.org/www/articles/rmshadows/rmshadows.htm for soft shadows


# Prior Version:

![image](https://user-images.githubusercontent.com/60444726/136303288-56a5e5cf-45c0-4c4f-8d5b-71ce14544b6e.png)

https://user-images.githubusercontent.com/60444726/136304635-f42c05d8-0661-4741-a4df-19935e79727d.mp4

# Bloopers:

Pinocchio Scene: Issue caused by allowing the bounding box to cast shadows on the scene

![wooden bug](https://user-images.githubusercontent.com/60444726/137224445-b18101aa-21ef-42b4-81d6-0970a217e678.png)

