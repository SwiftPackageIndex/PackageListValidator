import Foundation
import PromiseKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct SwiftPackageReporter {
  let downloader: PackageDownloader = TemporaryPackageDownloader()
  let parser: PackageParser = ProcessPackageParser()
  func verifyPackage(at gitURL: URL, withSession session: URLSession, usingDecoder decoder: JSONDecoder) -> Promise<SwiftPackageReport> {
    firstly {
      self.downloader.download(gitURL, withSession: session)
    }.then { downloadURL in
      self.parser.verifyPackageDump(at: downloadURL, withDecoder: decoder)
    }.map { detail in
      debugPrint("Verified \(gitURL)")
      return SwiftPackageReport(url: gitURL, result: .success(detail))
    }.recover(only: PackageError.self) { error -> Guarantee<SwiftPackageReport> in
      debugPrint("Failed \(gitURL): \(error.friendlyName)")
      return Guarantee {
        $0(SwiftPackageReport(url: gitURL, result: .failure(error)))
      }
    }
  }
}

public extension SwiftPackageReporter {
  func parseRepos(_ packageUrls: [URL], withSession session: URLSession, usingDecoder decoder: JSONDecoder) -> Promise<[SwiftPackageReport]> {
    let promises = packageUrls.map {
      self.verifyPackage(at: $0, withSession: session, usingDecoder: decoder)
    }

    return when(fulfilled: promises)
  }
}