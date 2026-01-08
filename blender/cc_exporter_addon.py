# NOTE: Windows has a max path length of 260 chars, if the tree exceeds this, export will fail. (why Windows, why)
bl_info = {
    "name": "3D Character Creator Exporter",
    "author": "Gui",
    "version": (0, 2),
    "blender": (4, 0, 0),
    "location": "View3D Sidebar > CC Exporter, Dope Sheet Sidebar > CC Animation",
    "description": "Export CC_/CCC_ structured characters with rig adapter for multi-variant support",
    "category": "Import-Export",
}

import bpy
import json
from pathlib import Path
import uuid
from bpy.props import StringProperty, BoolProperty, EnumProperty
from bpy.types import Operator, Panel, PropertyGroup
from mathutils import Vector, Euler

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def ensure_uuid(obj):
    """Ensure object has a persistent short UUID (8 chars) in CC_id custom property."""
    if not obj.get("CC_id"):
        obj["CC_id"] = str(uuid.uuid4())[:8]

def obj_valid(obj):
    """Check if object reference is still valid (not deleted)."""
    if obj is None:
        return False
    try:
        _ = obj.name
        return True
    except ReferenceError:
        return False

def selection_context(objs):
    """Context manager for safe selection state management."""
    class SelectionState:
        def __init__(self, target_objs):
            self.objs = target_objs
            self.state = {o: o.select_get() for o in bpy.context.scene.objects}
            self.active = bpy.context.view_layer.objects.active

        def __enter__(self):
            for o in bpy.context.scene.objects:
                o.select_set(False)
            for o in self.objs:
                o.select_set(True)
            if self.objs:
                bpy.context.view_layer.objects.active = self.objs[0]
            return self

        def __exit__(self, *args):
            for o, sel in self.state.items():
                try:
                    o.select_set(sel)
                except:
                    pass
            try:
                bpy.context.view_layer.objects.active = self.active
            except:
                pass

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

# ============================================================================
# RIG ADAPTER - CORE FUNCTIONS
# ============================================================================

def get_variant_meshes(armature):
    """Get direct CC_ mesh children of armature (these are variants)."""
    if not armature or armature.type != 'ARMATURE':
        return []
    return [c for c in armature.children if c.name.startswith("CC_") and c.type == 'MESH']

def get_variant_name(mesh_obj):
    """Extract variant name from mesh object (e.g., 'CC_male' -> 'male')."""
    if not mesh_obj or not mesh_obj.name.startswith("CC_"):
        return None
    return mesh_obj.name[3:]  # Strip 'CC_' prefix

def is_direct_armature_child(obj):
    """Check if object is a CC_ mesh that's a direct child of an armature."""
    if not obj or not obj.name.startswith("CC_"):
        return False
    if not obj.parent or obj.parent.type != 'ARMATURE':
        return False
    return True

def get_tree_objects(root):
    """Get all objects in tree (root + all descendants recursively)."""
    result = [root]
    for child in root.children:
        result.extend(get_tree_objects(child))
    return result

# ---------- Bone Config Functions ----------

def capture_bone_config(armature):
    """Capture current bone state from armature pose bones."""
    if not armature or armature.type != 'ARMATURE':
        return {}

    config = {}

    for pbone in armature.pose.bones:
        bone_data = {}

        # Location
        loc = pbone.location
        if abs(loc.x) > 0.0001 or abs(loc.y) > 0.0001 or abs(loc.z) > 0.0001:
            bone_data["location"] = [loc.x, loc.y, loc.z]

        # Rotation - handle different rotation modes
        rot_mode = pbone.rotation_mode
        bone_data["rotation_mode"] = rot_mode

        if rot_mode == 'QUATERNION':
            q = pbone.rotation_quaternion
            # Default quaternion is (1, 0, 0, 0)
            if abs(q.w - 1) > 0.0001 or abs(q.x) > 0.0001 or abs(q.y) > 0.0001 or abs(q.z) > 0.0001:
                bone_data["rotation_quaternion"] = [q.w, q.x, q.y, q.z]
        elif rot_mode == 'AXIS_ANGLE':
            aa = pbone.rotation_axis_angle
            if abs(aa[0]) > 0.0001:  # angle
                bone_data["rotation_axis_angle"] = [aa[0], aa[1], aa[2], aa[3]]
        else:  # Euler modes (XYZ, XZY, etc.)
            rot = pbone.rotation_euler
            if abs(rot.x) > 0.0001 or abs(rot.y) > 0.0001 or abs(rot.z) > 0.0001:
                bone_data["rotation_euler"] = [rot.x, rot.y, rot.z]

        # Scale
        scale = pbone.scale
        if abs(scale.x - 1) > 0.0001 or abs(scale.y - 1) > 0.0001 or abs(scale.z - 1) > 0.0001:
            bone_data["scale"] = [scale.x, scale.y, scale.z]

        # Only store if there's actual data (beyond just rotation_mode)
        if len(bone_data) > 1:
            config[pbone.name] = bone_data

    return config

def apply_bone_config(armature, config):
    """Apply bone config to armature."""
    if not armature or armature.type != 'ARMATURE':
        return

    from mathutils import Quaternion

    for pbone in armature.pose.bones:
        if pbone.name in config:
            bone_data = config[pbone.name]

            # Location
            if "location" in bone_data:
                loc = bone_data["location"]
                pbone.location = (loc[0], loc[1], loc[2])
            else:
                pbone.location = (0, 0, 0)

            # Rotation - respect the saved rotation mode
            if "rotation_mode" in bone_data:
                pbone.rotation_mode = bone_data["rotation_mode"]

            if "rotation_quaternion" in bone_data:
                q = bone_data["rotation_quaternion"]
                pbone.rotation_quaternion = Quaternion((q[0], q[1], q[2], q[3]))
            else:
                pbone.rotation_quaternion = Quaternion((1, 0, 0, 0))

            if "rotation_euler" in bone_data:
                rot = bone_data["rotation_euler"]
                pbone.rotation_euler = Euler((rot[0], rot[1], rot[2]))
            else:
                pbone.rotation_euler = Euler((0, 0, 0))

            if "rotation_axis_angle" in bone_data:
                aa = bone_data["rotation_axis_angle"]
                pbone.rotation_axis_angle = (aa[0], aa[1], aa[2], aa[3])
            else:
                pbone.rotation_axis_angle = (0, 0, 1, 0)

            # Scale
            if "scale" in bone_data:
                s = bone_data["scale"]
                pbone.scale = (s[0], s[1], s[2])
            else:
                pbone.scale = (1, 1, 1)
        else:
            # Reset to default
            pbone.location = (0, 0, 0)
            pbone.rotation_quaternion = Quaternion((1, 0, 0, 0))
            pbone.rotation_euler = Euler((0, 0, 0))
            pbone.scale = (1, 1, 1)

def save_variant_config(armature, variant_name):
    """Save current armature state to variant's config slot."""
    if not armature or not variant_name:
        return

    config = capture_bone_config(armature)
    key = f"CC_config_{variant_name}"

    # Store as JSON string (Blender custom props don't handle nested dicts well)
    armature[key] = json.dumps(config)
    print(f"[CC Rig] Saved config for {variant_name}: {len(config)} bones")

def load_variant_config(armature, variant_name):
    """Load variant's config onto armature."""
    if not armature or not variant_name:
        return

    key = f"CC_config_{variant_name}"
    config_json = armature.get(key, "{}")

    try:
        config = json.loads(config_json) if isinstance(config_json, str) else {}
    except:
        config = {}

    apply_bone_config(armature, config)
    print(f"[CC Rig] Loaded config for {variant_name}: {len(config)} bones")

# ---------- Visibility Functions ----------

def save_visibility_state(armature, variant_name, root_mesh):
    """Save visibility state of variant's entire tree."""
    if not armature or not variant_name or not root_mesh:
        return

    tree_objects = get_tree_objects(root_mesh)
    state = {}

    for obj in tree_objects:
        state[obj.name] = not obj.hide_get()  # True = visible

    key = f"CC_visibility_{variant_name}"
    armature[key] = json.dumps(state)

def restore_visibility_state(armature, variant_name, root_mesh):
    """Restore visibility state for variant's tree."""
    if not armature or not variant_name or not root_mesh:
        return

    key = f"CC_visibility_{variant_name}"
    state_json = armature.get(key, "{}")

    try:
        state = json.loads(state_json) if isinstance(state_json, str) else {}
    except:
        state = {}

    tree_objects = get_tree_objects(root_mesh)

    for obj in tree_objects:
        if obj.name in state:
            obj.hide_set(not state[obj.name])  # hide_set(False) = visible
        else:
            # Default: root mesh visible, children follow their current state
            if obj == root_mesh:
                obj.hide_set(False)

def hide_tree(root_obj):
    """Recursively hide object and all descendants."""
    if not root_obj:
        return

    for obj in get_tree_objects(root_obj):
        obj.hide_set(True)

def show_tree(root_obj):
    """Recursively show object and all descendants."""
    if not root_obj:
        return

    for obj in get_tree_objects(root_obj):
        obj.hide_set(False)

# ---------- Variant Switching ----------

# Global state
_active_variant = None  # Currently active variant mesh object
_switching = False  # Prevent recursive switches

def switch_variant(new_variant_obj):
    """Main function: save old state, hide old tree, load new state, show new tree."""
    global _active_variant, _switching

    if _switching:
        return

    if not is_direct_armature_child(new_variant_obj):
        return

    armature = new_variant_obj.parent
    new_variant_name = get_variant_name(new_variant_obj)

    if not armature or not new_variant_name:
        return

    _switching = True

    try:
        # Get lock state
        props = bpy.context.scene.cc_rig_adapter_props
        is_locked = props.lock_variant_config

        # Handle previous variant
        if obj_valid(_active_variant) and _active_variant != new_variant_obj:
            old_variant_name = get_variant_name(_active_variant)
            old_armature = _active_variant.parent

            if old_armature == armature:  # Same rig, different variant
                # Save old variant's state (only if unlocked)
                if not is_locked:
                    save_variant_config(armature, old_variant_name)
                save_visibility_state(armature, old_variant_name, _active_variant)

                # Hide old variant tree
                hide_tree(_active_variant)

        # Activate new variant
        _active_variant = new_variant_obj

        # Load new variant's config
        load_variant_config(armature, new_variant_name)

        # Restore or show new variant tree
        restore_visibility_state(armature, new_variant_name, new_variant_obj)

        print(f"[CC Rig] Switched to variant: {new_variant_obj.name}")

    finally:
        _switching = False

# ============================================================================
# RIG ADAPTER - HANDLERS
# ============================================================================

_last_mode = None

@bpy.app.handlers.persistent
def on_depsgraph_update(scene, depsgraph):
    """Handle selection changes and mode transitions."""
    global _active_variant, _switching, _last_mode

    if _switching:
        return

    try:
        obj = bpy.context.active_object
        mode = bpy.context.mode
    except:
        return

    if not obj:
        return

    # Check for mode change (exiting pose/edit mode on armature)
    if _last_mode != mode:
        old_mode = _last_mode
        _last_mode = mode

        # If we just exited pose mode and have an active variant, save config
        if old_mode in ('POSE', 'EDIT_ARMATURE') and mode == 'OBJECT':
            if obj_valid(_active_variant):
                props = bpy.context.scene.cc_rig_adapter_props
                if not props.lock_variant_config:
                    armature = _active_variant.parent
                    variant_name = get_variant_name(_active_variant)
                    if armature and variant_name:
                        save_variant_config(armature, variant_name)

    # Handle CC_ mesh selection (variant switch)
    if obj.name.startswith("CC_") and is_direct_armature_child(obj):
        if _active_variant != obj:
            switch_variant(obj)

# ============================================================================
# ANIMATION OWNERSHIP SYSTEM
# ============================================================================

def get_action_owner(action):
    """Get the owner variant of an action."""
    if not action:
        return ""
    return action.get("CC_owner", "")

def set_action_owner(action, owner):
    """Set the owner variant of an action."""
    if not action:
        return
    if owner:
        action["CC_owner"] = owner
    elif "CC_owner" in action:
        del action["CC_owner"]

def get_available_variants():
    """Get list of all CC_ variant names in scene for dropdown."""
    variants = set()
    for obj in bpy.context.scene.objects:
        if obj.type == 'ARMATURE' and obj.name.startswith("CC_"):
            for child in obj.children:
                if child.name.startswith("CC_") and child.type == 'MESH':
                    variants.add(child.name)
    return sorted(variants)

# ============================================================================
# EXPORT SYSTEM
# ============================================================================

def export_glb(obj, folder):
    """Export object and descendants as GLB."""
    objs = gather_descendants(obj)
    if not objs:
        return None

    folder.mkdir(parents=True, exist_ok=True)
    out_path = folder / f"{obj.name}.glb"

    # Store original visibility states
    visibility_state = {}
    for o in objs:
        visibility_state[o] = o.hide_get()
        o.hide_set(False)

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
        for o, prev_state in visibility_state.items():
            o.hide_set(prev_state)

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

def process_armature_hierarchy(armature, folder):
    """Process armature with variant meshes as children."""
    armature_folder = folder / make_foldername(armature)
    armature_folder.mkdir(parents=True, exist_ok=True)

    # Export each variant mesh and its descendants
    for child in armature.children:
        if child.name.startswith("CC_"):
            variant_folder = armature_folder / make_foldername(child)
            export_glb(child, variant_folder)
            # Process nested structure under variant
            for sub in child.children:
                if sub.name.startswith("CCC_"):
                    process_children(sub, variant_folder / make_foldername(sub))
                elif sub.name.startswith("CC_"):
                    process_children(child, variant_folder)

def validate_hierarchy(top_obj):
    """Validate the CC hierarchy structure. Returns (valid, error_message)."""
    if not top_obj.name.startswith("CCC_"):
        return False, "Top level must be a CCC_ collection"

    # Check direct children - should be armatures (CC_*_rig) or standard CC_/CCC_
    for child in top_obj.children:
        if child.type == 'ARMATURE' and child.name.startswith("CC_"):
            # Armature children must be CC_ meshes (variants)
            for variant in child.children:
                if variant.name.startswith("CC_") and variant.type != 'MESH':
                    return False, f"Armature child {variant.name} must be a mesh"
        elif not (child.name.startswith("CC_") or child.name.startswith("CCC_")):
            return False, f"Invalid child under top-level: {child.name}"

    return True, ""

def process_hierarchy(top_objects, export_root):
    """Process top-level objects into folder structure."""
    if not top_objects:
        return

    top = top_objects[0]
    base = export_root
    base.mkdir(parents=True, exist_ok=True)

    # Process top-level CCC_
    top_folder = base / make_foldername(top)
    top_folder.mkdir(parents=True, exist_ok=True)

    for child in top.children:
        if child.type == 'ARMATURE' and child.name.startswith("CC_"):
            # New structure: armature with variant children
            process_armature_hierarchy(child, top_folder)
        elif child.name.startswith("CC_"):
            # Old structure: direct CC_ mesh
            child_folder = top_folder / make_foldername(child)
            export_glb(child, child_folder)
            process_children(child, child_folder)
        elif child.name.startswith("CCC_"):
            process_children(child, top_folder / make_foldername(child))

# ============================================================================
# PROPERTY GROUPS
# ============================================================================

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
        description="Delete CC_/CCC_ folders at destination before exporting",
        default=True
    )

class CCRigAdapterProperties(PropertyGroup):
    lock_variant_config: BoolProperty(
        name="Lock Variant Config",
        description="When locked, bone modifications are NOT saved when switching variants (for animation workflow)",
        default=False
    )

# ============================================================================
# OPERATORS
# ============================================================================

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
            if len(str(target.resolve())) <= 10:
                self.report({'ERROR'}, f"Refusing to delete unsafe path: {target}")
                return {'CANCELLED'}
            if target.exists():
                try:
                    from shutil import rmtree
                    for item in target.iterdir():
                        if item.is_dir() and (item.name.startswith("CCC_") or item.name.startswith("CC_")):
                            rmtree(item)
                except Exception as e:
                    self.report({'ERROR'}, f"Failed to delete destination: {e}")
                    return {'CANCELLED'}

        # Assign UUIDs to CC_/CCC_ objects
        for obj in context.scene.objects:
            if obj.name.startswith(("CC_", "CCC_")):
                ensure_uuid(obj)

        # Validate and process
        top_objects = [o for o in context.scene.objects if not o.parent]

        if not top_objects or len(top_objects) > 1:
            self.report({'ERROR'}, "Scene must have exactly one top-level object")
            return {'CANCELLED'}

        valid, error = validate_hierarchy(top_objects[0])
        if not valid:
            self.report({'ERROR'}, error)
            return {'CANCELLED'}

        process_hierarchy(top_objects, target)
        self.report({'INFO'}, "CC export complete.")
        return {'FINISHED'}

class CC_OT_save_variant_config(Operator):
    bl_idname = "cc.save_variant_config"
    bl_label = "Save Current Config"
    bl_description = "Manually save current bone configuration to active variant"

    def execute(self, context):
        global _active_variant

        if not obj_valid(_active_variant):
            self.report({'ERROR'}, "No active variant")
            return {'CANCELLED'}

        armature = _active_variant.parent
        variant_name = get_variant_name(_active_variant)

        if armature and variant_name:
            save_variant_config(armature, variant_name)
            self.report({'INFO'}, f"Saved config for {_active_variant.name}")

        return {'FINISHED'}

class CC_OT_reset_variant_config(Operator):
    bl_idname = "cc.reset_variant_config"
    bl_label = "Reset to Default"
    bl_description = "Reset bones to default pose and clear saved config"

    def execute(self, context):
        global _active_variant

        if not obj_valid(_active_variant):
            self.report({'ERROR'}, "No active variant")
            return {'CANCELLED'}

        armature = _active_variant.parent
        variant_name = get_variant_name(_active_variant)

        if armature and variant_name:
            # Clear config
            key = f"CC_config_{variant_name}"
            if key in armature:
                del armature[key]

            # Reset bones
            apply_bone_config(armature, {})
            self.report({'INFO'}, f"Reset config for {_active_variant.name}")

        return {'FINISHED'}

class CC_OT_set_animation_owner(Operator):
    bl_idname = "cc.set_animation_owner"
    bl_label = "Set Owner"
    bl_description = "Set the owner variant for this action"

    owner: StringProperty(name="Owner", default="")

    def execute(self, context):
        if not context.space_data or context.space_data.type != 'DOPESHEET_EDITOR':
            self.report({'ERROR'}, "Must be in Dope Sheet")
            return {'CANCELLED'}

        action = context.space_data.action
        if not action:
            self.report({'ERROR'}, "No active action")
            return {'CANCELLED'}

        set_action_owner(action, self.owner)
        self.report({'INFO'}, f"Set owner to: {self.owner or 'Default/Shared'}")
        return {'FINISHED'}

class CC_OT_clear_animation_owner(Operator):
    bl_idname = "cc.clear_animation_owner"
    bl_label = "Clear"
    bl_description = "Clear owner (make action shared/default)"

    def execute(self, context):
        if not context.space_data or context.space_data.type != 'DOPESHEET_EDITOR':
            self.report({'ERROR'}, "Must be in Dope Sheet")
            return {'CANCELLED'}

        action = context.space_data.action
        if action:
            set_action_owner(action, "")
            self.report({'INFO'}, "Cleared owner")

        return {'FINISHED'}

# ============================================================================
# UI PANELS
# ============================================================================

class CC_PT_exporter_panel(Panel):
    bl_label = "CC Exporter"
    bl_idname = "CC_PT_exporter_panel"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'CC'

    def draw(self, context):
        layout = self.layout
        props = context.scene.cc_exporter_props

        layout.prop(props, "export_path")
        layout.prop(props, "add_root_folder")
        layout.prop(props, "delete_and_recreate")
        layout.operator("cc.export", text="Export", icon='EXPORT')

class CC_PT_rig_adapter_panel(Panel):
    bl_label = "CC Rig Adapter"
    bl_idname = "CC_PT_rig_adapter_panel"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'CC'

    def draw(self, context):
        layout = self.layout
        props = context.scene.cc_rig_adapter_props

        # Show active armature and variant
        box = layout.box()

        if obj_valid(_active_variant):
            armature = _active_variant.parent
            armature_name = armature.name if armature else "None"

            box.label(text=f"Armature: {armature_name}", icon='ARMATURE_DATA')
            box.label(text=f"Variant: {_active_variant.name}", icon='MESH_DATA')

            # Show available variants
            if armature:
                variants = get_variant_meshes(armature)
                if len(variants) > 1:
                    row = box.row()
                    row.label(text="Variants:")
                    for v in variants:
                        icon = 'RADIOBUT_ON' if v == _active_variant else 'RADIOBUT_OFF'
                        row.label(text=v.name[3:], icon=icon)  # Strip CC_ prefix

            # Show config info
            variant_name = get_variant_name(_active_variant)
            if armature and variant_name:
                key = f"CC_config_{variant_name}"
                config_json = armature.get(key, "{}")
                try:
                    config = json.loads(config_json) if isinstance(config_json, str) else {}
                    box.label(text=f"{len(config)} bones configured")
                except:
                    box.label(text="No config")
        else:
            box.label(text="Select a CC_ variant mesh", icon='INFO')
            box.label(text="(direct child of armature)")

        layout.separator()

        # Lock toggle
        layout.prop(props, "lock_variant_config", icon='LOCKED' if props.lock_variant_config else 'UNLOCKED')

        if props.lock_variant_config:
            layout.label(text="Bone changes won't be saved", icon='INFO')

        # Actions
        col = layout.column(align=True)
        col.operator("cc.save_variant_config", icon='FILE_TICK')
        col.operator("cc.reset_variant_config", icon='LOOP_BACK')

class CC_PT_animation_owner_panel(Panel):
    bl_label = "CC Animation Owner"
    bl_idname = "CC_PT_animation_owner_panel"
    bl_space_type = 'DOPESHEET_EDITOR'
    bl_region_type = 'UI'
    bl_category = 'CC'

    def draw(self, context):
        layout = self.layout

        action = None
        if context.space_data and hasattr(context.space_data, 'action'):
            action = context.space_data.action

        if not action:
            layout.label(text="No active action", icon='INFO')
            return

        box = layout.box()
        box.label(text=f"Action: {action.name}", icon='ACTION')

        current_owner = get_action_owner(action)
        box.label(text=f"Owner: {current_owner or 'Default/Shared'}")

        # Owner selection
        row = layout.row(align=True)

        # Get available variants for dropdown
        variants = get_available_variants()

        if variants:
            for variant in variants[:4]:  # Limit to prevent UI overflow
                op = row.operator("cc.set_animation_owner", text=variant[3:])  # Strip CC_
                op.owner = variant

        row = layout.row(align=True)
        op = row.operator("cc.set_animation_owner", text="Default/Shared")
        op.owner = ""
        row.operator("cc.clear_animation_owner", text="", icon='X')

# ============================================================================
# REGISTRATION
# ============================================================================

classes = (
    CCExporterProperties,
    CCRigAdapterProperties,
    CC_OT_export,
    CC_OT_save_variant_config,
    CC_OT_reset_variant_config,
    CC_OT_set_animation_owner,
    CC_OT_clear_animation_owner,
    CC_PT_exporter_panel,
    CC_PT_rig_adapter_panel,
    CC_PT_animation_owner_panel,
)

def register():
    for cls in classes:
        bpy.utils.register_class(cls)

    bpy.types.Scene.cc_exporter_props = bpy.props.PointerProperty(type=CCExporterProperties)
    bpy.types.Scene.cc_rig_adapter_props = bpy.props.PointerProperty(type=CCRigAdapterProperties)

    # Register handler
    if on_depsgraph_update not in bpy.app.handlers.depsgraph_update_post:
        bpy.app.handlers.depsgraph_update_post.append(on_depsgraph_update)

def unregister():
    # Unregister handler
    if on_depsgraph_update in bpy.app.handlers.depsgraph_update_post:
        bpy.app.handlers.depsgraph_update_post.remove(on_depsgraph_update)

    del bpy.types.Scene.cc_rig_adapter_props
    del bpy.types.Scene.cc_exporter_props

    for cls in reversed(classes):
        bpy.utils.unregister_class(cls)

if __name__ == "__main__":
    register()
