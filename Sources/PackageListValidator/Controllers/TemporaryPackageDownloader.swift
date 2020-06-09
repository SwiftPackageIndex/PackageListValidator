import Foundation
import PromiseKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct TemporaryPackageDownloader: PackageDownloader {
  let branchQuery: DefaultBranchQuery
  let urlFetcher: PackageUrlFetcherProtocol = PackageUrlFetcher()
  let tempDataStorage: TemporaryDataStorage = TemporaryDirDataStorage()

  public func download(_ packageSwiftURL: URL, withSession session: URLSession) -> Promise<URL> {
    urlFetcher.getPackageSwiftURL(for: packageSwiftURL, resolvingWith: branchQuery).then { url in
      Promise<Data> { resolver in
        // debugPrint("Downloading \(url)...")
        session.dataTask(with: url) {
          resolver.resolve($2, $0)
          // debugPrint("Downloaded \(url)...")
        }.resume()
      }
    }.then { data in
      Promise<URL> { resolver in
        let result = Result { try self.tempDataStorage.directoryUrl(forSavingData: data) }
        resolver.resolve(result)
      }
    }.then { url in
      after(seconds: 10.0).map {
        url
      }
    }
  }
}