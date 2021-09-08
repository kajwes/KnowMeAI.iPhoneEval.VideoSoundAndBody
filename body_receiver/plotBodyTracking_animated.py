import numpy as np
import math as m
import matplotlib.pyplot as plt
import mpl_toolkits.mplot3d.axes3d as p3
import matplotlib.animation as animation
import json
import os
import glob
# Fixing random state for reproducibility
# Set up formatting for the movie files
Writer = animation.writers['ffmpeg']
writer = Writer(fps=15, metadata=dict(artist='Me'), bitrate=1800)

path = "./body_data/2021-09-06_20_25_44.503.json"
folder = "./body_data/stationary_cam"
#files = sorted(os.listdir(folder))
files = sorted(glob.glob(os.path.join(folder, "*.json")))

def axisEqual3D(ax):
    extents = np.array([getattr(ax, 'get_{}lim'.format(dim))() for dim in 'xyz'])
    sz = extents[:,1] - extents[:,0]
    centers = np.mean(extents, axis=1)
    maxsize = max(abs(sz))
    r = maxsize/2
    for ctr, dim in zip(centers, 'xyz'):
        getattr(ax, 'set_{}lim'.format(dim))(ctr - 2*r, ctr + 2*r)

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
            xyz_joint = [[translation[0], translation[1], translation[2]]]
            xyz_parent = [[translation_parent[0], translation_parent[1], translation_parent[2]]]
            if transform_to_world:
                rot_matrix = np.array(hip_world_position)[0:3, 0:3] # First 3x3 are joint rotation
                translation = np.array(hip_world_position)[3, 0:3] # First 3 columns in row 4 corresponds to x, y, z translation

                xyz_joint =  np.matmul(-rot_matrix, np.array(xyz_joint).T)  # Multiply rotation matrix with vertical 3D vector of joint
                xyz_parent =  np.matmul(-rot_matrix, np.array(xyz_parent).T)

            lines[i, 0, 0] = xyz_joint[0] - translation[0]
            lines[i, 0, 1] = xyz_parent[0] - translation[0]

            lines[i, 1, 0] = xyz_joint[1] - translation[1]
            lines[i, 1, 1] = xyz_parent[1] - translation[1]

            lines[i, 2, 0] = xyz_joint[2] - translation[2]
            lines[i, 2, 1] = xyz_parent[2] - translation[2]
            i += 1
        return lines

def Gen_RandLine(length, dims=2):
    """
    Create a line using a random walk algorithm

    length is the number of points for the line.
    dims is the number of dimensions the line has.
    """
    lineData = np.empty((dims, length))
    lineData[:, 0] = np.random.rand(dims)
    for index in range(1, length):
        # scaling the random numbers by 0.1 so
        # movement is small compared to position.
        # subtraction by 0.5 is to change the range to [-0.5, 0.5]
        # to allow a line to move backwards.
        step = ((np.random.rand(dims) - 0.5) * 0.1)
        lineData[:, index] = lineData[:, index - 1] + step

    return lineData


def update_lines(num, lines, files):
    data2 = getLinesFromJson(files[num], True)
    for line, data in zip(lines, data2):
        # NOTE: there is no .set_data() for 3 dim data...
        line.set_data(data[0:2, :])
        line.set_3d_properties(data[2, :])
        #line.set_data(data[0:2, :num])
        #line.set_3d_properties(data[2, :num])
    return lines

# Attaching 3D axis to the figure
fig = plt.figure()
ax = p3.Axes3D(fig)#, auto_add_to_figure=False)

# Fifty lines of random 3-D lines
data = [Gen_RandLine(25, 3) for index in range(50)]

data = getLinesFromJson(files[0], True)
# Creating fifty line objects.
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
line_ani.save('bodyTracking_raw.mp4', writer=writer)
plt.show()