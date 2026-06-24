import Foundation
import HealthKit
import WatchConnectivity
import Combine

class WorkoutManager: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, WCSessionDelegate {
    @Published var heartRate: Double = 0
    @Published var workoutActive = false
    
    let healthStore = HKHealthStore()
    var session: HKWorkoutSession?
    var builder: HKLiveWorkoutBuilder?
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    func requestAuthorization() {
        let typesToShare: Set = [
            HKQuantityType.workoutType()
        ]
        
        let typesToRead: Set = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            // Authorization completed
        }
    }
    
    func startWorkout() {
        requestAuthorization()
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .highIntensityIntervalTraining
        configuration.locationType = .indoor
        
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()
        } catch {
            return
        }
        
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        
        session?.delegate = self
        builder?.delegate = self
        
        session?.startActivity(with: Date())
        builder?.beginCollection(withStart: Date()) { (success, error) in
            DispatchQueue.main.async {
                self.workoutActive = true
            }
        }
    }
    
    func stopWorkout() {
        session?.end()
        builder?.endCollection(withEnd: Date()) { (success, error) in
            self.builder?.finishWorkout { (workout, error) in
                DispatchQueue.main.async {
                    self.workoutActive = false
                    self.heartRate = 0
                }
            }
        }
    }
    
    // MARK: - HKWorkoutSessionDelegate
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        // Workout session state changes
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // Workout session failed
    }
    
    // MARK: - HKLiveWorkoutBuilderDelegate
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Event collected
    }
    
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        for type in types {
            if let quantityType = type as? HKQuantityType, quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate) {
                let statistics = workoutBuilder.statistics(for: quantityType)
                if let quantity = statistics?.mostRecentQuantity() {
                    let heartRateUnit = HKUnit(from: "count/min")
                    let value = quantity.doubleValue(for: heartRateUnit)
                    DispatchQueue.main.async {
                        self.heartRate = value
                        self.sendHeartRateToPhone(Int(value))
                    }
                }
            }
        }
    }
    
    private func sendHeartRateToPhone(_ bpm: Int) {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["bpm": bpm], replyHandler: nil, errorHandler: { error in
                print("Error sending message to iOS: \(error.localizedDescription)")
            })
        } else {
            // Fallback for background transfer if connection is not immediately reachable
            let _ = WCSession.default.transferUserInfo(["bpm": bpm])
        }
    }
    
    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // WCSession activated
    }
}
