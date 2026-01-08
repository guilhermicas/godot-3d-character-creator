### Orchestrator

Given what was previously defined, blender keeps being the authoritative source of truth, not only on the model export, but also on the animation association and definition.

Godot, like the on the export, should blindly trust what blender dictates.

The orchestrator will decide:
- What animation role to play ("idle","walk","attack", etc...)
- Resolve the best available clip based on context
- Feed parameters into animation tree (in which the user can define the logic like normally)

It's an animation router.

##### Custom animation tree

This animation tree will function just like the usual, except instead of passing onto it the animations themselves, you pass in the roles. This way you abstract the animation, which will be resolved by the orchestrator.

This will have an inspector @export variable, in which you can define "all", "group", "singular":
- all <- the animation tree will apply to all skeletons
- group <- the animation tree will apply to certain skeletons
- singular <- the animation tree will apply to a singular skeleton

It's in the responsibility of the dev to manage these based on the context of the game their making.

If an archnid has animations that aren't part of the other skeletons, we may assume that the gameplay of the arachnid is different and wont trigger those other animations. (this would be the singular option)

If dev chooses all, it should be easier to manage, the only constraint would be that the dev is responsible to create all of the animations for all of the skeletons.

The dev will then program the animation tree as they so please, like usual.
These AnimationTree(s) will live under CCharacter node.

The custom animation tree should show non-blocking warnings in regards to missing animations, so for example if the user defines an "idle", the animation tree will then check with the orchestrator if the selected skeletons of the animation tree all have an idle animation, if 1:n don't, then it should warn "hey, male doesn't have an idle animation set".

To help the dev visualise, when the animation tree is being run on the editor, it will resolve the animations in realtime, the dev must choose what child mesh to use to visualize.
Dev opens animation tree, selects CC_male, then on the graph selects "idle", the animation tree will resolve in runtime and the dev can see what's actually happening.
When actualling running the game, the animation tree will only resolve ONCE uppon character load, or if user selects in a creator scene where definitive base model is false, a different base skeleton model.


# The workflow
Blender:
- Dev defines 1:n base skeletons.
- Makes 1:n child meshes for those skeletons.
- May adjust for a certain child mesh some scale adjustments to the parent skeleton.
- Make animation.
- Assign to that animation a role, and optionally the owner mesh.
- On export, it will export the models and skeletons with animations, and some metadata that specifies the ownership of meshes and animations.

Godot:
- Dev adds a new CCAnimationTree(s) under CCharacter.
- Dev customizes the animation tree(s)
- Dev may choose if the animation tree applies to all skeletons, or only some
  - If only some, dev may add another animation tree for the specificity of the situation
- Dev will only be able to choose roles inside the animation tree that exists on the blender metadata.

Godot internal:
- When instancing the character (\_load_character() on c_character), it'll use the orchestrator to assemble ONCE the animations on the animation tree.
<mark>If a user goes into a creator scene in which it's not defined to hide the definitive base models, when exporting it should re-create the animation tree based on if the base skeleton changed!</mark>

# Hard Rules

These rules are non-negotiable and enforced by tooling where possible.

Skeleton & Rig

- Skeleton topology is immutable:
  - No bone hierarchy changes
  - No bone renaming
  - No bone addition/removal

- Armature origin must be at (0,0,0) with no pre-transform.
- Rest pose is authoritative and shared across all mesh variants.

- Bone scale profiles:
  - Are static per mesh instance
  - Are applied once at character load
  - Are not animated and not blended

- Any anatomical change beyond bone scaling requires a new rig archetype.

Meshes

- Meshes must fully conform to their parent skeleton.
- Mesh shape keys are allowed but must not affect skeleton structure.
- Meshes do not own animations; they may only define override preferences.

Animations

- All animations are authored against a skeleton, not a mesh.
- Every animation must define a semantic role.
- Each role must have exactly one base animation per skeleton.
- Mesh-specific animations are overrides, not replacements.
- Animations must not assume mesh-specific bone scales.

Animation Resolution

- Animation resolution happens once per character load.
- Resolution results are cached and reused at runtime.
- Missing roles or overrides produce warnings, not silent failure.

Animation Trees

- AnimationTrees define logic and blending only.
- AnimationTrees never reference concrete animation names directly.
- Trees operate on resolved animation slots, not roles at runtime.
- Skeleton changes trigger character re-instantiation, not live mutation.

# Non-Goals

These are explicitly out of scope for this system.

- Retargeting animations between different skeleton archetypes.
- Procedural animation, IK solving, or physics-based motion.
- Runtime modification of skeleton topology.
- Keyframed bone scaling or pose-space skeleton deformation.
- Automatic generation of missing animations.
- Supporting partially compatible or “almost matching” rigs.
- Hot-swapping skeletons without character reload.
