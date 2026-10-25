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
CREATE TABLE session_message (
  id text PRIMARY KEY,
  session_id text NOT NULL,
  type text NOT NULL,
  seq integer NOT NULL,
  time_created integer NOT NULL,
  time_updated integer NOT NULL,
  data text NOT NULL
);
INSERT INTO project VALUES ('prj_new', '/Users/example/www/acme/runway-app', 'git', NULL, 1790812800000);
INSERT INTO session_v2 VALUES ('ses_root_a', 'prj_new', NULL, 'ses_root_a', '/Users/example/www/acme/runway-app', 'Synthetic title', 'build', 1791194300000);
INSERT INTO session_v2 VALUES ('ses_child_a', 'prj_new', 'ses_root_a', 'ses_child_a', '/Users/example/www/acme/runway-app', 'Synthetic title', 'build', 1791194300000);
INSERT INTO session_v2 VALUES ('ses_grand_a', 'prj_new', 'ses_child_a', 'ses_grand_a', '/Users/example/www/acme/runway-app', 'Synthetic title', 'build', 1791194300000);
INSERT INTO session_v2 VALUES ('ses_root_b', 'prj_new', NULL, 'ses_root_b', '/Users/example/www/acme/runway-app', 'Synthetic title', 'build', 1791194300000);
INSERT INTO session_v2 VALUES ('ses_child_b', 'prj_new', 'ses_root_b', 'ses_child_b', '/Users/example/www/acme/runway-app', 'Synthetic title', 'build', 1791194300000);
INSERT INTO session_v2 VALUES ('ses_grand_b', 'prj_new', 'ses_child_b', 'ses_grand_b', '/Users/example/www/acme/runway-app', 'Synthetic title', 'build', 1791194300000);
INSERT INTO session_message VALUES ('msg_root_a', 'ses_root_a', 'assistant', 1, 1791363600000, 1791363600000,
  '{"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"tokens":{"input":10,"output":300,"reasoning":0,"cache":{"read":1000,"write":0}}}');
INSERT INTO session_message VALUES ('msg_grand_a', 'ses_grand_a', 'assistant', 1, 1791363660000, 1791363660000,
  '{"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"tokens":{"input":10,"output":300,"reasoning":0,"cache":{"read":1000,"write":0}}}');
INSERT INTO session_message VALUES ('msg_root_b', 'ses_root_b', 'assistant', 1, 1791363720000, 1791363720000,
  '{"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"tokens":{"input":10,"output":300,"reasoning":0,"cache":{"read":1000,"write":0}}}');
INSERT INTO session_message VALUES ('msg_child_b', 'ses_child_b', 'assistant', 1, 1789894800000, 1789894800000,
  '{"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"tokens":{"input":10,"output":300,"reasoning":0,"cache":{"read":1000,"write":0}}}');
INSERT INTO session_message VALUES ('msg_grand_b', 'ses_grand_b', 'assistant', 1, 1791363780000, 1791363780000,
  '{"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"tokens":{"input":10,"output":300,"reasoning":0,"cache":{"read":1000,"write":0}}}');
