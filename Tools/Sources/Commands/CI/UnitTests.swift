import ArgumentParser
import Foundation

struct UnitTests: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "unit-tests",
                                                    abstract: "Runs the unit test CI workflow: lint, unit tests, preview tests, and result collection.")
    
    @Flag(help: "Skip preview tests")
    var skipPreviews = false
    
    @Flag(help: "Run the unit tests on a saturated CPU to reproduce the flakiness of a busy CI runner.")
    var constrained = false
    
    // Artise: feature branches run the suite once (a real failure shows in one pass, not four); development keeps 3.
    @Option(help: "Number of times to retry failed unit tests.")
    var retries = 3
    
    // Artise: feature branches run only the suites that test Artise's code; none given runs every suite.
    @Option(name: .customLong("only-testing"), help: "Only run this unit test suite; repeat for several.")
    var onlyTesting: [String] = []
    
    private static let osVersion = CI.defaultOSVersion
    private static let device = "iPhone 17"
    
    func run() async throws {
        try await CI.lint()
        
        var failures: [String] = []
        
        // Run unit tests
        do {
            logger.info("\n🧪 Running unit tests…\n")
            
            var arguments = [
                "--scheme", "UnitTests",
                "--device", Self.device,
                "--os-version", Self.osVersion,
                "--retries", String(retries)
            ]
            if constrained {
                arguments.append("--constrained")
            }
            for suite in onlyTesting {
                arguments += ["--only-testing", suite]
            }
            
            try await RunTests.parse(arguments).run()
        } catch {
            failures.append("UnitTests")
            logger.error("\n❌ Unit tests failed. \(error)\n")
        }
        
        if !skipPreviews {
            do {
                try await PreviewTests.parse([]).run()
            } catch {
                failures.append("PreviewTests")
                logger.error("\n❌ Preview tests failed. \(error)\n")
            }
        }
        
        // Zip results (best-effort, useful for CI artifact uploads)
        await CI.zipResults(bundles: ["UnitTests.xcresult", "PreviewTests.xcresult"],
                            outputName: "UnitTests.zip")
        
        // Collect coverage and JUnit results for unit tests
        await CI.collectCoverage(resultBundle: "UnitTests.xcresult", outputName: "unit-cobertura.xml")
        await CI.collectTestResults(resultBundle: "UnitTests.xcresult", outputName: "unit-junit.xml")
        
        if !failures.isEmpty {
            let failedSuites = "[\(failures.joined(separator: ","))]"
            logger.error("\n❌ \(failures.count) test suite(s) failed \(failedSuites)\n")
            CI.annotateError(title: "\(failures.count) test suite(s) failed", "Failing suites: \(failedSuites). Download the artifacts for the xcresult bundles.")
            throw ExitCode.failure
        }
        
        logger.info("\n✅ All unit test suites passed.\n")
    }
}
