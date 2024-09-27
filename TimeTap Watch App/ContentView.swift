import SwiftUI
import WatchKit
import AVFoundation

struct ContentView: View {
    @StateObject private var stopwatch = Stopwatch()
    @State private var crownValue: Double = 0
    @State private var lastCrownValue: Double = 0
    @State private var cumulativeCrownRotation: Double = 0
    @State private var crownInactivityTimer: Timer?
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    // Added extended runtime session here
    @State private var runtimeSession: WKExtendedRuntimeSession?
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            Text(stopwatch.timeString)
                .font(.system(size: 50, weight: .medium, design: .monospaced))
                .foregroundColor(currentTextColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding()
        }
        .onAppear {
            setupAudioSession()
            startExtendedRuntimeSession()
        }
        .onDisappear {
            invalidateExtendedRuntimeSession()
            crownInactivityTimer?.invalidate()
        }
        .gesture(
            ExclusiveGesture(
                LongPressGesture(minimumDuration: 1.0)
                    .onEnded { _ in
                        stopwatch.reset()
                    },
                LongPressGesture(minimumDuration: 0.2)
                    .onEnded { _ in
                        if !stopwatch.isRunning {
                            stopwatch.start()
                        }
                    }
            )
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    if stopwatch.isRunning {
                        stopwatch.stop()
                        speakTime()
                    }
                }
        )
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: -Double.greatestFiniteMagnitude,
            through: Double.greatestFiniteMagnitude,
            by: 1.0,
            sensitivity: .medium,
            isContinuous: true,
            isHapticFeedbackEnabled: false
        )
        .onChange(of: crownValue) { newValue in
            let delta = newValue - lastCrownValue
            lastCrownValue = newValue
            cumulativeCrownRotation += delta
            
            crownInactivityTimer?.invalidate()
            
            crownInactivityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                let rotationThreshold: Double = 24.0
                if abs(cumulativeCrownRotation) >= rotationThreshold {
                    speakTime()
                }
                cumulativeCrownRotation = 0
            }
        }
    }
    
    // MARK: - Extended Runtime Session Management
    
    func startExtendedRuntimeSession() {
        if runtimeSession == nil || runtimeSession?.state == .invalid {
            runtimeSession = WKExtendedRuntimeSession()
            runtimeSession?.delegate = stopwatch
            runtimeSession?.start()
        }
    }
    
    func invalidateExtendedRuntimeSession() {
        if let runtimeSession = runtimeSession, runtimeSession.state == .running {
            runtimeSession.invalidate()
        }
        runtimeSession = nil
    }
    
    // MARK: - Helper Functions
    
    var currentTextColor: Color {
        if stopwatch.timeElapsed == 0 {
            return .white
        } else if stopwatch.isRunning {
            return .green
        } else {
            return .red
        }
    }
    
    func speakTime() {
        let utterance = AVSpeechUtterance(string: stopwatch.timeStringSpoken)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechSynthesizer.speak(utterance)
    }
    
    func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }
}

class Stopwatch: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
    @Published var timeElapsed: TimeInterval = 0
    @Published var isRunning = false
    
    private var timer: Timer?
    private var startTime: Date?
    
    var timeString: String {
        let minutes = Int(timeElapsed) / 60
        let seconds = Int(timeElapsed) % 60
        let milliseconds = Int((timeElapsed - floor(timeElapsed)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    var timeStringSpoken: String {
        let minutes = Int(timeElapsed) / 60
        let seconds = Int(timeElapsed) % 60
        let milliseconds = Int((timeElapsed - floor(timeElapsed)) * 100)
        var components = [String]()
        if minutes > 0 {
            components.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }
        if seconds > 0 {
            components.append("\(seconds) \(seconds == 1 ? "second" : "seconds")")
        }
        if milliseconds > 0 {
            components.append("\(milliseconds) milliseconds")
        }
        if components.isEmpty {
            components.append("0 seconds")
        }
        return components.joined(separator: ", ")
    }
    
    func start() {
        startTime = Date() - timeElapsed
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            self.timeElapsed = Date().timeIntervalSince(self.startTime!)
        }
        isRunning = true
        playHapticFeedback()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
    
    func reset() {
        stop()
        timeElapsed = 0
        playResetHaptic()
        playResetHaptic()
    }
    
    // MARK: - Haptic Feedback
    
    func playHapticFeedback() {
        WKInterfaceDevice.current().play(.start)
    }
    
    func playResetHaptic() {
        WKInterfaceDevice.current().play(.notification)
    }
    
    // MARK: - WKExtendedRuntimeSessionDelegate
    
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("Extended runtime session started.")
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("Extended runtime session will expire soon.")
        // Optionally, you can handle the expiration here
    }
    
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        if let error = error {
            print("Extended runtime session invalidated with error: \(error.localizedDescription)")
        } else {
            print("Extended runtime session invalidated with reason: \(reason.rawValue)")
        }
    }
}
