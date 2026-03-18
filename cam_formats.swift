import Foundation
import AVFoundation
import CoreMedia

func fourCCString(_ code: FourCharCode) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]
    let s = bytes.map { b -> Character in
        if b >= 32 && b <= 126 {
            return Character(UnicodeScalar(b))
        } else {
            return "."
        }
    }
    return String(s)
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift cam_formats.swift <camera-uniqueID>\n", stderr)
    exit(2)
}

let uid = CommandLine.arguments[1]

guard let device = AVCaptureDevice(uniqueID: uid) else {
    fputs("camera not found for UID: \(uid)\n", stderr)
    exit(1)
}

print("name: \(device.localizedName)")
print("uid : \(device.uniqueID)")
print("formats:")

for (i, format) in device.formats.enumerated() {
    let desc = format.formatDescription
    let dims = CMVideoFormatDescriptionGetDimensions(desc)
    let subtype = CMFormatDescriptionGetMediaSubType(desc)
    let pixel = fourCCString(subtype)

    let fpsRanges = format.videoSupportedFrameRateRanges
        .map { r in
            String(format: "%.3f-%.3f fps", r.minFrameRate, r.maxFrameRate)
        }
        .joined(separator: ", ")

    print("[\(i)] \(dims.width)x\(dims.height)  pixel=\(pixel)  fps=\(fpsRanges)")
}
