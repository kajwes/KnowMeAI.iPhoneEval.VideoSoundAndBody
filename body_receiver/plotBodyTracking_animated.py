import numpy as np
import matplotlib.pyplot as plt
import mpl_toolkits.mplot3d.axes3d as p3
import matplotlib.animation as animation
import json
import os
import glob
# Set up formatting for the movie files
Writer = animation.writers['ffmpeg']
writer = Writer(fps=15, metadata=dict(artist='Me'), bitrate=1800)

folder = "./body_data/stationary_cam"
files = sorted(glob.glob(os.path.join(folder, "*.json")))

def getLinesFromJson(filepath, transform_to_world = False):
    with open(filepath) as f:
        body = json.load(f)
        hip_world_position = body["hip_world_position"]
        N = len(body["bodyData"])
        lines=np.zeros((N, 3, 2))

        i = 0
        for joint in body["bodyData"]:
            translation = body["bodyData"][joint]["translation"]
            translation_parent = body["bodyData"][joint]["parent_translation"]
            # ToDo: check if joint is tracked or not (from json). Color differently
            xyz_joint = [[translation[0], translation[1], translation[2]]]
            xyz_parent = [[translation_parent[0], translation_parent[1], translation_parent[2]]]
            if transform_to_world:
                rot_matrix = np.array(hip_world_position)[0:3, 0:3] # First 3x3 are joint rotation
                translation = np.array(hip_world_position)[3, 0:3] # First 3 columns in row 4 corresponds to x, y, z translation

                # Perform the local body to world transformation (rotation + translation)
                xyz_joint =  np.subtract(np.matmul(-rot_matrix, np.array(xyz_joint).T), translation[:,np.newaxis])
                xyz_parent =  np.subtract(np.matmul(-rot_matrix, np.array(xyz_parent).T), translation[:,np.newaxis])

            # Build up a 3D matrix of all skeleton 2-point lines. ToDo: Add slices instead of one-by-one
            lines[i, 0, 0] = xyz_joint[0]
            lines[i, 0, 1] = xyz_parent[0]

            lines[i, 1, 0] = xyz_joint[1]
            lines[i, 1, 1] = xyz_parent[1]

            lines[i, 2, 0] = xyz_joint[2]
            lines[i, 2, 1] = xyz_parent[2]
            i += 1
        return lines

def update_lines(num, lines, files):
    data2 = getLinesFromJson(files[num], True)
    for line, data in zip(lines, data2):
        # NOTE: there is no .set_data() for 3 dim data...
        line.set_data(data[0:2, :])
        line.set_3d_properties(data[2, :])
    return lines

# Attaching 3D axis to the figure
fig = plt.figure()
ax = p3.Axes3D(fig)#, auto_add_to_figure=False)

data = getLinesFromJson(files[0], True)
# NOTE: Can't pass empty arrays into 3d version of plot()
lines = [ax.plot(dat[0, 0:1], dat[1, 0:1], dat[2, 0:1])[0] for dat in data]

# Setting the axes properties
ax.set_xlim3d([-2, 2.0])
ax.set_xlabel('X')

ax.set_ylim3d([1.0, 5.0])
ax.set_ylabel('Y')

ax.set_zlim3d([-2.0, 2.0])
ax.set_zlabel('Z')

ax.set_title('3D Test')
ax.view_init(-270, 90)
# Creating the Animation object
line_ani = animation.FuncAnimation(fig, update_lines, len(files), fargs=(lines, files),
                                   interval=50, blit=False)
# Uncomment the below line to save animation as an mp4 video
#line_ani.save('bodyTracking_raw.mp4', writer=writer)
plt.show()