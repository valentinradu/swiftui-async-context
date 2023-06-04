@testable import AsyncBoundary
import XCTest

enum TestTask {
    case parallelTask
    case droppingTask
    case debouncedTask
}

extension TestTask: TaskIdentifier {
    var strategy: TaskQueueStrategy {
        switch self {
        case .parallelTask:
            return .parallelize
        case .droppingTask:
            return .drop
        case .debouncedTask:
            return .debounce(for: 0.25)
        }
    }
}

private actor Counter {
    private var _value: Int = 0

    var value: Int {
        _value
    }

    func increment() {
        _value += 1
    }

    func reset() {
        _value = 0
    }
}

final class AsyncBoundaryTests: XCTestCase {
    func testDroppingTask() async throws {
        let counter = Counter()
        let asyncBoundaryStorage = AsyncBoundaryStorage()
        let asyncContext = AsyncContext(storage: asyncBoundaryStorage, errorContext: .empty)

        for _ in 0 ..< 10 {
            asyncContext.perform(TestTask.droppingTask) {
                await counter.increment()
            }
        }

        await asyncBoundaryStorage.waitForAllStoredTasks()
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testParallelTask() async throws {
        let counter = Counter()
        let asyncBoundaryStorage = AsyncBoundaryStorage()
        let asyncContext = AsyncContext(storage: asyncBoundaryStorage, errorContext: .empty)

        for _ in 0 ..< 10 {
            asyncContext.perform(TestTask.parallelTask) {
                await counter.increment()
            }
        }

        await asyncBoundaryStorage.waitForAllStoredTasks()
        let count = await counter.value
        XCTAssertEqual(count, 10)
    }

    func testDebounceTask() async throws {
        let counter = Counter()
        let asyncBoundaryStorage = AsyncBoundaryStorage()
        let asyncContext = AsyncContext(storage: asyncBoundaryStorage, errorContext: .empty)

        for _ in 0 ..< 10 {
            asyncContext.perform(TestTask.debouncedTask) {
                await counter.increment()
            }
            try await Task.sleep(for: .seconds(0.1))
        }

        await asyncBoundaryStorage.waitForAllStoredTasks()
        let debouncedCount = await counter.value
        XCTAssertEqual(debouncedCount, 1)

        await counter.reset()

        for _ in 0 ..< 10 {
            asyncContext.perform(TestTask.debouncedTask) {
                await counter.increment()
            }
            try await Task.sleep(for: .seconds(0.3))
        }

        await asyncBoundaryStorage.waitForAllStoredTasks()
        let count = await counter.value
        XCTAssertEqual(count, 10)
    }
}
