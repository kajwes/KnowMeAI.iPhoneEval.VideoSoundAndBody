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

    @IBOutlet private weak var currentFPSLabel: UILabel!
    @IBOutlet private weak var publishButton: UIButton!
    @IBOutlet private weak var pauseButton: UIButton!
    @IBOutlet private weak var videoBitrateLabel: UILabel!
    @IBOutlet private weak var videoBitrateSlider: UISlider!
    @IBOutlet private weak var audioBitrateLabel: UILabel!
    @IBOutlet private weak var audioBitrateSlider: UISlider!
    @IBOutlet private weak var fpsControl: UISegmentedControl!

    // The 3D character to display.
    var character: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [-1.0, 0, 0] // Offset the character by one meter to the left
    let characterAnchor = AnchorEntity()
    
    // MARK: - ARKit
    let metalDevice: MTLDevice = MTLCreateSystemDefaultDevice()!
    var arMultimediaIO: ARMultimediaIO!
    weak var arView: ARView? {
        return arMultimediaIO.arView
    }
    
    // MARK: - Video Streaming
    private var rtmpConnection = RTMPConnection()
    private var rtmpStream: RTMPStream!
    private var sharedObject: RTMPSharedObject!
    private var currentEffect: VideoEffect?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var retryCount: Int = 0
    private var publishing: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // MARK: - Config the RTMP stream and set ARKit as the audio/video source
        rtmpStream = RTMPStream(connection: rtmpConnection)
        rtmpStream.videoSettings[.profileLevel] = kVTProfileLevel_H264_High_AutoLevel // Important — without High profile, it's impossible to stream 1080p
        
        // MARK: - Config the ARKit video/audio source
        arMultimediaIO = ARMultimediaIO(metalDevice: metalDevice)
        arMultimediaIO.delegate = self
        
        // Enumerate viable ARKit video formats
        let availableVideoFormats = ARBodyTrackingConfiguration.supportedVideoFormats
        for (idx, fmt) in availableVideoFormats.enumerated() {
            print("Video format #\(idx): \(fmt)")
        }
        let selectedVideoFormat = availableVideoFormats[1] //.last! // Usually, the last video format has the lowest resolution (e.g. 1280x720 px)
        
        // Start the camera capture process
        arMultimediaIO.startCameraStream(videoFormat: selectedVideoFormat)
        
        self.onFPSValueChanged(self.fpsControl)
        
        // Place the ARSCNView to the screen
        let arPreview = arMultimediaIO.arView
        let bgView = self.view!
        bgView.addSubview(arPreview)
        arPreview.translatesAutoresizingMaskIntoConstraints = false
        let arPreviewConstraints = [
            NSLayoutConstraint(item: arPreview, attribute: .centerX, relatedBy: .equal, toItem: bgView, attribute: .centerX, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: arPreview, attribute: .centerY, relatedBy: .equal, toItem: bgView, attribute: .centerY, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: arPreview, attribute: .width, relatedBy: .equal, toItem: bgView, attribute: .width, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: arPreview, attribute: .height, relatedBy: .equal, toItem: bgView, attribute: .height, multiplier: 1, constant: 0),
        ]
        NSLayoutConstraint.activate(arPreviewConstraints)
        bgView.addConstraints(arPreviewConstraints)
        bgView.sendSubviewToBack(arPreview)
        
        // Adjust bitrate sliders
        videoBitrateSlider?.value = Float(RTMPStream.defaultVideoBitrate) / 1000
        audioBitrateSlider?.value = Float(RTMPStream.defaultAudioBitrate) / 1000

//        NotificationCenter.default.addObserver(self, selector: #selector(on(_:)), name: UIDevice.orientationDidChangeNotification, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        logger.info("viewWillAppear")
        super.viewWillAppear(animated)
        
        rtmpStream.attachARMultimediaSource(self.arMultimediaIO)
    }

    override func viewWillDisappear(_ animated: Bool) {
        logger.info("viewWillDisappear")
        super.viewWillDisappear(animated)
//        rtmpStream.removeObserver(self, forKeyPath: "currentFPS")
        rtmpStream.close()
        rtmpStream.dispose()
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
        
        var newFPS: Double? = nil
        
        switch segment.selectedSegmentIndex {
        case 0:
            newFPS = 15.0
        case 1:
            newFPS = 30.0
        case 2:
            newFPS = 60.0
        default:
            break
        }
        
        if let newFPS = newFPS {
            rtmpStream.captureSettings[.fps] = newFPS
            self.arMultimediaIO.setFPS(Int(newFPS))
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
    
    
    // MARK: - Code from Body tracking sample app below:
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        arView?.scene.addAnchor(characterAnchor)
        
        //return
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
}

extension LiveViewController : ARMultimediaIODelegate {
    func onRGBVideoResolutionChanged(width: Int, height: Int) {
        rtmpStream.videoSettings = [
            .width: width,
            .height: height
        ]
        logger.info("onRGBResolutionChanged: \(width)x\(height)")
    }
    
    func onAnchorsUpdate(session: ARSession, anchors: [ARAnchor]) {
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
}
