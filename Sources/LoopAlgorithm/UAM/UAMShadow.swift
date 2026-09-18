//
//  UAMShadow.swift
//  LoopAlgorithm
//
//  Shadow-only implementation of Unannounced Meal (UAM) prediction.
//  This code does not participate in Loop's glucose prediction or dosing.
//

import Foundation

enum UAMShadow {
    static func trimFlatTails(
        _ series: [Double],
        lookback: Int
    ) -> [Double] {
        guard series.count > lookback, lookback >= 0 else {
            return series
        }

        let maxToRemove = series.count - lookback

        let reversedSeries = series
            .map { jsRounded($0, scale: 0) }
            .reversed()

        var removeCount = 0

        for (current, next) in zip(
            reversedSeries,
            reversedSeries.dropFirst()
        ) {
            guard current == next else {
                break
            }

            removeCount += 1
        }

        removeCount = min(maxToRemove, removeCount)

        return Array(series.dropLast(removeCount))
    }

    static func uamDuration(
        unannouncedGlucoseImpact: Double,
        slopeFromDeviations: Double,
        glucoseImpactCount: Int
    ) -> TimeInterval {
        var durationHours = 0.0

        for index in 0..<glucoseImpactCount {
            let tick = index + 1

            let impact = forecastedUnannouncedGlucoseImpact(
                initialImpact: unannouncedGlucoseImpact,
                slopeFromDeviations: slopeFromDeviations,
                tick: tick
            )

            if impact > 0 {
                durationHours = Double(tick + 1) * 5 / 60
            }
        }

        return jsRounded(durationHours, scale: 1)
    }

    static func jsRounded(
        _ value: Double,
        scale: Int
    ) -> Double {
        let multiplier = pow(10.0, Double(scale))
        return floor(value * multiplier + 0.5) / multiplier
    }
    
    static func currentUnannouncedGlucoseImpact(
        trend: GlucoseTrend,
        insulinEffects: [GlucoseEffect]
    ) -> Double? {
        guard let insulinImpact = insulinImpact(
            at: trend.date,
            effects: insulinEffects
        ) else {
            return nil
        }

        return unannouncedGlucoseImpact(
            delta: trend.delta,
            shortAverageDelta: trend.shortAverageDelta,
            insulinImpact: insulinImpact
        )
    }
    static func conservativeGlucoseDelta(
            delta: Double,
            shortAverageDelta: Double
        ) -> Double {
            min(delta, shortAverageDelta)
        }
    static func unannouncedGlucoseImpact(
           delta: Double,
           shortAverageDelta: Double,
           insulinImpact: Double
       ) -> Double {
           jsRounded(
               conservativeGlucoseDelta(
                   delta: delta,
                   shortAverageDelta: shortAverageDelta
               ) - insulinImpact,
               scale: 1
           )
       }
    static func forecastedUnannouncedGlucoseImpact(
            initialImpact: Double,
            slopeFromDeviations: Double,
            tick: Int
        ) -> Double {
            let ticksInThreeHours = 36.0
            let tick = Double(tick)

            let slopeProjection = max(
                0,
                initialImpact + tick * slopeFromDeviations
            )

            let linearDecay = max(
                0,
                initialImpact * (1 - tick / ticksInThreeHours)
            )

            return min(slopeProjection, linearDecay)
        }

    static func deviationSlope(
        slopeFromMaxDeviation: Double,
        slopeFromMinDeviation: Double
    ) -> Double {
        min(
            jsRounded(slopeFromMaxDeviation, scale: 2),
            -jsRounded(slopeFromMinDeviation, scale: 2) / 3
        )
    }
    
    static func averageDelta(
        from buckets: [GlucoseBucket],
        at index: Int
    ) -> Double? {
        guard index >= 0,
              index + 3 < buckets.count
        else {
            return nil
        }

        return jsRounded(
            (buckets[index].glucose - buckets[index + 3].glucose) / 3,
            scale: 2
        )
    }

    static func insulinImpact(
          from startEffect: GlucoseEffect,
          to endEffect: GlucoseEffect
      ) -> Double {
          endEffect.quantity.doubleValue(for: .milligramsPerDeciliter)
              - startEffect.quantity.doubleValue(for: .milligramsPerDeciliter)
      }

    static func interpolatedInsulinEffect(
        at date: Date,
        effects: [GlucoseEffect]
    ) -> Double? {
        guard !effects.isEmpty else {
            return nil
        }

        if let exact = effects.first(where: { $0.startDate == date }) {
            return exact.quantity.doubleValue(for: .milligramsPerDeciliter)
        }

        guard let upperIndex = effects.firstIndex(where: { $0.startDate > date }),
              upperIndex > effects.startIndex
        else {
            return nil
        }

        let lower = effects[effects.index(before: upperIndex)]
        let upper = effects[upperIndex]

        let interval = upper.startDate.timeIntervalSince(lower.startDate)

        guard interval > 0 else {
            return nil
        }

        let fraction = date.timeIntervalSince(lower.startDate) / interval

        let lowerValue =
            lower.quantity.doubleValue(for: .milligramsPerDeciliter)

        let upperValue =
            upper.quantity.doubleValue(for: .milligramsPerDeciliter)

        return lowerValue + fraction * (upperValue - lowerValue)
    }

    static func insulinImpact(
        at date: Date,
        effects: [GlucoseEffect]
    ) -> Double? {
        let fiveMinutesAgo = date.addingTimeInterval(-5 * 60)

        guard let startEffect = interpolatedInsulinEffect(
            at: fiveMinutesAgo,
            effects: effects
        ),
        let endEffect = interpolatedInsulinEffect(
            at: date,
            effects: effects
        ) else {
            return nil
        }

        return endEffect - startEffect
    }

    static func futureGlucoseImpacts(
        from effects: [GlucoseEffect]
    ) -> [Double] {
        guard effects.count >= 2 else {
            return []
        }

        let sorted = effects.sorted {
            $0.startDate < $1.startDate
        }

        return zip(sorted, sorted.dropFirst()).map { start, end in
            insulinImpact(
                from: start,
                to: end
            )
        }
    }

    static func deviationSamples(
        buckets: [GlucoseBucket],
        insulinEffects: [GlucoseEffect]
    ) -> [DeviationSample] {
        guard buckets.count >= 4 else {
            return []
        }

        var samples: [DeviationSample] = []

        for index in 0..<(buckets.count - 3) {
            let bucket = buckets[index]

            guard let averageDelta = averageDelta(
                from: buckets,
                at: index
            ),
            let insulinImpact = insulinImpact(
                at: bucket.date,
                effects: insulinEffects
            ) else {
                continue
            }

            samples.append(
                DeviationSample(
                    date: bucket.date,
                    averageDelta: averageDelta,
                    insulinImpact: insulinImpact,
                    deviation: jsRounded(
                        averageDelta - insulinImpact,
                        scale: 3
                    )
                )
            )
        }

        return samples
    }

    static func deviationSlopes(
        samples: [DeviationSample],
        referenceDate: Date
    ) -> (
        slopeFromMaxDeviation: Double,
        slopeFromMinDeviation: Double
    ) {
        guard let current = samples.first else {
            return (0, 999)
        }

        let currentDeviation = current.deviation

        var slopeFromMaxDeviation = 0.0
        var slopeFromMinDeviation = 999.0
        var maxDeviation = 0.0
        var minDeviation = 999.0

        for sample in samples.dropFirst() {
            guard referenceDate > sample.date else {
                continue
            }

            let timeInterval =
                sample.date.timeIntervalSince(referenceDate)

            guard timeInterval != 0 else {
                continue
            }

            let deviationSlope =
                (sample.deviation - currentDeviation)
                / timeInterval
                * 60
                * 5

            if sample.deviation > maxDeviation {
                slopeFromMaxDeviation = min(0, deviationSlope)
                maxDeviation = sample.deviation
            }

            if sample.deviation < minDeviation {
                slopeFromMinDeviation = max(0, deviationSlope)
                minDeviation = sample.deviation
            }
        }

        return (
            slopeFromMaxDeviation,
            slopeFromMinDeviation
        )
    }
    
    static func forecast(
        startingGlucose: Double,
        glucoseImpactSeries: [Double],
        unannouncedGlucoseImpact: Double,
        carbImpact: Double,
        slopeFromDeviations: Double
    ) -> [Double] {
        var result = [startingGlucose]

        for (index, glucoseImpact) in glucoseImpactSeries.enumerated() {
            let tick = index + 1

            let forecastedDeviation =
                carbImpact * (1 - min(1, Double(tick) / 12))

            let forecastedUAMImpact =
                forecastedUnannouncedGlucoseImpact(
                    initialImpact: unannouncedGlucoseImpact,
                    slopeFromDeviations: slopeFromDeviations,
                    tick: tick
                )

            let next =
                result[result.count - 1]
                + jsRounded(glucoseImpact, scale: 2)
                + min(0, forecastedDeviation)
                + forecastedUAMImpact

            if result.count < 48 {
                result.append(next)
            }
        }

        let clampedResult = result.map {
            min(401, max(39, $0))
        }

        return trimFlatTails(
            clampedResult,
            lookback: 13
        )
    }
    
    static func calculate(
        glucose: [GlucoseBucket],
        insulinEffects: [GlucoseEffect],
        futureGlucoseImpacts: [Double],
        carbImpact: Double,
        referenceDate: Date
    ) -> Result? {
        guard let trend = glucoseTrend(from: glucose),
              let currentUAMImpact = currentUnannouncedGlucoseImpact(
                  trend: trend,
                  insulinEffects: insulinEffects
              )
        else {
            return nil
        }

        let buckets = bucketGlucose(
            glucose,
            referenceDate: referenceDate
        )

        let samples = deviationSamples(
            buckets: buckets,
            insulinEffects: insulinEffects
        )

        let slopes = deviationSlopes(
            samples: samples,
            referenceDate: referenceDate
        )

        let combinedSlope = deviationSlope(
            slopeFromMaxDeviation: slopes.slopeFromMaxDeviation,
            slopeFromMinDeviation: slopes.slopeFromMinDeviation
        )

        let prediction = forecast(
            startingGlucose: trend.glucose,
            glucoseImpactSeries: futureGlucoseImpacts,
            unannouncedGlucoseImpact: currentUAMImpact,
            carbImpact: carbImpact,
            slopeFromDeviations: combinedSlope
        )

        return Result(
            currentGlucose: trend.glucose,
            unannouncedGlucoseImpact: currentUAMImpact,
            slopeFromMaxDeviation: slopes.slopeFromMaxDeviation,
            slopeFromMinDeviation: slopes.slopeFromMinDeviation,
            forecast: prediction,
            duration: uamDuration(
                unannouncedGlucoseImpact: currentUAMImpact,
                slopeFromDeviations: combinedSlope,
                glucoseImpactCount: futureGlucoseImpacts.count
            )
        )
    }
    
    struct GlucoseTrend {
           let glucose: Double
           let date: Date
           let delta: Double
           let shortAverageDelta: Double
           let longAverageDelta: Double
       }
    
    static func glucoseTrend(
        from glucose: [GlucoseBucket]
    ) -> GlucoseTrend? {
        let sorted = glucose.sorted { $0.date > $1.date }

        guard let mostRecent = sorted.first else {
            return nil
        }

        var currentGlucose = mostRecent.glucose
        var currentDate = mostRecent.date

        var lastDeltas: [Double] = []
        var shortDeltas: [Double] = []
        var longDeltas: [Double] = []

        for entry in sorted.dropFirst() {
            guard entry.glucose > 38 else {
                continue
            }

            let minutesAgo =
                (currentDate.timeIntervalSince(entry.date) / 60).rounded()

            let change = currentGlucose - entry.glucose

            if minutesAgo > -2 && minutesAgo <= 2.5 {
                currentGlucose =
                    (currentGlucose + entry.glucose) / 2

                currentDate = Date(
                    timeIntervalSince1970:
                        (currentDate.timeIntervalSince1970
                         + entry.date.timeIntervalSince1970) / 2
                )
            } else if minutesAgo > 2.5 && minutesAgo <= 17.5 {
                let averageDelta =
                    (change / minutesAgo) * 5

                shortDeltas.append(averageDelta)

                if minutesAgo < 7.5 {
                    lastDeltas.append(averageDelta)
                }
            } else if minutesAgo > 17.5 && minutesAgo < 42.5 {
                let averageDelta =
                    (change / minutesAgo) * 5

                longDeltas.append(averageDelta)
            }
        }

        func mean(_ values: [Double]) -> Double {
            guard !values.isEmpty else {
                return 0
            }

            return values.reduce(0, +) / Double(values.count)
        }

        return GlucoseTrend(
            glucose: currentGlucose,
            date: currentDate,
            delta: mean(lastDeltas),
            shortAverageDelta: mean(shortDeltas),
            longAverageDelta: mean(longDeltas)
        )
    }

    struct GlucoseBucket {
        let date: Date
        let glucose: Double
    }

    struct DeviationSample {
        let date: Date
        let averageDelta: Double
        let insulinImpact: Double
        let deviation: Double
    }

    struct Result {
        let currentGlucose: Double
        let unannouncedGlucoseImpact: Double
        let slopeFromMaxDeviation: Double
        let slopeFromMinDeviation: Double
        let forecast: [Double]
        let duration: TimeInterval
    }
    
    static func bucketGlucose(
        _ glucose: [GlucoseBucket],
        referenceDate: Date
    ) -> [GlucoseBucket] {
        let glucoseData = glucose
            .filter { $0.glucose >= 39 }
            .filter {
                let age = referenceDate.timeIntervalSince($0.date)
                return age >= 0 && age <= 45 * 60
            }
            .sorted { $0.date > $1.date }

        guard let first = glucoseData.first else {
            return []
        }

        var bucketedData = [first]
        var lastIndex = 0

        for index in 1..<glucoseData.count {
            let current = glucoseData[index]

            var last = glucoseData[lastIndex]
            var elapsedMinutes =
                current.date.timeIntervalSince(last.date) / 60

            if abs(elapsedMinutes) > 8 {
                elapsedMinutes = min(240, abs(elapsedMinutes))

                while elapsedMinutes > 5 {
                    let previousDate =
                        last.date.addingTimeInterval(-5 * 60)

                    let gapDelta = current.glucose - last.glucose
                    let previousGlucose =
                        last.glucose
                        + (5 / elapsedMinutes) * gapDelta

                    let interpolated = GlucoseBucket(
                        date: previousDate,
                        glucose: previousGlucose.rounded()
                    )

                    bucketedData.append(interpolated)

                    elapsedMinutes -= 5
                    last = GlucoseBucket(
                        date: previousDate,
                        glucose: previousGlucose
                    )
                }

                // Match Trio: don't append the actual reading after
                // interpolating a gap.
            } else if abs(elapsedMinutes) > 2 {
                bucketedData.append(current)
            } else {
                let previous = bucketedData[bucketedData.count - 1]

                // Match Trio's simple two-value averaging behavior while
                // retaining the newer bucket's timestamp.
                bucketedData[bucketedData.count - 1] = GlucoseBucket(
                    date: previous.date,
                    glucose: (previous.glucose + current.glucose) / 2
                )
            }

            lastIndex = index
        }

        return bucketedData
    }
}
