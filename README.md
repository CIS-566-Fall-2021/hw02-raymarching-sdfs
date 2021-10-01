# Tiny Planet

![](NoisyPlanet.png)

## Live Demo
View a live WebGL Demo here!:
https://ndevlin.github.io/hw01-noisy-planet/

## User Info
- Created by Nathan Devlin (ndevlin), based on original code by Adam Mally
- Written in TypeScript and glsl, using WebGL

- A small planet whose God (you!) can modify things at will
  - Modify Tesselations to increase the detail of the planet (but decrease framerate)
  - Use the 3 LightPos controls to change the position of the Sun according to spherical coordinates
  - BPM allows you to match the beating of the planet to a song of your choice!
      Choose a song and find it's Beats Per Minute. Then set the BPM slider accordingly and your planet will bounce along with the music!
  - Altitude Multiplier allows you to ajust the steepness of the mountains
  - Terrain Seed allows you to change the landscape to change the formation of land masses to your liking
  - Ocean Color gives you RGB controls for the color of the ocean
  - Light Color gives you RGB controls for the color of the sun.

  Try it out and have some fun!

## Implementation Details

- The planet is at base an icosphere that has been subdivided 6 times (changeable by user)
- The planet's terrain is created using a 3D Fractal Brownian Noise function and trilinear interpolation
- There are five biomes; four are created according to elevation: Ocean, Sand, Forest and Mountains. The fifth, Arctic Tundra is created according to latitude.
- There are two surface reflection models. Ocean is rendered with a Blinn-Phong specular reflection model, while all other biomes are rendered with Lambertian shading.
- The fragment shader detects the night side of the planet and creates cities, represented by concentrated city lights, which exist only on habitable land (i.e. not on ocean or Arctic Tundra).
- The terrain noise changes over time according to the user's input to the BPM slider. This allows the planet's animation to match music.
  - Milliseconds since epoch is passed into the shader to allow the pulsing of the planet to match the BPM slider regardless of the framerate
- There is a Jupiter-like textured Moon that orbits the planet. The color noise for this planet was created with a modified use of the same FBM algorithm as the terrain.
