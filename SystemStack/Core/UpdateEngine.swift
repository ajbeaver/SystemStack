import Foundation

actor UpdateEngine {
    private var modules: [any MenuModule] = []
    private var task: Task<Void, Never>?

    func setModules(_ modules: [any MenuModule]) {
        self.modules = modules
    }

    func start(onValuesChanged: @escaping @MainActor () -> Void) {
        guard task == nil else { return }

        task = Task(priority: .utility) { [self] in
            await runLoop(onValuesChanged: onValuesChanged)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func runLoop(onValuesChanged: @escaping @MainActor () -> Void) async {
        while !Task.isCancelled {
            let snapshot = modules
            var didChange = false

            for module in snapshot where module.isEnabled && module.id != "battery" {
                if await module.update() {
                    didChange = true
                }
                await Task.yield()
            }

            if didChange {
                await MainActor.run {
                    onValuesChanged()
                }
            }

            let intervalNanoseconds = tickIntervalNanoseconds(for: snapshot)
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
            await Task.yield()
        }
    }

    private func tickIntervalNanoseconds(for modules: [any MenuModule]) -> UInt64 {
        let enabled = modules.filter { $0.isEnabled }
        guard !enabled.isEmpty else { return 10_000_000_000 }

        if enabled.contains(where: { $0.id == "cpu" || $0.id == "network" }) {
            return 1_000_000_000
        }

        if let clock = enabled.first(where: { $0.id == "clock" }) as? ClockModule,
           clock.showSeconds {
            return 1_000_000_000
        }

        if enabled.count == 1, enabled.first?.id == "battery" {
            return 10_000_000_000
        }

        return 5_000_000_000
    }
}
