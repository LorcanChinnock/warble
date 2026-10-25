import SwiftUI
import WarbleCore

/// An activity's clock. SwiftUI's timer text is ticked by the system, so Warble starts no timer to draw it. A clock that
/// reaches zero stays at 0:00 until the sender ends the activity.
struct ActivityClockText: View {
    let clock: ActivityClock

    var body: some View {
        switch clock {
        case .since(let date):
            Text(timerInterval: date...Date.distantFuture, countsDown: false, showsHours: false)
        case .until(let date):
            // The range must not run backwards, so a clock already at zero is an empty one.
            let now = Date.now
            Text(timerInterval: min(now, date)...date, countsDown: true, showsHours: false)
        }
    }
}

/// An activity's right-hand text: its clock, or failing that its badge.
struct ActivityValueText: View {
    let activity: Activity

    var body: some View {
        if let clock = activity.clock {
            ActivityClockText(clock: clock)
        } else if let badge = activity.badge {
            Text(verbatim: badge)
        }
    }
}
