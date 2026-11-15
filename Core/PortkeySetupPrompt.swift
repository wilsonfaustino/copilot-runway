import Foundation

// A prompt the user pastes into an AI agent so the agent adds Portkey model prices to its config. Portkey has no
// price API, so agents store a cost only for models priced in their own config.
public enum PortkeySetupPrompt {
  public static let disclaimer = "This prompt asks your AI agent to change its config files. "
    + "Copilot Runway is not responsible for what the agent does. Check each change before you accept it."

  private static let agents: [(source: SessionSource, name: String, section: String)] = [
    (.pi, "Pi", piSection),
    (.opencode, "OpenCode", openCodeSection),
    (.omp, "omp", ompSection),
  ]

  // Ids sorted, per agent. A model counts when its newest record from that agent has no cost, so a model priced
  // after some unpriced requests does not count. Ids with a backtick or a control character are skipped: in the
  // prompt they could close the inline code and add instructions for the agent.
  public static func unpricedModels(in records: [PortkeyRecord]) -> [SessionSource: [String]] {
    let newestRecords = Dictionary(grouping: records) { "\($0.source.rawValue)\u{0}\($0.model)" }
      .compactMap { $0.value.max { $0.timestamp < $1.timestamp } }
    return Dictionary(grouping: newestRecords.filter { $0.costUSD == nil && isSafeInPrompt($0.model) }, by: \.source)
      .mapValues { $0.map(\.model).sorted() }
  }

  private static func isSafeInPrompt(_ model: String) -> Bool {
    !model.contains("`") && model.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }

  // With no unpriced model: every agent section and placeholders only.
  public static func text(records: [PortkeyRecord]) -> String {
    let unpricedModels = unpricedModels(in: records)
    let shownAgents = unpricedModels.isEmpty ? agents : agents.filter { unpricedModels[$0.source] != nil }
    let modelList = unpricedModels.isEmpty
      ? "I do not know which models need a price. Find the models under the Portkey provider in each config below and ask me about each one."
      : shownAgents.map { agent in
        "- \(agent.name): " + unpricedModels[agent.source, default: []].map { "`\($0)`" }.joined(separator: ", ")
      }.joined(separator: "\n")
    return ([introduction, "## Models without a price\n\n\(modelList)"] + shownAgents.map(\.section) + [check])
      .joined(separator: "\n\n") + "\n"
  }

  private static let introduction = """
    Configure my AI agents so that each Portkey message in my sessions stores a correct USD cost. Copilot Runway reads that cost from the session files to show Portkey spend. Portkey has no price API, so each agent needs the price of each model in its own config. Without a price, the agent stores a cost of 0 and Copilot Runway shows the request as unpriced.

    ## Rules

    - Before you save any change, show me the diff and wait for my approval.
    - Never print, log, copy or echo an API key. Do not `cat` a key file. When you show a config file, replace each key value with `REDACTED`.
    - Back up each file before you change it: `cp <file> <file>.bak-portkey-pricing-$(date +%Y%m%d-%H%M%S)`. If that backup file already exists, stop and ask me.
    - Merge the changes into my existing files. Do not remove other providers, models or settings.
    - Do not change the base URL, headers or key of a provider that already works. Change only the `cost` blocks, plus a provider id rename that I approve, with the matching `<provider>/<model id>` strings named in that agent's section below.
    - If a model already has a cost above 0, tell me and do not change it.
    - If something below does not match what you find, stop and ask me. Do not guess.

    ## Prices

    - Ask me for the price of each model in USD per 1 million tokens: input, output, cache read and cache write.
    - You can tell me where to look, for example the Portkey model catalog or the pricing page of the model provider.
    - Do not search the web or fill in a price yourself, unless I explicitly ask you to. If I ask, show the source URL next to each price.
    - Before you write, show me a table of each model and its four prices, and wait for my confirmation.
    """

  private static let piSection = """
    ## Pi

    - Config: `~/.pi/agent/models.json`. Pi reads it when it starts.
    - Find the provider in `providers` whose `baseUrl` points to my Portkey gateway, for example `<your.portkey.gateway.com>`. Copilot Runway counts a message as Portkey only when the provider id contains `portkey` (any letter case). If it does not, ask me before you rename it. A rename also changes the `<provider>/<model id>` strings in `~/.pi/agent/settings.json`, and you must update those too.
    - Add a `cost` block to each model in the `models` list of that provider:

      ```json
      { "id": "<model id>", "cost": { "input": <input>, "output": <output>, "cacheRead": <cache read>, "cacheWrite": <cache write> } }
      ```
    """

  private static let openCodeSection = """
    ## OpenCode

    - Config: `~/.config/opencode/opencode.json`. OpenCode reads it when it starts.
    - Find the provider in `providers` whose `settings.baseURL` points to my Portkey gateway, for example `<your.portkey.gateway.com>`. Its id must contain `portkey`, for example `portkey-openai-compatible`. If it does not, ask me before you rename it. A rename also changes the `<provider>/<model id>` strings in the `model` and `small_model` keys of that file, and you must update those too.
    - Add a `cost` object to each model under `providers.<provider id>.models`:

      ```json
      "<model id>": { "cost": { "input": <input>, "output": <output>, "cache": { "read": <cache read>, "write": <cache write> } } }
      ```
    """

  private static let ompSection = """
    ## omp

    - Config: `~/.omp/agent/models.yml` (YAML). omp is a Pi fork and uses the same `cost` keys as Pi.
    - Copilot Runway has not tested this file end to end. If the file is missing, or the Portkey provider does not look like this example, stop and ask me.
    - Find the provider whose `baseUrl` points to my Portkey gateway. Its id must contain `portkey` (any letter case). If it does not, ask me before you rename it. A rename also changes each `<provider>/<model id>` string in the omp config files under `~/.omp/agent/`, and you must update those too.

      ```yaml
      providers:
        portkey:
          baseUrl: <your.portkey.gateway.com>
          models:
            - id: <model id>
              cost: { input: <input>, output: <output>, cacheRead: <cache read>, cacheWrite: <cache write> }
      ```
    """

  private static let check = """
    ## Check

    1. Check that each changed JSON file is valid: `python3 -m json.tool <file> > /dev/null`.
    2. Check that each changed YAML file is valid: `ruby -ryaml -e 'YAML.parse_file(ARGV[0])' <file>`.
    3. Tell me to quit and start each changed agent again, then send one short message with a Portkey model.
    4. In Copilot Runway, the new request shows a USD amount. Older requests stay unpriced, because agents do not recalculate old messages.
    """
}
