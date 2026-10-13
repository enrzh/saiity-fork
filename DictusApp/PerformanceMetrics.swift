import Foundation
import MetricKit
import SyllivraKernel

/// Registers MetricKit once per app process and records aggregated performance data.
///
/// MetricKit delivers daily payloads on a background queue, so this subscriber adds
/// no work to the dictation or keyboard interaction paths. The compact log summaries
/// make CPU, memory, launch, hang, crash, and disk-write regressions inspectable in
/// device logs without persisting user content or full call stacks.
final class PerformanceMetricsSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = PerformanceMetricsSubscriber()

    private override init() {
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            var fields = ["version=\(payload.latestApplicationVersion)"]

            if let cpu = payload.cpuMetrics {
                let seconds = cpu.cumulativeCPUTime.converted(to: .seconds).value
                fields.append("cpuSeconds=\(format(seconds))")
            }
            if let memory = payload.memoryMetrics {
                let megabytes = memory.peakMemoryUsage.converted(to: .megabytes).value
                fields.append("peakMemoryMB=\(format(megabytes))")
            }
            if let launch = payload.applicationLaunchMetrics {
                fields.append("launchBuckets=\(launch.histogrammedTimeToFirstDraw.totalBucketCount)")
            }
            if let responsiveness = payload.applicationResponsivenessMetrics {
                fields.append("hangBuckets=\(responsiveness.histogrammedApplicationHangTime.totalBucketCount)")
            }

            DictusLogger.app.info(
                "MetricKit metrics \(fields.joined(separator: " "), privacy: .public)"
            )
            PersistentLog.log(.diagnosticProbe(component: "MetricKit", instanceID: payload.latestApplicationVersion,
                                             action: "dailyMetrics", details: fields.joined(separator: " ")))
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let hangs = payload.hangDiagnostics?.count ?? 0
            let crashes = payload.crashDiagnostics?.count ?? 0
            let launches = payload.appLaunchDiagnostics?.count ?? 0
            let cpuExceptions = payload.cpuExceptionDiagnostics?.count ?? 0
            let diskWriteExceptions = payload.diskWriteExceptionDiagnostics?.count ?? 0

            DictusLogger.app.error(
                "MetricKit diagnostics hangs=\(hangs) crashes=\(crashes) launches=\(launches) cpuExceptions=\(cpuExceptions) diskWriteExceptions=\(diskWriteExceptions)"
            )
            PersistentLog.log(.diagnosticProbe(component: "MetricKit", instanceID: "daily",
                                             action: "diagnostics",
                                             details: "hangs=\(hangs) crashes=\(crashes) launches=\(launches) cpuExceptions=\(cpuExceptions) diskWriteExceptions=\(diskWriteExceptions)"))
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
