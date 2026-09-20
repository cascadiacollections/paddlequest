"""Generate the paddle mesh. Run headless:

    blender --background --python tools/make_paddle.py

Axis mapping matters here. Blender is Z-up; glTF (and so Godot) is Y-up, and
the exporter maps Blender (X, Y, Z) to glTF (X, Z, -Y). The game needs the
blade's face normal along Godot's Z and the handle running out along Godot +Z
towards the hand, so in Blender the blade is thin along Y and the handle
extends along -Y.
"""

import bpy
import math
import os

BLADE_HALF_W = 0.17       # Godot X
BLADE_HALF_H = 0.19       # Godot Y
BLADE_THICK = 0.028       # Godot Z
HANDLE_RADIUS = 0.021
HANDLE_LEN = 0.14
OUT = os.path.join(os.path.dirname(os.path.dirname(__file__)), "assets", "paddle.glb")


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            block.remove(item)


def material(name, rgba, roughness, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def build_blade(mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=1.0, depth=BLADE_THICK)
    blade = bpy.context.active_object
    blade.name = "Blade"
    # Lay the disc face-on: its axis becomes Y, its circle spans XZ.
    blade.rotation_euler[0] = math.radians(90)
    bpy.ops.object.transform_apply(rotation=True)
    blade.scale = (BLADE_HALF_W, 1.0, BLADE_HALF_H)
    bpy.ops.object.transform_apply(scale=True)

    bevel = blade.modifiers.new("Bevel", "BEVEL")
    bevel.width = 0.006
    bevel.segments = 3
    bevel.limit_method = "ANGLE"
    bpy.ops.object.modifier_apply(modifier=bevel.name)

    bpy.ops.object.shade_smooth()
    blade.data.materials.append(mat)
    return blade


def build_throat(mat):
    """Cone easing the blade into the handle, so the join does not read as two
    parts stuck together."""
    bpy.ops.mesh.primitive_cone_add(
        vertices=24, radius1=0.055, radius2=HANDLE_RADIUS, depth=0.05
    )
    throat = bpy.context.active_object
    throat.name = "Throat"
    throat.rotation_euler[0] = math.radians(-90)
    bpy.ops.object.transform_apply(rotation=True)
    throat.location = (0.0, -(BLADE_THICK / 2 + 0.024), 0.0)
    bpy.ops.object.transform_apply(location=True)
    throat.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return throat


def build_handle(mat):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=20, radius=HANDLE_RADIUS, depth=HANDLE_LEN
    )
    handle = bpy.context.active_object
    handle.name = "Handle"
    handle.rotation_euler[0] = math.radians(90)
    bpy.ops.object.transform_apply(rotation=True)
    handle.location = (0.0, -(BLADE_THICK / 2 + 0.04 + HANDLE_LEN / 2), 0.0)
    bpy.ops.object.transform_apply(location=True)

    bevel = handle.modifiers.new("Bevel", "BEVEL")
    bevel.width = 0.004
    bevel.segments = 2
    bpy.ops.object.modifier_apply(modifier=bevel.name)

    handle.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return handle


def build_butt(mat):
    """Flare at the end of the grip. In the headset this is the cue for where
    your hand is relative to the paddle."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=0.027)
    butt = bpy.context.active_object
    butt.name = "Butt"
    butt.scale = (1.0, 0.55, 1.0)
    butt.location = (0.0, -(BLADE_THICK / 2 + 0.04 + HANDLE_LEN), 0.0)
    bpy.ops.object.transform_apply(location=True, scale=True)
    butt.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return butt


def join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    bpy.context.active_object.name = name
    return bpy.context.active_object


def main():
    clear_scene()

    blade_mat = material("PaddleBlade", (0.72, 0.13, 0.17, 1.0), 0.45)
    grip_mat = material("PaddleGrip", (0.09, 0.09, 0.11, 1.0), 0.8)

    parts = [
        build_blade(blade_mat),
        build_throat(grip_mat),
        build_handle(grip_mat),
        build_butt(grip_mat),
    ]
    paddle = join(parts, "Paddle")

    tris = sum(len(p.vertices) - 2 for p in paddle.data.polygons)
    print(f"PADDLE_TRIS={tris}")
    print(f"PADDLE_VERTS={len(paddle.data.vertices)}")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
    )
    print(f"PADDLE_EXPORTED={OUT}")


main()
