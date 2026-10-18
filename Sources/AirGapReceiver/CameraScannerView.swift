import SwiftUI
import AVFoundation

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

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .high

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

            // Hardware configuration: Continuous autofocus and 60 FPS scan mode
            try? videoCaptureDevice.lockForConfiguration()
            if videoCaptureDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoCaptureDevice.focusMode = .continuousAutoFocus
            }
            if videoCaptureDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoCaptureDevice.exposureMode = .continuousAutoExposure
            }
            for vFormat in videoCaptureDevice.formats {
                for range in vFormat.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= 60.0 {
                        videoCaptureDevice.activeFormat = vFormat
                        videoCaptureDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                        videoCaptureDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
                        break
                    }
                }
            }
            videoCaptureDevice.unlockForConfiguration()

            let metadataOutput = AVCaptureMetadataOutput()
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.global(qos: .userInteractive))
                metadataOutput.metadataObjectTypes = [.qr]
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
                onCodeScanned?(stringValue)
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
