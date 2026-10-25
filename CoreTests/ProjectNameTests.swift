@testable import Core
import Foundation
import Testing

let exampleHome = "/Users/example"

// A fake disk: the .git entry of each listed folder. No test reads the real disk or home folder.
func projectName(
  directory: String?, projectRoot: String? = nil, gitEntries: [String: ProjectName.GitEntry] = [:]
) -> String {
  ProjectName.of(directory: directory, projectRoot: projectRoot, homeDirectory: exampleHome) { gitEntries[$0] }
}

@Test func openCodeProjectRootNamesTheProject() {
  let name = projectName(
    directory: "/Users/example/orca/workspaces/runway-app/fix-chart", projectRoot: "/Users/example/www/acme/runway-app",
    gitEntries: ["/Users/example/www/acme/billing-api": .directory]
  )
  #expect(name == "runway-app")
}

// The OpenCode global project has the root "/", so the folder decides.
@Test func globalProjectRootFallsBackToTheFolder() {
  #expect(projectName(directory: "/private/tmp/scratch", projectRoot: "/") == "Temporary")
  #expect(projectName(directory: exampleHome, projectRoot: "/") == "Home")
}

@Test func gitRootOnDiskNamesTheProjectFromASubfolder() {
  let name = projectName(
    directory: "/Users/example/www/acme/billing-api/packages/server",
    gitEntries: ["/Users/example/www/acme/billing-api": .directory]
  )
  #expect(name == "billing-api")
}

// A linked worktree has a .git file that points to the main repo.
@Test func gitWorktreeFileNamesTheMainRepo() {
  let name = projectName(
    directory: "/Users/example/src/runway-fix",
    gitEntries: ["/Users/example/src/runway-fix": .file(contents: "gitdir: /Users/example/www/acme/runway-app/.git/worktrees/runway-fix\n")]
  )
  #expect(name == "runway-app")
}

@Test func relativeGitWorktreeFileNamesTheMainRepo() {
  let name = projectName(
    directory: "/Users/example/www/acme/runway-app/.claude/worktrees/fix",
    gitEntries: ["/Users/example/www/acme/runway-app/.claude/worktrees/fix": .file(contents: "gitdir: ../../../.git/worktrees/fix")]
  )
  #expect(name == "runway-app")
}

// A submodule's .git file points into the parent's modules folder. The submodule is a repo of its own.
@Test func submoduleGitFileNamesTheSubmodule() {
  let name = projectName(
    directory: "/Users/example/www/acme/runway-app/vendor/charts",
    gitEntries: [
      "/Users/example/www/acme/runway-app/vendor/charts": .file(contents: "gitdir: ../../.git/modules/charts"),
      "/Users/example/www/acme/runway-app": .directory,
    ]
  )
  #expect(name == "charts")
}

// Orca removes worktree folders, so a gone folder still names its repo.
@Test func orcaWorkspaceFolderNamesTheRepo() {
  #expect(projectName(directory: "/Users/example/orca/workspaces/runway-app/PROJ-123-fix") == "runway-app")
  #expect(projectName(directory: "/Users/example/orca/workspaces/runway-app/PROJ-123-fix/App") == "runway-app")
}

// A dotfiles repo in the home folder must not name every folder below it.
@Test func gitWalkStopsBelowTheHomeFolder() {
  let gitEntries: [String: ProjectName.GitEntry] = [exampleHome: .directory, "/": .directory]
  #expect(projectName(directory: "/Users/example/orca/workspaces/runway-app/fix", gitEntries: gitEntries) == "runway-app")
  #expect(projectName(directory: "/Users/example/notes", gitEntries: gitEntries) == "notes")
  #expect(projectName(directory: "/opt/tools", gitEntries: gitEntries) == "tools")
}

@Test func lastFolderComponentNamesAFolderWithoutARepo() {
  #expect(projectName(directory: "/Users/example/www/acme/scratch") == "scratch")
  #expect(projectName(directory: "/Users/example/www/acme/scratch/") == "scratch")
}

@Test func temporaryFoldersNameTemporary() {
  #expect(projectName(directory: "/tmp") == "Temporary")
  #expect(projectName(directory: "/tmp/build") == "Temporary")
  #expect(projectName(directory: "/private/tmp/build") == "Temporary")
  #expect(projectName(directory: "/var/folders/xy/T/opencode") == "Temporary")
  #expect(projectName(directory: "/private/var/folders/xy/T/opencode") == "Temporary")
  #expect(projectName(directory: "/tmpfiles/build") == "build")
}

@Test func homeAndRootNameHome() {
  #expect(projectName(directory: exampleHome) == "Home")
  #expect(projectName(directory: "/Users/example/") == "Home")
  #expect(projectName(directory: "/") == "Home")
}

@Test func noFolderNamesUnknown() {
  #expect(projectName(directory: nil) == "Unknown folder")
}

@Test func namesLookUpEachFolderOnce() {
  let turns = [
    Turn(timestamp: fixtureCycleStart, source: .pi, directory: "/Users/example/www/acme/runway-app/App"),
    Turn(timestamp: fixtureCycleStart, source: .pi, directory: "/Users/example/www/acme/runway-app/App"),
    Turn(timestamp: fixtureCycleStart, source: .opencode, directory: "/x", projectRoot: "/Users/example/www/acme/runway-app"),
  ]
  var lookedUpFolders: [String] = []
  let name = ProjectName.names(of: turns, homeDirectory: exampleHome) { folder in
    lookedUpFolders.append(folder)
    return folder == "/Users/example/www/acme/runway-app" ? .directory : nil
  }
  #expect(turns.map(name) == ["runway-app", "runway-app", "runway-app"])
  #expect(lookedUpFolders == ["/Users/example/www/acme/runway-app/App", "/Users/example/www/acme/runway-app"])
  #expect(name(Turn(timestamp: fixtureCycleStart, source: .pi, directory: "/other")) == "Unknown folder")
}

@Test func gitEntryOnDiskReadsAGitFolderAndAGitFile() throws {
  let root = FileManager.default.temporaryDirectory.appending(path: "project-name-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }
  let checkout = root.appending(path: "checkout")
  let worktree = root.appending(path: "worktree")
  try FileManager.default.createDirectory(at: checkout.appending(path: ".git"), withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
  let gitFile = "gitdir: \(checkout.path)/.git/worktrees/worktree\n"
  try gitFile.write(to: worktree.appending(path: ".git"), atomically: true, encoding: .utf8)
  #expect(ProjectName.gitEntryOnDisk(folder: checkout.path) == .directory)
  #expect(ProjectName.gitEntryOnDisk(folder: worktree.path) == .file(contents: gitFile))
  #expect(ProjectName.gitEntryOnDisk(folder: root.path) == nil)
}

let sevenProjects = (1...7).map { ProjectCredits(name: "project-\($0)", credits: Double(80 - 10 * $0)) }

@Test func projectBreakdownFoldsAfterFiveProjects() {
  let breakdown = ProjectName.breakdown(sevenProjects)
  #expect(breakdown.items.map(\.name) == ["project-1", "project-2", "project-3", "project-4", "project-5", "Other projects"])
  #expect(breakdown.items.last?.credits == 30)
  #expect(breakdown.items.map(\.share).reduce(0, +) == 100)
  #expect(breakdown.shareTotal == 280)
}

@Test func projectBreakdownWithFiveProjectsHasNoOtherItem() {
  let breakdown = ProjectName.breakdown(Array(sevenProjects.prefix(5)))
  #expect(breakdown.items.count == 5)
  #expect(!breakdown.items.contains { $0.name == "Other projects" })
}

@Test func projectInsightUsesTheLegendShare() {
  let breakdown = ProjectName.breakdown([
    ProjectCredits(name: "runway-app", credits: 2), ProjectCredits(name: "billing-api", credits: 1),
  ])
  #expect(ProjectName.insight(breakdown) == "runway-app took 67% of local credits this cycle.")
  #expect(ProjectName.insight(ProjectName.breakdown([])) == nil)
}

// A real project can be named like the folded remainder. The remainder keeps its own id, so it stays gray and unhighlighted.
@Test func projectNamedOtherProjectsKeepsItsOwnIdentity() {
  var projects = sevenProjects
  projects[1] = ProjectCredits(name: "Other projects", credits: projects[1].credits)
  let breakdown = ProjectName.breakdown(projects)
  #expect(breakdown.items.count == 6)
  #expect(Set(breakdown.items.map(\.id)).count == 6)
  #expect(breakdown.items[1].id == .entry("Other projects"))
  #expect(breakdown.items[1].kind == .entry)
  #expect(breakdown.items[5].id == .otherProjects)
  #expect(breakdown.items[5].kind == .otherProjects)
  #expect(breakdown.items[5].name == "Other projects")
  #expect(breakdown.items.map(\.share).reduce(0, +) == 100)
}

// Isolated temporary tree. The folder names carry the meaning, so the tests call gitRoot and not the naming rule,
// which reads every temporary folder as "Temporary".
func makeSymlinkTree() throws -> (root: URL, home: URL) {
  let root = FileManager.default.temporaryDirectory.appending(path: "project-symlink-\(UUID().uuidString)")
  let home = root.appending(path: "home")
  try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
  return (root, home)
}

func makeRepo(at repo: URL) throws {
  try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: repo.appending(path: "App"), withIntermediateDirectories: true)
}

func realPath(_ url: URL) -> String {
  ProjectName.resolvedOnDisk(url.path)
}

@Test func symlinkToARepoResolvesToTheRepo() throws {
  let (root, home) = try makeSymlinkTree()
  defer { try? FileManager.default.removeItem(at: root) }
  let repo = home.appending(path: "src/billing-api")
  try makeRepo(at: repo)
  let alias = home.appending(path: "short")
  try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: repo)
  let gitRootOfAlias = ProjectName.gitRoot(of: alias.appending(path: "App").path, homeDirectory: home.path, gitEntry: ProjectName.gitEntryOnDisk)
  let gitRootOfTarget = ProjectName.gitRoot(of: repo.appending(path: "App").path, homeDirectory: home.path, gitEntry: ProjectName.gitEntryOnDisk)
  #expect(gitRootOfAlias == realPath(repo))
  #expect(gitRootOfAlias == gitRootOfTarget)
}

@Test func symlinkedAncestorResolvesToTheRepo() throws {
  let (root, home) = try makeSymlinkTree()
  defer { try? FileManager.default.removeItem(at: root) }
  let repo = home.appending(path: "src/billing-api")
  try makeRepo(at: repo)
  let linkedSource = home.appending(path: "linked")
  try FileManager.default.createSymbolicLink(at: linkedSource, withDestinationURL: home.appending(path: "src"))
  let gitRoot = ProjectName.gitRoot(
    of: linkedSource.appending(path: "billing-api/App").path, homeDirectory: home.path, gitEntry: ProjectName.gitEntryOnDisk
  )
  #expect(gitRoot == realPath(repo))
}

// The home folder holds a dotfiles repo. A link to it must stop the walk like the home folder itself.
@Test func symlinkToTheHomeFolderStopsTheGitWalk() throws {
  let (root, home) = try makeSymlinkTree()
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: home.appending(path: ".git"), withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: home.appending(path: "notes"), withIntermediateDirectories: true)
  let homeLink = root.appending(path: "homelink")
  try FileManager.default.createSymbolicLink(at: homeLink, withDestinationURL: home)
  for folder in [homeLink, homeLink.appending(path: "notes")] {
    #expect(ProjectName.gitRoot(of: folder.path, homeDirectory: home.path, gitEntry: ProjectName.gitEntryOnDisk) == nil)
  }
  // The home folder given as the link works too.
  #expect(ProjectName.gitRoot(of: home.appending(path: "notes").path, homeDirectory: homeLink.path, gitEntry: ProjectName.gitEntryOnDisk) == nil)
}

// An Orca workspace folder that is gone cannot be resolved. The recorded path still names the repo, with a home that is a symlink.
@Test func goneOrcaFolderKeepsItsRecordedPathUnderASymlinkedHome() throws {
  let (root, home) = try makeSymlinkTree()
  defer { try? FileManager.default.removeItem(at: root) }
  let homeLink = root.appending(path: "homelink")
  try FileManager.default.createSymbolicLink(at: homeLink, withDestinationURL: home)
  let goneFolder = homeLink.appending(path: "orca/workspaces/runway-app/fix").path
  #expect(ProjectName.of(directory: goneFolder, projectRoot: nil, homeDirectory: homeLink.path) == "runway-app")
}
