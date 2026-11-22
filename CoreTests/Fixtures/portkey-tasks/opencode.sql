-- Turns at 01:00, 02:00, 03:00 and 04:00 UTC on 2026-10-10, as in pi.jsonl: a Portkey edit, a Copilot read with a
-- Portkey grep, a Portkey answer with no tools, and an unpriced Portkey gh pr view.
CREATE TABLE project (
  id text PRIMARY KEY,
  worktree text NOT NULL,
  vcs text,
  name text,
  time_created integer NOT NULL
);
CREATE TABLE session_v2 (
  id text PRIMARY KEY,
  project_id text NOT NULL,
  parent_id text,
  slug text NOT NULL,
  directory text NOT NULL,
  title text NOT NULL,
  agent text,
  time_created integer NOT NULL
);
INSERT INTO project VALUES ('prj_new', '/Users/example/www/acme/runway-app', 'git', NULL, 1790812800000);
INSERT INTO session_v2 VALUES ('ses_portkey_tasks', 'prj_new', NULL, 'portkey', '/Users/example/orca/workspaces/runway-app/fix-chart', 'Synthetic title', 'build', 1791594000000);
CREATE TABLE session_message (
  id text PRIMARY KEY,
  session_id text NOT NULL,
  type text NOT NULL,
  seq integer NOT NULL,
  time_created integer NOT NULL,
  time_updated integer NOT NULL,
  data text NOT NULL
);
INSERT INTO session_message VALUES ('msg_pkt_user_1', 'ses_portkey_tasks', 'user', 1, 1791594000000, 1791594000000,
  '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_pkt_edit', 'ses_portkey_tasks', 'assistant', 2, 1791594001000, 1791594001000,
  '{"time":{"created":1791594001000},"agent":"build","model":{"id":"@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017","providerID":"portkey-openai-compatible"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_1","name":"edit","executed":true,"state":{"status":"completed","input":{"filePath":"/p/a.swift"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"tokens":{"input":1000,"output":200,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0.02}');
INSERT INTO session_message VALUES ('msg_pkt_user_2', 'ses_portkey_tasks', 'user', 3, 1791597600000, 1791597600000,
  '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_pkt_copilot_read', 'ses_portkey_tasks', 'assistant', 4, 1791597601000, 1791597601000,
  '{"time":{"created":1791597601000},"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_2","name":"read","executed":true,"state":{"status":"completed","input":{"filePath":"/p/a.swift"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"tokens":{"input":1000,"output":200,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0}');
INSERT INTO session_message VALUES ('msg_pkt_grep', 'ses_portkey_tasks', 'assistant', 5, 1791597602000, 1791597602000,
  '{"time":{"created":1791597602000},"agent":"build","model":{"id":"@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017","providerID":"portkey-openai-compatible"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_3","name":"grep","executed":true,"state":{"status":"completed","input":{"pattern":"Runway","path":"/p"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"tokens":{"input":1000,"output":200,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0.01}');
INSERT INTO session_message VALUES ('msg_pkt_user_3', 'ses_portkey_tasks', 'user', 6, 1791601200000, 1791601200000,
  '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_pkt_no_tools', 'ses_portkey_tasks', 'assistant', 7, 1791601201000, 1791601201000,
  '{"time":{"created":1791601201000},"agent":"build","model":{"id":"@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017","providerID":"portkey-openai-compatible"},"content":[{"type":"text","text":"Synthetic answer."}],"tokens":{"input":1000,"output":200,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0.005}');
INSERT INTO session_message VALUES ('msg_pkt_user_4', 'ses_portkey_tasks', 'user', 8, 1791604800000, 1791604800000,
  '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_pkt_review', 'ses_portkey_tasks', 'assistant', 9, 1791604801000, 1791604801000,
  '{"time":{"created":1791604801000},"agent":"build","model":{"id":"@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017","providerID":"portkey-openai-compatible"},"content":[{"type":"text","text":"Synthetic answer."},{"type":"tool","id":"tool_4","name":"shell","executed":true,"state":{"status":"completed","input":{"command":"gh pr view 3"},"content":[{"type":"text","text":"Synthetic tool output."}]},"time":{"created":0}}],"tokens":{"input":1000,"output":200,"reasoning":0,"cache":{"read":0,"write":0}}}');
