import Foundation

/// ISO/IEC 14496-12 5th 12.2.2.2
struct MP4VideoMediaHeaderBox: MP4FullBox {
    static let version: UInt8 = 0
    static let flags: UInt32 = 0
    // MARK: MP4FullBox
    var size: UInt32 = 0
    let type: String = "vmhd"
    var offset: UInt64 = 0
    var version: UInt8 = Self.version
    var flags: UInt32 = Self.flags
    var children: [MP4BoxConvertible] = []
    // MARK: MP4VideoMediaHeaderBox
    var graphicsMode: UInt16 = 0
    var opcolor: [UInt16] = [0, 0, 0]
}

extension MP4VideoMediaHeaderBox: DataConvertible {
    // MARK: DataConvertible
    var data: Data {
        get {
            let buffer = ByteArray()
                .writeUInt32(size)
                .writeUTF8Bytes(type)
                .writeUInt8(version)
                .writeUInt24(flags)
                .writeUInt16(graphicsMode)
                .writeUInt16(opcolor[0])
                .writeUInt16(opcolor[1])
                .writeUInt16(opcolor[2])
            let size = buffer.position
            buffer.position = 0
            buffer.writeUInt32(UInt32(size))
            return buffer.data
        }
        set {
            do {
                let buffer = ByteArray(data: newValue)
                size = try buffer.readUInt32()
                _ = try buffer.readUTF8Bytes(4)
                version = try buffer.readUInt8()
                flags = try buffer.readUInt24()
                graphicsMode = try buffer.readUInt16()
                opcolor = [
                    try buffer.readUInt16(),
                    try buffer.readUInt16(),
                    try buffer.readUInt16()
                ]
            } catch {
                logger.error(error)
            }
        }
    }
}

extension MP4Box.Names {
    static let vmhd = MP4Box.Name<MP4VideoMediaHeaderBox>(rawValue: "vmhd")
}
