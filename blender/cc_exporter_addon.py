# NOTE: Windows has a max path length of 260 chars, if the tree exceeds this, export will fail. (why Windows, why)
bl_info = {
    "name": "3D Character Creator Exporter",
    "author": "Gui",
    "version": (0, 1),
    "blender": (5, 0, 0),
    "location": "Side Panel",
    "description": "Export CC_/CCC_ structured objects into folder tree of GLBs",
    "category": "Import-Export",
}

import bpy
from pathlib import Path
import uuid
from bpy.props import StringProperty, BoolProperty
from bpy.types import Operator, Panel, PropertyGroup

# ---------- Utility functions ----------

def ensure_uuid(obj):
    """Ensure object has a persistent short UUID (8 chars) in CC_id custom property."""
    if not obj.get("CC_id"): obj["CC_id"] = str(uuid.uuid4())[:8]

def selection_context(objs):
    """Context manager for safe selection state management."""
    class SelectionState:
        def __init__(self, target_objs):
            self.objs = target_objs
            self.state = {o: o.select_get() for o in bpy.context.scene.objects}
            self.active = bpy.context.view_layer.objects.active

        def __enter__(self):
            for o in bpy.context.scene.objects: o.select_set(False)
            for o in self.objs: o.select_set(True)
            if self.objs: bpy.context.view_layer.objects.active = self.objs[0]
            return self

        def __exit__(self, *args):
            for o, sel in self.state.items():
                try: o.select_set(sel)
                except: pass
            try: bpy.context.view_layer.objects.active = self.active
            except: pass

    return SelectionState(objs)

def gather_descendants(root, include_root=True):
    """Recursively gather root and non-CC_/CCC_ descendants."""
    result = [root] if include_root else []
    for child in root.children:
        if not (child.name.startswith("CC_") or child.name.startswith("CCC_")):
            result.extend(gather_descendants(child))
    return result

def make_foldername(obj):
    """Generate folder name with format: name_CC_id_shortuid"""
    return f"{obj.name}_CC_id_{obj.get('CC_id', 'unknown')}"

def export_glb(obj, folder):
    """Export object and descendants as GLB (filename is just object name)."""
    objs = gather_descendants(obj)
    if not objs: return None

    folder.mkdir(parents=True, exist_ok=True)
    out_path = folder / f"{obj.name}.glb"

    # Store original visibility states for objects and their data
    # This is necessary because hidden objects are not exported
    # So we temporarily unhide them
    visibility_state = {}

    for o in objs:
        visibility_state[o] = o.hide_get() # Store object visibility
        o.hide_set(False) # Unhide object

    try:
        with selection_context(objs):
            bpy.ops.export_scene.gltf(
                filepath=str(out_path),
                export_format='GLB',
                use_selection=True,
                export_apply=True,
                export_extras=True
            )
        print(f"[CC Exporter] Exported {obj.name} -> {out_path}")
        result = out_path
    except Exception as e:
        print(f"[CC Exporter] Export failed for {obj.name}: {e}")
        result = None
    finally:
        # Restore original visibility states
        for o, previous_hide_state in visibility_state.items(): o.hide_set(previous_hide_state)

    return result

def process_children(parent, folder):
    """Process children: CC_ objects export, CCC_ objects create subfolders."""
    for child in parent.children:
        name = child.name
        if name.startswith("CC_"):
            child_folder = folder / make_foldername(child)
            export_glb(child, child_folder)
            # Process nested CCC_ collections under this CC_
            for sub in child.children:
                if sub.name.startswith("CCC_"):
                    process_children(sub, child_folder / make_foldername(sub))
        elif name.startswith("CCC_"):
            process_children(child, folder / make_foldername(child))

def process_hierarchy(top_objects, export_root):
    """Process top-level objects into folder structure."""
    base = export_root / "root" if len(top_objects) > 1 else export_root
    base.mkdir(parents=True, exist_ok=True)

    for obj in top_objects:
        name = obj.name
        if name.startswith("CC_"):
            comp_folder = base / make_foldername(obj)
            export_glb(obj, comp_folder)
            process_children(obj, comp_folder)
        elif name.startswith("CCC_"):
            process_children(obj, base / make_foldername(obj))
        else:
            print(f"[CC Exporter] Skipping non-CC_/CCC_ top-level: {name}")

# ---------- Blender UI Components ----------

class CCExporterProperties(PropertyGroup):
    export_path: StringProperty(
        name="Export Path",
        description="Path where the CC glb folders will be created",
        default="//cc_export",
        subtype='DIR_PATH'
    )
    add_root_folder: BoolProperty(
        name="Add folder",
        description="Add a root 'character_config' folder under the chosen export path",
        default=True
    )
    delete_and_recreate: BoolProperty(
        name="Delete and recreate",
        description="Delete everything at the destination and recreate before exporting",
        default=True
    )

class CC_OT_export(Operator):
    bl_idname = "cc.export"
    bl_label = "Export"
    bl_description = "Export CC_ components into GLB folders"

    def execute(self, context):
        props = context.scene.cc_exporter_props
        base = Path(bpy.path.abspath(props.export_path))
        target = base / "character_config" if props.add_root_folder else base

        # Safety check and cleanup
        if props.delete_and_recreate:
            if len(str(target.resolve())) <= 3:
                self.report({'ERROR'}, f"Refusing to delete unsafe path: {target}")
                return {'CANCELLED'}
            if target.exists():
                try:
                    from shutil import rmtree
                    rmtree(target)
                except Exception as e:
                    self.report({'ERROR'}, f"Failed to delete destination: {e}")
                    return {'CANCELLED'}

        # Assign UUIDs to CC_/CCC_ objects
        for obj in context.scene.objects:
            if obj.name.startswith(("CC_", "CCC_")):
                ensure_uuid(obj)

        # Process top-level objects
        top_objects = [o for o in context.scene.objects if not o.parent]
        if not top_objects or len(top_objects) > 1 or not top_objects[0].name.startswith("CCC_"):
            self.report({'WARNING'}, "The top level object must be a single CCC_")
            return {'CANCELLED'}

        process_hierarchy(top_objects, target)
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
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'CC Exporter'

    def draw(self, context):
        layout = self.layout
        props = context.scene.cc_exporter_props
        layout.prop(props, "export_path")
        layout.prop(props, "add_root_folder")
        layout.prop(props, "delete_and_recreate")
        row = layout.row()
        row.operator("cc.export", text="Export", icon='EXPORT')
        row.operator("cc.propagate_shape_keys", text="Propagate Shape Keys", icon='SHAPEKEY_DATA')

# ---------- Registration ----------

classes = (CCExporterProperties, CC_OT_export, CC_OT_propagate_shape_keys, CC_PT_exporter_panel)

def register():
    for cls in classes: bpy.utils.register_class(cls)
    bpy.types.Scene.cc_exporter_props = bpy.props.PointerProperty(type=CCExporterProperties)

def unregister():
    for cls in reversed(classes): bpy.utils.unregister_class(cls)
    del bpy.types.Scene.cc_exporter_props

if __name__ == "__main__": register()