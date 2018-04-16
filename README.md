# gltf2-opengl
glTF2 loader for D using OpenGL

GL Transmission Format (glTF2) for D
glTF2 is a specification by Khronos for transmitting and loading 3D scenes and models for applications. Read more: https://github.com/KhronosGroup/glTF

This is planned to be a complete implementation of the glTF2 specification, with support for all future Khronos extensions.
This repository is the OpenGL loader for glTF2. Maybe you need this, maybe you don't. Although this is intended
for external usage, it's primary goal is as the backend for the glTF2 opengl viewer.

 * [Base glTF2](https://github.com/AODQ/gltf2)
 * [OpenGL Loader](https://github.com/AODQ/gltf2-opengl)
 * [OpenGL Viewer](https://github.com/AODQ/gltf2-opengl-viewer)
 * Vulkan Loader: WIP
 * Vulkan Viewer: WIP

![](https://github.com/AODQ/gltf2/blob/master/media/glTF2-api-spec-0.png?raw=true)

The goal right now is to load & view all glTF2 sample models in OpenGL from
https://github.com/KhronosGroup/glTF-Sample-Models/tree/master/2.0/

The following is a list of working models with an implementation quality from * to *** when compared to their reference screenshot:

    "Triangle Without Indices" ........... **
    "Triangle" ........................... **
    "Box" ................................ **
    "BoxInterleaved" ..................... **
    "Suzanne" ............................ *
    "SciFiHelmet" ........................ *
    
    
![](https://github.com/AODQ/gltf2/blob/master/media/suzeanneworking.gif)
