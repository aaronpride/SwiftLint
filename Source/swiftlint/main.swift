//
//  main.swift
//  SwiftLint
//
//  Created by JP Simard on 2015-05-16.
//  Copyright (c) 2015 Realm. All rights reserved.
//

import Foundation
import Commandant
import SwiftLintFramework

DispatchQueue.global().async {
    let registry = CommandRegistry<CommandantError<()>>()
    registry.register(LintCommand())
    registry.register(AutoCorrectCommand())
    registry.register(VersionCommand())
    registry.register(RulesCommand())
    registry.register(HelpCommand(registry: registry))

    registry.main(defaultVerb: LintCommand().verb) { error in
        queuedPrintError(String(describing: error))
    }
}

dispatchMain()
