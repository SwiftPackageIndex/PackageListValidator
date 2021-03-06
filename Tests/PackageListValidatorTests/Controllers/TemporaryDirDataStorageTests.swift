import PackageListValidator
#if !os(watchOS)
  import XCTest

  final class TemporaryDirDataStorageTests: XCTestCase {
    func testDirectoryUrl() {
      let url = URL.fileRandom()
      let expectedData = Data.random()
      let storage = TemporaryDirDataStorage { () -> (URL) in
        url
      }
      let result: URL
      do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        result = try storage.directoryUrl(forSavingData: expectedData)
      } catch {
        XCTAssertNil(error)
        return
      }

      let actualData: Data
      do {
        actualData = try Data(contentsOf: result.appendingPathComponent("Package.swift"))
      } catch {
        XCTAssertNil(error)
        return
      }
      let directory = result.deletingLastPathComponent().lastPathComponent

      let actual = result.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(directory, isDirectory: false)
      XCTAssertEqual(actual, url)
      XCTAssertEqual(expectedData, actualData)
    }
  }
#endif
