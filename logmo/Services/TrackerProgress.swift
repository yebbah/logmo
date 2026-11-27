import Foundation

/// Where a daily tracker stands in the day being edited: nothing logged, started but the day's goal or form isn't complete yet,
/// or complete. Shown on the Log screen's "Still to log" strip in grey, amber and green.
enum TrackerState: Equatable { case none, inProgress, done }

enum TrackerProgress {
    /// - logged: anything entered for the tracker; complete: every field entered.
    /// A goal that isn't reached yet keeps a tracker in progress: protein for food, water, and a daily steps total.
    static func state(_ t: Tracker, logged: Set<Tracker>, complete: Set<Tracker>, protein: Int?, water: Int?, steps: Int?,
                      goals: GoalSet?) -> TrackerState {
        guard logged.contains(t) else { return .none }
        switch t {
        case .weight:
            return .done
        case .food:
            guard complete.contains(.food) else { return .inProgress }
            if let g = goals?.proteinDaily, let p = protein, p < g { return .inProgress }
            return .done
        case .water:
            if let g = goals?.waterDailyMl, let w = water, w < g { return .inProgress }
            return .done
        case .steps:
            if let g = goals?.dailyStepsGoal, let s = steps, s < g { return .inProgress }
            return .done
        case .checkIn:
            return complete.contains(.checkIn) ? .done : .inProgress
        }
    }
}

extension DayDraft {
    /// Trackers with anything entered in the day being edited.
    var loggedTrackers: Set<Tracker> {
        var s: Set<Tracker> = []
        if !weight.isEmpty { s.insert(.weight) }
        if !calories.isEmpty || !protein.isEmpty || !fat.isEmpty || !carbs.isEmpty { s.insert(.food) }
        if !water.isEmpty { s.insert(.water) }
        if !steps.isEmpty { s.insert(.steps) }
        if !ratings.isEmpty || performanceNA { s.insert(.checkIn) }
        return s
    }

    func state(_ t: Tracker, goals: GoalSet?) -> TrackerState {
        TrackerProgress.state(t, logged: loggedTrackers, complete: completeTrackers, protein: Int(protein), water: Int(water), steps: Int(steps), goals: goals)
    }
}
