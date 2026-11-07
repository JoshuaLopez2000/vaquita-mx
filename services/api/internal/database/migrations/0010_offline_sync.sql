CREATE TABLE IF NOT EXISTS offline_sync_groups (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  local_group_id TEXT NOT NULL,
  group_id TEXT NOT NULL REFERENCES expense_groups(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, local_group_id),
  UNIQUE (group_id)
);

CREATE TABLE IF NOT EXISTS offline_sync_members (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  local_group_id TEXT NOT NULL,
  local_member_id TEXT NOT NULL,
  member_id TEXT NOT NULL REFERENCES members(id),
  PRIMARY KEY (user_id, local_group_id, local_member_id),
  FOREIGN KEY (user_id, local_group_id)
    REFERENCES offline_sync_groups(user_id, local_group_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS offline_sync_entries (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  local_group_id TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('expense', 'settlement')),
  local_entity_id TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  PRIMARY KEY (user_id, local_group_id, entity_type, local_entity_id),
  FOREIGN KEY (user_id, local_group_id)
    REFERENCES offline_sync_groups(user_id, local_group_id) ON DELETE CASCADE
);
