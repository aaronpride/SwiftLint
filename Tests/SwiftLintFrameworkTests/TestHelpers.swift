//
//  TestHelpers.swift
//  SwiftLint
//
//  Created by JP Simard on 2015-05-16.
//  Copyright (c) 2015 Realm. All rights reserved.
//

import Foundation
@testable import SwiftLintFramework
import SourceKittenFramework
import XCTest

private let violationMarker = "↓"

let allRuleIdentifiers = Array(masterRuleList.list.keys)

func violations(_ string: String, config: Configuration = Configuration()) -> [StyleViolation] {
    File.clearCaches()
    let stringStrippingMarkers = string.replacingOccurrences(of: violationMarker, with: "")
    let file = File(contents: stringStrippingMarkers)
    return Linter(file: file, configuration: config).styleViolations
}

private func cleanedContentsAndMarkerOffsets(from contents: String) -> (String, [Int]) {
    var contents = contents as NSString
    var markerOffsets = [Int]()
    var markerRange = contents.range(of: violationMarker)
    while markerRange.location != NSNotFound {
        markerOffsets.append(markerRange.location)
        contents = contents.replacingCharacters(in: markerRange, with: "") as NSString
        markerRange = contents.range(of: violationMarker)
    }
    return (contents as String, markerOffsets.sorted())
}

private func render(violations: [StyleViolation], in contents: String) -> String {
    var contents = (contents as NSString).lines().map { $0.content }
    for violation in violations.sorted(by: { $0.location > $1.location }) {
        guard let line = violation.location.line,
            let character = violation.location.character else { continue }

        let message = String(repeating: " ", count: character - 1) + "^ " + [
            "\(violation.severity.rawValue): ",
            "\(violation.ruleDescription.name) Violation: ",
            violation.reason,
            " (\(violation.ruleDescription.identifier))"].joined()
        if line >= contents.count {
            contents.append(message)
        } else {
            contents.insert(message, at: line)
        }
    }
    return (["```"] + contents + ["```"]).joined(separator: "\n")
}

private func render(locations: [Location], in contents: String) -> String {
    var contents = (contents as NSString).lines().map { $0.content }
    for location in locations.sorted(by: > ) {
        guard let line = location.line, let character = location.character else { continue }
        var content = contents[line - 1]
        let index = content.index(content.startIndex, offsetBy: character - 1)
        content.insert("↓", at: index)
        contents[line - 1] = content
    }
    return (["```"] + contents + ["```"]).joined(separator: "\n")
}

extension Configuration {
    fileprivate func assertCorrection(_ before: String, expected: String) {
        guard let path = NSURL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(NSUUID().uuidString + ".swift")?.path else {
                XCTFail("couldn't generate temporary path for assertCorrection()")
                return
        }
        let (cleanedBefore, markerOffsets) = cleanedContentsAndMarkerOffsets(from: before)
        do {
            try cleanedBefore.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("couldn't write to file for assertCorrection() with error: \(error)")
            return
        }
        guard let file = File(path: path) else {
            XCTFail("couldn't read file at path '\(path)' for assertCorrection()")
            return
        }
        // expectedLocations are needed to create before call `correct()`
        let expectedLocations = markerOffsets.map { Location(file: file, characterOffset: $0) }
        let corrections = Linter(file: file, configuration: self).correct().sorted {
            $0.location < $1.location
        }
        if expectedLocations.isEmpty {
            XCTAssertEqual(corrections.count, before != expected ? 1 : 0)
        } else {
            XCTAssertEqual(corrections.count, expectedLocations.count)
            for (correction, expectedLocation) in zip(corrections, expectedLocations) {
                XCTAssertEqual(correction.location, expectedLocation)
            }
        }
        XCTAssertEqual(file.contents, expected)
        do {
            let corrected = try String(contentsOfFile: path, encoding: .utf8)
            XCTAssertEqual(corrected, expected)
        } catch {
            XCTFail("couldn't read file at path '\(path)': \(error)")
        }
    }
}

extension String {
    fileprivate func toStringLiteral() -> String {
        return "\"" + replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}

fileprivate func makeConfig(_ ruleConfiguration: Any?, _ identifier: String) -> Configuration? {
    if let ruleConfiguration = ruleConfiguration, let ruleType = masterRuleList.list[identifier] {
        // The caller has provided a custom configuration for the rule under test
        return (try? ruleType.init(configuration: ruleConfiguration)).flatMap { configuredRule in
            return Configuration(whitelistRules: [identifier], configuredRules: [configuredRule])
        }
    }
    return Configuration(whitelistRules: [identifier])
}

extension XCTestCase {
    // swiftlint:disable:next function_body_length
    func verifyRule(_ ruleDescription: RuleDescription,
                    ruleConfiguration: Any? = nil,
                    commentDoesntViolate: Bool = true,
                    stringDoesntViolate: Bool = true) {
        guard let config = makeConfig(ruleConfiguration, ruleDescription.identifier) else {
            XCTFail()
            return
        }

        let triggers = ruleDescription.triggeringExamples
        let nonTriggers = ruleDescription.nonTriggeringExamples

        // Non-triggering examples don't violate
        for nonTrigger in nonTriggers {
            let unexpectedViolations = violations(nonTrigger, config: config)
            if unexpectedViolations.isEmpty { continue }
            let nonTriggerWithViolations = render(violations: unexpectedViolations, in: nonTrigger)
            XCTFail("nonTriggeringExample violated: \n\(nonTriggerWithViolations)")
        }

        // Triggering examples violate
        for trigger in triggers {
            let triggerViolations = violations(trigger, config: config)

            // Triggering examples with violation markers violate at the marker's location
            let (cleanTrigger, markerOffsets) = cleanedContentsAndMarkerOffsets(from: trigger)
            if markerOffsets.isEmpty {
                if triggerViolations.isEmpty {
                    XCTFail("triggeringExample did not violate: \n```\n\(trigger)\n```")
                }
                continue
            }
            let file = File(contents: cleanTrigger)
            let expectedLocations = markerOffsets.map { Location(file: file, characterOffset: $0) }

            // Assert violations on unexpected location
            let violationsAtUnexpectedLocation = triggerViolations
                .filter { !expectedLocations.contains($0.location) }
            if !violationsAtUnexpectedLocation.isEmpty {
                XCTFail("triggeringExample violate at unexpected location: \n" +
                    "\(render(violations: violationsAtUnexpectedLocation, in: trigger))")
            }

            // Assert locations missing vaiolation
            let violatedLocations = triggerViolations.map { $0.location }
            let locationsWithoutViolation = expectedLocations
                .filter { !violatedLocations.contains($0) }
            if !locationsWithoutViolation.isEmpty {
                XCTFail("triggeringExample did not violate at expected location: \n" +
                    "\(render(locations: locationsWithoutViolation, in: cleanTrigger))")
            }

            XCTAssertEqual(triggerViolations.count, expectedLocations.count)
            for (triggerViolation, expectedLocation) in zip(triggerViolations, expectedLocations) {
                XCTAssertEqual(triggerViolation.location, expectedLocation,
                               "'\(trigger)' violation didn't match expected location.")
            }
        }

        // Comment doesn't violate
        XCTAssertEqual(
            triggers.flatMap({ violations("/*\n  " + $0 + "\n */", config: config) }).count,
            commentDoesntViolate ? 0 : triggers.count
        )

        // String doesn't violate
        XCTAssertEqual(
            triggers.flatMap({ violations($0.toStringLiteral(), config: config) }).count,
            stringDoesntViolate ? 0 : triggers.count
        )

        // "disable" command doesn't violate
        let command = "// swiftlint:disable \(ruleDescription.identifier)\n"
        XCTAssert(triggers.flatMap({ violations(command + $0, config: config) }).isEmpty)

        // corrections
        ruleDescription.corrections.forEach(config.assertCorrection)
        // make sure strings that don't trigger aren't corrected
        zip(nonTriggers, nonTriggers).forEach(config.assertCorrection)

        // "disable" command do not correct
        ruleDescription.corrections.forEach { before, _ in
            let beforeDisabled = command + before
            let expectedCleaned = cleanedContentsAndMarkerOffsets(from: beforeDisabled).0
            config.assertCorrection(expectedCleaned, expected: expectedCleaned)
        }

    }

    func checkError<T: Error & Equatable>(_ error: T, closure: () throws -> () ) {
        do {
            try closure()
            XCTFail("No error caught")
        } catch let rError as T {
            if error != rError {
                XCTFail("Wrong error caught")
            }
        } catch {
            XCTFail("Wrong error caught")
        }
    }
}
