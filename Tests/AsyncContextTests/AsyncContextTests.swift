@testable import AsyncContext
import XCTest

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

@MainActor
final class AsyncContextTests: XCTestCase {
    func testDroppingTask() async throws {
        let counter = Counter()
        let asyncContextStorage = AsyncContextStorage()
        let performAsync = AsyncContext(storage: asyncContextStorage,
                                        strategy: .drop,
                                        errorContext: .empty)

        for _ in 0 ..< 10 {
            performAsync {
                await counter.increment()
            }
        }

        await asyncContextStorage.waitForAllTasks()
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testParallelTask() async throws {
        let counter = Counter()
        let asyncContextStorage = AsyncContextStorage()
        let performAsync = AsyncContext(storage: asyncContextStorage,
                                        strategy: .parallelize,
                                        errorContext: .empty)

        for _ in 0 ..< 10 {
            performAsync {
                await counter.increment()
            }
        }

        await asyncContextStorage.waitForAllTasks()
        let count = await counter.value
        XCTAssertEqual(count, 10)
    }

    func testDebounceTask() async throws {
        let counter = Counter()
        let asyncContextStorage = AsyncContextStorage()
        let performAsync = AsyncContext(storage: asyncContextStorage,
                                        strategy: .debounce(for: 0.25),
                                        errorContext: .empty)

        for _ in 0 ..< 10 {
            performAsync {
                await counter.increment()
            }
            try await Task.sleep(for: .seconds(0.1))
        }

        await asyncContextStorage.waitForAllTasks()
        let debouncedCount = await counter.value
        XCTAssertEqual(debouncedCount, 1)

        await counter.reset()

        for _ in 0 ..< 10 {
            performAsync {
                await counter.increment()
            }
            try await Task.sleep(for: .seconds(0.3))
        }

        await asyncContextStorage.waitForAllTasks()
        let count = await counter.value
        XCTAssertEqual(count, 10)
    }
}
