import Flutter
import UIKit
import CoreLocation

public class SwiftBackgroundLocationPlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {
    static var locationManager: CLLocationManager?
    static var channel: FlutterMethodChannel?
    var running = false
    var lastUpdateTime: Date?
    var updateInterval: TimeInterval = 60.0 // 60 seconds default (1 minute)
    var locationTimer: Timer?
    var lastKnownLocation: CLLocation?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftBackgroundLocationPlugin()
        
        SwiftBackgroundLocationPlugin.channel = FlutterMethodChannel(name: "com.almoullim.background_location/methods", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: SwiftBackgroundLocationPlugin.channel!)
        SwiftBackgroundLocationPlugin.channel?.setMethodCallHandler(instance.handle)
        instance.running = false
    }

    private func initLocationManager() {
        if (SwiftBackgroundLocationPlugin.locationManager == nil) {
            SwiftBackgroundLocationPlugin.locationManager = CLLocationManager()
            SwiftBackgroundLocationPlugin.locationManager?.delegate = self
            SwiftBackgroundLocationPlugin.locationManager?.requestAlwaysAuthorization()

            SwiftBackgroundLocationPlugin.locationManager?.allowsBackgroundLocationUpdates = true
            if #available(iOS 11.0, *) {
                SwiftBackgroundLocationPlugin.locationManager?.showsBackgroundLocationIndicator = true;
            }
            SwiftBackgroundLocationPlugin.locationManager?.pausesLocationUpdatesAutomatically = false
            
            // Set more aggressive settings for frequent updates
            SwiftBackgroundLocationPlugin.locationManager?.desiredAccuracy = kCLLocationAccuracyBest
            SwiftBackgroundLocationPlugin.locationManager?.distanceFilter = 1.0 // 1 meter
            SwiftBackgroundLocationPlugin.locationManager?.activityType = .fitness
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        SwiftBackgroundLocationPlugin.channel?.invokeMethod("location", arguments: "method")

        if (call.method == "start_location_service") {
            initLocationManager()
            SwiftBackgroundLocationPlugin.channel?.invokeMethod("location", arguments: "start_location_service")
            
            let args = call.arguments as? Dictionary<String, Any>
            let distanceFilter = args?["distance_filter"] as? Double
            let priority = args?["priority"] as? Int

            SwiftBackgroundLocationPlugin.locationManager?.distanceFilter = distanceFilter ?? 0

            if (priority == 0) {
                SwiftBackgroundLocationPlugin.locationManager?.desiredAccuracy = kCLLocationAccuracyBest
            }
            if (priority == 1) {
                SwiftBackgroundLocationPlugin.locationManager?.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            }
            if (priority == 2) {
                SwiftBackgroundLocationPlugin.locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
            }
            if (priority == 3) {
                if #available(iOS 14.0, *) {
                    SwiftBackgroundLocationPlugin.locationManager?.desiredAccuracy = kCLLocationAccuracyReduced
                } else {
                    // Fallback on earlier versions
                }
            }

            SwiftBackgroundLocationPlugin.locationManager?.startUpdatingLocation()
            
            // Start timer for periodic updates
            startLocationTimer()
            
            running = true
            result(true)
        } else if (call.method == "set_configuration") {
            let args = call.arguments as? Dictionary<String, Any>
            if let intervalString = args?["interval"] as? String,
               let interval = Double(intervalString) {
                updateInterval = interval / 1000.0 // Convert milliseconds to seconds
                print("iOS: Update interval set to \(updateInterval) seconds")
            }
            result(true)
        } else if (call.method == "set_android_notification") {
            // iOS doesn't need notification configuration like Android
            // But we can handle it for compatibility
            print("iOS: Notification configuration received (not needed for iOS)")
            result(true)
        } else if (call.method == "is_service_running") {
            result(running)
        } else if (call.method == "stop_location_service") {
            initLocationManager()
            running = false
            
            // Stop timer
            stopLocationTimer()
            
            SwiftBackgroundLocationPlugin.channel?.invokeMethod("location", arguments: "stop_location_service")
            SwiftBackgroundLocationPlugin.locationManager?.stopUpdatingLocation()
            result(true)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedAlways {
           
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let currentTime = Date()
        
        // Store the latest location
        lastKnownLocation = locations.last
        
        // Log all location updates for debugging
        print("DEBUG: Location update received at \(currentTime)")
        
        // Check if enough time has passed since last update
        if let lastUpdate = lastUpdateTime {
            let timeDifference = currentTime.timeIntervalSince(lastUpdate)
            print("DEBUG: Time since last update: \(timeDifference) seconds")
            if timeDifference < updateInterval {
                // Not enough time has passed, skip this update
                print("DEBUG: Skipping update - too soon")
                return
            }
        } else {
            print("DEBUG: First update - no previous time")
        }
        
        // Update the last update time
        lastUpdateTime = currentTime
        
        sendLocationUpdate(locations.last!)
    }
    
    private func sendLocationUpdate(_ location: CLLocation) {
        let locationData = [
            "speed": location.speed,
            "altitude": location.altitude,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "bearing": location.course,
            "time": location.timestamp.timeIntervalSince1970 * 1000,
            "is_mock": false
        ] as [String : Any]

        // Print lat/long to console
        print("=== iOS LOCATION UPDATE ===")
        print("Latitude: \(location.coordinate.latitude)")
        print("Longitude: \(location.coordinate.longitude)")
        print("Time: \(location.timestamp)")
        print("==========================")

        SwiftBackgroundLocationPlugin.channel?.invokeMethod("location", arguments: locationData)
    }
    
    private func startLocationTimer() {
        stopLocationTimer() // Stop any existing timer
        
        print("Starting location timer with interval: \(updateInterval) seconds")
        locationTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self, let location = self.lastKnownLocation else {
                print("DEBUG: Timer fired but no location available")
                return
            }
            
            print("DEBUG: Timer fired - sending location update")
            self.sendLocationUpdate(location)
        }
    }
    
    private func stopLocationTimer() {
        locationTimer?.invalidate()
        locationTimer = nil
        print("Location timer stopped")
    }
}
