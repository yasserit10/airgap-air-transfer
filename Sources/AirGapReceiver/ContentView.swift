import SwiftUI

public struct ContentView: View {
    @StateObject private var engine = ReconstructionEngine()
    @State private var showingShareSheet = false
    @State private var copiedNotice = false

    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.09, blue: 0.14) // Dark Navy
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header Bar
                headerView

                if engine.isComplete {
                    successView
                } else {
                    scannerView
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let fileUrl = engine.savedFileURL {
                ShareSheet(items: [fileUrl])
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: {
                engine.reset()
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text("مستقبل البيانات البصري فائق السرعة")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("AirGap Optical Receiver Pro (60 FPS)")
                    .font(.caption2)
                    .foregroundColor(Color.cyan)
            }

            Spacer()

            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 20))
                .foregroundColor(.green)
                .padding(10)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color(red: 0.11, green: 0.14, blue: 0.22))
    }

    // MARK: - Scanner View
    private var scannerView: some View {
        VStack(spacing: 16) {
            // Camera Viewfinder Box
            ZStack {
                CameraScannerView { code in
                    engine.processScannedCode(code)
                }
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(engine.totalChunks > 0 ? Color.green : Color.cyan, lineWidth: 2)
                )

                // Reticle corners & prompt
                VStack {
                    HStack {
                        Text("⚡ 60 FPS Hardware Vision")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.85))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        Spacer()
                    }
                    .padding(12)

                    Spacer()

                    Text(engine.totalChunks > 0 ? "جاري التقاط الإطارات المتتابعة..." : "وجه الكاميرا نحو شاشة الحاسوب")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.75))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .padding(.bottom, 16)
                }

                if engine.isVerifying {
                    Color.black.opacity(0.85)
                        .cornerRadius(20)
                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .green))
                            .scaleEffect(1.6)
                        Text("جاري فك الضغط ومطابقة SHA-256...")
                            .foregroundColor(.white)
                            .font(.callout)
                            .fontWeight(.bold)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1.0, contentMode: .fit)
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Live Dashboard & Progress
            dashboardCard
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            Spacer()
        }
    }

    // MARK: - Dashboard Card
    private var dashboardCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(engine.totalChunks > 0 ? "\(engine.receivedCount) / \(engine.totalChunks) (\(engine.progressPercentString))" : "--")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)

                Spacer()

                Text(engine.totalChunks > 0 ? engine.fileName : "في انتظار أول إطار...")
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(gradient: Gradient(colors: [.cyan, .green]), startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(engine.progress), height: 12)
                        .animation(.easeInOut(duration: 0.15), value: engine.progress)
                }
            }
            .frame(height: 12)

            // Missing Frames Alert Box (Solves the Coupon Collector delay!)
            if engine.isNearCompletion && !engine.missingChunksText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("الإطارات المتبقية لإكمال الملف (\(engine.missingCount)):")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)

                        Spacer()

                        Button(action: {
                            UIPasteboard.general.string = engine.missingChunksText
                            copiedNotice = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedNotice = false
                            }
                        }) {
                            Text(copiedNotice ? "تم النسخ ✓" : "نسخ الأرقام")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.35))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }

                    Text(engine.missingChunksText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(6)

                    Text("💡 الصق هذه الأرقام في خانة 'بث النواقص' بالكمبيوتر لإكمال الملف فوراً.")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .padding(10)
                .background(Color(red: 0.25, green: 0.15, blue: 0.05))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.6), lineWidth: 1)
                )
            }

            if let err = engine.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(red: 0.11, green: 0.14, blue: 0.22))
        .cornerRadius(16)
    }

    // MARK: - Success View
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
            }

            VStack(spacing: 6) {
                Text("تم استلام قاعدة البيانات بنجاح!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("تم فك الضغط ومطابقة رمز التجزئة (SHA-256) بالكامل")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            VStack(spacing: 12) {
                infoRow(label: "اسم الملف:", value: engine.fileName)
                infoRow(label: "الحجم النهائي:", value: formatBytes(engine.origSize))
                infoRow(label: "عدد الإطارات:", value: "\(engine.totalChunks) إطار")
                infoRow(label: "حالة الأمان:", value: "مطابق وموثوق 100% ✅")
            }
            .padding()
            .background(Color(red: 0.11, green: 0.14, blue: 0.22))
            .cornerRadius(16)
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Button(action: {
                    showingShareSheet = true
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("مشاركة أو حفظ في تطبيق 'الملفات'")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.blue)
                    .cornerRadius(14)
                }

                Button(action: {
                    engine.reset()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("مسح داتابيس جديدة")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.cyan)
            Spacer()
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - ShareSheet Helper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
