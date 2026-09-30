ALTER TABLE group_members
  ADD COLUMN role TEXT NOT NULL DEFAULT 'member';

UPDATE group_members AS membership
SET role = 'owner'
FROM expense_groups AS expense_group
WHERE membership.group_id = expense_group.id
  AND membership.member_id = expense_group.owner_id;

ALTER TABLE group_members
  ADD CONSTRAINT group_members_role_check
  CHECK (role IN ('owner', 'member'));

CREATE UNIQUE INDEX group_members_one_owner_idx
  ON group_members(group_id)
  WHERE role = 'owner';
