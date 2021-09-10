import UIKit
import ARKit
import RealityKit
import SceneKit
import HaishinKit


public protocol ARMultimediaIODelegate : AnyObject {
    func onRGBVideoResolutionChanged(width: Int, height: Int)
    func onAnchorsUpdate(session: ARSession, anchors: [ARAnchor])
}


/// Wrapper around ARSession providing camera and audio frames instead of raw device input
public class ARMultimediaIO : NSObject, IMultimediaSampleProvider {
    
    public weak var delegate: ARMultimediaIODelegate? = nil {
        didSet {
            self.didChangeOrientation()
        }
    }
    
    public private(set) var arView: ARView
    private var arSession: ARSession {
        return arView.session
    }
    
    private let frameProcessingQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.Example-iOS.frameProcessingQueue", qos: .userInteractive, attributes: [], autoreleaseFrequency: .workItem, target: nil)

    public var onNewVideoSample: ARVideoCallback = { _ in }
    public var onNewAudioSample: ARAudioCallback = { _ in }
    
    private var currInterfaceOrientation: UIInterfaceOrientation
    private var frameIdx = 0
    private var preferredFPS = -1
    
    let coreImageContext: CIContext
    let metalDevice: MTLDevice
    
    
    public init(metalDevice: MTLDevice) {
        arView = ARView(frame: .zero)
        self.currInterfaceOrientation = .unknown
        self.metalDevice = metalDevice
        coreImageContext = CIContext(mtlDevice: metalDevice)
        
        super.init()
        
        DispatchQueue.main.async { [weak self] in
            self?.currInterfaceOrientation = UIApplication.shared.statusBarOrientation
            logger.info(self!.currInterfaceOrientation.rawValue)
        }
        
        arView.session.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.didChangeOrientation), name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public func startCameraStream(videoFormat: ARBodyTrackingConfiguration.VideoFormat) {
        guard ARBodyTrackingConfiguration.isSupported else {
            fatalError("This feature is only supported on devices with an A12 chip")
        }
        
        let config = ARBodyTrackingConfiguration()
        config.providesAudioData = true
        config.videoFormat = videoFormat
        
        preferredFPS = videoFormat.framesPerSecond
        arSession.delegate = self
        arSession.run(config, options: [.removeExistingAnchors, .resetTracking])
        didChangeOrientation()
    }
    
    public func stopCameraStream() {
        arSession.pause()
    }
    
    @objc
    func didChangeOrientation() {
        guard arSession.configuration != nil else { return }
        
        DispatchQueue.main.async { [weak self] in
            let newOrientation = UIApplication.shared.statusBarOrientation
            
            self?.frameProcessingQueue.async { [weak self] in
                guard let self = self else { return }
                
                // Change orientation
//                let prevInterfaceOrientation = self.currInterfaceOrientation
                self.currInterfaceOrientation = newOrientation
                
                let landscapeWidth = Int(self.arSession.configuration!.videoFormat.imageResolution.width)
                let landscapeHeight = Int(self.arSession.configuration!.videoFormat.imageResolution.height)
                let newWidth = self.currInterfaceOrientation.isPortrait ? landscapeHeight : landscapeWidth
                let newHeight = self.currInterfaceOrientation.isPortrait ? landscapeWidth : landscapeHeight
                self.delegate?.onRGBVideoResolutionChanged(width: newWidth, height: newHeight)
            }
        }
    }
    
    public func setFPS(_ fps: Int) {
        logger.info("Setting FPS to \(fps)")
        self.preferredFPS = fps
    }
}

// MARK: - ARSession delegate
extension ARMultimediaIO : ARSessionDelegate {
    public func session(_ session: ARSession, didOutputAudioSampleBuffer audioSampleBuffer: CMSampleBuffer) {
        onNewAudioSample(audioSampleBuffer)
    }
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            defer {
                self.frameIdx += 1
            }
            
            // Ensure FPS
            let skipEveryNthFrame: Int = self.arSession.configuration!.videoFormat.framesPerSecond / self.preferredFPS
            guard (self.frameIdx % skipEveryNthFrame) == 0 else { return }
                
            /**
             You can either send the metadata via a RTMP message, similalrly how RGB frames are being sent. This will send metadata
             even when there is no person being recorded.
             
             Or you can do what what you did originally — i.e. send metadata only when there is a person in camera view and ARKit
             updates the tracked person's pose.
             
             In both cases, I move the implementation to the `processSceneAnchors()` method.
             */
//        self.processSceneAnchors(anchors: frame.anchors)
            
            autoreleasepool { [weak self] in
                guard let self = self else { return }
                
                if let correctlyOrientedPixelBuffer = self.rotatedPixelBufferBasedOnDeviceOrientation(pixelBuffer: frame.capturedImage),
                   let sampleBuffer = self.pixelBuffer2SampleBuffer(pixelBuffer: correctlyOrientedPixelBuffer, timestamp: frame.timestamp) {
                    self.onNewVideoSample(sampleBuffer)
                    
                } else {
                    logger.warn("ERROR: Could not create video CMSampleBuffer.")
                }
            }
        }
    }
    
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        frameProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            /**
             Process the body anchors either here or in `session(:didUpdate:)` above (see a more in-depth description in that method).
             */
            self.processSceneAnchors(session: session, anchors: anchors)
        }
    }
    
    private func processSceneAnchors(session: ARSession, anchors: [ARAnchor]) {
        self.delegate?.onAnchorsUpdate(session: session, anchors: anchors)
    }
    
    // MARK: - Status change
    public func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        print("ARSession failed with error" + error.localizedDescription)
    }
    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
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
    public func sessionWasInterrupted(_ session: ARSession) {
        logger.warn("AR Session was interrupted. Tracking state is:")
    }
    public func sessionInterruptionEnded(_ session: ARSession) {
        logger.warn("AR Session interruption ended")
    }
    public func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool
    {
        logger.warn("AR Session should attempt relocalization")
        return true
    }
}

// MARK: - [Internal] Pixel buffer rotation and conversion to CMSampleBuffer
extension ARMultimediaIO {
    private func pixelBuffer2SampleBuffer(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> CMSampleBuffer? {
        // Create video format description
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
        guard let formatDescription = formatDescription else {
            logger.warn("ERROR: Could not create a suitable video format description.")
            return nil
        }
        
        // Create output sample buffer
        let scale = CMTimeScale(NSEC_PER_SEC)
        let pts = CMTime(value: CMTimeValue(timestamp * Double(scale)), timescale: scale)
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: pts, decodeTimeStamp: CMTime.invalid)

        var outputSampleBuffer: CMSampleBuffer? = nil
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: pixelBuffer,
                                                 formatDescription: formatDescription,
                                                 sampleTiming: &timingInfo,
                                                 sampleBufferOut: &outputSampleBuffer)
        guard let outputSampleBuffer = outputSampleBuffer else {
            logger.warn("ERROR: Could not create video CMSampleBuffer.")
            return nil
        }
        
        return outputSampleBuffer
    }
    
    private func rotatedPixelBufferBasedOnDeviceOrientation(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        // The default orientation of the `capturedImage` buffer is landscape (home button to the left)
        // and we have to orient it according to the current interface orientation.

        // Performance optimization - If we're in a landscape orientation, don't change the video resolution and flip pixel buffer in-place.
        if currInterfaceOrientation == .landscapeLeft {
            // `.landscapeRight` is the default orientation of ARKit, so we flip only `.landscapeLeft` image
            
//            let _1: UInt8? = flipPixelBuferInPlace(pixelBuffer: pixelBuffer, planeIdx: 0) // Flip the Y plane
//            let _2: UInt16? = flipPixelBuferInPlace(pixelBuffer: pixelBuffer, planeIdx: 1) // Flip the CbCr plane

            return rotate(pixelBuffer, orientation: .down)
            
        } else if currInterfaceOrientation.isPortrait {
            // We need rotate the buffer to a portrait orientation
            return rotate(pixelBuffer, orientation: currInterfaceOrientation == .portrait ? .right : .left)
        }
        
        // If the interface is in the `.landscapeRight` orientation, we return the unmodified buffer
        return pixelBuffer
    }
    
    private func flipPixelBuferInPlace<T>(pixelBuffer: CVPixelBuffer, planeIdx: Int) -> T? {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIdx)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIdx)
        
        let baseAddr = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIdx)!.assumingMemoryBound(to: (T).self)
        let bottomAddr = baseAddr + (width * height - 1)
        
        for pixIdx in 0 ..< (width * height / 2) {
            let topRowAddr = baseAddr + pixIdx
            let bottomRowAddr = bottomAddr - pixIdx
            let tmp = topRowAddr.pointee
            topRowAddr.pointee = bottomRowAddr.pointee
            bottomRowAddr.pointee = tmp
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        
        return nil
    }
    
    // https://stackoverflow.com/a/64808787
    private func rotate(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CVPixelBuffer? {
        var newPixelBuffer: CVPixelBuffer?
        let error = CVPixelBufferCreate(kCFAllocatorDefault,
                        orientation == .down ? CVPixelBufferGetWidth(pixelBuffer) : CVPixelBufferGetHeight(pixelBuffer),
                        orientation == .down ? CVPixelBufferGetHeight(pixelBuffer) : CVPixelBufferGetWidth(pixelBuffer),
                        CVPixelBufferGetPixelFormatType(pixelBuffer), // kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                        nil,
                        &newPixelBuffer)
        
        guard error == kCVReturnSuccess,
           let buffer = newPixelBuffer else {
          return nil
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        coreImageContext.render(ciImage, to: buffer)
        return buffer
    }
}
