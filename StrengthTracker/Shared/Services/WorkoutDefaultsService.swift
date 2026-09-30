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
            apply(previous: previous, to: &resolved, warmup: true)
            apply(previous: previous, to: &resolved, warmup: false)
            return resolved
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
