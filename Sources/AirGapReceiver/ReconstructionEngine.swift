import Foundation
import CryptoKit
import Compression
import UIKit

public final class ReconstructionEngine: ObservableObject {
    // Published UI properties (Throttled for ultra-smooth 60 FPS performance)
    @Published public var totalChunks: Int = 0
    @Published public var receivedCount: Int = 0
    @Published public var fileName: String = ""
    @Published public var origSize: Int = 0
    @Published public var shortHash: String = ""
    @Published public var isComplete: Bool = false
    @Published public var isVerifying: Bool = false
    @Published public var savedFileURL: URL? = nil
    @Published public var errorMessage: String? = nil
    
    // Missing frames tracking
    @Published public var isNearCompletion: Bool = false
    @Published public var missingChunksText: String = ""
    @Published public var missingCount: Int = 0

    // Internal lock-free / thread-safe storage
    private var chunksStorage: [Int: String] = [:]
    private let storageLock = NSLock()
    private let processingQueue = DispatchQueue(label: "com.airgap.processing", qos: .userInteractive)
    private let successGenerator = UINotificationFeedbackGenerator()

    // Throttled UI updater (10 Hz) to keep SwiftUI running at 60 FPS without micro-stutters
    private var uiUpdateTimer: Timer?
    private var lastPublishedCount: Int = -1

    public init() {
        successGenerator.prepare()
        startUIThrottleTimer()
    }

    deinit {
        uiUpdateTimer?.invalidate()
    }

    private func startUIThrottleTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.syncStateToUI()
            }
        }
    }

    public var progress: Double {
        guard totalChunks > 0 else { return 0.0 }
        return Double(receivedCount) / Double(totalChunks)
    }

    public var progressPercentString: String {
        guard totalChunks > 0 else { return "0%" }
        let pct = Int(progress * 100)
        return "\(pct)%"
    }

    public func processScannedCode(_ rawString: String) {
        guard !isComplete && !isVerifying else { return }
        guard rawString.hasPrefix("AG1|") else { return }

        let parts = rawString.components(separatedBy: "|")
        // AG1|total_chunks|chunk_index|filename|orig_size|short_hash|chunk_data
        guard parts.count == 7 else { return }

        guard let total = Int(parts[1]),
              let index = Int(parts[2]),
              let size = Int(parts[4]) else { return }

        let name = parts[3]
        let hash = parts[5]
        let payload = parts[6]

        var shouldFinalize = false

        storageLock.lock()
        if totalChunks == 0 {
            totalChunks = total
            fileName = name
            origSize = size
            shortHash = hash
        }

        if chunksStorage[index] == nil {
            chunksStorage[index] = payload
            if chunksStorage.count == total {
                shouldFinalize = true
            }
        }
        storageLock.unlock()

        if shouldFinalize {
            finalizeReconstruction()
        }
    }

    private func syncStateToUI() {
        storageLock.lock()
        let count = chunksStorage.count
        let total = totalChunks
        let isDone = isComplete
        storageLock.unlock()

        guard !isDone, total > 0 else { return }

        if count != lastPublishedCount {
            lastPublishedCount = count
            receivedCount = count

            let remaining = total - count
            missingCount = remaining

            // If remaining <= 50 frames or progress >= 75%, compute missing frames list
            if remaining <= 50 || (Double(count) / Double(total)) >= 0.75 {
                storageLock.lock()
                let missingIndices = (1...total).filter { chunksStorage[$0] == nil }
                storageLock.unlock()

                isNearCompletion = true
                missingChunksText = missingIndices.map(String.init).joined(separator: ", ")
            } else {
                isNearCompletion = false
                missingChunksText = ""
            }
        }
    }

    private func finalizeReconstruction() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isVerifying else { return }
            self.isVerifying = true
        }

        storageLock.lock()
        let chunksCopy = self.chunksStorage
        let total = self.totalChunks
        let expectedHash = self.shortHash
        let targetName = self.fileName
        let expectedSize = self.origSize
        storageLock.unlock()

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // 1. Reassemble chunks sequentially 1...total
            var combinedBase64 = ""
            combinedBase64.reserveCapacity(chunksCopy.count * 1500)
            for i in 1...total {
                if let part = chunksCopy[i] {
                    combinedBase64.append(part)
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "نقص في الإطار رقم \(i)"
                        self.isVerifying = false
                    }
                    return
                }
            }

            // 2. Decode Base64 into compressed bytes
            guard let compressedData = Data(base64Encoded: combinedBase64) else {
                DispatchQueue.main.async {
                    self.errorMessage = "فشل في فك تشفير Base64"
                    self.isVerifying = false
                }
                return
            }

            // 3. Decompress using LZMA (or ZLIB fallback)
            guard let decompressedData = self.decompress(data: compressedData, expectedSize: expectedSize) else {
                DispatchQueue.main.async {
                    self.errorMessage = "فشل في فك الضغط (LZMA/ZLIB)"
                    self.isVerifying = false
                }
                return
            }

            // 4. Verify SHA-256 hash
            let computedHash = SHA256.hash(data: decompressedData)
            let computedHashHex = computedHash.map { String(format: "%02x", $0) }.joined()

            guard computedHashHex.hasPrefix(expectedHash) else {
                DispatchQueue.main.async {
                    self.errorMessage = "رمز التحقق غير متطابق! قد يكون الملف تالفاً."
                    self.isVerifying = false
                }
                return
            }

            // 5. Save to app Documents directory
            let docsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileUrl = docsUrl.appendingPathComponent(targetName)

            do {
                try decompressedData.write(to: fileUrl, options: .atomic)
                DispatchQueue.main.async {
                    self.savedFileURL = fileUrl
                    self.isVerifying = false
                    self.isComplete = true
                    self.receivedCount = total
                    self.successGenerator.notificationOccurred(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "فشل حفظ الملف: \(error.localizedDescription)"
                    self.isVerifying = false
                }
            }
        }
    }

    private func decompress(data: Data, expectedSize: Int) -> Data? {
        let isXZ = data.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])

        // Allocate sufficient buffer: expected original size + 2MB safety margin
        let bufferSize = max(expectedSize + 2097152, data.count * 20)
        var destinationData = Data(count: bufferSize)

        // 1. If it's an XZ stream, decode with COMPRESSION_LZMA first
        if isXZ {
            let decodedSizeLZMA = destinationData.withUnsafeMutableBytes { destBuffer in
                data.withUnsafeBytes { srcBuffer in
                    compression_decode_buffer(
                        destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        bufferSize,
                        srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        data.count,
                        nil,
                        COMPRESSION_LZMA
                    )
                }
            }
            if decodedSizeLZMA > 0 {
                return destinationData.prefix(decodedSizeLZMA)
            }
        }

        // 2. Try ZLIB decoding (raw deflate or stripped zlib)
        var candidates: [Data] = []
        if data.count > 6 && data.first == 0x78 {
            let start = data.startIndex + 2
            let end = data.endIndex - 4
            if start < end {
                let rawSlice = data.subdata(in: start..<end)
                candidates.append(rawSlice)
            }
        }
        candidates.append(data)

        for candidate in candidates {
            let decodedSize = destinationData.withUnsafeMutableBytes { destBuffer in
                candidate.withUnsafeBytes { srcBuffer in
                    compression_decode_buffer(
                        destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        bufferSize,
                        srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        candidate.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if decodedSize > 0 {
                return destinationData.prefix(decodedSize)
            }
        }

        // 3. Fallback to LZMA even if magic header differed
        let fallbackLZMASize = destinationData.withUnsafeMutableBytes { destBuffer in
            data.withUnsafeBytes { srcBuffer in
                compression_decode_buffer(
                    destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    bufferSize,
                    srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_LZMA
                )
            }
        }
        if fallbackLZMASize > 0 {
            return destinationData.prefix(fallbackLZMASize)
        }

        return nil
    }

    public func reset() {
        storageLock.lock()
        chunksStorage.removeAll()
        totalChunks = 0
        fileName = ""
        origSize = 0
        shortHash = ""
        isComplete = false
        isVerifying = false
        savedFileURL = nil
        errorMessage = nil
        isNearCompletion = false
        missingChunksText = ""
        missingCount = 0
        lastPublishedCount = -1
        receivedCount = 0
        storageLock.unlock()
    }
}
