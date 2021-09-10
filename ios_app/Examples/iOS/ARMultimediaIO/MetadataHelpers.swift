import ARKit
import simd


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
    
    let cam_k = frame.camera.intrinsics
    let proj = frame.camera.projectionMatrix
    let pose_frame = frame.camera.transform
    
    //let tracking = frame.camera.trackingState // how do we turn into string?
    
    jsonDict["frame_index"] = frameIndex

    // Add timestamps
    jsonDict["time"] = time
    let date = Date()
    let format = DateFormatter()
    format.dateFormat = "yyyy-MM-dd_HH_mm_ss.SSS"
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
