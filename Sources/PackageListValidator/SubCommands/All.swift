import ArgumentParser
import Foundation
import PromiseKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct All: ParsableCommand {
  public static var configuration
    = CommandConfiguration(abstract: "Verify every package in the JSON file.")

  @Argument(default: "packages.json", help: "Path to the JSON file containing the repository list")
  var path: String?

  public init() {}

  public func run() throws {
    let session: URLSession = URLSession(configuration: Configuration.default.config)
    let decoder = JSONDecoder()
    let packageListJsonURLParser: PackageListJsonURLParserProtocol = PackageListJsonURLParser()
    let listValidators: [ListValidator] = [GitUrlListValidator(), SortedListValidator(), UniqueListValidator()]

    let currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    // Find the "packages.json" file based on arguments, current directory, or the directory of the script
    let packagesJsonURL = packageListJsonURLParser.url(
      packagesFromDirectories: [
        currentDirectoryURL,
        URL(fileURLWithPath: #file).deletingLastPathComponent()
      ], andPath: path
    )

    // Based on arguments find the `package.json` file
    guard let url = packagesJsonURL else {
      throw ValidationError("Unable to find packages.json to validate.")
    }

    let packageUrls: [URL]
    do {
      let data = try Data(contentsOf: url)
      packageUrls = try decoder.decode([URL].self, from: data)
    } catch {
      Self.exit(withError: error)
    }

    let errors = listValidators.compactMap {
      $0.validateUrls(packageUrls)
    }

    if let error = ListValidationError(errors: errors) {
      Self.exit(withError: error)
    }

    print(listValidators.map {
      type(of: $0)
        .successDescription
        .padding(toLength: 25, withPad: " ", startingAt: 0) + "\u{001B}[32m✓\u{001B}[0m"
    }
    .joined(separator: "\n"))

    print("Checking each url for valid package dump\u{001B}[5m...\u{001B}[0m")
    var status = Status(totalCount: packageUrls.count)
    let filter = PackageFilter(type: .none)
    let reporter = SwiftPackageReporter(downloader: TemporaryPackageDownloader(branchQuery: JustBranchQuery(branchName: "master"))) { report in
      var output = FileHandle.standardOutput as TextOutputStream
      status.update(with: report, to: &output)
    }
    _ = firstly {
      filter.filterRepos(packageUrls, withSession: session, usingDecoder: decoder)
    }.then { urls in
      reporter.parseRepos(urls, withSession: session, usingDecoder: decoder)
    }.done { reports in

      let error = ReportError(reports)

      if error == nil {
        print("Validation Successful.")
      }

      Self.exit(withError: error)
    }

    RunLoop.main.run()
  }
}
