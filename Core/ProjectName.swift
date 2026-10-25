import Foundation

// The project of a session, named from its folders without reading any message. See Core/README.md for the rule.
public enum ProjectName {
  public static let temporary = "Temporary"
  public static let home = "Home"
  // A turn without a folder, for example from an OpenCode database without session_v2.
  public static let unknown = "Unknown folder"
  public static let otherProjectsName = "Other projects"
  // The dashboard By project card names the top projects and folds the rest into "Other projects".
  public static let namedProjectLimit = 5
  static let temporaryFolders = ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"]
  static let orcaWorkspaces = "orca/workspaces"

  // What a folder holds at .git: a folder in a main checkout, a file in a linked worktree or a submodule.
  public enum GitEntry: Equatable, Sendable {
    case directory
    case file(contents: String)
  }

  // In order: the OpenCode project root, the git root on disk, the Orca workspace rule, the last folder component.
  // A project root of "/" is the OpenCode global project (no repo), so the folder decides instead.
  public static func of(
    directory: String?,
    projectRoot: String?,
    homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
    gitEntry: (String) -> GitEntry? = gitEntryOnDisk(folder:)
  ) -> String {
    let home = trimmed(homeDirectory)
    if let projectRoot, trimmed(projectRoot) != "/" {
      return name(of: trimmed(projectRoot), homeDirectory: home)
    }
    guard let directory else { return unknown }
    let folder = trimmed(directory)
    if let gitRoot = gitRoot(of: folder, homeDirectory: home, gitEntry: gitEntry) {
      return name(of: gitRoot, homeDirectory: home)
    }
    // The recorded path, not the resolved one, because a gone Orca folder has no disk to resolve.
    if let orcaRepo = orcaRepo(of: folder, homeDirectory: home) {
      return orcaRepo
    }
    return name(of: resolvedOnDisk(folder), homeDirectory: resolvedOnDisk(home))
  }

  // Names each distinct folder of turns once, so the git walk runs once per folder and not once per turn.
  // A turn that is not in turns gets "Unknown folder".
  public static func names(
    of turns: [Turn],
    homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
    gitEntry: (String) -> GitEntry? = gitEntryOnDisk(folder:)
  ) -> @Sendable (Turn) -> String {
    var namesByFolder: [Folder: String] = [:]
    for turn in turns where namesByFolder[Folder(turn)] == nil {
      namesByFolder[Folder(turn)] = of(
        directory: turn.directory, projectRoot: turn.projectRoot, homeDirectory: homeDirectory, gitEntry: gitEntry
      )
    }
    return { [namesByFolder] turn in namesByFolder[Folder(turn)] ?? unknown }
  }

  // The nearest folder with a .git entry, from folder up to but not including the home folder and "/".
  // Many users keep a dotfiles repo in the home folder, and it must not swallow every folder below it.
  // A linked worktree's .git file points to the main repo, so a worktree counts with its repo.
  // Symlinks of folders that exist are resolved first, so an alias and its target are one repo and a link to
  // the home folder stops the walk like the home folder.
  static func gitRoot(of folder: String, homeDirectory: String, gitEntry: (String) -> GitEntry?) -> String? {
    let realHome = resolvedOnDisk(homeDirectory)
    var current = resolvedOnDisk(folder)
    while current != "/", current != realHome, !current.isEmpty {
      switch gitEntry(current) {
      case .directory:
        return current
      case .file(let contents):
        return mainRepoRoot(gitFileContents: contents, folder: current) ?? current
      case nil:
        current = parent(of: current)
      }
    }
    return nil
  }

  // "gitdir: <repo>/.git/worktrees/<name>" gives <repo>. A relative gitdir is relative to folder.
  // nil for any other gitdir, for example a submodule, which is a repo of its own.
  static func mainRepoRoot(gitFileContents: String, folder: String) -> String? {
    let gitDirPrefix = "gitdir:"
    guard let gitDirLine = gitFileContents.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix(gitDirPrefix) })
    else { return nil }
    let gitDir = gitDirLine.dropFirst(gitDirPrefix.count).trimmingCharacters(in: .whitespaces)
    let absoluteGitDir = gitDir.hasPrefix("/") ? gitDir : URL(fileURLWithPath: folder + "/" + gitDir).standardized.path
    guard let worktreesRange = absoluteGitDir.range(of: "/.git/worktrees/") else { return nil }
    return String(absoluteGitDir[..<worktreesRange.lowerBound])
  }

  // ~/orca/workspaces/<repo>/<branch> gives <repo>. Orca removes these folders, so the rule needs no disk.
  static func orcaRepo(of folder: String, homeDirectory: String) -> String? {
    let workspacesPrefix = homeDirectory + "/" + orcaWorkspaces + "/"
    guard folder.hasPrefix(workspacesPrefix) else { return nil }
    return folder.dropFirst(workspacesPrefix.count).split(separator: "/").first.map(String.init)
  }

  static func name(of folder: String, homeDirectory: String) -> String {
    if temporaryFolders.contains(where: { folder == $0 || folder.hasPrefix($0 + "/") }) { return temporary }
    if folder == homeDirectory || folder == "/" { return home }
    return folder.split(separator: "/").last.map(String.init) ?? home
  }

  // The real path of a folder that exists. A folder that is gone keeps its recorded path.
  static func resolvedOnDisk(_ folder: String) -> String {
    guard let resolvedPath = realpath(folder, nil) else { return folder }
    defer { free(resolvedPath) }
    return String(cString: resolvedPath)
  }

  public static func gitEntryOnDisk(folder: String) -> GitEntry? {
    let gitPath = folder + "/.git"
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory) else { return nil }
    if isDirectory.boolValue { return .directory }
    return .file(contents: (try? String(contentsOfFile: gitPath, encoding: .utf8)) ?? "")
  }

  // Projects by credits, the top namedProjectLimit by name and the rest as "Other projects". Shares are of the
  // local total, allocated like every other split bar.
  public static func breakdown(_ projectCredits: [ProjectCredits]) -> ShareBreakdown {
    let namedEntries = projectCredits.prefix(namedProjectLimit).map { (name: $0.name, credits: $0.credits) }
    let otherCredits = projectCredits.dropFirst(namedProjectLimit).reduce(0) { $0 + $1.credits }
    return ShareBreakdown.projects(
      entries: namedEntries, other: projectCredits.count > namedProjectLimit ? (otherProjectsName, otherCredits) : nil
    )
  }

  // "Project A took 67% of local credits this cycle.", with the percent the legend shows. nil without credits.
  public static func insight(_ breakdown: ShareBreakdown) -> String? {
    guard !breakdown.isEmpty, let topProject = breakdown.items.first else { return nil }
    return "\(topProject.name) took \(Credits.shareLabel(percent: topProject.share, of: topProject.credits)) of local credits this cycle."
  }

  private struct Folder: Hashable {
    let directory: String?
    let projectRoot: String?

    init(_ turn: Turn) {
      directory = turn.directory
      projectRoot = turn.projectRoot
    }
  }

  private static func trimmed(_ path: String) -> String {
    path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }

  private static func parent(of folder: String) -> String {
    let parentFolder = (folder as NSString).deletingLastPathComponent
    return parentFolder.isEmpty ? "/" : parentFolder
  }
}
