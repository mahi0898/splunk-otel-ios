//
/*
Copyright 2021 Splunk Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import Foundation

let MAX_SESSION_AGE_SECONDS = 4 * 60 * 60

private var rumSessionId = generateNewSessionId()
private var sessionIdExpiration = Date().addingTimeInterval(TimeInterval(MAX_SESSION_AGE_SECONDS))
private let sessionIdLock = NSLock()
private var sessionIdCallbacks: [(() -> Void)] = []
private var isSessionIdChanged = false
private var oldRumSessionId = ""

func generateNewSessionId() -> String {
    var i=0
    var answer = ""
    while i < 16 {
        i += 1
        let b = Int.random(in: 0..<256)
        answer += String(format: "%02x", b)
    }
    if !oldRumSessionId.isEmpty { // firtst time id generated so it is not consider as session id changed
        isSessionIdChanged = true
    }
    return answer
}

func addSessionIdCallback(_ callback: @escaping (() -> Void)) {
    sessionIdLock.lock()
    defer {
        sessionIdLock.unlock()
    }
    sessionIdCallbacks.append(callback)
}

func getRumSessionId() -> String {
    sessionIdLock.lock()
    var unlocked = false
    var callbacks: [(() -> Void)] = []
    defer {
        if !unlocked {
            sessionIdLock.unlock()
        }
    }
    if Date() > sessionIdExpiration {
        sessionIdExpiration = Date().addingTimeInterval(TimeInterval(MAX_SESSION_AGE_SECONDS))
        oldRumSessionId = rumSessionId
        rumSessionId = generateNewSessionId()
        callbacks = sessionIdCallbacks
    }
    sessionIdLock.unlock()
    unlocked = true
    for callback in callbacks {
        callback()
    }
    if isSessionIdChanged {
        createSessionIdChangeSpan()
    }
    return rumSessionId
}
func createSessionIdChangeSpan() {
    isSessionIdChanged = false
    let now = Date()
    let tracer = buildTracer()
    let span = tracer.spanBuilder(spanName: "sessionId.change").setStartTime(time: now).startSpan()
    span.setAttribute(key: "splunk.rum.previous_session_id", value: oldRumSessionId)
    span.end(time: now)
}
