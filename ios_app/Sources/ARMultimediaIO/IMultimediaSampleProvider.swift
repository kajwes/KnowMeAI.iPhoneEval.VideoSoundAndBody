import Foundation
import AVFoundation


public typealias ARVideoCallback = (CMSampleBuffer) -> ()
public typealias ARAudioCallback = (CMSampleBuffer) -> ()

public protocol IMultimediaSampleProvider : AnyObject {
    var onNewVideoSample: ARVideoCallback { get set }
    var onNewAudioSample: ARAudioCallback { get set }
}
