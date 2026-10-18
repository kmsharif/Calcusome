create table public.history_entries (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  device_id   text not null,
  expression  text not null,
  result      text not null,
  label       text,
  pinned      boolean not null default false,
  tape_id     uuid,
  created_at  timestamptz not null,
  updated_at  timestamptz not null,
  deleted_at  timestamptz,
  synced_at   timestamptz not null default clock_timestamp(),
  constraint expression_len check (char_length(expression) <= 1000),
  constraint result_len check (char_length(result) <= 200),
  constraint label_len check (char_length(label) <= 200),
  constraint device_id_len check (char_length(device_id) <= 64)
);

create index history_entries_user_synced_idx on public.history_entries (user_id, synced_at);

revoke all on public.history_entries from anon;
revoke delete, truncate, trigger, references on public.history_entries from authenticated;
grant select, insert, update on public.history_entries to authenticated;

alter table public.history_entries enable row level security;

create policy history_select on public.history_entries for select
  using ((select auth.uid()) = user_id);
create policy history_insert on public.history_entries for insert
  with check ((select auth.uid()) = user_id);
create policy history_update on public.history_entries for update
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

alter publication supabase_realtime add table public.history_entries;

-- Merge rule (the Swift client must agree exactly): strictly newer updated_at wins, tie keeps the
-- existing row; deleted_at is the earlier non-null of the two; identity columns never change.
create function public.history_merge() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' then
    new.user_id := old.user_id; new.device_id := old.device_id; new.created_at := old.created_at;
    new.deleted_at := least(old.deleted_at, new.deleted_at);  -- least() skips nulls
    if new.updated_at <= old.updated_at then
      if new.deleted_at is not distinct from old.deleted_at then
        return null;  -- stale edit, nothing to take: skip the row (no WAL write, no Realtime event)
      end if;
      -- stale edit carrying an earlier tombstone: keep the newer content, take the tombstone
      new.expression := old.expression; new.result := old.result; new.label := old.label;
      new.pinned := old.pinned; new.tape_id := old.tape_id; new.updated_at := old.updated_at;
    end if;
  end if;
  new.synced_at := clock_timestamp();
  return new;
end $$;

create trigger history_merge before insert or update on public.history_entries
  for each row execute function public.history_merge();

create function public.delete_my_account() returns void
  language sql security definer set search_path = ''
  as $$ delete from auth.users where id = auth.uid(); $$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
