import Foundation
import PromiseKit

extension Promise {
  func timeout(after seconds: TimeInterval, withError error: Error) -> Promise<T> {
    race(asVoid(), after(seconds: seconds).done {
      throw error
        }).map {
      self.value!
    }
  }
}

struct RepoDetail {
  let firstProduct: Product
  let package: Package

  init(package: Package) throws {
    guard let firstProduct = package.products.first else {
      throw PackageError.missingProducts
    }
    self.firstProduct = firstProduct
    self.package = package
  }
}

struct RepoUrlReport {
  let url: URL
  let result: Result<RepoDetail, PackageError>
}

@available(*, deprecated)
public struct ObsoleteValidator {
  // MARK: Configuration Values and Constants

  // number of validations to run simultaneously
  static let semaphoreCount = 3

  static let timeoutIntervalForRequest = 3000.0
  static let timeoutIntervalForResource = 6000.0

  // base url for github raw files
  static let rawURLComponentsBase = URLComponents(string: "https://raw.githubusercontent.com")!

  // master package list to compare against
  static let masterPackageList = rawURLComponentsBase.url!.appendingPathComponent("daveverwer/SwiftPMLibrary/master/packages.json")

  static let logEveryCount = 10

  static let httpMaximumConnectionsPerHost = 10

  static let displayProgress = false

  static let processTimeout = 10.0

  static let helpText = """
  usage: %@ <command> [path]

  COMMANDS:
    all   validate all packages in JSON packages.json
    diff  validate all new packages in JSON packages.json
    mine  validate the Package of the current directoy

  OPTIONS:
    path  to define the specific `packages.json` file or Swift package directory
  """
  static let config: URLSessionConfiguration = {
    let config: URLSessionConfiguration = .default
    config.timeoutIntervalForRequest = timeoutIntervalForRequest
    config.timeoutIntervalForResource = timeoutIntervalForResource
    config.httpMaximumConnectionsPerHost = httpMaximumConnectionsPerHost
    return config
  }()

  static let processSemaphore = DispatchSemaphore(value: semaphoreCount)

  // MARK: Functions

  /**
   Based on repository url, find the raw url to the Package.swift file.
   - Parameter gitURL: Repository URL
   - Returns: raw git URL, if successful; other `invalidURL` if not proper git repo url or `unsupportedHost` if the host is not currently supported.
   */
  static func getPackageSwiftURL(for gitURL: URL) -> Result<URL, PackageError> {
    guard let hostString = gitURL.host else {
      return .failure(.invalidURL(gitURL))
    }

    guard let host = GitHost(rawValue: hostString) else {
      return .failure(.unsupportedHost(hostString))
    }

    switch host {
    case .github:
      var rawURLComponents = ObsoleteValidator.rawURLComponentsBase
      let repositoryName = gitURL.deletingPathExtension().lastPathComponent
      let userName = gitURL.deletingLastPathComponent().lastPathComponent
      let branchName = "master"
      rawURLComponents.path = ["", userName, repositoryName, branchName, "Package.swift"].joined(separator: "/")
      guard let packageSwiftURL = rawURLComponents.url else {
        return .failure(.invalidURL(gitURL))
      }
      return .success(packageSwiftURL)
    }
  }

  static func download(_ packageSwiftURL: URL, withSession session: URLSession) -> Promise<URL> {
    Promise<Data> { resolver in
      session.dataTask(with: packageSwiftURL) {
        resolver.resolve($2, $0)
      }.resume()
    }.then { data in
      Promise { resolver in
        let result = Result { try directoryForData(data) }
        resolver.resolve(result)
      }
    }
  }

  static func directoryForData(_ data: Data) throws -> URL {
    let temporaryDirectoryURL: URL
    temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

    let outputDirURL = temporaryDirectoryURL.appendingPathComponent(UUID().uuidString)

    try FileManager.default.createDirectory(at: outputDirURL, withIntermediateDirectories: false, attributes: nil)
    try data.write(to: outputDirURL.appendingPathComponent("Package.swift"), options: .atomic)
    return outputDirURL
  }

  /**
   Creates a `Process` for dump the package metadata.
   - Parameter packageDirectoryURL: File URL to Package
   - Parameter outputTo: standard output pipe
   - Parameter errorsTo: error pipe
   */
  static func dumpPackageProcessAt(_ packageDirectoryURL: URL, outputTo pipe: Pipe, errorsTo errorPipe: Pipe) -> Process {
    let process = Process()
    process.launchPath = "/usr/bin/swift"
    process.arguments = ["package", "dump-package"]
    if #available(OSX 10.13, *) {
      process.currentDirectoryURL = packageDirectoryURL
    } else {
      process.currentDirectoryPath = packageDirectoryURL.path
    }
    process.standardOutput = pipe
    process.standardError = errorPipe
    return process
  }

  static func verifyPackageDump(at directoryURL: URL, withDecoder decoder: JSONDecoder) -> Promise<RepoDetail> {
    let pipe = Pipe()
    let errorPipe = Pipe()
    let process = dumpPackageProcessAt(directoryURL, outputTo: pipe, errorsTo: errorPipe)
    let processPromise = Promise<RepoDetail> { resolver in
      process.terminationHandler = {
        _ in

        guard process.terminationStatus == 0 else {
          let error: PackageError
          if process.terminationStatus == 15 {
            error = .dumpTimeout
          } else {
            error = .badDump(String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
          }
          resolver.reject(error)
          return
        }

        let package: Package
        do {
          package = try decoder.decode(Package.self, from: pipe.fileHandleForReading.readDataToEndOfFile())
        } catch {
          resolver.reject(PackageError.decodingError(error))
          return
        }

        let repoDetail: RepoDetail
        do {
          repoDetail = try RepoDetail(package: package)
        } catch {
          resolver.reject(error)
          return
        }

        resolver.fulfill(repoDetail)
//
//        guard package.products.count > 0 else {
//          (.missingProducts)
//          return
//        }
//        callback(nil)
      }
      processSemaphore.wait()

      debugPrint("Verifying Dump...")
      process.launch()
    }
    return processPromise.timeout(after: processTimeout, withError: PackageError.dumpTimeout).ensure {
      if process.isRunning {
        process.terminate()
        debugPrint("Verifying Dump Failed")
      }
      processSemaphore.signal()
      debugPrint("Verifying Dump Completed")
    }
  }

  static func verifyPackage(at gitURL: URL, withSession session: URLSession, usingDecoder decoder: JSONDecoder) -> Promise<RepoUrlReport> {
    firstly {
      download(gitURL, withSession: session)
    }.then { downloadURL in
      verifyPackageDump(at: downloadURL, withDecoder: decoder)
    }.map { detail in
      RepoUrlReport(url: gitURL, result: .success(detail))
    }.recover(only: PackageError.self) { error in
      Guarantee {
        $0(RepoUrlReport(url: gitURL, result: .failure(error)))
      }
    }
  }

  static func fetchMasterList(withSession session: URLSession, andDecoder decoder: JSONDecoder) -> Promise<[URL]> {
    Promise {
      resolver in
      session.dataTask(with: ObsoleteValidator.masterPackageList) {
        resolver.resolve($0, $2)
      }.resume()
    }.then {
      data in
      Promise {
        $0.resolve(Result { try decoder.decode([URL].self, from: data) })
      }
    }
  }

  static func filterRepos(_ packageUrls: [URL], withSession session: URLSession, usingDecoder decoder: JSONDecoder, includingMaster: Bool) -> Promise<[URL]> {
    Promise { resolver in
      guard !includingMaster else {
        resolver.fulfill(packageUrls)
        return
      }

      fetchMasterList(withSession: session, andDecoder: decoder).done {
        resolver.fulfill($0)
      }
//      return
//      session.dataTask(with: ObsoleteValidator.masterPackageList) { data, _, error in
//
//        let allPackageURLs: [URL]
//        guard let data = data else {
//          completion(.failure(PackageError.noResult))
//          return
//        }
//
//        if let error = error {
//          completion(.failure(error))
//          return
//        }
//
//        do {
//          allPackageURLs = try ObsoleteValidator.decoder.decode([URL].self, from: data)
//        } catch {
//          completion(.failure(error))
//          return
//        }
//        completion(.success([URL](Set<URL>(packageUrls).subtracting(allPackageURLs))))
//      }.resume()
//      filterRepos(packageUrls, withSession: session, includingMaster: includingMaster) { result in
//        resolver.resolve(result)
//      }
    }
  }

  /**
   Filters repositories based what is not listen in the master list.
   - Parameter packageUrls: current package urls
   - Parameter includingMaster: to not filter all repository url and just verify all package URLs
   */
  static func filterRepos(_: [URL], withSession _: URLSession, includingMaster _: Bool, _: @escaping ((Result<[URL], Error>) -> Void)) {}

  static func parseRepos(_ packageUrls: [URL], withSession session: URLSession, usingDecoder decoder: JSONDecoder) -> Promise<[RepoUrlReport]> {
    let promises = packageUrls.map {
      verifyPackage(at: $0, withSession: session, usingDecoder: decoder)
    }

    return when(fulfilled: promises)
  }

  /**
   Based on the directories passed and command line arguments, find the `packages.json` url.
   - Parameter directoryURLs: directory url to search for `packages.json` file
   - Parameter arguments: Command Line arguments which may contain a path to a `packages.json` file.
   */
  static func url(packagesFromDirectories directoryURLs: [URL], andArguments arguments: [String]) -> URL? {
    let possiblePackageURLs = arguments.dropFirst().compactMap { URL(fileURLWithPath: $0) } + directoryURLs.map { $0.appendingPathComponent("packages.json") }
    return possiblePackageURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) })
  }

  // MARK: Running Code

  // RunLoop.main.run()
}
