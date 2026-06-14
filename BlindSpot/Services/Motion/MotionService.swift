//
//  MotionService.swift
//  Blind Spot
//
//  The seam for the device IMU (accelerometer/gyro via CoreMotion). Used during
//  a ride to capture motion and detect impacts/crashes. Delivers the
//  user-acceleration magnitude (in g, gravity removed) at the sensor rate.
//

import Foundation

protocol MotionService: AnyObject {
    var isAvailable: Bool { get }

    /// Start IMU updates, delivered on the main thread:
    ///  - `impact`: user-acceleration magnitude in g (≈0 at rest, spikes on hits)
    ///  - `total`:  total measured acceleration in g (≈1 at rest, ≈0 in free fall)
    func start(onSample: @escaping (_ impact: Double, _ total: Double) -> Void)
    func stop()
}
