// Native silent setup video; no screenshots, microphone or external encoder.
import AppKit
import AVFoundation

let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "DictusApp/Resources/KeyboardSetupGuide.mp4")
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
guard !FileManager.default.fileExists(atPath: destination.path) else { fatalError("Output already exists; choose a new output path") }
let width = 960, height = 540, fps = 12, secondsPerStep = 6
let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 800_000]])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
writer.add(input)
precondition(writer.startWriting())
writer.startSession(atSourceTime: .zero)
let steps = [
    ("Open Keyboard Settings", "General → Keyboard → Keyboards", "Add New Keyboard…", "sAiity"),
    ("Add sAiity", "Choose sAiity in Other Keyboards", "Other Keyboards", "sAiity"),
    ("Allow Full Access", "Open sAiity in the keyboard list", "sAiity", "Allow Full Access"),
    ("Return and verify", "Tap the test field. Hold the globe and choose sAiity.", "Next keyboard", "sAiity")]
func drawText(_ text: String, rect: CGRect, size: CGFloat, color: NSColor, bold: Bool = false) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    text.draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
                                       .foregroundColor: color, .paragraphStyle: paragraph])
}
for frame in 0..<(steps.count * secondsPerStep * fps) {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    var buffer: CVPixelBuffer?
    precondition(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess)
    let pixel = buffer!
    CVPixelBufferLockBaseAddress(pixel, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    NSColor(calibratedRed: 0.04, green: 0.09, blue: 0.16, alpha: 1).setFill()
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let step = frame / (secondsPerStep * fps)
    let text = steps[step]
    drawText("sAiity · Keyboard setup", rect: CGRect(x: 48, y: 32, width: 820, height: 42), size: 26, color: .systemTeal, bold: true)
    drawText(text.0, rect: CGRect(x: 48, y: 91, width: 860, height: 66), size: 48, color: .white, bold: true)
    drawText(text.1, rect: CGRect(x: 48, y: 164, width: 850, height: 80), size: 28, color: .lightGray)
    NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: 48, y: 256, width: 864, height: 180), xRadius: 22, yRadius: 22).fill()
    drawText(text.2, rect: CGRect(x: 72, y: 275, width: 690, height: 48), size: 32, color: .lightGray)
    drawText(text.3, rect: CGRect(x: 72, y: 357, width: 660, height: 56), size: 36, color: .white, bold: true)
    if step == 2 {
        NSColor.systemGreen.setFill()
        NSBezierPath(roundedRect: CGRect(x: 788, y: 352, width: 92, height: 50), xRadius: 25, yRadius: 25).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(x: 833, y: 355, width: 44, height: 44)).fill()
    } else {
        drawText("›", rect: CGRect(x: 842, y: 345, width: 48, height: 64), size: 46, color: .systemTeal)
    }
    for index in steps.indices {
        (index <= step ? NSColor.systemTeal : NSColor.darkGray).setFill()
        NSBezierPath(roundedRect: CGRect(x: 48 + index * 220, y: 478, width: 204, height: 8), xRadius: 4, yRadius: 4).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    CVPixelBufferUnlockBaseAddress(pixel, [])
    precondition(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))))
}
input.markAsFinished()
let completion = DispatchSemaphore(value: 0)
writer.finishWriting { completion.signal() }
completion.wait()
precondition(writer.status == .completed, "Video write failed: \(writer.error?.localizedDescription ?? "unknown")")
print("Created \(destination.path), 24 seconds, silent H.264")
