//
//  MockMotionService.swift
//  Blind Spot
//
//  Preview/offline `MotionService`. Reports nothing (no IMU in previews).
//

import Foundation

final class MockMotionService: MotionService {
    var isAvailable: Bool { false }
    func start(onSample: @escaping (_ impact: Double, _ total: Double) -> Void) {}
    func stop() {}
}
