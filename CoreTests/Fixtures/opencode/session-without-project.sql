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
CREATE TABLE session_message (
  id text PRIMARY KEY,
  session_id text NOT NULL,
  type text NOT NULL,
  seq integer NOT NULL,
  time_created integer NOT NULL,
  time_updated integer NOT NULL,
  data text NOT NULL
);
INSERT INTO session_v2 VALUES ('ses_root', 'prj_new', NULL, 'ses_root', '/Users/example/www/acme/runway-app', 'Synthetic title', 'build', 1791194300000);
INSERT INTO session_v2 VALUES ('ses_child', 'prj_new', 'ses_root', 'ses_child', '/Users/example/www/acme/runway-app', 'Synthetic title', 'build', 1791194300000);
INSERT INTO session_message VALUES ('msg_root', 'ses_root', 'assistant', 1, 1791363600000, 1791363600000,
  '{"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"tokens":{"input":10,"output":300,"reasoning":0,"cache":{"read":1000,"write":0}}}');
INSERT INTO session_message VALUES ('msg_child', 'ses_child', 'assistant', 1, 1791363660000, 1791363660000,
  '{"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"tokens":{"input":10,"output":300,"reasoning":0,"cache":{"read":1000,"write":0}}}');
