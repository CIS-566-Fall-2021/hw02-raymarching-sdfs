# Serena Gandhi (gserena), Raymarching SDFs 
# Link:
https://gserena01.github.io/hw02-raymarching-sdfs/
# Images:
![image](https://user-images.githubusercontent.com/60444726/135357336-64d4801a-70c1-4156-8b89-a4700512aff5.png)

![image](https://user-images.githubusercontent.com/60444726/135357472-5eee50be-b314-4483-a183-6a38e9705ef8.png)

![image](https://user-images.githubusercontent.com/60444726/135357390-3b6d8b3b-7ff7-449a-8e14-d7ec2f718df0.png)


# Overview:
- uses signed distance functions to model a mug, a pair of scissors, and the ground plane
- SDFs are combined using smooth blending and smooth subtraction operations
- features several different colors of materials
- Lambertian shading is applied to all materials
- soft shadows are cast by SDF primitives
- Scissors and objects are animated by moving their local origins according to time modified by Bias and Gain functions, for smoother, non-linear motion.


# External Sources:
- https://github.com/dmnsgn/glsl-rotate for rotation matrices used to rotate primitives
- http://demofox.org/biasgain.html for bias and gain functions used to transition during animation
- https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm for sdf functions to create, smooth blend, and transform primitives
- https://www.iquilezles.org/www/articles/rmshadows/rmshadows.htm for soft shadows
