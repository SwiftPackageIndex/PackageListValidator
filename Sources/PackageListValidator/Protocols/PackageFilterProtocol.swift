import Foundation
import PromiseKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/**
 Filters the urls in an array based another list (i.e. master list).
 */
public protocol PackageFilterProtocol {
  /**
   Filters the urls in an array based another list (i.e. master list).
   - Parameter packageUrls: The list to filter.
   - Parameter session: The session to read the other list from.
   - Parameter decoder: The JSONDecoder
   - Parameter completed: The callback made when the result is received.
   */
  func filterRepos<SessionType: Session>(
    _ packageUrls: [URL],
    withSession session: SessionType,
    usingDecoder decoder: JSONDecoder,
    _ completed: @escaping (Result<[URL], Error>) -> Void
  )
}

public extension PackageFilterProtocol {
  func filterRepos<SessionType: Session>(
    _ packageUrls: [URL],
    withSession session: SessionType,
    usingDecoder decoder: JSONDecoder
  ) -> Promise<[URL]> {
    Promise<[URL]> { resolver in
      self.filterRepos(packageUrls, withSession: session, usingDecoder: decoder) {
        resolver.resolve($0)
      }
    }
  }
}
