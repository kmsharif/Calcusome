begin;
select plan(22);

insert into auth.users (id, instance_id, aud, role, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@test.dev'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@test.dev');

-- act as A
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}';

select lives_ok($$
  insert into public.history_entries (id, device_id, expression, result, label, created_at, updated_at)
  values ('11111111-1111-1111-1111-111111111111', 'dev-1', '1+1', '2', 'first',
          '2026-01-01 00:00:00+00', '2026-01-01 00:00:10+00')
$$, 'A inserts own row');

select throws_ok($$
  insert into public.history_entries (id, user_id, device_id, expression, result, created_at, updated_at)
  values ('22222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'dev-1', '2+2', '4',
          now(), now())
$$, '42501', null, 'A cannot insert as B');

-- B sees nothing
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}';
select is((select count(*) from public.history_entries), 0::bigint, 'B sees none of A''s rows');

-- back to A
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}';
select set_config('t.synced', (select synced_at::text from public.history_entries), true);

-- older update ignored
update public.history_entries
   set label = 'stale', updated_at = '2026-01-01 00:00:09+00'
 where id = '11111111-1111-1111-1111-111111111111';
select is((select label from public.history_entries), 'first', 'older update ignored: label unchanged');
select is((select synced_at::text from public.history_entries), current_setting('t.synced'),
          'older update ignored: synced_at unchanged');

-- newer update applied
update public.history_entries
   set label = 'second', updated_at = '2026-01-01 00:00:20+00'
 where id = '11111111-1111-1111-1111-111111111111';
select is((select label from public.history_entries), 'second', 'newer update applied: label changed');
select ok((select synced_at > current_setting('t.synced')::timestamptz from public.history_entries),
          'newer update applied: synced_at increased');

-- older tombstone still deletes
update public.history_entries
   set label = 'ignored', deleted_at = '2026-01-01 00:00:15+00', updated_at = '2026-01-01 00:00:15+00'
 where id = '11111111-1111-1111-1111-111111111111';
select is((select deleted_at::text from public.history_entries), '2026-01-01 00:00:15+00',
          'older tombstone still deletes: deleted_at set');
select ok((select label = 'second' and updated_at = '2026-01-01 00:00:20+00' from public.history_entries),
          'older tombstone keeps newer label and updated_at');

-- tombstone is sticky
update public.history_entries
   set deleted_at = null, updated_at = '2026-01-01 00:00:30+00'
 where id = '11111111-1111-1111-1111-111111111111';
select isnt((select deleted_at from public.history_entries), null, 'tombstone is sticky');

-- identity columns immutable (update carries a NEWER updated_at so the trigger does not skip it)
update public.history_entries
   set device_id = 'dev-2', created_at = '2030-01-01 00:00:00+00',
       user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', updated_at = '2026-01-01 00:00:40+00'
 where id = '11111111-1111-1111-1111-111111111111';
select ok((select updated_at = '2026-01-01 00:00:40+00'
              and device_id = 'dev-1'
              and created_at = '2026-01-01 00:00:00+00'
              and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
           from public.history_entries),
          'identity columns immutable');

-- id is pinned too: a newer update that sets a different id keeps the original row
update public.history_entries
   set id = '55555555-5555-5555-5555-555555555555', updated_at = '2026-01-01 00:00:45+00'
 where id = '11111111-1111-1111-1111-111111111111';
select ok((select count(*) = 1 and bool_and(id = '11111111-1111-1111-1111-111111111111' and updated_at = '2026-01-01 00:00:45+00')
           from public.history_entries),
          'id immutable');

-- long expression rejected
select throws_ok($$
  insert into public.history_entries (id, device_id, expression, result, created_at, updated_at)
  values ('33333333-3333-3333-3333-333333333333', 'dev-1', repeat('1', 1001), '1', now(), now())
$$, '23514', null, 'long expression rejected');

-- stale incoming tombstone older than the stored tombstone: earlier deleted_at wins
insert into public.history_entries (id, device_id, expression, result, label, created_at, updated_at, deleted_at)
values ('44444444-4444-4444-4444-444444444444', 'dev-1', '3+3', '6', 'kept',
        '2026-01-01 00:00:00+00', '2026-01-01 00:00:10+00', '2026-01-01 00:00:50+00');
update public.history_entries
   set label = 'stale', updated_at = '2026-01-01 00:00:05+00', deleted_at = '2026-01-01 00:00:40+00'
 where id = '44444444-4444-4444-4444-444444444444';
select ok((select deleted_at = '2026-01-01 00:00:40+00'::timestamptz from public.history_entries
            where id = '44444444-4444-4444-4444-444444444444'),
          'stale earlier tombstone: deleted_at becomes the earlier value');
select ok((select label = 'kept' and updated_at = '2026-01-01 00:00:10+00'::timestamptz from public.history_entries
            where id = '44444444-4444-4444-4444-444444444444'),
          'stale earlier tombstone: label and updated_at unchanged');
-- stale incoming tombstone later than the stored one is ignored
update public.history_entries
   set updated_at = '2026-01-01 00:00:05+00', deleted_at = '2026-01-01 00:00:45+00'
 where id = '44444444-4444-4444-4444-444444444444';
select ok((select deleted_at = '2026-01-01 00:00:40+00'::timestamptz from public.history_entries
            where id = '44444444-4444-4444-4444-444444444444'),
          'stale later tombstone ignored');

-- authenticated cannot hard-delete rows
select throws_ok($$ delete from public.history_entries where id = '11111111-1111-1111-1111-111111111111' $$,
                 '42501', null, 'authenticated DELETE denied');
select is((select count(*) from public.history_entries where id = '11111111-1111-1111-1111-111111111111'), 1::bigint,
          'row still exists after denied DELETE');

-- anon cannot delete accounts
set local role anon;
set local request.jwt.claims = '{}';
select throws_ok($$ select public.delete_my_account() $$, '42501', null, 'anon cannot delete accounts');

select throws_ok($$ select count(*) from public.history_entries $$, '42501', null, 'anon has no table access');

-- delete_my_account removes user and rows
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}';
select public.delete_my_account();
reset role;
select is((select count(*) from auth.users where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 0::bigint,
          'delete_my_account removes user');
select is((select count(*) from public.history_entries where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 0::bigint,
          'delete_my_account removes rows');

select * from finish();
rollback;
