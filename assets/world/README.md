# World textures

Generated (ours, no licence). Upload as Images and put the IDs in
`Source/ReplicatedFirst/views/SkinAssets.luau`.

The Grid (`6372755229`, Roblox's baseplate grid) and Studs (`10455712361`)
patterns use existing Roblox images, so they have no source file here.

| File | Used for | SkinAssets field |
|---|---|---|
| clouds.png | Floor pattern "Clouds" (seamless fractal Perlin noise, white on alpha; `python tools/build_clouds.py`). Uploaded as `113580888960089` | `floorTextures.Clouds` |
| grass.png | Floor pattern "Grass" (seamless, white on alpha; 512 px from a 1024 source). Uploaded as `100227557484882` | `floorTextures.Grass` |
| water.png | Floor pattern "Water" (seamless, white on alpha; 512 px from a 1024 source). Uploaded as `98759281326939` | `floorTextures.Water` |
| checker.png | Floor pattern "Checker" (white 2×2 checker, tinted by the pattern colour in-game). Uploaded as `92292194903425` | `floorTextures.Checker` |
| sky_studio.png | Sky preset "Studio" — flat light grey on all six skybox faces | `skyTextures.Studio` |
| sky_void.png | Sky preset "Void" — flat near-black on all six skybox faces | `skyTextures.Void` |
