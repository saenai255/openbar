import AudioToolbox
import CoreAudio

enum Volume {
    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static var outputDevice: AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    static var level: Float? {
        get {
            guard let dev = outputDevice else { return nil }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            guard AudioObjectHasProperty(dev, &addr),
                  AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr else { return nil }
            return value
        }
        set {
            guard let dev = outputDevice, var value = newValue.map({ Float32(min(max($0, 0), 1)) }) else { return }
            var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            if value > 0 && isMuted { isMuted = false }
        }
    }

    static var isMuted: Bool {
        get {
            guard let dev = outputDevice else { return false }
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            var addr = address(kAudioDevicePropertyMute)
            guard AudioObjectHasProperty(dev, &addr),
                  AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr else { return false }
            return value != 0
        }
        set {
            guard let dev = outputDevice else { return }
            var value = UInt32(newValue ? 1 : 0)
            var addr = address(kAudioDevicePropertyMute)
            AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}
