# Ruth Chung

## Pennkey: 33615194

## link to scene
[https://ruthchu.github.io/hw02-raymarching-sdfs/](https://ruthchu.github.io/hw02-raymarching-sdfs/)

![](images/kirbyrender.png)

gif to see the animation (gif is not slowed down, my project is just very slow)
![](images/kirby.gif)

## techniques used
kirby + star
- made of 5 ellipsoid sdfs (body, 2 arms, 2 eyes) and two round cone sdfs (feet)
- used the concept of a scene graph to make sure the entire kirby + star sdf can be moved and rotated as one unit
- star is made of 5 rhombii rotated around a center point, and smoothblended with an ellipse to create the bulge in the center
- kirby is animated to bob up and down using a sin function, which is then modified by gain and bias to give more "elasticity" to the bounce
- arms are also animated in this way
- feet are fixed to ground
- entire sdf moves randomly

## useful external resources
- referenced the heck out of this page:
[https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm](https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm)