import bpy
p = bpy.context.preferences
cp = p.addons['cycles'].preferences
cp.compute_device_type = 'OPTIX'; cp.refresh_devices()
for d in cp.devices: d.use = d.type == 'OPTIX'
p.use_preferences_save = True
bpy.ops.wm.save_userpref()
print("PREFS", cp.compute_device_type, [(d.name, d.type, d.use) for d in cp.devices])
