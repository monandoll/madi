import Foundation

/// 이 Mac 이 지금 **무거운 일을 얼마나 받을 수 있나.** 발열 · 메모리 압박 · 사양을 보고 앱이 스스로 속도를 조절한다.
///
/// 칩이 뜨거워지는 것 자체는 앱이 막을 수 없다. 대신 macOS 가 강제로 확 느리게 만들기(스로틀링) **전에**
/// 앱이 먼저 덜 일한다 — 팬 없는 맥북 에어 · 8GB 맥에서도 맥이 버벅이거나 멈추지 않게.
/// 2026-09-29 에 개발 맥(32GB)이 메모리 바닥으로 두 번 재부팅된 뒤 넣었다.
///
/// | 단계 | 언제 | 무엇을 줄이나 |
/// |---|---|---|
/// | `full` | 보통 | 받아적기와 영상 읽기를 동시에 · 분석과 영상 만들기도 동시에 |
/// | `eased` | 약간 뜨거움 · 저전력 모드 · 메모리 8GB 이하 | 무거운 일을 **하나씩** |
/// | `gentle` | 뜨거움 · 메모리 경고 | 하나씩 + 일한 만큼 쉬어 간다 (절반만 일한다) |
/// | `paused` | 위험 · 메모리 위험 | 식을 때까지 새 일을 시작하지 않고, 하던 일도 멈춰 기다린다 |
public enum LoadLevel: Int, Comparable, Sendable {
    case full, eased, gentle, paused
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum MemoryPressure: Int, Sendable { case normal, warning, critical }

/// 단계를 정하는 재료.
public struct LoadInputs: Hashable, Sendable {
    /// `ProcessInfo.ThermalState.rawValue` — 0 보통 · 1 약간 · 2 뜨거움 · 3 위험.
    public var thermal: Int
    public var lowPower: Bool
    public var memory: MemoryPressure
    public var physicalMemoryGB: Double

    public init(thermal: Int, lowPower: Bool, memory: MemoryPressure, physicalMemoryGB: Double) {
        self.thermal = thermal; self.lowPower = lowPower; self.memory = memory; self.physicalMemoryGB = physicalMemoryGB
    }
}

public final class LoadGovernor: @unchecked Sendable {
    public static let shared = LoadGovernor()

    private let lock = NSLock()
    private var pressure: MemoryPressure = .normal
    private var forced: LoadLevel?
    private let source: DispatchSourceMemoryPressure

    init() {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical],
                                                         queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source.data
            let value: MemoryPressure = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
            self.lock.withLock { self.pressure = value }
        }
        source.resume()
    }

    /// 시험용 — 스파이크 · 판정이 단계를 강제로 정한다 (`MADI_LOAD_LEVEL`). 앱은 쓰지 않는다.
    public var override: LoadLevel? {
        get { lock.withLock { forced } }
        set { lock.withLock { forced = newValue } }
    }

    public var inputs: LoadInputs {
        let info = ProcessInfo.processInfo
        return LoadInputs(thermal: info.thermalState.rawValue, lowPower: info.isLowPowerModeEnabled,
                          memory: lock.withLock { pressure },
                          physicalMemoryGB: Double(info.physicalMemory) / 1_073_741_824)
    }

    public var level: LoadLevel { override ?? Self.level(inputs) }

    /// 화면에 "맥 식히는 중" 을 띄울지 — 쉬어 가거나 멈춰 기다리는 중.
    public var isCooling: Bool { level >= .gentle }

    public static func level(_ i: LoadInputs) -> LoadLevel {
        if i.thermal >= 3 || i.memory == .critical { return .paused }
        if i.thermal == 2 || i.memory == .warning { return .gentle }
        if i.thermal == 1 || i.lowPower || i.physicalMemoryGB <= 8.5 { return .eased }
        return .full
    }

    /// 무거운 반복 사이에 부른다. `gentle` 이면 방금 일한 만큼 쉬고(절반만 일한다),
    /// `paused` 면 식을 때까지 기다린다. 작업이 취소되면 바로 돌아간다.
    public func breathe(worked: TimeInterval) async {
        switch level {
        case .full, .eased:
            return
        case .gentle:
            try? await Task.sleep(for: .seconds(min(max(worked, 0.005), 0.5)))
        case .paused:
            while level == .paused, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
