//
//  View+AsyncBoundary.swift
//
//
//  Created by Valentin Radu on 10/03/2023.
//

import os
import SwiftUI
import ErrorBoundary

class AsyncBoundaryStorage: ObservableObject {
    static let empty: AsyncBoundaryStorage = .init()
    private var _tasks: [AnyHashable: Task<Void, Never>] = [:]

    func addTask<N>(id: N, value: Task<Void, Never>) where N: Hashable {
        _tasks[id] = value
    }

    func removeTask<N>(id: N) where N: Hashable {
        _tasks.removeValue(forKey: id)
    }

    func fetchTask<N>(id: N) -> Task<Void, Never>? where N: Hashable {
        _tasks[id]
    }

    @discardableResult
    func withTask<N>(id: N, perform: (Task<Void, Never>) -> Void) -> Task<Void, Never>?
        where N: Hashable {
        if let task = _tasks[id] {
            perform(task)
            return task
        } else {
            return nil
        }
    }
    
    func waitForAllStoredTasks() async -> Void {
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

private struct AsyncContextEnvironmentKey: EnvironmentKey {
    static var defaultValue: AsyncContext = .empty
}

public extension EnvironmentValues {
    var asyncContext: AsyncContext {
        get { self[AsyncContextEnvironmentKey.self] }
        set { self[AsyncContextEnvironmentKey.self] = newValue }
    }
}

public enum TaskQueueStrategy {
    case parallelize
    case drop
    case debounce(for: TimeInterval)
}

public protocol TaskIdentifier: Hashable {
    var strategy: TaskQueueStrategy { get }
}

public struct AsyncContext {
    private let _storage: AsyncBoundaryStorage
    private let _errorContext: ErrorContext
    private let _logger: Logger = .init(subsystem: "com.vansurfer.app", category: "task-context")

    static let empty: AsyncContext = .init(storage: .empty,
                                           errorContext: .empty)

    init(storage: AsyncBoundaryStorage,
         errorContext: ErrorContext) {
        _errorContext = errorContext
        _storage = storage
    }

    public func perform<N>(_ id: N,
                           action: @MainActor @escaping () async throws -> Void) where N: TaskIdentifier {
        switch id.strategy {
        case .drop:
            if _storage.fetchTask(id: id) != nil {
                return
            }
        case .debounce:
            _storage.withTask(id: id) { $0.cancel() }
        case .parallelize:
            break
        }

        let newTask = Task.detached { [_storage, _errorContext] in
            if case let .debounce(time) = id.strategy {
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
                    _storage.removeTask(id: id)
                    _errorContext.report(error: error)
                }
            }

            await MainActor.run {
                _storage.removeTask(id: id)
            }
        }

        _storage.addTask(id: id, value: newTask)
    }

    public func cancelTask<N>(id: N) where N: Hashable {
        _storage.withTask(id: id) { $0.cancel() }
    }
}

public struct TaskBoundary<C>: View where C: View {
    private let _content: C
    @StateObject private var _storage: AsyncBoundaryStorage = .empty
    @Environment(\.errorContext) private var _errorContext

    public init(@ViewBuilder _ contentBuilder: () -> C) {
        _content = contentBuilder()
    }

    public var body: some View {
        let asyncContext = AsyncContext(storage: _storage,
                                        errorContext: _errorContext)
        _content
            .environment(\.asyncContext, asyncContext)
    }
}
