import AppKit
import CoreLocation
import CoreWLAN

/// Tracks the current Wi-Fi SSID and publishes the text to show in the menu bar.
///
/// Since macOS 14, `CWInterface.ssid()` returns nil unless the app has been
/// granted Location access, so this also drives the permission flow.
@MainActor
final class WiFiMonitor: NSObject, ObservableObject, CWEventDelegate, CLLocationManagerDelegate {
    @Published private(set) var ssid: String?
    @Published private(set) var needsLocationPermission = false
    @Published var isVisible = true

    private let wifiClient = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()

    var menuBarTitle: String {
        let name = ssid ?? "Disconnected"
        return isVisible ? name : String(repeating: "_", count: name.count)
    }

    override init() {
        super.init()
        locationManager.delegate = self
        startMonitoring()
        requestLocationIfNeeded()
        refresh()
    }

    deinit {
        try? wifiClient.stopMonitoringAllEvents()
    }

    // MARK: - Wi-Fi

    private func startMonitoring() {
        wifiClient.delegate = self
        do {
            try wifiClient.startMonitoringEvent(with: .ssidDidChange)
        } catch {
            NSLog("WiFiName: could not monitor SSID changes: \(error.localizedDescription)")
        }
    }

    private func refresh() {
        // `interface()` is nil on Macs without Wi-Fi hardware; the original force-unwrapped it.
        ssid = wifiClient.interface()?.ssid()
        updatePermissionState()
    }

    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in self.refresh() }
    }

    // MARK: - Location permission

    private func requestLocationIfNeeded() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func updatePermissionState() {
        let status = locationManager.authorizationStatus
        let denied = status == .denied || status == .restricted
        // Only flag it when we are actually missing a name because of permissions.
        needsLocationPermission = denied && ssid == nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    func openLocationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
        NSWorkspace.shared.open(url)
    }
}
