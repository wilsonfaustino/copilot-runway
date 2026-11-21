-- A Portkey turn that starts at 23:00 UTC on 2026-10-10 with an edit and goes on after 00:00 UTC with a read, then a
-- Portkey-only turn at 01:00 UTC on 2026-10-11 that runs the plan agent with no tools.
CREATE TABLE session_message (
  id text PRIMARY KEY,
  session_id text NOT NULL,
  type text NOT NULL,
  seq integer NOT NULL,
  time_created integer NOT NULL,
  time_updated integer NOT NULL,
  data text NOT NULL
);
INSERT INTO session_message VALUES ('msg_split_user_1', 'ses_portkey_split', 'user', 1, 1791673200000, 1791673200000,
  '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_split_edit', 'ses_portkey_split', 'assistant', 2, 1791673201000, 1791673201000,
  '{"time":{"created":1791673201000},"agent":"build","model":{"id":"@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017","providerID":"portkey-openai-compatible"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_s1","name":"edit","executed":true,"state":{"status":"completed","input":{"filePath":"/p/a.swift"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"tokens":{"input":1000,"output":200,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0.01}');
INSERT INTO session_message VALUES ('msg_split_read', 'ses_portkey_split', 'assistant', 3, 1791676801000, 1791676801000,
  '{"time":{"created":1791676801000},"agent":"build","model":{"id":"@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017","providerID":"portkey-openai-compatible"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_s2","name":"read","executed":true,"state":{"status":"completed","input":{"filePath":"/p/a.swift"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"tokens":{"input":1000,"output":200,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0.01}');
INSERT INTO session_message VALUES ('msg_split_user_2', 'ses_portkey_split', 'user', 4, 1791680400000, 1791680400000,
  '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_split_plan', 'ses_portkey_split', 'assistant', 5, 1791680401000, 1791680401000,
  '{"time":{"created":1791680401000},"agent":"plan","model":{"id":"@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017","providerID":"portkey-openai-compatible"},"content":[{"type":"text","text":"Synthetic answer."}],"tokens":{"input":1000,"output":200,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0.01}');
