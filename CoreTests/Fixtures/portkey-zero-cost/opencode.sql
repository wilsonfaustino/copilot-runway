-- Portkey rows with a cost of 0 for the session_message table of opencode/opencode.sql. Run after it, into the same
-- database. OpenCode writes cost 0 when it has no price for the model.
INSERT INTO session_message VALUES ('msg_zero_user', 'ses_zero_cost', 'user', 1, 1791190740000, 1791190740000,
  '{"content":[{"type":"text","text":"Synthetic prompt."}]}');
INSERT INTO session_message VALUES ('msg_zero_cost', 'ses_zero_cost', 'assistant', 2, 1791190800000, 1791190800000,
  '{"model":{"id":"@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017","providerID":"portkey-openai-compatible"},"cost":0,"tokens":{"input":1000,"output":200,"reasoning":0,"cache":{"read":0,"write":0}}}');
INSERT INTO session_message VALUES ('msg_zero_priced', 'ses_zero_cost', 'assistant', 3, 1791191100000, 1791191100000,
  '{"model":{"id":"@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017","providerID":"portkey-openai-compatible"},"cost":0.01,"tokens":{"input":1000,"output":200,"reasoning":0,"cache":{"read":0,"write":0}}}');
