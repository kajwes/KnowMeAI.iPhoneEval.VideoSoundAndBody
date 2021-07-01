import threading
import zmq
import numpy as np
import matplotlib.pyplot as plt
from PIL import Image
import cv2
from datetime import datetime



context = zmq.Context()
url = "tcp://192.168.10.207:2021"
threaded_receivers = ["Confidence", "CameraImage", "BodyTracking", "CameraIntrinsics", "CompressedCameraFrame"]#, "SmoothedSceneDepth", "EstimatedDepthData"]
main_thread_topic = "SceneDepth"#, "SmoothedSceneDepth", "EstimatedDepthData"]
print('Waiting for messages...')

def data_receiver( context, url, topic, out_folder = "/home/vidar/projects/knowmeai/DepthStreamer/DepthImages/", showImage = False):
    socket = context.socket(zmq.SUB)
    socket.setsockopt_string(zmq.SUBSCRIBE, topic)
    socket.connect(url)
    plt.ion()
    plt.show()
    imWidth = 256
    imHeight = 192
    dataType = "float"
    image_name = "no_name_received"
    bReceived = False;
    while True:
        #  Wait for next request from client
        try:
            message = socket.recv()
            if topic == "CameraIntrinsics":
                with open(out_folder + "../CameraIntrinsics.txt", 'w') as f:
                    f.write(message.decode())
            elif topic == "CompressedCameraFrame":
                print('CompressedCameraFrame. Size' + str(len(message)))
            else:
                if len(message) < 100:  # Dirty. TODO: Separate topic with image header, including dimensions.
                    message_str = message.decode()
                    if(message_str.find("imWidth = ") == 0):
                        imWidth = int(message_str[len("imWidth = ")::])
                    elif(message_str.find("imHeight = ") == 0):
                        imHeight = int(message_str[len("imHeight = ")::])
                    elif(message_str.find("dataType = ") == 0):
                        dataType = message_str[len("dataType = ")::]
                    elif(message_str.find("Name = ") == 0):
                        image_name = out_folder + message_str[len("Name = ")::]
                        if not bReceived:
                            print('New topic received: ' + image_name)
                            bReceived = True
                else:
                    if topic == "BodyTracking":
                        with open(image_name + "_" + datetime.now().strftime("%Y-%m-%d-%H-%M-%S-%f") + ".json", 'w') as f:
                            f.write(message.decode('utf-8'))
                        continue
                    arr = np.array(message)
                    print(image_name + " bytes: " + str(len(message)))
                    if(dataType == 'YUV420'):
                        y=np.frombuffer(arr, dtype='uint8')
                        with open(image_name + '_' + str(imWidth) + '_' + str(imHeight) + '_YUV420.npy', 'wb') as f:
                            np.save(f, y)
                        img = np.reshape(y[0:int(1.5*imHeight * imWidth)], (int(imHeight*1.5),int(imWidth)))
                        bgr = cv2.cvtColor(img, cv2.COLOR_YUV420p2RGB);#cv2.COLOR_YUV2BGR_I420);
                        cv2.imwrite(image_name + "_cv.png", bgr)

                    else:
                        y=np.frombuffer(arr, dtype=dataType)
                        img = np.reshape(y, (imHeight,imWidth))

                    # Save SceneDepth in float32 numpy format
                    if image_name.find("SceneDepth") >= 0:
                        with open(image_name + '.npy', 'wb') as f:
                            np.save(f, img)
                    if(showImage):
                        plt.imshow(img) # Cannot plot outside main thread...
                        plt.pause(0.001)

                    # Convert float array image to 8 bit png, representing 0-10 meters.
                    if(dataType == "float32"):
                        img_8bit = (np.clip(img,0, 10) * 25.5).astype('uint8')
                        Image.fromarray(img_8bit).save(image_name + '.png')
                    else:
                        Image.fromarray(img).save(image_name + '.png')


        except:
            print(" Exception in thread")
# Start worker threads receiving different topics
for topic in threaded_receivers:
    thread = threading.Thread( target = data_receiver, args = ( context, url, topic ) )
    thread.start()

# Read one of the topics in main thread to be able to plot (matplotlib is not multithreaded)
data_receiver( context, url, main_thread_topic, showImage = True)
