-- Portkey rows for the session_message table of opencode/opencode.sql. Run after it, into the same database.
INSERT INTO session_message VALUES ('msg_pk_user', 'ses_portkey', 'user', 1, 1791190740000, 1791190740000,
  '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_pk_deepseek', 'ses_portkey', 'assistant', 2, 1791190800000, 1791190800000,
  '{"model":{"id":"@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017","providerID":"portkey-openai-compatible"},"cost":0.01,"tokens":{"input":1000,"output":200,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_pk_glm', 'ses_portkey', 'assistant', 3, 1791191100000, 1791191100000,
  '{"model":{"id":"@fireworks-ai-global/accounts/fireworks/models/glm-5p3-flash","providerID":"portkey-openai-compatible"},"cost":0.001,"tokens":{"input":100,"output":20,"reasoning":0,"cache":{"read":0,"write":0}}}');
