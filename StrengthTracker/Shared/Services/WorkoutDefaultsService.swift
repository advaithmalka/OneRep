import Foundation

/// Resolves the values shown in a newly started workout from completed training
/// history. Routine targets remain the fallback when no compatible performance exists.
public enum WorkoutDefaultsService {
    public static func applyingLatestPerformance(
        to exercises: [WorkoutExercise],
        history: [Workout],
        before date: Date = Date()
    ) -> [WorkoutExercise] {
        guard !exercises.isEmpty else { return exercises }

        let references = Dictionary(
            exercises.map { ($0.exercise.id, $0.exercise) },
            uniquingKeysWith: { current, _ in current }
        )
        let compatibleHistory = WeightRecordingHistory.matching(
            history
                .filter { $0.completedAt != nil && !$0.isDeload && $0.trainingDate < date }
                .sorted { $0.trainingDate > $1.trainingDate },
            references: references
        )

        return exercises.map { exercise in
            guard let previous = compatibleHistory.lazy
                .compactMap({ workout in
                    workout.exercises.first {
                        $0.exercise.id == exercise.exercise.id &&
                        $0.sets.contains(where: \.isFullyCompleted)
                    }
                })
                .first else { return exercise }

            var resolved = exercise
            if resolved.sets.isEmpty {
                resolved.sets = previous.sets.filter {
                    $0.isFullyCompleted && $0.sideSets == nil && $0.dropSets.isEmpty
                }.enumerated().map { index, prior in
                    ExerciseSet(
                        id: UUID(), order: index + 1, setType: prior.setType,
                        weight: prior.weight, reps: prior.reps,
                        durationSeconds: prior.durationSeconds,
                        distanceMeters: prior.distanceMeters,
                        rpe: nil, isCompleted: false,
                        isPersonalRecord: false, completedAt: nil
                    )
                }
            }
            apply(previous: previous, to: &resolved, warmup: true)
            apply(previous: previous, to: &resolved, warmup: false)
            return resolved
        }
    }

    /// Keep the newest two completed observations per exercise for Watch defaults.
    /// Strip unrelated workout details so application context stays small.
    public static func historyForWatch(_ history: [Workout]) -> [Workout] {
        var counts: [UUID: Int] = [:]
        return history
            .filter { $0.completedAt != nil && !$0.isDeload }
            .sorted { $0.trainingDate > $1.trainingDate }
            .compactMap { workout in
                var copy = workout
                copy.exercises = workout.exercises.filter { exercise in
                    guard exercise.sets.contains(where: \.isFullyCompleted),
                          counts[exercise.exercise.id, default: 0] < 2 else { return false }
                    counts[exercise.exercise.id, default: 0] += 1
                    return true
                }
                guard !copy.exercises.isEmpty else { return nil }
                copy.notes = nil
                return copy
            }
    }

    private static func apply(
        previous: WorkoutExercise,
        to current: inout WorkoutExercise,
        warmup: Bool
    ) {
        let priorSets = previous.sets.filter {
            $0.isFullyCompleted && ($0.setType == .warmup) == warmup
        }
        guard !priorSets.isEmpty else { return }

        let currentIndices = current.sets.indices.filter {
            !current.sets[$0].isFullyCompleted &&
            (current.sets[$0].setType == .warmup) == warmup
        }
        for (position, index) in currentIndices.enumerated() {
            let prior = priorSets[min(position, priorSets.count - 1)]
            if let weight = prior.weight { current.sets[index].weight = weight }
            if let reps = prior.reps { current.sets[index].reps = reps }
        }
    }
}
