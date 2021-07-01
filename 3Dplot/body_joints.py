# This is a sample Python script.

# Press Shift+F10 to execute it or replace it with your code.
# Press Double Shift to search everywhere for classes, files, tool windows, actions, and settings.

import open3d as o3d
import numpy as np
import json
import tkinter.filedialog
from os import listdir
from os.path import isfile, join
import time


def my_func(name):
    number = name.split(".")[0].split("_")[-1]
    return int(number)


def print_hi(name):
    vis = o3d.visualization.Visualizer()

    # Use a breakpoint in the code line below to debug your script.
    print(f'Hi, {name}')  # Press Ctrl+F8 to toggle the breakpoint.
    dir = tkinter.filedialog.askdirectory()
    files = [f for f in listdir(dir) if isfile(join(dir, f)) and ".json" in f]
    # Give all files same number of characters to enable sorting
    files.sort()
    pose_list = []
    i = 0
    for file in files:
        with open(join(dir, file)) as bf:
            body = json.load( bf )
        with open("joints.json") as jf:
            joints = json.load( jf)
        with open("body.json") as jf:
            body_layout = json.load( jf)

        points = []
        point_name = []
        for point in joints["joints"]:
            points.append(body[point])
            point_name.append(point)
        #print(point_name)
        lines = []
        for line_joints in body_layout["body"]:
            lines.append((point_name.index(line_joints[0]), point_name.index(line_joints[1])))
        #print(lines)


        #print("Let\'s draw a cubic using LineSet")
        colors = [[1, 0, 0] for i in range(len(lines))]
        line_set = o3d.geometry.LineSet()
        line_set.points = o3d.utility.Vector3dVector(points)
        line_set.lines = o3d.utility.Vector2iVector(lines)
        line_set.colors = o3d.utility.Vector3dVector(colors)
        #print("Start drawing")
        #o3d.visualization.draw_geometries([line_set])
        pose_list.append(line_set)
        lookat = np
        if i % 10 == 0:
            o3d.visualization.draw_geometries([line_set], zoom=0.34, lookat=[2.0, 2.0, 1.5], up=[-0.07, -0.98, 0.202], front=[0.43, -0.21, -0.88])
        i += 1
    print("Final anmation")
    #o3d.visualization.draw_geometries_with_custom_animation(pose_list)


# Press the green button in the gutter to run the script.
if __name__ == '__main__':
    print_hi('PyCharm')

# See PyCharm help at https://www.jetbrains.com/help/pycharm/
