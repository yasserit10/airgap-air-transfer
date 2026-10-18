import SwiftUI
import AVFoundation
import CoreMedia

public struct CameraScannerView: UIViewControllerRepresentable {
    public let onCodeScanned: (String) -> Void

    public init(onCodeScanned: @escaping (String) -> Void) {
        self.onCodeScanned = onCodeScanned
    }

    public func makeUIViewController(context: Context) -> CameraScannerViewController {
        let controller = CameraScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }

    public func updateUIViewController(_ uiViewController: CameraScannerViewController, context: Context) {}
}

public class CameraScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    public var onCodeScanned: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var lastScannedCode: String = ""

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        // inputPriority tells AVFoundation that device.activeFormat controls resolution and frame rate
        session.sessionPreset = .inputPriority

        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                return
            }

            // Find optimal 1080p 60 FPS format:
            // 1080p has ample resolution for dense barcodes while avoiding 4K thermal/memory bottlenecks
            var bestFormat: AVCaptureDevice.Format? = nil
            for format in videoCaptureDevice.formats {
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= 60.0 {
                        if dims.width == 1920 && dims.height == 1080 {
                            bestFormat = format
                            break
                        } else if bestFormat == nil && dims.width <= 1920 && dims.width >= 1280 {
                            bestFormat = format
                        }
                    }
                }
                if let best = bestFormat {
                    let d = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
                    if d.width == 1920 && d.height == 1080 {
                        break
                    }
                }
            }

            try? videoCaptureDevice.lockForConfiguration()
            if let targetFormat = bestFormat {
                videoCaptureDevice.activeFormat = targetFormat
                videoCaptureDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                videoCaptureDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
            }

            // Hardware configuration: Continuous autofocus restricted to near-range (computer monitor distance)
            if videoCaptureDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoCaptureDevice.focusMode = .continuousAutoFocus
            }
            if videoCaptureDevice.isAutoFocusRangeRestrictionSupported {
                videoCaptureDevice.autoFocusRangeRestriction = .near
            }

            // Continuous auto-exposure with slight negative bias to eliminate screen blowout/glare
            if videoCaptureDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoCaptureDevice.exposureMode = .continuousAutoExposure
            }
            if videoCaptureDevice.minExposureTargetBias < videoCaptureDevice.maxExposureTargetBias {
                let bias = max(videoCaptureDevice.minExposureTargetBias, min(Float(-0.75), videoCaptureDevice.maxExposureTargetBias))
                videoCaptureDevice.setExposureTargetBias(bias, completionHandler: nil)
            }
            if videoCaptureDevice.isLowLightBoostSupported {
                videoCaptureDevice.automaticallyEnablesLowLightBoostWhenAvailable = false
            }
            videoCaptureDevice.unlockForConfiguration()

            let metadataOutput = AVCaptureMetadataOutput()
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.global(qos: .userInteractive))
                metadataOutput.metadataObjectTypes = [.qr]

                // Disable video stabilization to eliminate multi-frame buffering latency and motion blur
                for connection in metadataOutput.connections {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .off
                    }
                }
            } else {
                return
            }

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.frame = view.layer.bounds
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)
            self.previewLayer = preview

            self.captureSession = session

            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        } catch {
            print("Error initializing camera: \(error.localizedDescription)")
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        for metadata in metadataObjects {
            if let readableObject = metadata as? AVMetadataMachineReadableCodeObject,
               let stringValue = readableObject.stringValue {
                // Deduplicate immediate identical scans right at the camera layer
                // Prevents redundant processing of the same frame 4-5 times at 60 FPS
                if stringValue != lastScannedCode {
                    lastScannedCode = stringValue
                    onCodeScanned?(stringValue)
                }
            }
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }
}
