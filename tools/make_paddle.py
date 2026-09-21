"""Generate the paddle mesh. Run headless:

    blender --background --python tools/make_paddle.py

Axis mapping matters here. Blender is Z-up; glTF (and so Godot) is Y-up, and
the exporter maps Blender (X, Y, Z) to glTF (X, Z, -Y). Everything below is
authored in GODOT coordinates and converted on the way in, because the game
cares about Godot's axes: the blade's face normal must lie along Godot Z, and
the grip must end up behind and below it at Godot +Z / -Y.

The handle joins the blade at its bottom rim and rakes back to the hand. An
earlier version ran the handle into the centre of the blade, which is
geometrically what "face forward" implies and reads unmistakably as a sink
plunger.
"""

import bpy
import math
import mathutils
import os

# All in Godot space, metres, origin at the blade centre.
BLADE_HALF_W = 0.145
BLADE_HALF_H = 0.160
BLADE_THICK = 0.026
NECK_TOP = (0.0, -0.138, 0.002)
NECK_BOTTOM = (0.0, -0.198, 0.052)
GRIP_END = (0.0, -0.245, 0.185)
GRIP_RADIUS = 0.019

OUT = os.path.join(os.path.dirname(os.path.dirname(__file__)), "assets", "paddle.glb")


def to_blender(p):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return mathutils.Vector((p[0], -p[2], p[1]))


def _lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            block.remove(item)


def material(name, rgba, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def cylinder_between(a, b, r1, r2, mat, verts=20):
    """A tapered cylinder spanning two Godot-space points."""
    pa, pb = to_blender(a), to_blender(b)
    delta = pb - pa
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts,
        radius1=r1,
        radius2=r2,
        depth=delta.length,
        location=(pa + pb) / 2.0,
    )
    obj = bpy.context.active_object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def build_blade(mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=44, radius=1.0, depth=BLADE_THICK)
    blade = bpy.context.active_object
    blade.name = "Blade"
    blade.rotation_euler[0] = math.radians(90)
    bpy.ops.object.transform_apply(rotation=True)
    blade.scale = (BLADE_HALF_W, 1.0, BLADE_HALF_H)
    bpy.ops.object.transform_apply(scale=True)

    bevel = blade.modifiers.new("Bevel", "BEVEL")
    bevel.width = 0.005
    bevel.segments = 3
    bevel.limit_method = "ANGLE"
    bpy.ops.object.modifier_apply(modifier=bevel.name)

    bpy.ops.object.shade_smooth()
    blade.data.materials.append(mat)
    return blade


def build_butt(mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=18, ring_count=9, radius=0.024)
    butt = bpy.context.active_object
    butt.name = "Butt"
    butt.location = to_blender(GRIP_END)
    bpy.ops.object.transform_apply(location=True)
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

    blade_mat = material("PaddleBlade", (0.42, 0.045, 0.06, 1.0), 0.42)
    grip_mat = material("PaddleGrip", (0.035, 0.035, 0.045, 1.0), 0.75)

    parts = [
        build_blade(blade_mat),
        # Neck tapers from the blade rim into the grip.
        # The two grip segments deliberately overlap: each is a capped
        # cylinder, and abutting them exactly leaves their caps visible as a
        # step partway down the handle.
        cylinder_between(NECK_TOP, NECK_BOTTOM, 0.031, GRIP_RADIUS, grip_mat),
        cylinder_between(
            _lerp(NECK_TOP, NECK_BOTTOM, 0.75),
            GRIP_END,
            GRIP_RADIUS,
            GRIP_RADIUS * 1.06,
            grip_mat,
        ),
        build_butt(grip_mat),
    ]
    paddle = join(parts, "Paddle")

    tris = sum(len(p.vertices) - 2 for p in paddle.data.polygons)
    print(f"PADDLE_TRIS={tris}")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT, export_format="GLB", export_apply=True, export_yup=True
    )
    print(f"PADDLE_EXPORTED={OUT}")


main()
