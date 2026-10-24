Scatter patches
===============

Drag `solid_scatter.tscn` or `crushable_scatter.tscn` into your level. Both render
their visuals with MultiMesh: one batch per mesh in each chosen source model. They do
not create a separate visual scene for each prop.

- Solid scatter uses box-shaped StaticBody3D colliders and blocks the tank.
- Crushable scatter uses box-shaped Area3D triggers, lets the tank pass through,
  and flattens only the touched instance. The flattened model stays on the ground.

Select a patch and add models to the Source Scenes array. Each placement randomly
chooses one non-empty entry. Every entry is equally likely; repeat a scene in the
array to make it more common without creating extra rendering batches. The seed
reproduces both the placement layout and the model choices. Empty slots are skipped.

Change Instance Count, Area Size, Scatter Seed,
Minimum Spacing, Scale Range, and Maximum Slope. Click Rebuild Scatter to preview
the result, or Clear Scatter to remove it. Moving a patch reprojects its editor
preview. Placement is deterministic and generated again when the game starts;
generated colliders and meshes are not saved into the level scene.

Density Noise controls clustering for either scatter type. It samples seeded
Perlin noise in world X/Z coordinates and caches a 128x128 density map on rebuild.
The read-only Density Preview texture in the Inspector shows the patch's map:
white is dense, gray is sparse, and black leaves empty ground.

- Density Frequency: lower values make larger patches; higher values make smaller clusters.
- Density Seed / Offset: change the pattern or slide it across the terrain.
- Density Octaves: add smaller variations inside the broad patches.
- Density Strength: 1 applies the full noise map; 0 restores uniform scatter.
- Density Threshold: raise it for more empty ground.
- Density Transition: controls how softly sparse regions become dense ones.

Click Rebuild Scatter after changing density settings. Matching density settings
use the same world-space pattern across neighboring patches. Instance Count is
an upper limit; density, terrain, and spacing can reduce the actual count. Sparse
cells keep the same probability roll on retries so holes are not filled back in.
Disable Density Enabled to restore the original uniform distribution. Noise is
sampled during rebuilding, with no extra work during gameplay.

Each source scene should contain visuals at the desired size. `rock_visual.tscn` and
`cactus_visual.tscn` are examples. Models with multiple mesh parts retain those
parts, with each part batched through its own MultiMesh. Colliders use the bounds
of the model chosen for that instance, and crushing changes only that instance
inside its model's batches. Imported mesh materials
and whole-mesh material overrides are preserved.

Set Ground Body Path to the StaticBody3D that owns the terrain collision if the
patch should scatter only on that terrain. The patches in the main scene point
to the level's terrain body. Samples in gaps and on slopes above Maximum Slope
are skipped. Center Clearance leaves an empty circle around the patch origin.
Area Size controls the footprint; move and rotate the patch instead of scaling it.

Vehicles use physics layer 2 and the `scatter_crushers` group. Ground and solid
props use layer 1. Crushable areas scan layer 2 and only flatten for bodies in
that group. Other vehicles can opt in through the same layer and group.

The main scene contains both types as examples. Disable Generate On Start and
clear the preview to keep a patch configured without generating its props.
