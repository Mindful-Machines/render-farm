# Prefer OptiX, fall back to CUDA (Docker Desktop has no OptiX), never to the CPU.
import bpy
p = bpy.context.preferences
cp = p.addons['cycles'].preferences
for backend in ('OPTIX', 'CUDA'):
    cp.compute_device_type = backend; cp.refresh_devices()
    if any(d.type == backend for d in cp.devices): break
else:
    print("PREFS NONE", [(d.name, d.type) for d in cp.devices])
    raise SystemExit(1)
for d in cp.devices: d.use = d.type == backend
p.use_preferences_save = True
bpy.ops.wm.save_userpref()
print("PREFS", backend, [(d.name, d.type, d.use) for d in cp.devices])
