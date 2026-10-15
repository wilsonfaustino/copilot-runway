CREATE TABLE message (
  id text PRIMARY KEY,
  session_id text NOT NULL,
  time_created integer NOT NULL,
  time_updated integer NOT NULL,
  data text NOT NULL
);
CREATE TABLE session_message (
  id text PRIMARY KEY,
  session_id text NOT NULL,
  type text NOT NULL,
  seq integer NOT NULL,
  time_created integer NOT NULL,
  time_updated integer NOT NULL,
  data text NOT NULL
);
INSERT INTO message VALUES ('msg_legacy', 'ses_1', 1791194400000, 1791194400000,
  '{"role":"assistant","providerID":"github-copilot","modelID":"gpt-6.1-sol","tokens":{"input":100,"output":2000,"reasoning":500,"cache":{"read":50000,"write":0}},"time":{"created":1791194400000}}');
INSERT INTO message VALUES ('msg_legacy_user', 'ses_1', 1791194390000, 1791194390000,
  '{"role":"user","time":{"created":1791194390000}}');
INSERT INTO session_message VALUES ('msg_legacy', 'ses_1', 'assistant', 1, 1791194400000, 1791194400000,
  '{"model":{"id":"gpt-6.1-sol","providerID":"github-copilot"},"tokens":{"input":100,"output":2000,"reasoning":500,"cache":{"read":50000,"write":0}},"time":{"created":1791194400000}}');
INSERT INTO session_message VALUES ('msg_luna', 'ses_1', 'assistant', 2, 1791198000000, 1791198000000,
  '{"model":{"id":"gpt-6-luna","providerID":"github-copilot","variant":"max"},"tokens":{"input":10,"output":300,"reasoning":40,"cache":{"read":300000,"write":0}},"time":{"created":1791198000000},"content":[{"type":"text","text":"Synthetic answer."}]}');
INSERT INTO session_message VALUES ('msg_openai', 'ses_1', 'assistant', 3, 1791201600000, 1791201600000,
  '{"model":{"id":"gpt-6.1-sol","providerID":"openai"},"tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":1,"write":0}}}');
INSERT INTO session_message VALUES ('msg_before_cycle', 'ses_1', 'assistant', 4, 1790769600000, 1790769600000,
  '{"model":{"id":"gpt-6.1-sol","providerID":"github-copilot"},"tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":1,"write":0}}}');
INSERT INTO session_message VALUES ('msg_user', 'ses_1', 'user', 5, 1791205200000, 1791205200000,
  '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_error', 'ses_1', 'assistant', 6, 1791208800000, 1791208800000,
  '{"model":{"id":"gpt-6.1-sol","providerID":"github-copilot"},"error":{"name":"SyntheticError"}}');
