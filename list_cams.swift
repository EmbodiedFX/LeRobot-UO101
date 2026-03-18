import AVFoundation

for (i, d) in AVCaptureDevice.devices(for: .video).enumerated() {
    print("[\(i)] \(d.localizedName)\tUID=\(d.uniqueID)")
}
