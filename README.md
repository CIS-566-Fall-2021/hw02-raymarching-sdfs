# CIS 566 Homework 2: Implicit Surfaces

Sharon Dong (pennkey: sharondo)

Live demo: https://sharond106.github.io/hw02-raymarching-sdfs/

![Demo](https://media.giphy.com/media/yEBYLNNHVoXVJyJBNT/giphy.gif)

Reference: 

![Reference](reference.jpg)

## Techniques
I created this scene using ray marched sign distance functions. Here are some more details about the more involved objects:

**Enoki mushrooms** - smooth blend operation of the mushroom cap and stem using finite reptition, 
and 3 varying rows of mushrooms are placed on top of each other

**Noodles** - 2 layers of rounded cylinders with finite repetition, where the x and z positions are offsetted with cosine functions to appear wavy

**Smoke** - warped 3D fbm noise using a smoother step function for interpolation, contained in a sphere, 
and a gain function using the x position to make the smoke near the outside of the sphere fade out

**Bowl** - "onioning" operation from IQ's blog of a capped cone cut in half

I also put "bounding boxes" around complex groups, like the mushrooms and the noodles, to make the ray marching computation more efficient.
Instead of checking if a ray intersects each mushroom or noodle at each step, I encapsulate all the mushrooms inside a box and only start computing the SDF of the mushrooms until the ray enters that box.
## Helpful Links

https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm
https://iquilezles.org/www/articles/warp/warp.htm

