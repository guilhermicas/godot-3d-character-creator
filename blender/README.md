# Blender Example Model and Blender Export Add-On Explanation

## Example Model

This folder contains an example [male model](https://www.blender.org/download/demo-files/).

The purpose of the example is to show how simple it is to structure your own made character for use in Godot's side.

- CCC_genders
    - CC_male
        - CCC_shirts
            - CC_t_shirt
    - CC_female

Individual objects to be selected in Godot's side have the prefix CC_ (Character Creator). \
Collections of objects to be selected in Godot's side have the prefix CCC_ (Character Creator Collection). \
That's all the prefixes you have to memorize to structure your character costumization. \

This is all in favor of being able to create and test your character with all of the clothing in one scene, \
and exporting it such that it's optimized for use with our plugin on Godot's side. \

## Blender Export Add-On

Based on your character's structure, the blender add-on will walk down the tree of objects, and export them individually. \
This is for optimization purposes, to only load the needed models. \
Once exported, each model will have associated with it a CC_id (Character Creator Id), \
which is a uuid4 with the purpose of knowing which object is which, even if you save and close blender, \
or move the object around inside blender. \
Godot will understand what object is which even if changed in blender. \

To view this UUID, which we do NOT recommend you change it, you can go to: \
"Object Properties" > "Custom Properties" \
And you should see the CC_id. \

### Add-on usage

Select the export path, this will contain the object and it's components broken down. \
We recommend the .blend file being outside of Godot, so Godot doesn't re-import it everytime, \
and the export to in it's own folder, maybe in a "lib"||"assets"||"utils" folder. \
The Delete and Recreate option simply deletes the whole export folder and re-creates every export inside from scratch, \
this is to avoid stale files, we recommend keeping it on. \
The contents of the folder are NOT to be changed, unless you understand what it's doing. \

##### TODO: add pictures and make this better
