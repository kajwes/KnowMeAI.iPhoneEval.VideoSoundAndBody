import json
import matplotlib.pyplot as plt
from PIL import Image, ImageDraw
import numpy as np

def drawLine(draw, sz, x, y, x2, y2):
    draw.line((sz[0] / 2 + sz[0] / 2 * x, sz[1] / 2 + sz[1] / 2* y, sz[0] / 2 + sz[0] / 2 * x2 , sz[1] / 2 + sz[1] / 2* y2), fill=128)
img = Image.open("/Users/vidarsolli/Desktop/BodyTrackingData/CameraImage_18601.png").convert("RGBA")
path = "/Users/vidarsolli/Desktop/BodyTrackingData/BodyTracking_18601.json"
sz = img.size
TINT_COLOR = (0, 0, 0)  # Black
TRANSPARENCY = .25  # Degree of transparency, 0-100%
OPACITY = int(255 * TRANSPARENCY)
with open(path, encoding="utf8", errors='ignore') as f:
    body = json.load(f)
    coords = np.zeros((body.__len__(), 3))
    i = 0
    for part in body:
        coords[i, 0] = body[part][0]
        coords[i, 1] = body[part][1]
        coords[i, 2] = body[part][2]
        i += 1
    # Creating figure
    fig = plt.figure(figsize=(10, 7))
    ax = plt.axes(projection="3d")

    # Creating plot
    ax.scatter3D(coords[:,0], coords[:,1], coords[:,2], color="green")
    plt.title("simple 3D scatter plot")

    # show plot
    #plt.show()
    #draw = ImageDraw.Draw(img)
    #drawLine(draw, sz, body["hips_joint"][0], body["hips_joint"][1], body["neck_1_joint"][0], body["neck_1_joint"][1])
    #drawLine(draw, sz, body["left_shoulder_1_joint"][0], body["left_shoulder_1_joint"][1], body["right_shoulder_1_joint"][0], body["right_shoulder_1_joint"][1])
    #drawLine(draw, sz, body["left_shoulder_1_joint"][0], body["left_shoulder_1_joint"][1], body["left_arm_joint"][0], body["left_arm_joint"][1])
    #drawLine(draw, sz, body["right_shoulder_1_joint"][0], body["right_shoulder_1_joint"][1], body["right_arm_joint"][0], body["right_arm_joint"][1])
    #drawLine(draw, sz, body["left_forearm_joint"][0], body["left_forearm_joint"][1], body["left_arm_joint"][0], body["left_arm_joint"][1])
    #drawLine(draw, sz, body["right_forearm_joint"][0], body["right_forearm_joint"][1], body["right_arm_joint"][0], body["right_arm_joint"][1])
    #drawLine(draw, sz, body["left_forearm_joint"][0], body["left_forearm_joint"][1], body["left_hand_joint"][0], body["left_hand_joint"][1])
    #drawLine(draw, sz, body["right_forearm_joint"][0], body["right_forearm_joint"][1], body["right_hand_joint"][0], body["right_hand_joint"][1])
    #x = sz[0] / 2 + sz[0] * body["left_shoulder_1_joint"][0]
    #y = sz[1] / 2 + sz[1] * body["left_shoulder_1_joint"][1]
    #x = sz[0] / 2 + sz[0] * body["right_shoulder_1_joint"][0]
    #y = sz[1] / 2 + sz[1] * body["right_shoulder_1_joint"][1]
    #img.show()
    # Alpha composite these two images together to obtain the desired result.
