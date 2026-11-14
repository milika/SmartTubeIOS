import CoreImage
import CoreImage.CIFilterBuiltins
import SmartTubeIOSCore
import SwiftUI

#if os(macOS)
import AppKit
#endif

// MARK: - SignInView
//
// Google Device Authorization Grant sign-in UI (mirrors Android's equivalent).
// No browser redirect — the user enters a short code at youtube.com/activate.

public struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showError = false

    public init() {}

    public var body: some View {
        #if os(tvOS)
        tvBody
        #else
        NavigationStack {
            Group {
                if let info = auth.pendingActivation {
                    activationView(info: info)
                } else {
                    loadingView
                }
            }
            .navigationTitle(L10n.string("Sign In"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel")) {
                        auth.cancelSignIn()
                        dismiss()
                    }
                }
            }
            .alert(L10n.string("Sign-In Failed"), isPresented: $showError, presenting: auth.error) { _ in
                Button(L10n.string("Try Again")) { Task { await auth.beginSignIn() } }
                Button(L10n.string("Cancel"), role: .cancel) { auth.error = nil }
            } message: { err in
                Text(err.localizedDescription)
            }
            .onChange(of: auth.error == nil ? 0 : 1) { _, hasError in
                if hasError == 1 { showError = true }
            }
        }
        .task {
            await auth.beginSignIn()
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
        #endif
    }

    #if os(tvOS)
    /// Full-screen tvOS sign-in layout — two-column, 10-foot-UI friendly.
    private var tvBody: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.85).ignoresSafeArea()

            if let info = auth.pendingActivation {
                tvActivationView(info: info)
            } else {
                tvLoadingView
            }

            Button {
                auth.cancelSignIn()
                dismiss()
            } label: {
                Label(L10n.string("Cancel"), systemImage: "xmark")
                    .font(.headline)
            }
            .padding(40)
        }
        .alert(L10n.string("Sign-In Failed"), isPresented: $showError, presenting: auth.error) { _ in
            Button(L10n.string("Try Again")) { Task { await auth.beginSignIn() } }
            Button(L10n.string("Cancel"), role: .cancel) { auth.error = nil }
        } message: { err in
            Text(err.localizedDescription)
        }
        .onChange(of: auth.error == nil ? 0 : 1) { _, hasError in
            if hasError == 1 { showError = true }
        }
        .task { await auth.beginSignIn() }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }

    private var tvLoadingView: some View {
        VStack(spacing: 24) {
            ProgressView().controlSize(.large)
            Text("Connecting to Google…", bundle: L10n.bundle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tvActivationView(info: AuthService.ActivationInfo) -> some View {
        HStack(alignment: .center, spacing: 80) {
            // Left column: instructions + code + countdown
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: AppSymbol.tvMediabox)
                        .font(.system(size: 56))
                        .foregroundStyle(.red)

                    Text("Sign in to SmartTube", bundle: L10n.bundle)
                        .font(.largeTitle).fontWeight(.bold)

                    Text("On any device, open the link below and enter the code.", bundle: L10n.bundle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Go to:", bundle: L10n.bundle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(info.verificationURL.absoluteString)
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }

                Text(info.userCode)
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .tracking(10)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 32)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                CountdownView(expiresAt: info.expiresAt) {
                    Task { await auth.beginSignIn() }
                }

                HStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for authorisation…", bundle: L10n.bundle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: QR code
            VStack(spacing: 16) {
                QRCodeView(content: activationQRURL(info: info))
                    .frame(width: 280, height: 280)
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text("Scan to open activation page", bundle: L10n.bundle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    // MARK: - Loading screen

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting to Google…", bundle: L10n.bundle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Activation code screen

    /// Builds the URL that Google accepts to auto-fill the user code:
    /// https://www.google.com/device?user_code=XXXX-XXXX
    private func activationQRURL(info: AuthService.ActivationInfo) -> String {
        guard var components = URLComponents(url: info.verificationURL, resolvingAgainstBaseURL: false) else {
            return info.verificationURL.absoluteString
        }
        let existing = components.queryItems ?? []
        components.queryItems = existing + [URLQueryItem(name: "user_code", value: info.userCode)]
        return components.url?.absoluteString ?? info.verificationURL.absoluteString
    }

    #if os(macOS)
    /// Opens the activation URL in the system default browser.
    ///
    /// `ASWebAuthenticationSession` was tried here but crashes reliably on macOS
    /// when the user closes Safari: the SafariLaunchAgent XPC teardown fires on a
    /// non-main thread and AppKit's sheet dismissal path calls `dispatch_assert_queue`
    /// against the main queue → `_dispatch_assert_queue_fail`.  Since Device
    /// Authorization Grant never needs a redirect callback, a plain browser open is
    /// both simpler and crash-free.
    @MainActor
    private func openActivationPageMac(info: AuthService.ActivationInfo) {
        guard let url = URL(string: activationQRURL(info: info)) else { return }
        NSWorkspace.shared.open(url)
    }
    #endif

    private func activationView(info: AuthService.ActivationInfo) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 20)

                Image(systemName: AppSymbol.tvMediabox)
                    .font(.system(size: 64))
                    .foregroundStyle(.red)

                VStack(spacing: 6) {
                    Text("Activate SmartTube", bundle: L10n.bundle)
                        .font(.title2).fontWeight(.bold)
                    Text(
                        "On this device, tap the button below — the sign-in page opens with your code already filled in.",
                        bundle: L10n.bundle
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }

                // Primary CTA: opens the activation URL with user_code pre-filled.
                // On macOS use ASWebAuthenticationSession so the page opens in an
                // in-app browser sheet rather than the external default browser.
                Button {
                    #if os(macOS)
                    openActivationPageMac(info: info)
                    #else
                    openURL(URL(string: activationQRURL(info: info)) ?? info.verificationURL)
                    #endif
                } label: {
                    Label(L10n.string("Open Activation Page"), systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // ── Or: scan from another device ────────────────────────────
                HStack(spacing: 8) {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                    Text("Or scan from another device", bundle: L10n.bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                }

                // QR code — scan to open the activation URL with code pre-filled
                QRCodeView(content: activationQRURL(info: info))
                    .frame(width: 180, height: 180)
                    .padding(8)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)

                Text("Scan to open activation page", bundle: L10n.bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // User code box
                Text(info.userCode)
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .tracking(6)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 32)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = info.userCode
                    #elseif os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(info.userCode, forType: .string)
                    #endif
                } label: {
                    Label(L10n.string("Copy Code"), systemImage: AppSymbol.copyDoc)
                }
                .buttonStyle(.bordered)

                // Countdown
                CountdownView(expiresAt: info.expiresAt) {
                    // Code expired — restart
                    Task { await auth.beginSignIn() }
                }

                VStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for authorisation…", bundle: L10n.bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                Button(role: .cancel) {
                    auth.cancelSignIn()
                } label: {
                    Text("Use a different account", bundle: L10n.bundle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
    }
}

// MARK: - QRCodeView

struct QRCodeView: View {
    let content: String

    var body: some View {
        if let img = makeQRImage() {
            GeometryReader { geo in
                img
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        } else {
            Image(systemName: AppSymbol.qrcode)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private func makeQRImage() -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.correctionLevel = "M"
        guard let data = content.data(using: .utf8) else { return nil }
        filter.message = data

        guard let ciImage = filter.outputImage else { return nil }

        // Scale up so the QR is crisp at any display size
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaled = ciImage.transformed(by: scale)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        #if os(macOS)
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        return Image(nsImage: nsImage)
        #else
        let uiImage = UIImage(cgImage: cgImage)
        return Image(uiImage: uiImage)
        #endif
    }
}

// MARK: - CountdownView

private struct CountdownView: View {
    let expiresAt: Date
    let onExpired: () -> Void

    @State private var remaining: TimeInterval = 0

    var body: some View {
        Group {
            if remaining > 0 {
                Label(timeString, systemImage: AppSymbol.clock)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Code expired", bundle: L10n.bundle)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task {
            remaining = max(0, expiresAt.timeIntervalSinceNow)
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining = max(0, expiresAt.timeIntervalSinceNow)
            }
            // Give an in-flight poll (e.g. fired by handleForeground on app return)
            // a few seconds to complete before creating a new device code.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            onExpired()
        }
    }

    private var timeString: String {
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        let fmt = L10n.string("Code expires in %d:%02d")
        return String(format: fmt, mins, secs)
    }
}
