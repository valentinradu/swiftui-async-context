//
//  View+ErrorBoundary.swift
//
//
//  Created by Valentin Radu on 11/02/2023.
//

import AnyError
import SwiftUI

struct ErrorBoundaryStorage {
    private var _errors: [AnyError] = []

    mutating func append<E>(error: E) where E: Error {
        _errors.append(error.asAnyError)
    }

    mutating func remove<E>(error: E) where E: Error {
        if let i = _errors.firstIndex(of: error.asAnyError) {
            _errors.remove(at: i)
        }
    }

    var allErrors: [AnyError] {
        _errors
    }
}

private struct ErrorContextEnvironmentKey: EnvironmentKey {
    static var defaultValue: ErrorContext = .empty
}

public extension EnvironmentValues {
    var errorContext: ErrorContext {
        get { self[ErrorContextEnvironmentKey.self] }
        set { self[ErrorContextEnvironmentKey.self] = newValue }
    }
}

public struct ErrorContext {
    static let empty: ErrorContext = .init(storage: .constant(.init()))
    @Binding private var _storage: ErrorBoundaryStorage

    init(storage: Binding<ErrorBoundaryStorage>) {
        __storage = storage
    }

    public func report<E>(error: E) where E: Error {
        _storage.append(error: error)
    }

    public func dismiss<E>(error: E) where E: Error {
        _storage.remove(error: error)
    }

    public func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            _storage.append(error: error)
        }
    }

    public func lookUp<E>(error: E.Type) -> [E] where E: Error {
        _storage.allErrors.compactMap {
            $0.underlyingError as? E
        }
    }

    public var allErrors: [AnyError] {
        _storage.allErrors
    }
}

public struct ErrorBoundary<C>: View where C: View {
    @State private var _storage: ErrorBoundaryStorage = .init()
    private let _content: C

    public init(@ViewBuilder _ contentBuilder: @escaping () -> C) {
        _content = contentBuilder()
    }

    public var body: some View {
        let errorContext = ErrorContext(storage: $_storage)
        _content
            .environment(\.errorContext, errorContext)
    }
}
