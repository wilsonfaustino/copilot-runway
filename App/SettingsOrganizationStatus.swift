import Core
import SwiftUI

enum SettingsOrganizationStatus: Equatable {
  case notSet
  case unsaved
  case loading
  case found
  case notFound
  case rateLimited
  case failed(String)

  @MainActor
  init(usageStore: UsageStore, enteredText: String) {
    let enteredOrganization = GitHubOutcomesClient.normalizedOrganization(enteredText)
    if enteredOrganization != usageStore.organization {
      self = enteredOrganization == nil ? .notSet : .unsaved
    } else if usageStore.organization == nil {
      self = .notSet
    } else if usageStore.outcomes != nil {
      self = .found
    } else if let outcomesErrorKind = usageStore.outcomesErrorKind {
      switch outcomesErrorKind {
      case .organizationNotFound: self = .notFound
      case .rateLimited: self = .rateLimited
      case .ghNotFound, .notLoggedIn, .searchFailed: self = .failed(outcomesErrorKind.message)
      }
    } else {
      self = .loading
    }
  }

  var text: String {
    switch self {
    case .notSet: "Not set. Add an organization to count your PRs, reviews and commits."
    case .unsaved: "Press Return to save."
    case .loading: "Checking the organization through gh."
    case .found: "Found. Counts your PRs, reviews and commits here through gh."
    case .notFound: "Not found, or you have no access to it."
    case .rateLimited: "GitHub search rate limit reached. Retries in 30 minutes."
    case .failed(let message): message
    }
  }

  var symbolName: String? {
    switch self {
    case .notSet: "circle.dashed"
    case .unsaved: "return"
    case .loading: nil
    case .found: "checkmark.circle"
    case .notFound: "xmark.circle"
    case .rateLimited: "clock"
    case .failed: "exclamationmark.triangle"
    }
  }

  var tint: Color {
    switch self {
    case .found: Theme.accent(.healthy)
    case .notFound, .rateLimited, .failed: Theme.accent(.short)
    case .notSet, .unsaved, .loading: .secondary
    }
  }
}
