//
//  View+AsyncContext.swift
//
//
//  Created by Valentin Radu on 10/03/2023.
//

import ErrorBoundary
import os
import SwiftUI

public enum AsyncContextStrategy: Sendable, Hashable {
    case parallelize
    case drop
    case debounce(for: TimeInterval)
}

public final class AsyncContextStorage {
    private var _tasks: [UUID: Task<Void, Never>] = [:]

    var isEmpty: Bool {
        _tasks.isEmpty
    }

    func add(id: UUID, task: Task<Void, Never>) {
        _tasks[id] = task
    }

    func remove(id: UUID) {
        _tasks.removeValue(forKey: id)
    }

    func cancelAll() {
        for (_, task) in _tasks {
            task.cancel()
        }
    }

    func waitForAllTasks() async {
        await withTaskGroup(of: Void.self) { group in
            for (_, task) in _tasks {
                group.addTask {
                    await task.value
                }
            }
        }
    }

    deinit {
        for (_, task) in _tasks {
            task.cancel()
        }
    }
}

@MainActor
public struct AsyncContext {
    private let _storage: AsyncContextStorage
    private let _errorContext: ErrorContext
    private let _strategy: AsyncContextStrategy
    private let _logger: Logger = .init(subsystem: "com.asynccontext", category: "task")

    init(storage: AsyncContextStorage,
         strategy: AsyncContextStrategy,
         errorContext: ErrorContext) {
        _errorContext = errorContext
        _strategy = strategy
        _storage = storage
    }

    public func perform(action: @MainActor @Sendable @escaping () async throws -> Void) {
        switch _strategy {
        case .drop:
            if !_storage.isEmpty {
                return
            }
        case .debounce:
            _storage.cancelAll()
        case .parallelize:
            break
        }

        let id: UUID = .init()
        let newTask = Task {
            if case let .debounce(time) = _strategy {
                do {
                    try await Task.sleep(for: .seconds(time))
                    try Task.checkCancellation()
                } catch {
                    return
                }
            }

            do {
                try await action()
            } catch {
                _logger.error("\(error)")
                await MainActor.run {
                    _storage.remove(id: id)
                    _errorContext.report(error: error)
                }
            }

            _storage.remove(id: id)
        }

        _storage.add(id: id, task: newTask)
    }
}

public struct AsyncContextReader<C>: View where C: View {
    public typealias ContentProvider = (AsyncContext) -> C
    @Environment(\.errorContext) private var _errorContext
    @State private var _state: AsyncContextStorage = .init()
    private let _strategy: AsyncContextStrategy
    private let _action: ContentProvider

    public init(strategy: AsyncContextStrategy = .drop, 
                @ViewBuilder action: @escaping ContentProvider) {
        _strategy = strategy
        _action = action
    }

    public var body: some View {
        let context = AsyncContext(storage: _state,
                                   strategy: _strategy,
                                   errorContext: _errorContext)
        _action(context)
    }
}
