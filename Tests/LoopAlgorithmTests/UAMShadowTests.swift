//
//  UAMShadowTests.swift
//  LoopAlgorithm
//
//  Created by Melissa Lin on 9/16/26.
//

import XCTest
@testable import LoopAlgorithm

final class UAMShadowTests: XCTestCase {

    func testConservativeGlucoseDeltaUsesSmallerDelta() {
        let result = UAMShadow.conservativeGlucoseDelta(
            delta: 8,
            shortAverageDelta: 5
        )

        XCTAssertEqual(result, 5)
    }

    func testConservativeGlucoseDeltaUsesMoreNegativeDelta() {
        let result = UAMShadow.conservativeGlucoseDelta(
            delta: -6,
            shortAverageDelta: -3
        )

        XCTAssertEqual(result, -6)
    }

    func testUnannouncedGlucoseImpactSubtractsInsulinImpact() {
        let result = UAMShadow.unannouncedGlucoseImpact(
            delta: 8,
            shortAverageDelta: 5,
            insulinImpact: -2
        )

        XCTAssertEqual(result, 7)
    }
    
    func testForecastedUAMImpactDecaysToZeroOverThreeHours() {
        let initialImpact = 9.0

        let atStart = UAMShadow.forecastedUnannouncedGlucoseImpact(
            initialImpact: initialImpact,
            slopeFromDeviations: 0,
            tick: 0
        )

        let halfway = UAMShadow.forecastedUnannouncedGlucoseImpact(
            initialImpact: initialImpact,
            slopeFromDeviations: 0,
            tick: 18
        )

        let atThreeHours = UAMShadow.forecastedUnannouncedGlucoseImpact(
            initialImpact: initialImpact,
            slopeFromDeviations: 0,
            tick: 36
        )

        XCTAssertEqual(atStart, 9)
        XCTAssertEqual(halfway, 4.5)
        XCTAssertEqual(atThreeHours, 0)
    }

    func testForecastedUAMImpactCannotGrowAboveLinearDecayLimit() {
        let result = UAMShadow.forecastedUnannouncedGlucoseImpact(
            initialImpact: 9,
            slopeFromDeviations: 2,
            tick: 6
        )

        XCTAssertEqual(result, 7.5)
    }

    func testForecastedUAMImpactCanDecayFasterFromNegativeSlope() {
        let result = UAMShadow.forecastedUnannouncedGlucoseImpact(
            initialImpact: 9,
            slopeFromDeviations: -1,
            tick: 6
        )

        XCTAssertEqual(result, 3)
    }

    func testDeviationSlopeUsesMoreConservativeSlope() {
        let result = UAMShadow.deviationSlope(
            slopeFromMaxDeviation: -0.5,
            slopeFromMinDeviation: 3
        )

        XCTAssertEqual(result, -1)
    }

    func testGlucoseTrendCalculatesTrioDeltaWindows() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let glucose = [
            UAMShadow.GlucoseBucket(
                date: now,
                glucose: 120
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-5 * 60),
                glucose: 115
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-10 * 60),
                glucose: 110
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-15 * 60),
                glucose: 105
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-20 * 60),
                glucose: 100
            )
        ]

        let trend = try XCTUnwrap(
            UAMShadow.glucoseTrend(from: glucose)
        )

        XCTAssertEqual(trend.glucose, 120)
        XCTAssertEqual(trend.date, now)

        XCTAssertEqual(
            trend.delta,
            5,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            trend.shortAverageDelta,
            5,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            trend.longAverageDelta,
            5,
            accuracy: 0.0001
        )
    }

    func testGlucoseTrendSmoothsVeryRecentReadingIntoCurrentGlucose() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let glucose = [
            UAMShadow.GlucoseBucket(
                date: now,
                glucose: 120
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-60),
                glucose: 118
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-6 * 60),
                glucose: 110
            )
        ]

        let trend = try XCTUnwrap(
            UAMShadow.glucoseTrend(from: glucose)
        )

        XCTAssertEqual(
            trend.glucose,
            119,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            trend.date.timeIntervalSince1970,
            now.addingTimeInterval(-30).timeIntervalSince1970,
            accuracy: 0.0001
        )
    }

    func testBucketGlucosePreservesFiveMinuteReadings() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let glucose = [
            UAMShadow.GlucoseBucket(
                date: now,
                glucose: 120
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-5 * 60),
                glucose: 115
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-10 * 60),
                glucose: 110
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-15 * 60),
                glucose: 105
            )
        ]

        let result = UAMShadow.bucketGlucose(
            glucose,
            referenceDate: now
        )

        XCTAssertEqual(result.count, 4)

        XCTAssertEqual(result[0].glucose, 120)
        XCTAssertEqual(result[1].glucose, 115)
        XCTAssertEqual(result[2].glucose, 110)
        XCTAssertEqual(result[3].glucose, 105)
    }

    func testBucketGlucoseMergesReadingsWithinTwoMinutes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let glucose = [
            UAMShadow.GlucoseBucket(
                date: now,
                glucose: 120
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-60),
                glucose: 116
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-5 * 60),
                glucose: 110
            )
        ]

        let result = UAMShadow.bucketGlucose(
            glucose,
            referenceDate: now
        )

        XCTAssertEqual(result.count, 2)

        XCTAssertEqual(
            result[0].glucose,
            118,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            result[0].date,
            now
        )

        XCTAssertEqual(
            result[1].glucose,
            110,
            accuracy: 0.0001
        )
    }

    func testBucketGlucoseInterpolatesLargeGap() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let glucose = [
            UAMShadow.GlucoseBucket(
                date: now,
                glucose: 120
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-15 * 60),
                glucose: 90
            )
        ]

        let result = UAMShadow.bucketGlucose(
            glucose,
            referenceDate: now
        )

        XCTAssertEqual(result.count, 3)

        XCTAssertEqual(result[0].glucose, 120)
        XCTAssertEqual(result[1].glucose, 110)
        XCTAssertEqual(result[2].glucose, 100)

        XCTAssertEqual(
            result[1].date,
            now.addingTimeInterval(-5 * 60)
        )

        XCTAssertEqual(
            result[2].date,
            now.addingTimeInterval(-10 * 60)
        )
    }

    func testAverageDeltaUsesThreeBucketWindow() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let buckets = [
            UAMShadow.GlucoseBucket(
                date: now,
                glucose: 120
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-5 * 60),
                glucose: 115
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-10 * 60),
                glucose: 110
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-15 * 60),
                glucose: 105
            )
        ]

        let result = try XCTUnwrap(
            UAMShadow.averageDelta(
                from: buckets,
                at: 0
            )
        )

        XCTAssertEqual(
            result,
            5,
            accuracy: 0.0001
        )
    }

    func testInsulinImpactUsesDifferenceBetweenCumulativeEffects() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let start = GlucoseEffect(
            startDate: now.addingTimeInterval(-5 * 60),
            quantity: LoopQuantity(
                unit: .milligramsPerDeciliter,
                doubleValue: -10
            )
        )

        let end = GlucoseEffect(
            startDate: now,
            quantity: LoopQuantity(
                unit: .milligramsPerDeciliter,
                doubleValue: -13
            )
        )

        let result = UAMShadow.insulinImpact(
            from: start,
            to: end
        )

        XCTAssertEqual(
            result,
            -3,
            accuracy: 0.0001
        )
    }

    func testInsulinImpactInterpolatesAtExactGlucoseTimestamp() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let effects = [
            GlucoseEffect(
                startDate: now.addingTimeInterval(-10 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -10
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-5 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -15
                )
            ),
            GlucoseEffect(
                startDate: now,
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -20
                )
            )
        ]

        let glucoseDate = now.addingTimeInterval(-2.5 * 60)

        let result = try XCTUnwrap(
            UAMShadow.insulinImpact(
                at: glucoseDate,
                effects: effects
            )
        )

        XCTAssertEqual(
            result,
            -5,
            accuracy: 0.0001
        )
    }

    func testDeviationSamplesSubtractInsulinImpactFromAverageDelta() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let buckets = [
            UAMShadow.GlucoseBucket(date: now, glucose: 120),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-5 * 60),
                glucose: 115
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-10 * 60),
                glucose: 110
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-15 * 60),
                glucose: 105
            )
        ]

        let effects = [
            GlucoseEffect(
                startDate: now.addingTimeInterval(-20 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: 0
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-15 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -2
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-10 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -4
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-5 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -6
                )
            ),
            GlucoseEffect(
                startDate: now,
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -8
                )
            )
        ]

        let samples = UAMShadow.deviationSamples(
            buckets: buckets,
            insulinEffects: effects
        )

        XCTAssertEqual(samples.count, 1)

        let sample = try XCTUnwrap(samples.first)

        XCTAssertEqual(sample.averageDelta, 5, accuracy: 0.0001)
        XCTAssertEqual(sample.insulinImpact, -2, accuracy: 0.0001)
        XCTAssertEqual(sample.deviation, 7, accuracy: 0.0001)
    }

    func testDeviationSlopesDetectFallingHistoricalDeviation() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let samples = [
            UAMShadow.DeviationSample(
                date: now,
                averageDelta: 0,
                insulinImpact: 0,
                deviation: 6
            ),
            UAMShadow.DeviationSample(
                date: now.addingTimeInterval(-5 * 60),
                averageDelta: 0,
                insulinImpact: 0,
                deviation: 4
            ),
            UAMShadow.DeviationSample(
                date: now.addingTimeInterval(-10 * 60),
                averageDelta: 0,
                insulinImpact: 0,
                deviation: 2
            )
        ]

        let slopes = UAMShadow.deviationSlopes(
            samples: samples,
            referenceDate: now
        )

        XCTAssertEqual(
            slopes.slopeFromMaxDeviation,
            0,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            slopes.slopeFromMinDeviation,
            2,
            accuracy: 0.0001
        )

        let combined = UAMShadow.deviationSlope(
            slopeFromMaxDeviation: slopes.slopeFromMaxDeviation,
            slopeFromMinDeviation: slopes.slopeFromMinDeviation
        )

        XCTAssertEqual(
            combined,
            -2.0 / 3.0,
            accuracy: 0.0001
        )
    }

    func testForecastAppliesUAMImpactAndDecay() {
        let result = UAMShadow.forecast(
            startingGlucose: 120,
            glucoseImpactSeries: [0, 0, 0],
            unannouncedGlucoseImpact: 6,
            carbImpact: 0,
            slopeFromDeviations: 0
        )

        XCTAssertEqual(result.count, 4)

        XCTAssertEqual(result[0], 120, accuracy: 0.0001)
        XCTAssertEqual(result[1], 125.8333333333, accuracy: 0.0001)
        XCTAssertEqual(result[2], 131.5, accuracy: 0.0001)
        XCTAssertEqual(result[3], 137, accuracy: 0.0001)
    }

    func testForecastIsLimitedToFortyEightPoints() {
        let glucoseImpactSeries = Array(
            repeating: 0.0,
            count: 100
        )

        let result = UAMShadow.forecast(
            startingGlucose: 120,
            glucoseImpactSeries: glucoseImpactSeries,
            unannouncedGlucoseImpact: 6,
            carbImpact: 0,
            slopeFromDeviations: 0
        )

        XCTAssertLessThanOrEqual(result.count, 48)
        XCTAssertGreaterThanOrEqual(result.count, 13)
    }

    func testForecastClampsGlucoseToTrioBounds() {
        let highResult = UAMShadow.forecast(
            startingGlucose: 400,
            glucoseImpactSeries: [20],
            unannouncedGlucoseImpact: 10,
            carbImpact: 0,
            slopeFromDeviations: 0
        )

        let lowResult = UAMShadow.forecast(
            startingGlucose: 40,
            glucoseImpactSeries: [-20],
            unannouncedGlucoseImpact: 0,
            carbImpact: 0,
            slopeFromDeviations: 0
        )

        XCTAssertEqual(
            highResult.last,
            401
        )

        XCTAssertEqual(
            lowResult.last,
            39
        )
    }

    func testForecastOnlyAppliesNegativeCarbDeviation() {
        let positiveDeviation = UAMShadow.forecast(
            startingGlucose: 120,
            glucoseImpactSeries: [0],
            unannouncedGlucoseImpact: 0,
            carbImpact: 6,
            slopeFromDeviations: 0
        )

        let negativeDeviation = UAMShadow.forecast(
            startingGlucose: 120,
            glucoseImpactSeries: [0],
            unannouncedGlucoseImpact: 0,
            carbImpact: -6,
            slopeFromDeviations: 0
        )

        XCTAssertEqual(
            positiveDeviation[1],
            120,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            negativeDeviation[1],
            114.5,
            accuracy: 0.0001
        )
    }

    func testCalculateProducesUAMForecastForUnexplainedRise() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let glucose = [
            UAMShadow.GlucoseBucket(date: now, glucose: 120),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-5 * 60),
                glucose: 115
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-10 * 60),
                glucose: 110
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-15 * 60),
                glucose: 105
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-20 * 60),
                glucose: 100
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-25 * 60),
                glucose: 95
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-30 * 60),
                glucose: 90
            )
        ]
        let effects = [
            GlucoseEffect(
                startDate: now.addingTimeInterval(-20 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: 0
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-15 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -2
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-10 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -4
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-5 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -6
                )
            ),
            GlucoseEffect(
                startDate: now,
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -8
                )
            )
        ]

        let result = try XCTUnwrap(
            UAMShadow.calculate(
                glucose: glucose,
                insulinEffects: effects,
                futureGlucoseImpacts: [-2, -2, -2],
                carbImpact: 0,
                referenceDate: now
            )
        )

        XCTAssertEqual(
            result.currentGlucose,
            120,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            result.unannouncedGlucoseImpact,
            7,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            result.forecast.first,
            120
        )

        XCTAssertGreaterThan(
            result.forecast[1],
            120
        )
    }

    func testCalculateDoesNotCreateUAMRiseWhenGlucoseMatchesInsulinEffect() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let glucose = [
            UAMShadow.GlucoseBucket(date: now, glucose: 90),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-5 * 60),
                glucose: 92
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-10 * 60),
                glucose: 94
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-15 * 60),
                glucose: 96
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-20 * 60),
                glucose: 98
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-25 * 60),
                glucose: 100
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-30 * 60),
                glucose: 102
            )
        ]

        let effects = [
            GlucoseEffect(
                startDate: now.addingTimeInterval(-35 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: 0
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-30 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -2
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-25 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -4
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-20 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -6
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-15 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -8
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-10 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -10
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-5 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -12
                )
            ),
            GlucoseEffect(
                startDate: now,
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -14
                )
            )
        ]

        let result = try XCTUnwrap(
            UAMShadow.calculate(
                glucose: glucose,
                insulinEffects: effects,
                futureGlucoseImpacts: [-2, -2, -2],
                carbImpact: 0,
                referenceDate: now
            )
        )

        XCTAssertEqual(
            result.unannouncedGlucoseImpact,
            0,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            result.forecast,
            [90, 88, 86, 84]
        )
    }

    func testCalculateFadingUnexpectedRiseReducesUAMPersistence() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let glucose = [
            UAMShadow.GlucoseBucket(date: now, glucose: 120),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-5 * 60),
                glucose: 115
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-10 * 60),
                glucose: 111
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-15 * 60),
                glucose: 108
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-20 * 60),
                glucose: 106
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-25 * 60),
                glucose: 105
            ),
            UAMShadow.GlucoseBucket(
                date: now.addingTimeInterval(-30 * 60),
                glucose: 105
            )
        ]

        let effects = [
            GlucoseEffect(
                startDate: now.addingTimeInterval(-35 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: 0
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-30 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -2
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-25 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -4
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-20 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -6
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-15 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -8
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-10 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -10
                )
            ),
            GlucoseEffect(
                startDate: now.addingTimeInterval(-5 * 60),
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -12
                )
            ),
            GlucoseEffect(
                startDate: now,
                quantity: LoopQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: -14
                )
            )
        ]

        let result = try XCTUnwrap(
            UAMShadow.calculate(
                glucose: glucose,
                insulinEffects: effects,
                futureGlucoseImpacts: [-2, -2, -2],
                carbImpact: 0,
                referenceDate: now
            )
        )

        XCTAssertGreaterThan(
            result.unannouncedGlucoseImpact,
            0
        )

        XCTAssertGreaterThan(
            result.slopeFromMinDeviation,
            0
        )

        let combinedSlope = UAMShadow.deviationSlope(
            slopeFromMaxDeviation: result.slopeFromMaxDeviation,
            slopeFromMinDeviation: result.slopeFromMinDeviation
        )

        XCTAssertLessThan(
            combinedSlope,
            0
        )

        let withoutFasterDecay = UAMShadow.forecast(
            startingGlucose: result.currentGlucose,
            glucoseImpactSeries: [-2, -2, -2],
            unannouncedGlucoseImpact: result.unannouncedGlucoseImpact,
            carbImpact: 0,
            slopeFromDeviations: 0
        )

        XCTAssertLessThan(
            result.forecast[3],
            withoutFasterDecay[3]
        )
    }
    
    func testForecastMatchesTrioReferenceFixture() {
        let forecast = UAMShadow.forecast(
            startingGlucose: 120,
            glucoseImpactSeries: [-2, -2, -2],
            unannouncedGlucoseImpact: 7,
            carbImpact: 0,
            slopeFromDeviations: 0
        )

        let trioReference = [
            120.0,
            124.80555555555556,
            129.41666666666666,
            133.83333333333333
        ]

        XCTAssertEqual(
            forecast.count,
            trioReference.count
        )

        for (actual, expected) in zip(forecast, trioReference) {
            XCTAssertEqual(
                actual,
                expected,
                accuracy: 0.000001
            )
        }
    }
}
