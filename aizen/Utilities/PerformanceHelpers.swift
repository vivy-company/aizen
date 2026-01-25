//
//  PerformanceHelpers.swift
//  aizen
//
//  Performance optimization utilities for chat and agent output views
//

import Combine
import SwiftUI

// MARK: - Memoization Cache

final class MemoCache<Key: Hashable, Value> {
    private var cache: [Key: Value] = [:]
    private let maxSize: Int
    private var accessOrder: [Key] = []
    
    init(maxSize: Int = 100) {
        self.maxSize = maxSize
    }
    
    func get(_ key: Key) -> Value? {
        if let value = cache[key] {
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
                accessOrder.append(key)
            }
            return value
        }
        return nil
    }
    
    func set(_ key: Key, value: Value) {
        if cache[key] == nil {
            if cache.count >= maxSize {
                if let oldest = accessOrder.first {
                    cache.removeValue(forKey: oldest)
                    accessOrder.removeFirst()
                }
            }
            accessOrder.append(key)
        }
        cache[key] = value
    }
    
    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
}

// MARK: - Lazy View Modifier

struct LazyView<Content: View>: View {
    let build: () -> Content
    
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    
    var body: Content {
        build()
    }
}

// MARK: - Debounced View Updates

class Debouncer: ObservableObject {
    private var workItem: DispatchWorkItem?
    private let delay: TimeInterval
    
    init(delay: TimeInterval = 0.1) {
        self.delay = delay
    }
    
    func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        let workItem = DispatchWorkItem(block: action)
        self.workItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

// MARK: - Throttled Updates

class Throttler {
    private var lastExecutionTime: Date?
    private let interval: TimeInterval
    
    init(interval: TimeInterval = 0.1) {
        self.interval = interval
    }
    
    func throttle(action: @escaping () -> Void) {
        let now = Date()
        if let lastTime = lastExecutionTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed >= interval {
                lastExecutionTime = now
                action()
            }
        } else {
            lastExecutionTime = now
            action()
        }
    }
}

// MARK: - Stable Equatable Wrapper

struct StableEquatableWrapper<Content: View, Value: Equatable>: View, Equatable {
    let content: Content
    let value: Value
    
    init(value: Value, @ViewBuilder content: () -> Content) {
        self.value = value
        self.content = content()
    }
    
    var body: some View {
        content
    }
    
    static func == (lhs: StableEquatableWrapper<Content, Value>, rhs: StableEquatableWrapper<Content, Value>) -> Bool {
        lhs.value == rhs.value
    }
}

// MARK: - View Modifiers

extension View {
    func equatable<Value: Equatable>(by value: Value) -> some View {
        StableEquatableWrapper(value: value) { self }
    }
    
    func onFirstAppear(perform action: @escaping () -> Void) -> some View {
        modifier(FirstAppearModifier(action: action))
    }
}

private struct FirstAppearModifier: ViewModifier {
    let action: () -> Void
    @State private var hasAppeared = false
    
    func body(content: Content) -> some View {
        content.onAppear {
            if !hasAppeared {
                hasAppeared = true
                action()
            }
        }
    }
}

// MARK: - Cached Computation

@propertyWrapper
struct Cached<Value> {
    private var value: Value?
    private var computation: () -> Value
    
    init(wrappedValue: @autoclosure @escaping () -> Value) {
        self.computation = wrappedValue
    }
    
    var wrappedValue: Value {
        mutating get {
            if let value = value {
                return value
            }
            let computed = computation()
            value = computed
            return computed
        }
    }
    
    mutating func invalidate() {
        value = nil
    }
}

// MARK: - Async Image Loading

@MainActor
class AsyncImageLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var isLoading = false
    
    private static let cache = NSCache<NSString, NSImage>()
    
    func load(from path: String) {
        let key = path as NSString
        
        if let cached = Self.cache.object(forKey: key) {
            self.image = cached
            return
        }
        
        isLoading = true
        
        Task {
            let loadedImage = await Task.detached(priority: .background) {
                NSImage(contentsOfFile: path)
            }.value
            
            if let image = loadedImage {
                Self.cache.setObject(image, forKey: key)
                self.image = image
            }
            self.isLoading = false
        }
    }
}

// MARK: - Syntax Highlighting Cache

actor SyntaxHighlightCache {
    static let shared = SyntaxHighlightCache()
    
    private var cache: [String: AttributedString] = [:]
    private let maxSize = 50
    
    func get(key: String) -> AttributedString? {
        cache[key]
    }
    
    func set(key: String, value: AttributedString) {
        if cache.count >= maxSize {
            let keysToRemove = Array(cache.keys.prefix(10))
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }
        cache[key] = value
    }
    
    func clear() {
        cache.removeAll()
    }
}

// MARK: - Performance Measurement

struct PerformanceTimer {
    private let startTime: CFAbsoluteTime
    private let label: String
    
    init(_ label: String) {
        self.label = label
        self.startTime = CFAbsoluteTimeGetCurrent()
    }
    
    func elapsed() -> TimeInterval {
        CFAbsoluteTimeGetCurrent() - startTime
    }
    
    func log() {
        #if DEBUG
        let elapsed = self.elapsed()
        if elapsed > 0.016 {
            print("⚠️ [\(label)] took \(String(format: "%.2f", elapsed * 1000))ms")
        }
        #endif
    }
}
