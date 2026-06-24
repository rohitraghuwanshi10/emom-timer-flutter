import SwiftUI

struct ContentView: View {
    @StateObject var workoutManager = WorkoutManager()
    
    var body: some View {
        VStack(spacing: 12) {
            Text("ChronoPulse")
                .font(.headline)
                .foregroundColor(.purple)
            
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .foregroundColor(workoutManager.heartRate > 0 ? .red : .gray)
                    .scaleEffect(workoutManager.heartRate > 0 ? 1.2 : 1.0)
                    .animation(workoutManager.heartRate > 0 ? Animation.heartbeat() : .default, value: workoutManager.heartRate)
                
                Text(workoutManager.heartRate > 0 ? "\(Int(workoutManager.heartRate))" : "--")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                
                Text("BPM")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            if workoutManager.workoutActive {
                Button(action: {
                    workoutManager.stopWorkout()
                }) {
                    Text("Stop Workout")
                        .bold()
                        .foregroundColor(.white)
                }
                .background(Color.red)
                .cornerRadius(12)
            } else {
                Button(action: {
                    workoutManager.startWorkout()
                }) {
                    Text("Start Workout")
                        .bold()
                        .foregroundColor(.white)
                }
                .background(Color.green)
                .cornerRadius(12)
            }
        }
        .padding()
        .onAppear {
            workoutManager.requestAuthorization()
        }
    }
}

extension Animation {
    static func heartbeat() -> Animation {
        return Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
    }
}
