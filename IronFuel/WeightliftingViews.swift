import SwiftUI
import SwiftData
import CoreLocation

// MARK: - 1) Workout Dashboard (MyFitnessPal Style)

struct WorkoutDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var workouts: [WorkoutSession]
    @Query private var gymLocations: [GymLocation]
    
    @StateObject private var locManager = LocationManager()
    @State private var detectedGym: GymLocation?
    
    @State private var showActiveWorkout = false
    @State private var currentSession: WorkoutSession?
    @State private var showGymManagement = false
    
    // Today's workout stats
    private var todaysWorkouts: [WorkoutSession] {
        workouts.filter { Calendar.current.isDateInToday($0.startTime) }
    }
    
    private var totalExercisesToday: Int {
        todaysWorkouts.reduce(0) { $0 + $1.exercises.count }
    }
    
    private var totalSetsToday: Int {
        todaysWorkouts.reduce(0) { workout, session in
            workout + session.exercises.reduce(0) { $0 + $1.sets.count }
        }
    }
    
    private var workoutDurationToday: Int {
        todaysWorkouts.reduce(0) { total, workout in
            let duration = workout.endTime?.timeIntervalSince(workout.startTime) ?? 0
            return total + Int(duration / 60)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Today's Progress Card
                        todayProgressCard
                            .padding(.horizontal)
                        
                        // Quick Stats Row
                        HStack(spacing: 12) {
                            quickStatCard(icon: "dumbbell.fill", value: "\(totalExercisesToday)", label: "Exercises", color: .purple)
                            quickStatCard(icon: "repeat", value: "\(totalSetsToday)", label: "Sets", color: .blue)
                        }
                        .padding(.horizontal)
                        
                        // Gym Location Card
                        gymLocationCard
                            .padding(.horizontal)
                        
                        // Recent Workouts Section
                        recentWorkoutsSection
                            .padding(.horizontal)
                        
                        // Bottom padding for FAB
                        Spacer().frame(height: 100)
                    }
                    .padding(.top, 8)
                }
                .background(Color(.systemGroupedBackground))
                
                // Floating Start Workout Button
                floatingStartButton
            }
            .navigationTitle("Lift")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showGymManagement = true
                    } label: {
                        Image(systemName: "location.circle")
                            .foregroundColor(.blue)
                    }
                }
            }
            .fullScreenCover(item: $currentSession) { session in
                ActiveWorkoutView(session: session, onDelete: {
                    deleteWorkout(session)
                })
            }
            .sheet(isPresented: $showGymManagement) {
                GymManagementView()
            }
            .onAppear {
                setupLocation()
            }
        }
    }
    
    // MARK: - Today's Progress Card
    
    private var todayProgressCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Workout")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if todaysWorkouts.isEmpty {
                        Text("No workouts yet")
                            .font(.title2)
                            .fontWeight(.bold)
                    } else {
                        Text("\(todaysWorkouts.count) session\(todaysWorkouts.count == 1 ? "" : "s")")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }
                
                Spacer()
                
                // Duration circle
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    
                    Circle()
                        .trim(from: 0, to: min(Double(workoutDurationToday) / 60.0, 1.0))
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    
                    VStack(spacing: 0) {
                        Text("\(workoutDurationToday)")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("min")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 70, height: 70)
            }
            
            if !todaysWorkouts.isEmpty {
                Button {
                    if let last = todaysWorkouts.first {
                        currentSession = last
                    }
                } label: {
                    HStack {
                        Text("Great work! Keep pushing! 💪")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Quick Stat Card
    
    private func quickStatCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Gym Location Card
    
    private var gymLocationCard: some View {
        Button {
            showGymManagement = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: detectedGym != nil ? "location.fill" : "location.circle")
                    .font(.title2)
                    .foregroundColor(detectedGym != nil ? .green : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    if let gym = detectedGym {
                        Text("At \(gym.name)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Text("Auto-detected")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("No gym detected")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("Tap to manage locations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
        }
    }
    
    // MARK: - Recent Workouts Section
    
    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Workouts")
                    .font(.headline)
                Spacer()
                if workouts.count > 5 {
                    NavigationLink(destination: WorkoutHistoryListView()) {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            if workouts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("No workouts yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Start your first workout to track your gains!")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(Color(.systemBackground))
                .cornerRadius(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(workouts.prefix(5).enumerated()), id: \.element.id) { index, workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            workoutRow(workout: workout)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteWorkout(workout)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }

                        if index < min(workouts.count - 1, 4) {
                            Divider()
                                .padding(.leading, 50)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(16)
            }
        }
    }
    
    private func workoutRow(workout: WorkoutSession) -> some View {
        HStack(spacing: 12) {
            // Workout icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(.purple)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text("\(workout.exercises.count) exercises")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let gym = workout.gym {
                        Text("• \(gym.name)")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(workout.startTime.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let endTime = workout.endTime {
                    let duration = Int(endTime.timeIntervalSince(workout.startTime) / 60)
                    Text("\(duration) min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
    }
    
    // MARK: - Floating Start Button
    
    private var floatingStartButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    startNewWorkout()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.title3.bold())
                        Text("Start Workout")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.purple)
                            .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
                    )
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Actions
    
    func startNewWorkout() {
        let newSession = WorkoutSession(startTime: Date(), title: "New Workout")
        newSession.gym = detectedGym
        modelContext.insert(newSession)
        try? modelContext.save()
        currentSession = newSession
    }
    
    func deleteWorkout(_ workout: WorkoutSession) {
        modelContext.delete(workout)
        try? modelContext.save()
        currentSession = nil
    }
    
    func setupLocation() {
        locManager.requestPermission()
        locManager.getCurrentLocation { loc in
            if loc != nil {
                self.detectedGym = locManager.detectGym(from: gymLocations)
            }
        }
    }
}

// MARK: - Workout History Row (Legacy, keeping for compatibility)

struct WorkoutHistoryRow: View {
    let workout: WorkoutSession
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(workout.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("\(workout.exercises.count) Exercises • \(workout.startTime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let gymName = workout.gym?.name {
                Text(gymName)
                    .font(.caption2)
                    .padding(4)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(4)
                    .foregroundColor(.purple)
            }
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - 2) Active Workout View (with Edit/Delete)

struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let onDelete: () -> Void

    @State private var showAddExercise = false
    @State private var showDeleteConfirmation = false
    @State private var isEditing = false
    @State private var showVoiceError = false
    @StateObject private var voiceService = VoiceWorkoutService()
    @State private var selectedExerciseForVoice: WorkoutExercise?
    
    private var workoutDuration: String {
        let interval = Date().timeIntervalSince(session.startTime)
        let minutes = Int(interval / 60)
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Workout Header Card
                        workoutHeaderCard
                            .padding(.horizontal)
                        
                        // Exercises
                        VStack(spacing: 0) {
                            ForEach(session.exercises.sorted(by: { $0.orderIndex < $1.orderIndex })) { exercise in
                                exerciseCard(exercise: exercise)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Add Exercise Button
                        Button {
                            showAddExercise = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Add Exercise")
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(16)
                        }
                        .padding(.horizontal)
                        
                        // Voice Input Section
                        if voiceService.isRecording || !voiceService.transcibedText.isEmpty {
                            voiceRecordingCard
                                .padding(.horizontal)
                        }
                        
                        // Voice Error Message
                        if let error = voiceService.errorMessage, !voiceService.isRecording {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // Bottom padding
                        Spacer().frame(height: 120)
                    }
                    .padding(.top, 8)
                }
                .background(Color(.systemGroupedBackground))
                
                // Bottom Action Bar
                bottomActionBar
            }
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Cancel")
                            .foregroundColor(.red)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditing.toggle()
                        }
                    }
                    .foregroundColor(.blue)
                }
            }
            .sheet(isPresented: $showAddExercise) {
                ExerciseSelectionView { selectedExercise in
                    addExercise(selectedExercise)
                }
            }
            .alert("Cancel Workout?", isPresented: $showDeleteConfirmation) {
                Button("Keep Workout", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This will delete the current workout. This action cannot be undone.")
            }
        }
        .onAppear {
            voiceService.requestAuthorization()
        }
    }
    
    // MARK: - Workout Header Card
    
    private var workoutHeaderCard: some View {
        VStack(spacing: 12) {
            TextField("Workout Title", text: $session.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 20) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .foregroundColor(.purple)
                    Text(workoutDuration)
                        .font(.subheadline)
                        .monospacedDigit()
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "dumbbell.fill")
                        .foregroundColor(.purple)
                    Text("\(session.exercises.count) exercises")
                        .font(.subheadline)
                }
                
                if let gym = session.gym {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.green)
                        Text(gym.name)
                            .font(.subheadline)
                    }
                }
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Exercise Card
    
    private func exerciseCard(exercise: WorkoutExercise) -> some View {
        VStack(spacing: 0) {
            // Exercise Header
            HStack {
                Text(exercise.exerciseName)
                    .font(.headline)
                    .foregroundColor(.purple)

                Spacer()

                // Voice button for this specific exercise
                Button {
                    selectedExerciseForVoice = exercise
                    try? voiceService.startRecording()
                } label: {
                    Image(systemName: selectedExerciseForVoice?.id == exercise.id && voiceService.isRecording ? "waveform.circle.fill" : "mic.circle")
                        .foregroundColor(selectedExerciseForVoice?.id == exercise.id && voiceService.isRecording ? .red : .blue)
                        .font(.title3)
                }
                .disabled(voiceService.isRecording && selectedExerciseForVoice?.id != exercise.id)

                if isEditing {
                    Button {
                        deleteExercise(exercise)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            
            // Sets
            VStack(spacing: 0) {
                // Header row
                HStack {
                    Text("SET")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                    
                    Text("KG")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                    
                    Text("REPS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                    
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 44)
                    
                    if isEditing {
                        Spacer().frame(width: 44)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                
                ForEach(exercise.sets.sorted(by: { $0.orderIndex < $1.orderIndex })) { set in
                    setRow(set: set, exercise: exercise)
                    Divider().padding(.leading)
                }
                
                // Add Set Button
                Button {
                    addSet(to: exercise)
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Set")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))
            }
        }
        .cornerRadius(16)
        .padding(.bottom, 12)
    }
    
    private func setRow(set: ExerciseSet, exercise: WorkoutExercise) -> some View {
        HStack {
            Text("\(set.orderIndex + 1)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 40)
            
            TextField("0", value: Binding(get: { set.weight }, set: { set.weight = $0 }), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .frame(maxWidth: .infinity)
            
            TextField("0", value: Binding(get: { set.reps }, set: { set.reps = $0 }), format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .frame(maxWidth: .infinity)
            
            Button {
                set.isCompleted.toggle()
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(set.isCompleted ? .green : .gray)
            }
            .frame(width: 44)
            
            if isEditing {
                Button {
                    deleteSet(set, from: exercise)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .frame(width: 44)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Voice Recording Card
    
    private var voiceRecordingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if voiceService.isRecording {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                        .symbolEffect(.pulse)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listening...")
                            .font(.subheadline)
                        if let selected = selectedExerciseForVoice {
                            Text("For: \(selected.exerciseName)")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)

                    Text("Recorded")
                        .font(.subheadline)
                }

                Spacer()

                if voiceService.isRecording {
                    Button("Stop") {
                        voiceService.stopRecording()
                        processVoiceCommand(voiceService.transcibedText)
                    }
                    .foregroundColor(.red)
                } else {
                    Button("Clear") {
                        voiceService.transcibedText = ""
                        selectedExerciseForVoice = nil
                    }
                    .foregroundColor(.secondary)
                }
            }

            if !voiceService.transcibedText.isEmpty {
                Text(voiceService.transcibedText)
                    .font(.body)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Bottom Action Bar
    
    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 16) {
                // Voice Button
                Button {
                    handleVoiceButton()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: voiceService.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.title2)
                        Text("Voice")
                            .font(.caption2)
                    }
                    .foregroundColor(voiceService.isRecording ? .red : .blue)
                }
                .frame(maxWidth: .infinity)
                
                // Finish Button
                Button {
                    session.endTime = Date()
                    try? modelContext.save()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Finish Workout")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.green)
                    )
                }
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }
    
    // MARK: - Actions
    
    func addExercise(_ exercise: Exercise) {
        let newExercise = WorkoutExercise(exerciseName: exercise.name, orderIndex: session.exercises.count, exerciseRef: exercise)
        session.exercises.append(newExercise)
    }
    
    func deleteExercise(_ exercise: WorkoutExercise) {
        session.exercises.removeAll { $0.id == exercise.id }
        modelContext.delete(exercise)
    }
    
    func addSet(to exercise: WorkoutExercise) {
        let lastWeight = exercise.sets.last?.weight ?? 0
        let lastReps = exercise.sets.last?.reps ?? 0
        let newSet = ExerciseSet(weight: lastWeight, reps: lastReps, orderIndex: exercise.sets.count)
        exercise.sets.append(newSet)
    }
    
    func deleteSet(_ set: ExerciseSet, from exercise: WorkoutExercise) {
        exercise.sets.removeAll { $0.id == set.id }
        modelContext.delete(set)
        // Reorder remaining sets
        for (index, s) in exercise.sets.sorted(by: { $0.orderIndex < $1.orderIndex }).enumerated() {
            s.orderIndex = index
        }
    }
    
    func handleVoiceButton() {
        if voiceService.isRecording {
            voiceService.stopRecording()
            processVoiceCommand(voiceService.transcibedText)
        } else {
            selectedExerciseForVoice = nil
            try? voiceService.startRecording()
        }
    }
    
    func processVoiceCommand(_ text: String) {
        guard let data = voiceService.parseCommand(text) else {
            voiceService.errorMessage = "Could not parse command. Try saying: '100 kg 5 reps' or 'Bench Press 100 kg 5 reps'"
            return
        }

        let targetExercise: WorkoutExercise

        // If no exercise name was spoken, add to a selected or last exercise
        if data.exerciseName == nil {
            // Check if we have a specifically selected exercise from the exercise card
            if let selected = selectedExerciseForVoice {
                targetExercise = selected
            } else if let lastExercise = session.exercises.last {
                // Otherwise use the last exercise in the workout
                targetExercise = lastExercise
            } else {
                voiceService.errorMessage = "No exercise selected. Please add an exercise first or say the exercise name."
                return
            }
        } else {
            // Exercise name was spoken - try to match it
            let spokenName = data.exerciseName!

            // First, check if this exercise already exists in the current workout
            if let existingInWorkout = session.exercises.first(where: {
                $0.exerciseName.lowercased() == spokenName.lowercased()
            }) {
                targetExercise = existingInWorkout
            } else {
                // Try to match against the exercise database
                let fetchDescriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
                let allExercises = (try? modelContext.fetch(fetchDescriptor)) ?? []
                let exerciseNames = allExercises.map { $0.name }

                if let matchedName = voiceService.findBestExerciseMatch(for: spokenName, from: exerciseNames) {
                    // Found a match in the database
                    if let matchedExercise = allExercises.first(where: { $0.name == matchedName }) {
                        // Check again if this matched exercise is already in the workout
                        if let existingInWorkout = session.exercises.first(where: {
                            $0.exerciseName.lowercased() == matchedName.lowercased()
                        }) {
                            targetExercise = existingInWorkout
                        } else {
                            // Create new workout exercise from the matched database exercise
                            targetExercise = WorkoutExercise(
                                exerciseName: matchedName,
                                orderIndex: session.exercises.count,
                                exerciseRef: matchedExercise
                            )
                            session.exercises.append(targetExercise)
                        }
                    } else {
                        // Shouldn't happen, but fallback
                        targetExercise = WorkoutExercise(
                            exerciseName: matchedName,
                            orderIndex: session.exercises.count
                        )
                        session.exercises.append(targetExercise)
                    }
                } else {
                    // No match found - create a new custom exercise
                    targetExercise = WorkoutExercise(
                        exerciseName: spokenName,
                        orderIndex: session.exercises.count
                    )
                    session.exercises.append(targetExercise)
                    voiceService.errorMessage = "Created new exercise '\(spokenName)'. Did you mean something else?"
                }
            }
        }

        // Add the set to the target exercise
        let newSet = ExerciseSet(weight: data.weight, reps: data.reps, orderIndex: targetExercise.sets.count)
        targetExercise.sets.append(newSet)

        // Clear error if successful
        if voiceService.errorMessage?.contains("Created new exercise") != true {
            voiceService.errorMessage = nil
        }
    }
}

// MARK: - 3) Gym Management View

struct GymManagementView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var gyms: [GymLocation]
    @StateObject private var locManager = LocationManager()
    @State private var currentLocation: CLLocation?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        if let loc = currentLocation {
                            let newGym = GymLocation(name: "New Gym", latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                            context.insert(newGym)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("Add Current Location as Gym")
                        }
                    }
                    .disabled(currentLocation == nil)
                } footer: {
                    if currentLocation == nil {
                        Text("Locating...")
                    } else {
                        Text("Lat: \(currentLocation!.coordinate.latitude, specifier: "%.4f"), Long: \(currentLocation!.coordinate.longitude, specifier: "%.4f")")
                    }
                }
                
                Section("My Gyms") {
                    if gyms.isEmpty {
                        Text("No gyms saved yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(gyms) { gym in
                            VStack(alignment: .leading) {
                                TextField("Gym Name", text: Bindable(gym).name)
                                    .font(.headline)
                                Text("\(gym.latitude, specifier: "%.4f"), \(gym.longitude, specifier: "%.4f")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                context.delete(gyms[i])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Gyms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                locManager.requestPermission()
                locManager.getCurrentLocation { loc in
                    self.currentLocation = loc
                }
            }
        }
    }
}

// MARK: - 4) Exercise Selection View

struct ExerciseSelectionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    let onSelect: (Exercise) -> Void
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    
    @State private var searchText = ""
    
    var filtered: [Exercise] {
        if searchText.isEmpty { allExercises }
        else { allExercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) } }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { ex in
                    Button {
                        onSelect(ex)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ex.name)
                                    .foregroundColor(.primary)
                                Text(ex.muscleGroup.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let new = Exercise(name: searchText.isEmpty ? "New Exercise" : searchText, muscleGroup: .other)
                        context.insert(new)
                        onSelect(new)
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                if allExercises.isEmpty {
                    for def in WeightliftingConstants.defaultExercises {
                        let exercise = Exercise(name: def.name, muscleGroup: def.muscleGroup)
                        context.insert(exercise)
                    }
                }
            }
        }
    }
}

// MARK: - 5) Workout Detail View

struct WorkoutDetailView: View {
    let workout: WorkoutSession
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false
    @State private var selectedSetForEdit: ExerciseSet?
    @Environment(\.dismiss) private var dismiss
    
    private var duration: String {
        guard let endTime = workout.endTime else { return "In Progress" }
        let interval = Int(endTime.timeIntervalSince(workout.startTime) / 60)
        return "\(interval) min"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary Card
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.startTime.formatted(date: .complete, time: .shortened))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(duration)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        Spacer()
                        
                        if let gym = workout.gym {
                            VStack(alignment: .trailing) {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.green)
                                Text(gym.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
        }
    }
}

                    HStack(spacing: 20) {
                        VStack {
                            Text("\(workout.exercises.count)")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Exercises")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text("\(workout.exercises.reduce(0) { $0 + $1.sets.count })")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Sets")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            let totalVolume = workout.exercises.reduce(0.0) { exerciseTotal, exercise in
                                exerciseTotal + exercise.sets.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
                            }
                            Text("\(Int(totalVolume))")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("kg Volume")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Exercises
                List {
                    ForEach(workout.exercises.sorted(by: { $0.orderIndex < $1.orderIndex })) { exercise in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(exercise.exerciseName)
                                .font(.headline)
                                .foregroundColor(.purple)
                            
                            ForEach(exercise.sets.sorted(by: { $0.orderIndex < $1.orderIndex })) { set in
                                HStack {
                                    Text("Set \(set.orderIndex + 1)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    
                                    Text("\(set.weight, specifier: "%.1f") kg × \(set.reps)")
                                        .font(.subheadline)
                                    
                                    Spacer()
                                    
                                    if set.isCompleted {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Delete", role: .destructive) {
                                        deleteSet(set, from: exercise)
                                    }
                                    
                                    Button("Edit") {
                                        selectedSetForEdit = set
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .leading) {
                                    Button("Add Set") {
                                        addSetToExercise(exercise)
                                    }
                                    .tint(.green)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) {
                                deleteExercise(exercise)
                            }
                            
                            Button("Add Set") {
                                addSetToExercise(exercise)
                            }
                            .tint(.green)
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Delete Button
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Workout")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSetForEdit) { exerciseSet in
            EditExerciseSetSheet(exerciseSet: exerciseSet)
        }
        .alert("Delete Workout?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(workout)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    // MARK: - Helper Functions
    
    private func deleteExercise(_ exercise: WorkoutExercise) {
        withAnimation {
            // Delete all sets first
            for set in exercise.sets {
                modelContext.delete(set)
            }
            // Then delete the exercise
            modelContext.delete(exercise)
            try? modelContext.save()
        }
    }
    
    private func deleteSet(_ set: ExerciseSet, from exercise: WorkoutExercise) {
        withAnimation {
            modelContext.delete(set)
            try? modelContext.save()
            
            // Reorder remaining sets
            let remainingSets = exercise.sets.filter { $0.id != set.id }.sorted { $0.orderIndex < $1.orderIndex }
            for (index, remainingSet) in remainingSets.enumerated() {
                remainingSet.orderIndex = index
            }
            try? modelContext.save()
        }
    }
    
    private func addSetToExercise(_ exercise: WorkoutExercise) {
        let newSet = ExerciseSet(
            weight: exercise.sets.last?.weight ?? 45.0,
            reps: exercise.sets.last?.reps ?? 10,
            orderIndex: exercise.sets.count
        )
        newSet.exercise = exercise
        exercise.sets.append(newSet)
        modelContext.insert(newSet)
        try? modelContext.save()
    }
}

// MARK: - Workout History List View

struct WorkoutHistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var allWorkouts: [WorkoutSession]

    @State private var searchText = ""

    var filteredWorkouts: [WorkoutSession] {
        if searchText.isEmpty {
            return allWorkouts
        } else {
            return allWorkouts.filter { $0.title.localizedCaseInsensitiveContains(searchText) || ($0.gym?.name.localizedCaseInsensitiveContains(searchText) ?? false) }
        }
    }

    var body: some View {
        List {
            ForEach(filteredWorkouts) { workout in
                NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                    WorkoutHistoryRow(workout: workout)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteWorkout(workout)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Workout History")
        .searchable(text: $searchText, prompt: "Search workouts or gyms")
        .overlay {
            if filteredWorkouts.isEmpty {
                ContentUnavailableView("No Workouts", systemImage: "dumbbell", description: Text("You haven't logged any workouts yet."))
            }
        }
    }

    private func deleteWorkout(_ workout: WorkoutSession) {
        modelContext.delete(workout)
        try? modelContext.save()
    }
}
