import ExpoModulesCore
import Foundation
import HealthKit


public class HealthBridgeModule: Module {
  private let store = HKHealthStore()
  
  public func definition() -> ModuleDefinition {
    Name("HealthBridge")
    
    AsyncFunction("isAvailable") { () -> Bool in
      return HKHealthStore.isHealthDataAvailable()
    }
    
    // Request read-only authorization for Sleep Analysis
    AsyncFunction("requestAuthorization") { () async throws -> Bool in
      guard HKHealthStore.isHealthDataAvailable() else { return false }
      guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return false }
      try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        store.requestAuthorization(toShare: [], read: [sleepType]) { ok, err in
          if let err { cont.resume(throwing: err) } else { cont.resume() }
        }
      }
      return true
    }
    
    // Returns [{ start: number(ms), end: number(ms), value: number, label: string }]
    AsyncFunction("getSleepSamples") { (startMs: Double, endMs: Double) async throws -> [[String: Any]] in
      guard HKHealthStore.isHealthDataAvailable() else { return [] }
      guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
      
      let start = Date(timeIntervalSince1970: startMs / 1000.0)
      let end = Date(timeIntervalSince1970: endMs / 1000.0)
      let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
      
      let samples: [HKSample] = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKSample], Error>) in
        let q = HKSampleQuery(sampleType: sleepType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [
          NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        ]) { _, results, error in
          if let error { cont.resume(throwing: error); return }
          cont.resume(returning: results ?? [])
        }
        self.store.execute(q)
      }
      
      let mapped: [[String: Any]] = samples.compactMap { s in
        guard let c = s as? HKCategorySample else { return nil }
        let v = c.value
        let label: String
        if #available(iOS 16.0, *) {
          switch v {
          case HKCategoryValueSleepAnalysis.inBed.rawValue: label = "inBed"
          case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: label = "asleep"
          case HKCategoryValueSleepAnalysis.awake.rawValue: label = "awake"
          case HKCategoryValueSleepAnalysis.asleepCore.rawValue: label = "asleepCore"
          case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: label = "asleepDeep"
          case HKCategoryValueSleepAnalysis.asleepREM.rawValue: label = "asleepREM"
          default: label = "unknown"
          }
        } else {
          switch v {
          case HKCategoryValueSleepAnalysis.inBed.rawValue: label = "inBed"
          case HKCategoryValueSleepAnalysis.asleep.rawValue: label = "asleep"
          case HKCategoryValueSleepAnalysis.awake.rawValue: label = "awake"
          default: label = "unknown"
          }
        }
        return [
          "start": c.startDate.timeIntervalSince1970 * 1000.0,
          "end": c.endDate.timeIntervalSince1970 * 1000.0,
          "value": v,
          "label": label
        ]
      }
      return mapped
    }
  }
}
