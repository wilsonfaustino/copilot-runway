CREATE TABLE session_message (
  id text PRIMARY KEY,
  session_id text NOT NULL,
  type text NOT NULL,
  seq integer NOT NULL,
  time_created integer NOT NULL,
  time_updated integer NOT NULL,
  data text NOT NULL
);
INSERT INTO session_message VALUES ('msg_ses_a_1', 'ses_a', 'user', 1, 1791334800000, 1791334800000,
  '{"time":{"created":1791334800000},"text":"Synthetic prompt.","files":[],"agents":[]}');
INSERT INTO session_message VALUES ('msg_ses_a_2', 'ses_a', 'assistant', 2, 1791334801000, 1791334801000,
  '{"time":{"created":1791334801000},"agent":"plan","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_1","name":"read","executed":true,"state":{"status":"completed","input":{"path":"/p/a.swift"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"finish":"stop","cost":0,"tokens":{"input":100,"output":10,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_ses_a_3', 'ses_a', 'user', 3, 1791338400000, 1791338400000,
  '{"time":{"created":1791338400000},"text":"Synthetic prompt.","files":[],"agents":[]}');
INSERT INTO session_message VALUES ('msg_ses_a_4', 'ses_a', 'assistant', 4, 1791338401000, 1791338401000,
  '{"time":{"created":1791338401000},"agent":"plan","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"content":[{"type":"text","text":"Synthetic answer."}],"finish":"stop","cost":0,"tokens":{"input":100,"output":100,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_ses_a_5', 'ses_a', 'user', 5, 1791342000000, 1791342000000,
  '{"time":{"created":1791342000000},"text":"Synthetic prompt.","files":[],"agents":[]}');
INSERT INTO session_message VALUES ('msg_ses_a_6', 'ses_a', 'assistant', 6, 1791342001000, 1791342001000,
  '{"time":{"created":1791342001000},"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_2","name":"patch","executed":true,"state":{"status":"completed","input":{"patchText":"*** Begin Patch"},"content":[{"type":"text","text":"Synthetic tool output."}],"metadata":{"files":[{"file":"/p/a.swift"},{"file":"/p/b.swift"}],"truncated":false}},"time":{"created":0}}],"finish":"stop","cost":0,"tokens":{"input":100,"output":10,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_ses_a_7', 'ses_a', 'synthetic', 7, 1791342002000, 1791342002000,
  '{"time":{"created":1791342002000},"text":"Synthetic note."}');
INSERT INTO session_message VALUES ('msg_ses_a_8', 'ses_a', 'assistant', 8, 1791342003000, 1791342003000,
  '{"time":{"created":1791342003000},"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_3","name":"shell","executed":true,"state":{"status":"completed","input":{"command":"swift test","workdir":"/p"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"finish":"stop","cost":0,"tokens":{"input":100,"output":10,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_ses_a_9', 'ses_a', 'assistant', 9, 1791342004000, 1791342004000,
  '{"time":{"created":1791342004000},"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_4","name":"edit","executed":true,"state":{"status":"completed","input":{"filePath":"/p/b.swift","oldString":"","newString":""},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"finish":"stop","cost":0,"tokens":{"input":100,"output":10,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_ses_a_10', 'ses_a', 'user', 10, 1791345600000, 1791345600000,
  '{"time":{"created":1791345600000},"text":"Synthetic prompt.","files":[],"agents":[]}');
INSERT INTO session_message VALUES ('msg_ses_a_11', 'ses_a', 'assistant', 11, 1791345601000, 1791345601000,
  '{"time":{"created":1791345601000},"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_5","name":"glob","executed":true,"state":{"status":"completed","input":{"pattern":"**/*.swift"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}},{"type":"tool","id":"tool_6","name":"webfetch","executed":true,"state":{"status":"completed","input":{"url":"https://example.com"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"finish":"stop","cost":0,"tokens":{"input":100,"output":10,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_ses_b_1', 'ses_b', 'user', 1, 1791349200000, 1791349200000,
  '{"time":{"created":1791349200000},"text":"Synthetic prompt.","files":[],"agents":[]}');
INSERT INTO session_message VALUES ('msg_ses_b_2', 'ses_b', 'agent-switched', 2, 1791349201000, 1791349201000,
  '{"time":{"created":1791349201000},"agent":"build","previous":"plan"}');
INSERT INTO session_message VALUES ('msg_ses_b_3', 'ses_b', 'assistant', 3, 1791349202000, 1791349202000,
  '{"time":{"created":1791349202000},"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_7","name":"shell","executed":true,"state":{"status":"completed","input":{"command":"gh pr view 3 --comments"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"finish":"stop","cost":0,"tokens":{"input":100,"output":10,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_ses_b_4', 'ses_b', 'user', 4, 1791352800000, 1791352800000,
  '{"time":{"created":1791352800000},"text":"Synthetic prompt.","files":[],"agents":[]}');
INSERT INTO session_message VALUES ('msg_ses_b_5', 'ses_b', 'assistant', 5, 1791352801000, 1791352801000,
  '{"time":{"created":1791352801000},"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_8","name":"skill","executed":true,"state":{"status":"completed","input":{"id":"example"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}},{"type":"tool","id":"tool_9","name":"question","executed":true,"state":{"status":"completed","input":{"questions":[]},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"finish":"stop","cost":0,"tokens":{"input":100,"output":50,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_ses_c_1', 'ses_c', 'assistant', 1, 1791356400000, 1791356400000,
  '{"time":{"created":1791356400000},"agent":"general","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_10","name":"patch","executed":true,"state":{"status":"completed","input":{"patchText":"*** Begin Patch"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"finish":"stop","cost":0,"tokens":{"input":100,"output":10,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_ses_c_2', 'ses_c', 'user', 2, 1791360000000, 1791360000000,
  '{"time":{"created":1791360000000},"text":"Synthetic prompt.","files":[],"agents":[]}');
INSERT INTO session_message VALUES ('msg_ses_c_3', 'ses_c', 'assistant', 3, 1791360001000, 1791360001000,
  '{"time":{"created":1791360001000},"agent":"build","model":{"id":"gpt-6-luna","providerID":"openai"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_11","name":"read","executed":true,"state":{"status":"completed","input":{"path":"/p/a.swift"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"finish":"stop","cost":0,"tokens":{"input":100,"output":10,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_ses_c_4', 'ses_c', 'user', 4, 1790762400000, 1790762400000,
  '{"time":{"created":1790762400000},"text":"Synthetic prompt.","files":[],"agents":[]}');
INSERT INTO session_message VALUES ('msg_ses_c_5', 'ses_c', 'assistant', 5, 1790762401000, 1790762401000,
  '{"time":{"created":1790762401000},"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_12","name":"read","executed":true,"state":{"status":"completed","input":{"path":"/p/a.swift"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"finish":"stop","cost":0,"tokens":{"input":100,"output":10,"reasoning":0,"cache":{"read":0,"write":0}}}');
