import Foundation
import IOKit.ps

struct BatteryState: Equatable {
    var percent: Int
    var isCharging: Bool
    var onAC: Bool
    var minutesRemaining: Int?

    static func read() -> BatteryState? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let key = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = (d[key] as? Int).flatMap { $0 > 0 ? $0 : nil }
            return BatteryState(percent: current * 100 / max, isCharging: charging,
                                onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                                minutesRemaining: minutes)
        }
        return nil
    }

    var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
