import bpy, sys
src, dst = sys.argv[sys.argv.index("--")+1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in list(bpy.data.objects):
    if o.name == "Icosphere":
        bpy.data.objects.remove(o, do_unlink=True)
arm = bpy.data.objects["Zombie"]
acts = {a.name.split("|")[-1]: a for a in bpy.data.actions}
ad = arm.animation_data or arm.animation_data_create()
ad.action = None
for t in list(ad.nla_tracks): ad.nla_tracks.remove(t)
track = ad.nla_tracks.new()
f = 1
# Charge: run cycle x4, then the arms-out grab from the bite clip.
for name, reps, rng in [("ZombieRun", 4, None), ("ZombieBite", 1, (92, 112))]:
    a = acts[name]
    s = track.strips.new(name, int(f), a)
    if rng:
        s.action_frame_start, s.action_frame_end = rng
    s.repeat = reps
    f = s.frame_end
sc = bpy.context.scene
sc.frame_start, sc.frame_end = 1, int(f)
sc.render.fps = 30
print("FRAMES", sc.frame_start, sc.frame_end)
bpy.ops.wm.usd_export(filepath=dst, export_animation=True, export_armatures=True, export_materials=True, selected_objects_only=False)
print("EXPORTED", dst)
