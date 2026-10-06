import Foundation
import CoreFoundation

enum Json {
  static func isJSONBoolean(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
  }

  static func object(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
  }

  static func array(_ value: Any?) -> [Any]? {
    value as? [Any]
  }

  static func string(_ value: Any?) -> String? {
    value as? String
  }

  static func bool(_ value: Any?) -> Bool? {
    guard let value, isJSONBoolean(value) else { return nil }
    return (value as? NSNumber)?.boolValue
  }

  static func int(_ value: Any?) -> Int? {
    guard let value, !(value is NSNull), !isJSONBoolean(value) else { return nil }
    if let number = value as? NSNumber {
      let double = number.doubleValue
      guard double.rounded() == double, double <= Double(Int.max), double >= Double(Int.min) else { return nil }
      return number.intValue
    }
    if let number = value as? Int { return number }
    return nil
  }

  static func int64(_ value: Any?) -> Int64? {
    guard let number = int(value) else { return nil }
    return Int64(number)
  }

  static func double(_ value: Any?) -> Double? {
    guard let value, !(value is NSNull), !isJSONBoolean(value) else { return nil }
    if let number = value as? NSNumber { return number.doubleValue }
    if let number = value as? Double { return number }
    return nil
  }

  static func isNull(_ value: Any?) -> Bool {
    value == nil || value is NSNull
  }

  static func matches(_ pattern: String, _ value: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }
}
