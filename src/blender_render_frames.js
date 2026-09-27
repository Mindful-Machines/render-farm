// SPDX-License-Identifier: GPL-3.0-or-later

// Flamenco v3.9.3 simple_blender_render.js with the preview-video task removed.
// Upstream: https://projects.blender.org/studio/flamenco/src/tag/v3.9.3/internal/manager/job_compilers/scripts/simple_blender_render.js

const JOB_TYPE = {
    label: "Blender Render Frames",
    description: "Render a sequence of frames. No preview video; build it locally once all frames are in.",
    settings: [
        // Settings for artists to determine:
        { key: "frames", type: "string", required: true,
          eval: "f'{C.scene.frame_start}-{C.scene.frame_end}'",
          evalInfo: {
            showLinkButton: true,
            description: "Scene frame range",
          },
          description: "Frame range to render. Examples: '47', '1-30', '3, 5-10, 47-327'" },
        { key: "chunk_size", type: "int32", default: 1, description: "Number of frames to render in one Blender render task",
          visible: "submission" },

        // render_output_root + add_path_components determine the value of render_output_path.
        { key: "render_output_root", type: "string", subtype: "dir_path", required: true, visible: "submission",
          description: "Base directory of where render output is stored. Will have some job-specific parts appended to it"},
        { key: "add_path_components", type: "int32", required: true, default: 0, propargs: {min: 0, max: 32}, visible: "submission",
          description: "Number of path components of the current blend file to use in the render output path"},
        { key: "render_output_path", type: "string", subtype: "file_path", editable: false,
          eval: "str(Path(abspath(settings.render_output_root), last_n_dir_parts(settings.add_path_components), jobname, '{timestamp}', '######'))",
          description: "Final file path of where render output will be saved"},

        // Automatically evaluated settings:
        { key: "blendfile", type: "string", required: true, description: "Path of the Blend file to render", visible: "web" },
        { key: "fps", type: "float", eval: "C.scene.render.fps / C.scene.render.fps_base", visible: "hidden" },
        { key: "format", type: "string", required: true, eval: "C.scene.render.image_settings.file_format", visible: "web" },
        { key: "image_file_extension", type: "string", required: true, eval: "C.scene.render.file_extension", visible: "hidden",
          description: "File extension used when rendering images" },
        { key: "has_previews", type: "bool", required: false, eval: "C.scene.render.image_settings.use_preview", visible: "hidden",
          description: "Whether Blender will render preview images."},
        { key: "scene", type: "string", required: true, eval: "C.scene.name", visible: "web",
          description: "Name of the scene to render."},
    ]
};


// File formats that would cause rendering to video.
// This is not supported by this job type.
const videoFormats = ['FFMPEG', 'AVI_RAW', 'AVI_JPEG'];

// The file extension should be determined by the render settings, not necessarily by the settings
// in the output panel. Rescheduling should not overwrite existing frames.
const py_render_settings = `
import bpy
r = bpy.context.scene.render
r.use_file_extension = True
r.use_overwrite = False
r.use_placeholder = False
`;

function compileJob(job) {
    print("Blender Render job submitted");
    print("job: ", job);

    const settings = job.settings;
    if (videoFormats.indexOf(settings.format) >= 0) {
        throw `This job type only renders images, and not "${settings.format}"`;
    }

    const renderOutput = renderOutputPath(job);

    // Make sure that when the job is investigated later, it shows the
    // actually-used render output:
    settings.render_output_path = renderOutput;

    const renderDir = path.dirname(renderOutput);
    const renderTasks = authorRenderTasks(settings, renderDir, renderOutput);

    for (const rt of renderTasks) {
        job.addTask(rt);
    }
}

// Do field replacement on the render output path.
function renderOutputPath(job) {
    let path = job.settings.render_output_path;
    if (!path) {
        throw "no render_output_path setting!";
    }
    return path.replace(/{([^}]+)}/g, (match, group0) => {
        switch (group0) {
        case "timestamp":
            return formatTimestampLocal(job.created);
        default:
            return match;
        }
    });
}

function authorRenderTasks(settings, renderDir, renderOutput) {
    print("authorRenderTasks(", renderDir, renderOutput, ")");
    let renderTasks = [];
    let chunks = frameChunker(settings.frames, settings.chunk_size);

    let baseArgs = [];
    if (settings.scene) {
      baseArgs = baseArgs.concat(["--scene", settings.scene]);
    }

    for (let chunk of chunks) {
        const task = author.Task(`render-${chunk}`, "blender");
        const command = author.Command("blender-render", {
            exe: "{blender}",
            exeArgs: "{blenderArgs}",
            argsBefore: [],
            blendfile: settings.blendfile,
            args: baseArgs.concat([
                "--python-expr", py_render_settings.trim().split("\n").join("; "),
                "--render-output", path.join(renderDir, path.basename(renderOutput)),
                "--render-format", settings.format,
                "--render-frame", chunk.replaceAll("-", ".."), // Convert to Blender frame range notation.
            ])
        }, frameCount(chunk));
        task.addCommand(command);
        renderTasks.push(task);
    }
    return renderTasks;
}
