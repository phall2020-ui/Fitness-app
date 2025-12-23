import Foundation
import Speech
import AVFoundation

struct ParsedExerciseData {
    let exerciseName: String?  // Optional now - can be nil for set-only input
    let weight: Double
    let reps: Int
}

class VoiceWorkoutService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    @Published var isRecording = false
    @Published var transcibedText = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    @Published var isAuthorized = false
    
    override init() {
        super.init()
        speechRecognizer?.delegate = self
    }
    
    func requestAuthorization() {
        // Request speech recognition permission
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                self?.isAuthorized = status == .authorized
                
                switch status {
                case .authorized:
                    print("✅ Speech recognition authorized")
                case .denied:
                    self?.errorMessage = "Speech recognition permission denied. Please enable in Settings."
                case .restricted:
                    self?.errorMessage = "Speech recognition is restricted on this device."
                case .notDetermined:
                    self?.errorMessage = "Speech recognition permission not determined."
                @unknown default:
                    self?.errorMessage = "Unknown authorization status."
                }
            }
        }
        
        // Also request microphone permission
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if !granted {
                    self?.errorMessage = "Microphone permission denied. Please enable in Settings."
                    self?.isAuthorized = false
                } else {
                    print("✅ Microphone permission granted")
                }
            }
        }
    }
    
    func startRecording() throws {
        // Reset any previous error
        errorMessage = nil
        transcibedText = ""
        
        // Check authorization
        guard authorizationStatus == .authorized else {
            errorMessage = "Speech recognition not authorized"
            throw NSError(domain: "VoiceWorkoutService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized"])
        }
        
        // Cancel any existing task
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        // Clean up any existing tap
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to configure audio session: \(error.localizedDescription)"
            throw error
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Unable to create recognition request"
            throw NSError(domain: "VoiceWorkoutService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // For on-device recognition (iOS 13+)
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        // Get input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Validate audio format - simulator may not have valid audio input
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("⚠️ Invalid audio format. Voice recording not available.")
            DispatchQueue.main.async {
                self.transcibedText = "[Voice input not available - check microphone]"
                self.errorMessage = "Voice input not available on this device"
                self.isRecording = false
            }
            return
        }
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                DispatchQueue.main.async {
                    self.transcibedText = result.bestTranscription.formattedString
                }
                isFinal = result.isFinal
                print("🎤 Transcribed: \(result.bestTranscription.formattedString)")
            }
            
            if let error = error {
                print("❌ Recognition error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
            }
            
            if error != nil || isFinal {
                DispatchQueue.main.async {
                    self.stopRecording()
                }
            }
        }
        
        // Install audio tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        
        DispatchQueue.main.async {
            self.isRecording = true
            print("🎙️ Recording started")
        }
    }
    
    func stopRecording() {
        print("🛑 Stopping recording")
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecording = false
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error)")
        }
    }
    
    // MARK: - SFSpeechRecognizerDelegate
    
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            if !available {
                self.errorMessage = "Speech recognition temporarily unavailable"
            }
        }
    }
    
    // MARK: - NLP Parsing Logic

    // Example: "Bench Press 100 kg 5 reps" -> ("Bench Press", 100.0, 5)
    // Example: "100 kg 5 reps" -> (nil, 100.0, 5) - for set-only mode
    func parseCommand(_ text: String) -> ParsedExerciseData? {
        let lower = text.lowercased()

        // 1. Extract Weight
        var weight: Double = 0.0

        // Find "X kg" or "X lbs" or "X kilos"
        if let weightMatch = parseNumber(from: lower, suffix: "kg") {
            weight = weightMatch
        } else if let weightMatch = parseNumber(from: lower, suffix: "kilo") {
            weight = weightMatch
        } else if let weightMatch = parseNumber(from: lower, suffix: "kilos") {
            weight = weightMatch
        } else if let weightMatch = parseNumber(from: lower, suffix: "lbs") {
            weight = weightMatch
        } else if let weightMatch = parseNumber(from: lower, suffix: "pounds") {
            weight = weightMatch
        }

        // 2. Extract Reps
        var reps: Int = 0
        if let repsMatch = parseNumber(from: lower, suffix: "reps") {
            reps = Int(repsMatch)
        } else if let repsMatch = parseNumber(from: lower, suffix: "rep") {
            reps = Int(repsMatch)
        } else if let repsMatch = parseNumber(from: lower, suffix: "repetitions") {
            reps = Int(repsMatch)
        } else if let repsMatch = parseNumber(from: lower, suffix: "times") {
            reps = Int(repsMatch)
        }

        // 3. Extract Name - remove weight and reps from text
        var cleanName = lower
        cleanName = cleanName.replacingOccurrences(of: "reps", with: "")
        cleanName = cleanName.replacingOccurrences(of: "rep", with: "")
        cleanName = cleanName.replacingOccurrences(of: "repetitions", with: "")
        cleanName = cleanName.replacingOccurrences(of: "times", with: "")
        cleanName = cleanName.replacingOccurrences(of: "kg", with: "")
        cleanName = cleanName.replacingOccurrences(of: "kilo", with: "")
        cleanName = cleanName.replacingOccurrences(of: "kilos", with: "")
        cleanName = cleanName.replacingOccurrences(of: "lbs", with: "")
        cleanName = cleanName.replacingOccurrences(of: "pounds", with: "")
        cleanName = cleanName.components(separatedBy: CharacterSet.decimalDigits).joined()
        cleanName = cleanName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clean up multiple spaces
        while cleanName.contains("  ") {
            cleanName = cleanName.replacingOccurrences(of: "  ", with: " ")
        }

        // Require at least weight AND reps
        guard weight > 0 && reps > 0 else {
            return nil
        }

        // Return with exercise name if we have one, otherwise set-only mode
        if cleanName.isEmpty {
            return ParsedExerciseData(exerciseName: nil, weight: weight, reps: reps)
        } else {
            return ParsedExerciseData(exerciseName: cleanName.capitalized, weight: weight, reps: reps)
        }
    }

    // Fuzzy match exercise name against a list of known exercises
    func findBestExerciseMatch(for spokenName: String, from exercises: [String]) -> String? {
        let normalizedSpoken = spokenName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Try exact match first
        if let exact = exercises.first(where: { $0.lowercased() == normalizedSpoken }) {
            return exact
        }

        // Try contains match
        if let contains = exercises.first(where: { $0.lowercased().contains(normalizedSpoken) }) {
            return contains
        }

        // Try reverse contains (spoken contains the exercise name)
        if let reverseContains = exercises.first(where: { normalizedSpoken.contains($0.lowercased()) }) {
            return reverseContains
        }

        // Calculate Levenshtein distance for fuzzy matching
        var bestMatch: String?
        var bestScore = Int.max

        for exercise in exercises {
            let distance = levenshteinDistance(normalizedSpoken, exercise.lowercased())
            // Accept if within 3 character edits
            if distance < bestScore && distance <= 3 {
                bestScore = distance
                bestMatch = exercise
            }
        }

        return bestMatch
    }

    // Levenshtein distance algorithm for fuzzy string matching
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }

        return matrix[m][n]
    }
    
    private func parseNumber(from text: String, suffix: String) -> Double? {
        // pattern: (number) followed by optional space and suffix
        let pattern = "([0-9]+(?:\\.[0-9]+)?)\\s*\(suffix)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        
        if let match = results.first {
            let numberString = nsString.substring(with: match.range(at: 1))
            return Double(numberString)
        }
        return nil
    }
}
