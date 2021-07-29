import AVFoundation
import HaishinKit
import Photos
import UIKit
import VideoToolbox

// modules for body detection:
import ARKit
import RealityKit
import Combine

import UIKit
import SceneKit
import SceneKit.ModelIO


// Network communication
import Foundation



extension simd_float4x4: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        try self.init(container.decode([SIMD4<Float>].self))
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode([columns.0,columns.1, columns.2, columns.3])
    }
}


final class ExampleRecorderDelegate: DefaultAVRecorderDelegate {
    static let `default` = ExampleRecorderDelegate()

    override func didFinishWriting(_ recorder: AVRecorder) {
        guard let writer: AVAssetWriter = recorder.writer else {
            return
        }
        PHPhotoLibrary.shared().performChanges({() -> Void in
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: writer.outputURL)
        }, completionHandler: { _, error -> Void in
            do {
                try FileManager.default.removeItem(at: writer.outputURL)
            } catch {
                print(error)
            }
        })
    }
}

final class LiveViewController: UIViewController, ARSessionDelegate {
    private static let maxRetryCount: Int = 5

    @IBOutlet private weak var lfView: MTHKView!
    @IBOutlet private weak var currentFPSLabel: UILabel!
    @IBOutlet private weak var publishButton: UIButton!
    @IBOutlet private weak var pauseButton: UIButton!
    @IBOutlet private weak var videoBitrateLabel: UILabel!
    @IBOutlet private weak var videoBitrateSlider: UISlider!
    @IBOutlet private weak var audioBitrateLabel: UILabel!
    @IBOutlet private weak var zoomSlider: UISlider!
    @IBOutlet private weak var audioBitrateSlider: UISlider!
    @IBOutlet private weak var fpsControl: UISegmentedControl!
    @IBOutlet private weak var effectSegmentControl: UISegmentedControl!
    //@IBOutlet private weak var arView: ARView!
    
    // The 3D character to display.
    var character: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [-1.0, 0, 0] // Offset the character by one meter to the left
    let characterAnchor = AnchorEntity()
    
    // ARKit
    //let arSession = ARSession()
    let arView = ARSCNView()
    
    // Video Streaming
    private var rtmpConnection = RTMPConnection()
    private var rtmpStream: RTMPStream!
    private var sharedObject: RTMPSharedObject!
    private var currentEffect: VideoEffect?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var retryCount: Int = 0
    private var publishing: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        rtmpStream = RTMPStream(connection: rtmpConnection)
        if let orientation = DeviceUtil.videoOrientation(by: UIApplication.shared.statusBarOrientation) {
            rtmpStream.orientation = orientation
        }
        rtmpStream.captureSettings = [
            .sessionPreset: AVCaptureSession.Preset.hd1280x720,
            .continuousAutofocus: true,
            .continuousExposure: true
            // .preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode.auto
        ]
        rtmpStream.videoSettings = [
            .width: 720,
            .height: 1280
        ]
        rtmpStream.mixer.recorder.delegate = ExampleRecorderDelegate.shared

        videoBitrateSlider?.value = Float(RTMPStream.defaultVideoBitrate) / 1000
        audioBitrateSlider?.value = Float(RTMPStream.defaultAudioBitrate) / 1000

        NotificationCenter.default.addObserver(self, selector: #selector(on(_:)), name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        logger.info("viewWillAppear")
        super.viewWillAppear(animated)
        rtmpStream.attachAudio(AVCaptureDevice.default(for: .audio)) { error in
            logger.warn(error.description)
        }
        rtmpStream.attachCamera(DeviceUtil.device(withPosition: currentPosition)) { error in
            logger.warn(error.description)
        }
        rtmpStream.addObserver(self, forKeyPath: "currentFPS", options: .new, context: nil)
        lfView?.attachStream(rtmpStream)
    }

    override func viewWillDisappear(_ animated: Bool) {
        logger.info("viewWillDisappear")
        super.viewWillDisappear(animated)
        rtmpStream.removeObserver(self, forKeyPath: "currentFPS")
        rtmpStream.close()
        rtmpStream.dispose()
        
        arView.session.pause()
    }

    @IBAction func rotateCamera(_ sender: UIButton) {
        logger.info("rotateCamera")
        let position: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        rtmpStream.captureSettings[.isVideoMirrored] = position == .front
        rtmpStream.attachCamera(DeviceUtil.device(withPosition: position)) { error in
            logger.warn(error.description)
        }
        currentPosition = position
    }

    @IBAction func toggleTorch(_ sender: UIButton) {
        rtmpStream.torch.toggle()
    }

    @IBAction func on(slider: UISlider) {
        if slider == audioBitrateSlider {
            audioBitrateLabel?.text = "audio \(Int(slider.value))/kbps"
            rtmpStream.audioSettings[.bitrate] = slider.value * 1000
        }
        if slider == videoBitrateSlider {
            videoBitrateLabel?.text = "video \(Int(slider.value))/kbps"
            rtmpStream.videoSettings[.bitrate] = slider.value * 1000
        }
        if slider == zoomSlider {
            rtmpStream.setZoomFactor(CGFloat(slider.value), ramping: true, withRate: 5.0)
        }
    }

    @IBAction func on(pause: UIButton) {
        rtmpStream.paused.toggle()
    }

    @IBAction func on(close: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func on(publish: UIButton) {
        if publish.isSelected {
            UIApplication.shared.isIdleTimerDisabled = false
            rtmpConnection.close()
            rtmpConnection.removeEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
            rtmpConnection.removeEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
            publish.setTitle("●", for: [])
            publishing = false
        } else {
            UIApplication.shared.isIdleTimerDisabled = true
            rtmpConnection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
            rtmpConnection.addEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
            rtmpConnection.connect(Preference.defaultInstance.uri!)
            publish.setTitle("■", for: [])
            publishing = true
        }
        publish.isSelected.toggle()
    }

    @objc
    private func rtmpStatusHandler(_ notification: Notification) {
        let e = Event.from(notification)
        guard let data: ASObject = e.data as? ASObject, let code: String = data["code"] as? String else {
            return
        }
        logger.info(code)
        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            retryCount = 0
            rtmpStream!.publish(Preference.defaultInstance.streamName!)
            // sharedObject!.connect(rtmpConnection)
        case RTMPConnection.Code.connectFailed.rawValue, RTMPConnection.Code.connectClosed.rawValue:
            guard retryCount <= LiveViewController.maxRetryCount else {
                return
            }
            Thread.sleep(forTimeInterval: pow(2.0, Double(retryCount)))
            rtmpConnection.connect(Preference.defaultInstance.uri!)
            retryCount += 1
        default:
            break
        }
    }

    @objc
    private func rtmpErrorHandler(_ notification: Notification) {
        logger.error(notification)
        rtmpConnection.connect(Preference.defaultInstance.uri!)
    }

    func tapScreen(_ gesture: UIGestureRecognizer) {
        if let gestureView = gesture.view, gesture.state == .ended {
            let touchPoint: CGPoint = gesture.location(in: gestureView)
            let pointOfInterest = CGPoint(x: touchPoint.x / gestureView.bounds.size.width, y: touchPoint.y / gestureView.bounds.size.height)
            print("pointOfInterest: \(pointOfInterest)")
            rtmpStream.setPointOfInterest(pointOfInterest, exposure: pointOfInterest)
        }
    }

    @IBAction private func onFPSValueChanged(_ segment: UISegmentedControl) {
        switch segment.selectedSegmentIndex {
        case 0:
            rtmpStream.captureSettings[.fps] = 15.0
        case 1:
            rtmpStream.captureSettings[.fps] = 30.0
        case 2:
            rtmpStream.captureSettings[.fps] = 60.0
        default:
            break
        }
    }

    @IBAction private func onEffectValueChanged(_ segment: UISegmentedControl) {
        if let currentEffect: VideoEffect = currentEffect {
            _ = rtmpStream.unregisterVideoEffect(currentEffect)
        }
        switch segment.selectedSegmentIndex {
        case 1:
            currentEffect = MonochromeEffect()
            _ = rtmpStream.registerVideoEffect(currentEffect!)
        case 2:
            currentEffect = PronamaEffect()
            _ = rtmpStream.registerVideoEffect(currentEffect!)
        default:
            break
        }
    }

    @objc
    private func on(_ notification: Notification) {
        guard let orientation = DeviceUtil.videoOrientation(by: UIApplication.shared.statusBarOrientation) else {
            return
        }
        rtmpStream.orientation = orientation
    }

    @objc
    private func didEnterBackground(_ notification: Notification) {
        // rtmpStream.receiveVideo = false
    }

    @objc
    private func didBecomeActive(_ notification: Notification) {
        // rtmpStream.receiveVideo = true
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if Thread.isMainThread {
            currentFPSLabel?.text = "\(rtmpStream.currentFPS)"
        }
    }
    
    
    // Code from Body tracking sample app below:
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        //arView.session.delegate = self
        
        // If the iOS device doesn't support body tracking, raise a developer error for
        // this unhandled case.
        guard ARBodyTrackingConfiguration.isSupported else {
            fatalError("This feature is only supported on devices with an A12 chip")
        }

        // Run a body tracking configration.
        let configuration = ARBodyTrackingConfiguration()
        //arSession.delegate = self
        arView.session.delegate = self
        //configuration.videoFormat.framesPerSecond = 15
        //arSession.run(configuration)
        arView.preferredFramesPerSecond = 15
        arView.session.run(configuration)
        
        //arView.scene.addAnchor(characterAnchor)
        return
        // Asynchronously load the 3D character.
        var cancellable: AnyCancellable? = nil
        cancellable = Entity.loadBodyTrackedAsync(named: "character/robot").sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Error: Unable to load model: \(error.localizedDescription)")
                }
                cancellable?.cancel()
        }, receiveValue: { (character: Entity) in
            if let character = character as? BodyTrackedEntity {
                // Scale the character to human size
                character.scale = [1.0, 1.0, 1.0]
                self.character = character
                cancellable?.cancel()
            } else {
                print("Error: Unable to load model as BodyTrackedEntity")
            }
        })
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        print("ARSession didUpdate")
        for anchor in anchors {
            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
            //if publishing {
                saveMetadata(frame: session.currentFrame!, time: 0, frameIndex: 0, bodyAnchor: bodyAnchor)
            //}
            // Update the position of the character anchor's position.
            let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
            characterAnchor.position = bodyPosition + characterOffset
            // Also copy over the rotation of the body anchor, because the skeleton's pose
            // in the world is relative to the body anchor's rotation.
            characterAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation
   
            if let character = character, character.parent == nil {
                // Attach the character to its anchor as soon as
                // 1. the body anchor was detected and
                // 2. the character was loaded.
                characterAnchor.addChild(character)
            }
        }
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        print("ARSession failed with error" + error.localizedDescription)
    }
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        if case .normal = camera.trackingState {
            logger.info("Normal camera tracking state detected")
        }
        if case .limited(let reason) = camera.trackingState {
            logger.warn("Limited camera tracking state detected")
        }
        if case .notAvailable = camera.trackingState {
            logger.error("No camera tracking available detected")
        }
    }
    func sessionWasInterrupted(_ session: ARSession) {
        logger.warn("AR Session was interrupted")
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        logger.warn("AR Session interruption ended")
    }
    func to_double_arr(vec : simd_float4)->Array<Float>//[Float; Float; Float; Float]
    {
        //return vec[0] as Float
        return [vec[0] as Float, vec[1] as Float, vec[2] as Float, vec[3] as Float]
    }
    func to_double_arr(vec : simd_float3)->Array<Float>//[Float; Float; Float; Float]
    {
        //return vec[0] as Float
        return [vec[0] as Float, vec[1] as Float, vec[2] as Float]
    }
    func to_2d_arr(matrix: simd_float3x3)->Array<Array<Float>>
    {
        //return vec[0] as Float
        return [to_double_arr(vec: matrix.columns.0), to_double_arr(vec: matrix.columns.1), to_double_arr(vec: matrix.columns.2)]
    }
    func to_2d_arr(matrix: simd_float4x4)->Array<Array<Float>>
    {
        //return vec[0] as Float
        return [to_double_arr(vec: matrix.columns.0), to_double_arr(vec: matrix.columns.1), to_double_arr(vec: matrix.columns.2), to_double_arr(vec: matrix.columns.3)]
    }

    func saveMetadata( frame : ARFrame, time : CFTimeInterval, frameIndex : Int, bodyAnchor: ARBodyAnchor ) {
        if (bodyAnchor.isTracked){
            print("bodyAnchor Is Tracked")
        }
        else{
            print("bodyAnchor Not Tracked")
        }
        var jsonDict : [String: Any] = [:]
        
        // let pose_sk = self.sceneView.pointOfView!.transform
        
        let cam_k = frame.camera.intrinsics
        let proj = frame.camera.projectionMatrix
        let pose_frame = frame.camera.transform
        
        //let tracking = frame.camera.trackingState // how do we turn into string?
        
        jsonDict["frame_index"] = frameIndex

        // Add timestamps
        jsonDict["time"] = time
        let date = Date()
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS"
        let timestamp = format.string(from: date)
        jsonDict["timestamp_readable"] = timestamp

        jsonDict["cameraPoseScenekit"] = 0// todo: pose_sk.rowMajorArray
        jsonDict["cameraPoseARFrame"] = to_2d_arr(matrix: pose_frame)
        jsonDict["camera_intrinsics"] = to_2d_arr(matrix: cam_k)
        jsonDict["camera_projectionMatrix"] = to_2d_arr(matrix: proj)
        
        //jsonDict["isARKitTrackingNormal"] = (tracking == ARCamera.TrackingState.normal)
        
        
        var joints : [String : Any] = [:]
        
        jsonDict["estimatedScaleFactor"] = bodyAnchor.estimatedScaleFactor
        jsonDict["isTracked"] = bodyAnchor.isTracked
        
        let hipWorldPosition = bodyAnchor.transform
        jsonDict["hip_world_position"] = to_2d_arr(matrix: hipWorldPosition)
        // Joints relatove to hip
        let jointTransforms = bodyAnchor.skeleton.jointModelTransforms

        for (i, jointTransform) in jointTransforms.enumerated(){
            let parentIndex = bodyAnchor.skeleton.definition.parentIndices[i]
            let jointName = bodyAnchor.skeleton.definition.jointNames[i]
            guard parentIndex != -1 else{ continue}
            let parentJointTransform = jointTransforms[parentIndex]
            
            var jointCoords : [String : Any] = [:]
            jointCoords["translation"] = to_double_arr(vec : jointTransform.columns.3)
            jointCoords["parent_translation"] = to_double_arr(vec : parentJointTransform.columns.3)
            jointCoords["is_tracked"] = bodyAnchor.skeleton.isJointTracked(i)
            joints[jointName] = jointCoords
        }
        
        jsonDict["bodyData"] = joints

        //var jsonDictTest : [String: Any] = [:]
        //jsonDictTest["bodyData"] = joints
        
        let host_url = Preference.defaultInstance.uri?.replacingOccurrences(of: "rtmp://", with: "http://")
        let host_url2 = host_url?.replacingOccurrences(of: "/live", with: ":5000")
        print(host_url2)
        sendJsonData(urlPath: host_url2!, jsonDict: jsonDict)
    }
    
    func sendJsonData(urlPath : String, jsonDict : [String: Any] ){
        do{
            
            let data = try JSONSerialization.data(withJSONObject: jsonDict, options: .prettyPrinted)
            //let jsonString = String(data: data, encoding: String.Encoding.utf8) // the data will be converted to the string
            //print(jsonString, terminator:"")// <-- here is ur string

            //let urlPath: String = "YOUR URL HERE"
            let url: NSURL = NSURL(string: urlPath)!
            let request1: NSMutableURLRequest = NSMutableURLRequest(url: url as URL)

            request1.httpMethod = "POST"
                //let stringPost="deviceToken=123456" // Key and Value

            //let data = payload.data(using: <#String.Encoding#>)//, usingEncoding: String.Encoding.utf8)

            request1.timeoutInterval = 60
            request1.httpBody=data
            request1.httpShouldHandleCookies=false

            let queue:OperationQueue = OperationQueue()

            NSURLConnection.sendAsynchronousRequest(request1 as URLRequest, queue: queue, completionHandler:{ (response: URLResponse?, data: Data?, error: Error?) -> Void in

                    do {
                        print("response from http server")
                        //if let jsonResult = try JSONSerialization.jsonObject(with: data!, options: []) as? NSDictionary {
                        //    print("ASynchronous\(jsonResult)")
                        //}
                    } catch let error as NSError {
                        print(error.localizedDescription)
                    }


                })
 
        } catch let error as NSError {
            print(error.localizedDescription)
        }

    }
    // TODO: error handle
    func saveJsonFile( fileUrl : URL , jsonDict : [String : Any] ) {
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted] )
        {
            try! jsonData.write(to: fileUrl )
        } else {
            print("err saving")
        }

        
    }

}
