//
//  Location.swift
//  SwiftLint
//
//  Created by JP Simard on 2015-05-16.
//  Copyright (c) 2015 Realm. All rights reserved.
//

import SourceKittenFramework

private func < <T: Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
  }
}

public struct Location: CustomStringConvertible, Comparable {
    public let file: String?
    public let line: Int?
    public let character: Int?
    public var description: String {
        // Xcode likes warnings and errors in the following format:
        // {full_path_to_file}{:line}{:character}: {error,warning}: {content}
        let fileString: String = file ?? "<nopath>"
        let lineString: String = line.map({ ":\($0)" }) ?? ""
        let charString: String = character.map({ ":\($0)" }) ?? ""
        return [fileString, lineString, charString].joined()
    }

    public init(file: String?, line: Int? = nil, character: Int? = nil) {
        self.file = file
        self.line = line
        self.character = character
    }

    public init(file: File, byteOffset offset: Int) {
        self.file = file.path
        if let lineAndCharacter = file.contents.lineAndCharacter(forByteOffset: offset) {
            line = lineAndCharacter.line
            character = lineAndCharacter.character
        } else {
            line = nil
            character = nil
        }
    }

    public init(file: File, characterOffset offset: Int) {
        self.file = file.path
        if let lineAndCharacter = file.contents.lineAndCharacter(forCharacterOffset: offset) {
            line = lineAndCharacter.line
            character = lineAndCharacter.character
        } else {
            line = nil
            character = nil
        }
    }
}

// MARK: Comparable

public func == (lhs: Location, rhs: Location) -> Bool {
    return lhs.file == rhs.file &&
        lhs.line == rhs.line &&
        lhs.character == rhs.character
}

public func < (lhs: Location, rhs: Location) -> Bool {
    if lhs.file != rhs.file {
        return lhs.file < rhs.file
    }
    if lhs.line != rhs.line {
        return lhs.line < rhs.line
    }
    return lhs.character < rhs.character
}
