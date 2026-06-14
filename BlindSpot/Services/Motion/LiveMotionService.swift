//
//  LiveMotionService.swift
//  Blind Spot
//
//  CoreMotion-backed `MotionService`. Streams device-motion at ~25 Hz and
//  reports the magnitude of user acceleration (gravity already removed by
//  CoreMotion's sensor fusion) in g.
//

import Foundation
import CoreMotion

final class LiveMotionService: MotionService {

    private let manager = CMMotionManager()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start(onSample: @escaping (_ impact: Double, _ total: Double) -> Void) {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 25.0   // 25 Hz

        // Deliver on the main queue so the consumer can update UI state directly.
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion else { return }
            let ua = motion.userAcceleration      // gravity removed
            let g = motion.gravity                // gravity component
            // Impact: magnitude of user acceleration (≈0 at rest, spikes on hits).
            let impact = (ua.x * ua.x + ua.y * ua.y + ua.z * ua.z).squareRoot()
            // Total measured acceleration = userAcceleration + gravity. ≈1g at
            // rest, ≈0 in free fall (the device is weightless).
            let tx = ua.x + g.x, ty = ua.y + g.y, tz = ua.z + g.z
            let total = (tx * tx + ty * ty + tz * tz).squareRoot()
            onSample(impact, total)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
