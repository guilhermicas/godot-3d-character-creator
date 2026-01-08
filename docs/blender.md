Skeleton should define:
- Bones
  - Hierarchy
  - Names
- Rest Pose (authoritative)
- Coordinate space assumptions (should be 0,0)

So humanoid or arachnid are rig archetypes.

The skeletons will be in the root CCC.

Children of skeletons will be the mesh variants:
- Humanoid rig
  - Male
  - Female
- Arachnid rig
  - Jumping spider
  - Wolf spider

The objective of the system is to allow devs to implement World Of Warcraft like base characters which diverge in the base skeleton significantly, while being scalable.

Now the base humanoid rig for example may be slightly adjusted to fit a female's anatomy better for example.
<mark>When selecting female mesh, you should be able to configure on addon a bone scale profile, in which when selecting the female, the base skeleton will auto assume those variations, without actually changing the base skeleton. On Godot these variations will be applied on runtime.</mark>
Bone scale profiles are STATIC PER MESH INSTANCE, NOT PART OF THE ANIMATION DATA. (this way it scales) Bone scale profiles are applied before animation playback begins (load character)

If the dev has a need for different bone proportions beyond scaling, that's should be a different rig.

### Animation ownership

An animation will be part of a structure:
- role
- mesh owner(s) override
- rig owner (this should already be infered, because it would already be associated with the skeleton i think?)

When animating the character, you make visible the base skeleton of said character, and the mesh you want. Then you make the animation.

You then assign to this animation which role it is, and who is the mesh owner (CC_id of CC_male or CC_female, etc...)

If an animation doesn't have a set mesh owner, it will be a default fallback. (if you define "idle" animation without defining "CC_female" as the owner for example, that idle will apply to all if a more specific one doesn't exist)

##### Exporting of the animations
Blender, or my addon should be configured such that it exports AnimationLibraries, in which the orchestrator will use to lookup.

The skeleton will be it's own folder with "CC_skeleton.glb" inside, and the animation library will be in the glb.
