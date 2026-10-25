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
INSERT INTO session_v2 VALUES ('ses_root', 'prj_new', 'root', '/Users/example/www/acme/runway-app', 'Synthetic title', 'build', 1791194300000);
INSERT INTO session_message VALUES ('msg_root', 'ses_root', 'assistant', 1, 1791363600000, 1791363600000,
  '{"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"tokens":{"input":10,"output":300,"reasoning":0,"cache":{"read":1000,"write":0}}}');
