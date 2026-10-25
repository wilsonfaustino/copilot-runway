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
INSERT INTO project VALUES ('prj_old', '/Users/example/www/acme/runway-app', 'git', NULL, 1767225600000);
INSERT INTO project VALUES ('prj_new', '/Users/example/www/acme/runway-app', 'git', NULL, 1790812800000);
INSERT INTO project VALUES ('prj_api', '/Users/example/www/acme/billing-api', 'git', NULL, 1790812800000);
INSERT INTO project VALUES ('global', '/', NULL, NULL, 1767225600000);
INSERT INTO session_v2 VALUES ('ses_root', 'prj_new', NULL, 'root', '/Users/example/orca/workspaces/runway-app/fix-chart', 'Synthetic title', 'build', 1791194300000);
INSERT INTO session_v2 VALUES ('ses_child', 'prj_new', 'ses_root', 'child', '/Users/example/orca/workspaces/runway-app/fix-chart', 'Synthetic title', 'general', 1791194500000);
INSERT INTO session_v2 VALUES ('ses_old', 'prj_old', NULL, 'old', '/Users/example/www/acme/runway-app', 'Synthetic title', 'build', 1791198000000);
INSERT INTO session_v2 VALUES ('ses_api', 'prj_api', NULL, 'api', '/Users/example/www/acme/billing-api/packages/server', 'Synthetic title', 'build', 1791201600000);
INSERT INTO session_v2 VALUES ('ses_home', 'global', NULL, 'home', '/Users/example', 'Synthetic title', 'build', 1791205200000);
INSERT INTO session_message VALUES ('msg_root_user', 'ses_root', 'user', 1, 1791194400000, 1791194400000, '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_root_answer', 'ses_root', 'assistant', 2, 1791194410000, 1791194410000,
  '{"agent":"build","model":{"id":"gpt-6.1-sol","providerID":"github-copilot"},"tokens":{"input":100,"output":2000,"reasoning":0,"cache":{"read":50000,"write":0}}}');
INSERT INTO session_message VALUES ('msg_child_user', 'ses_child', 'user', 1, 1791194500000, 1791194500000, '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_child_answer', 'ses_child', 'assistant', 2, 1791194510000, 1791194510000,
  '{"agent":"general","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"tokens":{"input":10,"output":300,"reasoning":40,"cache":{"read":30000,"write":0}}}');
INSERT INTO session_message VALUES ('msg_old_answer', 'ses_old', 'assistant', 1, 1791198000000, 1791198000000,
  '{"agent":"build","model":{"id":"gpt-6.1-sol","providerID":"github-copilot"},"tokens":{"input":50,"output":500,"reasoning":0,"cache":{"read":10000,"write":0}}}');
INSERT INTO session_message VALUES ('msg_api_answer', 'ses_api', 'assistant', 1, 1791201600000, 1791201600000,
  '{"agent":"build","model":{"id":"gemini-3.8-flash","providerID":"github-copilot"},"tokens":{"input":40,"output":60,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_home_answer', 'ses_home', 'assistant', 1, 1791205200000, 1791205200000,
  '{"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"tokens":{"input":10,"output":20,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_missing_answer', 'ses_missing', 'assistant', 1, 1791208800000, 1791208800000,
  '{"agent":"build","model":{"id":"gpt-6-luna","providerID":"github-copilot"},"tokens":{"input":10,"output":20,"reasoning":0,"cache":{"read":0,"write":0}}}');
