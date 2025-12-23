import Foundation
import CoreLocation
import SwiftData

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var completion: ((CLLocation?) -> Void)?
    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func getCurrentLocation(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
        locationManager.requestLocation()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        completion?(location)
        completion = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
        completion?(nil)
        completion = nil
    }
    
    // MARK: - Gym Detection Logic
    
    /// Returns the nearest matched GymLocation if within radius
    func detectGym(from locations: [GymLocation]) -> GymLocation? {
        guard let current = lastLocation else { return nil }
        
        let sorted = locations.sorted {
            let dist1 = current.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            let dist2 = current.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
            return dist1 < dist2
        }
        
        if let nearest = sorted.first {
            let distance = current.distance(from: CLLocation(latitude: nearest.latitude, longitude: nearest.longitude))
            if distance <= nearest.radiusMeters {
                return nearest
            }
        }
        return nil
    }
}
