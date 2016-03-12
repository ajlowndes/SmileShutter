# SmileShutter
a comparison of detecting smiles using CIDetector, OpenFrameWorks or OpenCV

You'll notice an annoying "ttzzcchh" sound that plays when a smile reaches the threshold you set. That sound, if played through an IR LED instead of headphones, will trigger any Sony DSLR or Mirrorless camera to take a picture. It's just like  using one of the sony remotes you find on ebay. That's kind of why I started writing this program - to trigger my sony A6000 to take a picture when a smile is detected via the webcam.

Yes I know that the A6000 has this feature already - but it doesn't work with tethering, which is actually all-important for me. I wanted a system that would detect smiles AND have the images saved to the computer hard drive immediately (for Lightroom to play with and export on the fly) rather than onto an SD card where I'd have to import them later. That's the whole point of this program and why I wrote it. I'm taking the long way around, re-inventing Sony's smile-detecting wheel just to satisfy my own pedanticism!

As for the programming side:
This is currently not a wonderfully written program, I'll be the first to admit that. That's because I barely know what I am doing, I'm basically learning as I go. I started with an example I found called AVRecorder, somehow renamed it as "SmileShutter", then added libraries, files and functions until I managed to get it to work the way I want. At least on my macbook it does.

If you download this and it doesn't compile and run - here are some possible gotcha's:
- the OpenCV libraries are static .a files on my machine. I can't really remember why I did that but there was some reason.
- if it does compile, it does crash after a while on my computer still. I just haven't managed to take the time to debug it to the stage where it doesn't anymore.

If you do manage to use some part of my code, please let me know if you found a way to clean mine up at the same time. I would love that!
