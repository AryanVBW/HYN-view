-- Shared relayers can belong to more than one owner. The previous unique
-- index on relayer_id alone rejected that shape, which Postgres already allows.
DROP INDEX IF EXISTS relayer_assignments_relayer_id_idx;
CREATE UNIQUE INDEX IF NOT EXISTS relayer_assignments_owner_relayer_idx
  ON relayer_assignments (owner, relayer_id);
