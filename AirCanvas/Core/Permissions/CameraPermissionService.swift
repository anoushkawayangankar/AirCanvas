import AVFoundation

@MainActor
protocol CameraPermissionProviding {
    func authorizationStatus() -> CameraAuthorization
    func requestAccess() async -> CameraAuthorization
}

struct CameraPermissionService: CameraPermissionProviding {
    func authorizationStatus() -> CameraAuthorization {
        CameraAuthorization(status: AVCaptureDevice.authorizationStatus(for: .video))
    }

    func requestAccess() async -> CameraAuthorization {
        guard authorizationStatus() == .notDetermined else {
            return authorizationStatus()
        }

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        let updatedStatus = authorizationStatus()

        if granted != (updatedStatus == .authorized) {
            AppLogger.permissions.warning("Camera permission request result did not match the current authorization status")
        }

        return updatedStatus
    }
}
