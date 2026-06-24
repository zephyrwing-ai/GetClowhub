#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let authURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Services")
    .appendingPathComponent("AuthManager.swift")

let source = try String(contentsOf: authURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func block(startingWith signature: String, in text: String) -> String {
    guard let start = text.range(of: signature) else {
        fatalError("Could not find \(signature)")
    }

    var depth = 0
    var hasEnteredBody = false
    var index = start.lowerBound

    while index < text.endIndex {
        let char = text[index]
        if char == "{" {
            depth += 1
            hasEnteredBody = true
        } else if char == "}" {
            depth -= 1
            if hasEnteredBody && depth == 0 {
                return String(text[start.lowerBound...index])
            }
        }
        index = text.index(after: index)
    }

    fatalError("Could not extract block for \(signature)")
}

let configBlock = block(startingWith: "enum AuthConfig", in: source)
let checkOnLaunchBlock = block(startingWith: "func checkOnLaunch()", in: source)
let refreshBlock = block(startingWith: "func refreshTokenIfNeeded()", in: source)

require(
    configBlock.contains("launchCheckTimeout"),
    "AuthConfig should define a launch-check timeout so login overlay cannot stay in checking forever."
)
require(
    checkOnLaunchBlock.contains("withTimeout(seconds: AuthConfig.launchCheckTimeout") &&
        checkOnLaunchBlock.contains("state = .notLoggedIn"),
    "checkOnLaunch should bound token refresh and settle to notLoggedIn on timeout or refresh failure."
)
require(
    refreshBlock.contains("request.timeoutInterval = AuthConfig.launchCheckTimeout"),
    "refreshTokenIfNeeded should set a URLRequest timeout for launch-time refresh."
)

print("Auth launch-check timeout verification passed")
