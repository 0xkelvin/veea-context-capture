import ReplayKit
import CoreImage
import UniformTypeIdentifiers

class SampleHandler: RPBroadcastSampleHandler {

    private let appGroupID = "group.ai.bluleap.veea"
    private let snapshotsFolder = "snapshots"
    
    // Memory-efficient rendering pipeline
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Throttling state
    private var lastCaptureTime: TimeInterval = 0

    // Cached settings – re-read from UserDefaults at most once every 2 seconds
    // to avoid expensive I/O on every incoming video frame.
    // Note: RPBroadcastSampleHandler guarantees that processSampleBuffer is called
    // serially on a single background thread, so these fields do not require
    // additional synchronization.
    private var cachedFPS: Double = 1.0
    private var cachedMaxFrames: Int = 300
    // Minimum fraction of pixels (by perceptual luma) that must change to trigger
    // a capture. Prevents saving redundant frames when the screen is static.
    // Default 0.03 = 3 % change threshold.
    private var cachedSensitivity: Double = 0.03
    private var settingsLastReadTime: TimeInterval = 0
    private let settingsCacheInterval: TimeInterval = 2.0

    // Thumbnail of the last saved frame used for change detection.
    // Stored as raw RGBA8 bytes of a 16×16 downscaled image (~1 KB).
    private var lastSavedThumbBytes: [UInt8]?
    private let thumbWidth  = 16
    private let thumbHeight = 16

    private func refreshSettingsIfNeeded() {
        let now = CACurrentMediaTime()
        guard now - settingsLastReadTime >= settingsCacheInterval else { return }
        settingsLastReadTime = now
        let defaults = UserDefaults(suiteName: appGroupID)
        let fps = defaults?.double(forKey: "capture_fps") ?? 0
        cachedFPS = fps > 0 ? fps : 1.0
        let max = defaults?.integer(forKey: "max_frames") ?? 0
        cachedMaxFrames = max > 0 ? max : 300
        let sensitivity = defaults?.double(forKey: "capture_sensitivity") ?? 0
        cachedSensitivity = (sensitivity > 0 && sensitivity <= 1.0) ? sensitivity : 0.03
    }

    // Renders `ciImage` into a tiny 16×16 RGBA8 bitmap for fast pixel comparison.
    private func extractThumbBytes(from ciImage: CIImage) -> [UInt8]? {
        let sx = Double(thumbWidth)  / Double(ciImage.extent.width)
        let sy = Double(thumbHeight) / Double(ciImage.extent.height)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        let byteCount = thumbWidth * thumbHeight * 4
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        ciContext.render(
            scaled,
            toBitmap: &bytes,
            rowBytes: thumbWidth * 4,
            bounds: CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return bytes
    }

    // Returns the mean perceptual luma difference (0.0–1.0) between two RGBA8
    // byte arrays of the same length.  Uses integer luma weights to avoid
    // floating-point arithmetic in the inner loop.
    private func frameDifference(prev: [UInt8], curr: [UInt8]) -> Double {
        guard prev.count == curr.count, !prev.isEmpty else { return 1.0 }
        var weightedSum = 0
        var i = 0
        while i < prev.count {
            let dr = abs(Int(prev[i])     - Int(curr[i]))
            let dg = abs(Int(prev[i + 1]) - Int(curr[i + 1]))
            let db = abs(Int(prev[i + 2]) - Int(curr[i + 2]))
            // Perceptual luma: 0.299·R + 0.587·G + 0.114·B (integer approximation)
            weightedSum += 299 * dr + 587 * dg + 114 * db
            i += 4
        }
        let pixelCount = prev.count / 4
        // Divide by 1000 once (outside the loop) to complete the luma scaling,
        // then normalise to 0.0–1.0 against the maximum possible value.
        return Double(weightedSum / 1000) / Double(pixelCount * 255)
    }

    // Date formatter initialised once – DateFormatter is expensive to create.
    // The en_US_POSIX locale ensures the format is not affected by device locale.
    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss_SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        // Setup initial folder
        if let sharedFolder = getSnapshotsFolder() {
            if !FileManager.default.fileExists(atPath: sharedFolder.path) {
                try? FileManager.default.createDirectory(at: sharedFolder, withIntermediateDirectories: true)
            }
        }
    }
    
    override func broadcastPaused() { }
    override func broadcastResumed() { }
    override func broadcastFinished() { }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        refreshSettingsIfNeeded()

        let currentTime = CACurrentMediaTime()
        let interval = 1.0 / cachedFPS

        // Throttle: enforce the minimum interval between any two captures.
        // This also acts as the max capture rate, preventing burst captures
        // during rapid scrolling.
        if currentTime - lastCaptureTime < interval {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Change detection: compare a tiny 16×16 thumbnail of the current frame
        // against the last saved frame.  Skip the capture if the perceptual
        // difference is below the configured sensitivity threshold so that we
        // don't write redundant frames while the screen is static (e.g. user
        // is reading a chat without scrolling).
        if let thumbBytes = extractThumbBytes(from: ciImage) {
            if let prevBytes = lastSavedThumbBytes {
                let diff = frameDifference(prev: prevBytes, curr: thumbBytes)
                if diff < cachedSensitivity {
                    return  // Not enough change – skip this frame
                }
            }
            lastSavedThumbBytes = thumbBytes
        }

        lastCaptureTime = currentTime

        // Downscale to 480p approx. Cap at 1.0 so we never upscale frames that
        // are already shorter than 480 pixels.
        let scale = min(1.0, 480.0 / ciImage.extent.height)
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return }

        // Write as HEIC directly using CIContext (memory efficient, avoids UIImage/CGImage allocation overhead)
        guard let heicData = ciContext.heifRepresentation(of: scaledImage, format: .RGBA8, colorSpace: colorSpace, options: [:]) else {
            return
        }

        saveSnapshot(data: heicData)
        runJanitor()
    }
    
    // MARK: - File Management
    
    private func getSnapshotsFolder() -> URL? {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        return container?.appendingPathComponent(snapshotsFolder)
    }
    
    private func saveSnapshot(data: Data) {
        guard let folder = getSnapshotsFolder() else { return }
        
        let filename = "snapshot_\(dateFormatter.string(from: Date())).heic"
        let fileURL = folder.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to write snapshot: \(error)")
        }
    }
    
    private func runJanitor() {
        guard let folder = getSnapshotsFolder() else { return }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            
            if files.count <= cachedMaxFrames { return }
            
            // Sort by creation date (oldest first)
            let sortedFiles = try files.sorted {
                let date1 = try $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try $1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 < date2
            }
            
            // Delete excess older files
            let excessCount = files.count - cachedMaxFrames
            for i in 0..<excessCount {
                try FileManager.default.removeItem(at: sortedFiles[i])
            }
            
        } catch {
            print("Janitor failed: \(error)")
        }
    }
}
