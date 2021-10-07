# CIS 566 Homework 2: Implicit Surfaces
Author: Nathaniel Korzekwa

PennKey: korzekwa

[Live Demo](https://ciscprocess.github.io/hw02-raymarching-sdfs/)

# Overview and Goal
This project currently lays the technical foundation for what I hope to be a 
musically-animated piano, ideally with some somewhat interesting decorations in
the scene.

I have a soft-spot for old-school MIDI-style or other "low-quality" synthetic
music, and my hope is to be able to write a program/shader that can render the
keystrokes that match the music being played. Ideally, this could include procdural
"music" rendered by some sort of noise function, but that may not be realistic.

# Engine
Currently, the raymarching engine closely follows the template given in class:
rays are cast from the eye through voxels in the screen, and points are generated
based on the distance to the closest object along the ray until a collision is
found.

I did add a bounding box around the most complicated part of the scene (the keys),
to limit the amount of rays that needed to compute that part of the SDF, as well
as a somewhat trivial "max distance" ray limiter.

Since I have old hardware and the piano keys add a huge drain, I actually downsampled
the resolution and may need to keep it that way (or add it as a setting perhaps),
since timing will be so critical in this project.

# Status
<p align="center">
  <img src="https://user-images.githubusercontent.com/6472567/136318003-9e562fdd-c56f-467c-92ca-960da331846a.png">
</p>
<p align="center">Current Rendering</p>

Currently the scene is pretty drab. It's not really my best work, but the 
basics are there to be improved upon. The 'D' keys are animated according to 
exponential impulse and cosine over time, and parts of the piano are smoothed
together. I did add basic coloring since the white was painful on my eyes.

I used some smooth union and smooth subtraction operations to make things look
a little nicer than plain min/max operations.

But there are still many details off: No pedals, no bench, no music, the number
of keys is wrong, and I'm sure there are some other piano details that will
throw red flags. I hope to adress these later in the project.