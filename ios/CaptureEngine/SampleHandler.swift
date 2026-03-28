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
    private var settingsLastReadTime: TimeInterval = 0
    private let settingsCacheInterval: TimeInterval = 2.0

    private func refreshSettingsIfNeeded() {
        let now = CACurrentMediaTime()
        guard now - settingsLastReadTime >= settingsCacheInterval else { return }
        settingsLastReadTime = now
        let defaults = UserDefaults(suiteName: appGroupID)
        let fps = defaults?.double(forKey: "capture_fps") ?? 0
        cachedFPS = fps > 0 ? fps : 1.0
        let max = defaults?.integer(forKey: "max_frames") ?? 0
        cachedMaxFrames = max > 0 ? max : 300
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
        
        // Throttling: If we haven't reached the next interval, drop the frame
        if currentTime - lastCaptureTime < interval {
            return
        }
        
        lastCaptureTime = currentTime
        
        // Process Frame
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Downscale to 480p approx. Cap at 1.0 so we never upscale frames that
        // are already shorter than 480 pixels.
        let scale = min(1.0, 480.0 / ciImage.extent.height)
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        
        // Write as HEIC directly using CIContext (Memory efficient, avoids UIImage/CGImage allocation overhead)
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
