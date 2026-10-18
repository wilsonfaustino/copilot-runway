CREATE TABLE session_message (
  id text PRIMARY KEY,
  session_id text NOT NULL,
  type text NOT NULL,
  seq integer NOT NULL,
  time_created integer NOT NULL,
  time_updated integer NOT NULL,
  data text NOT NULL
);
-- One turn across the Oct 1 reset: a plan agent read on Sep 30, then a build agent read on Oct 1.
INSERT INTO session_message VALUES ('msg_user', 'ses_split', 'user', 1, 1790809200000, 1790809200000,
  '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_sep', 'ses_split', 'assistant', 2, 1790809800000, 1790809800000,
  '{"agent":"plan","model":{"id":"gpt-6.1-sol","providerID":"github-copilot"},"tokens":{"input":100,"output":2000,"reasoning":0,"cache":{"read":50000,"write":0}},"content":[{"type":"tool","name":"read","state":{"input":{"path":"/p/a.swift"}}}]}');
INSERT INTO session_message VALUES ('msg_oct', 'ses_split', 'assistant', 3, 1790813400000, 1790813400000,
  '{"agent":"build","model":{"id":"gpt-6.1-sol","providerID":"github-copilot"},"tokens":{"input":200,"output":3000,"reasoning":0,"cache":{"read":60000,"write":0}},"content":[{"type":"tool","name":"read","state":{"input":{"path":"/p/b.swift"}}}]}');
