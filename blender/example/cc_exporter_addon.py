bl_info = {
    "name": "3D Character Creator Exporter",
    "author": "Gui",
    "version": (0, 1),
    "blender": (5, 0, 0),
    "location": "Scene Properties > 3D Character Creator Exporter", #TODO: put in floating menu instead of scene props
    "description": "Export CC_/CCC_ structured objects into folder tree of GLBs",
    "category": "Import-Export",
}

# TODO: maybe on export it should auto create a "character_config" root folder

import bpy
import os
import uuid # TODO: use this or check if there's any reliable object id from blender we can use

from bpy.props import StringProperty
from bpy.types import Operator, Panel, AddonPreferences, PropertyGroup

# ---------- Utility functions ----------

def ensure_dir(path):
    if not os.path.exists(path):
        os.makedirs(path, exist_ok=True)

def save_selection_state():
    sel = {ob: ob.select_get() for ob in bpy.context.scene.objects}
    active = bpy.context.view_layer.objects.active
    return sel, active

def restore_selection_state(state):
    sel, active = state
    for ob, was_selected in sel.items():
        try:
            ob.select_set(was_selected)
        except Exception:
            pass
    try:
        bpy.context.view_layer.objects.active = active
    except Exception:
        pass

def gather_export_objects(root_obj):
    """
    Return a set/list of objects that should be exported together when exporting `root_obj`.
    Rule: include root_obj and *descendants* except any descendant whose name starts with CC_ or CCC_.
    """
    out = []

    def recurse(obj):
        out.append(obj)
        for child in obj.children:
            name = child.name or ""
            if name.startswith("CC_") or name.startswith("CCC_"):
                # skip including this child in this export (it's a separate component or a collection marker)
                continue
            else:
                recurse(child)

    recurse(root_obj)
    return out

# ---------- Recursive traversal & export logic ----------

def export_cc_object(obj, export_folder, filepath_name=None):
    """
    Export a CC_ object and its non-CC_/non-CCC_ descendants as a single GLB.
    """
    objs_to_export = gather_export_objects(obj)
    if not objs_to_export:
        return None

    # prepare selection
    state = save_selection_state()
    try:
        # deselect all
        for o in bpy.context.scene.objects:
            o.select_set(False)

        # select the objects we export
        for o in objs_to_export:
            o.select_set(True)

        # make one of them active
        bpy.context.view_layer.objects.active = objs_to_export[0]

        # filename:
        name = filepath_name or obj.name
        ensure_dir(export_folder)
        out_path = os.path.join(export_folder, f"{name}.glb")

        # Blender 5 glTF exporter: use_selection=True to export only selected objects
        bpy.ops.export_scene.gltf(
            filepath=out_path,
            export_format='GLB',
            use_selection=True,
            export_apply=True
        )

        print(f"[CC Exporter] Exported {obj.name} -> {out_path}")
        return out_path
    finally:
        restore_selection_state(state)

def process_collection_of_top_level_objects(export_root, top_objects):
    """
    Walk all top-level objects and process them according to your rules.
    This produces a folder tree under export_root.
    """
    # if many top level objects (>1) then wrap in 'root' folder per your request
    if len(top_objects) > 1:
        base_folder = os.path.join(export_root, "root")
    else:
        base_folder = export_root
    ensure_dir(base_folder)

    # For each top-level object: if starts with CC_ handle as component; otherwise skip unless CCC_?
    for top in top_objects:
        name = top.name or ""
        if name.startswith("CC_"):
            # export this component into base_folder
            # create component folder
            comp_folder = os.path.join(base_folder, name)
            ensure_dir(comp_folder)
            export_cc_object(top, comp_folder, filepath_name=name)
            # Also process children for CCC_ subtree under this component
            for child in top.children:
                if child.name.startswith("CCC_"):
                    # create folder for CCC_ child and process its children recursively
                    subfolder_name = child.name
                    subfolder = os.path.join(comp_folder, subfolder_name)
                    ensure_dir(subfolder)
                    process_cc_collection_recursive(child, subfolder)
                # children starting with CC_ are intentionally ignored here (they are separate components)
        elif name.startswith("CCC_"):
            # a top-level collection marker: make folder and process children
            folder = os.path.join(base_folder, name)
            ensure_dir(folder)
            process_cc_collection_recursive(top, folder)
        else:
            # not CC_/CCC_ top-level: ignore for this exporter
            print(f"[CC Exporter] Skipping top-level object (not CC_/CCC_): {top.name}")

def process_cc_collection_recursive(collection_marker_obj, folder_path):
    """
    Walk children of a CCC_ object. For each child:
      - if child starts with CC_: export it as its own component in the folder
      - if child starts with CCC_: create subfolder and recurse
      - otherwise (non prefixed) these are plain geometry children and are ignored at this step,
        they will be included by their CC_ ancestor export.
    """
    ensure_dir(folder_path)
    for child in collection_marker_obj.children:
        cname = child.name or ""
        if cname.startswith("CC_"):
            comp_folder = os.path.join(folder_path, cname)
            ensure_dir(comp_folder)
            export_cc_object(child, comp_folder, filepath_name=cname)
            # process further nested CCC_ under this CC_ if present
            for sub in child.children:
                if sub.name.startswith("CCC_"):
                    subfolder = os.path.join(comp_folder, sub.name)
                    ensure_dir(subfolder)
                    process_cc_collection_recursive(sub, subfolder)
        elif cname.startswith("CCC_"):
            subfolder = os.path.join(folder_path, cname)
            ensure_dir(subfolder)
            process_cc_collection_recursive(child, subfolder)
        else:
            # non prefixed child - not a separate export here
            # an unprefixed child under a CCC_ might be an error or data; we ignore for top-down exports
            print(f"[CC Exporter] Ignoring non-prefixed child under CCC_: {child.name}")

# ---------- Blender Operators & UI ----------

class CCExporterProperties(PropertyGroup):
    export_path: StringProperty(
        name="Export Path",
        description="Path where the CC glb folders will be created",
        default="//cc_export",
        subtype='DIR_PATH'
    )

class CC_OT_export(Operator):
    bl_idname = "cc.export"
    bl_label = "Export"
    bl_description = "Export CC_ components into GLB folders"

    def execute(self, context):
        props = context.scene.cc_exporter_props
        export_base = bpy.path.abspath(props.export_path)
        ensure_dir(export_base)

        # gather top-level objects (objects with no parent)
        top_objects = [o for o in context.scene.objects if o.parent is None]

        if not top_objects:
            self.report({'WARNING'}, "No top-level objects found in scene.")
            return {'CANCELLED'}

        process_collection_of_top_level_objects(export_base, top_objects)
        self.report({'INFO'}, "CC export complete.")
        return {'FINISHED'}

class CC_OT_propagate_shape_keys(Operator):
    bl_idname = "cc.propagate_shape_keys"
    bl_label = "Propagate Shape Keys"
    bl_description = "Placeholder: propagate shape keys (no-op)"

    def execute(self, context):
        self.report({'INFO'}, "Propagate Shape Keys is a placeholder (no action implemented).")
        return {'FINISHED'}


class CC_PT_exporter_panel(Panel):
    bl_label = "3D Character Creator Exporter"
    bl_idname = "CC_PT_exporter_panel"
    bl_space_type = 'PROPERTIES'
    bl_region_type = 'WINDOW'
    bl_context = "scene"

    def draw(self, context):
        layout = self.layout
        props = context.scene.cc_exporter_props

        layout.prop(props, "export_path")
        row = layout.row()
        row.operator("cc.export", text="Export", icon='EXPORT')
        row.operator("cc.propagate_shape_keys", text="Propagate Shape Keys", icon='SHAPEKEY_DATA')

# ---------- Registration ----------

classes = (
    CCExporterProperties,
    CC_OT_export,
    CC_OT_propagate_shape_keys,
    CC_PT_exporter_panel,
)

def register():
    for cls in classes:
        bpy.utils.register_class(cls)
    bpy.types.Scene.cc_exporter_props = bpy.props.PointerProperty(type=CCExporterProperties)
    print("3D Character Creator Exporter registered")

def unregister():
    for cls in reversed(classes):
        bpy.utils.unregister_class(cls)
    del bpy.types.Scene.cc_exporter_props
    print("3D Character Creator Exporter unregistered")

if __name__ == "__main__":
    register()
